extends Node
const Library=preload("res://scripts/fusion_3d/character_library.gd")
@export var max_flight_speed:=40.0
@export var boost_impulse:=14.0
@export var boost_cooldown:=0.6
@export var takeoff_impulse:=90.0
var boost_remaining:=0.0
var has_boosted:=false
var world:Node3D
var equipped_id:=""
var wings:Node3D
var wing_player:AnimationPlayer
var flying:=false
var speed:=0.0
var flap_time:=0.0
var flight_age:=0.0
var last_space:=-10.0
var bound_teen:Node3D
var preview_owned:=false
var wing_clip:=""
var wing_skeleton:Skeleton3D
var anchor_bone:=-1
var profile:Dictionary={}
var flap_phase:=0.0
func equip(id:String) -> void:
	land()
	_restore_back_attachment()
	if is_instance_valid(wings):wings.queue_free()
	wings=null;wing_player=null;wing_skeleton=null;anchor_bone=-1;profile={};wing_clip=""
	equipped_id=id
	if not is_instance_valid(world.avatar) or world.avatar.teen==null:return
	bound_teen=world.avatar.teen
	if id.is_empty():return
	var entry:Dictionary=Library.entry(id)
	if entry.is_empty():
		equipped_id=""
		return
	for item in JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/wing_mounts.json")):
		if item.id==id:profile=item;break
	if profile.is_empty():
		equipped_id=""
		return
	wings=Node3D.new();wings.name="FlightWings";world.avatar.add_child(wings)
	var model:Node3D=load(entry.model).instantiate();wings.add_child(model)
	model.rotation.y=deg_to_rad(float(profile.get("yaw",90)))
	model.scale=Vector3.ONE*float(profile.get("scale",0.5))
	wing_skeleton=bound_teen.find_kind(model,"Skeleton3D") as Skeleton3D
	anchor_bone=wing_skeleton.find_bone(str(profile.get("anchor_bone","Bone_000")))
	wing_player=bound_teen.find_kind(model,"AnimationPlayer") as AnimationPlayer
	_set_wing_clip("000")
	if bound_teen.attachments.has("teen_back"):bound_teen.attachments.teen_back.hide()

func _restore_back_attachment() -> void:
	if is_instance_valid(bound_teen) and bound_teen.attachments.has("teen_back"):
		bound_teen.attachments.teen_back.show()
func _set_wing_clip(code:String) -> void:
	if wing_player==null:return
	if profile.get("procedural_flap",false):wing_player.stop();return
	for clip in wing_player.get_animation_list():
		if str(clip).contains("anim_"+code+"_"):
			if wing_clip!=clip or not wing_player.is_playing():
				wing_player.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
				wing_player.play(clip,0.12);wing_clip=clip
			return
func space_pressed() -> void:
	var now:=Time.get_ticks_msec()/1000.0
	if now-last_space<0.32:
		if flying:land()
		else:take_off()
		last_space=-10
	else:last_space=now
func take_off() -> void:
	if equipped_id.is_empty() or not is_instance_valid(wings):return
	flying=true;flight_age=0;speed=0;flap_time=0
	boost_remaining=0;has_boosted=false
	world.swimming=false;world.avatar.set_swimming(false)
	world.player.velocity+=Vector3.UP*takeoff_impulse
func flap() -> void:
	if not flying or boost_remaining>0:return
	var direction:Vector3=-world.camera.global_basis.z.normalized()
	world.player.velocity=(world.player.velocity+direction*boost_impulse).limit_length(max_flight_speed)
	flap_time=0.6;boost_remaining=boost_cooldown;has_boosted=true
	speed=world.player.velocity.length()
func land() -> void:
	flying=false;flap_time=0;speed=0
	boost_remaining=0;has_boosted=false
	if is_instance_valid(world.avatar):world.avatar.rotation.x=0;world.avatar.rotation.z=0
	if is_instance_valid(bound_teen) and preview_owned:bound_teen.preview_animation("")
	preview_owned=false
	_set_wing_clip("000")
func update_visual(delta:float) -> void:
	if equipped_id.is_empty():
		if world.avatar.teen!=bound_teen:
			_restore_back_attachment()
			bound_teen=world.avatar.teen
			_restore_back_attachment()
		return
	if world.avatar.teen!=bound_teen or not is_instance_valid(wings):equip(equipped_id)
	if not is_instance_valid(wings):return
	# Cancel mount root motion and follow the animated back socket in avatar space.
	wings.visible=not world.swimming
	if wing_player!=null:wing_player.speed_scale=(1.8 if flap_time>0 else 0.3) if flying else 0.7
	if flying and is_instance_valid(bound_teen):
		var clip="teenelf"+str(bound_teen.outfit.gender)+"_chibang_00"
		if not bound_teen.animation_key(clip).is_empty():
			if bound_teen.preview_clip!=clip:bound_teen.preview_animation(clip)
			bound_teen.player.get_animation(bound_teen.animation_key(clip)).loop_mode=Animation.LOOP_LINEAR
			preview_owned=true
		var look:Vector3=-world.camera.global_basis.z.normalized()
		var glide_lean:=lerpf(-5.0,-55.0+rad_to_deg(asin(clampf(look.y,-1,1)))*0.8,clampf(speed/18.0,0,1))
		world.avatar.rotation.x=lerpf(world.avatar.rotation.x,deg_to_rad(glide_lean),1-exp(-6*delta))
		_set_wing_clip(str(profile.get("flap_clip","004")) if flap_time>0 else str(profile.get("glide_clip","013")))
	else:_set_wing_clip("000")
	align_to_back()
