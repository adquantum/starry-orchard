extends RefCounted
## Imported city collision in unit-scale world space. Decorative foliage is not
## a floor; stair nosings share a continuous, closed support envelope.
const REGION_SIZE := 96.0
const WALKABLE_NORMAL_Y := 0.6156615
var stats: Dictionary = {"source_solids": 0, "tree_trunks": 0, "decorative_skipped": 0, "missing_floors_restored": 0,
	"stair_ramps": 0, "solid_bodies": 0, "floor_bodies": 0, "floor_triangles": 0}
var _root: Node3D
var _city_mask: int
var _solid: Dictionary = {}
var _floor: Dictionary = {}
var _cached_faces: Dictionary = {}
var _nodes: Dictionary = {}

func install(city_root: Node3D, city_mask: int) -> Dictionary:
	_city_mask = city_mask
	_root = Node3D.new()
	_root.name = "SkyRuntimeCollision"
	_root.top_level = true
	city_root.add_child(_root)
	_root.global_transform = Transform3D(Basis.IDENTITY, city_root.global_position)
	_collect(city_root)
	_add_city_joins()
	_build(_solid, 1, "Solid")
	_build(_floor, city_mask, "WalkSurface")
	_cached_faces.clear()
	_solid.clear()
	_floor.clear()
	return stats.duplicate()

func _collect(node: Node) -> void:
	if node == _root:
		return
	if node is MeshInstance3D and node.mesh != null and (String(node.name).begins_with("C_") or _missing_floor(String(node.name)) or node.get_meta("city_walk_surface", false)):
		var mesh_node := node as MeshInstance3D
		var source := String(node.name)
		var owner_name := source.get_slice("__", 0)
		_nodes[owner_name] = mesh_node
		stats.source_solids += 1
		if _missing_floor(source):
			stats.missing_floors_restored += 1
		if source.contains("__SM_VEG_04_Cypress") or source.contains("__SM_VEG_02_PinkCherry") or source.contains("__SM_VEG_03_GoldenTree"):
			_add_trunk(mesh_node, source)
		elif _decoration(source):
			stats.decorative_skipped += 1
		elif (owner_name.begins_with("C_ARRAY_") and owner_name.contains("Stair")) or owner_name.begins_with("C_INST_SideSteps_"):
			_add_stair(mesh_node, owner_name)
		elif owner_name in ["C_SUPPORT_GrandStairWedge", "C_SUPPORT_GrandStair", "C_SUPPORT_EntranceStairWedge"]:
			# The source stair now supplies a single continuous collision envelope.
			# Keeping the overlapping older wedge would add a second contact plane.
			pass
		else:
			_add_mesh(mesh_node, _walk_surface(owner_name, source) or _missing_floor(source) or mesh_node.get_meta("city_walk_surface", false))
	for child in node.get_children():
		if not child is StaticBody3D:
			_collect(child)

func _decoration(source: String) -> bool:
	var upper := source.to_upper()
	for token in ["__SM_VEG_01_", "__SM_VEG_05_", "__SM_VEG_06_", "PETAL", "FLOWER", "SHRUB", "UNDERSTORY", "SHORE_FOAM", "WATER_FPS", "__GUANG_"]:
		if upper.contains(token):
			return true
	return false

func _missing_floor(source: String) -> bool:
	# These authored ground slabs were exported as visual-only V_, although
	# their upper faces are the visible city floor (up to 11m above LAND_).
	var owner_name := source.get_slice("__", 0)
	if not owner_name.begins_with("V_"):
		return false
	if owner_name.begins_with("V_EXP_"):
		return owner_name.ends_with("_Meadow") or owner_name.ends_with("_Terrace") or owner_name.ends_with("_RoundPlaza")
	return owner_name.begins_with("V_TERRACE_Housing_") or owner_name.begins_with("V_TERRACE_Garden_") or owner_name.begins_with("V_SOIL_")

func _walk_surface(owner_name: String, source: String) -> bool:
	for token in ["RAIL", "PARAPET", "FENCE", "POSTS"]:
		if owner_name.to_upper().contains(token):
			return false
	if source.contains("__SM_ARC_04_WaterfallIsland_B"):
		return true
	for prefix in ["C_LAND_", "C_PLATFORM_", "C_PLAZA_", "C_PAVING_", "C_PATH_", "C_BRIDGE_", "C_ABUTMENT_", "C_SOIL_"]:
		if owner_name.begins_with(prefix):
			return true
	if owner_name.begins_with("C_EXP_"):
		return owner_name.ends_with("_Meadow") or owner_name.ends_with("_Terrace") or owner_name.ends_with("_RoundPlaza")
	if owner_name.begins_with("C_ARRAY_"):
		return owner_name.contains("Paving") or owner_name.contains("Stair")
	return owner_name.begins_with("C_POL_East_Academy_Approach_") or owner_name == "C_SUPPORT_EntranceStairWedge"

