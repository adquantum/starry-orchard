extends Node
## Star Orchard story progress lives inside the existing account-synced chapter save.
signal objective_changed(objective: Dictionary)
signal battle_requested(encounter_id: String)
signal course_completed(course_id: String)

const CONFIG_PATH := "res://resources/fusion_3d/star_orchard_onboarding.json"
const SATELLITES_PATH := "res://resources/fusion_3d/star_orchard_satellites.json"
const ENCOUNTERS_PATH := "res://resources/fusion_3d/star_orchard_encounters.json"
const LAYOUT_PATH := "res://resources/fusion_3d/star_orchard_layout.json"
const Satellites := preload("res://scripts/worlds/star_orchard_satellites.gd")
const SAVE_KEY := "star_orchard_onboarding"
const SCHOOL_ACTORS := {
	"fire":"npc_magictutorfire_15d27c6f",
	"ice":"npc_magictutorice_29d2cc87",
	"storm":"npc_magictutorstorm_c2e1a3af",
	"life":"npc_magictutorlife_53e7ff99",
	"death":"npc_magictutordeath_172f6400",
	"myth":"npc_magictutormyth_ad335b3c",
	"balance":"npc_magictutorstorm_df7be259"
}

var atlas: Node
var world: Node3D
var runner: Node
var quests: Array = []
var lessons: Array = []
var errands: Array = []
var points: Dictionary = {}
var arenas: Dictionary = {}
var battle_points: Dictionary = {}
var battle_centers: Dictionary = {}
var battle_names: Dictionary = {}
var labels: Dictionary = {}
var progress: Dictionary = {}
var active_battle := ""
var confirmed_battle := ""
var tracked_course := ""
var tracked_errand := ""
var side_visible := false
var hud: PanelContainer
var title_label: Label
var objective_label: Label
var notice_label: Label
var marker: Label3D
var travel_tick := 0.0
var navigation: Control
var dialogue: PanelContainer
var dialogue_title: Label
var dialogue_body: Label
var reply: Button
var pending_action: Callable
var equip_error := ""

func setup(owner_atlas: Node, owner_world: Node3D, encounter_runner: Node = null) -> bool:
	atlas = owner_atlas
	world = owner_world
	runner = encounter_runner
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
	if not source is Dictionary or int(source.get("schema_version", 0)) != 1:
		push_error("Star Orchard onboarding catalog invalid")
		return false
	quests = source.get("quests", [])
	lessons = source.get("lessons", [])
	errands = source.get("errands", [])
	if quests.size() != 28 or lessons.size() != 21 or errands.size() != 3:
		push_error("Star Orchard onboarding content count invalid")
		return false
	_load_points()
	_load_progress()
	_build_hud()
	_refresh()
	if is_instance_valid(runner) and runner.has_signal("encounter_finished"):
		var callback := Callable(self, "battle_finished")
		if not runner.is_connected("encounter_finished", callback):
			runner.connect("encounter_finished", callback)
	return true

func _point(raw: Variant) -> Vector3:
	if raw is Array and raw.size() == 3:
		return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	return Vector3.ZERO

