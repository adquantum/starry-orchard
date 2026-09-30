extends "res://scripts/worlds/haqi_explorer.gd"
## Reuses the authored terrain builder and mesh transforms; no explorer or environment.
const ROOM_LAYER := 1 << 19
var authored_spawn := Vector3.ZERO
var local_bounds := AABB()
var maximum_height := 0.0
var prepared := false
var bodies: Array[StaticBody3D] = []
var arena_local:=Vector3.INF
var dressing: Node3D

func _ready() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)

func prepare(source: String) -> bool:
	world_root = source
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("world.json")))
	if not parsed is Dictionary:return false
	data = parsed
	terrain_size = float(data.tile_size)
	origin = Vector2(data.origin[0],data.origin[1])
	var attr: Dictionary = data.attributes
	authored_spawn = Vector3(float(attr.PlayerX)-origin.x,float(attr.PlayerY),float(attr.PlayerZ)-origin.y)
	var paths: Dictionary = {}
	for path in data.models.values():paths[str(path)] = true
	for tile in data.terrain:
		var painted := source.path_join("terrain_paint_layers_v1/ground_%d_%d.png" % [int(tile.tile[0]),int(tile.tile[1])])
		var texture := painted if ResourceLoader.exists(painted) else str(tile.get("texture",""))
		if not texture.is_empty():paths[texture] = true
	for path in paths:
		if ResourceLoader.load_threaded_request(path) != OK:return false
	for path in paths:
		while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_LOADED:return false
		var resource := ResourceLoader.load_threaded_get(path)
		if resource == null:return false
		if resource is PackedScene:
			var instance: Node = (resource as PackedScene).instantiate()
			var parts: Array = []
			_collect_meshes(instance,Transform3D.IDENTITY,parts)
			prototypes[path] = parts
			instance.free()
		await get_tree().process_frame
	for tile in data.terrain:
		_build_terrain(tile)
		await get_tree().process_frame
	for placement in data.placements:
		if str(placement.model).is_empty():continue
		var m: Array = placement.matrix
		var tr := Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[3],m[4],m[5]),Vector3(m[6],m[7],m[8])),Vector3(placement.position[0]+m[9],placement.position[1]+m[10],placement.position[2]+m[11]))
		if absf(tr.basis.determinant()) < 0.00001:continue
		for part in prototypes[placement.model]:
			var mesh := MeshInstance3D.new()
			mesh.mesh = part.mesh
			mesh.transform = tr * part.transform
			add_child(mesh)
			if bool(placement.solid):
				if not part.has("shape"):part.shape = part.mesh.create_trimesh_shape()
				var body := StaticBody3D.new()
				body.collision_layer = 0
				body.collision_mask = 0
				var collision := CollisionShape3D.new()
				collision.shape = part.shape
				body.add_child(collision)
				mesh.add_child(body)
		await get_tree().process_frame
	var first := true
	for child in get_children():
		if child is Node3D:child.position -= authored_spawn
		if child is MeshInstance3D:
			var bounds: AABB = child.transform * child.get_aabb()
			local_bounds = bounds if first else local_bounds.merge(bounds)
			first = false
		_configure_branch(child)
	maximum_height = local_bounds.size.y
	prepared = true
	set_active(false)
	return true

func _build_terrain(tile: Dictionary) -> void:
	super._build_terrain(tile)
	_configure_branch(get_child(get_child_count()-1))

func _configure_branch(node: Node) -> void:
	if node is GeometryInstance3D:
		node.layers = ROOM_LAYER
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is StaticBody3D:
		node.collision_layer = 0
		node.collision_mask = 0
		if not bodies.has(node):bodies.append(node)
	for child in node.get_children():_configure_branch(child)

func set_active(value: bool) -> void:
	visible = value
	for body in bodies:body.collision_layer = ROOM_LAYER if value else 0

func ground_at(point: Vector3) -> float:
	var authored := to_local(point) + authored_spawn
	return super._height(authored) - authored_spawn.y + global_position.y

func find_arena() -> Vector3:
	for x in range(-80,201,10):
		for z in range(-80,201,10):
			var point:=global_position+Vector3(x,0,z)
			var height:=ground_at(point)
			if height<global_position.y-4:continue
			var flat:=true
			for offset in [Vector3(17,0,0),Vector3(-17,0,0),Vector3(0,0,17),Vector3(0,0,-17)]:
				if absf(ground_at(point+offset)-height)>0.35:flat=false
			if flat:return to_local(Vector3(point.x,height+0.2,point.z))
	return Vector3.INF

func dress(index: int) -> bool:
	arena_local=find_arena()
	if not arena_local.is_finite():return false
	dressing=preload("res://scripts/tower_v01/floor_dressing.gd").new()
	add_child(dressing);dressing.build(self,index,arena_local)
	set_active(false)
	return true