func _faces(mesh: Mesh) -> PackedVector3Array:
	var key := mesh.get_instance_id()
	if not _cached_faces.has(key):
		_cached_faces[key] = mesh.get_faces()
	return _cached_faces[key]

func _add_mesh(node: MeshInstance3D, walk_surface: bool) -> void:
	var source := _faces(node.mesh)
	var transform := _root.global_transform.affine_inverse() * node.global_transform
	var faces := PackedVector3Array()
	var flip := transform.basis.determinant() < 0.0
	for i in range(0, source.size(), 3):
		var a := transform * source[i]
		var b := transform * source[i + (2 if flip else 1)]
		var c := transform * source[i + (1 if flip else 2)]
		faces.append_array(PackedVector3Array([a, b, c]))
	_queue(transform * node.mesh.get_aabb().get_center(), faces, walk_surface)

func _queue(center: Vector3, faces: PackedVector3Array, walk_surface: bool) -> void:
	var valid := PackedVector3Array()
	var floor_faces := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		var normal := (c - a).cross(b - a)
		if normal.length_squared() < 0.00000001:
			continue
		valid.append_array(PackedVector3Array([a, b, c]))
		if walk_surface and normal.normalized().y >= WALKABLE_NORMAL_Y:
			floor_faces.append_array(PackedVector3Array([a, b, c]))
	var cell := Vector2i(floori(center.x / REGION_SIZE), floori(center.z / REGION_SIZE))
	if not valid.is_empty():
		if not _solid.has(cell):
			_solid[cell] = []
		_solid[cell].append(valid)
	if not floor_faces.is_empty():
		if not _floor.has(cell):
			_floor[cell] = []
		_floor[cell].append(floor_faces)
		stats.floor_triangles += floor_faces.size() / 3

func _build(batches: Dictionary, layer: int, label: String) -> void:
	for cell in batches:
		var faces := PackedVector3Array()
		for batch: PackedVector3Array in batches[cell]:
			faces.append_array(batch)
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = false
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var body := StaticBody3D.new()
		body.name = "Sky%s_%d_%d" % [label, cell.x, cell.y]
		body.collision_layer = layer
		body.collision_mask = 0
		body.add_child(collision)
		_root.add_child(body)
		if layer == _city_mask:
			stats.floor_bodies += 1
		else:
			stats.solid_bodies += 1

func _add_trunk(node: MeshInstance3D, source_name: String) -> void:
	# Dimensions are from these three source meshes, not their crown AABBs.
	# The atlas combines wood and leaves in one surface, so surface filtering
	# cannot separate them. A tapered closed trunk replaces the leaf triangle soup.
	var cypress := source_name.contains("Cypress")
	var radius := 0.20 if cypress else 0.48
	var height := 3.7 if cypress else 1.65
	var transform := _root.global_transform.affine_inverse() * node.global_transform
	var points := PackedVector3Array()
	for ring in range(2):
		for side in range(10):
			var angle := TAU * float(side) / 10.0
			var r := radius * (1.0 if ring == 0 else 0.72)
			points.append(transform * Vector3(cos(angle) * r, float(ring) * height, sin(angle) * r))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var collision := CollisionShape3D.new()
	collision.shape = shape
	var body := StaticBody3D.new()
	body.name = "TreeTrunk_%d" % int(stats.tree_trunks)
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_child(collision)
	_root.add_child(body)
	stats.tree_trunks += 1
	stats.solid_bodies += 1