func _load_points() -> void:
	points.clear()
	arenas.clear()
	battle_points.clear()
	battle_centers.clear()
	battle_names.clear()
	labels.clear()
	var sat: Variant = JSON.parse_string(FileAccess.get_file_as_string(SATELLITES_PATH))
	if not sat is Dictionary:
		return
	points["goddess"] = _point(sat.get("goddess", {}).get("position", sat.get("main_return", [])))
	labels["goddess"] = "星庭女神"
	var temple: Dictionary = sat.get("temple", {})
	points["orchard_temple"] = _point(temple.get("entry", []))
	points["temple_core"] = _point(temple.get("center", []))
	labels["orchard_temple"] = "星辉神殿"
	labels["temple_core"] = "神殿星核"
	for island_value in sat.get("islands", []):
		if not island_value is Dictionary:
			continue
		var island: Dictionary = island_value
		var id := str(island.get("id", ""))
		var short_id := id.trim_prefix("orchard_")
		var island_name := str(island.get("name", id))
		points[id] = _point(island.get("entry", []))
		labels[id] = island_name
		points[short_id + "_supply"] = _point(island.get("investigate", []))
		points[short_id + "_route"] = _point(island.get("investigate", []))
		points[short_id + "_node"] = _point(island.get("landmark", []))
		points[short_id + "_crystal"] = _point(island.get("investigate", []))
		points[short_id + "_source"] = _point(island.get("landmark", []))
		points[short_id + "_platform"] = _point(island.get("landmark", []))
		for suffix in ["supply", "route", "node", "crystal", "source", "platform"]:
			labels[short_id + "_" + suffix] = island_name + "调查点"
		points[str(island.get("npc", {}).get("id", ""))] = _point(island.get("npc", {}).get("position", []))
		for suffix in ["guardian", "captain", "scout", "envoy"]:
			points[short_id + "_" + suffix] = _point(island.get("npc", {}).get("position", []))
			labels[short_id + "_" + suffix] = island_name + "引路人"
	for anchor_value in Satellites.resolved_anchors():
		if not anchor_value is Dictionary:
			continue
		var anchor: Dictionary = anchor_value
		arenas[str(anchor.get("id", ""))] = _point(anchor.get("approach", anchor.get("center", [])))
		battle_centers[str(anchor.get("id", ""))] = _point(anchor.get("center", []))
	var encounter_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ENCOUNTERS_PATH))
	if encounter_data is Dictionary:
		for value in encounter_data.get("encounters", []):
			if value is Dictionary:
				var encounter_id := str(value.get("id", ""))
				var anchor_id := str(value.get("anchor_id", ""))
				battle_points[encounter_id] = arenas.get(anchor_id, Vector3.ZERO)
				battle_centers[encounter_id] = battle_centers.get(anchor_id, Vector3.ZERO)
				battle_names[encounter_id] = str(value.get("name", ""))
	var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if layout is Dictionary:
		for value in layout.get("objects", []):
			if not value is Dictionary:
				continue
			var actor := str(value.get("actor_id", value.get("npc_id", "")))
			if actor == "npc_businessman_e30b14ad":
				points["market_supply"] = _point(value.get("position", []))
				labels["market_supply"] = "商业街商人"
			for school in SCHOOL_ACTORS:
				if actor == str(SCHOOL_ACTORS[school]):
					points["mentor_" + school] = _point(value.get("position", []))
					labels["mentor_" + school] = {"fire":"火焰", "ice":"寒冰", "storm":"风暴", "life":"生命", "death":"死亡", "myth":"神话", "balance":"平衡"}.get(school, school) + "导师"
	points["mentor_own"] = points.get("mentor_" + _school(), Vector3.ZERO)
	labels["mentor_own"] = labels.get("mentor_" + _school(), "本系导师")

func set_anchor(id: String, position: Vector3) -> void:
	## Map integration may override a point after moving NPCs in the editor.
	points[id] = position
	if id == "mentor_" + _school():
		points["mentor_own"] = position
	_refresh()

func _school() -> String:
	return str(Accounts.active_character.get("school", atlas.current_school if is_instance_valid(atlas) else "life"))

func _default_progress() -> Dictionary:
	return {"version":1, "step":0, "objective":0, "completed":[], "lessons":{}, "errands":{}, "tracked_course":"", "tracked_errand":"", "side_visible":false}

