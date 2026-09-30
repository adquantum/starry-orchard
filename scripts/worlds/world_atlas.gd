extends Node

const Journey = preload("res://scripts/worlds/orchard_journey_rules.gd")
var orchard_main_mode := false
var journey_admitted := false
var journey_state: Dictionary = {}
var journey_ui: Node
var journey_switching := false
var pending_journey_destination := ""

const MobileControls = preload("res://scripts/worlds/mobile_controls.gd")
const CharacterStart = preload("res://scripts/worlds/orchard_character_start.gd")

var debug_panel: PanelContainer
var loadout: RefCounted
var game_menu: Node
var frost_npcs: Node
var world_chat: Node
var empower_reward_popup:Node
var mobile_controls: CanvasLayer
var player_minimap: Control
var MAPS: Array = []
var category_picker: OptionButton

var encounters: Node
var world: Node3D
var map_picker: OptionButton
var region_picker: OptionButton
var character_library_panel: Control
var first_entry_guide: Control
var library_button: Button
var wardrobe_panel: Control
var wardrobe_button: Button
var status: Label
var size_label: Label
var size_slider: HSlider
var ui: Control
var busy := false
var current_map := -1
var current_school := "life"
var appearance_loaded := false
var character_size := 2.0
var preferences := ConfigFile.new()
var wing_mounts:Array=[]
var wing_label:Label
var equipped_wing:=""
var unlocked_wings:Array[String]=[]
var wing_request_pending:=false
var test_mode := false
var return_states: Dictionary = {}
var exit_pending:=false
var previous_auto_accept_quit:=true

func _l(zh: String,en: String) -> String:
	return en if Locale.locale == "en" else zh

func _map_name(index: int) -> String:
	var original:=str(MAPS[index][0])
	if Locale.locale != "en":return original
	var names:={"哈奇小镇":"Haqi Town","拉斐尔城堡 · PVP":"Raphael Castle · PvP","冰霜岛":"Frost Island","火鸟岛":"Phoenix Island","黑暗森林":"Dark Forest","古埃及岛":"Ancient Egypt Island","新手岛":"Beginner Island","云端要塞":"Cloud Fortress","星界果园":"Starry Orchard"}
	return str(names.get(original,original))

