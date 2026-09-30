extends "res://scripts/server/island_battle_room.gd"
## SO1 uses the authenticated room engine, without Frost economic transactions.
const Tutorial = preload("res://scripts/server/star_orchard_tutorial.gd")
const CAMPAIGN := "star_orchard_world1_v2"
var victory_receipts: Dictionary = {}

func start_pve(index: int, trigger: int, candidates: Array[int]) -> bool:
	if not profiles.has(trigger) or not net.positions.has(trigger):return false
	if not Allies.valid_request(profiles[trigger].get("ai",0)):return false
	if not coordinator.orchard_authority.is_peer(trigger):return false
	var id := str(sites[index].id)
	var tutorial := Tutorial.is_tutorial(id)
	members.clear();owners.clear()
	var entering: Array[int] = [trigger]
	if not tutorial:
		for peer in candidates:
			if peer != trigger and entering.size() < 4 and coordinator.orchard_authority.can_join(peer,id):entering.append(peer)
	var party: Array[StringName] = []
	var loadouts: Array = []
	var origins: Dictionary = {}
	for peer in entering:
		if not coordinator._reserve_peer(peer,self):return false
		members.append(peer)
		var profile: Dictionary = profiles[peer].duplicate(true)
		profile["treasures"] = {};profile["treasure_tokens"] = {}
		if tutorial:profile["counts"] = Tutorial.deck_counts(id,str(profile.school))
		var character := str(profile.get("progression_snapshot",{}).get("character_id",""))
		if character.is_empty():return false
		var unit_id := "P" + str(party.size())
		owners[unit_id]=peer;participant_characters[unit_id]=character
		party.append(StringName(loadout.character(str(profile.school))))
		loadouts.append(profile);origins[unit_id]=net.positions[peer]
	if id=="SO1_T05":
		var school: String=Tutorial.Fixed.Finale.partner(str(profiles[trigger].school))
		owners["P1"]=0;origins["P1"]=Geo.point(sites[index].approach)+Vector3(2,0,2)
		party.append(StringName(loadout.character(school)))
		loadouts.append({"school":school,"counts":Tutorial.Fixed.counts(Tutorial.Fixed.Finale.deck(school,true)),"treasures":{}})
	if not tutorial:
		var test_override := int(test_ai_counts.get(trigger,0))
		for i in Allies.available_count(profiles[trigger].get("ai",0),party.size(),test_override):
			var helper: Dictionary = Allies.test_profile(loadout.content,loadouts[0],i) if test_override>0 else Allies.profile(loadout.content,loadouts[0],i)
			var school: String = helper.school
			var unit_id := "P" + str(party.size())
			owners[unit_id]=0;origins[unit_id]=Geo.point(sites[index].approach)+Vector3(float(i)*2.0,0,2)
			var actor := StringName(loadout.character(school))
			party.append(actor)
			loadouts.append(helper)
	var enemy_specs: Array = Tutorial.enemies(id,members.size()) if tutorial else sites[index].enemies.duplicate(true)
	for i in enemy_specs.size():origins["E"+str(i)]=monster_position(index,i)
	engine=preload("res://scripts/fusion_3d/fusion_engine.gd").new()
	engine.party.assign(party);engine.encounter_id=id
	# Register the possible reinforcements in the room-local registry once.
	engine.encounter_spec={"enemies":Tutorial.enemies(id,4) if tutorial else enemy_specs}
	if not engine.setup(_room_content(),{},randi()):engine=null;return false
	if tutorial:
		for unit in engine.state.units.duplicate():
			if unit.team==1 and unit.slot>=enemy_specs.size():engine.state.units.erase(unit)
		engine.encounter_spec.enemies=enemy_specs.duplicate(true)
		if not Tutorial.configure_engine(engine,id):engine=null;return false
	else:
		for i in loadouts.size():
			var unit_id := StringName("P"+str(i))
			if not engine.configure_deck(unit_id,loadouts[i].counts):engine=null;return false
			engine.state.unit_by_id(unit_id).deck.treasure_pile.clear()
			if int(owners.get(str(unit_id),0))>0:
				var extras: Dictionary = loadout.configure_extras(engine,unit_id,loadouts[i])
				if not bool(extras.get("ok",false)):engine=null;return false
			elif not Allies.configure(engine,unit_id):engine=null;return false
	engine.start_battle();preparing=false
	var room_appearances: Dictionary = {}
	for member in members:room_appearances[member] = net.appearances.get(member, {}).duplicate(true)
	descriptor={"id":encounter,"battle_id":battle_id,"site":index,"campaign_id":CAMPAIGN,"encounter_id":id,"enemies":enemy_specs.duplicate(true),"party":party,"loadouts":loadouts,"origins":origins,"appearances":room_appearances}
	if tutorial:descriptor["tutorial"]=Tutorial.metadata(id)
	deadline=Time.get_ticks_msec()+90000
	_publish({"op":"open","descriptor":descriptor,"owners":owners,"members":members})
	print("SO1_ENCOUNTER_OPEN id=",encounter," story=",id," humans=",members.size()," enemies=",enemy_specs.size())
	return true