func _add_stair(node: MeshInstance3D, owner_name: String) -> void:
	var geometry := stair_geometry(node, _root.global_transform, owner_name.begins_with("C_ARRAY_POL_"))
	if geometry.is_empty():
		_add_mesh(node, true)
		return
	var faces: PackedVector3Array = geometry.faces
	if owner_name in ["C_ARRAY_POL_INST_EXP_WestRise_Stair", "C_ARRAY_POL_INST_EXP_EastRise_Stair", "C_ARRAY_POL_INST_EXP_TreeWest_Stair", "C_ARRAY_POL_INST_EXP_TreeEast_Stair"]:
		# Their exported stair hulls overlap the next terrace. Keep the walkable
		# tread envelope but leave out vertical sides that block the join.
		var tops := PackedVector3Array()
		for i in range(0, faces.size(), 3):
			var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
			if normal.y >= WALKABLE_NORMAL_Y:
				tops.append_array(PackedVector3Array([faces[i], faces[i + 1], faces[i + 2]]))
		faces = tops
	_queue(geometry.center, faces, true)
	_add_stair_sides(geometry.sides, node.get_active_material(0))
	stats.stair_ramps += 1

static func stair_geometry(node: MeshInstance3D, reference: Transform3D, along_x: bool) -> Dictionary:
	var axis := 0 if along_x else 2
	var across := 2 if along_x else 0
	var unique: Dictionary = {}
	for vertex in node.mesh.get_faces():
		unique[Vector2(snappedf(vertex[axis], 0.0001), snappedf(vertex.y, 0.0001))] = true
	var points: Array = unique.keys()
	var bounds := node.mesh.get_aabb()
	var y_at_min := -INF
	var y_at_max := -INF
	for point: Vector2 in points:
		if absf(point.x - bounds.position[axis]) < 0.001:
			y_at_min = maxf(y_at_min, point.y)
		if absf(point.x - bounds.end[axis]) < 0.001:
			y_at_max = maxf(y_at_max, point.y)
	# Each flight starts with a raised tread. Extend its bottom nosing into a
	# short visible stone toe at the first tread's base, eliminating that riser.
	if is_finite(y_at_min) and is_finite(y_at_max):
		var low_run := bounds.position[axis] if y_at_min < y_at_max else bounds.end[axis]
		var sign_run := -1.0 if y_at_min < y_at_max else 1.0
		points.append(Vector2(low_run + sign_run * 0.55, bounds.position.y))
	points.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if points.size() < 3:
		return {}
	var hull: Array[Vector2] = []
	for point: Vector2 in points:
		while hull.size() >= 2 and (hull[-1] - hull[-2]).cross(point - hull[-1]) <= 0.0:
			hull.pop_back()
		hull.append(point)
	var lower_count := hull.size()
	for i in range(points.size() - 2, -1, -1):
		var point: Vector2 = points[i]
		while hull.size() > lower_count and (hull[-1] - hull[-2]).cross(point - hull[-1]) <= 0.0:
			hull.pop_back()
		hull.append(point)
	hull.pop_back()
	var transform := reference.affine_inverse() * node.global_transform
	var center := transform * bounds.get_center()
	var faces := PackedVector3Array()
	var support_faces := PackedVector3Array()
	for i in range(hull.size()):
		var j := (i + 1) % hull.size()
		var a := Vector3.ZERO
		var b := Vector3.ZERO
		a[axis] = hull[i].x
		a.y = hull[i].y
		a[across] = bounds.position[across]
		b[axis] = hull[j].x
		b.y = hull[j].y
		b[across] = bounds.position[across]
		var c := b
		var d := a
		c[across] = bounds.end[across]
		d[across] = bounds.end[across]
		var side_center := transform * ((a + b + c + d) * 0.25)
		_triangle(faces, transform * a, transform * b, transform * c, side_center - center)
		_triangle(faces, transform * a, transform * c, transform * d, side_center - center)
		# The toe may share a convex-hull edge with the far end of the flight.
		# Only render its part outside the original tread bounds; rendering the
		# entire edge covered every tread with one giant sloping stone sheet.
		var aa := a
		var bb := b
		var a_out := a[axis] < bounds.position[axis] - 0.001 or a[axis] > bounds.end[axis] + 0.001
		var b_out := b[axis] < bounds.position[axis] - 0.001 or b[axis] > bounds.end[axis] + 0.001
		if a_out or b_out:
			var limit := bounds.position[axis] if minf(a[axis], b[axis]) < bounds.position[axis] else bounds.end[axis]
			if a_out and not b_out:
				bb = a.lerp(b, (limit - a[axis]) / (b[axis] - a[axis]))
			elif b_out and not a_out:
				aa = a.lerp(b, (limit - a[axis]) / (b[axis] - a[axis]))
			var cc := bb
			var dd := aa
			cc[across] = bounds.end[across]
			dd[across] = bounds.end[across]
			_triangle(support_faces, transform * aa, transform * bb, transform * cc, side_center - center)
			_triangle(support_faces, transform * aa, transform * cc, transform * dd, side_center - center)
	for side in range(2):
		var ring := PackedVector3Array()
		for point: Vector2 in hull:
			var v := Vector3.ZERO
			v[axis] = point.x
			v.y = point.y
			v[across] = bounds.position[across] if side == 0 else bounds.end[across]
			ring.append(transform * v)
		for i in range(1, ring.size() - 1):
			_triangle(faces, ring[0], ring[i], ring[i + 1], (ring[0] + ring[i] + ring[i + 1]) / 3.0 - center)
			_triangle(support_faces, ring[0], ring[i], ring[i + 1], (ring[0] + ring[i] + ring[i + 1]) / 3.0 - center)
	return {"faces": faces, "sides": support_faces, "center": center}

