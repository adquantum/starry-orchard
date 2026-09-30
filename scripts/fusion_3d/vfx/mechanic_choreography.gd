extends Node3D
## Event-driven presentation: never edits combat state or status identities.
var stage: Node3D
var arrivals: Array[Node3D] = []
const VISIBLE_KINDS = ["blade","weakness","accuracy_blade","accuracy_weakness","healing_blade","infection","shield","trap","absorb","dot","hot","delay_damage"]

func clear() -> void:
	for item in arrivals:
		if is_instance_valid(item) and not item.get_meta("orbit_adopted",false): item.queue_free()
	arrivals.clear()

func old_token(id: StringName, status_id: int) -> Node3D:
	for item in stage.visuals.status_nodes.get(id, []):
		if is_instance_valid(item) and int(item.get_meta("status_id", -1)) == status_id:
			return item
	return null

# Attached effects inherit the action/turn composition; they never own a shot.
func focus_pair(_from_id: StringName, _to_id: StringName) -> void:
	pass

func focus_status(_id: StringName) -> void:
	pass

func face_camera(item: Node3D) -> void:
	item.look_at(stage.camera.global_position, Vector3.UP, true)
	if item.get_meta("planar_status", false): item.rotate_object_local(Vector3.RIGHT, PI * 0.5)

func school_for(data: Dictionary) -> String:
	var status := StatusInstanceV2.new()
	status.kind = StringName(str(data.get("kind", "")))
	status.set_school_filters(data.get("school_filters", data.get("school_filter", "*")))
	return ArtRegistryV2.status_school_key(status)

func land(id: StringName, data: Dictionary) -> void:
	var kind := str(data.get("kind", ""))
	if kind not in VISIBLE_KINDS or not stage.actors.has(id): return
	if not stage.shot_targets.has(id): await focus_status(id)
	var item: Node3D = stage.visuals.token(self, kind, school_for(data))
	var peers := 0
	for previous in arrivals:
		if is_instance_valid(previous) and previous.visible and previous.get_meta("recipient", &"") == id:
			peers += 1
	item.set_meta("recipient", id)
	arrivals.append(item)
	var at: Vector3 = stage.actors[id].position
	var ratio: float = stage.actor_size_ratio(id)
	var floor_kind := kind in ["dot","hot","delay_damage"]
	var upper_kind: bool = kind in stage.visuals.CHARM_KINDS
	var end_height: float = (2.7 if upper_kind else 0.95) * ratio
	if floor_kind: end_height = 0.08 if kind != "delay_damage" else 0.38 * ratio
	var front: Vector3 = stage.camera.position - at
	front.y = 0
	front = front.normalized().rotated(Vector3.UP, peers * 0.62)
	var group := "floor" if floor_kind else ("upper" if upper_kind else "ward")
	var speed:=0.35 if floor_kind else 0.5
	var status_id:=int(data.get("instance_id",-1))
	var phase: float=atan2(front.x,front.z)-stage.visuals.clock*speed
	if status_id>=0:
		phase=stage.visuals.reserve_orbit(id,status_id,group,phase)
		stage.visuals.register_arrival(id,status_id,item)
		item.set_meta("status_id",status_id)
		var angle: float=phase+stage.visuals.clock*speed
		front=Vector3(sin(angle),0,cos(angle))
		item.set_meta("orbit_angle",phase)
		item.set_meta("orbit_group",group)
		item.set_meta("orbit_height",end_height)
	var destination: Vector3 = at + front * stage.visuals.STATUS_ORBIT_RADIUS + Vector3.UP * end_height
	item.position = destination + Vector3.UP * (0.65 if floor_kind else 0.45)
	if not floor_kind: face_camera(item)
	item.scale = Vector3.ONE * 0.05
	var appear := create_tween().set_parallel(true)
	appear.tween_property(item, "scale", Vector3.ONE * 1.25, 0.23 * stage.cinematic_rate).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if status_id>=0:
		var initial_rotation:=item.quaternion
		appear.tween_method(func(t: float):
			var ease:=t*t*(3.0-2.0*t)
			var angle: float=stage.visuals.orbit_phase(id,status_id,group)+stage.visuals.clock*speed
			var radius: float=stage.visuals.STATUS_ORBIT_RADIUS+0.25*(1.0-ease)
			item.position=at+Vector3(sin(angle)*radius,end_height+0.45*(1.0-ease),cos(angle)*radius)
			item.quaternion=initial_rotation.slerp(Quaternion(Vector3.UP,angle),ease),0.0,1.0,0.55*stage.cinematic_rate)
	else:
		appear.tween_property(item,"position",destination,0.42*stage.cinematic_rate)
	await appear.finished
	if status_id>=0:item.set_meta("follow_orbit",true)
	var settle := create_tween()
	settle.tween_property(item, "scale", Vector3.ONE, 0.16 * stage.cinematic_rate)
	await settle.finished