func _load_progress() -> void:
	progress = _default_progress()
	var path := Accounts.path_for("academy_chapter_one.json")
	if not FileAccess.file_exists(path):
		return
	var chapter: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not chapter is Dictionary:
		return
	var saved: Variant = chapter.get(SAVE_KEY, {})
	if not saved is Dictionary or int(saved.get("version", 0)) != 1:
		return
	progress.step = clampi(int(saved.get("step", 0)), 0, quests.size())
	progress.objective = maxi(0, int(saved.get("objective", 0)))
	progress.completed = saved.get("completed", []) if saved.get("completed", []) is Array else []
	progress.lessons = saved.get("lessons", {}) if saved.get("lessons", {}) is Dictionary else {}
	progress.errands = saved.get("errands", {}) if saved.get("errands", {}) is Dictionary else {}
	progress.tracked_course = str(saved.get("tracked_course", ""))
	progress.tracked_errand = str(saved.get("tracked_errand", ""))
	progress.side_visible = bool(saved.get("side_visible", false))
	tracked_course = str(progress.tracked_course)
	tracked_errand = str(progress.tracked_errand)
	side_visible = bool(progress.side_visible)
	if int(progress.step) < quests.size():
		progress.objective = mini(int(progress.objective), _objectives(quests[int(progress.step)]).size() - 1)
	else:
		progress.objective = 0

func _save() -> bool:
	var path := Accounts.path_for("academy_chapter_one.json")
	var chapter: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not chapter is Dictionary:
		chapter = {}
	chapter[SAVE_KEY] = progress.duplicate(true)
	var written := Accounts.write_json(path, chapter)
	if written and Accounts.character_ready:
		call_deferred("_sync_account")
	return written

func _sync_account() -> void:
	if Accounts.character_ready:
		await Accounts.sync_save()

func _objectives(quest: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append({"kind":str(quest.get("kind", "talk")), "id":str(quest.get("lead", ""))})
	for id in quest.get("battles", []):
		result.append({"kind":"battle", "id":str(id)})
	if not str(quest.get("tail", "")).is_empty():
		result.append({"kind":"talk", "id":str(quest.tail)})
	return result

func current_quest() -> Dictionary:
	if int(progress.get("step", 0)) >= quests.size():
		return {}
	return quests[int(progress.step)]

func current_objective() -> Dictionary:
	var quest := current_quest()
	if quest.is_empty():
		return {}
	var objectives := _objectives(quest)
	return objectives[clampi(int(progress.objective), 0, objectives.size() - 1)]

func shown_objective() -> Dictionary:
	if side_visible:
		var course := _tracked_lesson()
		if not course.is_empty():
			var state := _course_state(str(course.id))
			if state == 1:
				return {"kind":"battle", "id":str(course.encounter), "course":str(course.id)}
			if state == 2:
				return {"kind":"talk", "id":str(course.mentor), "course":str(course.id)}
		var errand := _tracked_errand()
		if not errand.is_empty():
			var state := _errand_state(str(errand.id))
			if state == 1:
				return {"kind":str(errand.kind), "id":str(errand.target), "errand":str(errand.id)}
			if state == 2:
				return {"kind":"talk", "id":"market_supply", "errand":str(errand.id)}
	return current_objective()

func objective_point() -> Vector3:
	var objective := shown_objective()
	if str(objective.get("kind", "")) == "battle":
		return battle_points.get(str(objective.get("id", "")), Vector3.ZERO)
	return points.get(str(objective.get("id", "")), Vector3.ZERO)

func _near(point: Vector3, distance: float = 7.0) -> bool:
	return is_instance_valid(world) and is_instance_valid(world.player) and point != Vector3.ZERO and world.player.global_position.distance_to(point) <= distance

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player):
		return
	travel_tick += delta
	if travel_tick < 0.25:
		return
	travel_tick = 0.0
	var objective := shown_objective()
	if str(objective.get("kind", "")) == "arrive" and _near(objective_point(), 13.0):
		on_event("arrive", str(objective.id))
		return
	if is_instance_valid(marker):
		var point := objective_point()
		marker.visible = not objective.is_empty() and point != Vector3.ZERO and not _battle_busy() and not is_open()
		if marker.visible:
			marker.global_position = point + Vector3(0, 3.5, 0)
			marker.text = "◆ " + _objective_text(objective)
	if is_instance_valid(objective_label):
		var point := objective_point()
		var distance := roundi(world.player.global_position.distance_to(point)) if point != Vector3.ZERO else -1
		objective_label.text = _objective_text(objective) + (" · %d m" % distance if distance >= 0 else "")

