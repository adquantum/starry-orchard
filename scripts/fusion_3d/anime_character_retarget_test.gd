extends Node3D
# Match the standard female avatar's 2.0715-unit visible idle height.
const MODEL_SCALE:float=2.063
const MAP={"Root":"Bone_000","Hip":"Bone_001","Waist":"Bone_001","Spine01":"Bone_002","Spine02":"Bone_003","NeckTwist01":"Bone_019","Head":"Bone_018","L_Clavicle":"Bone_014","L_Upperarm":"Bone_015","L_Forearm":"Bone_016","L_Hand":"Bone_017","R_Clavicle":"Bone_010","R_Upperarm":"Bone_011","R_Forearm":"Bone_012","R_Hand":"Bone_013","L_Thigh":"Bone_007","L_Calf":"Bone_008","L_Foot":"Bone_009","R_Thigh":"Bone_004","R_Calf":"Bone_005","R_Foot":"Bone_006"}
const CHILD={"L_Upperarm":"L_Forearm","L_Forearm":"L_Hand","R_Upperarm":"R_Forearm","R_Forearm":"R_Hand","L_Thigh":"L_Calf","L_Calf":"L_Foot","R_Thigh":"R_Calf","R_Calf":"R_Foot"}
var source:Skeleton3D
var target:Skeleton3D
var source_player:AnimationPlayer
var target_player:AnimationPlayer
var corrections={}
var remap={}
var native_mode=false
var active="idle"
var c=Basis(Vector3.UP,PI/2)
var external_source:Skeleton3D
var external_player:AnimationPlayer
func find_kind(n:Node,kind:String)->Node:
	if n.is_class(kind):return n
	for ch in n.get_children():
		var found=find_kind(ch,kind)
		if found!=null:return found
	return null
func _ready():
	if external_source!=null:
		source=external_source;source_player=external_player
	else:
		var donor=load("res://assets/models/teen_humans/female_baselayer.glb").instantiate();add_child(donor);donor.visible=false
		source=find_kind(donor,"Skeleton3D");source_player=find_kind(donor,"AnimationPlayer")
	var model=load("res://assets/models/character_tests/anime_character.scn").instantiate();add_child(model);model.scale=Vector3.ONE*MODEL_SCALE
	target=find_kind(model,"Skeleton3D");target_player=find_kind(model,"AnimationPlayer");target_player.stop();target.reset_bone_poses()
	for name in MAP:
		var ti=target.find_bone(name);var si=source.find_bone(MAP[name]);assert(ti>=0 and si>=0,name)
		remap[ti]=si
		var align=Quaternion.IDENTITY
		if CHILD.has(name):
			var tc=target.find_bone(CHILD[name]);var sc=source.find_bone(MAP[CHILD[name]])
			var td=(target.get_bone_global_rest(tc).origin-target.get_bone_global_rest(ti).origin).normalized()
			var sd=(c.inverse()*(source.get_bone_global_rest(sc).origin-source.get_bone_global_rest(si).origin)).normalized()
			align=Quaternion(td,sd)
		# Hands inherit their forearm rest alignment; otherwise the A-pose offset
		# is lost at the wrist when the source arm is lowered.
		if str(name).ends_with("_Hand"):
			var forearm_name=str(name).replace("_Hand","_Forearm")
			var fi=target.find_bone(forearm_name)
			var sf=source.find_bone(MAP[forearm_name])
			var target_axis=(target.get_bone_global_rest(ti).origin-target.get_bone_global_rest(fi).origin).normalized()
			var source_axis=(c.inverse()*(source.get_bone_global_rest(si).origin-source.get_bone_global_rest(sf).origin)).normalized()
			align=Quaternion(target_axis,source_axis)
		corrections[ti]=align*target.get_bone_global_rest(ti).basis.get_rotation_quaternion()
	if external_source==null:play_action("idle")
func play_action(action:String):
	active=action
	if native_mode:
		var names={"idle":"walk","walk":"walk","run":"run","cast":"cast_a_spell","hit":"hit_to_body_01","fall":"fall","jump":"walk"}
		var key="Original_"+str(names[action]);assert(target_player.has_animation(key),key)
		target_player.get_animation(key).loop_mode=Animation.LOOP_LINEAR
		target_player.play(key)
		if action=="idle":target_player.seek(0,true);target_player.pause()
	else:
		target_player.stop();target.reset_bone_poses()
		var ids={"idle":"base_000","walk":"base_013","run":"base_004","cast":"base_071","hit":"base_073","fall":"base_075","jump":"base_037"}
		for key in source_player.get_animation_list():
			if str(key)==ids[action] or str(key).ends_with("/"+str(ids[action])):
				source_player.play(key,0);source_player.get_animation(key).loop_mode=Animation.LOOP_LINEAR;break
func set_native(value:bool):
	target.reset_bone_poses();native_mode=value;play_action(active)
func _process(_delta):
	if not native_mode:retarget()
func retarget():
	for ti in target.get_bone_count():
		if not remap.has(ti):continue
		var si:int=remap[ti]
		var rest=source.get_bone_global_rest(si).basis.orthonormalized()
		var pose=source.get_bone_global_pose(si).basis.orthonormalized()
		var delta=c.inverse()*pose*rest.inverse()*c
		var global_rotation=delta.get_rotation_quaternion()*corrections[ti]
		var parent=target.get_bone_parent(ti)
		var parent_rotation=Quaternion.IDENTITY if parent<0 else target.get_bone_global_pose(parent).basis.get_rotation_quaternion()
		target.set_bone_pose_rotation(ti,(parent_rotation.inverse()*global_rotation).normalized())
	var root_id=target.find_bone("Root")
	var hip=source.find_bone("Bone_001")
	var shift=c.inverse()*(source.get_bone_global_pose(hip).origin-source.get_bone_global_rest(hip).origin)*.26
	target.set_bone_pose_position(root_id,target.get_bone_rest(root_id).origin+shift)


