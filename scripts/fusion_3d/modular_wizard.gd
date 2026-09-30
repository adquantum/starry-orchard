extends Node3D
const Motion=preload("res://scripts/fusion_3d/character_motion.gd")
## Shared skinned avatar; swaps donor meshes onto one compatible skeleton.
var school_id:="fire"
var enemy:=false
var follow_local_wardrobe:=true
var battle_mode:=false
var model: Node3D
var skeleton: Skeleton3D
var equipped: Dictionary={}
var modules: Dictionary={}
var rest: Dictionary={}
var cast_amount:=0.0
var cast_sweep:=0.0
var airborne:=false
var vertical_speed:=0.0
var air_pose:=0.0
var landing:=0.0
var recoil:=0.0
var phase:=0.0
var motion:=0.0
var last_position:=Vector3.ZERO
var initialized:=false
var dead:=false
var cast_tween: Tween
var life_tween: Tween
var release_offset:=Vector3.ZERO
var foot_circle: Node3D
var battle_effect_opacity := 1.0:
	set(value):
		battle_effect_opacity=clampf(value,0.0,1.0)
		if is_instance_valid(foot_circle):foot_circle.opacity=battle_effect_opacity
static var scenes: Dictionary={}
var head_preview:=false
var is_custom_model:=false
var teen: Node3D
func _ready() -> void:
	get_node("/root/Wardrobe").changed.connect(_outfit_changed)
func configure(_color: Color, school: String, is_enemy: bool) -> void:
	school_id=school
	enemy=is_enemy
	var store:=get_node("/root/Wardrobe")
	apply_outfit(store.default_outfit(school) if enemy else store.outfit(school))
func _outfit_changed(school: String) -> void:
	if follow_local_wardrobe and school==school_id and not enemy:apply_outfit(get_node("/root/Wardrobe").outfit(school))
func source(theme: String) -> Node3D:
	return source_path(get_node("/root/Wardrobe").model_path(theme))
func source_path(path: String) -> Node3D:
	if not scenes.has(path):scenes[path]=load(path)
	return scenes[path].instantiate()
func find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:return root
	for child in root.get_children():
		var found:=find_skeleton(child)
		if found!=null:return found
	return null
func module_name(node: Node) -> String:
	return str(node.name).split("__")[-1].replace("_", ".")
