extends RefCounted
## Saved Blender city. Visual meshes stay intact; runtime collision is authored
## separately so water, light cards and garden decoration cannot trap the player.
const CityCollision = preload("res://scripts/worlds/orchard_city_collision.gd")
const CityGeometry = preload("res://scripts/worlds/orchard_city_geometry.gd")
const GroundMaterials = preload("res://scripts/worlds/orchard_city_ground_materials.gd")
const CITY_FILE := "res://assets/worlds/star_orchard/harbor_city/harbor_city_game.glb"
const MOUNT := Vector3(1027.1793804, 258.5462952, 112.7727833)
const CITY_MASK := 1 << 18
const CITY_SCALE := 2.0
const WORLD_MIN := Vector3(754.9327, 209.6408, -261.7778)
const WORLD_MAX := Vector3(1399.8317, 326.2952, 420.0001)
const COLLISION_REGION_SIZE := 96.0
const WALKABLE_NORMAL_Y := 0.6156615 # The explorer's existing 52 degree limit.
const FLOOR_QUERY_RISE := 1.2
const FOUNTAIN_OWNER := "C_SO_INST_SO_01_Central_Plaza_0001_fountain"
var ground_material_stats: Dictionary = {}
var root: Node3D
var _world: Node3D
var _collision_root: Node3D
var _mesh_faces: Dictionary = {}
var _solid_batches: Dictionary = {}
var _floor_batches: Dictionary = {}
var _upper_landing: MeshInstance3D
var _installed := false
var quay: Node3D
var collision_stats: Dictionary = {
	"source_solids": 0, "decorative_skipped": 0, "stair_ramps": 0,
	"solid_bodies": 0, "floor_bodies": 0, "floor_triangles": 0,
	"fountain_sections": 0,
}

func install(world: Node3D) -> bool:
	if _installed:
		return true
	_world = world
	root = preload("res://scripts/worlds/orchard_scene_cache.gd").instantiate(CITY_FILE)
	if root == null:
		push_error("Harbor city GLB generated no Node3D scene")
		return false
	root.name = "BlenderHarborCity"
	root.position = MOUNT
	root.scale = Vector3.ONE * CITY_SCALE
	world.add_child(root)
	_install_tideroot_quay()
	var removed_cliff_rocks := _remove_imported_cliff_rocks(root)
	root.set_meta("removed_imported_cliff_rocks", removed_cliff_rocks)
	var geometry := CityGeometry.new()
	geometry.repair(root, "harbor")
	ground_material_stats = GroundMaterials.new().apply_city(root, "harbor")
	geometry.finish(root)
	# Bake every source transform into the vertices. Physics bodies have unit
	# scale for any remaining nonuniformly scaled imported instances.
	_collision_root = Node3D.new()
	_collision_root.name = "HarborRuntimeCollision"
	_collision_root.top_level = true
	root.add_child(_collision_root)
	_collision_root.global_transform = Transform3D(Basis.IDENTITY, root.global_position)
	_collect_collisions(root)
	_add_east_bridge_join()
	_build_regions(_solid_batches, 1, "Solid")
	_build_regions(_floor_batches, CITY_MASK, "WalkSurface")
	_mesh_faces.clear()
	_solid_batches.clear()
	_floor_batches.clear()
	root.set_meta("harbor_collision_revision", 4)
	root.set_meta("harbor_collision_stats", collision_stats.duplicate())
	_installed = true
	return true

func _install_tideroot_quay() -> void:
	const QUAY_FILE := "res://assets/worlds/star_orchard/tideroot_quay/quay_runtime.scn"
	var packed := load(QUAY_FILE) as PackedScene
	if packed == null:
		push_error("Tideroot quay unavailable; preserving original harbor decks")
		return
	quay = packed.instantiate() as Node3D
	_world.add_child(quay)
	var removed := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var label := str(node.name)
		var old_dock_prop: bool = label.begins_with("C_SO_INST_SO_05_Harbor_") and node.position.y < -16.0 and not label.contains("airship")
		if old_dock_prop or label.begins_with("C_SO_RAIL_") or label.begins_with("C_SO_DOCK_") or label.begins_with("C_SO_R2_DOCK_") or label.begins_with("C_SO_INST_Dock_Lamp_") or label.begins_with("C_SO_INST_Harbor_Barrels_") or label.begins_with("C_SO_INST_Harbor_Cargo_"):
			node.get_parent().remove_child(node)
			node.free()
			removed += 1
		elif label.contains("0378_airship"):
			node.global_position = Vector3(885.4, 222.28, 319.8)
		elif label.contains("0379_airship"):
			node.global_position = Vector3(1284, 234.6, 368)
	quay.set_meta("replaced_original_meshes", removed)
	root.set_meta("tideroot_quay_installed", true)

func _remove_imported_cliff_rocks(node: Node) -> int:
	# The land meshes already form continuous textured outer walls. These
	# Blender stone instances only overlay them as a jagged decorative ring.
	var removed := 0
	for child in node.get_children():
		if String(child.name).begins_with("C_SO_INST_Cliff_"):
			node.remove_child(child)
			child.free()
			removed += 1
		else:
			removed += _remove_imported_cliff_rocks(child)
	return removed

