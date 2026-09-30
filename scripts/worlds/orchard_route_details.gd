extends RefCounted
## Local road furniture; all walking overlays use the final sampled terrain.
## Real shallow stair treads share
## one mesh for display/collision and the same rectangles for floor queries.
const Textures := preload("res://scripts/worlds/orchard_main_terrain.gd")
var _landscape: Node3D
var _config: Dictionary = {}
var _spec: Dictionary = {}
var _routes: Array[Dictionary] = []
var _batches: Dictionary = {}
var _steps: Array[Dictionary] = []
var _city_footprints: Array[Rect2] = []
var _root: Node3D
var _stone: StandardMaterial3D
var _lamp: ArrayMesh
var _block: BoxMesh
var _lamp_positions: Array[Vector2] = []
var _shoulder_count := 0
var _flight_count := 0
var _max_stair_lift := 0.0


func install(world: Node3D, landscape: Node3D) -> void:
	if world.has_meta("orchard_route_details"): return
	_landscape = landscape
	_config = landscape.settings
	_spec = _config.get("route_details", {})
	if not bool(_spec.get("enabled", false)): return
	_root = Node3D.new()
	_root.name = "MountainRouteDetails"
	world.add_child(_root)
	_add_route(_config.get("sampled_mountain_route", _config.mountain_route))
	for spur in _config.get("sampled_terrace_spurs", []):
		_add_route(spur.points)
	if _routes.is_empty(): return
	for node_name in ["BlenderSkySanctuary", "BlenderHarborCity"]:
		var city := world.get_node_or_null(node_name)
		if city != null: _collect_city_footprints(city)
	_stone = _material(Color("b8beb3"), "orchard_stone_generated.png")
	_stone.vertex_color_use_as_albedo = true
	_block = BoxMesh.new()
	_block.size = Vector3.ONE
	_block.material = _stone
	_lamp = _make_lamp_mesh()
	var main: Dictionary = _routes[0]
	# The trail shader provides one continuous surface; isolated stone rectangles
	# read as stray paving tiles on this dirt mountain road.
	# The continuous sampled road is already walkable. Omit isolated shallow
	# stair overlays, which read as rectangular stone patches on gentle grades.
	var main_lamps: Array = _spec.get("lamp_main_fractions", [0.11, 0.23, 0.36, 0.48, 0.60, 0.73, 0.84])
	for i in main_lamps.size():
		_place_lamp(main, float(main.length) * float(main_lamps[i]), 1.0 if i % 2 == 0 else -1.0)
	var spur_lamps: Array = _spec.get("lamp_spur_fractions", [[0.34, 0.64], [0.42], [0.31, 0.57]])
	for i in mini(spur_lamps.size(), _routes.size() - 1):
		for fraction in spur_lamps[i]:
			_place_lamp(_routes[i + 1], float(_routes[i + 1].length) * float(fraction), -1.0 if i % 2 == 0 else 1.0)
	for section in [[0.20, 1.0], [0.40, -1.0], [0.56, 1.0], [0.76, -1.0]]:
		_shoulder_section(main, float(main.length) * float(section[0]), float(section[1]), 22.0)
	for i in range(1, _routes.size()):
		_shoulder_section(_routes[i], float(_routes[i].length) * 0.43, -1.0, 15.0)
	_flush_batches()
	preload("res://scripts/worlds/orchard_road_fences.gd").new().install(world, landscape, self)
	world.set_meta("orchard_route_details", {
		"revision": _spec.get("revision", "orchard_route_details_v9"),
		"lamps": _lamp_positions.size(), "inlaid_stones": 0,
		"shoulder_stones": _shoulder_count, "stair_runs": _flight_count,
		"stair_treads": _steps.size(), "max_stair_lift": _max_stair_lift,
		"dynamic_lights": 0, "spatial_batches": _batches.size()
	})


func surface_height(at: Vector3) -> float:
	var point := Vector2(at.x, at.z)
	var result := -INF
	for step in _steps:
		var local: Vector2 = point - Vector2(step.center)
		if absf(local.dot(step.tangent)) <= float(step.half_depth) + 0.001 and absf(local.dot(step.side)) <= float(step.half_width) + 0.001:
			result = maxf(result, float(step.height))
	return result


