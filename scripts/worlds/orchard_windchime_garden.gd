extends Node3D
## Authored garden, grounded into the west sea. Five clearings are design anchors only.
const MODEL := "res://assets/worlds/star_orchard/windchime_garden/windchime_garden.glb"
const CONFIG := "res://assets/worlds/star_orchard/windchime_garden/layout.json"
const FLOOR_MASK := 1 << 18
var model: Node3D
var config: Dictionary
var floor_count := 0
var world: Node3D

func install(target: Node3D) -> bool:
	world = target
	name = "WindchimeGarden"
	config = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	model = preload("res://scripts/worlds/orchard_scene_cache.gd").instantiate(MODEL)
	if model == null:
		push_error("Windchime garden model failed to load")
		return false
	add_child(model)
	position = point(config.mount)
	scale = Vector3.ONE * float(config.scale)
	_install_floors(model)
	_install_ramps()
	_install_trunks(model)
	set_meta("battle_clearings", config.arenas)
	set_meta("grounded_to_seabed", true)
	return true

static func point(v: Array) -> Vector3:
	return Vector3(float(v[0]), float(v[1]), float(v[2]))

func _install_floors(node: Node) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("WalkSurface_"):
		var body := StaticBody3D.new()
		body.name = "GardenWalkSurface"
		body.collision_layer = 1 | FLOOR_MASK
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		if _is_battle_clearing(node):
			shape.shape = _battle_clearing_shape(node.mesh)
		else:
			shape.shape = node.mesh.create_trimesh_shape()
		body.add_child(shape)
		node.add_child(body)
		floor_count += 1
	for child in node.get_children():
		if not child is StaticBody3D: _install_floors(child)

func _is_battle_clearing(node: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != model:
		if String(parent.name).begins_with("07_Battle_Clearings"):
			return true
		parent = parent.get_parent()
	return false

func _battle_clearing_shape(mesh: Mesh) -> ConcavePolygonShape3D:
	# Keep the board height, replacing its vertical lip with a shallow approach
	# on all sides. The outer edge sinks below the surrounding terrace/path.
	var bounds := mesh.get_aabb()
	var center := bounds.get_center()
	center.y = bounds.end.y
	var radius := maxf(bounds.size.x, bounds.size.z) * 0.5
	var faces := PackedVector3Array()
	for i in 64:
		var angle_a := TAU * float(i) / 64.0
		var angle_b := TAU * float(i + 1) / 64.0
		var direction_a := Vector3(cos(angle_a), 0.0, sin(angle_a))
		var direction_b := Vector3(cos(angle_b), 0.0, sin(angle_b))
		var inner_a := center + direction_a * radius
		var inner_b := center + direction_b * radius
		var outer_a := center + direction_a * (radius + 0.8)
		var outer_b := center + direction_b * (radius + 0.8)
		outer_a.y = bounds.position.y
		outer_b.y = bounds.position.y
		faces.append_array(PackedVector3Array([center, inner_a, inner_b,
			inner_a, outer_a, outer_b, inner_a, outer_b, inner_b]))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return shape

func _install_ramps() -> void:
	for route in config.bridges:
		var a := point(route[0])
		var b := point(route[1])
		var side := Vector3(-(b-a).z,0,(b-a).x).normalized() * float(route[2]) * .5
		# Match the visible top of the staircase with a continuous walk plane.
		a.y += .14
		b.y += .14
		var points := PackedVector3Array([a-side,a+side,b-side,b-side,a+side,b+side])
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(points)
		shape.backface_collision = true
		var collider := CollisionShape3D.new()
		collider.shape = shape
		var body := StaticBody3D.new()
		body.name = "GardenContinuousStairRamp"
		body.collision_layer = 1 | FLOOR_MASK
		body.collision_mask = 0
		body.add_child(collider)
		add_child(body)

func _install_trunks(node: Node) -> void:
	if String(node.name).begins_with("Orchard_"):
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = .33
		cylinder.height = 3.5
		shape.shape = cylinder
		shape.position.y = 1.75
		body.add_child(shape)
		node.add_child(body)
	for child in node.get_children():
		if not child is StaticBody3D: _install_trunks(child)

func surface_height(at: Vector3) -> float:
	if model == null or at.x < -5 or at.x > 615 or at.z < -785 or at.z > -190:
		return -INF
	var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*1.3, Vector3(at.x,188,at.z),FLOOR_MASK)
	query.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return -INF
	return float(hit.position.y)

func entry_point() -> Vector3:
	return Vector3(221.6,228,-343)

func add_destinations(target: Node3D) -> void:
	target.destinations.append(entry_point())
	target.destination_names.append("风铃云圃 · 海岸花园")
	for arena in config.arenas:
		target.destinations.append(point(arena.world)+Vector3.UP*1.5)
		target.destination_names.append("风铃云圃 · "+str(arena.name))

