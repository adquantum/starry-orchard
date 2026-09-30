extends Node
## Reuses the production 4v4 stage; exploration remains loaded behind it.
const Stage = preload("res://scenes/fusion_3d/battle_stage.tscn")
const Board = preload("res://scripts/fusion_3d/battle_board.gd")
const StageScript = preload("res://scripts/fusion_3d/battle_stage.gd")
var atlas: Node
var world: Node3D
var site: Dictionary = {}
var site_entries: Array[Dictionary] = []
var selected_site := -1
var board: Node3D
var stage: Node3D
var active := false
var prepared: Node3D
var armed := true
var saved_position := Vector3.ZERO
var saved_yaw := 0.0
var saved_pitch := 0.0
var saved_distance := 9.0
var hidden_canvases: Array[CanvasLayer] = []
var hidden_geometry: Array[GeometryInstance3D] = []
var exit_layer: CanvasLayer
var music: Node
var site_label: Label3D

func install(target: Node3D) -> void:
	prepared = null
	armed = true
	world = target
	site = {}
	site_entries.clear()
	selected_site = -1
	board = null
	site_label = null
	music = null
	var sites: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/world_battle_sites.json"))
	var key: String = str(world.world_root).trim_suffix("/").get_file()
	if not sites.has(key):return
	var definitions: Array = sites[key] if sites[key] is Array else [sites[key]]
	for definition in definitions:
		site = definition
		board = Board.new()
		world.add_child(board)
		board.position = center()
		board.scale = Vector3.ONE * float(site.scale)
		board.setup(StageScript.SLOT_COORDS)
		board.transparency = 0.0
		# Match the production slot foot plane and support walking over the disc.
		var support := StaticBody3D.new()
		support.name = "BattleDiscFloor"
		world.add_child(support)
		support.position = center() + Vector3.UP * 0.10
		var collision := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = float(site.radius)
		cylinder.height = 0.20
		collision.shape = cylinder
		support.add_child(collision)
		var title := Label3D.new()
		site_label = title
		title.text = str(site.name) + "\n走入战斗盘 · 自动入场"
		title.position = center() + Vector3(0, 5, -float(site.radius)-2)
		title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		title.font_size = 44
		title.pixel_size = 0.012
		title.modulate = Color("ffe5a0")
		world.add_child(title)
		world.destinations.append(Vector3(site.approach[0],site.approach[1],site.approach[2]))
		world.destination_names.append(site.name)
		site_entries.append({"config":site,"board":board,"label":site_label})
	_select_site(0)
	for child in world.get_children():
		if child.get_script() == preload("res://scripts/fusion_3d/exploration_music.gd"):music = child

	_prepare()

func _select_site(index: int) -> void:
	if index == selected_site:return
	selected_site = index
	site = site_entries[index].config
	board = site_entries[index].board
	site_label = site_entries[index].label
	if is_instance_valid(prepared):
		# Candidate sites share the demo encounter. Reposition instead of rebuilding eight actors.
		if prepared.encounter_id != str(site.encounter):
			prepared.queue_free()
			prepared = null
			_prepare()
		else:
			prepared.position = center()
			prepared.scale = Vector3.ONE * float(site.scale)

func nearest_site_index() -> int:
	var result := selected_site
	var best := INF
	for i in site_entries.size():
		var point: Array = site_entries[i].config.center
		var distance: float = world.player.position.distance_squared_to(Vector3(point[0],point[1],point[2]))
		if distance < best:
			best = distance
			result = i
	return result

func _prepare() -> void:
	if not is_instance_valid(world) or site.is_empty() or is_instance_valid(prepared):return
	prepared = Stage.instantiate()
	prepared.embedded = true
	prepared.manual_entrance = true
	prepared.encounter_id = site.encounter
	prepared.scale = Vector3.ONE * float(site.scale)
	prepared.position = center()
	var schools := {"fire":&"fire_student","ice":&"ice_guardian","storm":&"storm_duelist","life":&"life_healer","death":&"death_reaper","myth":&"myth_scholar","balance":&"balance_adept"}
	var party: Array[StringName] = [schools.get(atlas.current_school,&"life_healer")]
	for id in [&"fire_student",&"ice_guardian",&"life_healer",&"storm_duelist"]:
		if not party.has(id) and party.size()<4:party.append(id)
	prepared.party = party
	prepared.hide()
	world.add_child(prepared)
	prepared.shell.set_music_paused(true)
	prepared.process_mode = Node.PROCESS_MODE_DISABLED
	print("ATLAS_BATTLE_PREPARED")

