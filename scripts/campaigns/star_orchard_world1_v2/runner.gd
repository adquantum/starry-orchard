extends Node
## First-world campaign. Progress is committed only after its atomic local save succeeds.
## Combat completion is accepted only from the encounter adapter's matched victory signal.
signal progress_changed(progress: Dictionary)
signal quest_completed(quest_id: String)

const CONFIG := "res://resources/campaigns/star_orchard_world1_v2/story.json"
const SAVE_KEY := "star_orchard_world1_v2"
const UI := preload("res://scripts/campaigns/star_orchard_world1_v2/journal_ui.gd")
const INVALID_POINT := Vector3.INF

var atlas: Node
var world: Node3D
var battle_runner: Node
var placements: Node
var data: Dictionary = {}
var progress: Dictionary = {}
var quests: Dictionary = {}
var mains: Array = []
var sides: Array = []
var _encounter_catalog: Dictionary = {}
var ui: CanvasLayer
var marker: Label3D
var _identity := ""
var _account_identity := ""
var _configured := false
var _tick := 0.0
var _notice := ""
var _notice_until := 0
var _sync_pending := false
var _sync_running := false
var _sync_after := 0
var _pending_battle: Dictionary = {}
var _confirmed_battle := ""
var _failed_battle_save: Dictionary = {}
var _failed_travel_save: Dictionary = {}
var _travel_pending := false
var _resume_mouse := Input.MOUSE_MODE_VISIBLE
var _suspended_before := false
var _read_error := false
var _completion_dialog := ""
var _completion_snoozed: Dictionary = {}
var _save_retry_after := 0
var _last_near: Dictionary = {}
var _route_guide: Dictionary = {}

func setup(owner_atlas: Node, owner_world: Node3D, encounters: Node, world_placements: Node) -> bool:
	atlas = owner_atlas
	world = owner_world
	battle_runner = encounters
	placements = world_placements
	name = "StarOrchardWorld1"
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not source is Dictionary or int(source.get("schema_version", 0)) != 2:
		push_error("First-world campaign catalog is missing or invalid")
		return false
	data = source
	mains = data.get("main_quests", [])
	sides = data.get("side_quests", [])
	for value in mains + sides:
		if value is Dictionary:
			quests[str(value.get("id", ""))] = value
	var encounter_path := str(data.get("encounters_file", ""))
	if not encounter_path.is_empty() and FileAccess.file_exists(encounter_path):
		var encounter_source: Variant = JSON.parse_string(FileAccess.get_file_as_string(encounter_path))
		if encounter_source is Dictionary:
			for encounter in encounter_source.get("encounters", []):
				if encounter is Dictionary:
					_encounter_catalog[str(encounter.get("id", ""))] = encounter
	_identity = str(Accounts.active_character.get("id", ""))
	_account_identity = str(Accounts.account.get("id", ""))
	_load_progress()
	ui = UI.new()
	add_child(ui)
	ui.build()
	ui.interaction_requested.connect(interact)
	ui.journal_requested.connect(open_journal)
	ui.close_requested.connect(close)
	marker = Label3D.new()
	marker.name = "World1ObjectiveMarker"
	marker.font_size = 40
	marker.pixel_size = 0.025
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.outline_size = 9
	marker.modulate = Color(1.0, 0.89, 0.52)
	marker.no_depth_test = false
	marker.visible = false
	world.add_child(marker)
	if is_instance_valid(battle_runner):
		if battle_runner.has_signal("encounter_started"):
			battle_runner.connect("encounter_started", _battle_started)
		if battle_runner.has_signal("encounter_finished"):
			battle_runner.connect("encounter_finished", battle_finished)
	_configured = true
	_publish()
	return true

func _blank() -> Dictionary:
	return {"version": 2, "character_id": _identity, "account_id": _account_identity,
		"accepted": {}, "objectives": {}, "completed": [], "flags": {}, "evidence": [],
		"choices": {}, "tracked_side": "", "receipts": {}, "route_unlocks": [],
		"journal": [], "seen_accept": {}, "seen_choices": {}, "battle_proofs": {}}

func _load_progress() -> void:
	progress = _blank()
	if _identity.is_empty():
		_read_error = true
		_notice = "选择角色后，即可开始这一角色的巡园旅程。"
		return
	var path: String = Accounts.path_for("academy_chapter_one.json")
	if not FileAccess.file_exists(path):
		return
	var chapter: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not chapter is Dictionary:
		_read_error = true
		_notice = "巡园簿存档暂时无法读取；旧记录已保留。"
		return
	var saved: Variant = chapter.get(SAVE_KEY, {})
	if not saved is Dictionary or saved.is_empty():
		return
	if int(saved.get("version", 0)) != 2 or str(saved.get("character_id", "")) != _identity or str(saved.get("account_id", "")) != _account_identity:
		_read_error = true
		_notice = "巡园簿与当前角色不匹配，请重新登录当前角色。"
		return
	for key in progress:
		if saved.has(key) and typeof(saved[key]) == typeof(progress[key]):
			progress[key] = saved[key]
	# Discard unknown quest records from the active view without touching other save namespaces.
	var clean_completed: Array = []
	for id in progress.completed:
		if quests.has(str(id)) and not clean_completed.has(str(id)):
			clean_completed.append(str(id))
	progress.completed = clean_completed
	if not quests.has(str(progress.tracked_side)):
		progress.tracked_side = ""

func _same_character() -> bool:
	return not _identity.is_empty() and str(Accounts.active_character.get("id", "")) == _identity and str(Accounts.account.get("id", "")) == _account_identity

