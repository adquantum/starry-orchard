extends "res://scripts/worlds/island_battle_session.gd"
## SO1 keeps the established authenticated transport and public battle playback.
const CAMPAIGN := "star_orchard_world1_v2"
const RetryHelp = preload("res://scripts/campaigns/star_orchard_world1_v2/tutorial_retry_help.gd")
var tutorial_ui: CanvasLayer

func tutorial_character_key() -> String:
	var accounts:=get_node_or_null("/root/Accounts")
	return str(accounts.active_character.get("id","")) if accounts!=null else ""

func _ready() -> void:
	super._ready()
	tutorial_ui = preload("res://scripts/campaigns/star_orchard_world1_v2/tutorial_battle_ui.gd").new()
	tutorial_ui.session = self
	add_child(tutorial_ui)

func authority() -> bool:
	# Story wins only come from the dedicated service, including admin sessions.
	return false

func send_profile() -> void:
	if not is_instance_valid(manager) or not is_instance_valid(manager.atlas.loadout):return
	if net == null or not net.connected or profile_sending:return
	var accounts := get_node_or_null("/root/Accounts")
	if accounts == null or accounts.token.is_empty() or accounts.active_character.is_empty():return
	var profile: Dictionary = manager.atlas.loadout.profile()
	profile.erase("progression_snapshot")
	profile.erase("equipment")
	profile["treasures"] = {}
	profile_sending = true
	net.send_request({"op": "profile", "profile": profile, "protocol_version": 2, "battle_wire_version": 3, "observer_protocol": 1, "token": accounts.token, "character_id": str(accounts.active_character.id), "world_id": "star_orchard_main" if manager.atlas.orchard_main_mode else CAMPAIGN})
	profile_sending = false

func configure_engine(engine: BattleEngineV2) -> void:
	super.configure_engine(engine)
	if not engine.presentation_only:
		preload("res://scripts/server/star_orchard_tutorial.gd").configure_engine(engine,str(descriptor.get("encounter_id","")))
	for unit in engine.state.units:
		if unit.team == 0 and int(owners.get(str(unit.id), 0)) == 0:unit.deck.treasure_pile.clear()

func _receive(value: Dictionary) -> void:
	var op := str(value.get("op", ""))
	if op in ["world1_ready", "world1_result", "world1_rejected", "world1_record_pending", "world1_travel_result"]:
		if not net.connected or str(value.get("campaign_id", "")) != CAMPAIGN:return
		match op:
			"world1_ready":manager.authority_ready(value)
			"world1_result":manager.authority_reused(value)
			"world1_rejected":manager.authority_rejected(value)
			"world1_record_pending":manager.notice(str(value.get("message", "正在保存巡园记录。")))
			"world1_travel_result":manager.authority_travel_result(value)
		return
	var data := value.duplicate(true)
	var starting_id := ""
	var starting_battle_id := ""
	if data.get("descriptor") is Dictionary:
		var info: Dictionary = data.descriptor
		if str(info.get("campaign_id", "")) != CAMPAIGN:return
		var id := str(info.get("encounter_id", ""))
		var local_site: int = manager.site_index(id)
		if local_site < 0:return
		# Server retains all Frost site indexes. Playback resolves SO1 by stable id.
		info["site"] = local_site
		if op in ["open", "observe"] and data.get("members", []).has(local_id()):
			starting_id = id
			starting_battle_id = str(info.get("battle_id", ""))
	if op == "close" and not bool(data.get("observer_only", false)):
		if int(data.get("encounter", -1)) == encounter and active_local:
			# Only authoritative enemy victories count; leaving/disconnection uses -1.
			if int(data.get("winner",-1))==1 and net.connected and str(data.get("battle_id",""))==str(descriptor.get("battle_id","")):
				var lesson_id:=str(descriptor.get("encounter_id",""))
				var attempts:=RetryHelp.record_loss(tutorial_character_key(),lesson_id,str(descriptor.get("battle_id","")))
				if attempts>=2 and is_instance_valid(tutorial_ui):tutorial_ui.show_retry_help(lesson_id)
			manager.accept_close_receipt(data)
	# sync_roster builds E2/E3 from the new authoritative descriptor on admission.
	if op == "join_admit" and is_instance_valid(stage) and data.get("descriptor") is Dictionary:
		stage.encounter_spec = {"enemies":data.descriptor.get("enemies",[]).duplicate(true)}
	super._receive(data)
	if not starting_id.is_empty() and active_local:manager.authority_started(starting_id, starting_battle_id)
	if op == "join_admit" and active_local and manager.active_id.is_empty():
		manager.authority_started(str(descriptor.get("encounter_id","")),str(descriptor.get("battle_id","")))

func _process(delta: float) -> void:
	super._process(delta)
	if not is_instance_valid(stage) or stage.engine == null: return
	var enemies: Array = descriptor.get("enemies",[])
	for unit in stage.engine.state.units:
		if unit.team != 1 or unit.slot >= enemies.size() or not stage.actors.has(unit.id): continue
		var creature := stage.actors[unit.id].get_node_or_null("Body") as Node3D
		if creature == null or creature.has_meta("orchard_variant_applied"): continue
		var variant_id := str(enemies[unit.slot].get("variant_id",""))
		if not variant_id.is_empty():
			if not preload("res://scripts/worlds/star_orchard_variant_materials.gd").apply(creature,variant_id):
				preload("res://scripts/fusion_3d/monster_theme_materials.gd").apply_report(creature,variant_id)
		creature.set_meta("orchard_variant_applied",true)

func _left(peer: int) -> void:
	if peer == 0:manager.authority_disconnected()
	super._left(peer)
