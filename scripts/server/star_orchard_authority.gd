extends Node
## Authenticated SO1 admission and durable, character-scoped victory receipts.
## This module never grants currency or writes the Frost/account reward ledger.
const Catalog = preload("res://scripts/server/star_orchard_catalog.gd")
const Journey = preload("res://scripts/worlds/orchard_journey_rules.gd")
const CAMPAIGN := "star_orchard_world1_v2"
var coordinator: Node
var peer_worlds: Dictionary = {}
var indexes: Dictionary = {}
var records: Dictionary = {}
var requests: Dictionary = {}
var travel_routes: Dictionary = {}
var legacy_migration_running := false
var legacy_migration_done := false

func setup(owner_server: Node) -> void:
	coordinator = owner_server
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(Catalog.SERVER_DATA))
	if value is Dictionary:travel_routes = value.get("travel_routes", {}).duplicate(true)
	for site in Catalog.all_sites():
		indexes[str(site.id)] = coordinator.sites.size()
		coordinator.sites.append(site)

func is_site(index: int) -> bool:
	return index >= 0 and index < coordinator.sites.size() and str(coordinator.sites[index].get("campaign_id", "")) == CAMPAIGN

func is_peer(peer: int) -> bool:
	return str(peer_worlds.get(peer, "")) in [CAMPAIGN, Journey.MAIN]

func same_world(peer: int, index: int) -> bool:
	if is_peer(peer) != is_site(index):return false
	if is_site(index):return is_tutorial_peer(peer) == Catalog.Tutorial.is_tutorial(str(coordinator.sites[index].id))
	return true

func same_peer_world(a: int, b: int) -> bool:
	if not coordinator.profiles.has(a) or not coordinator.profiles.has(b):return false
	if is_tutorial_peer(a) or is_tutorial_peer(b):return a == b
	return str(peer_worlds.get(a, "")) == str(peer_worlds.get(b, ""))

func publish_chat(sender: int, packet: Dictionary) -> void:
	for peer in coordinator.profiles:
		if same_peer_world(sender, int(peer)):coordinator.net.publish(packet, int(peer))

func is_tutorial_peer(peer: int) -> bool:
	return str(peer_worlds.get(peer, "")) == CAMPAIGN

func _account(peer: int) -> String:
	return str(coordinator.profiles.get(peer, {}).get("progression_snapshot", {}).get("account_id", ""))

func _account_path(account: String) -> String:
	if account.length() != 32 or not account.is_valid_hex_number(false) or coordinator.progression == null:return ""
	return str(coordinator.progression.journal_dir).path_join("orchard_accounts").path_join(account + ".json")

func _write_record(path: String, data: Dictionary) -> bool:
	if path.is_empty():return false
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:return false
	file.store_string(JSON.stringify(data));file.flush()
	var error := file.get_error();file.close()
	return error == OK and DirAccess.rename_absolute(absolute + ".tmp", absolute) == OK

func account_completed(peer: int) -> bool:
	var account := _account(peer)
	var path := _account_path(account)
	if path.is_empty() or not FileAccess.file_exists(path):return false
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value is Dictionary and str(value.get("account_id", "")) == account and bool(value.get("completed", false))

func _mark_account(peer: int) -> bool:
	return _write_record(_account_path(_account(peer)), {"version":1, "account_id":_account(peer), "completed":true, "character_id":_character(peer)})

func bind_peer(peer: int, request: Dictionary) -> void:
	var record := _load_record(_character(peer))
	if Journey.completed(record):_mark_account(peer)
	var requested := str(request.get("world_id", Journey.FROST))
	if requested not in [CAMPAIGN, Journey.MAIN, Journey.FROST]:requested = Journey.FROST
	if not Journey.admitted(record):requested = CAMPAIGN
	peer_worlds[peer] = requested
	if requested != str(request.get("world_id", Journey.FROST)):
		coordinator.net.publish({"op":"journey_redirect", "destination":CAMPAIGN, "message":"请先完成西岛五课；账号完成后，新角色可在西岛选择跳过。"}, peer)
	if is_peer(peer):send_state(peer)