func _commit(candidate: Dictionary) -> bool:
	if _read_error or not _same_character():
		_notify("当前角色的巡园簿未就绪，本次操作尚未记录。", 12)
		return false
	var path: String = Accounts.path_for("academy_chapter_one.json")
	var chapter: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not chapter is Dictionary:
		_notify("存档读取失败，未覆盖原记录。", 12)
		return false
	candidate.character_id = _identity
	candidate.account_id = _account_identity
	chapter[SAVE_KEY] = candidate.duplicate(true)
	if not Accounts.write_json(path, chapter):
		_save_retry_after = Time.get_ticks_msec() + 6000
		_notify("本次进度尚未保存，请检查存储空间后重试。", 20)
		return false
	progress = candidate
	_sync_pending = true
	_sync_after = Time.get_ticks_msec() + 1800
	_publish()
	return true

func _sync_account() -> void:
	if not _same_character() or not Accounts.character_ready or _sync_running:
		return
	_sync_pending = false
	_sync_running = true
	var result: Variant = await Accounts.sync_save()
	_sync_running = false
	if result is Dictionary and not bool(result.get("ok", false)):
		_notify("本机巡园簿已保存，云端同步暂未完成。", 8)

func _publish() -> void:
	if is_instance_valid(placements) and placements.has_method("set_story_state"):
		placements.set_story_state(progress.duplicate(true))
	progress_changed.emit(progress.duplicate(true))

func _prerequisites_met(quest: Dictionary) -> bool:
	for id in quest.get("prerequisites", []):
		if not progress.completed.has(str(id)):
			return false
	for flag in quest.get("requires_flags", []):
		if not bool(progress.flags.get(str(flag), false)):
			return false
	return true

func current_quest() -> Dictionary:
	for quest in mains:
		if not progress.completed.has(str(quest.id)) and _prerequisites_met(quest):
			return quest
	return {}

func shown_quest() -> Dictionary:
	var tracked := str(progress.get("tracked_side", ""))
	if quests.has(tracked) and not progress.completed.has(tracked):
		return quests[tracked]
	return current_quest()

func _quest_objectives(quest: Dictionary) -> Array:
	return quest.get("objectives", [])

func _count(quest_id: String, objective_id: String) -> int:
	var counts: Variant = progress.objectives.get(quest_id, {})
	return int(counts.get(objective_id, 0)) if counts is Dictionary else 0

func _is_done(quest: Dictionary, objective: Dictionary) -> bool:
	return _count(str(quest.id), str(objective.id)) >= maxi(1, int(objective.get("count", 1)))

func _available_objectives(quest: Dictionary) -> Array:
	var result: Array = []
	if quest.is_empty() or not bool(progress.accepted.get(str(quest.id), false)) or progress.completed.has(str(quest.id)):
		return result
	for objective in _quest_objectives(quest):
		if _is_done(quest, objective):
			continue
		var ready := true
		for required in objective.get("requires_objectives", []):
			var prerequisite := _find_objective(quest, str(required))
			if prerequisite.is_empty() or not _is_done(quest, prerequisite):
				ready = false
		for flag in objective.get("requires_flags", []):
			if not bool(progress.flags.get(str(flag), false)):
				ready = false
		if ready:
			result.append(objective)
	return result

func _find_objective(quest: Dictionary, id: String) -> Dictionary:
	for objective in _quest_objectives(quest):
		if str(objective.get("id", "")) == id:
			return objective
	return {}

func _all_done(quest: Dictionary) -> bool:
	if _quest_objectives(quest).is_empty():
		return false
	for objective in _quest_objectives(quest):
		if bool(objective.get("required", true)) and not _is_done(quest, objective):
			return false
	return true

func _active_quests() -> Array:
	var result: Array = []
	var primary := current_quest()
	if not primary.is_empty() and bool(progress.accepted.get(str(primary.id), false)):
		result.append(primary)
	var tracked := str(progress.get("tracked_side", ""))
	for quest in sides:
		if str(quest.id) == tracked and bool(progress.accepted.get(str(quest.id), false)) and not progress.completed.has(str(quest.id)):
			result.append(quest)
	return result

func _resolve_id(value: String) -> String:
	return value.replace("{school}", str(Accounts.active_character.get("school", "life")))

func _target_id(objective: Dictionary) -> String:
	var school := str(Accounts.active_character.get("school", "life"))
	var by_school: Dictionary = objective.get("encounter_by_school", {})
	if not by_school.is_empty():
		return str(by_school.get(school, _resolve_id(str(objective.get("target", "")))))
	return _resolve_id(str(objective.get("target", "")))

func _anchor_id(quest: Dictionary, objective: Dictionary) -> String:
	if bool(objective.get("remote", false)):
		return _resolve_id(str(objective.get("anchor", quest.get("anchor", ""))))
	if str(objective.get("kind", "")) == "prepare":
		return _resolve_id(str(objective.get("anchor", quest.get("anchor", ""))))
	return _resolve_id(str(objective.get("anchor", _target_id(objective))))

func _point(id: String) -> Vector3:
	if is_instance_valid(placements) and placements.has_method("anchor"):
		var value: Variant = placements.anchor(_resolve_id(id))
		if value is Vector3:
			return value
	return INVALID_POINT

func _objective_point(quest: Dictionary, objective: Dictionary) -> Vector3:
	return _point(_anchor_id(quest, objective))

func _valid_point(point: Vector3) -> bool:
	return is_finite(point.x) and is_finite(point.y) and is_finite(point.z)