func _process(_delta: float) -> void:
	if stage == null: return
	for item in arrivals:
		if not is_instance_valid(item) or item.get_meta("orbit_adopted",false) or not item.get_meta("follow_orbit", false): continue
		var id: StringName = item.get_meta("recipient")
		if not stage.actors.has(id): continue
		var group: String=item.get_meta("orbit_group")
		var angle: float = stage.visuals.orbit_phase(id,int(item.get_meta("status_id")),group) + stage.visuals.clock * (0.35 if group == "floor" else 0.5)
		item.position = stage.actors[id].position + Vector3(sin(angle) * stage.visuals.STATUS_ORBIT_RADIUS, item.get_meta("orbit_height"), cos(angle) * stage.visuals.STATUS_ORBIT_RADIUS)
		item.rotation = Vector3(0, angle, 0)

func move_status(data: Dictionary) -> void:
	var from_id := StringName(str(data.get("from_id", "")))
	var to_id := StringName(str(data.get("to_id", "")))
	if not stage.actors.has(from_id) or not stage.actors.has(to_id): return
	await focus_pair(from_id, to_id)
	var old := old_token(from_id, int(data.get("status_id", -1)))
	var school := str(old.get_meta("school_symbol", "all")) if old != null else "all"
	var item: Node3D = stage.visuals.token(self, str(data.get("kind", "shield")), school)
	arrivals.append(item)
	var start: Vector3 = stage.to_local(old.global_position) if old != null else stage.actors[from_id].position + Vector3.UP
	if old != null: old.hide()
	var end: Vector3 = stage.actors[to_id].position + Vector3.UP * 1.3 * stage.actor_size_ratio(to_id)
	item.position = start
	face_camera(item)
	var flight := create_tween()
	flight.tween_method(func(t: float):
		item.position = start.lerp(end, t) + Vector3.UP * sin(t * PI) * 2.2
		face_camera(item), 0.0, 1.0, 0.95 * stage.cinematic_rate).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await flight.finished
	var shrink := create_tween()
	shrink.tween_property(item, "scale", Vector3.ONE * 0.05, 0.18 * stage.cinematic_rate)
	await shrink.finished
	item.hide()
	await focus_status(to_id)
	await land(to_id, {"kind":data.get("kind", "shield"), "school_filter":school, "instance_id":data.get("status_id", -1)})

func soul_texture(asset: String) -> Texture2D:
	return preload("res://scripts/fusion_3d/vfx/painted_particle_assets.gd").texture(asset)

func soul_sprite(parent: Node3D, asset: String, height: float) -> Sprite3D:
	var sprite:=Sprite3D.new()
	sprite.texture=soul_texture(asset)
	sprite.pixel_size=height/float(sprite.texture.get_height())
	sprite.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.shaded=false
	sprite.no_depth_test=false
	sprite.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow:=ShaderMaterial.new()
	glow.shader=preload("res://scripts/fusion_3d/vfx/soul_glow.gdshader")
	glow.set_shader_parameter("painted_sprite",sprite.texture)
	glow.set_shader_parameter("glow_color",Color("ff426d") if asset=="blood" else Color("bb91ff"))
	glow.set_shader_parameter("energy",1.3 if asset=="blood" else 1.7)
	sprite.material_override=glow
	parent.add_child(sprite)
	return sprite

