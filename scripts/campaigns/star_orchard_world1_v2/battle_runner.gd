extends "res://scripts/worlds/island_encounters.gd"
## Explicit, solo story admission backed by the existing authenticated server.
signal encounter_started(encounter_id: String)
signal encounter_finished(encounter_id: String, won: bool)
const Catalog = preload("res://scripts/server/star_orchard_catalog.gd")
const CAMPAIGN := "star_orchard_world1_v2"
const Geo = preload("res://scripts/server/encounter_geometry.gd")
const Variants = preload("res://scripts/worlds/star_orchard_variant_materials.gd")
var placements: Node
var active_id := ""
var requested_id := ""
var request_deadline := 0
var confirmed_id := ""
var active_battle_id := ""
var server_ready := false
var tutorial_bypassed := false
var completed_receipts: Dictionary = {}
var received_close_receipt: Dictionary = {}
var id_to_site: Dictionary = {}
var travel_pending: Dictionary = {}
var travel_response: Dictionary = {}
var travel_serial := 0
var roaming_nodes: Dictionary = {}
var roaming_tick := 0.0
var contact_cooldowns: Dictionary = {}
const TUTORIAL_IDS := ["SO1_T01", "SO1_T02", "SO1_T03", "SO1_T04", "SO1_T05"]
const LESSON_NAMES = Catalog.Tutorial.TITLES
var tutorial_layer: CanvasLayer
var tutorial_status: Label
var tutorial_navigation: Control
var tutorial_dialog: PanelContainer
var tutorial_dialog_title: Label
var tutorial_dialog_body: Label
var tutorial_dialog_continue: Button
var guided_lesson := "unseen"
var tutorial_voice: Node

func _ready() -> void:
	session = preload("res://scripts/campaigns/star_orchard_world1_v2/battle_session.gd").new()
	session.name = "IslandSession"
	session.manager = self
	add_child(session)

func setup(owner_atlas: Node, owner_world: Node3D, world_placements: Node) -> bool:
	atlas = owner_atlas
	world = owner_world
	placements = world_placements
	completed_receipts.clear()
	server_ready = false
	tutorial_bypassed = false
	site_entries.clear()
	id_to_site.clear()
	for child in world.get_children():
		if child.get_script() == preload("res://scripts/fusion_3d/exploration_music.gd"):music = child
	for definition in Catalog.all_sites():
		var root := Node3D.new()
		root.name = "StoryEncounter_" + str(definition.id)
		world.add_child(root)
		id_to_site[str(definition.id)] = site_entries.size()
		site_entries.append({"config": definition, "root": root, "monsters": []})
	if site_entries.is_empty():return false
	var first_roamer := site_index(TUTORIAL_IDS[0])
	if first_roamer > 0:
		var saved: Dictionary = site_entries[0]
		site_entries[0] = site_entries[first_roamer]
		site_entries[first_roamer] = saved
		for i in site_entries.size():id_to_site[str(site_entries[i].config.id)] = i
	site = site_entries[0].config
	if atlas.orchard_main_mode:_install_roaming()
	_install_tutorial_status()
	notice("星界果园主世界 · 游荡精英建议 T4 毕业后组队挑战。" if atlas.orchard_main_mode else "星界果园 · 西岛五课：走入当前课程战斗盘开始练习。")
	return true

func install(target: Node3D) -> void:
	# Atlas uses setup after placements are ready; never install Frost roamers here.
	world = target

func _install_roaming(ids: Array = Catalog.ROAMING_IDS) -> void:
	for id in ids:
		if roaming_nodes.has(str(id)): continue
		var index := site_index(str(id))
		if index < 0:continue
		var entry: Dictionary = site_entries[index]
		var models: Array[Node3D] = []
		for enemy in entry.config.enemies:
			var monster := preload("res://scripts/fusion_3d/world_one_monster.gd").new()
			monster.model_id = str(enemy.model)
			entry.root.add_child(monster)
			monster.scale = Vector3.ONE * float(entry.config.scale)
			var variant_id := str(enemy.get("variant_id", ""))
			if not variant_id.is_empty():
				if not Variants.apply(monster, variant_id):
					preload("res://scripts/fusion_3d/monster_theme_materials.gd").apply_report(monster, variant_id)
			if monster.animation != null:
				for clip in monster.animation.get_animation_list():
					if "anim_004_" in clip:
						monster.animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
						monster.animation.play(clip)
						monster.animation.speed_scale = 0.65
						break
			models.append(monster)
		roaming_nodes[str(id)] = models
		if id in TUTORIAL_IDS: entry.root.hide()