func _player() -> CharacterBody3D:
	if not is_instance_valid(world):
		return null
	return world.get("player") as CharacterBody3D

func _near(quest: Dictionary, objective: Dictionary) -> bool:
	var player := _player()
	var point := _objective_point(quest, objective)
	if not is_instance_valid(player) or not _valid_point(point):
		return false
	var radius := float(objective.get("interaction_radius", 12.0 if str(objective.get("kind", "")) == "arrive" else 8.0))
	var delta := player.global_position - point
	return Vector2(delta.x, delta.z).length() <= radius and absf(delta.y) <= 7.0

func _world_ready() -> bool:
	return _configured and _same_character() and is_instance_valid(atlas) and not bool(atlas.get("busy")) and is_instance_valid(world) and bool(world.get("ready_world")) and is_instance_valid(_player())

func _battle_busy() -> bool:
	if not _pending_battle.is_empty():
		return true
	if is_instance_valid(atlas):
		var manager: Variant = atlas.get("encounters")
		if is_instance_valid(manager) and bool(manager.get("active")):
			return true
	return false

func _other_modal() -> bool:
	if not is_instance_valid(atlas):
		return false
	var game_menu: Variant = atlas.get("game_menu")
	if is_instance_valid(game_menu) and game_menu.has_method("is_open") and game_menu.is_open():
		return true
	for field in ["first_entry_guide", "wardrobe_panel", "debug_panel"]:
		var control: Variant = atlas.get(field)
		if is_instance_valid(control) and control is CanvasItem and control.visible:
			return true
	if atlas.has_method("library_is_open") and atlas.library_is_open():
		return true
	var map_ui: Variant = atlas.get("player_minimap")
	if is_instance_valid(map_ui) and bool(map_ui.get("expanded")):
		return true
	var creative: Node = world.get_node_or_null("CreativeMode") if is_instance_valid(world) else null
	return is_instance_valid(creative) and bool(creative.get("enabled"))

func _process(delta: float) -> void:
	if not _configured:
		return
	_tick += delta
	if _tick < 0.2:
		return
	_tick = 0.0
	if _sync_pending and not _sync_running and Time.get_ticks_msec() >= _sync_after:
		_sync_account()
	if not _world_ready():
		if is_instance_valid(marker):
			marker.hide()
		return
	ui.hud.visible = not _battle_busy()
	if _battle_busy() or _other_modal():
		marker.hide()
		return
	var quest := current_quest()
	if not quest.is_empty() and not bool(progress.accepted.get(str(quest.id), false)) and not _read_error and not is_open() and Time.get_ticks_msec() >= _save_retry_after:
		var accepted := progress.duplicate(true)
		accepted.accepted[str(quest.id)] = true
		if not _commit(accepted):
			_refresh_hud()
			return
	if not is_open():
		for active in _active_quests():
			if _all_done(active) and not _completion_snoozed.has(str(active.id)):
				_show_turn_in(active)
				break
			for objective in _available_objectives(active):
				if str(objective.kind) == "arrive" and _near(active, objective):
					_complete_objective(active, objective, "arrive:" + str(objective.id))
					break
	_refresh_hud()

func _nearest_interaction() -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	var player := _player()
	if not is_instance_valid(player):
		return best
	var active := _active_quests()
	var tracked := str(progress.get("tracked_side", ""))
	for quest in active:
		for objective in _available_objectives(quest):
			if str(objective.kind) == "arrive" or not _near(quest, objective):
				continue
			var distance := player.global_position.distance_to(_objective_point(quest, objective))
			if str(quest.id) == tracked:
				distance -= 20.0
			if distance < best_distance:
				best_distance = distance
				best = {"quest": quest, "objective": objective}
	return best

func _refresh_hud() -> void:
	if not is_instance_valid(ui):
		return
	var quest := shown_quest()
	var player := _player()
	var target := INVALID_POINT
	var title := "星界果园 · 巡园簿"
	var text := "第一世界的故事已完成。巡园簿里还有可选委托与旅途证据。"
	if not quest.is_empty():
		title = ("支线 · " if str(quest.get("track", "main")) == "side" else "主线 · ") + str(quest.get("title", ""))
		var available := _available_objectives(quest)
		if not available.is_empty():
			var nearest: Dictionary = available[0]
			var distance := INF
			for objective in available:
				var at := _objective_point(quest, objective)
				if _valid_point(at) and is_instance_valid(player) and player.global_position.distance_to(at) < distance:
					distance = player.global_position.distance_to(at)
					nearest = objective
			target = _objective_point(quest, nearest)
			text = str(nearest.get("text", "前往标记位置"))
			if available.size() > 1:
				text += "\n可按任意顺序完成 · 另有 %d 项" % (available.size() - 1)
			if is_finite(distance):
				text += " · %d 米" % roundi(distance)
		elif _all_done(quest):
			text = "整理本次见闻，完成巡园记录。"
		else:
			text = "正在整理任务线索…"
	if not _route_guide.is_empty():
		target = _point(str(_route_guide.source))
		title = "已开放路线"
		text = "前往 " + _place_label(str(_route_guide.source))
		if _valid_point(target) and is_instance_valid(player):
			text += " · %d 米" % roundi(player.global_position.distance_to(target))
	_last_near = _nearest_interaction()
	var finish_ready := not quest.is_empty() and _all_done(quest)
	var message := _notice if _read_error or Time.get_ticks_msec() < _notice_until else ""
	if message.is_empty() and not _failed_travel_save.is_empty():
		message = "本次行程尚待保存 · 打开巡园簿重试保存"
	elif message.is_empty() and not _failed_battle_save.is_empty():
		message = "战斗胜利尚待保存 · 打开巡园簿重试保存"
	var action := "交互 [E]"
	var route_near := not _route_guide.is_empty() and _near_route(_route_guide)
	if route_near:
		action = "沿已开放路线启程 [E]"
	elif finish_ready:
		action = "整理见闻 [E]"
	elif not _last_near.is_empty():
		action = {"battle":"开始战斗 [E]", "prepare":"检查卡组 [E]", "inspect":"查看 [E]", "activate":"操作 [E]", "travel":"启程 [E]", "choice":"作出判断 [E]"}.get(str(_last_near.objective.kind), "交谈 [E]")
	ui.update_hud(title, text, message, (route_near or finish_ready or not _last_near.is_empty()) and not is_open(), action)
	marker.visible = _valid_point(target) and not is_open() and not _battle_busy()
	if marker.visible:
		marker.global_position = target + Vector3(0, 5.2, 0)
		marker.text = "◆  " + ("%d 米" % roundi(player.global_position.distance_to(target)) if is_instance_valid(player) else "目的地")

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not _world_ready() or _battle_busy():
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if event.keycode == KEY_ESCAPE and is_open():
		close()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_J and not _other_modal():
		if is_open():
			close()
		else:
			open_journal()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_E and not is_open() and not _other_modal():
		interact()
		get_viewport().set_input_as_handled()