func _ready() -> void:
	previous_auto_accept_quit=get_tree().auto_accept_quit
	get_tree().auto_accept_quit=false
	var catalog_path := "res://resources/fusion_3d/mobile_lite/world_atlas_catalog.json" if MobileControls.should_enable() else "res://resources/fusion_3d/world_atlas_catalog.json"
	MAPS = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
	test_mode = "--atlas-test" in OS.get_cmdline_user_args()
	preferences.load("user://island_explorer.cfg")
	character_size = clampf(float(preferences.get_value("exploration", "character_size", 2.0)), 1.0, 3.0)
	loadout=preload("res://scripts/worlds/island_loadout.gd").new()
	loadout.setup(Accounts.path_for("academy_custom_decks.json"),str(Accounts.active_character.get("school","life")))
	current_school=loadout.school
	appearance_loaded=true
	_build_ui()
	empower_reward_popup=preload("res://scripts/worlds/empower_reward_popup.gd").new()
	add_child(empower_reward_popup);empower_reward_popup.setup(self)
	var progression_callback:=Callable(self,"_on_progression_changed")
	if Accounts.has_signal("progression_changed") and not Accounts.is_connected("progression_changed",progression_callback):
		Accounts.progression_changed.connect(progression_callback)
	_on_progression_changed(Accounts.progression_snapshot)
	encounters = preload("res://scripts/worlds/island_encounters.gd").new()
	# RPC paths must survive different login/UI node creation histories on each peer.
	encounters.name = "IslandEncounters"
	encounters.atlas = self
	add_child(encounters)
	game_menu=preload("res://scripts/worlds/island_game_menu.gd").new()
	add_child(game_menu)
	game_menu.setup(self,loadout)
	world_chat=preload("res://scripts/worlds/world_chat.gd").new()
	add_child(world_chat)
	world_chat.setup(self,encounters.session)
	player_minimap=preload("res://scripts/worlds/player_minimap.gd").new()
	player_minimap.atlas=self;player_minimap.name="PlayerMinimap";ui.add_child(player_minimap)
	if MobileControls.should_enable():
		mobile_controls=MobileControls.new()
		add_child(mobile_controls)
		mobile_controls.setup(self)
		player_minimap.set_mobile_layout(true)
	if test_mode:
		var store := get_node("/root/Wardrobe")
		store.save_enabled = false
		store.save_path = "user://island_explorer_test_wardrobe.json"
		store.outfits = {"life": store.default_outfit("life")}
		appearance_loaded = true
		character_size = 2.0
		_run_validation.call_deferred()
	else:
		journey_admitted = bool(Accounts.progression_snapshot.get("orchard_journey", {}).get("admitted", false))
		var spawn_index:=0
		var section := _character_preference_section()
		var startup_map := "star_orchard.tscn" if "--orchard-editor" in OS.get_cmdline_user_args() else (CharacterStart.startup_map(Accounts.snapshot(), str(preferences.get_value(section,"map_path","")), MAPS) if journey_admitted else CharacterStart.MAP)
		orchard_main_mode = journey_admitted and "star_orchard.tscn" in startup_map and bool(preferences.get_value(section,"orchard_main_mode",false))
		for index in MAPS.size():
			if startup_map in str(MAPS[index][1]):spawn_index=index;break
		if journey_admitted and not "star_orchard.tscn" in str(MAPS[spawn_index][1]) and str(MAPS[spawn_index][1]) == str(preferences.get_value(section,"map_path","")):
			var saved: Variant = preferences.get_value(section,"world_state",{})
			if saved is Dictionary and saved.get("position") is Vector3 and (saved.position as Vector3).is_finite():
				return_states[spawn_index] = saved
		switch_map.call_deferred(spawn_index)

