extends Node3D
var model_id := "lifetree"
var visual: Node3D
var animation: AnimationPlayer
var idle := ""
var cast_token := 0
var alive := true
var source_forward := Vector3.RIGHT
var presentation_scale := Vector3.ONE
func _ready() -> void:
	var stage_profiles: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/monster_stage_profiles.json"))
	var stage_profile: Dictionary=stage_profiles.get(model_id,{})
	visual=preload("res://scripts/fusion_3d/world_one_model.gd").place(self,model_id,Vector3.ZERO,2.5,true,false,stage_profile)
	if visual==null:return
	presentation_scale=Vector3.ONE*float(stage_profile.get("scale",1.0))
	visual.scale=presentation_scale
	var orientations: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/monster_orientation.json"))
	var orientation_id: String=preload("res://scripts/fusion_3d/character_library.gd").entry(model_id).get("existing_painted",model_id)
	if orientation_id.is_empty():orientation_id=model_id
	var profile: Dictionary=orientations.get(orientation_id,{"source_forward":[1,0,0],"yaw_degrees":90})
	var axis: Array=profile.source_forward
	source_forward=Vector3(axis[0],axis[1],axis[2])
	visual.rotation.y=deg_to_rad(float(profile.yaw_degrees))
	var players:=visual.find_children("*","AnimationPlayer",true,false)
	if not players.is_empty():
		animation=players[0]
		for id in animation.get_animation_list():
			if "000" in id or "Idle" in id:idle=id;break
		if idle.is_empty() and not animation.get_animation_list().is_empty():idle=animation.get_animation_list()[0]
		if not idle.is_empty():
			animation.get_animation(idle).loop_mode=Animation.LOOP_LINEAR
			animation.play(idle)
func anchor_global(id: String) -> Vector3:
	return to_global({"CastRelease":Vector3(0,1.8,-0.7),"HitPoint":Vector3(0,1.3,0),"HeadStatus":Vector3(0,2.8,0),"FootRing":Vector3.ZERO}.get(id,Vector3.UP))
func play_cast(duration: float) -> void:
	if not alive:return
	cast_token+=1
	var token:=cast_token
	if animation:
		for id in animation.get_animation_list():
			if "anim_071_" in id or "Cast" in id:
				animation.play(id,0.12);break
	var tween:=create_tween()
	tween.tween_property(visual,"rotation:x",-0.13,duration*0.35)
	tween.tween_property(visual,"rotation:x",0.0,duration*0.65)
	await get_tree().create_timer(duration).timeout
	if is_inside_tree() and token==cast_token and alive and animation and not idle.is_empty():animation.play(idle,0.15)
func hit() -> void:
	if not alive:return
	cast_token+=1
	var token:=cast_token
	var clip:=action_clip("073")
	if animation and not clip.is_empty():
		animation.get_animation(clip).loop_mode=Animation.LOOP_NONE
		animation.play(clip,0.08)
		await get_tree().create_timer(animation.get_animation(clip).length).timeout
		if is_inside_tree() and token==cast_token and alive and not idle.is_empty():animation.play(idle,0.12)
func set_alive(value: bool) -> void:
	if alive==value:return
	alive=value
	cast_token+=1
	visual.scale=presentation_scale
	if animation:
		if alive and not idle.is_empty():animation.play(idle)
		else:
			var clip:=action_clip("075")
			if clip.is_empty():clip=action_clip("001")
			if not clip.is_empty():
				animation.get_animation(clip).loop_mode=Animation.LOOP_NONE
				animation.play(clip,0.10)
			else:animation.pause()

func action_clip(code: String) -> String:
	if animation:
		for clip in animation.get_animation_list():
			if "anim_"+code+"_" in clip:return clip
	return ""

func front_global() -> Vector3:
	return (visual.global_basis*source_forward).normalized()
func face_center(center: Vector3) -> void:
	var level_target:=Vector3(center.x,global_position.y,center.z)
	if global_position.distance_squared_to(level_target)>0.0001:look_at(level_target,Vector3.UP)