func apply_outfit(value: Dictionary) -> void:
	# Clothing and hair swatches update uniforms without rebuilding the rig or restarting its clip.
	if teen!=null and is_instance_valid(teen):
		var previous:=equipped.duplicate(true)
		var incoming:=value.duplicate(true)
		previous.erase("teen_dyes")
		incoming.erase("teen_dyes")
		previous.erase("teen_hair_color")
		incoming.erase("teen_hair_color")
		if previous==incoming:
			equipped=value.duplicate(true)
			teen.update_dyes(equipped)
			return
	equipped=value.duplicate(true)
	if cast_tween!=null and cast_tween.is_valid():cast_tween.kill()
	if life_tween!=null and life_tween.is_valid():life_tween.kill()
	cast_amount=0
	cast_sweep=0
	if model!=null:
		remove_child(model)
		model.queue_free()
	if foot_circle!=null:
		remove_child(foot_circle)
		foot_circle.queue_free()
	foot_circle=null
	teen=null
	skeleton=null
	modules.clear()
	if str(equipped.get("model_style",""))=="teen":
		is_custom_model=false
		teen=preload("res://scripts/fusion_3d/teen_avatar.gd").new()
		model=teen
		add_child(teen)
		teen.setup(equipped)
		teen.set_alive(not dead)
		teen.set_head_preview(head_preview)
		foot_circle=preload("res://scripts/fusion_3d/school_vfx.gd").new()
		foot_circle.name="EquippedAura"
		foot_circle.school=str(equipped.aura)
		foot_circle.kind="rune"
		foot_circle.diameter=1.65
		foot_circle.subtle=true
		foot_circle.opacity=battle_effect_opacity
		foot_circle.position.y=0.045
		add_child(foot_circle)
		foot_circle.visible=battle_mode and not dead
		return
	var store:=get_node("/root/Wardrobe")
	var custom: Dictionary=store.catalog.get("custom_models",{}).get(school_id,{})
	is_custom_model=str(equipped.get("model_style","modular"))=="custom" and not custom.is_empty()
	model=source_path(str(custom.model)) if is_custom_model else source(str(equipped.body))
	model.name="ModularModel"
	add_child(model)
	model.scale=Vector3.ONE*Motion.MODEL_SCALE
	# Blender -Y converts to glTF +Z; adapt once to the game's shared -Z forward.
	model.rotation.y=PI
	skeleton=find_skeleton(model)
	modules.clear()
	if is_custom_model:
		for item in model.find_children("*","MeshInstance3D",true,false):modules[module_name(item)]=item
	else:
		for item in model.find_children("*","MeshInstance3D",true,false):
			var part:=module_name(item)
			if part in ["Body","Arm.L","Arm.R"]:
				modules[part]=item
			else:
				item.get_parent().remove_child(item)
				item.queue_free()
		for slot in ["gender","hairstyle","hat","robe","boots","staff"]:
			var donor: Node3D=source_path(store.appearance_path(slot,str(equipped[slot]))) if slot in ["gender","hairstyle"] else source(str(equipped[slot]))
			var wanted: Array=[]
			match slot:
				"gender":wanted=["Head","Face","Ear.L","Ear.R"]
				"hairstyle":wanted=["Hair.Bangs","Hair.Side.L","Hair.Side.R","Hair.Back","Hair.Accessory"]
				"hat":wanted=["Hat"]
				"robe":wanted=["Clothes","Sleeve.L","Sleeve.R","Belt"]
				"boots":wanted=["Boot.L","Boot.R"]
				"staff":wanted=["Staff"]
			for item in donor.find_children("*","MeshInstance3D",true,false):
				var part:=module_name(item)
				if not wanted.has(part):continue
				var copy:=item.duplicate() as MeshInstance3D
				copy.owner=null
				skeleton.add_child(copy)
				copy.skeleton=copy.get_path_to(skeleton)
				modules[part]=copy
			donor.free()
		_tint_appearance(str(equipped.body))
	set_head_preview(head_preview)
	rest.clear()
	for i in skeleton.get_bone_count():rest[skeleton.get_bone_name(i)]=skeleton.get_bone_rest(i)
	skeleton.reset_bone_poses()
	skeleton.force_update_all_bone_transforms()
	var hand:=skeleton.find_bone("hand.L")
	var tip: Vector3
	if is_custom_model:
		var point: Array=custom.cast_release
		tip=Vector3(point[0],point[1],point[2])
	else:
		var bounds: AABB=modules.Staff.get_aabb()
		tip=Vector3(bounds.get_center().x,bounds.end.y,bounds.get_center().z)
	release_offset=skeleton.get_bone_global_pose(hand).affine_inverse()*tip
	foot_circle=preload("res://scripts/fusion_3d/school_vfx.gd").new()
	foot_circle.name="EquippedAura"
	foot_circle.school=str(equipped.aura)
	foot_circle.kind="rune"
	foot_circle.diameter=1.65
	foot_circle.subtle=true
	foot_circle.opacity=battle_effect_opacity
	foot_circle.position.y=0.045
	add_child(foot_circle)
	foot_circle.visible=battle_mode and not dead
	if dead:model.rotation.z=1.15