func _process(_delta: float) -> void:
	if active or site.is_empty() or not is_instance_valid(world) or atlas.busy:return
	if world.get_node_or_null("CreativeMode") != null and world.get_node("CreativeMode").enabled:return
	var offset: Vector3 = world.player.position-center()
	if Vector2(offset.x,offset.z).length() > float(site.radius)+3.0:armed = true
	if armed:_select_site(nearest_site_index())
	if can_start():start()

func center() -> Vector3:
	return Vector3(site.center[0],site.center[1],site.center[2])

func can_start() -> bool:
	if is_instance_valid(world) and world.get_node_or_null("CreativeMode") != null and world.get_node("CreativeMode").enabled:return false
	return armed and is_instance_valid(prepared) and not active and not site.is_empty() and is_instance_valid(world) and world.ready_world and not atlas.busy and not atlas.wardrobe_panel.visible and Vector2(world.player.position.x-center().x,world.player.position.z-center().z).length() < float(site.radius)+1.0 and absf(world.player.position.y-center().y) < 3.0

func start() -> void:
	if not can_start():return
	active = true
	armed = false
	saved_position = world.player.position
	saved_yaw = world.yaw
	saved_pitch = world.pitch
	saved_distance = world.distance
	world.input_suspended = true
	world.player.velocity = Vector3.ZERO
	board.hide()
	site_label.hide()
	atlas.ui.hide()
	hidden_canvases.clear()
	for child in world.get_children():
		if child is CanvasLayer and child.visible:
			hidden_canvases.append(child)
			child.hide()
	if is_instance_valid(music):music.set_battle(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stage = prepared
	prepared = null
	stage.process_mode = Node.PROCESS_MODE_INHERIT
	stage.entry_origin = (saved_position-center())/float(site.scale)
	stage.entry_player = world.player
	stage.entry_avatar = world.avatar
	stage.entry_camera = world.camera.global_transform.orthonormalized()
	stage.entry_fov = world.camera.fov
	stage.actors[&"P0"].get_node("Body").external.scale = Vector3.ONE * world.explorer_scale / float(site.scale)
	stage.encounter_finished.connect(finish)
	stage.show()
	stage.shell.set_music_paused(false)
	stage._enter_battle()
	# MultiMesh props are not handled by the legacy MeshInstance clearance.
	# Hide only tall nearby batches for the battle camera, then restore them.
	hidden_geometry.clear()
	for child in world.get_children():
		if not child is MultiMeshInstance3D or not child.visible:continue
		var bounds: AABB = child.global_transform * child.get_aabb()
		if bounds.size.y < 6.0:continue
		var nearest := Vector2(clampf(center().x,bounds.position.x,bounds.end.x),clampf(center().z,bounds.position.z,bounds.end.z))
		if nearest.distance_to(Vector2(center().x,center().z)) < 45.0:
			hidden_geometry.append(child)
			child.hide()
	exit_layer = CanvasLayer.new()
	exit_layer.layer = 30
	exit_layer.hide()
	add_child(exit_layer)
	var control := Control.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exit_layer.add_child(control)
	var button := Button.new()
	button.text = "退出演示 · 返回地图"
	control.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	button.offset_left = -115
	button.offset_right = 115
	button.offset_top = 45
	button.offset_bottom = 85
	button.pressed.connect(func():finish(-1))
	stage.entrance_finished.connect(func():
		if is_instance_valid(exit_layer):exit_layer.show())
	print("ATLAS_BATTLE_STARTED ", site.name, " party=", stage.party)

func finish(winner: int) -> void:
	if not active:return
	active = false
	if is_instance_valid(stage):
		stage.hide()
		stage.queue_free()
	stage = null
	if is_instance_valid(exit_layer):exit_layer.queue_free()
	exit_layer = null
	for node in hidden_geometry:
		if is_instance_valid(node):node.show()
	hidden_geometry.clear()
	for canvas in hidden_canvases:
		if is_instance_valid(canvas):canvas.show()
	hidden_canvases.clear()
	board.show()
	site_label.show()
	world.player.position = saved_position
	world.player.velocity = Vector3.ZERO
	world.player.show()
	world.yaw = saved_yaw
	world.pitch = saved_pitch
	world.distance = saved_distance
	world.camera.current = true
	world.input_suspended = false
	atlas.ui.show()
	if is_instance_valid(music):music.set_battle(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	atlas.status.text = "演示结束，已返回战斗盘。" if winner >= 0 else "已退出演示，返回原位置。"
	world.avatar.set_locomotion(false,0,0)
	_prepare.call_deferred()
	print("ATLAS_BATTLE_RETURNED winner=", winner)