func journey_state(peer: int) -> Dictionary:
	var record := _load_record(_character(peer))
	return {"completed":Journey.completed(record), "admitted":Journey.admitted(record), "can_skip":account_completed(peer) and not Journey.admitted(record), "world_id":str(peer_worlds.get(peer, ""))}

func _journey_request(peer: int, data: Dictionary) -> void:
	var action := str(data.get("action", ""))
	var response := {"op":"journey_result", "action":action, "ok":false, "destination":"", "message":"请在入口交互，并先完成西岛新手教程。"}
	if not coordinator._available(peer):
		coordinator.net.publish(response, peer);return
	var record := _load_record(_character(peer))
	if record.is_empty():coordinator.net.publish(response, peer);return
	var destination := ""
	var at: Vector3 = coordinator.net.positions[peer]
	if action == "skip" and is_tutorial_peer(peer) and account_completed(peer):
		var next := record.duplicate(true)
		next["tutorial_skipped"] = true
		next["account_id"] = _account(peer)
		if _write_record(_record_path(_character(peer)), next):
			records[_character(peer)] = next
			destination = Journey.FROST
	elif action == "crystal" and is_tutorial_peer(peer) and Journey.admitted(record) and Journey.near(at, Journey.CRYSTAL):
		destination = Journey.FROST
	elif action == "ship" and str(peer_worlds.get(peer, "")) == Journey.FROST and Journey.admitted(record) and Journey.near(at, Journey.SHIP, 18.0):
		destination = Journey.MAIN
	elif action == "return" and str(peer_worlds.get(peer, "")) == Journey.MAIN and Journey.admitted(record) and Journey.near(at, Journey.MAIN_ENTRY, 35.0):
		destination = Journey.FROST
	if not destination.is_empty():
		response.ok = true;response.destination = destination;response.message = "航线已开放。"
		response["journey"] = journey_state(peer)
	coordinator.net.publish(response, peer)

func left(peer: int) -> void:
	peer_worlds.erase(peer)
	requests.erase(peer)

func _character(peer: int) -> String:
	var profile: Dictionary = coordinator.profiles.get(peer, {})
	return str(profile.get("progression_snapshot", {}).get("character_id", ""))

func _record_path(character: String) -> String:
	if character.length() != 32 or not character.is_valid_hex_number(false):return ""
	if coordinator.progression == null:return ""
	return str(coordinator.progression.journal_dir).path_join("star_orchard_world1").path_join(character + ".json")

func _load_record(character: String) -> Dictionary:
	if records.has(character):return records[character]
	var path := _record_path(character)
	if path.is_empty():return {}
	var record: Dictionary = {"schema_version": 1, "campaign_id": CAMPAIGN, "character_id": character, "victories": {}}
	if FileAccess.file_exists(path):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary or str(value.get("character_id", "")) != character or str(value.get("campaign_id", "")) != CAMPAIGN or not value.get("victories") is Dictionary:
			push_error("SO1 victory journal requires operator recovery: " + character)
			return {}
		record = value
	records[character] = record
	return record

func record_victory(character: String, id: String, battle_id: String) -> Dictionary:
	if not indexes.has(id) or battle_id.is_empty():return {}
	var previous := _load_record(character)
	if previous.is_empty():return {}
	if previous.victories.has(id) and id not in Catalog.ROAMING_IDS:
		if Journey.completed(previous):
			for peer in coordinator.profiles:
				if _character(int(peer)) == character and not _mark_account(int(peer)):return {}
		return previous.victories[id].duplicate(true)
	var receipt := {"campaign_id": CAMPAIGN, "character_id": character, "encounter_id": id, "battle_id": battle_id, "winner": 0, "committed": true, "economic_rewards": false, "completed_at": int(Time.get_unix_time_from_system())}
	var next := previous.duplicate(true)
	next.victories[id] = receipt
	var path := _record_path(character)
	var absolute := ProjectSettings.globalize_path(path)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:return {}
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:return {}
	file.store_string(JSON.stringify(next))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:return {}
	records[character] = next
	if Journey.completed(next):
		for peer in coordinator.profiles:
			if _character(int(peer)) == character and not _mark_account(int(peer)):return {}
	return receipt