func _add_route(raw: Array) -> void:
	if raw.size() < 2: return
	var points: Array[Vector2] = []
	var cumulative := PackedFloat32Array([0.0])
	var length := 0.0
	for value in raw:
		var point := Vector2(float(value[0]), float(value[2]))
		if not points.is_empty():
			length += points.back().distance_to(point)
			cumulative.append(length)
		points.append(point)
	_routes.append({"points": points, "along": cumulative, "length": length})


func _at(route: Dictionary, distance: float) -> Vector2:
	var along: PackedFloat32Array = route.along
	var points: Array = route.points
	distance = clampf(distance, 0.0, float(route.length))
	for i in range(1, points.size()):
		if along[i] >= distance:
			return Vector2(points[i - 1]).lerp(points[i], (distance - along[i - 1]) / maxf(along[i] - along[i - 1], 0.001))
	return points.back()


func _tangent(route: Dictionary, distance: float) -> Vector2:
	return (_at(route, distance + 1.0) - _at(route, distance - 1.0)).normalized()


func _protected(at: Vector2, margin: float = 0.0) -> bool:
	if _routes.is_empty(): return true
	var main: Dictionary = _routes[0]
	if at.distance_to(_at(main, 0.0)) < float(_spec.get("protected_harbor_radius", 35.0)) + margin: return true
	if at.distance_to(_at(main, float(main.length))) < float(_spec.get("protected_gate_radius", 55.0)) + margin: return true
	for reservation in _config.get("battle_reservations", []):
		var center: Array = reservation.center
		if at.distance_to(Vector2(center[0], center[2])) < float(reservation.clear_radius) + margin + 2.0: return true
	for footprint in _city_footprints:
		if footprint.grow(margin + 1.0).has_point(at): return true
	return false


func _distance_to_roads(at: Vector2) -> float:
	var closest := INF
	for route in _routes:
		var points: Array = route.points
		for i in range(points.size() - 1):
			var a: Vector2 = points[i]
			var delta: Vector2 = Vector2(points[i + 1]) - a
			var t := clampf((at - a).dot(delta) / maxf(delta.length_squared(), 0.001), 0.0, 1.0)
			closest = minf(closest, at.distance_to(a + delta * t))
	return closest


func _rectangle(center: Vector2, tangent: Vector2, half_depth: float, half_width: float) -> Array[Vector2]:
	var side := Vector2(-tangent.y, tangent.x)
	return [center - tangent * half_depth - side * half_width, center + tangent * half_depth - side * half_width, center + tangent * half_depth + side * half_width, center - tangent * half_depth + side * half_width]


func _clip_left(polygon: Array[Vector2], a: Vector2, b: Vector2) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if polygon.is_empty(): return result
	var previous: Vector2 = polygon.back()
	var previous_side := (b - a).cross(previous - a)
	for point in polygon:
		var side := (b - a).cross(point - a)
		if (side >= -0.00001) != (previous_side >= -0.00001):
			result.append(previous.lerp(point, previous_side / (previous_side - side)))
		if side >= -0.00001: result.append(point)
		previous = point
		previous_side = side
	return result


func _make_stair_run(route: Dictionary, spec: Dictionary) -> void:
	var length := float(spec.get("length", 14.0))
	var count := maxi(2, ceili(length / float(spec.get("tread_depth", 0.65))))
	var depth := length / count
	var half_width := float(spec.get("width", 6.8)) * 0.5
	var along := float(route.length) * float(spec.get("fraction", 0.5))
	var center := _at(route, along)
	var tangent := _tangent(route, along)
	var side := Vector2(-tangent.y, tangent.x)
	var candidates: Array[Dictionary] = []
	var max_lift := float(_spec.get("stair_max_lift", 0.20))
	var previous_height := INF
	for i in count:
		var at := center + tangent * (-length * 0.5 + (i + 0.5) * depth)
		if _protected(at, half_width + 1.0): return
		var corners := _rectangle(at, tangent, depth * 0.5, half_width)
		# Every intersected terrain facet participates, so extrema hidden between
		# the tread's corners cannot poke through the horizontal walking face.
		var limits := _terrain_height_bounds(corners)
		var lowest := limits.x
		var highest := limits.y
		var top := highest + 0.012
		if top - lowest > max_lift: return
		if is_finite(previous_height) and absf(top - previous_height) > 0.18: return
		previous_height = top
		candidates.append({"center": at, "tangent": tangent, "side": side, "half_depth": depth * 0.5, "half_width": half_width, "height": top, "bottom": lowest - 0.08, "lift": top - lowest, "corners": corners})
	if candidates.is_empty(): return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for tread in candidates:
		var corners: Array = tread.corners
		var upper: Array[Vector3] = []
		var lower: Array[Vector3] = []
		for point in corners:
			upper.append(Vector3(point.x, float(tread.height), point.y))
			lower.append(Vector3(point.x, float(tread.bottom), point.y))
		_append_quad(vertices, normals, uvs, upper[0], upper[1], upper[2], upper[3], Vector3.UP)
		for edge in 4:
			var next := (edge + 1) % 4
			var outward := Vector3.UP.cross(lower[next] - lower[edge]).normalized()
			_append_quad(vertices, normals, uvs, lower[edge], lower[next], upper[next], upper[edge], outward)
		_steps.append(tread)
		_max_stair_lift = maxf(_max_stair_lift, float(tread.lift))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _stone)
	var instance := MeshInstance3D.new()
	instance.name = "ShallowStoneSteps_%d" % _flight_count
	instance.mesh = mesh
	_root.add_child(instance)
	instance.create_trimesh_collision()
	_flight_count += 1