func sacrifice(id: StringName, on_formed: Callable=Callable()) -> void:
	if not stage.actors.has(id): return
	await focus_status(id)
	var origin: Vector3 = stage.actors[id].position + Vector3.UP * 1.5 * stage.actor_size_ratio(id)
	var group := Node3D.new()
	group.name="SacrificeBloodCrystal"
	add_child(group)
	var crown:=origin+Vector3.UP*1.6
	var drop:=soul_sprite(group,"blood",1.8)
	drop.position=crown
	drop.scale=Vector3.ONE*0.01
	var body: Node3D=stage.actors[id].get_node("Body")
	var motion := create_tween().set_parallel(true)
	motion.tween_property(drop,"scale",Vector3.ONE,1.65*stage.cinematic_rate).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	motion.tween_method(func(value: float):drop.material_override.set_shader_parameter("energy",value),0.8,1.6,1.65*stage.cinematic_rate)
	for index in 12:
		var piece:=soul_sprite(group,"shard",0.43+0.06*float(index%3))
		piece.flip_h=index%2==1
		var angle := float(index) * TAU / 12.0
		piece.position = origin+Vector3(cos(angle)*0.65,-0.55,sin(angle)*0.65)
		motion.tween_method(func(t: float):
			var turn:=angle+t*2.0
			piece.position=origin.lerp(crown,t)+Vector3(cos(turn),0,sin(turn))*0.65*(1-t)
			piece.scale=Vector3.ONE*(1.0-t*0.9),0.0,1.0,1.5*stage.cinematic_rate).set_delay(index*0.012*stage.cinematic_rate)
	await motion.finished
	for child in group.get_children():
		if child!=drop:child.hide()
	# One cost-feedback beat when the crystal finishes forming.
	if on_formed.is_valid():on_formed.call()
	else:body.hit()
	var pulse:=create_tween().set_parallel(true)
	pulse.tween_property(drop,"scale",Vector3.ONE*1.13,0.12*stage.cinematic_rate)
	pulse.tween_method(func(value: float):drop.material_override.set_shader_parameter("energy",value),1.6,3.0,0.12*stage.cinematic_rate)
	await pulse.finished
	drop.hide()
	var burst:=create_tween().set_parallel(true)
	for index in 12:
		var piece:=soul_sprite(group,"shard",0.36+0.05*float(index%3))
		piece.flip_h=index%2==1
		piece.modulate=Color("ffafc5")
		piece.position=crown
		var angle:=float(index)*TAU/12.0
		burst.tween_property(piece,"position",crown+Vector3(cos(angle)*1.15,sin(angle*3.0)*0.65,sin(angle)*1.15),0.38*stage.cinematic_rate)
		burst.tween_property(piece,"scale",Vector3.ONE*0.01,0.38*stage.cinematic_rate)
	await burst.finished
	group.queue_free()

func remove_status(data: Dictionary) -> void:
	var id := StringName(str(data.get("unit_id", "")))
	var item := old_token(id, int(data.get("status_id", -1)))
	if item == null or not stage.actors.has(id): return
	if not stage.shot_targets.has(id): await focus_status(id)
	item.set_meta("choreography_locked", true)
	var fade := create_tween().set_parallel(true)
	fade.tween_property(item, "position:y", item.position.y + 0.5, 0.36 * stage.cinematic_rate)
	fade.tween_property(item, "scale", Vector3.ONE * 0.01, 0.36 * stage.cinematic_rate).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await fade.finished
	item.hide()

func present(event: BattleEventV2) -> bool:
	match event.type:
		&"StatusApplied":
			await land(StringName(str(event.payload.get("target_id", ""))), event.payload.get("status", {}))
			return true
		&"StatusStolen", &"StatusTransferred":
			await move_status(event.payload)
			return true
		&"StatusRemoved":
			await remove_status(event.payload)
	return false
