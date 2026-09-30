extends Node3D
var model: Node3D
var animation: AnimationPlayer
var sockets: Dictionary={}
var cast_generation:=0
func _ready() -> void:
	model=load("res://assets/models/academy/life_professor.glb").instantiate()
	add_child(model)
	model.scale=Vector3.ONE*1.65
	model.rotation.y=PI
	var skeleton:=find_skeleton(model)
	if skeleton:
		for pair in [["HandGrip","hand_r"],["StaffSocket","hand_r"],["CastRelease","hand_r"],["HeadStatus","Head"]]:
			var anchor:=BoneAttachment3D.new()
			anchor.name=pair[0]
			anchor.bone_name=pair[1]
			skeleton.add_child(anchor)
			sockets[pair[0]]=anchor
	animation=find_animation(model)
	if animation:
		for id in animation.get_animation_list():
			if "Idle" in id:
				animation.get_animation(id).loop_mode=Animation.LOOP_LINEAR
				animation.play(id)
func find_animation(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node
	for child in node.get_children():
		var found:=find_animation(child)
		if found: return found
	return null
func configure(_color: Color,_school: String,_enemy: bool) -> void: pass
func anchor_global(id: String) -> Vector3:
	if sockets.has(id): return sockets[id].global_position
	var offsets: Dictionary={"CastRelease":Vector3(-0.55,2.3,-0.3),"HitPoint":Vector3(0,1.5,0),"HeadStatus":Vector3(0,3.1,0),"FootRing":Vector3.ZERO}
	return to_global(offsets.get(id,Vector3.UP))
func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node
	for child in node.get_children():
		var found:=find_skeleton(child)
		if found: return found
	return null
func play_named(fragment: String, looping: bool=false) -> void:
	if animation==null:return
	for id in animation.get_animation_list():
		if fragment in id:
			animation.get_animation(id).loop_mode=Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
			animation.play(id,0.15)
			return
func play_cast(duration: float) -> void:
	cast_generation+=1
	var token:=cast_generation
	play_named("Cast")
	await get_tree().create_timer(duration).timeout
	if is_inside_tree() and token==cast_generation: play_named("Idle",true)
func hit() -> void:
	var tween:=create_tween()
	tween.tween_property(model,"position:z",0.12,0.08)
	tween.tween_property(model,"position:z",0.0,0.18)
func set_alive(alive: bool) -> void:
	cast_generation+=1
	model.visible=alive
	if alive:play_named("Idle",true)