func _begin_planning() -> void:
	if not descriptor.has("tutorial"):super._begin_planning();return
	planning=true;planning_deadline=Time.get_ticks_msec()+90000
	# Fix lesson intent before player selection; generic AI cannot replace it.
	# Private action filtering keeps enemy intentions out of the command payload.
	if Tutorial.Fixed.active(str(descriptor.get("encounter_id",""))):
		for enemy in engine.state.living_units(1):
			if not engine.state.actions.has(enemy.id):
				engine.queue_action(Tutorial.Fixed.enemy_action(engine,enemy))
	if str(descriptor.get("encounter_id",""))=="SO1_T05":
		var ally:=engine.state.unit_by_id(&"P1")
		if ally!=null and ally.alive and not engine.state.actions.has(ally.id):
			engine.queue_action(Tutorial.Fixed.Finale.choose(engine,ally))
	_try_admit();_planning_packet()

func _shorten_planning_for_last_peer() -> void:
	if not descriptor.has("tutorial"):super._shorten_planning_for_last_peer()

func _scan_late() -> void:
	if descriptor.has("tutorial"):return
	if not descriptor.has("tutorial") or settlement_queued or not gathering or not (planning or resolving) or not pending_join.is_empty() or owners.size()>=4:return
	var site: Dictionary=sites[int(descriptor.site)]
	for value in net.positions:
		var peer:=int(value)
		if members.has(peer) or not coordinator.orchard_authority.can_join(peer,str(descriptor.encounter_id)) or not Geo.in_arena(net.positions[peer],site):continue
		var slot:=Pvp.free_slot(owners,0)
		if slot<0 or not coordinator._reserve_peer(peer,self):continue
		var profile: Dictionary=profiles[peer].duplicate(true)
		profile.treasures={};profile.treasure_tokens={};profile.counts=Tutorial.deck_counts(str(descriptor.encounter_id),str(profile.school))
		pending_join={"team":0,"peer":peer,"slot":slot,"profile":profile,"appearance":net.appearances.get(peer,{}).duplicate(true),"origin":net.positions[peer],"round":engine.state.round_index+1,"ready":{},"deadline":Time.get_ticks_msec()+180000}
		var enemy_slot: int = descriptor.enemies.size()
		if owners.size()+1 > enemy_slot:
			pending_join.reinforcement_slot=enemy_slot
			pending_join.reinforcement=Tutorial.enemies(str(descriptor.encounter_id),4)[enemy_slot]
		_publish({"op":"join_prepare","encounter":encounter,"descriptor":descriptor,"owners":owners,"members":members,"pending":pending_join,"state":Wire.pack(engine.state),"seq":sequence,"pause":false})
		return