func entry_point() -> Vector3:
	return Vector3(1045.0, 242.1952, 146.7728)

func _collect_collisions(node: Node) -> void:
	if node == _collision_root:
		return
	if node is MeshInstance3D and node.mesh != null and (str(node.name).begins_with("C_") or node.get_meta("city_walk_surface", false)):
		var mesh_node := node as MeshInstance3D
		var source_name := str(node.name)
		var owner_name := source_name.get_slice("__", 0)
		if owner_name == "C_SO_R3_EastBridge_UpperLanding":
			_upper_landing = mesh_node
		collision_stats.source_solids += 1
		if mesh_node.get_meta("city_walk_surface", false):
			_add_mesh_collision(mesh_node, true)
		elif owner_name == FOUNTAIN_OWNER:
			# Guang_01, guang_02 and water_fps3 were incorrectly exported as C_.
			# Only the solid stone body receives a simple closed compound collider.
			if source_name.ends_with("__ShengMingZhiQuan_00"):
				_add_fountain_collision(mesh_node)
			else:
				collision_stats.decorative_skipped += 1
		elif _is_decoration(source_name, owner_name):
			collision_stats.decorative_skipped += 1
		elif owner_name.contains("Stair_Flight_"):
			_add_stair_collision(mesh_node)
		elif owner_name.contains("Stair_Support_"):
			# The old support starts 0.78-0.83m below the first tread. Replace its
			# contact surface with the flight's continuous nosing envelope.
			pass
		else:
			_add_mesh_collision(mesh_node, _is_walk_surface(owner_name) or mesh_node.get_meta("city_walk_surface", false))
	for child in node.get_children():
		if not child is StaticBody3D:
			_collect_collisions(child)


func _add_stair_collision(node: MeshInstance3D) -> void:
	var geometry := CityCollision.stair_geometry(node, _collision_root.global_transform, false)
	if geometry.is_empty():
		_add_mesh_collision(node, true)
		return
	var faces: PackedVector3Array = geometry.faces
	var floor_faces := PackedVector3Array()
	for i in range(0, faces.size(), 3):
		var normal := (faces[i + 2] - faces[i]).cross(faces[i + 1] - faces[i]).normalized()
		if normal.y >= WALKABLE_NORMAL_Y:
			floor_faces.append_array(PackedVector3Array([faces[i], faces[i + 1], faces[i + 2]]))
	_add_batch(_solid_batches, geometry.center, faces)
	_add_batch(_floor_batches, geometry.center, floor_faces)
	collision_stats.floor_triangles += floor_faces.size() / 3
	collision_stats.stair_ramps += 1
	var sides := CityCollision.make_faces_mesh(geometry.sides, node.get_active_material(0))
	sides.name = "HarborStairStoneSides_%d" % int(collision_stats.stair_ramps)
	_collision_root.add_child(sides)

func _add_east_bridge_join() -> void:
	if _upper_landing == null:
		return
	var origin := _collision_root.global_position
	var join := CityCollision.make_join_mesh(
		Vector3(1183.0, 252.3952, 114.0) - origin,
		Vector3(1184.5, 252.1152, 114.0) - origin,
		9.0, _upper_landing.get_active_material(0))
	join.name = "HarborEastBridgeTempleJoin"
	_collision_root.add_child(join)
	_add_mesh_collision(join, true)
	collision_stats["visible_joins"] = 1

func _is_decoration(source_name: String, owner_name: String) -> bool:
	var source_upper := source_name.to_upper()
	var owner_upper := owner_name.to_upper()
	# SHRUB and FOAM were missing from the original export blacklist. Keep
	# all buildings, walls, fence/rail posts, cliffs, cargo, piles and decks.
	for token in ["SHRUB", "UNDERSTORY", "GUANMU", "SHORE_FOAM", "WATER_FPS", "__GUANG_"]:
		if source_upper.contains(token):
			return true
	for token in ["_ROPE", "_SACK", "_BUCKET", "_CANDLE", "_RUNE", "_SIGN", "_GOODS", "SHOPPOT"]:
		if owner_upper.contains(token):
			return true
	return false

func _is_walk_surface(owner_name: String) -> bool:
	for prefix in ["C_SO_LAND_", "C_SO_PATH_", "C_SO_PLAZA_", "C_SO_GARDEN_BED_"]:
		if owner_name.to_upper().begins_with(prefix):
			return true
	if owner_name.begins_with("C_SO_DOCK_"):
		return owner_name.ends_with("_Plank")
	if owner_name == "C_SO_R2_Harbor_UpperLanding":
		return true
	if not owner_name.begins_with("C_SO_R3_") or owner_name.contains("_INST_"):
		return false
	for token in ["Rail", "Posts", "Support", "BANK_", "Fence"]:
		if owner_name.contains(token):
			return false
	for token in ["_PATH_", "_Path", "Apron", "_Court_", "_Rest_", "Landing"]:
		if owner_name.contains(token):
			return true
	return false