func send_state(peer: int) -> void:
	if not is_peer(peer) or not coordinator.profiles.has(peer):return
	var record := _load_record(_character(peer))
	if record.is_empty():
		_reject(peer, "", "progress_unavailable", "巡园战斗记录暂不可用，已有进度不会被覆盖。")
		return
	coordinator.net.publish({"op": "world1_ready", "campaign_id": CAMPAIGN, "character_id": _character(peer), "victories": record.victories.duplicate(true), "catalog_version": 2, "economic_rewards": false, "journey":journey_state(peer)}, peer)

func handle(peer: int, data: Dictionary) -> bool:
	var op := str(data.get("op", ""))
	if op == "journey":
		_journey_request(peer, data);return true
	if op not in ["world1_begin", "world1_state", "world1_travel"]:return false
	if not is_peer(peer):
		_reject(peer, str(data.get("encounter_id", "")), "wrong_world", "请在星界果园重新连接后入场。")
		return true
	if op == "world1_travel":_travel(peer, data)
	elif op == "world1_state":send_state(peer)
	else:_begin(peer, str(data.get("encounter_id", "")))
	return true

func _travel(peer: int, data: Dictionary) -> void:
	if is_tutorial_peer(peer):
		_reject(peer, "", "tutorial_required", "西岛单人副本请使用山顶水晶前往寒冰岛。")
		return
	var request_id := str(data.get("request_id", ""))
	var source := str(data.get("source_id", ""))
	var destination := str(data.get("destination_id", ""))
	if request_id.is_empty() or request_id.length() > 80:return
	var response := {"op": "world1_travel_result", "campaign_id": CAMPAIGN, "request_id": request_id, "source_id": source, "destination_id": destination, "ok": false, "message": "这条路线暂时不能使用，请在出发点稍后重试。"}
	var route: Dictionary = travel_routes.get(source, {})
	if not coordinator._available(peer) or route.is_empty() or str(route.get("destination_id", "")) != destination:
		coordinator.net.publish(response, peer)
		return
	var from := Vector3(route.source_position[0], route.source_position[1], route.source_position[2])
	var delta: Vector3 = coordinator.net.positions[peer] - from
	if Vector2(delta.x, delta.z).length() > 20.0 or absf(delta.y) > 18.0:
		response.message = "请先到这条路线的出发点，航线标记仍留在巡园簿里。"
		coordinator.net.publish(response, peer)
		return
	var record := _load_record(_character(peer))
	if record.is_empty():coordinator.net.publish(response, peer);return
	for id in route.get("requires_victories", []):
		if not record.victories.has(str(id)):
			response.message = "这条安全航线尚未开放，请先完成当前调查。"
			coordinator.net.publish(response, peer)
			return
	var destination_point := Vector3(route.destination_position[0], route.destination_position[1], route.destination_position[2]) + Vector3.UP * 0.16
	coordinator.net.positions[peer] = destination_point
	coordinator.net.last_seen[peer] = Time.get_ticks_msec()
	response.ok = true
	response.position = [destination_point.x, destination_point.y, destination_point.z]
	response.character_id = _character(peer)
	response.message = "航线已确认。"
	coordinator.net.publish(response, peer)

func _reject(peer: int, id: String, code: String, message: String) -> void:
	coordinator.net.publish({"op": "world1_rejected", "campaign_id": CAMPAIGN, "encounter_id": id, "code": code, "message": message}, peer)