func _battle_busy() -> bool:
	return not active_battle.is_empty() or (is_instance_valid(atlas) and is_instance_valid(atlas.encounters) and atlas.encounters.active)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if is_open():
		if event.keycode == KEY_ESCAPE:
			close_dialogue()
		elif event.keycode == KEY_E:
			_confirm_dialogue()
		get_viewport().set_input_as_handled()
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if not is_instance_valid(atlas) or atlas.busy or atlas.game_menu.is_open() or atlas.wardrobe_panel.visible or atlas.library_is_open():
		return
	if event.keycode == KEY_J and not _battle_busy() and (not tracked_course.is_empty() or not tracked_errand.is_empty()):
		side_visible = not side_visible
		progress.side_visible = side_visible
		_save()
		_refresh()
		get_viewport().set_input_as_handled()
		return
	if event.keycode != KEY_E:
		return
	if _battle_busy() or atlas.wardrobe_panel.visible or atlas.library_is_open():
		return
	if interact_nearby():
		get_viewport().set_input_as_handled()

func interact_nearby() -> bool:
	if is_open():
		return true
	var objective := shown_objective()
	var kind := str(objective.get("kind", ""))
	var encounter_id := str(objective.get("id", ""))
	var at_target := _near(objective_point())
	if kind == "battle":
		at_target = at_target or _near(battle_centers.get(encounter_id, Vector3.ZERO), 17.0)
	if kind != "arrive" and at_target:
		if kind == "battle":
			return request_battle(str(objective.id))
		if objective.has("course"):
			return _open_dialogue(str(objective.id), str(_tracked_lesson().get("title", "导师课程")), "练习已经完成，请向导师交付课程记录。", interact_course.bind(str(objective.id)))
		if objective.has("errand"):
			return _open_dialogue(str(objective.id), str(_tracked_errand().get("title", "商业街委托")), str(_tracked_errand().get("text", "记录调查结果。")), interact_errand if kind == "talk" else interact_errand_objective.bind(kind, str(objective.id)))
		return _open_dialogue(str(objective.id), str(current_quest().get("title", "任务")), str(current_quest().get("text", "")), on_event.bind(kind, str(objective.id)))
	var mentor := "mentor_" + _school()
	if _near(points.get(mentor, Vector3.ZERO)):
		return _open_dialogue(mentor, "本系导师课程", "让我检查你的课程记录，准备下一场法术练习。", interact_course.bind(mentor))
	if _near(points.get("market_supply", Vector3.ZERO)):
		return _open_dialogue("market_supply", "商业街委托", "来看看当前的调查委托，已经完成的记录也可以在这里交付。", interact_errand)
	return false

func on_event(kind: String, id: String) -> bool:
	var objective := current_objective()
	if kind != str(objective.get("kind", "")) or id != str(objective.get("id", "")):
		return false
	if kind == "battle" and confirmed_battle != id:
		return false
	if kind == "lesson" and not _equip_course_card(1):
		_notice(equip_error)
		return false
	if kind == "prepare" and is_instance_valid(atlas.game_menu):
		atlas.game_menu.open_inventory("cards")
	var quest := current_quest()
	_notice(str(quest.get("text", "")))
	progress.objective = int(progress.objective) + 1
	if int(progress.objective) >= _objectives(quest).size():
		_complete_main(quest)
	else:
		_save()
	_refresh()
	return true

func _complete_main(quest: Dictionary) -> void:
	var id := str(quest.id)
	if id not in progress.completed:
		progress.completed.append(id)
	progress.step = int(progress.step) + 1
	progress.objective = 0
	_save()

func request_battle(id: String) -> bool:
	var main := current_objective()
	var course := _tracked_lesson()
	var eligible := str(main.get("kind", "")) == "battle" and str(main.get("id", "")) == id
	eligible = eligible or (not course.is_empty() and int(_course_state(str(course.id))) == 1 and str(course.encounter) == id)
	if not eligible or _battle_busy():
		return false
	active_battle = id
	if is_instance_valid(runner) and (runner.has_method("begin") or runner.has_method("start_encounter")):
		var method := "begin" if runner.has_method("begin") else "start_encounter"
		var started: Variant = runner.call(method, id)
		if started is bool and not started:
			active_battle = ""
			return false
	else:
		battle_requested.emit(id)
	_notice("战斗开始。失败后可在同一地点重试。")
	return true