func _try_admit() -> void:
	if descriptor.has("tutorial"):return
	if not descriptor.has("tutorial"):return
	if pending_join.is_empty() or not planning or int(pending_join.round)>engine.state.round_index:return
	for peer in members+[int(pending_join.peer)]:
		if not pending_join.ready.has(peer):return
	var peer:=int(pending_join.peer)
	if not profiles.has(peer):return
	var profile: Dictionary=pending_join.profile
	var unit: BattleUnitStateV2=engine._create_unit(StringName(loadout.character(str(profile.school))),0,int(pending_join.slot))
	engine.state.units.append(unit)
	if not Tutorial.configure_unit(engine,str(descriptor.encounter_id),unit):
		engine.state.units.erase(unit);pending_join.clear();coordinator._release_peer(peer,self)
		_publish({"op":"join_cancel","encounter":encounter});return
	unit.resources.append_pip(ResourceStateV2.PipKind.POWER if Tutorial.lesson(str(descriptor.encounter_id))>=2 else ResourceStateV2.PipKind.NORMAL)
	owners[str(unit.id)]=peer;members.append(peer)
	participant_characters[str(unit.id)]=str(profile.progression_snapshot.character_id)
	descriptor.party.append(StringName(loadout.character(str(profile.school))));descriptor.loadouts.append(profile)
	descriptor.appearances[peer]=pending_join.appearance;descriptor.origins[str(unit.id)]=pending_join.origin
	if pending_join.has("reinforcement"):
		var spec: Dictionary=pending_join.reinforcement
		var enemy_slot:=int(pending_join.reinforcement_slot)
		var reinforcement: BattleUnitStateV2=engine._create_unit(StringName(str(spec.id)),1,enemy_slot)
		engine.state.units.append(reinforcement)
		reinforcement.deck.draw_to_limit();reinforcement.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
		descriptor.enemies.append(spec.duplicate(true));engine.encounter_spec.enemies=descriptor.enemies.duplicate(true)
		descriptor.origins[str(reinforcement.id)]=monster_position(int(descriptor.site),enemy_slot)
	_publish({"op":"join_admit","encounter":encounter,"descriptor":descriptor,"owners":owners,"members":members,"state":Wire.pack(engine.state)})
	pending_join.clear();planning_deadline=Time.get_ticks_msec()+90000;_planning_packet()

func _queue_settlement(winner: int) -> bool:
	if settlement_queued:return true
	if engine == null:return true
	var actual_win: bool = winner == 0 and engine.state.phase == BattleStateV2.Phase.FINISHED and engine.state.winner_team == 0
	if actual_win:
		for unit_id in participant_characters:
			var peer := int(owners.get(unit_id, 0))
			var receipt: Dictionary = coordinator.orchard_authority.record_victory(str(participant_characters[unit_id]), str(descriptor.encounter_id), battle_id)
			if receipt.is_empty():
				_publish({"op": "world1_record_pending", "message": "已经获胜，服务器正在保存巡园记录。请稍候。"}, peer)
				deadline = Time.get_ticks_msec() + 3000
				return false
			if peer > 0 and members.has(peer):victory_receipts[peer] = receipt
	settlement_queued = true
	frozen_winner = 0 if actual_win else -1
	return true

func finish(winner: int) -> void:
	# A failed journal write must never convert a real win into an unearned loss.
	if engine != null and engine.state.phase == BattleStateV2.Phase.FINISHED and engine.state.winner_team == 0:winner = 0
	var fixed_lesson := Tutorial.Fixed.active(str(descriptor.get("encounter_id","")))
	var finished_site := int(descriptor.get("site",-1))
	super.finish(winner)
	if fixed_lesson and engine == null and finished_site >= 0:
		cooldowns[finished_site]=Time.get_ticks_msec()/1000.0+5.0

func _publish(data: Dictionary, peer: int = 0) -> void:
	var packet := data.duplicate(true)
	packet["campaign_id"] = CAMPAIGN
	packet["encounter_id"] = str(descriptor.get("encounter_id", ""))
	packet["battle_id"] = battle_id
	if str(packet.get("op", "")) == "close":
		# Receipts are sent separately to each eligible participant, never observers.
		var recipients: Array = [peer] if peer > 1 else members.duplicate()
		for recipient in recipients:
			var individual := packet.duplicate(true)
			individual["receipt"] = victory_receipts.get(int(recipient), {}).duplicate(true)
			net.publish(individual, int(recipient))
		if peer <= 1:
			for observer in coordinator.observer_recipients(self):net.publish(_public_packet(packet), observer)
		return
	super._publish(packet, peer)

func _public_packet(data: Dictionary) -> Dictionary:
	var result := super._public_packet(data)
	if result.is_empty():return result
	result["campaign_id"] = CAMPAIGN
	result["encounter_id"] = str(descriptor.get("encounter_id", ""))
	if result.get("descriptor") is Dictionary:
		result.descriptor["campaign_id"] = CAMPAIGN
		result.descriptor["encounter_id"] = str(descriptor.get("encounter_id", ""))
	result.erase("receipt")
	return result
