extends Node
## Visual clearance only; collision and battle rules remain unchanged.
var hidden_meshes: Array[GeometryInstance3D] = []
var candidates: Array[Dictionary] = []
var battle_stage: Node3D
var targets: Array[Vector3] = []

func configure(stage: Node3D) -> void:
	battle_stage=stage
	for x in [-9.0,0.0,9.0]:
		for z in [-9.0,0.0,9.0]:
			for y in [0.5,3.0]:
				targets.append(stage.global_position+Vector3(x,y,z))
	var origin := stage.global_position
	for node in stage.get_parent().find_children("*", "MeshInstance3D", true, false):
		if stage.is_ancestor_of(node) or not node.is_visible_in_tree():
			continue
		var bounds: AABB = node.global_transform * node.get_aabb()
		if bounds.size.y < 0.85 or bounds.end.y < origin.y + 0.8:
			continue
		if bounds.size.x > 100.0 or bounds.size.z > 100.0:
			continue
		var closest := Vector2(clampf(origin.x, bounds.position.x, bounds.end.x), clampf(origin.z, bounds.position.z, bounds.end.z))
		if closest.distance_to(Vector2(origin.x, origin.z)) <= 26.0:
			candidates.append({"mesh":node,"bounds":bounds,"distance":closest.distance_to(Vector2(origin.x,origin.z))})
	_process(0.0)

func _process(_delta: float) -> void:
	if not is_instance_valid(battle_stage) or battle_stage.camera==null:return
	var eye: Vector3=battle_stage.camera.global_position
	for entry in candidates:
		var mesh: MeshInstance3D=entry.mesh
		if not is_instance_valid(mesh) or not mesh.visible:continue
		var blocked: bool=entry.distance<12.0
		if not blocked:
			for target in targets:
				if entry.bounds.intersects_segment(eye,target)!=null:
					blocked=true
					break
		if blocked:
			hidden_meshes.append(mesh)
			mesh.hide()

func _exit_tree() -> void:
	for mesh in hidden_meshes:
		if is_instance_valid(mesh):
			mesh.show()
	hidden_meshes.clear()