func battle_finished(id: String, won: bool) -> void:
	if id != active_battle:
		return
	active_battle = ""
	if not won:
		_notice("挑战未通过。检查卡组后在原地点重试。")
		return
	confirmed_battle = id
	if on_event("battle", id):
		confirmed_battle = ""
		return
	confirmed_battle = ""
	var course := _tracked_lesson()
	if not course.is_empty() and int(_course_state(str(course.id))) == 1 and str(course.encounter) == id:
		_set_course_state(str(course.id), 2)
		_notice("练习完成。返回本系导师交付课程。")
		_refresh()

func _tracked_lesson() -> Dictionary:
	for value in lessons:
		if value is Dictionary and str(value.get("id", "")) == tracked_course:
			return value
	return {}

func _tracked_errand() -> Dictionary:
	for value in errands:
		if value is Dictionary and str(value.get("id", "")) == tracked_errand:
			return value
	return {}

func _errand_state(id: String) -> int:
	return int((progress.get("errands", {}) as Dictionary).get(id, 0))

func _set_errand_state(id: String, state: int) -> void:
	var states: Dictionary = progress.get("errands", {})
	states[id] = state
	progress.errands = states
	_save()

func interact_errand() -> bool:
	if not _near(points.get("market_supply", Vector3.ZERO)):
		return false
	for value in errands:
		if not value is Dictionary:
			continue
		var errand: Dictionary = value
		var id := str(errand.id)
		var state := _errand_state(id)
		if state == 3:
			continue
		if int(progress.step) < int(errand.min_main_step):
			_notice("继续巡查后，商业街会有新的委托。")
			return true
		if state == 2:
			if id == "SO_E03" and is_instance_valid(atlas.game_menu):
				atlas.game_menu.open_inventory("cards")
			_set_errand_state(id, 3)
			tracked_errand = ""
			progress.tracked_errand = ""
			side_visible = false
			progress.side_visible = false
			_save()
			_notice(str(errand.title) + "已归档。没有额外物品发放。")
			_refresh()
			return true
		tracked_course = ""
		progress.tracked_course = ""
		tracked_errand = id
		progress.tracked_errand = id
		side_visible = true
		progress.side_visible = true
		if state == 0:
			_set_errand_state(id, 1)
		else:
			_save()
		_notice(str(errand.text))
		_refresh()
		return true
	_notice("商业街调查已全部归档。")
	return true

func interact_errand_objective(kind: String, id: String) -> bool:
	var errand := _tracked_errand()
	if errand.is_empty() or _errand_state(str(errand.id)) != 1:
		return false
	if kind != str(errand.kind) or id != str(errand.target):
		return false
	_set_errand_state(str(errand.id), 2)
	_notice(str(errand.text) + " 返回商业街报告。")
	_refresh()
	return true

func _course_state(id: String) -> int:
	return int((progress.get("lessons", {}) as Dictionary).get(id, 0))

func _set_course_state(id: String, state: int) -> void:
	var states: Dictionary = progress.get("lessons", {})
	states[id] = state
	progress.lessons = states
	_save()

func interact_course(mentor_id: String) -> bool:
	var school := _school()
	if mentor_id != "mentor_" + school:
		return false
	for value in lessons:
		if not value is Dictionary or str(value.get("school", "")) != school:
			continue
		var lesson: Dictionary = value
		var id := str(lesson.id)
		var state := _course_state(id)
		if state == 3:
			continue
		if int(progress.step) < int(lesson.min_main_step):
			_notice("继续主线后再来学习下一阶课程。")
			return true
		if state == 2:
			_set_course_state(id, 3)
			tracked_course = ""
			progress.tracked_course = ""
			side_visible = false
			progress.side_visible = false
			_save()
			course_completed.emit(id)
			_notice(str(lesson.title) + "完成。课程记录已经保存。")
			_refresh()
			return true
		if not _equip_card(str(lesson.card), school):
			_notice(equip_error)
			return false
		tracked_course = id
		progress.tracked_course = id
		tracked_errand = ""
		progress.tracked_errand = ""
		side_visible = true
		progress.side_visible = true
		if state == 0:
			_set_course_state(id, 1)
		else:
			_save()
		_notice(str(lesson.title) + "：已将 " + str(lesson.card) + " 纳入卡组。前往练习遭遇。")
		_refresh()
		return true
	_notice("本系三阶课程已完成。")
	return true