func _set_dialogue_speaker(id: String) -> void:
	for npc in data.get("npcs", []):
		if str(npc.get("id", "")) != id: continue
		var actor := str(npc.get("model_id", npc.get("actor_id", npc.get("model_candidate", ""))))
		var title := str(npc.get("name", ""))
		if actor == "goddess": actor = "npc_ordergoddess_c146406c"
		if str(npc.get("interaction_role", "")) == "mentor_by_player_school":
			var mentor: Dictionary = data.get("mentors", {}).get(str(Accounts.active_character.get("school", "life")), {})
			actor = str(mentor.get("actor_id", ""))
			title = str(mentor.get("name", title))
		ui.set_speaker(title, actor)
		return

func _begin_modal() -> void:
	ui.set_speaker("")
	if not is_open():
		_resume_mouse = Input.mouse_mode
		_suspended_before = bool(world.get("input_suspended"))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	world.set("input_suspended", true)
	var player := _player()
	if is_instance_valid(player):
		player.velocity = Vector3.ZERO
	marker.hide()

func is_open() -> bool:
	return is_instance_valid(ui) and ui.is_open()

func close() -> void:
	if not is_instance_valid(ui) or _travel_pending:
		return
	var was_open := is_open()
	ui.hide_modal()
	if not _completion_dialog.is_empty():
		_completion_snoozed[_completion_dialog] = true
	_completion_dialog = ""
	if was_open and is_instance_valid(world):
		world.set("input_suspended", _other_modal() or _battle_busy() or _suspended_before)
		if not _other_modal() and not _battle_busy():
			Input.mouse_mode = _resume_mouse

func interact() -> void:
	if not _world_ready() or is_open() or _battle_busy() or _other_modal() or _travel_pending:
		return
	if not _route_guide.is_empty() and _near_route(_route_guide):
		_show_route(_route_guide)
		return
	var shown := shown_quest()
	if not shown.is_empty() and _all_done(shown):
		_show_turn_in(shown)
		return
	var nearby: Array = []
	for quest in _active_quests():
		for objective in _available_objectives(quest):
			if str(objective.kind) != "arrive" and _near(quest, objective):
				nearby.append({"quest": quest, "objective": objective})
	if nearby.size() > 1:
		var options: Array = []
		for entry in nearby:
			options.append({"text": str(entry.objective.get("text", entry.quest.get("title", "继续旅程"))), "callback": _show_objective.bind(entry.quest, entry.objective)})
		_begin_modal()
		ui.show_pages("附近的线索", ["这里有几件已经可以进行的事。你想先做哪一件？"], "暂时收起", close, options)
		return
	var selected := _nearest_interaction()
	if selected.is_empty():
		_notify("沿标记走近目标后，再交谈或查看。")
		return
	_show_objective(selected.quest, selected.objective)

func _show_objective(quest: Dictionary, objective: Dictionary) -> void:
	if not _near(quest, objective):
		_notify("请先走近目标。")
		return
	var pages: Array = []
	if not bool(progress.seen_accept.get(str(quest.id), false)):
		pages.append_array(quest.get("dialogue", {}).get("accept", []))
	pages.append_array(objective.get("content", [str(objective.get("text", ""))]))
	_begin_modal()
	_set_dialogue_speaker(str(objective.get("npc_id", objective.get("target", quest.get("lead_npc", "")))))
	var kind := str(objective.get("kind", "talk"))
	if kind == "choice":
		pages.append(str(objective.get("prompt", "你准备怎样做？")))
		var choices: Array = []
		var options: Array = objective.get("choices", [])
		for index in range(options.size()):
			var choice: Dictionary = options[index]
			choices.append({"text": str(choice.get("text", "回应")), "callback": _choose.bind(quest, objective, index)})
		ui.show_pages(str(quest.title), pages, "", Callable(), choices)
	elif kind == "prepare":
		var check := _deck_check(objective)
		var preview := _encounter_preview(_resolve_id(str(objective.get("preview_encounter_id", ""))))
		if not preview.is_empty():
			pages.append(preview)
		pages.append(str(check.text))
		pages.append("需要帮助时，可以在队伍里选择 AI 助战。整理好卡组和队伍，再回来确认准备。")
		var actions: Array = [{"text": "打开卡组整理", "callback": _open_deck}, {"text": "队伍与 AI 助战", "callback": _open_party}]
		ui.show_pages(str(quest.title), pages, "确认这套卡组" if check.ok else "重新检查", _prepare.bind(quest, objective), actions)
	elif kind == "battle":
		var preview := _encounter_preview(_target_id(objective))
		if not preview.is_empty():
			pages.append(preview)
		var actions: Array = [{"text": "先整理卡组", "callback": _open_deck}, {"text": "队伍与 AI 助战", "callback": _open_party}]
		ui.show_pages(str(quest.title), pages, "准备好了，进入战斗", _begin_battle.bind(quest, objective), actions)
	elif kind == "travel":
		ui.show_pages(str(quest.title), pages, "启程", _travel.bind(quest, objective))
	else:
		var action: String = {"talk":"记下这段交谈", "inspect":"记入巡园簿", "activate":"确认操作"}.get(kind, "确认")
		ui.show_pages(str(quest.title), pages, action, _confirm_objective.bind(quest, objective))