func _add_stair_sides(faces: PackedVector3Array, material: Material) -> void:
	# Fill the holes between the exported individual tread strips on both
	# sides. The visible stair treads remain exposed above this stone support.
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for i in range(0, faces.size(), 3):
		var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
		for j in range(3):
			normals.append(normal)
			uvs.append(Vector2(faces[i + j].x + faces[i + j].z, faces[i + j].y) * 0.15)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "StairStoneSides_%d" % int(stats.stair_ramps)
	instance.mesh = mesh
	instance.material_override = material
	_root.add_child(instance)

func _add_city_joins() -> void:
	# Coordinates come from the installed GLB's transformed floor triangles.
	# The 3.4m side gaps had no surface at entry height, only LAND_ 10m below.
	_add_join("EntryWest", Vector3(1055.4, 323.81, -560.0), Vector3(1059.3, 323.64, -560.0), 21.6, "C_ARRAY_EntrancePaving")
	_add_join("EntryEast", Vector3(1100.7, 323.64, -560.0), Vector3(1104.6, 323.81, -560.0), 21.6, "C_ARRAY_EntrancePaving")
	# Start the ramp where the raised paving actually ends, rather than under
	# it: the former overlap exposed a 1.824m vertical drop at z=-589.
	_add_join("EntryMainSlope", Vector3(1080.0, 314.19, -612.8), Vector3(1080.0, 323.64, -589.5), 20.5, "C_SUPPORT_EntranceStairWedge")
	_add_join("EntryMainLanding", Vector3(1080.0, 323.64, -589.5), Vector3(1080.0, 323.64, -588.4), 20.5, "C_ARRAY_EntrancePaving")
	_add_join("EastGateHouse", Vector3(1144.8, 324.08, -578.0), Vector3(1146.0, 324.20, -578.0), 5.0, "C_BRIDGE_POL_EastGate")
	_add_join("EastGateMeadow", Vector3(1168.0, 324.20, -578.0), Vector3(1169.2, 324.12, -578.0), 5.0, "C_BRIDGE_POL_EastGate")
	_add_join("WestGateMeadow", Vector3(990.8, 324.12, -578.0), Vector3(992.0, 324.20, -578.0), 5.0, "C_BRIDGE_POL_WestGate")
	_add_join("WestGateHouse", Vector3(1014.0, 324.20, -578.0), Vector3(1015.2, 324.08, -578.0), 5.0, "C_BRIDGE_POL_WestGate")
	# The exported elevated stair and terrace pieces leave raised lips at their
	# joins. These visible stone decks bridge the lips at a walkable grade.
	_add_join("WestRiseLower", Vector3(878.0, 328.6, -699.0), Vector3(872.0, 353.0, -730.0), 5.0, "C_ARRAY_POL_INST_EXP_WestRise_Stair", true)
	_add_join("WestRiseTop", Vector3(872.0, 353.0, -730.0), Vector3(869.0, 352.2, -744.0), 5.0, "C_ARRAY_POL_INST_EXP_WestRise_Stair", true)
	_add_join("EastRiseLower", Vector3(1273.0, 326.2, -680.0), Vector3(1278.0, 334.0, -700.0), 5.0, "C_ARRAY_POL_INST_EXP_EastRise_Stair", true)
	_add_join("EastRiseMiddle", Vector3(1278.0, 334.0, -700.0), Vector3(1282.5, 353.0, -725.0), 5.0, "C_ARRAY_POL_INST_EXP_EastRise_Stair", true)
	_add_join("EastRiseTop", Vector3(1282.5, 353.0, -725.0), Vector3(1286.0, 352.3, -744.0), 5.0, "C_ARRAY_POL_INST_EXP_EastRise_Stair", true)
	_add_join("TreeWestTop", Vector3(1015.0, 356.8, -760.0), Vector3(1037.0, 356.3, -760.0), 5.5, "C_ARRAY_POL_INST_EXP_TreeWest_Stair", true)
	_add_join("TreeWestSlope", Vector3(1037.0, 356.3, -760.0), Vector3(1060.0, 336.2, -760.0), 5.5, "C_ARRAY_POL_INST_EXP_TreeWest_Stair", true)
	_add_join("TreeEastLower", Vector3(1120.0, 336.7, -755.0), Vector3(1170.0, 348.5, -809.0), 8.0, "C_ARRAY_POL_INST_EXP_TreeEast_Stair", true)
	_add_join("TreeEastTop", Vector3(1170.0, 348.5, -809.0), Vector3(1180.0, 350.7, -820.0), 8.0, "C_ARRAY_POL_INST_EXP_TreeEast_Stair", true)
	_add_join("TreeEastLip", Vector3(1180.0, 350.7, -820.0), Vector3(1184.0, 353.0, -824.0), 8.0, "C_ARRAY_POL_INST_EXP_TreeEast_Stair", true)
	_add_join("TreeEastExit", Vector3(1184.0, 353.0, -824.0), Vector3(1208.0, 352.3, -850.0), 8.0, "C_ARRAY_POL_INST_EXP_TreeEast_Stair", true)
	_add_join("EastRearSeam", Vector3(1226.0, 352.1, -829.0), Vector3(1239.0, 352.4, -816.0), 4.5, "C_PATH_POL_INST_EXP_EastRear", true)