func _tint_appearance(theme: String) -> void:
	var palette: Dictionary=get_node("/root/Wardrobe").option("body",theme)
	var hair_color:=Color(str(palette.hair_color))
	var eye_color:=Color(str(palette.eye_color))
	for part in modules:
		if part!="Face" and not str(part).begins_with("Hair."):continue
		var item: MeshInstance3D=modules[part]
		for index in item.mesh.get_surface_count():
			var material:=item.mesh.surface_get_material(index) as StandardMaterial3D
			if material==null:continue
			var name_lower:=material.resource_name.to_lower()
			var tint_hair: bool=(str(part).begins_with("Hair.") and not name_lower.contains("tie")) or name_lower.contains("natural hair")
			if not tint_hair and not name_lower.contains("library iris"):continue
			var colored:=material.duplicate() as StandardMaterial3D
			colored.albedo_color=hair_color if tint_hair else eye_color
			item.set_surface_override_material(index,colored)
func set_head_preview(value: bool) -> void:
	head_preview=value
	if teen!=null:teen.set_head_preview(value);return
	if modules.has("Hat"):modules["Hat"].visible=not value
	if modules.has("Staff"):modules["Staff"].visible=not value
	if modules.has("Hair.Accessory"):modules["Hair.Accessory"].visible=value or str(equipped.get("hairstyle",""))=="f4"
func bone_rotate(name: String, axis: Vector3, angle: float) -> void:
	var index:=skeleton.find_bone(name)
	if index<0:return
	var global_rest:=skeleton.get_bone_global_rest(index)
	var local_axis: Vector3=(global_rest.basis.inverse()*axis).normalized()
	var original: Transform3D=rest[name]
	skeleton.set_bone_pose_rotation(index,original.basis.get_rotation_quaternion()*Quaternion(local_axis,angle))
func bone_pose(name: String,angles: Vector3) -> void:
	if is_custom_model:angles*=0.25 if name.begins_with("upper_arm") or name.begins_with("forearm") else 0.4
	var index:=skeleton.find_bone(name)
	if index<0:return
	var inverse:=skeleton.get_bone_global_rest(index).basis.inverse()
	var original: Transform3D=rest[name]
	var rotation:=Quaternion((inverse*Vector3.RIGHT).normalized(),angles.x)*Quaternion((inverse*Vector3.UP).normalized(),angles.y)*Quaternion((inverse*Vector3.BACK).normalized(),angles.z)
	skeleton.set_bone_pose_rotation(index,original.basis.get_rotation_quaternion()*rotation)
func set_locomotion(in_air: bool,speed_y: float,planar_speed: float=-1.0) -> void:
	if teen!=null:teen.set_locomotion(in_air,speed_y,planar_speed);return
	if airborne and not in_air:landing=1.0
	airborne=in_air
	vertical_speed=speed_y
func _process(delta: float) -> void:
	if skeleton==null:return
	phase+=delta
	if initialized:
		var travel:=Vector2(global_position.x-last_position.x,global_position.z-last_position.z).length()
		motion=lerpf(motion,clampf(travel/maxf(delta,0.001)/Motion.MOVE_SPEED,0,1),minf(delta*9,1))
	initialized=true
	last_position=global_position
	if dead:return
	air_pose=move_toward(air_pose,1.0 if airborne else 0.0,delta*8)
	landing=move_toward(landing,0.0,delta*5)
	var stride:=sin(phase*Motion.WALK_CADENCE)*motion*(1-air_pose)
	bone_pose("thigh.L",Vector3(stride*Motion.HIP_SWING+air_pose*.32+landing*.15,0,0))
	bone_pose("thigh.R",Vector3(-stride*Motion.HIP_SWING-air_pose*.16+landing*.15,0,0))
	bone_pose("shin.L",Vector3(maxf(0,-stride)*Motion.KNEE_SWING+air_pose*.68+landing*.2,0,0))
	bone_pose("shin.R",Vector3(maxf(0,stride)*Motion.KNEE_SWING+air_pose*.58+landing*.2,0,0))
	bone_pose("foot.L",Vector3(-air_pose*.2-stride*.10,0,0))
	bone_pose("foot.R",Vector3(-air_pose*.2+stride*.10,0,0))
	# Raise and open the arms, then sweep the wand forward; hands follow their existing skinned wrist joints.
	bone_pose("upper_arm.L",Vector3(-cast_amount*1.30+cast_sweep*.60-stride*Motion.ARM_SWING-air_pose*.32,cast_amount*.12,cast_amount*.20+air_pose*.23))
	bone_pose("upper_arm.R",Vector3(-cast_amount*1.05+cast_sweep*.28+stride*Motion.ARM_SWING-air_pose*.28,-cast_amount*.18,-cast_amount*.28-air_pose*.23))
	bone_pose("forearm.L",Vector3(-cast_amount*.65+cast_sweep*.36-air_pose*.22,0,0))
	bone_pose("forearm.R",Vector3(-cast_amount*.65+cast_sweep*.25-air_pose*.20,0,0))
	bone_pose("hand.L",Vector3(cast_amount*.18+cast_sweep*.22,cast_amount*.16-cast_sweep*.38,cast_amount*.10))
	bone_pose("hand.R",Vector3(cast_amount*.35,cast_amount*.4,-cast_amount*.18))
	bone_pose("spine",Vector3(-cast_amount*.12+cast_sweep*.14+recoil+landing*.06,cast_amount*.18-cast_sweep*.30,stride*.025))
	bone_pose("head",Vector3(-cast_amount*.03,sin(phase*1.5)*.035*(1-cast_amount),0))
	model.position.y=(absf(stride)*.065+sin(phase*2)*.008-landing*.025)*Motion.SIZE_RATIO