func _equip_course_card(tier: int) -> bool:
	equip_error = "没有找到本系课程，请重新进入地图。"
	var school := _school()
	for value in lessons:
		if value is Dictionary and str(value.get("school", "")) == school and int(value.get("tier", 0)) == tier:
			return _equip_card(str(value.card), school)
	return false

func _equip_card(card_id: String, school: String) -> bool:
	equip_error = "卡组尚未就绪，请重新进入地图后再与导师交谈。"
	if not is_instance_valid(atlas) or atlas.loadout == null:
		return false
	var loadout: RefCounted = atlas.loadout
	if loadout.school != school:
		equip_error = "角色学派与卡组不一致，请重新进入角色。"
		return false
	var card = loadout.content.card(StringName(card_id))
	if card == null or not card.learned or card.treasure or card.enemy_only or str(card.school_id) != school:
		equip_error = "这门课程的法术当前不可用，请检查课程目录。"
		return false
	var counts: Dictionary = loadout.counts()
	if int(counts.get(card_id, 0)) > 0:
		return true
	var total := 0
	for amount in counts.values():
		total += int(amount)
	if total >= 40:
		equip_error = "卡组已满。请关闭对话，在 P 菜单腾出一个卡位后再来。"
		return false
	counts[card_id] = 1
	if not loadout.valid_counts(counts):
		equip_error = "卡组包含不可用的卡牌，请在 P 菜单检查后重试。"
		return false
	var previous: Dictionary = loadout.saved.duplicate(true)
	loadout.saved[loadout.character()] = counts
	if not loadout.save():
		loadout.saved = previous
		equip_error = "卡组保存失败，请检查存档目录是否可写后重试。"
		return false
	if is_instance_valid(atlas.encounters) and is_instance_valid(atlas.encounters.session):
		atlas.encounters.session.send_profile()
	if is_instance_valid(atlas.game_menu) and atlas.game_menu.has_method("_queue_sync"):
		atlas.game_menu.call("_queue_sync")
	return true

func track_course(id: String) -> bool:
	for value in lessons:
		if value is Dictionary and str(value.get("id", "")) == id and str(value.get("school", "")) == _school() and _course_state(id) in [1, 2]:
			tracked_course = id
			progress.tracked_course = id
			tracked_errand = ""
			progress.tracked_errand = ""
			side_visible = true
			progress.side_visible = true
			_save()
			_refresh()
			return true
	return false

func track_main() -> void:
	side_visible = false
	progress.side_visible = false
	_save()
	_refresh()

func _build_hud() -> void:
	hud = PanelContainer.new()
	hud.name = "StarOrchardQuestTracker"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.position = Vector2(24, 156)
	hud.custom_minimum_size = Vector2(400, 96)
	hud.add_theme_stylebox_override("panel", _quest_panel_style())
	atlas.ui.add_child(hud)
	var box := VBoxContainer.new()
	hud.add_child(box)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 19)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.custom_minimum_size.x = 390
	box.add_child(title_label)
	objective_label = Label.new()
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(objective_label)
	notice_label = Label.new()
	notice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_label.custom_minimum_size.x = 390
	box.add_child(notice_label)
	marker = Label3D.new()
	marker.name = "OnboardingObjectiveMarker"
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.font_size = 34
	marker.pixel_size = 0.007
	marker.modulate = Color("ffe5a0")
	world.add_child(marker)
	navigation = preload("res://scripts/fusion_3d/quest_indicator.gd").new()
	navigation.objective_provider = self
	atlas.ui.add_child(navigation)
	navigation.setup(world)
	_build_dialogue()