func current_tutorial_id() -> String:
	if tutorial_bypassed or (is_instance_valid(atlas) and atlas.orchard_main_mode):return ""
	for id in TUTORIAL_IDS:
		if not completed_receipts.has(id): return id
	return ""

func _install_tutorial_status() -> void:
	if is_instance_valid(tutorial_layer): tutorial_layer.queue_free()
	tutorial_layer = CanvasLayer.new()
	tutorial_layer.layer = 30
	world.add_child(tutorial_layer)
	tutorial_status = Label.new()
	tutorial_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_status.add_theme_font_size_override("font_size",19)
	tutorial_status.add_theme_color_override("font_shadow_color",Color.BLACK)
	tutorial_status.add_theme_constant_override("shadow_outline_size",5)
	tutorial_layer.add_child(tutorial_status)
	tutorial_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tutorial_status.offset_left=-322; tutorial_status.offset_right=-22
	tutorial_status.offset_top=334; tutorial_status.offset_bottom=466
	tutorial_navigation = preload("res://scripts/fusion_3d/quest_indicator.gd").new()
	tutorial_navigation.objective_provider = self
	tutorial_layer.add_child(tutorial_navigation)
	tutorial_navigation.setup(world)
	guided_lesson = "unseen"
	tutorial_dialog = preload("res://scripts/fusion_3d/npc_dialogue_panel.gd").new()
	tutorial_layer.add_child(tutorial_dialog)
	tutorial_voice = preload("res://scripts/campaigns/star_orchard_world1_v2/west_island_voice.gd").new()
	tutorial_dialog.add_child(tutorial_voice)
	tutorial_dialog_title = tutorial_dialog.heading
	tutorial_dialog_body = tutorial_dialog.body
	tutorial_dialog_continue = tutorial_dialog.add_action("明白了，前往练习", func(): tutorial_dialog.hide())
	tutorial_dialog.hide()

func _show_lesson_intro(id: String) -> void:
	var index := TUTORIAL_IDS.find(id)
	guided_lesson = id
	var introductions := [
		"果园的引路星莓被偷走了。去逐风庭找找那只背着弹弓的果鼠，别让它溜了。",
		"星莓指向了花信回廊，蜜叶蜂正挡着路。带上这颗辉豆，看看它能让你的魔法发生什么变化。",
		"通往花圃的桥被晶壳堵住了。苔晶穿山甲正在桥头打盹，小心它的起床气。",
		"风里传来了铃声！霜莓幼狼叼走了引路铃，正在初霜花圃里追着自己的尾巴跑。",
		"铃铛就在他们手里。一起上！"
	]
	tutorial_dialog_title.text = "风铃传讯 · " + ("西岛五课完成" if index < 0 else "第 %d 课：%s" % [index+1,LESSON_NAMES[index]])
	tutorial_dialog_body.text = "西岛五课已经完成！山顶的大水晶亮起来了。\n\n前往山顶，与水晶交互，即可启程去寒冰岛和其他玩家一起游玩。" if index < 0 else introductions[index]
	if index < 0 and tutorial_bypassed:
		tutorial_dialog_title.text = "新手指引已跳过"
		tutorial_dialog_body.text = "该角色已跳过西岛教程。与山顶水晶交互，即可前往寒冰岛。"
	tutorial_dialog_continue.text = "知道了" if index < 0 else "明白了，前往练习"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tutorial_dialog.show()
	# Admission runs later in this same update, before Atlas refreshes its lock.
	world.input_suspended = true
	tutorial_voice.play_text(tutorial_dialog_body.text)

func _refresh_tutorial_status() -> void:
	if not is_instance_valid(tutorial_status): return
	if atlas.orchard_main_mode:
		tutorial_layer.hide();return
	# The intro itself suspends world input. Keep its parent visible so the
	# Continue button remains reachable; only roaming HUD follows the input lock.
	tutorial_layer.visible = not active and not atlas.busy
	tutorial_status.visible = not world.input_suspended
	if is_instance_valid(atlas.player_minimap):
		var map_rect: Rect2 = atlas.player_minimap.get_global_rect()
		tutorial_status.position = Vector2(map_rect.position.x,map_rect.end.y+12)
		tutorial_status.size = Vector2(map_rect.size.x,132)
		tutorial_status.visible = not world.input_suspended and atlas.player_minimap.visible and not atlas.player_minimap.expanded
	var next := current_tutorial_id()
	if server_ready and tutorial_layer.visible and not world.input_suspended and guided_lesson != next:
		_show_lesson_intro(next)
	if not server_ready:
		tutorial_status.text = "西岛新手教程 · 正在同步服务器进度…"
	elif next.is_empty():
		tutorial_status.text = "西岛五课已完成 · 原卡组已恢复\n前往山顶大水晶 · 交互前往寒冰岛"
	else:
		var index := site_index(next)
		if index < 0: return
		var lesson := TUTORIAL_IDS.find(next)
		tutorial_status.text = "西岛教程 %d/5 · %s\n%s · 走入战斗盘开始\n战斗使用临时教学卡组" % [lesson+1,LESSON_NAMES[lesson],str(site_entries[index].config.name)]

