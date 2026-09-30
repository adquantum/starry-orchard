extends RefCounted
## Saved Blender city only; never substitutes old orchard islands on load failure.
const CityCollision = preload("res://scripts/worlds/orchard_city_collision.gd")
const CityGeometry = preload("res://scripts/worlds/orchard_city_geometry.gd")
const GroundMaterials = preload("res://scripts/worlds/orchard_city_ground_materials.gd")
const CITY_FILE := "res://assets/worlds/star_orchard/sky_city/sky_sanctuary_game.glb"
const MOUNT := Vector3(1080.0, 310.0, -630.0)
const CITY_MASK := 1 << 19
const CITY_SCALE := 2.0
const WORLD_MIN := Vector3(740.29, 244.12, -1143.97)
const WORLD_MAX := Vector3(1487.71, 433.46, -511.34)
var ground_material_stats: Dictionary = {}
var root: Node3D
var _world: Node3D
var collision_stats: Dictionary = {}
var _installed := false

func install(world: Node3D) -> bool:
	if _installed:
		return true
	_world = world
	root = preload("res://scripts/worlds/orchard_scene_cache.gd").instantiate(CITY_FILE)
	if root == null:
		push_error("Sky city GLB generated no Node3D scene")
		return false
	root.name = "BlenderSkySanctuary"
	root.position = MOUNT
	root.scale = Vector3.ONE * CITY_SCALE
	world.add_child(root)
	_remove_detached_islands(root)
	var entrance_patch := preload("res://scripts/worlds/orchard_root_entrance_geometry.gd").new()
	world.set_meta("old_root_entrance_geometry",entrance_patch.apply(root))
	var geometry := CityGeometry.new()
	geometry.repair(root, "sky")
	ground_material_stats = GroundMaterials.new().apply_city(root, "sky")
	geometry.finish(root)
	collision_stats = CityCollision.new().install(root, CITY_MASK)
	root.set_meta("sky_collision_revision", 4)
	root.set_meta("sky_collision_stats", collision_stats.duplicate())
	_installed = true
	return true

func _remove_detached_islands(node: Node) -> void:
	# Authored detached island groups only. Main-city cliff and terrace meshes
	# share their underlying assets and must remain in place.
	for child in node.get_children():
		var owner_name := String(child.name).get_slice("__", 0)
		if owner_name.begins_with("C_INST_EXP_DistantIsland_") or owner_name.begins_with("C_INST_WaterfallTerrace_") or owner_name.begins_with("V_INST_WaterfallTerrace_"):
			node.remove_child(child)
			child.free()
		else:
			_remove_detached_islands(child)

func entry_point() -> Vector3:
	return Vector3(1080.0, 325.64, -532.0)

func surface_height(at: Vector3) -> float:
	if not _installed or _world == null or not _world.is_inside_tree():
		return -INF
	if at.x < WORLD_MIN.x or at.x > WORLD_MAX.x or at.z < WORLD_MIN.z or at.z > WORLD_MAX.z:
		return -INF
	if at.y + 1.2 < WORLD_MIN.y or at.y > WORLD_MAX.y + 150.0:
		return -INF
	var space := _world.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.2,
		Vector3(at.x, WORLD_MIN.y - 2.0, at.z), CITY_MASK)
	query.hit_back_faces = false
	var hit := space.intersect_ray(query)
	if hit.is_empty() or hit.normal.y < 0.6156615:
		return -INF
	var height: float = hit.position.y
	# An overhead platform must not become a swimmer's floor.
	if height > at.y + 1.2:
		return -INF
	return height