func anchor_global(id: String) -> Vector3:
	if teen!=null:return teen.anchor_global(id)
	if skeleton!=null and id in ["HandGrip","OffHandGrip","StaffSocket","CastRelease"]:
		var bone:=skeleton.find_bone("hand.R" if id=="OffHandGrip" else "hand.L")
		var pose:=skeleton.get_bone_global_pose(bone)
		return skeleton.to_global(pose*release_offset if id=="CastRelease" else pose.origin)
	var points: Dictionary={"HitPoint":Vector3(0,1.45,0),"HeadStatus":Vector3(0,2.7,0),"FootRing":Vector3(0,0.025,0)}
	var point: Vector3=points.get(id,Vector3.ZERO)
	return to_global(point if id=="FootRing" else point*Motion.SIZE_RATIO)
func play_cast(duration: float) -> void:
	if teen!=null:teen.play_cast(duration);return
	if cast_tween!=null and cast_tween.is_valid():cast_tween.kill()
	cast_tween=create_tween()
	cast_sweep=0
	cast_tween.tween_property(self,"cast_amount",1.0,duration*.34).set_trans(Tween.TRANS_SINE)
	cast_tween.tween_interval(duration*.20)
	cast_tween.tween_property(self,"cast_sweep",1.0,duration*.16).set_trans(Tween.TRANS_CUBIC)
	cast_tween.parallel().tween_property(self,"cast_amount",.75,duration*.16)
	cast_tween.tween_property(self,"cast_amount",0.0,duration*.30).set_trans(Tween.TRANS_SINE)
	cast_tween.parallel().tween_property(self,"cast_sweep",0.0,duration*.30)
func hit() -> void:
	if teen!=null:teen.hit();return
	recoil=0.18
	create_tween().tween_property(self,"recoil",0.0,0.4)
func set_alive(alive: bool) -> void:
	if dead == (not alive):return
	dead=not alive
	if teen!=null:
		teen.set_alive(alive)
		if foot_circle!=null:foot_circle.visible=battle_mode and alive
		return
	if life_tween!=null and life_tween.is_valid():life_tween.kill()
	life_tween=create_tween()
	life_tween.tween_property(model,"rotation:z",0.0 if alive else 1.15,0.45)
	foot_circle.visible=battle_mode and alive

func set_battle_mode(value: bool) -> void:
	battle_mode=value
	if foot_circle!=null:foot_circle.visible=battle_mode and not dead


func set_swimming(value: bool) -> void:
	if teen!=null:teen.set_swimming(value)