func _button(parent: Node, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_ui() -> void:
	wing_mounts=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/wing_mounts.json"))
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var panel := PanelContainer.new()
	debug_panel=panel
	panel.hide()
	ui.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -760
	panel.offset_right = -22
	panel.offset_top = 20
	var box := StyleBoxFlat.new()
	box.bg_color = Color("122332ed")
	box.border_color = Color("bd9c63")
	box.set_border_width_all(1)
	box.set_corner_radius_all(10)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var header := Label.new()
	header.text = _l("世界旅行  /  世界与副本 · 同一套穿搭","World Travel / Worlds and Instances · One Outfit")
	header.add_theme_font_size_override("font_size", 20)
	column.add_child(header)
	var row := HBoxContainer.new()
	column.add_child(row)
	category_picker = OptionButton.new()
	category_picker.custom_minimum_size = Vector2(92,38)
	category_picker.add_item(_l("世界","Worlds"))
	category_picker.add_item(_l("副本","Instances"))
	category_picker.item_selected.connect(_select_category)
	row.add_child(category_picker)
	map_picker = OptionButton.new()
	map_picker.custom_minimum_size = Vector2(215, 38)
	map_picker.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_picker.get_popup().max_size = Vector2i(720,600)
	_refresh_map_picker(0)
	map_picker.item_selected.connect(func(local_index: int):switch_map(map_picker.get_item_id(local_index)))
	row.add_child(map_picker)
	region_picker = OptionButton.new()
	region_picker.custom_minimum_size.x = 170
	region_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_picker.item_selected.connect(_select_region)
	row.add_child(region_picker)
	wardrobe_button = _button(row, _l("衣橱  [B]","Wardrobe [B]"), toggle_wardrobe)
	var wing_row:=HBoxContainer.new();column.add_child(wing_row)
	_button(wing_row,_l("◀ 翅膀","◀ Wings"),func():_cycle_wing(-1))
	wing_label=Label.new();wing_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;wing_label.text=_l("未装备 · 击败地图翼 Boss 解锁","None equipped · Defeat a wing boss to unlock");wing_row.add_child(wing_label)
	_button(wing_row,_l("翅膀 ▶","Wings ▶"),func():_cycle_wing(1))
	var help:=Label.new();help.text=_l("双空格起飞 / 收翼 · 右键振翅加速","Double tap Space to fly / land · Right click to flap faster");wing_row.add_child(help)
	var settings := HBoxContainer.new()
	column.add_child(settings)
	size_label = Label.new()
	settings.add_child(size_label)
	size_slider = HSlider.new()
	size_slider.min_value = 1.0
	size_slider.max_value = 3.0
	size_slider.step = 0.1
	size_slider.value = character_size
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.custom_minimum_size.x = 160
	size_slider.value_changed.connect(_set_size)
	settings.add_child(size_slider)
	_button(settings, _l("恢复原模型尺寸","Reset character size"), func():size_slider.value = 2.0)
	_button(settings, _l("账号 / 角色","Account / Character"), _open_accounts)
	status = Label.new()
	status.text = _l("正在准备地图…","Preparing map…")
	status.add_theme_font_size_override("font_size", 15)
	column.add_child(status)
	library_button = _button(column,_l("怪物 / NPC 图鉴  [N]","Monster / NPC Library [N]"),toggle_character_library)
	size_label.text = _l("人物大小  %.1f×","Character size  %.1f×") % (character_size / 2.0)
	wardrobe_panel = preload("res://scripts/fusion_3d/wardrobe_panel.gd").new()
	ui.add_child(wardrobe_panel)
	wardrobe_panel.hide()
	wardrobe_panel.visibility_changed.connect(_wardrobe_visibility_changed)

func _refresh_map_picker(category: int) -> void:
	map_picker.clear()
	var kind := "instance" if category == 1 else "world"
	for index in MAPS.size():
		if str(MAPS[index][2]) == kind:
			map_picker.add_item(_map_name(index),index)
			map_picker.get_popup().set_item_tooltip(map_picker.item_count-1,str(MAPS[index][1]).get_file().trim_suffix(".tscn"))

func _select_category(category: int) -> void:
	if busy or (encounters != null and encounters.active):return
	_refresh_map_picker(category)
	if map_picker.item_count>0:switch_map(map_picker.get_item_id(0))

func switch_map(index: int) -> void:
	if (encounters != null and encounters.active) or busy or index < 0 or index >= MAPS.size():return
	if index == current_map and not journey_switching:return
	if current_map >= 0 and not test_mode and not journey_switching and not journey_admitted and not "--orchard-editor" in OS.get_cmdline_user_args():
		game_menu.message.text = "请先完成西岛五课，再与山顶水晶交互。"
		return
	# Cloud presence is connected automatically on entry. Leaving a world already
	# disconnects it in _prepare_scene_exit(), so it must not block travel.
	if encounters.session.net.lan_debug and (encounters.session.net.connected or encounters.session.net.connecting):
		game_menu.message.text=_l("联机期间请留在寒冰岛；离开房间后可以切换世界。","Stay on Frost Island while connected. Leave the room before changing worlds.")
		return
	busy = true
	if is_instance_valid(world) and not await _prepare_scene_exit():
		busy=false;return
	var loading=preload("res://scripts/worlds/world_loading.gd").obtain(get_tree())
	loading.begin(_l("正在前往 ","Traveling to ")+_map_name(index)+"…",null,str(MAPS[index][1]))
	await get_tree().process_frame
	await get_tree().process_frame
	map_picker.disabled = true
	category_picker.disabled = true
	region_picker.disabled = true
	wardrobe_button.disabled = true
	wardrobe_panel.hide()
	if library_is_open():character_library_panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	status.text = _l("正在前往 ","Traveling to ") + _map_name(index) + "…"
	if is_instance_valid(world):
		if is_instance_valid(frost_npcs):frost_npcs.close()
		return_states[current_map] = {"position":world.player.position, "yaw":world.yaw, "pitch":world.pitch, "distance":world.distance, "region":world.tour_index}
		world.input_suspended = true
		world.queue_free()
		await get_tree().process_frame
	exit_pending=false
	if not "star_orchard.tscn" in str(MAPS[index][1]):orchard_main_mode = false
	elif not journey_switching and current_map >= 0 and journey_admitted:orchard_main_mode = true
	world = load(MAPS[index][1]).instantiate()
	world.set_meta("tutorial_instance", "star_orchard.tscn" in str(MAPS[index][1]) and not orchard_main_mode and not "--orchard-editor" in OS.get_cmdline_user_args())
	world.set_meta("tutorial_distant_main", bool(preferences.get_value("graphics", "tutorial_distant_main", false)))
	world.production_mode=true
	world.explorer_scale = character_size
	world.use_session_appearance = appearance_loaded
	world.session_school = current_school
	add_child(world)
	while not world.ready_world:
		loading.report(world.loading_progress)
		await get_tree().process_frame
	if is_instance_valid(mobile_controls):mobile_controls.bind_world(world)
	world.flight.equip(equipped_wing)
	current_school = world.avatar.school_id
	var player_name:=Label3D.new()
	player_name.set_script(preload("res://scripts/worlds/player_world_name.gd"))
	player_name.name="ExplorationPlayerName"
	world.avatar.add_child(player_name)
	appearance_loaded = true
	get_node("/root/Wardrobe").save_enabled = not test_mode
	current_map = index
	var orchard_campaign: bool = "star_orchard.tscn" in str(MAPS[index][1]) and preload("res://scripts/worlds/star_orchard_features.gd").WORLD1_ENABLED and not "--orchard-editor" in OS.get_cmdline_user_args()
	_select_encounter_manager(orchard_campaign)
	await encounters.install(world)
	if "frostroarisland_teen" in str(MAPS[index][1]):
		frost_npcs=preload("res://scripts/worlds/frost_npc_controller.gd").new()
		frost_npcs.name="FrostNPCs"
		world.add_child(frost_npcs)
		frost_npcs.setup(self,world)
	else:frost_npcs=null
	if orchard_campaign:
		await get_tree().physics_frame
		var story_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/campaigns/star_orchard_world1_v2/story.json"))
		var placements = preload("res://scripts/campaigns/star_orchard_world1_v2/placements.gd").new()
		placements.name = "StarOrchardWorld1Places"
		world.add_child(placements)
		if not orchard_main_mode:
			encounters.setup(self, world, null)
		elif placements.setup(self, world, story_data, true):
			encounters.setup(self, world, placements)
		else:
			push_error("Star Orchard quest locations could not be installed")
	elif "star_orchard.tscn" in str(MAPS[index][1]) and preload("res://scripts/worlds/star_orchard_features.gd").STORY_ENABLED and not "--orchard-editor" in OS.get_cmdline_user_args():
		var orchard_runner := preload("res://scripts/worlds/star_orchard_encounter_controller.gd").new()
		orchard_runner.name = "StarOrchardEncounterRunner"
		world.add_child(orchard_runner)
		orchard_runner.setup(self, world)
		var orchard_story := preload("res://scripts/worlds/star_orchard_onboarding.gd").new()
		orchard_story.name = "StarOrchardOnboarding"
		world.add_child(orchard_story)
		orchard_story.setup(self, world, orchard_runner)
	if not "--offline" in OS.get_cmdline_user_args():game_menu.connect_default_server()
	loading.report(95,_l("正在准备魔法与战斗…","Preparing magic and combat…"))
	await encounters.session.prewarm()
	var orchard_editor: bool = "--orchard-editor" in OS.get_cmdline_user_args() and "star_orchard.tscn" in str(MAPS[index][1])
	if not is_instance_valid(mobile_controls) and "--offline" in OS.get_cmdline_user_args() and (orchard_editor or "--creative-mode" in OS.get_cmdline_user_args()):
		var creator = load("res://scripts/worlds/star_orchard_temp_editor.gd" if orchard_editor else "res://scripts/worlds/creative_mode.gd").new()
		creator.name = "CreativeMode"
		creator.world = world
		creator.atlas = self
		world.add_child(creator)
		if not orchard_editor:
			creator.layer.hide()
			creator.set_process_input(false)
			creator.set_process_unhandled_input(false)
	if bool(world.get_meta("tutorial_instance", false)):
		world.player.position = Journey.WEST_ENTRY
		world.player.velocity = Vector3.ZERO
		world._refresh_collisions()
	elif journey_switching and orchard_main_mode:
		world.player.position = Journey.MAIN_ENTRY
		world.player.velocity = Vector3.ZERO
		world._refresh_collisions()
	elif return_states.has(index):
		var saved: Dictionary = return_states[index]
		world.player.position = saved.position
		world.player.velocity = Vector3.ZERO
		world.yaw = saved.yaw
		world.pitch = saved.pitch
		world.distance = saved.distance
		world.tour_index = saved.region
		world._refresh_collisions()
	elif orchard_campaign and CharacterStart.is_new_orchard_character(Accounts.snapshot()):
		world.player.position = CharacterStart.ENTRY
		world.player.velocity = Vector3.ZERO
		world.tour_index = maxi(world.destinations.find(CharacterStart.ENTRY), 0)
		world._refresh_collisions()
	get_viewport().gui_release_focus()
	var category := 1 if str(MAPS[index][2]) == "instance" else 0
	category_picker.select(category)
	_refresh_map_picker(category)
	map_picker.select(map_picker.get_item_index(index))
	region_picker.clear()
	for title in world.destination_names:region_picker.add_item(title)
	region_picker.select(world.tour_index)
	map_picker.disabled = false
	category_picker.disabled = false
	region_picker.disabled = false
	wardrobe_button.disabled = false
	if is_instance_valid(journey_ui):journey_ui.queue_free()
	journey_ui = preload("res://scripts/worlds/orchard_journey_ui.gd").new()
	add_child(journey_ui)
	journey_ui.setup(self)
	busy = false
	_resume_world_music()
	loading.finish()
	status.text = _l("靠近商人按 E · P 卡牌 · B 背包装扮 · Esc 释放鼠标","Press E near merchants · P cards · B inventory · Esc release mouse")
	_save_preferences()
	_show_first_entry_guide()
	print("ATLAS_MAP_READY ", index, " ", MAPS[index][0])
	if not pending_journey_destination.is_empty():
		var destination := pending_journey_destination
		pending_journey_destination = ""
		journey_travel.call_deferred(destination)

func _resume_world_music() -> void:
	# Loading owns this pause. The campaign may fail to install placements, so
	# its battle manager is not a reliable owner of the current world's music.
	if not is_instance_valid(world):
		return
	for child in world.get_children():
		if child.get_script() == preload("res://scripts/fusion_3d/exploration_music.gd"):
			child.set_battle(false)

func _select_encounter_manager(orchard_campaign: bool) -> void:
	var target_script: Script = preload("res://scripts/campaigns/star_orchard_world1_v2/battle_runner.gd") if orchard_campaign else preload("res://scripts/worlds/island_encounters.gd")
	if encounters.get_script() == target_script:
		return
	# The old session has already completed _prepare_scene_exit. Keep the RPC
	# node path stable, and make the chat follow the single current connection.
	remove_child(encounters)
	encounters.free()
	encounters = target_script.new()
	encounters.name = "IslandEncounters"
	encounters.atlas = self
	add_child(encounters)
	if is_instance_valid(world_chat):
		world_chat.session = encounters.session

func _show_first_entry_guide() -> void:
	if test_mode:return
	if not is_instance_valid(first_entry_guide):
		first_entry_guide=preload("res://scripts/worlds/first_entry_guide.gd").new()
		ui.add_child(first_entry_guide)
	var key:=str(Accounts.active_character.get("id",Accounts.active_character.get("name",Accounts.account.get("username","default"))))
	first_entry_guide.open_for(key)

func _cycle_wing(direction:int) -> void:
	# This is only a selector for server-owned wings; the local catalog grants nothing.
	if wing_request_pending or busy or not is_instance_valid(world) or not world.ready_world:return
	if encounters!=null and encounters.active:return
	var options:Array[String]=[""]
	for mount in wing_mounts:
		var id:=str(mount.get("id",""))
		if id in unlocked_wings:options.append(id)
	if options.size()<=1:
		wing_label.text=_l("未装备 · 击败地图翼 Boss 解锁","None equipped · Defeat a wing boss to unlock")
		return
	var current:=options.find(equipped_wing)
	if current<0:current=0
	var requested:=options[posmod(current+direction,options.size())]
	wing_request_pending=true
	var result:Dictionary=await Accounts.equip_wing(requested,"wing-%s-%d"%[str(Accounts.active_character.get("id","character")),Time.get_ticks_usec()])
	wing_request_pending=false
	if bool(result.get("ok",false)):
		_on_progression_changed(result.get("snapshot",{}))
	else:
		wing_label.text=_l("翅膀切换失败：","Could not switch wings: ")+str(result.get("code","service_unavailable"))

func _on_progression_changed(snapshot: Dictionary) -> void:
	unlocked_wings.clear()
	for value in snapshot.get("wing_unlocks",[]):
		var id:=str(value)
		if not id.is_empty() and _wing_name(id)!="":unlocked_wings.append(id)
	var requested:=str(snapshot.get("equipped_wing",""))
	equipped_wing=requested if requested in unlocked_wings else ""
	if is_instance_valid(wing_label):
		wing_label.text=_l("未装备 · 击败地图翼 Boss 解锁","None equipped · Defeat a wing boss to unlock") if equipped_wing.is_empty() else _wing_name(equipped_wing)
	if is_instance_valid(world) and world.ready_world and is_instance_valid(world.flight):
		world.flight.equip(equipped_wing)

func _wing_name(id:String) -> String:
	for mount in wing_mounts:
		if str(mount.get("id",""))==id:return str(mount.get("name",id))
	return ""

func _select_region(index: int) -> void:
	if bool(world.get_meta("tutorial_instance", false)):return
	if busy or (encounters != null and encounters.active) or not is_instance_valid(world):return
	world.tour_index = index
	world._reset_player()
	world._refresh_collisions()
	ui.get_viewport().gui_release_focus()

func _set_size(value: float) -> void:
	character_size = value
	size_label.text = _l("人物大小  %.1f×","Character size  %.1f×") % (value / 2.0)
	if is_instance_valid(world) and world.ready_world:world.apply_explorer_scale(value)
	_save_preferences()

func _save_preferences() -> void:
	if test_mode:return
	preferences.set_value("exploration", "map", maxi(current_map, 0))
	preferences.set_value("exploration", "character_size", character_size)
	_save_character_location()
	preferences.save("user://island_explorer.cfg")

func _character_preference_section() -> String:
	return CharacterStart.preference_section(Accounts.server_url, str(Accounts.account.get("id","")), str(Accounts.active_character.get("id","")))

func _save_character_location() -> void:
	if test_mode or "--orchard-editor" in OS.get_cmdline_user_args() or Accounts.active_character.is_empty():return
	if current_map < 0 or not is_instance_valid(world) or not world.ready_world or not is_instance_valid(world.player):return
	if encounters != null and encounters.active:return
	var section := _character_preference_section()
	preferences.set_value(section,"orchard_main_mode", "star_orchard.tscn" in str(MAPS[current_map][1]) and not bool(world.get_meta("tutorial_instance",false)))
	preferences.set_value(section,"map_path",str(MAPS[current_map][1]))
	preferences.set_value(section,"world_state",{"position":world.player.position,"yaw":world.yaw,"pitch":world.pitch,"distance":world.distance,"region":world.tour_index})

func toggle_wardrobe() -> void:
	if library_is_open():character_library_panel.hide()
	if busy or (encounters != null and encounters.active) or not is_instance_valid(world) or not world.ready_world:return
	if is_instance_valid(game_menu) and game_menu.has_method("open_inventory"):
		if is_instance_valid(frost_npcs) and frost_npcs.is_open():frost_npcs.close()
		game_menu.call("open_inventory","appearance")
		return
	if wardrobe_panel.visible:wardrobe_panel.hide()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		wardrobe_panel.open_for(current_school)

func _wardrobe_visibility_changed() -> void:
	if is_instance_valid(world):
		world.input_suspended = (is_instance_valid(journey_ui) and journey_ui.is_open()) or (is_instance_valid(first_entry_guide) and first_entry_guide.visible) or wardrobe_panel.visible or library_is_open()
		if is_instance_valid(world.player):world.player.velocity = Vector3.ZERO

func _input(event: InputEvent) -> void:
	if is_instance_valid(first_entry_guide) and first_entry_guide.visible:return
	if encounters != null and encounters.active:return
	if is_instance_valid(world) and world.get_node_or_null("CreativeMode") != null and world.get_node("CreativeMode").enabled:return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F12:
			debug_panel.visible=not debug_panel.visible
			if debug_panel.visible:Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled();return
		if event.keycode==KEY_P and not (get_viewport().gui_get_focus_owner() is LineEdit):
			if is_instance_valid(frost_npcs) and frost_npcs.is_open():frost_npcs.close()
			if game_menu.has_method("open_inventory"):game_menu.call("open_inventory","cards")
			else:game_menu.toggle()
			get_viewport().set_input_as_handled();return
		if event.keycode==KEY_ESCAPE and game_menu.is_open():
			game_menu.close();get_viewport().set_input_as_handled();return
		if event.keycode == KEY_ESCAPE and library_is_open():
			character_library_panel.hide()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_N and not (get_viewport().gui_get_focus_owner() is LineEdit):
			toggle_character_library()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and wardrobe_panel.visible:
			wardrobe_panel.hide()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_B and not (get_viewport().gui_get_focus_owner() is LineEdit):
			toggle_wardrobe()
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if busy or (encounters != null and encounters.active) or not is_instance_valid(world) or not world.ready_world:return
	if encounters.can_start():status.text = _l("走进战斗盘后自动入场","Step onto the battle circle to join")
	elif not encounters.site.is_empty():status.text = _l("触碰游荡怪物进入战斗 · P 配置卡组","Touch a roaming monster to battle · P to edit deck")
	var focus := get_viewport().gui_get_focus_owner()
	world.input_suspended = (is_instance_valid(journey_ui) and journey_ui.is_open()) or (is_instance_valid(first_entry_guide) and first_entry_guide.visible) or (is_instance_valid(frost_npcs) and frost_npcs.is_open()) or (world.get_node_or_null("StarOrchardOnboarding") != null and world.get_node("StarOrchardOnboarding").is_open()) or (world.get_node_or_null("StarOrchardWorld1") != null and world.get_node("StarOrchardWorld1").is_open()) or ui.get_node("PlayerMinimap").expanded or wardrobe_panel.visible or library_is_open() or game_menu.is_open() or debug_panel.visible or focus is LineEdit or focus is TextEdit or (world.get_node_or_null("CreativeMode") != null and world.get_node("CreativeMode").enabled)
	if encounters!=null and encounters.has_method("is_open") and encounters.is_open():world.input_suspended=true
	if region_picker.selected != world.tour_index:region_picker.select(world.tour_index)

func _open_accounts() -> void:
	if busy or (encounters != null and encounters.active):return
	busy=true
	if not await _prepare_scene_exit():busy=false;return
	get_node("/root/Wardrobe").save()
	Accounts.leave_character()
	get_tree().change_scene_to_file("res://scenes/fusion_3d/account_menu.tscn")

func _prepare_scene_exit() -> bool:
	if exit_pending:return false
	_save_preferences()
	exit_pending=true
	var reconnect: bool=game_menu.cloud_enabled
	game_menu.cloud_enabled=false;game_menu.retry_timer.stop()
	encounters.session.net.disconnect_town()
	if not await encounters.session.prepare_world_exit():
		exit_pending=false
		game_menu.message.text=_l("战斗画面尚未结束，请稍后再试。","The battle scene is still closing. Please try again shortly.")
		if reconnect:game_menu.connect_default_server()
		return false
	return true

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and not exit_pending:_close_window()

func _close_window() -> void:
	if not is_instance_valid(encounters) or not is_instance_valid(game_menu):
		get_tree().quit();return
	busy=true
	if await _prepare_scene_exit():get_tree().quit()
	else:busy=false

func _exit_tree() -> void:
	get_tree().auto_accept_quit=previous_auto_accept_quit

func _run_validation() -> void:
	# Test-only temporary wardrobe; never write the player's account files.
	var store := get_node("/root/Wardrobe")
	for index in MAPS.size():
		await switch_map(index)
		await get_tree().create_timer(2).timeout
		assert(world.avatar.scale.is_equal_approx(Vector3.ONE * 2.0))
		assert(is_equal_approx(world.capsule_node.shape.height, 3.8))
		if index == 0:
			toggle_wardrobe()
			assert(wardrobe_panel.visible and world.input_suspended)
			store.set_teen_hair_color(current_school, Color("684131"))
			assert(world.avatar.equipped.teen_hair_color == "#684131")
			store.save_enabled = true
			store.save()
			store.save_enabled = false
			store.load_save()
			store.changed.emit(current_school)
			assert(store.outfit(current_school).teen_hair_color == "#684131")
			await get_tree().create_timer(0.7).timeout
			if not DisplayServer.get_name() == "headless":get_viewport().get_texture().get_image().save_png("res://docs/world_atlas/wardrobe.png")
			wardrobe_panel.hide()
			await get_tree().create_timer(0.3).timeout
		assert(world.avatar.equipped == store.outfit(current_school))
		if not DisplayServer.get_name() == "headless":get_viewport().get_texture().get_image().save_png("res://docs/world_atlas/map_%d.png" % index)
		print("ATLAS_VERIFIED ", index, " appearance, size, switching")
	await switch_map(0)
	assert(world.avatar.equipped == store.outfit(current_school))
	print("ATLAS_TEST_OK six maps, wardrobe, persistence, source size, revisit")
	get_tree().quit()

func library_is_open() -> bool:
	return is_instance_valid(character_library_panel) and character_library_panel.visible

func toggle_character_library() -> void:
	if busy or (encounters != null and encounters.active):return
	if library_is_open():
		character_library_panel.hide()
		return
	wardrobe_panel.hide()
	if not is_instance_valid(character_library_panel):
		character_library_panel=preload("res://scripts/fusion_3d/character_library_view.gd").new()
		ui.add_child(character_library_panel)
		character_library_panel.visibility_changed.connect(_wardrobe_visibility_changed)
	else:character_library_panel.filter_rows()
	character_library_panel.show()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_wardrobe_visibility_changed()

func journey_packet(data: Dictionary) -> void:
	if data.get("journey") is Dictionary:
		journey_state = data.journey.duplicate(true)
		journey_admitted = bool(data.journey.get("admitted", false))
		if is_instance_valid(journey_ui):journey_ui.set_state(data.journey)
	if str(data.get("op", "")) == "journey_redirect":
		journey_admitted = false
		journey_travel.call_deferred(Journey.TUTORIAL)
	elif str(data.get("op", "")) == "journey_result":
		if is_instance_valid(journey_ui):journey_ui.pending = false
		if bool(data.get("ok", false)):
			journey_admitted = true
			journey_travel.call_deferred(str(data.destination))
		else:
			var reason := str(data.get("message", "航线尚未开放。"))
			game_menu.message.text = reason
			if is_instance_valid(journey_ui):journey_ui.show_status(reason)

func journey_travel(destination: String) -> void:
	if busy:
		pending_journey_destination = destination
		return
	if encounters.active or journey_switching:return
	pending_journey_destination = ""
	var main := destination == Journey.MAIN
	var scene := "frostroarisland_teen" if destination == Journey.FROST else "star_orchard.tscn"
	for index in MAPS.size():
		if not scene in str(MAPS[index][1]):continue
		if index == current_map and main == orchard_main_mode:return
		var previous_mode := orchard_main_mode
		var previous_world := world
		orchard_main_mode = main
		journey_switching = true
		return_states.erase(index)
		await switch_map(index)
		if is_instance_valid(previous_world) and world == previous_world:orchard_main_mode = previous_mode
		journey_switching = false
		return