func _begin(peer: int, id: String) -> void:
	if id == "SO1_E01":
		_reject(peer, id, "disabled", "First city rat battle is disabled.")
		return
	if id not in Catalog.ROAMING_IDS and not Catalog.Tutorial.is_tutorial(id):
		_reject(peer, id, "quest_disabled", "果园任务战斗已关闭；请寻找山地游荡怪物。")
		return
	if requests.has(peer):return
	if not indexes.has(id) or not coordinator._available(peer):
		_reject(peer, id, "entry_unavailable", "暂时不能入场，请等待连接或上一场战斗结束。")
		return
	var index := int(indexes[id])
	if not same_world(peer, index):
		_reject(peer, id, "wrong_instance", "这场战斗不属于当前区域。")
		return
	var site: Dictionary = coordinator.sites[index]
	if not preload("res://scripts/server/encounter_geometry.gd").can_begin_story(coordinator.net.positions[peer],site):
		_reject(peer, id, "too_far", "请先走到这场遭遇的安全入口。")
		return
	var profile: Dictionary = coordinator.profiles[peer]
	if site.has("required_school") and str(site.required_school) != str(profile.school):
		_reject(peer, id, "wrong_school", "精修课程使用你当前角色所属的学院。")
		return
	var record := _load_record(_character(peer))
	if record.is_empty():
		_reject(peer, id, "progress_unavailable", "巡园战斗记录暂不可用，请稍后重试。")
		return
	for required in site.get("requires_victories", []):
		if not record.victories.has(str(required)):
			_reject(peer, id, "prerequisite_missing", "请先完成巡园簿上此前的战斗；左右回廊可以任选先后。")
			return
	if record.victories.has(id) and id not in Catalog.ROAMING_IDS:
		coordinator.net.publish({"op": "world1_result", "campaign_id": CAMPAIGN, "encounter_id": id, "receipt": record.victories[id].duplicate(true), "replayed_receipt": true}, peer)
		return
	var private_room := Catalog.Tutorial.is_tutorial(id)
	if (not private_room and coordinator.site_rooms.has(index)) or coordinator.rooms.size() >= coordinator.max_rooms:
		_reject(peer, id, "site_busy", "这处场地正在使用，请稍后再试。")
		return
	requests[peer] = true
	var room: Node = coordinator._new_room(index, private_room)
	if room == null:
		requests.erase(peer)
		_reject(peer, id, "site_busy", "战斗场地暂不可用，请稍后重试。")
		return
	var candidates: Array[int] = [peer]
	if not private_room:
		for other in coordinator.net.positions:
			if int(other) != peer and can_join(int(other), id) and preload("res://scripts/server/encounter_geometry.gd").in_arena(coordinator.net.positions[other], site):
				candidates.append(int(other))
				if candidates.size() >= 4:break
	var started: bool = await room.start_pve(index, peer, candidates)
	requests.erase(peer)
	if not started:
		coordinator._discard_room(room, index)
		_reject(peer, id, "start_failed", "卡组或角色状态尚未就绪，已返回安全入口。")
		return
	for member in room.members:coordinator._reserve_peer(int(member), room)

func can_join(peer: int, id: String) -> bool:
	if not is_peer(peer) or not coordinator._available(peer) or not indexes.has(id):return false
	if is_tutorial_peer(peer) or not same_world(peer, int(indexes[id])):return false
	var record := _load_record(_character(peer))
	if record.is_empty():return false
	for required in Catalog.prerequisites(id):
		if not record.victories.has(str(required)):return false
	return not record.victories.has(id) or id in Catalog.ROAMING_IDS

func state_for_identity(snapshot: Dictionary) -> Dictionary:
	var record := _load_record(str(snapshot.get("character_id", "")))
	var account := str(snapshot.get("account_id", ""))
	if Journey.completed(record):
		_write_record(_account_path(account), {"version":1, "account_id":account, "completed":true, "character_id":str(snapshot.get("character_id", ""))})
	return {"completed":Journey.completed(record), "admitted":Journey.admitted(record)}

func migrate_legacy_accounts() -> void:
	# Prior releases stored only character receipts. Resolve ownership through the
	# authenticated internal account service before granting account-wide skip.
	while legacy_migration_running:await get_tree().process_frame
	if legacy_migration_done:return
	legacy_migration_running = true
	var folder := str(coordinator.progression.journal_dir).path_join("star_orchard_world1")
	var directory := DirAccess.open(folder)
	var complete := true
	if directory != null:
		for filename in directory.get_files():
			if not filename.ends_with(".json"):continue
			var character := filename.trim_suffix(".json")
			var record := _load_record(character)
			if not Journey.completed(record):continue
			var result: Dictionary = await coordinator.progression.call_account("snapshot", {"character_id":character})
			if not bool(result.get("ok", false)):
				complete = false;continue
			var identity: Dictionary = result.get("snapshot", {})
			if str(identity.get("character_id", "")) != character:complete = false;continue
			var account := str(identity.get("account_id", ""))
			if not _write_record(_account_path(account), {"version":1, "account_id":account, "completed":true, "character_id":character}):complete = false
	legacy_migration_done = complete
	legacy_migration_running = false