func shown_objective() -> Dictionary:
	var next := current_tutorial_id()
	if server_ready and next.is_empty() and not atlas.orchard_main_mode:return {"id":"summit_crystal", "kind":"talk", "arrival_distance":12.0, "arrival_text":"与山顶水晶交互"}
	if not server_ready or next.is_empty() or site_index(next) < 0:return {}
	return {"id":next,"kind":"battle","arrival_distance":7.0,"arrival_text":"已到达 · 走入战斗盘开始"}

func objective_point() -> Vector3:
	if current_tutorial_id().is_empty() and not atlas.orchard_main_mode:return preload("res://scripts/worlds/orchard_journey_rules.gd").CRYSTAL
	var index := site_index(current_tutorial_id())
	return point(site_entries[index].config.center) if index >= 0 else Vector3.ZERO

func _objective_text(objective: Dictionary) -> String:
	if str(objective.get("id", "")) == "summit_crystal":return "山顶大水晶 · 前往寒冰岛"
	var index := site_index(str(objective.get("id","")))
	return str(site_entries[index].config.name) if index >= 0 else "前往课程战斗盘"

func _battle_busy() -> bool:
	return active or atlas.busy or not is_instance_valid(world) or not world.ready_world or world.input_suspended

func is_open() -> bool:
	return _retry_help_open() or (is_instance_valid(tutorial_dialog) and tutorial_dialog.is_visible_in_tree()) or atlas.game_menu.is_open() or (is_instance_valid(atlas.player_minimap) and atlas.player_minimap.expanded)

func _retry_help_open() -> bool:
	return is_instance_valid(session) and is_instance_valid(session.tutorial_ui) and session.tutorial_ui.retry_summary and session.tutorial_ui.panel.visible

func _update_roaming(delta: float) -> void:
	if not is_instance_valid(world) or not world.ready_world:return
	_refresh_tutorial_status()
	var next_tutorial := current_tutorial_id()
	# Admission depends on the platform, never the creature's render/roaming state.
	if _try_begin_tutorial(next_tutorial):return
	# Only the active lesson needs creature models; do not load all five at entry.
	if server_ready and not next_tutorial.is_empty() and not roaming_nodes.has(next_tutorial):
		_install_roaming([next_tutorial])
	var seconds := Time.get_ticks_msec() / 1000.0
	for id in roaming_nodes:
		var index := site_index(str(id))
		if index < 0:continue
		var entry: Dictionary = site_entries[index]
		if id in TUTORIAL_IDS:
			entry.root.visible = server_ready and id == next_tutorial and not active and not (session.encounter_busy and staged_site == index)
		if not entry.root.visible:continue
		var models: Array = roaming_nodes[id]
		for i in models.size():
			var monster: Node3D = models[i]
			var next: Vector3 = Geo.roam_position(entry.config, i, seconds)
			next.y = float(entry.config.get("roam_surface_y",point(entry.config.center).y)) if id in TUTORIAL_IDS else world._height(next)
			monster.position = next
			if monster.has_method("face_center"):
				monster.face_center(Geo.roam_position(entry.config, i, seconds + 0.1))
	roaming_tick += delta
	if active or not server_ready:return
	var check_contact := roaming_tick >= 0.16
	if check_contact:roaming_tick = 0.0
	if not is_instance_valid(world.player):return
	for id in roaming_nodes:
		if Time.get_ticks_msec() < int(contact_cooldowns.get(id, 0)):continue
		var index := site_index(str(id))
		if index < 0 or not site_entries[index].root.visible:continue
		if id in TUTORIAL_IDS:
			continue
		if not check_contact:continue
		for monster in roaming_nodes[id]:
			if Geo.touches(world.player.global_position, monster.global_position):
				contact_cooldowns[id] = Time.get_ticks_msec() + 5000
				begin(str(id))
				return

