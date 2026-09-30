extends RefCounted
## Single presentation timeline. Network readiness remains with the session.
static func face(body: Node3D, point: Vector3) -> void:
	if body.has_method("face_center"):body.face_center(point)
	elif body.global_position.distance_squared_to(point)>0.001:
		body.look_at(Vector3(point.x,body.global_position.y,point.z))

static func locomotion(body: Node3D, speed: float, moving: bool) -> void:
	if "external" in body and is_instance_valid(body.external):
		body.external.set_locomotion(false,0,speed)
	elif body.has_method("set_locomotion"):body.set_locomotion(false,0,speed)
	elif "animation" in body and body.animation!=null:
		if moving:
			if not body.get_meta("arrival_running",false):
				for clip in body.animation.get_animation_list():
					if "anim_004_" in clip:
						body.animation.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
						body.animation.play(clip,0.15);break
			body.animation.speed_scale=clampf(speed/5.0,0.3,1.5)
		else:
			body.animation.speed_scale=1.0
			if not body.idle.is_empty():body.animation.play(body.idle,0.15)
	body.set_meta("arrival_running",moving)

static func play(stage: Node3D, origins: Dictionary, move_camera: bool, existing_board: bool=false, explorer: Node3D=null, avatar: Node3D=null) -> void:
	stage.arrival_token+=1
	var token: int=stage.arrival_token
	stage.arrival_active=true;stage.entering=true
	stage.cancel_camera_action()
	if stage.shot_tween!=null and stage.shot_tween.is_valid():stage.shot_tween.kill()
	var cfg: Dictionary=stage.camera_config.get("arrival",{})
	var seconds: float=float(cfg.get("seconds",2.4))*stage.entrance_scale
	var movement_end:=float(cfg.get("movement_end",0.9))
	var target_local:=Transform3D.IDENTITY
	target_local.origin=stage.planning_camera_position()
	target_local=target_local.looking_at(stage.planning_camera_focus(),Vector3.UP)
	var target_camera: Transform3D=(stage.global_transform*target_local).orthonormalized()
	var start_camera: Transform3D=stage.entry_camera.orthonormalized() if move_camera else target_camera
	var start_fov: float=stage.entry_fov if move_camera else stage.planning_camera_fov()
	var tracks: Array[Dictionary]=[]
	for unit in stage.engine.state.units:
		var actor: Node3D=stage.actors[unit.id]
		var body: Node3D=actor.get_node("Body")
		var destination: Vector3=stage.to_global(stage.SLOT_COORDS[unit.id])
		var origin: Vector3=origins.get(str(unit.id),actor.global_position)
		if is_instance_valid(explorer) and unit.id==&"P0":
			actor.hide();actor=explorer;body=avatar;origin=explorer.global_position
		actor.global_position=destination;face(body,stage.to_global(Vector3.ZERO))
		var final_yaw:=body.rotation.y
		actor.global_position=origin;face(body,destination)
		tracks.append({"actor":actor,"body":body,"from":origin,"to":destination,"yaw":body.rotation.y,"end_yaw":final_yaw})
	stage.center_pointer.hide()
	stage.arena_surface.set_arrival_progress(0.0,existing_board)
	if move_camera:
		stage.camera.global_transform=start_camera;stage.camera.fov=start_fov;stage.camera.current=true
	var elapsed:=0.0
	var max_frame:=0.0
	while elapsed<seconds:
		if not is_instance_valid(stage) or stage.arrival_token!=token:return
		var t:=clampf(elapsed/maxf(seconds,0.001),0,1)
		stage.arena_surface.set_arrival_progress(t,existing_board)
		var cam_t:=smoothstep(0.08,0.94,t)
		if move_camera:
			stage.camera.global_transform=start_camera.interpolate_with(target_camera,cam_t).orthonormalized()
			stage.camera.fov=lerpf(start_fov,stage.planning_camera_fov(),cam_t)
		var u:=clampf(t/movement_end,0,1)
		var q:=maxf(0,u-0.8)
		var distance_t:=u/0.9 if u<0.8 else (0.8+q-q*q/0.4)/0.9
		var velocity_t:=1.0/0.9 if u<0.8 else (1.0-q/0.2)/0.9
		for track in tracks:
			var actor: Node3D=track.actor;var body: Node3D=track.body
			actor.global_position=Vector3(track.from).lerp(track.to,distance_t)
			body.rotation.y=lerp_angle(track.yaw,track.end_yaw,smoothstep(0.78,1.0,u))
			var speed:=Vector3(track.from).distance_to(track.to)*velocity_t/maxf(seconds*movement_end,0.001)
			locomotion(body,speed,u<1.0 and speed>0.05)
		await stage.get_tree().process_frame
		if not is_instance_valid(stage):return
		var delta: float=stage.get_process_delta_time()
		max_frame=maxf(max_frame,delta)
		elapsed+=delta
	if stage.arrival_token!=token:return
	for track in tracks:
		track.actor.global_position=track.to;track.body.rotation.y=track.end_yaw
		locomotion(track.body,0.0,false)
	if is_instance_valid(explorer):explorer.hide();stage.actors[&"P0"].show()
	stage.arena_surface.set_arrival_progress(1.0,existing_board)
	stage.arrival_active=false
	if move_camera:stage.set_planning_camera()
	if OS.get_cmdline_user_args().has("--battle-camera-debug"):
		print("BATTLE_ARRIVAL ",JSON.stringify({"seconds":elapsed,"max_frame_ms":max_frame*1000,"existing_board":existing_board,"camera":"exploration_to_planning" if move_camera else "observer"}))

