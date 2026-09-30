extends Node3D
## Local opt-in M1 gate. Online sessions are deliberately rejected until run isolation exists.
const Room = preload("res://scripts/tower_v01/tower_room.gd")
const ENTRANCE := Vector3(-153,2,-145)
const ROOM_LAYER := 1 << 19
var world: Node3D
var rooms: Array = []
var inside := false
var busy := false
var prepared := false
var preparation_failed := false
var current_room := -1
var saved: Dictionary = {}
var safe := Vector3.ZERO
var layer: CanvasLayer
var panel: PanelContainer
var status: Label
var enter_button: Button
var next_button: Button
var return_button: Button
var transitions: Array = []
var preparation_ms := 0
var recoveries := 0
var actor_layers: Dictionary = {}
var run_controller: Node
var party_session: Node

func _ready() -> void:
	world.exploration_context = self
	world.camera.cull_mask &= ~ROOM_LAYER
	layer = CanvasLayer.new()
	layer.layer = 35
	add_child(layer)
	panel = PanelContainer.new()
	panel.position = Vector2(24,150)
	layer.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	status = Label.new()
	status.custom_minimum_size = Vector2(420,60)
	column.add_child(status)
	enter_button = _button(column,"确认进入寒冰回响 · 本机测试",enter)
	next_button = _button(column,"前往寒冰 2 层",func(): await move_to(mini(2,current_room+1)))
	return_button = _button(column,"返回洞外",leave)
	_button(column,"开始单人试炼 · 无 AI 伙伴",func():
		if inside and not busy:run_controller.start())
	_button(column,"继续已有测试局",func():
		if inside and not busy:run_controller.resume())
	run_controller = preload("res://scripts/tower_v01/run_controller.gd").new()
	run_controller.tower = self
	add_child(run_controller)
	party_session=preload("res://scripts/tower_v01/party_session.gd").new()
	party_session.name="TowerParty"
	party_session.tower=self
	add_child(party_session)
	_button(column,"双人组队 · 局域网沙盒",func():
		if inside and not busy:run_controller.start())
	panel.hide()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func online() -> bool:
	var atlas := world.get_parent()
	if atlas.get("encounters") != null:
		var net: Node = atlas.encounters.session.net
		return net.connected or net.connecting
	return false

func near_entrance() -> bool:
	var at: Vector3 = world.player.global_position
	return Vector2(at.x-ENTRANCE.x,at.z-ENTRANCE.z).length() <= 15 and absf(at.y-ENTRANCE.y) <= 15

func _process(_delta: float) -> void:
	if not world.ready_world:return
	panel.visible = inside or near_entrance()
	if run_controller.running or run_controller.preparing or run_controller.panel.visible:panel.visible=false
	enter_button.visible = not inside
	next_button.visible = inside and current_room<2 and "--tower-debug-navigation" in OS.get_cmdline_user_args()
	next_button.text="前往寒冰 %d 层" % (current_room+2)
	return_button.visible = inside
	enter_button.disabled = busy or online() or preparation_failed
	next_button.disabled = busy
	return_button.disabled = busy
	if inside:
		status.text = "寒冰回响 · 寒冰 %d 层\n%s · 正式奖励关闭" % [current_room+1,preload("res://scripts/tower_v01/floor_dressing.gd").TITLES[current_room]]
	elif online():status.text = "寒冰回响 · 本机白名单测试\n请在离线测试入口运行；在线副本隔离尚未接入"
	elif preparation_failed:status.text = "准备失败；已保留洞外状态，请检查日志"
	elif busy:status.text = "正在后台准备原始副本资源…\n准备完成后才能传送"
	else:status.text = "寒冰回响 · 本机白名单测试\n复用原始寒冰 1、2 层 · 正式奖励关闭"

func prepare() -> bool:
	if prepared:return true
	if busy or preparation_failed:return false
	busy = true
	var start := Time.get_ticks_msec()
	var highest := 0.0
	for values in world.heights.values():
		for value in values:highest = maxf(highest,float(value))
	var altitude := maxf(300,highest+120)
	for index in 3:
		var room := Room.new()
		room.name = "AuthoredIceFloor%d" % (index+1)
		add_child(room)
		room.hide()
		if not await room.prepare("res://assets/worlds/crazytower_ice_%d/" % (mini(index,1)+1)):
			room.queue_free()
			for previous in rooms:previous.queue_free()
			rooms.clear()
			busy = false
			preparation_failed = true
			return false
		if not room.dress(index):
			preparation_failed=true;busy=false;return false
		room.position = Vector3(ENTRANCE.x,altitude-room.local_bounds.position.y,ENTRANCE.z)
		altitude = room.position.y + room.local_bounds.end.y + 60
		rooms.append(room)
	preparation_ms = Time.get_ticks_msec()-start
	prepared = true
	busy = false
	print("TOWER_PREPARED ms=",preparation_ms," outdoor_max=",highest)
	return true