func _faces(mesh: Mesh) -> PackedVector3Array:
	var key := mesh.get_instance_id()
	if not _mesh_faces.has(key):
		_mesh_faces[key] = mesh.get_faces()
	return _mesh_faces[key]

func _add_mesh_collision(node: MeshInstance3D, walk_surface: bool) -> void:
	var source := _faces(node.mesh)
	if source.is_empty():
		return
	var transform := _collision_root.global_transform.affine_inverse() * node.global_transform
	var flip := transform.basis.determinant() < 0.0
	var solid := PackedVector3Array()
	var floor_faces := PackedVector3Array()
	solid.resize(source.size())
	var write_index := 0
	for index in range(0, source.size(), 3):
		var a := transform * source[index]
		var b := transform * source[index + (2 if flip else 1)]
		var c := transform * source[index + (1 if flip else 2)]
		# Godot triangle front faces use clockwise winding. Mirrored source
		# transforms are corrected above before both physical and floor baking.
		var normal := (c - a).cross(b - a)
		var area_twice := normal.length()
		if area_twice < 0.00001:
			continue
		solid[write_index] = a
		solid[write_index + 1] = b
		solid[write_index + 2] = c
		write_index += 3
		if walk_surface and normal.y / area_twice >= WALKABLE_NORMAL_Y:
			floor_faces.append(a)
			floor_faces.append(b)
			floor_faces.append(c)
	solid.resize(write_index)
	var center := transform * node.mesh.get_aabb().get_center()
	_add_batch(_solid_batches, center, solid)
	_add_batch(_floor_batches, center, floor_faces)
	collision_stats.floor_triangles += floor_faces.size() / 3

func _add_batch(batches: Dictionary, center: Vector3, faces: PackedVector3Array) -> void:
	if faces.is_empty():
		return
	var cell := Vector2i(floori(center.x / COLLISION_REGION_SIZE), floori(center.z / COLLISION_REGION_SIZE))
	if not batches.has(cell):
		batches[cell] = []
	# An Array of batches avoids repeatedly copying growing packed arrays.
	batches[cell].append(faces)

func _build_regions(batches: Dictionary, layer: int, label: String) -> void:
	for cell in batches:
		var faces := PackedVector3Array()
		for batch: PackedVector3Array in batches[cell]:
			faces.append_array(batch)
		var body := StaticBody3D.new()
		body.name = "Harbor%s_%d_%d" % [label, cell.x, cell.y]
		body.collision_layer = layer
		body.collision_mask = 0
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = false
		shape.set_faces(faces)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		_collision_root.add_child(body)
		if layer == CITY_MASK:
			collision_stats.floor_bodies += 1
		else:
			collision_stats.solid_bodies += 1

func _add_fountain_collision(node: MeshInstance3D) -> void:
	var source := _faces(node.mesh)
	var transform := _collision_root.global_transform.affine_inverse() * node.global_transform
	# These boundaries come from the source fountain's stone vertices: the
	# outer basin rim ends at local Y=4.529, the stem at 15.415 and the crown
	# above it. Three closed hulls preserve its silhouette without a hollow
	# collision bowl, sharp internal triangles or invisible effect-card walls.
	for section in [[-0.01, 4.60], [4.45, 15.45], [15.40, 19.40]]:
		var points := PackedVector3Array()
		var seen: Dictionary = {}
		for vertex in source:
			if vertex.y < float(section[0]) or vertex.y > float(section[1]):
				continue
			if seen.has(vertex):
				continue
			seen[vertex] = true
			points.append(transform * vertex)
		if points.size() < 4:
			continue
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var collision := CollisionShape3D.new()
		collision.shape = shape
		var body := StaticBody3D.new()
		body.name = "FountainStoneSection%d" % int(collision_stats.fountain_sections)
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_child(collision)
		_collision_root.add_child(body)
		collision_stats.fountain_sections += 1
		collision_stats.solid_bodies += 1

func surface_height(at: Vector3) -> float:
	if not _installed or _world == null or not _world.is_inside_tree():
		return -INF
	if at.x < WORLD_MIN.x or at.x > WORLD_MAX.x or at.z < WORLD_MIN.z or at.z > WORLD_MAX.z:
		return -INF
	if at.y + FLOOR_QUERY_RISE < WORLD_MIN.y or at.y > WORLD_MAX.y + 150.0:
		return -INF
	var space := _world.get_world_3d().direct_space_state
	# Start below unreachable overhead decks instead of allowing the first
	# overhead hit to hide an otherwise valid ground surface below it.
	var ray_start := at + Vector3.UP * FLOOR_QUERY_RISE
	var ray_end := Vector3(at.x, WORLD_MIN.y - 2.0, at.z)
	for attempt in range(6):
		var query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, CITY_MASK)
		query.hit_back_faces = false
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return -INF
		var point: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		if normal.y >= WALKABLE_NORMAL_Y and point.y <= at.y + FLOOR_QUERY_RISE:
			return point.y
		ray_start = point - Vector3.UP * 0.03
		if ray_start.y <= ray_end.y:
			return -INF
	return -INF