func _add_join(label: String, a: Vector3, b: Vector3, half_width: float, material_owner: String, top_only: bool = false) -> void:
	if not _nodes.has(material_owner):
		return
	var source: MeshInstance3D = _nodes[material_owner]
	var node := make_join_mesh(a - _root.global_position, b - _root.global_position, half_width, source.get_active_material(0))
	node.name = "Seam_" + label
	_root.add_child(node)
	var faces := node.mesh.get_faces()
	if top_only:
		var deck_faces := PackedVector3Array()
		for i in range(0, faces.size(), 3):
			var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
			if normal.y > WALKABLE_NORMAL_Y:
				deck_faces.append_array(PackedVector3Array([faces[i], faces[i + 1], faces[i + 2]]))
		faces = deck_faces
	_queue((a + b) * 0.5 - _root.global_position, faces, true)
	stats["visible_joins"] = int(stats.get("visible_joins", 0)) + 1

static func make_join_mesh(a: Vector3, b: Vector3, half_width: float, material: Material) -> MeshInstance3D:
	var direction := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var side := Vector3(-direction.z, 0.0, direction.x) * half_width
	var ring := PackedVector3Array([a - side, a + side, b + side, b - side])
	var base := minf(a.y, b.y) - 0.24
	var bottom := PackedVector3Array()
	for point in ring:
		bottom.append(Vector3(point.x, base, point.z))
	var faces := PackedVector3Array()
	_triangle(faces, ring[0], ring[1], ring[2], Vector3.UP)
	_triangle(faces, ring[0], ring[2], ring[3], Vector3.UP)
	_triangle(faces, bottom[0], bottom[2], bottom[1], Vector3.DOWN)
	_triangle(faces, bottom[0], bottom[3], bottom[2], Vector3.DOWN)
	var center := (a + b) * 0.5
	for i in range(4):
		var j := (i + 1) % 4
		var outward := (ring[i] + ring[j]) * 0.5 - center
		outward.y = 0.0
		_triangle(faces, ring[i], bottom[i], bottom[j], outward)
		_triangle(faces, ring[i], bottom[j], ring[j], outward)
	return make_faces_mesh(faces, material)

static func make_faces_mesh(faces: PackedVector3Array, material: Material) -> MeshInstance3D:
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	for i in range(0, faces.size(), 3):
		var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
		for j in range(3):
			normals.append(normal)
			uv.append(Vector2(faces[i + j].x, faces[i + j].z) * 0.15)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance

static func _triangle(faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	faces.append(a)
	if (c - a).cross(b - a).dot(outward) >= 0.0:
		faces.append(b)
		faces.append(c)
	else:
		faces.append(c)
		faces.append(b)