func _confirm_objective(quest: Dictionary, objective: Dictionary) -> void:
	if not _world_ready() or not _near(quest, objective):
		_notify("已经离开目标附近，这次交互尚未完成。")
		close()
		return
	if _complete_objective(quest, objective, "interact:" + str(objective.id)):
		close()

func _choose(quest: Dictionary, objective: Dictionary, index: int) -> void:
	var options: Array = objective.get("choices", [])
	if index < 0 or index >= options.size() or not _near(quest, objective):
		return
	var chosen: Dictionary = options[index]
	var callback := _confirm_choice.bind(quest, objective, index)
	ui.show_pages(str(quest.title), [str(chosen.get("reply", ""))], "确认这份判断" if bool(chosen.get("completes", true)) else "重新考虑", callback)

func _confirm_choice(quest: Dictionary, objective: Dictionary, index: int) -> void:
	var choice: Dictionary = objective.get("choices", [])[index]
	if not bool(choice.get("completes", true)):
		_show_objective(quest, objective)
		return
	if not _world_ready() or not _near(quest, objective):
		close()
		return
	if _complete_objective(quest, objective, "choice:" + str(objective.id), {"choice_index": index}):
		close()

func _deck_check(objective: Dictionary) -> Dictionary:
	if not is_instance_valid(atlas) or atlas.get("loadout") == null:
		return {"ok": false, "text": "卡组仍在加载，请稍后再检查。"}
	var loadout: Variant = atlas.get("loadout")
	var counts: Dictionary = loadout.counts()
	if not loadout.valid_counts(counts):
		return {"ok": false, "text": "卡组含有不可使用的牌，请在卡组整理中调整。"}
	var total := 0
	var attack := false
	for id in counts:
		var copies := int(counts[id])
		total += copies
		if copies <= 0:
			continue
		var card: Variant = loadout.content.card(StringName(str(id)))
		if card == null:
			continue
		for effect in card.effects:
			var type := str(effect.get("type", effect.get("kind", ""))).to_lower()
			if "damage" in type or type in ["dot", "drain", "steal_health"]:
				attack = true
		if card.tags.has(&"attack") or card.tags.has(&"damage"):
			attack = true
	if total <= 0:
		return {"ok": false, "text": "卡组还是空的。打开卡组整理，装入已有的法术后再确认。"}
	if bool(objective.get("check_attack_card", false)) and not attack:
		return {"ok": false, "text": "这堂课程需要至少一张已有的攻击牌。卡组满时请自行选择换牌，任务不会替你移除法术。"}
	return {"ok": true, "text": "已检查现有卡组：%d / 40 张，配置可用。你可以直接保留，或先打开卡组整理。" % total}

func _open_deck() -> void:
	close()
	var menu: Variant = atlas.get("game_menu")
	if is_instance_valid(menu) and menu.has_method("open_inventory"):
		menu.open_inventory("cards")
	else:
		_notify("按 P 打开卡组整理，完成后回到目标处确认。")

func _open_party() -> void:
	close()
	var menu: Variant = atlas.get("game_menu")
	if is_instance_valid(menu) and menu.has_method("open_party"):
		menu.open_party()

func _encounter_preview(id: String) -> String:
	var encounter: Dictionary = _encounter_catalog.get(id, {})
	if encounter.is_empty():
		return ""
	var lines: Array[String] = ["即将面对：" + str(encounter.get("name", "旅途遭遇"))]
	for enemy in encounter.get("enemies", []):
		var resources: Dictionary = enemy.get("starting_resources", {})
		lines.append("• %s · %d 生命 · 起始普通魔豆 %d" % [str(enemy.get("name", "守卫")), int(enemy.get("hp", 0)), int(resources.get("normal", 0))])
	var hint := str(encounter.get("combat_hint", ""))
	if not hint.is_empty():
		lines.append("准备提示：" + hint)
	if is_instance_valid(atlas) and atlas.get("loadout") != null:
		lines.append("当前选择：%d 位 AI 助战；可在队伍中调整。" % int(atlas.get("loadout").ai_count))
	return "\n".join(lines)

func _prepare(quest: Dictionary, objective: Dictionary) -> void:
	var result := _deck_check(objective)
	if not bool(result.ok):
		_show_objective(quest, objective)
		return
	_confirm_objective(quest, objective)