func _try_begin_tutorial(id: String) -> bool:
	if active or not server_ready or id.is_empty() or not is_instance_valid(world.player):return false
	if Time.get_ticks_msec() < int(contact_cooldowns.get(id, 0)):return false
	var index := site_index(id)
	if index < 0 or not Geo.in_arena(world.player.global_position,site_entries[index].config):return false
	return begin(id)

func site_index(id: String) -> int:
	return int(id_to_site.get(id, -1))

func begin(id: String) -> bool:
	if id not in Catalog.ROAMING_IDS and id not in TUTORIAL_IDS:return false
	if id in TUTORIAL_IDS and id != current_tutorial_id():return false
	if active or not requested_id.is_empty() or not is_instance_valid(world) or not world.ready_world or atlas.busy:return false
	if world.input_suspended:return false
	if site_index(id) < 0 or not server_ready or not session.net.connected or not session.net.authenticated:
		notice("正在连接星界果园战斗服务，请稍后靠近游荡怪物重试。")
		return false
	var definition: Dictionary = site_entries[site_index(id)].config
	if not Geo.can_begin_story(world.player.global_position,definition):
		notice("先走到这场遭遇的安全入口，再确认入场。")
		return false
	if is_instance_valid(tutorial_dialog):tutorial_dialog.hide()
	requested_id = id
	active_id = id
	confirmed_id = ""
	active_battle_id = ""
	received_close_receipt.clear()
	active = true
	world.input_suspended = true
	world.player.velocity = Vector3.ZERO
	request_deadline = Time.get_ticks_msec() + 20000
	session.net.send_request({"op": "world1_begin", "encounter_id": id, "campaign_id": CAMPAIGN})
	notice("正在确认战斗入场…")
	return true

func _process(delta: float) -> void:
	_update_roaming(delta)
	if not requested_id.is_empty() and confirmed_id.is_empty() and Time.get_ticks_msec() > request_deadline:
		# Disconnect an uncertain request so it cannot open a late, unclaimed room.
		session.net.disconnect_town()
		notice("入场确认超时，已保留任务进度，连接恢复后可重试。")

func authority_ready(data: Dictionary) -> void:
	var accounts := get_node_or_null("/root/Accounts")
	if accounts == null or str(data.get("character_id", "")) != str(accounts.active_character.get("id", "")):return
	server_ready = int(data.get("catalog_version", 0)) == 2
	tutorial_bypassed = bool(data.get("journey", {}).get("admitted",false)) and not bool(data.get("journey", {}).get("completed",false))
	atlas.journey_packet(data)
	if data.get("victories") is Dictionary:
		for id in data.victories:
			if _valid_receipt(str(id), data.victories[id]):completed_receipts[str(id)] = data.victories[id].duplicate(true)

func _valid_receipt(id: String, value: Variant) -> bool:
	if not value is Dictionary:return false
	var accounts := get_node_or_null("/root/Accounts")
	if accounts == null:return false
	return str(value.get("campaign_id", "")) == CAMPAIGN and str(value.get("character_id", "")) == str(accounts.active_character.get("id", "")) and str(value.get("encounter_id", "")) == id and not str(value.get("battle_id", "")).is_empty() and bool(value.get("committed", false)) and int(value.get("winner", -1)) == 0

func authority_started(id: String, battle_id: String) -> void:
	if site_index(id) < 0:return
	active_id = id
	active_battle_id = battle_id
	requested_id = ""
	confirmed_id = id
	encounter_started.emit(id)

func begin_local(index: int, participating: bool) -> void:
	# Pending admission reserves input but has not yet hidden/restaged the world.
	if participating and staged_site < 0:active = false
	super.begin_local(index, participating)

func accept_close_receipt(data: Dictionary) -> void:
	received_close_receipt.clear()
	if str(data.get("campaign_id", "")) != CAMPAIGN or str(data.get("encounter_id", "")) != active_id:return
	if int(data.get("winner", -1)) != 0:return
	var proof: Variant = data.get("receipt", {})
	if not _valid_receipt(active_id, proof):return
	if str(data.get("battle_id", "")) != active_battle_id:return
	received_close_receipt = proof.duplicate(true)
	completed_receipts[active_id] = proof.duplicate(true)