func _objective_text(value: Dictionary) -> String:
	if value.is_empty():
		return "主线完成 · 可继续本系导师课程"
	var kind := str(value.get("kind", ""))
	var id := str(value.get("id", ""))
	if kind == "battle":
		var name := str(battle_names.get(id, ""))
		if name.is_empty() or name.contains("�"):
			var quest := current_quest()
			name = str(quest.get("title", "导师练习")) + " · 第" + str(int(id.get_slice("_", id.get_slice_count("_") - 1))) + "场"
		return "前往战斗盘并按 E：" + name
	if kind == "arrive":
		return "前往 " + str(labels.get(id, id))
	if kind == "lesson":
		return "与本系导师交谈并配置入门法术 · 按 E"
	if kind == "prepare":
		return "与商人查看已有卡牌和背包 · 按 E"
	if kind == "inspect":
		return "调查 " + str(labels.get(id, id)) + " · 按 E"
	return "与 " + str(labels.get(id, id)) + " 交谈 · 按 E"

func _exit_tree() -> void:
	if is_instance_valid(hud):
		hud.queue_free()
	if is_instance_valid(navigation):navigation.queue_free()
	if is_instance_valid(dialogue):dialogue.queue_free()

func _refresh() -> void:
	if not is_instance_valid(title_label):
		return
	var quest := current_quest()
	var course := _tracked_lesson()
	var errand := _tracked_errand()
	var title := str(quest.get("title", "")) if not quest.is_empty() else "见习毕业"
	if side_visible and not course.is_empty() and _course_state(str(course.id)) in [1, 2]:
		title = str(course.title)
	elif side_visible and not errand.is_empty() and _errand_state(str(errand.id)) in [1, 2]:
		title = str(errand.title)
	title_label.text = "星界果园 · " + title + (" [J 切换追踪]" if not tracked_course.is_empty() or not tracked_errand.is_empty() else "")
	objective_label.text = _objective_text(shown_objective())
	objective_changed.emit(shown_objective())

func _notice(value: String) -> void:
	if is_instance_valid(notice_label):
		notice_label.text = value
	if is_open():dialogue_body.text = value

func is_open() -> bool:
	return is_instance_valid(dialogue) and dialogue.visible

func _build_dialogue() -> void:
	dialogue = preload("res://scripts/fusion_3d/npc_dialogue_panel.gd").new()
	dialogue.name = "StarOrchardDialogue"
	atlas.ui.add_child(dialogue)
	dialogue_title = dialogue.heading
	dialogue_body = dialogue.body
	reply = dialogue.add_action("确认 · E", _confirm_dialogue)
	dialogue.add_action("稍后再来 · Esc", close_dialogue)
	dialogue.hide()

func _open_dialogue(id: String, title: String, body: String, action: Callable) -> bool:
	dialogue_title.text = str(labels.get(id, "调查记录")) + " · " + title
	dialogue_body.text = body
	pending_action = action
	var portrait_id := ""
	if id == "goddess": portrait_id = "npc_ordergoddess_c146406c"
	elif id.begins_with("mentor_"): portrait_id = str(SCHOOL_ACTORS.get(_school() if id == "mentor_own" else id.trim_prefix("mentor_"), ""))
	elif id == "market_supply": portrait_id = "npc_businessman_e30b14ad"
	dialogue.set_actor(portrait_id)
	dialogue.show()
	world.input_suspended = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(navigation):navigation.hide()
	return true

func close_dialogue() -> void:
	if is_instance_valid(dialogue):dialogue.hide()
	pending_action = Callable()
	get_viewport().gui_release_focus()

func _confirm_dialogue() -> void:
	if not pending_action.is_valid():return
	var action := pending_action
	if bool(action.call()):close_dialogue()

func _quest_panel_style() -> StyleBoxTexture:
	var style := preload("res://scripts/fusion_3d/combat_scroll_skin.gd").style().duplicate() as StyleBoxTexture
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	return style