func _complete_objective(quest: Dictionary, objective: Dictionary, receipt: String, extra: Dictionary = {}) -> bool:
	if quest.is_empty() or objective.is_empty() or progress.receipts.has(receipt) or _is_done(quest, objective):
		return false
	var available := _available_objectives(quest)
	var permitted := false
	for candidate in available:
		if str(candidate.id) == str(objective.id):
			permitted = true
	if not permitted:
		return false
	var next := progress.duplicate(true)
	var counts: Dictionary = next.objectives.get(str(quest.id), {})
	counts[str(objective.id)] = mini(_count(str(quest.id), str(objective.id)) + 1, maxi(1, int(objective.get("count", 1))))
	next.objectives[str(quest.id)] = counts
	next.receipts[receipt] = true
	next.seen_accept[str(quest.id)] = true
	for flag in objective.get("sets_flags", []):
		next.flags[str(flag)] = true
	for evidence in objective.get("evidence", []):
		if not next.evidence.has(str(evidence)):
			next.evidence.append(str(evidence))
	if extra.has("choice_index"):
		next.choices[str(quest.id) + "/" + str(objective.id)] = int(extra.choice_index)
	if extra.has("battle_proof"):
		next.battle_proofs[receipt] = extra.battle_proof
	if str(objective.get("kind", "")) == "travel":
		var route := {"source": _target_id(objective), "destination": _resolve_id(str(objective.get("destination_anchor", "")))}
		if not next.route_unlocks.has(route):
			next.route_unlocks.append(route)
	next.journal.append({"quest": str(quest.id), "objective": str(objective.id), "text": str(objective.get("text", "")), "time": int(Time.get_unix_time_from_system())})
	if _commit(next):
		_notify("已记录：" + str(objective.get("text", "")), 5)
		return true
	return false

func _show_turn_in(quest: Dictionary) -> void:
	if is_open() or not _world_ready() or _battle_busy():
		return
	_begin_modal()
	_set_dialogue_speaker(str(quest.get("turn_in_npc", quest.get("lead_npc", ""))))
	_completion_dialog = str(quest.id)
	var pages: Array = quest.get("dialogue", {}).get("turn_in", []).duplicate()
	if pages.is_empty():
		pages = ["这段旅程的见闻已经写进巡园簿。"]
	pages.append("本次见闻与已解锁的旅途状态会保留在当前角色的巡园簿中。")
	ui.show_pages(str(quest.title) + " · 任务回顾", pages, "完成这段旅程", _finish_quest.bind(quest))

func _finish_quest(quest: Dictionary) -> void:
	if not _all_done(quest) or progress.completed.has(str(quest.id)):
		close()
		return
	var next := progress.duplicate(true)
	next.completed.append(str(quest.id))
	for flag in quest.get("completion_flags", [quest.get("completion_flag", "")]):
		if not str(flag).is_empty():
			next.flags[str(flag)] = true
	if str(next.tracked_side) == str(quest.id):
		next.tracked_side = ""
	if not _commit(next):
		return
	_completion_dialog = ""
	_completion_snoozed.erase(str(quest.id))
	quest_completed.emit(str(quest.id))
	_notify("已完成：" + str(quest.title), 7)
	var flavor: Dictionary = quest.get("dialogue", {}).get("choice", {})
	if not flavor.is_empty() and not bool(progress.seen_choices.get(str(quest.id), false)):
		_show_flavor(quest, flavor)
	else:
		close()

func _show_flavor(quest: Dictionary, flavor: Dictionary) -> void:
	var options: Array = []
	var source: Array = flavor.get("options", [])
	for index in range(source.size()):
		var option: Dictionary = source[index]
		options.append({"text": str(option.get("text", "回应")), "callback": _flavor_reply.bind(quest, option, index)})
	ui.show_pages(str(quest.title), [str(flavor.get("prompt", "还有什么想说的？"))], "继续旅程", close, options)

func _flavor_reply(quest: Dictionary, option: Dictionary, index: int) -> void:
	var next := progress.duplicate(true)
	next.seen_choices[str(quest.id)] = true
	next.choices[str(quest.id) + "/flavor"] = index
	if not _commit(next):
		return
	ui.show_pages(str(quest.title), [str(option.get("reply", ""))], "继续旅程", close)

func _begin_battle(quest: Dictionary, objective: Dictionary) -> void:
	if not _world_ready() or not _near(quest, objective) or _battle_busy():
		return
	if not _failed_battle_save.is_empty() and str(_failed_battle_save.get("objective", "")) == str(objective.id):
		close()
		_retry_battle_save()
		return
	if not is_instance_valid(battle_runner) or not battle_runner.has_method("begin"):
		_notify("这处战斗暂未就绪，请稍后再来。")
		return
	var id := _target_id(objective)
	_pending_battle = {"id": id, "quest": str(quest.id), "objective": str(objective.id), "receipt": "battle:" + str(objective.id) + ":" + id}
	_confirmed_battle = ""
	close()
	var started: bool = battle_runner.begin(id)
	if not started:
		_pending_battle.clear()
		_notify("这处战斗暂时无法开始，已完成的步骤仍然保留。", 8)
		if is_instance_valid(world):
			world.set("input_suspended", _other_modal())

func _battle_started(encounter_id: String) -> void:
	if not _pending_battle.is_empty() and str(_pending_battle.id) == encounter_id:
		_confirmed_battle = encounter_id