func finish_local(winner: int, exit_position: Variant = null) -> void:
	var id := active_id
	var won: bool = winner == 0 and not received_close_receipt.is_empty() and confirmed_id == id
	var was_participant: bool = session.active_local and not id.is_empty()
	var finished_site := staged_site
	super.finish_local(0 if won else -1, exit_position)
	if _retry_help_open():
		world.input_suspended=true
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if Catalog.Tutorial.Fixed.active(id) and finished_site >= 0:
		cooldowns[finished_site]=Time.get_ticks_msec()/1000.0+5.0
	active_id = ""
	requested_id = ""
	confirmed_id = ""
	active_battle_id = ""
	received_close_receipt.clear()
	contact_cooldowns[id] = Time.get_ticks_msec() + (5000 if Catalog.Tutorial.Fixed.active(id) else 20000)
	if was_participant:
		notice("战斗胜利。" if won else ("已返回本场入口，5秒后可原地免费重试。" if Catalog.Tutorial.Fixed.active(id) else "已返回安全位置。"))
		encounter_finished.emit(id, won)
		if won:session.net.send_request({"op":"world1_state"})

func authority_reused(data: Dictionary) -> void:
	var id := str(data.get("encounter_id", ""))
	if id.is_empty() or requested_id != id:return
	var proof: Variant = data.get("receipt", {})
	if not _valid_receipt(id, proof):return
	completed_receipts[id] = proof.duplicate(true)
	requested_id = ""
	active_id = ""
	active = false
	world.input_suspended = false
	encounter_started.emit(id)
	encounter_finished.emit(id, true)
	notice("服务器确认这场遭遇已经完成，继续当前任务。")

func authority_rejected(data: Dictionary) -> void:
	var id := str(data.get("encounter_id", ""))
	if id == requested_id and not id.is_empty():
		# Position snapshots and admission use separate network channels. An entry
		# request can overtake the snapshot at the rim; allow the next update to land.
		var position_pending := id in TUTORIAL_IDS and str(data.get("code", "")) == "too_far"
		_cancel_request(250 if position_pending else 5000)
		print("ORCHARD_ENTRY_REJECTED id=",id," code=",str(data.get("code",""))," retry_ms=",250 if position_pending else 5000)
	notice(str(data.get("message", "这场遭遇暂时不能开始。")))

func authority_disconnected() -> void:
	server_ready = false
	if confirmed_id.is_empty():_cancel_request()

func _cancel_request(retry_ms: int = 5000) -> void:
	var id := requested_id
	requested_id = ""
	active_id = ""
	active = false
	contact_cooldowns[id] = Time.get_ticks_msec() + retry_ms
	if is_instance_valid(world):world.input_suspended = false
	if not id.is_empty():encounter_finished.emit(id, false)

func last_receipt(id: String) -> Dictionary:
	return completed_receipts.get(id, {}).duplicate(true)

func travel_to(source_id: String, destination_id: String) -> bool:
	if active or not travel_pending.is_empty() or not server_ready or not session.net.connected or not session.net.authenticated:return false
	travel_serial += 1
	var request_id := "%d:%d:%d" % [get_instance_id(), Time.get_ticks_msec(), travel_serial]
	travel_pending = {"request_id": request_id, "source_id": source_id, "destination_id": destination_id}
	travel_response.clear()
	var was_suspended: bool = world.input_suspended
	active = true
	world.input_suspended = true
	world.player.velocity = Vector3.ZERO
	session.net.send_request({"op": "world1_travel", "request_id": request_id, "source_id": source_id, "destination_id": destination_id})
	var deadline := Time.get_ticks_msec() + 12000
	while travel_response.is_empty() and session.net.connected and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var approved := bool(travel_response.get("ok", false))
	if not approved:notice(str(travel_response.get("message", "航线确认未完成，位置和任务进度保持原样。")))
	travel_pending.clear()
	travel_response.clear()
	active = false
	if is_instance_valid(world):world.input_suspended = was_suspended
	return approved

func authority_travel_result(data: Dictionary) -> void:
	if travel_pending.is_empty() or str(data.get("request_id", "")) != str(travel_pending.request_id):return
	if str(data.get("source_id", "")) != str(travel_pending.source_id) or str(data.get("destination_id", "")) != str(travel_pending.destination_id):return
	var accounts := get_node_or_null("/root/Accounts")
	if bool(data.get("ok", false)) and (accounts == null or str(data.get("character_id", "")) != str(accounts.active_character.get("id", ""))):return
	travel_response = data.duplicate(true)

func notice(text: String) -> void:
	if is_instance_valid(atlas) and is_instance_valid(atlas.game_menu) and is_instance_valid(atlas.game_menu.message):atlas.game_menu.message.text = text