func _terrain_height_bounds(polygon: Array[Vector2]) -> Vector2:
	var minimum: Vector2 = polygon[0]
	var maximum := minimum
	for point in polygon:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var start: Vector2 = _landscape.grid_start
	var step: float = _landscape.grid_step
	var first := Vector2i(floori((minimum.x - start.x) / step), floori((minimum.y - start.y) / step))
	var last := Vector2i(floori((maximum.x - start.x) / step), floori((maximum.y - start.y) / step))
	var lowest := INF
	var highest := -INF
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var a := start + Vector2(x, z) * step
			var b := a + Vector2(step, 0.0)
			var c := a + Vector2(0.0, step)
			var d := a + Vector2(step, step)
			for triangle in [[a, b, c], [b, d, c]]:
				var clipped: Array[Vector2] = polygon.duplicate()
				for edge in 3: clipped = _clip_left(clipped, triangle[edge], triangle[(edge + 1) % 3])
				for point in clipped:
					var height: float = _landscape.height_at(point)
					lowest = minf(lowest, height)
					highest = maxf(highest, height)
	return Vector2(lowest, highest)


func _append_quad(vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	for point in [a, b, c, a, c, d]:
		vertices.append(point)
		normals.append(normal)
		uvs.append(Vector2(point.x + point.y * 0.4, point.z) * 0.22)


func _place_lamp(route: Dictionary, distance: float, preferred_side: float) -> void:
	var center := _at(route, distance)
	var tangent := _tangent(route, distance)
	var side := Vector2(-tangent.y, tangent.x)
	for offset in [14.6, -14.6, 16.2, -16.2]:
		var at: Vector2 = center + side * float(offset) * preferred_side
		if _protected(at, 2.0) or _distance_to_roads(at) < 12.8: continue
		var crowded := false
		for placed in _lamp_positions:
			if at.distance_to(placed) < 24.0: crowded = true
		if crowded: continue
		var y: float = _landscape.height_at(at)
		if y < float(_config.sea_level) + 5.0: continue
		var variation := 0.0
		for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			variation = maxf(variation, absf(_landscape.height_at(at + direction) - y))
		if variation > 0.65: continue
		var scale := float(_spec.get("lamp_height", 9.0)) / 9.0
		var base := Vector3(at.x, y - 0.10, at.y)
		_batch("lamp", _lamp, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), base))
		# The two narrow, visible solids are outside every walking core.
		var body := StaticBody3D.new()
		body.name = "RoadLamp_%d" % _lamp_positions.size()
		body.position = base
		for dimensions in [Vector3(0.64, 0.65, 0.325), Vector3(0.15, 6.35, 3.75)]:
			var shape := CylinderShape3D.new()
			shape.radius = dimensions.x * scale
			shape.height = dimensions.y * scale
			var collider := CollisionShape3D.new()
			collider.position.y = dimensions.z * scale
			collider.shape = shape
			body.add_child(collider)
		_root.add_child(body)
		_lamp_positions.append(at)
		return