func align_to_back() -> void:
	if not is_instance_valid(bound_teen) or not is_instance_valid(wing_skeleton) or anchor_bone<0:return
	var skeleton:Skeleton3D=bound_teen.skeleton
	# Wardrobe rebuilds remove the old avatar before the next physics rebind.
	if not skeleton.is_inside_tree():return
	var back:int=skeleton.find_bone(str(bound_teen.rig.sockets["15"].bone))
	if back<0:return
	var offset:Array=profile.get("offset",[0,0,0])
	var target:Vector3=world.avatar.to_local(skeleton.to_global(skeleton.get_bone_global_pose(back).origin))+Vector3(float(offset[0]),float(offset[1]),0.24+float(offset[2]))
	var at:Vector3=world.avatar.to_local(wing_skeleton.to_global(wing_skeleton.get_bone_global_pose(anchor_bone).origin))
	# Some source mounts have an off-center parent bone. Use the two wing
	# roots for lateral centering without changing the approved height/depth.
	var center_bones:Array=profile.get("lateral_center_bones",[])
	if not center_bones.is_empty():
		var center_x:=0.0
		var count:=0
		for bone_name in center_bones:
			var bone:int=wing_skeleton.find_bone(str(bone_name))
			if bone<0:continue
			center_x+=world.avatar.to_local(wing_skeleton.to_global(wing_skeleton.get_bone_global_pose(bone).origin)).x
			count+=1
		if count>0:at.x=center_x/count
	wings.position+=target-at
func _process(delta:float) -> void:
	if not is_instance_valid(wings):return
	if profile.get("procedural_flap",false):
		# This legacy mount folds its two wing roots forward in every native clip.
		# Animate its original rig from the symmetric rest pose for flight.
		flap_phase+=delta*(14.0 if flap_time>0 else 2.0)
		wing_skeleton.reset_bone_poses()
		for pair in [["Bone_000",1.0],["Bone_005",-1.0]]:
			var bone:int=wing_skeleton.find_bone(pair[0])
			var angle:float=(sin(flap_phase)*0.5 if flap_time>0 else 0.12) if flying else 0.8
			wing_skeleton.set_bone_pose_rotation(bone,Quaternion(Vector3.RIGHT if flying else Vector3.UP,angle*float(pair[1])))
	align_to_back()
func step(delta:float,axis:Vector2) -> void:
	flight_age+=delta;flap_time=maxf(0,flap_time-delta)
	boost_remaining=maxf(0,boost_remaining-delta)
	var forward:=Basis(Vector3.UP,world.yaw)*Vector3.FORWARD
	var right:=Basis(Vector3.UP,world.yaw)*Vector3.RIGHT
	var steering:Vector3=(forward+right*axis.x*0.6).normalized()
	if has_boosted:
		var look:Vector3=-world.camera.global_basis.z.normalized()
		world.player.velocity=glide_velocity(world.player.velocity,look,delta,axis.y>0)
	else:
		# A one-shot vertical launch, then smooth deceleration into the normal glide.
		world.player.velocity.y=move_toward(world.player.velocity.y,-1.2,delta*90.0)
	# Do not immediately erase the requested launch impulse with the cruise limit.
	if has_boosted or flight_age>=1.0:world.player.velocity=world.player.velocity.limit_length(max_flight_speed)
	speed=world.player.velocity.length() if has_boosted else 0.0
	world.player.move_and_slide()
	world.avatar.rotation.y=lerp_angle(world.avatar.rotation.y,atan2(-steering.x,-steering.z),1-exp(-5*delta))
	world.avatar.rotation.z=lerpf(world.avatar.rotation.z,-axis.x*0.25*clampf(speed/14.0,0,1),1-exp(-5*delta))
	if world.player.is_on_floor() and flight_age>0.4:land()
	if world.player.position.y<float(world.water_config.sea_level)-0.4*world.explorer_scale:land()
	if world.player.is_on_wall():speed=maxf(0,speed-delta*30)

static func glide_velocity(velocity:Vector3,look:Vector3,delta:float,braking:bool=false) -> Vector3:
	# Camera steering redirects existing momentum. Gravity supplies dive speed
	# and removes climbing speed; looking upward cannot create free lift.
	var magnitude:=velocity.length()
	if magnitude<3.0:
		velocity.x=move_toward(velocity.x,0,delta*1.6)
		velocity.z=move_toward(velocity.z,0,delta*1.6)
		velocity.y=move_toward(velocity.y,-1.2,delta*3.5)
		return velocity
	velocity=velocity.lerp(look.normalized()*magnitude,1-exp(-2.0*delta))
	velocity.y-=4.0*delta
	velocity*=exp(-(1.4 if braking else 0.045)*delta)
	return velocity