func battle_finished(encounter_id: String, won: bool) -> void:
	if _pending_battle.is_empty() or str(_pending_battle.get("id", "")) != encounter_id:
		return
	if won and _confirmed_battle != encounter_id:
		return
	var pending := _pending_battle.duplicate(true)
	_pending_battle.clear()
	_confirmed_battle = ""
	if not won:
		_notify("已保留调查和其他胜利；整理卡组后可重试这一场。", 12)
		return
	var quest: Dictionary = quests.get(str(pending.quest), {})
	var objective := _find_objective(quest, str(pending.objective))
	var extra: Dictionary = {}
	if is_instance_valid(battle_runner) and battle_runner.has_method("last_receipt"):
		var proof: Variant = battle_runner.last_receipt(encounter_id)
		if proof is Dictionary and not proof.is_empty():
			extra.battle_proof = proof.duplicate(true)
	pending.extra = extra
	if not _complete_objective(quest, objective, str(pending.receipt), extra):
		if not progress.receipts.has(str(pending.receipt)):
			_failed_battle_save = pending
			_notify("已经获胜，但进度写入失败。打开巡园簿可重试保存，无需重打。", 30)

func _retry_battle_save() -> void:
	if _failed_battle_save.is_empty():
		return
	var pending := _failed_battle_save.duplicate(true)
	var quest: Dictionary = quests.get(str(pending.quest), {})
	var objective := _find_objective(quest, str(pending.objective))
	if _complete_objective(quest, objective, str(pending.receipt), pending.get("extra", {})) or progress.receipts.has(str(pending.receipt)):
		_failed_battle_save.clear()
		close()

func commit_receipt(receipt: Dictionary) -> bool:
	## Optional authority adapter hook: store proof, never infer a win from its mere arrival.
	if str(receipt.get("character_id", "")) != _identity or str(receipt.get("campaign_id", SAVE_KEY)) != SAVE_KEY:
		return false
	var id := str(receipt.get("battle_id", ""))
	if id.is_empty():
		return false
	var next := progress.duplicate(true)
	next.battle_proofs[id] = receipt.duplicate(true)
	return _commit(next)

func _travel(quest: Dictionary, objective: Dictionary) -> void:
	if not _world_ready() or not _near(quest, objective) or _travel_pending:
		return
	var destination := _resolve_id(str(objective.get("destination_anchor", "")))
	if destination.is_empty() or not _valid_point(_point(destination)) or not is_instance_valid(placements):
		_notify("目的地暂未就绪，行程尚未推进。")
		return
	if not is_instance_valid(battle_runner) or not battle_runner.has_method("travel_to"):
		_notify("航线暂未就绪，行程尚未推进。")
		return
	if not placements.has_method("prepare_travel") or not bool(placements.prepare_travel(destination)):
		_notify("目的地暂时没有可用的安全落点，行程尚未推进。")
		return
	_travel_pending = true
	ui.show_pages("正在准备行程", ["正在确认这条路线的安全落点，请稍候…"], "", Callable())
	var approved: bool = await battle_runner.travel_to(_target_id(objective), destination)
	_travel_pending = false
	if not _world_ready():
		close()
		return
	if not approved:
		_notify("本次行程未能启程，位置和任务进度已保留。", 10)
		_show_objective(quest, objective)
		return
	if not placements.travel_to(destination):
		_notify("暂时无法到达安全落点，行程尚未推进。")
		_show_objective(quest, objective)
		return
	if not _complete_objective(quest, objective, "travel:" + str(objective.id)):
		_failed_travel_save = {"quest": str(quest.id), "objective": str(objective.id)}
		close()
		_notify("已经抵达，但行程记录尚未保存。打开巡园簿可重试保存，无需重新启程。", 30)
		return
	close()

func _retry_travel_save() -> void:
	if _failed_travel_save.is_empty():
		return
	var quest: Dictionary = quests.get(str(_failed_travel_save.quest), {})
	var objective := _find_objective(quest, str(_failed_travel_save.objective))
	var receipt := "travel:" + str(objective.get("id", ""))
	if _complete_objective(quest, objective, receipt) or progress.receipts.has(receipt):
		_failed_travel_save.clear()
		close()

func open_journal() -> void:
	if not _world_ready() or _battle_busy() or _other_modal() or _travel_pending:
		return
	_begin_modal()
	ui.begin_journal()
	var main := current_quest()
	ui.journal_text("主线进度  %d / %d   ·   证据 %d 份" % [_completed_main_count(), mains.size(), progress.evidence.size()], 20)
	if not _failed_battle_save.is_empty():
		ui.journal_button("保存刚才的战斗胜利", _retry_battle_save)
	if not _failed_travel_save.is_empty():
		ui.journal_button("保存刚才的行程", _retry_travel_save)
	if not main.is_empty():
		ui.journal_button("追踪主线：" + str(main.title), _track_side.bind(""))
		_append_quest_journal(main)
	else:
		ui.journal_text("根与云之间 · 第一世界主线已完成。", 20)
	if not progress.route_unlocks.is_empty():
		ui.journal_text("已经开放的路线", 20)
		for route in progress.route_unlocks:
			if route is Dictionary and route.has("source") and route.has("destination"):
				ui.journal_button("前往路线入口：" + _place_label(str(route.source)) + " → " + _place_label(str(route.destination)), _guide_route.bind(route))
	ui.journal_text("可选委托", 20)
	var any_side := false
	for quest in sides:
		if progress.completed.has(str(quest.id)):
			ui.journal_button("✓ 回顾：" + str(quest.title), _review_quest.bind(quest))
			continue
		if not _prerequisites_met(quest):
			continue
		any_side = true
		if bool(progress.accepted.get(str(quest.id), false)):
			ui.journal_button("追踪委托：" + str(quest.title), _track_side.bind(str(quest.id)))
			if str(progress.tracked_side) == str(quest.id):
				_append_quest_journal(quest)
		else:
			ui.journal_button("查看委托：" + str(quest.title), _show_side_offer.bind(quest))
	if not any_side:
		ui.journal_text("沿主线认识更多居民后，会有新的委托。", 15)
	ui.journal_text("已经取得的证据", 20)
	var catalog: Dictionary = data.get("evidence_catalog", {})
	if progress.evidence.is_empty():
		ui.journal_text("调查得到的货签、刻痕与见闻会记录在这里。", 15)
	for id in progress.evidence:
		var record: Dictionary = catalog.get(str(id), {})
		ui.journal_button(str(record.get("title", "旅途记录")), _read_evidence.bind(str(id)))
	ui.journal_text("旅途回顾", 20)
	for quest in mains:
		if progress.completed.has(str(quest.id)):
			ui.journal_button("✓ " + str(quest.title), _review_quest.bind(quest))
	ui.journal_text("巡园簿记录剧情证据、已完成任务和世界变化。金币、经验与背包物品以服务器结算及背包记录为准。", 14)