func _shoulder_section(route: Dictionary, distance: float, direction: float, length: float) -> void:
	for i in floori(length / 2.9):
		var along := distance - length * 0.5 + i * 2.9
		var tangent := _tangent(route, along)
		var side := Vector2(-tangent.y, tangent.x)
		var at := _at(route, along) + side * 12.8 * direction
		if _protected(at, 2.0) or _distance_to_roads(at) < 11.7: continue
		var near_lamp := false
		for lamp in _lamp_positions:
			if lamp.distance_to(at) < 2.4: near_lamp = true
		if near_lamp: continue
		var y: float = _landscape.height_at(at)
		var a: float = _landscape.height_at(at - tangent * 1.2)
		var b: float = _landscape.height_at(at + tangent * 1.2)
		if absf(a - b) > 0.9: continue
		var axis := Vector3(tangent.x, (b - a) / 2.4, tangent.y).normalized()
		var lateral := Vector3(side.x, 0.0, side.y)
		var up := lateral.cross(axis).normalized()
		var basis := Basis(axis, up, lateral).scaled(Vector3(2.55, 0.65, 0.85))
		_batch("shoulder", _block, Transform3D(basis, Vector3(at.x, y + 0.15, at.y)))
		_shoulder_count += 1


func _make_lamp_mesh() -> ArrayMesh:
	var metal := _material(Color("657b78"), "orchard_stone_generated.png")
	var bronze := _material(Color("bd9c66"), "orchard_soil_generated.png")
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ffe4a6")
	glow.roughness = 1.0
	glow.emission_enabled = true
	glow.emission = Color("ffd98b")
	glow.emission_energy_multiplier = 1.1
	var parts: Array[Dictionary] = []
	_add_cylinder(parts, 0.75, 0.65, 0.65, 0.325, _stone)
	_add_cylinder(parts, 0.25, 0.18, 6.15, 3.675, metal)
	_add_cylinder(parts, 0.44, 0.44, 0.18, 6.55, bronze)
	_add_cylinder(parts, 0.63, 0.63, 0.18, 6.84, metal)
	_add_cylinder(parts, 0.52, 0.52, 1.18, 7.5, glow)
	_add_cylinder(parts, 0.65, 0.65, 0.16, 8.15, bronze)
	_add_cylinder(parts, 0.94, 0.05, 0.62, 8.53, metal)
	_add_cylinder(parts, 0.13, 0.0, 0.30, 8.90, bronze)
	for angle in [0.0, PI * 0.5, PI, PI * 1.5]:
		var bar := BoxMesh.new()
		bar.size = Vector3(0.12, 1.32, 0.12)
		parts.append({"mesh": bar, "offset": Vector3(cos(angle) * 0.52, 7.5, sin(angle) * 0.52), "material": metal})
	var mesh := ArrayMesh.new()
	for material in [_stone, metal, bronze, glow]:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for part in parts:
			if part.material != material: continue
			var source: Array = part.mesh.surface_get_arrays(0)
			var base := vertices.size()
			for point in source[Mesh.ARRAY_VERTEX]: vertices.append(point + Vector3(part.offset))
			normals.append_array(source[Mesh.ARRAY_NORMAL])
			uvs.append_array(source[Mesh.ARRAY_TEX_UV])
			for index in source[Mesh.ARRAY_INDEX]: indices.append(base + int(index))
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


func _add_cylinder(parts: Array[Dictionary], bottom: float, top: float, height: float, y: float, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	parts.append({"mesh": mesh, "offset": Vector3(0.0, y, 0.0), "material": material})


func _material(color: Color, texture_name: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = Textures.texture(texture_name)
	material.roughness = 1.0
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material


func _ground(at: Vector2, offset: float = 0.0) -> Vector3:
	return Vector3(at.x, _landscape.height_at(at) + offset, at.y)


func _cell(at: Vector2) -> Vector2i:
	var cell := float(_spec.get("spatial_cell", 112.0))
	return Vector2i(floori(at.x / cell), floori(at.y / cell))


func _batch(kind: String, mesh: Mesh, transform: Transform3D) -> void:
	var cell := _cell(Vector2(transform.origin.x, transform.origin.z))
	var key := "%s_%d_%d" % [kind, cell.x, cell.y]
	if not _batches.has(key): _batches[key] = {"mesh": mesh, "transforms": []}
	_batches[key].transforms.append(transform)


func _flush_batches() -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = batch.mesh
		multimesh.instance_count = batch.transforms.size()
		for i in multimesh.instance_count: multimesh.set_instance_transform(i, batch.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.name = key
		instance.multimesh = multimesh
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = 750.0
		instance.visibility_range_end_margin = 55.0
		_root.add_child(instance)


func _collect_city_footprints(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null and str(node.name).begins_with("C_"):
		var bounds: AABB = node.global_transform * node.mesh.get_aabb()
		_city_footprints.append(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)))
	for child in node.get_children(): _collect_city_footprints(child)