func enter() -> bool:
	if inside or busy or online() or not near_entrance() or world.input_suspended:return false
	if not await prepare():return false
	# Revalidate after asynchronous preparation: the player may have walked away or connected.
	if online() or not near_entrance() or world.input_suspended:return false
	world.flight.land()
	saved = {"position":world.player.global_position,"mask":world.player.collision_mask,
		"camera_mask":world.camera.cull_mask,"environment":world.camera.environment,
		"yaw":world.yaw,"pitch":world.pitch,"distance":world.distance}
	inside = true
	world.player.collision_mask = ROOM_LAYER
	world.camera.cull_mask = ROOM_LAYER
	actor_layers.clear()
	_set_actor_layers(world.player)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("223848")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9d9e6")
	environment.ambient_light_energy = 0.8
	environment.fog_enabled=true
	environment.fog_density=0.012
	environment.fog_light_color=Color("66899b")
	world.camera.environment = environment
	if not await move_to(0):
		await leave()
		return false
	return true

func move_to(index: int) -> bool:
	if busy or not inside or index < 0 or index >= rooms.size():return false
	busy = true
	world.input_suspended = true
	var started := Time.get_ticks_msec()
	var previous := current_room
	for i in rooms.size():rooms[i].set_active(i == index)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var room: Node3D = rooms[index]
	var origin: Vector3 = room.global_position
	var query := PhysicsRayQueryParameters3D.create(origin+Vector3.UP*15,origin-Vector3.UP*15,ROOM_LAYER)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		for i in rooms.size():rooms[i].set_active(i == previous)
		busy = false
		world.input_suspended = false
		push_error("Tower authored spawn has no verified floor")
		return false
	current_room = index
	world.camera.environment=room.dressing.environment
	safe = hit.position + Vector3.UP*0.12
	world.player.global_position = safe
	world.player.velocity = Vector3.ZERO
	world.swimming = false
	world.avatar.set_swimming(false)
	world.yaw = -float(room.data.attributes.get("PlayerFacing",0))
	world.pitch = -0.35
	world.distance = 12
	_snap_camera()
	await get_tree().physics_frame
	world.input_suspended = false
	busy = false
	transitions.append({"room":index+1,"ms":Time.get_ticks_msec()-started,"position":[safe.x,safe.y,safe.z]})
	print("TOWER_TRANSITION ",JSON.stringify(transitions.back()))
	return true

func leave() -> bool:
	if not inside or busy:return false
	if run_controller.in_battle:return false
	busy = true
	world.input_suspended = true
	for room in rooms:room.set_active(false)
	inside = false
	world.player.collision_mask = int(saved.mask)
	world.camera.cull_mask = int(saved.camera_mask)
	world.camera.environment = saved.environment
	for geometry in actor_layers:
		if is_instance_valid(geometry):geometry.layers = actor_layers[geometry]
	actor_layers.clear()
	world.yaw = saved.yaw
	world.pitch = saved.pitch
	world.distance = saved.distance
	# Return outside the interaction center; R/world navigation remain original after leaving.
	var destination := ENTRANCE + Vector3(0,0,10)
	destination.y = world._height(destination)
	world.player.global_position = destination + Vector3.UP*3
	world._refresh_collisions()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(destination+Vector3.UP*12,destination-Vector3.UP*6,int(saved.mask))
	query.exclude = [world.player.get_rid()]
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	world.player.global_position = hit.position+Vector3.UP*0.12 if not hit.is_empty() else saved.position
	world.player.velocity = Vector3.ZERO
	_snap_camera()
	current_room = -1
	world.input_suspended = false
	busy = false
	print("TOWER_RETURN ",world.player.global_position)
	return true

func _snap_camera() -> void:
	var target: Vector3 = world.player.position+Vector3.UP*1.45*world.explorer_scale
	world.camera.position = target+Basis(Vector3.UP,world.yaw)*Vector3(0,-sin(world.pitch)*world.distance,cos(world.pitch)*world.distance)
	world.camera.look_at(target)
	world.player.reset_physics_interpolation()
	world.camera.reset_physics_interpolation()

func _set_actor_layers(node: Node) -> void:
	if node is GeometryInstance3D:
		actor_layers[node] = node.layers
		node.layers = ROOM_LAYER
	for child in node.get_children():_set_actor_layers(child)

func floor_height(point: Vector3) -> float:
	return rooms[current_room].ground_at(point) if current_room >= 0 else 0

func check_bounds() -> void:
	if current_room < 0:return
	var room: Node3D = rooms[current_room]
	var local: Vector3 = room.to_local(world.player.global_position)
	if local.y < room.local_bounds.position.y-10 or absf(local.x)>500 or absf(local.z)>500:
		recoveries += 1
		reset_to_safe()

func reset_to_safe() -> void:
	world.player.global_position = safe
	world.player.velocity = Vector3.ZERO
	_snap_camera()