func _completed_main_count() -> int:
	var count := 0
	for quest in mains:
		if progress.completed.has(str(quest.id)):
			count += 1
	return count

func _append_quest_journal(quest: Dictionary) -> void:
	for objective in _quest_objectives(quest):
		ui.journal_text(("✓ " if _is_done(quest, objective) else "○ ") + str(objective.get("text", "")), 16)
	var pages: Array = quest.get("dialogue", {}).get("in_progress", [])
	if not pages.is_empty():
		ui.journal_button("再看看旅途提示", _hint.bind(quest))

func _hint(quest: Dictionary) -> void:
	ui.show_pages(str(quest.title), quest.get("dialogue", {}).get("in_progress", []), "返回巡园簿", open_journal)

func _show_side_offer(quest: Dictionary) -> void:
	var pages: Array = quest.get("dialogue", {}).get("accept", []).duplicate()
	pages.append("这是居民的可选委托。可以先记下位置，随时继续；不会阻挡主线。")
	ui.show_pages(str(quest.title), pages, "记下委托并追踪", _accept_side.bind(quest))

func _accept_side(quest: Dictionary) -> void:
	if not _prerequisites_met(quest) or progress.completed.has(str(quest.id)):
		return
	var next := progress.duplicate(true)
	next.accepted[str(quest.id)] = true
	next.tracked_side = str(quest.id)
	# Reading an offer is not the NPC talk objective; it still requires a nearby interaction.
	if _commit(next):
		close()

func _track_side(id: String) -> void:
	var next := progress.duplicate(true)
	next.tracked_side = id
	if _commit(next):
		_route_guide.clear()
		close()

func _place_label(id: String) -> String:
	if is_instance_valid(placements) and placements.has_method("label_for"):
		return str(placements.label_for(id))
	return "已记录的路口"

func _guide_route(route: Dictionary) -> void:
	_route_guide = route.duplicate(true)
	close()

func _near_route(route: Dictionary) -> bool:
	var player := _player()
	var point := _point(str(route.get("source", "")))
	if not is_instance_valid(player) or not _valid_point(point):
		return false
	var delta := player.global_position - point
	return Vector2(delta.x, delta.z).length() <= 9.0 and absf(delta.y) <= 7.0

func _show_route(route: Dictionary) -> void:
	_begin_modal()
	ui.show_pages("已经开放的路线", ["从这里前往" + _place_label(str(route.destination)) + "。"], "启程", _repeat_travel.bind(route))

func _repeat_travel(route: Dictionary) -> void:
	if not _world_ready() or not _near_route(route) or not progress.route_unlocks.has(route) or _travel_pending:
		return
	if not is_instance_valid(battle_runner) or not battle_runner.has_method("travel_to"):
		return
	if not placements.has_method("prepare_travel") or not bool(placements.prepare_travel(str(route.destination))):
		_notify("目的地暂时没有可用的安全落点，请稍后再来。")
		return
	_travel_pending = true
	ui.show_pages("正在准备行程", ["正在确认这条已开放路线的安全落点，请稍候…"], "", Callable())
	var approved: bool = await battle_runner.travel_to(str(route.source), str(route.destination))
	_travel_pending = false
	if not _world_ready():
		close()
		return
	if not approved:
		_notify("本次行程未能启程，位置已保留。", 10)
		_show_route(route)
		return
	if not placements.travel_to(str(route.destination)):
		_notify("目的地暂未就绪，请稍后再来。")
		_show_route(route)
		return
	_route_guide.clear()
	close()

func _read_evidence(id: String) -> void:
	var record: Dictionary = data.get("evidence_catalog", {}).get(id, {})
	ui.show_pages(str(record.get("title", "旅途证据")), record.get("text", []), "返回巡园簿", open_journal)

func _review_quest(quest: Dictionary) -> void:
	var pages: Array = quest.get("dialogue", {}).get("turn_in", []).duplicate()
	for objective in _quest_objectives(quest):
		pages.append("✓ " + str(objective.get("text", "")))
	ui.show_pages(str(quest.title), pages, "返回巡园簿", open_journal)

func _notify(text: String, seconds: int = 6) -> void:
	_notice = text
	_notice_until = Time.get_ticks_msec() + seconds * 1000

func _exit_tree() -> void:
	_configured = false
	if is_instance_valid(marker):
		marker.queue_free()
	if is_instance_valid(ui):
		ui.hide_modal()
	if is_instance_valid(world) and not world.is_queued_for_deletion():
		world.set("input_suspended", _other_modal() or _battle_busy())
