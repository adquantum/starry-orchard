extends Node
var town: Node3D
var close_view:=false
var yaw:=0.0
var pitch:=0.27
var captured:=false
var config: Dictionary
func configure(value: Node3D) -> void:
	town=value
	config=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/camera_presentation.json"))
func blocked() -> bool:
	return town==null or town.battle!=null or (is_instance_valid(town.character_library_panel) and town.character_library_panel.visible) or (town.icon_menu!=null and town.icon_menu.is_open()) or town.dialogue.visible or town.party_panel.visible or town.wardrobe_panel.visible or (town.chapter!=null and town.chapter.journal!=null and town.chapter.journal.visible)
func set_capture(value: bool) -> void:
	captured=value
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED if value else Input.MOUSE_MODE_VISIBLE
func toggle_view() -> void:
	close_view=not close_view
	town.overview=false
	set_capture(false)
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			set_capture(false)
		elif event.keycode==KEY_CTRL and not blocked():
			town.overview=false
			close_view=true
			set_capture(not captured)
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and captured and not blocked():
		yaw-=event.relative.x*float(config.mouse_sensitivity)
		pitch=clampf(pitch+event.relative.y*float(config.mouse_sensitivity),-0.08,1.05)
		get_viewport().set_input_as_handled()
func _process(_delta: float) -> void:
	if captured and (blocked() or town.overview):set_capture(false)
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:set_capture(false)
func _exit_tree() -> void:
	set_capture(false)
func movement_direction(input: Vector3) -> Vector3:
	return input.rotated(Vector3.UP,yaw) if close_view else input
func update_camera(_delta: float) -> void:
	var camera: Camera3D=town.camera
	if town.overview:
		camera.fov=48
		var origin:=Vector3.ZERO
		if town.player.position.x>300:origin=town.player.position
		camera.position=origin+Vector3(0,95,170)
		camera.look_at(origin+Vector3(0,0,-35))
	elif not close_view:
		camera.fov=48
		camera.position=town.player.position+Vector3(0,26,34)
		camera.look_at(town.player.position+Vector3(0,1,-4))
	else:
		camera.fov=60
		var pivot: Vector3=town.player.global_position+Vector3(0,1.8*preload("res://scripts/fusion_3d/character_motion.gd").SIZE_RATIO,0)
		var offset:=Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*float(config.third_person_distance)
		var desired:=pivot+offset
		var query:=PhysicsRayQueryParameters3D.create(pivot,desired)
		query.exclude=[town.player.get_rid()]
		var hit:=town.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():desired=hit.position+hit.normal*0.25
		camera.global_position=desired
		camera.look_at(pivot)
