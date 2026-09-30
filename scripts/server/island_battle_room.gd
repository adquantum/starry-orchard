extends Node
## Isolated authoritative battle; nearby observers receive only its public presentation.
signal acknowledged
signal closed(room: Node,departed: Array,winner: int)
const Geo=preload("res://scripts/server/encounter_geometry.gd")
const Wire=preload("res://scripts/fusion_3d/battle_wire.gd")
const Pvp=preload("res://scripts/server/pvp_encounter.gd")
const Allies=preload("res://scripts/worlds/island_ai_allies.gd")
var coordinator: Node
var net: Node
var loadout
var terrain
var ai
var sites: Array=[]
var profiles: Dictionary={}
var test_ai_counts: Dictionary={}
var cooldowns: Dictionary={}
var engine: BattleEngineV2
var members: Array[int]=[]
var owners: Dictionary={}
var descriptor: Dictionary={}
var loaded: Dictionary={}
var arrived: Dictionary={}
var pending_join: Dictionary={}
var awaiting: Dictionary={}
var encounter:=0
var sequence:=0
var gathering:=false
var planning:=false
var resolving:=false
var deadline:=0
var planning_deadline:=0
var scan_tick:=0.0
var awaiting_seq:=-1
var presentation_grace_until:=0
var last_packet: Dictionary={}
var round_steps: Array[Dictionary]=[]
var battle_id:=""
var reward_version:=""
var participant_characters: Dictionary={}
var has_reservation:=false
var settlement_queued:=false
var frozen_winner:=-2
var preparing:=true
var disconnected_slots: Dictionary={}
var reconnect_until:=0
const RECONNECT_GRACE_MS:=90000
const PRESENTATION_LAG_GRACE_MS:=2000
const PLANNING_LAST_PEER_MS:=8000

func configure(manager: Node,transport: Node,shared_loadout,shared_terrain,shared_ai,shared_sites: Array,shared_profiles: Dictionary,shared_cooldowns: Dictionary,id: int) -> void:
	coordinator=manager;net=transport;loadout=shared_loadout;terrain=shared_terrain;ai=shared_ai
	sites=shared_sites;profiles=shared_profiles;cooldowns=shared_cooldowns;encounter=id
	battle_id=Crypto.new().generate_random_bytes(24).hex_encode()

func now() -> float:return Time.get_ticks_msec()/1000.0
func _room_content() -> ContentRegistryV2:
	# Engines register encounter-specific characters/decks; never mutate another room.
	var result:=ContentRegistryV2.new()
	for property in loadout.content.get_property_list():
		if (int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE)==0:continue
		var value: Variant=loadout.content.get(property.name)
		result.set(property.name,value.duplicate(true) if value is Dictionary or value is Array else value)
	return result
func monster_position(site: int,index: int) -> Vector3:
	var at:=Geo.roam_position(sites[site],index,now())
	at.y=Geo.point(sites[site].center).y if bool(sites[site].get("fixed_roam_height",false)) else terrain.height(at)
	return at

func start_pve(index: int,trigger: int,candidates: Array[int]) -> bool:
	if not profiles.has(trigger) or not net.positions.has(trigger):return false
	if not Allies.valid_request(profiles[trigger].get("ai",0)):return false
	members.assign([trigger]);owners.clear()
	for peer in candidates:
		if peer==trigger:continue
		if not profiles.has(peer) or not net.positions.has(peer):continue
		members.append(peer)
		if members.size()>=4:break
	for peer in members:
		if not coordinator._reserve_peer(peer,self):return false
	var party: Array[StringName]=[]
	var loadouts: Array=[]
	var origins: Dictionary={}
	var entering:=members.duplicate()
	for peer in entering:
		var preparation: Dictionary=await coordinator.prepare_profile(int(peer),battle_id,sites[index])
		if not preparation.ok:return false
		has_reservation=true;reward_version=str(preparation.reward_version)
		if not members.has(peer) or not profiles.has(peer):return false
		var id:="P"+str(party.size())
		owners[id]=peer;origins[id]=net.positions[peer]
		party.append(StringName(loadout.character(str(preparation.profile.school))))
		loadouts.append(preparation.profile)
		participant_characters[id]=str(preparation.profile.progression_snapshot.character_id)
	if not profiles.has(trigger) or not members.has(trigger):return false
	var test_override := int(test_ai_counts.get(trigger,0))
	for i in Allies.available_count(profiles[trigger].get("ai",0),party.size(),test_override):
		var helper: Dictionary=Allies.test_profile(loadout.content,loadouts[0],i) if test_override>0 else Allies.profile(loadout.content,loadouts[0],i)
		var school: String=helper.school
		var id:="P"+str(party.size());owners[id]=0
		origins[id]=Geo.point(sites[index].center)+Vector3(0,0,10+i)
		party.append(StringName(loadout.character(school)))
		loadouts.append(helper)
	for i in sites[index].enemies.size():origins["E"+str(i)]=monster_position(index,i)
	engine=preload("res://scripts/fusion_3d/fusion_engine.gd").new()
	engine.party.assign(party);engine.encounter_id=str(sites[index].encounter)
	engine.encounter_spec={"enemies":sites[index].enemies.duplicate(true)}
	if not engine.setup(_room_content(),{},randi()):engine=null;members.clear();return false
	for i in loadouts.size():
		if not engine.configure_deck(StringName("P"+str(i)),loadouts[i].counts):engine=null;members.clear();return false
		if int(owners.get("P"+str(i),0))>0:
			var extras: Dictionary=loadout.configure_extras(engine,StringName("P"+str(i)),loadouts[i])
			if not extras.ok:engine=null;return false
		elif not Allies.configure(engine,StringName("P"+str(i))):engine=null;return false
	engine.start_battle()
	preparing=false
	descriptor={"id":encounter,"battle_id":battle_id,"site":index,"enemies":engine.encounter_spec.enemies.duplicate(true),"party":party,"loadouts":loadouts,"origins":origins,"appearances":net.appearances.duplicate(true)}
	deadline=Time.get_ticks_msec()+90000
	_publish({"op":"open","descriptor":descriptor,"owners":owners,"members":members})
	print("ENCOUNTER_OPEN id=",encounter," site=",index," trigger=",trigger," members=",members)
	return true

func start_pvp(index: int,value: Dictionary) -> bool:
	descriptor=value.duplicate(true);descriptor.id=encounter;descriptor.site=index
	members.assign([])
	for combatant in descriptor.combatants:members.append(int(combatant.peer))
	owners.clear()
	for combatant in descriptor.combatants:owners[combatant.id]=int(combatant.peer)
	for peer in members:
		if not coordinator._reserve_peer(peer,self):return false
	for combatant in descriptor.combatants:
		var preparation: Dictionary=await coordinator.prepare_profile(int(combatant.peer),battle_id,sites[index])
		if not preparation.ok:return false
		has_reservation=true;reward_version=str(preparation.reward_version)
		if not members.has(int(combatant.peer)):return false
		combatant.profile=preparation.profile
		participant_characters[str(combatant.id)]=str(preparation.profile.progression_snapshot.character_id)
	descriptor.loadouts=[]
	for combatant in descriptor.combatants:
		if int(combatant.team)==0:descriptor.loadouts.append(combatant.profile)
	engine=preload("res://scripts/fusion_3d/fusion_engine.gd").new()
	engine.party.assign(descriptor.party);engine.encounter_id="frost_pvp"
	if not engine.setup(_room_content(),{},randi()):engine=null;members.clear();return false
	engine.state.units.clear();engine.state.actions.clear();engine.state.round_index=0
	engine.state.pvp=true;engine.state.first_team=int(descriptor.first_team)
	for combatant in descriptor.combatants:
		var profile: Dictionary=combatant.profile
		var unit:=engine._create_unit(StringName(loadout.character(str(profile.school))),int(combatant.team),int(combatant.slot))
		engine.state.units.append(unit)
		if not engine.configure_deck(unit.id,profile.counts):engine=null;return false
		var extras: Dictionary=loadout.configure_extras(engine,unit.id,profile)
		if not extras.ok:engine=null;return false
		unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
		if unit.team!=engine.state.first_team:unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
	engine.start_battle();preparing=false
	deadline=Time.get_ticks_msec()+90000
	_publish({"op":"open","descriptor":descriptor,"owners":owners,"members":members})
	print("ENCOUNTER_OPEN id=",encounter," site=",index," pvp=true members=",members)
	return true

func accepts(peer: int) -> bool:
	return members.has(peer) or (not pending_join.is_empty() and int(pending_join.peer)==peer)

func observe(peer: int) -> void:
	if engine==null:return
	var participant:=members.has(peer)
	if not participant and not coordinator.observing(peer,self):return
	var packet:={"op":"observe","descriptor":descriptor,"owners":owners,"members":members,"state":Wire.pack(engine.state),"seq":sequence-1 if resolving else sequence}
	if resolving and last_packet.get("op","")=="round_batch":packet.seq=int(last_packet.steps[0].seq)-1
	net.publish(Wire.project_packet(packet,engine.state,owners,peer) if participant else _public_packet(packet),peer)
	if resolving and not last_packet.is_empty():net.publish(Wire.project_packet(last_packet,engine.state,owners,peer) if participant else _public_packet(last_packet),peer)

func request(peer: int,data: Dictionary) -> void:
	if engine==null or int(data.get("encounter",-1))!=encounter:return
	match str(data.get("op","")):
		"flee":
			if not planning or not members.has(peer):return
			_publish({"op":"fled","encounter":encounter},peer)
			# The leaver is removed from room routing below, so close its local battle now.
			_publish({"op":"close","encounter":encounter,"winner":-1},peer)
			net.positions[peer]=Geo.point(sites[int(descriptor.site)].approach);net.last_seen[peer]=Time.get_ticks_msec()
			peer_left(peer,true)
		"loaded":
			if members.has(peer):loaded[peer]=true;_check_ready()
		"arrived":
			if members.has(peer) and gathering:arrived[peer]=true;_check_ready()
		"command":
			if planning and Time.get_ticks_msec()<planning_deadline and _command(peer,data):
				_shorten_planning_for_last_peer()
				_planning_packet(peer,str(data.get("command","")) in ["draw","discard","fuse"])
				if _all_selected():_resolve()
		"step_presented":
			if int(data.get("seq",-1))==awaiting_seq and awaiting.has(peer):
				awaiting.erase(peer)
				_update_presentation_gate()
		"join_loaded":
			if not pending_join.is_empty() and int(data.get("joining",-1))==int(pending_join.peer) and (members.has(peer) or peer==int(pending_join.peer)):
				pending_join.ready[peer]=true
				if planning:_try_admit()

func _process(delta: float) -> void:
	if engine==null:return
	var ticks:=Time.get_ticks_msec()
	var slot_expired:=false
	for id in disconnected_slots.keys():
		if ticks<int(disconnected_slots[id]):continue
		disconnected_slots.erase(id)
		slot_expired=true
		var abandoned:=engine.state.unit_by_id(StringName(str(id)))
		if abandoned!=null:abandoned.alive=false;abandoned.hp=0;engine.state.actions.erase(abandoned.id)
	if slot_expired and engine.state.pvp and engine.check_battle_end():
		finish(engine.state.winner_team);return
	if members.is_empty():
		if reconnect_until>0 and ticks>=reconnect_until:finish(-1)
		return
	scan_tick+=delta
	if scan_tick>=0.1:scan_tick=0;_scan_late()
	if not awaiting.is_empty() and (ticks>=deadline or (presentation_grace_until>0 and ticks>=presentation_grace_until)):
		awaiting.clear();awaiting_seq=-1;presentation_grace_until=0;acknowledged.emit()
	elif not planning and not resolving and Time.get_ticks_msec()>deadline:
		finish(-1)
	# A downed player cannot send a command to trigger the usual readiness check.
	# Only living humans can hold planning open; AI-only turns advance immediately.
	elif planning and (_all_selected() or Time.get_ticks_msec()>=planning_deadline):
		_resolve()
	if not pending_join.is_empty() and Time.get_ticks_msec()>int(pending_join.deadline):
		var joining:=int(pending_join.peer)
		_publish({"op":"join_cancel","encounter":encounter});pending_join.clear()
		coordinator._release_peer(joining,self)

func _check_ready() -> void:
	if planning or resolving:return
	for peer in members:
		if not loaded.has(peer):return
	if not gathering:
		gathering=true;print("ROOM_GATHER id=",encounter," members=",members);_publish({"op":"gather","encounter":encounter});return
	for peer in members:
		if not arrived.has(peer):return
	_begin_planning()

func _begin_planning() -> void:
	planning=true;planning_deadline=Time.get_ticks_msec()+30000
	_try_admit();_planning_packet()

func _planning_packet(changed_peer: int=0,include_deck: bool=false) -> void:
	if engine==null:return
	sequence+=1
	var is_delta:=changed_peer>0
	var state: Dictionary=Wire.pack_planning_delta(engine.state,owners,changed_peer,include_deck) if is_delta else Wire.pack(engine.state)
	_publish({"op":"step","encounter":encounter,"seq":sequence,"kind":"planning","planning_delta":is_delta,"state":state,"remaining":maxf(0.0,(planning_deadline-Time.get_ticks_msec())/1000.0)})

func _all_selected() -> bool:
	for unit in engine.state.living_units(engine.state.active_team if engine.state.pvp else 0):
		if int(owners.get(str(unit.id),0))>0 and not engine.state.actions.has(unit.id):return false
	return true

func _shorten_planning_for_last_peer() -> void:
	var ready:=0
	var pending:=0
	for unit in engine.state.living_units(engine.state.active_team if engine.state.pvp else 0):
		if int(owners.get(str(unit.id),0))<=0:continue
		if engine.state.actions.has(unit.id):ready+=1
		else:pending+=1
	if ready>0 and pending==1:
		planning_deadline=mini(planning_deadline,Time.get_ticks_msec()+PLANNING_LAST_PEER_MS)

func _command(peer: int,data: Dictionary) -> bool:
	if int(data.get("round",-1))!=engine.state.round_index:return false
	var id:=StringName(str(data.get("actor","")))
	var unit:=engine.state.unit_by_id(id)
	if unit==null or not unit.alive or int(owners.get(str(id),0))!=peer:return false
	var command:=str(data.get("command",""))
	if engine.state.pvp and unit.team!=engine.state.active_team and command not in ["draw","discard","charge"]:return false
	if command=="cancel":
		if not engine.state.actions.has(id):return false
		engine.state.actions.erase(id);unit.planned_action=null;return true
	if engine.state.actions.has(id):return false
	match command:
		"pass":return engine.queue_pass(id)
		"cast":
			if not data.get("targets",[]) is Array or data.get("targets",[]).size()>8:return false
			var targets: Array[StringName]=[]
			for target in data.get("targets",[]):targets.append(StringName(str(target)))
			return engine.queue_action(ActionIntentV2.cast(id,int(data.get("card",-1)),targets))
		"draw":return engine.draw_one_treasure(id)!=null
		"discard":return engine.discard_for_treasure(id,int(data.get("card",-1)))
		"fuse":return engine.fuse_cards(id,int(data.get("first",-1)),int(data.get("second",-1)))!=null
		"charge":
			var school:=str(data.get("school",""))
			if school in loadout.SCHOOLS:engine.set_next_charge(id,StringName(school));return true
		"auto":
			for player in engine.state.living_units(engine.state.active_team if engine.state.pvp else 0):
				if int(owners.get(str(player.id),0))==peer and not engine.state.actions.has(player.id):engine.queue_action(ai.choose_action(engine,player))
			return true
	return false

func _publish_present(kind: String,extra: Dictionary={}) -> void:
	sequence+=1
	var compact:=kind in ["turn","action"]
	last_packet={"op":"step","encounter":encounter,"seq":sequence,"kind":kind,"state":Wire.pack_view(engine.state) if compact else Wire.pack(engine.state)}
	if compact:last_packet.compact=true
	last_packet.merge(extra)
	if compact:
		round_steps.append(last_packet)
		return
	if kind=="round_end" and not round_steps.is_empty():
		round_steps.append(last_packet)
		last_packet=Wire.round_packet(round_steps,encounter,sequence)
		round_steps.clear()
	_publish(last_packet)

func _present(kind: String,extra: Dictionary={}) -> void:
	awaiting_seq=sequence+1;awaiting.clear()
	presentation_grace_until=0
	for peer in members:awaiting[peer]=true
	deadline=Time.get_ticks_msec()+90000
	_publish_present(kind,extra)
	if not awaiting.is_empty():await acknowledged
	while engine!=null and members.is_empty():await acknowledged

func _update_presentation_gate() -> void:
	if awaiting.is_empty():
		awaiting_seq=-1;presentation_grace_until=0;acknowledged.emit()
	elif awaiting.size()==1 and members.size()>1 and presentation_grace_until==0:
		presentation_grace_until=Time.get_ticks_msec()+PRESENTATION_LAG_GRACE_MS

func _resolve() -> void:
	if resolving or not planning or coordinator.progression.stopped:return
	planning=false;resolving=true
	round_steps.clear()
	var current:=engine
	for unit in engine.state.living_units(engine.state.active_team if engine.state.pvp else 0):
		if not engine.state.actions.has(unit.id):
			if int(owners.get(str(unit.id),0))==0:engine.queue_action(ai.choose_action(engine,unit))
			else:engine.queue_pass(unit.id)
	if not engine.state.pvp:
		for enemy in engine.state.living_units(1):engine.queue_action(ai.choose_action(engine,enemy))
	engine.begin_resolution()
	for actor in engine.turn_manager.resolution_order(engine.state):
		if not actor.alive or not engine.state.actions.has(actor.id):continue
		var before: Dictionary=Wire.pack_view(engine.state)
		var events:=engine.begin_actor_turn(actor)
		_publish_present("turn",{"before":before,"events":Wire.pack(events),"actor":str(actor.id)})
		if engine.state.phase==BattleStateV2.Phase.FINISHED:break
		if not actor.alive:continue
		var intent: ActionIntentV2=engine.state.actions.get(actor.id)
		var spell: CardDefinitionV2
		var targets: Array[StringName]=[]
		if intent!=null and not intent.pass_action:
			var card:=engine.card_in_hand(actor,intent.card_instance_id)
			if card!=null:
				spell=card.definition
				for target in engine.target_resolver.resolve_selected(engine.state,actor,spell,intent.target_ids):targets.append(target.id)
		before=Wire.pack_view(engine.state);events=engine.resolve_actor_action(actor)
		if not _journal_consumption(events):return
		_publish_present("action",{"before":before,"events":Wire.pack(events),"actor":str(actor.id),"card":str(spell.id) if spell!=null else "","targets":targets})
		if engine.state.phase==BattleStateV2.Phase.FINISHED:break
	engine.end_resolution()
	# Freeze result and eligible humans durably BEFORE any client presentation await.
	if engine.state.phase==BattleStateV2.Phase.FINISHED:
		if not _queue_settlement(engine.state.winner_team):return
	await _present("round_end",{"round":engine.state.round_index})
	if engine!=current:return
	if engine.state.phase==BattleStateV2.Phase.FINISHED:
		await _present("finished")
		if engine==current:finish(engine.state.winner_team)
		return
	engine.start_next_round();resolving=false;last_packet.clear()
	if members.is_empty():planning=false;return
	_begin_planning()

func _scan_late() -> void:
	if settlement_queued or not gathering or not (planning or resolving) or not pending_join.is_empty() or owners.size()>=(8 if engine.state.pvp else 4):return
	var site: Dictionary=sites[int(descriptor.site)]
	for value in net.positions:
		var peer:=int(value)
		if members.has(peer) or not coordinator.peer_available(peer) or not Geo.in_arena(net.positions[peer],site):continue
		var team:=Pvp.team_at(net.positions[peer],site) if engine.state.pvp else 0
		var slot:=Pvp.free_slot(owners,team)
		if slot<0 or not coordinator._reserve_peer(peer,self):continue
		pending_join={"peer":peer,"reserving":true,"ready":{},"deadline":Time.get_ticks_msec()+90000}
		var preparation: Dictionary=await coordinator.prepare_profile(peer,battle_id,site)
		if preparation.ok:has_reservation=true
		if engine==null or settlement_queued:return
		if not preparation.ok or pending_join.is_empty() or not profiles.has(peer):
			pending_join.clear();coordinator._release_peer(peer,self);return
		pending_join={"team":team,"peer":peer,"slot":slot,"profile":preparation.profile,"appearance":net.appearances.get(peer,{}).duplicate(true),"origin":net.positions[peer],"round":engine.state.round_index+1,"ready":{},"deadline":Time.get_ticks_msec()+90000}
		_publish({"op":"join_prepare","encounter":encounter,"descriptor":descriptor,"owners":owners,"members":members,"pending":pending_join,"state":Wire.pack(engine.state),"seq":sequence,"pause":false})
		return

func _try_admit() -> void:
	if pending_join.is_empty() or pending_join.get("reserving",false) or not planning or int(pending_join.round)>engine.state.round_index:return
	for peer in members+[int(pending_join.peer)]:
		if not pending_join.ready.has(peer):return
	var peer:=int(pending_join.peer)
	var profile: Dictionary=pending_join.profile
	var unit: BattleUnitStateV2=engine._create_unit(StringName(loadout.character(str(profile.school))),int(pending_join.get("team",0)),int(pending_join.slot))
	engine.state.units.append(unit);engine.configure_deck(unit.id,profile.counts)
	var extras: Dictionary=loadout.configure_extras(engine,unit.id,profile)
	if not extras.ok:
		engine.state.units.erase(unit);pending_join.clear();coordinator._release_peer(peer,self)
		_publish({"op":"join_cancel","encounter":encounter});return
	unit.deck.draw_to_limit();unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
	owners[str(unit.id)]=peer;members.append(peer)
	participant_characters[str(unit.id)]=str(profile.progression_snapshot.character_id)
	if unit.team==0:descriptor.party.append(StringName(loadout.character(str(profile.school))));descriptor.loadouts.append(profile)
	if engine.state.pvp:descriptor.combatants.append({"id":str(unit.id),"team":unit.team,"slot":unit.slot,"peer":peer,"profile":profile})
	descriptor.appearances[peer]=pending_join.appearance;descriptor.origins[str(unit.id)]=pending_join.origin
	_publish({"op":"join_admit","encounter":encounter,"descriptor":descriptor,"owners":owners,"members":members,"state":Wire.pack(engine.state)})
	pending_join.clear();planning_deadline=Time.get_ticks_msec()+30000;_planning_packet()

func peer_left(peer: int,voluntary: bool=false) -> void:
	if not pending_join.is_empty() and int(pending_join.peer)==peer:
		_publish({"op":"join_cancel","encounter":encounter});pending_join.clear()
	members.erase(peer);loaded.erase(peer);arrived.erase(peer);awaiting.erase(peer)
	coordinator._release_peer(peer,self)
	for id in owners:
		if int(owners[id])==peer:
			owners[id]=-1
			if not voluntary:disconnected_slots[id]=Time.get_ticks_msec()+RECONNECT_GRACE_MS
			if engine!=null:
				var unit:=engine.state.unit_by_id(StringName(id))
				if unit!=null:
					engine.state.actions.erase(unit.id)
					if voluntary:unit.alive=false;unit.hp=0
	if engine==null:return
	if members.is_empty():
		if voluntary:finish(-1);return
		reconnect_until=Time.get_ticks_msec()+RECONNECT_GRACE_MS
	if engine.state.pvp and engine.check_battle_end():finish(engine.state.winner_team);return
	_publish({"op":"roster","encounter":encounter,"owners":owners,"members":members})
	_update_presentation_gate()
	if not members.is_empty():
		_check_ready()
		if planning:_try_admit();_planning_packet()

func try_rejoin(peer: int,character_id: String) -> bool:
	if engine==null or settlement_queued or character_id.is_empty():return false
	var matched: String=""
	for id in disconnected_slots:
		if str(participant_characters.get(id,""))==character_id and Time.get_ticks_msec()<int(disconnected_slots[id]):
			matched=str(id);break
	if matched.is_empty() or not coordinator._reserve_peer(peer,self):return false
	disconnected_slots.erase(matched);owners[matched]=peer;members.append(peer)
	reconnect_until=0
	descriptor.appearances[peer]=net.appearances.get(peer,{}).duplicate(true)
	if engine.state.pvp:
		for combatant in descriptor.combatants:
			if str(combatant.id)==matched:combatant.peer=peer
	else:descriptor.origins[matched]=net.positions.get(peer,Geo.point(sites[int(descriptor.site)].approach))
	observe(peer)
	_publish({"op":"roster","encounter":encounter,"owners":owners,"members":members})
	if planning:
		planning_deadline=Time.get_ticks_msec()+30000
		_planning_packet()
	elif not resolving:
		_begin_planning()
	acknowledged.emit()
	return true

func _has_human_players() -> bool:
	for owner in owners.values():
		var peer:=int(owner)
		if peer>0 and members.has(peer):return true
	return false

func finish(winner: int) -> void:
	if engine==null:return
	if not _queue_settlement(winner):return
	if settlement_queued and frozen_winner>=0:winner=frozen_winner
	var departed: Array=[];departed.assign(members)
	if not pending_join.is_empty():departed.append(int(pending_join.peer))
	coordinator.begin_site_cooldown(int(descriptor.site))
	var exit_positions:=Geo.scattered_exits(sites[int(descriptor.site)],departed)
	for peer in departed:
		net.position_frozen.erase(peer);net.positions[peer]=exit_positions[peer];net.last_seen[peer]=Time.get_ticks_msec()
	_publish({"op":"close","encounter":encounter,"winner":winner,"exit_positions":exit_positions})
	print("ENCOUNTER_CLOSE id=",encounter," winner=",winner)
	engine=null;members.clear();owners.clear();pending_join.clear();awaiting.clear();last_packet.clear()
	planning=false;resolving=false;gathering=false;awaiting_seq=-1;acknowledged.emit()
	closed.emit(self,departed,winner)

func _journal_consumption(events: Array) -> bool:
	for event in events:
		if event.type!=&"TreasureConsumed":continue
		var payload: Dictionary=event.payload
		var unit_id:=str(payload.get("unit_id",""))
		if not participant_characters.has(unit_id):continue
		if not coordinator.progression.enqueue("consume",{"battle_id":battle_id,"character_id":participant_characters[unit_id],"card_id":str(payload.card_id),"token":str(payload.token)}):return false
	return true

func _queue_settlement(winner: int) -> bool:
	if settlement_queued:return true
	if not has_reservation:return true
	var winners: Array=[]
	if winner==0 and engine!=null and not engine.state.pvp and engine.state.phase==BattleStateV2.Phase.FINISHED:
		for id in participant_characters:
			var peer:=int(owners.get(id,0))
			if peer>0 and members.has(peer):winners.append(participant_characters[id])
	if not coordinator.progression.enqueue("finish",{"battle_id":battle_id,"winners":winners,"reward_version":reward_version}):return false
	settlement_queued=true;frozen_winner=winner
	print("PROGRESSION_FROZEN battle=",battle_id," winner=",winner," eligible_humans=",winners.size()," version=",reward_version)
	return true

func cancel_preparation() -> void:
	_queue_settlement(-1)

func _publish(data: Dictionary,peer: int=0) -> void:
	if str(data.get("op",""))=="open" and engine!=null:
		data=data.duplicate();data.state=Wire.pack(engine.state)
	if peer>1:
		net.publish(Wire.project_packet(data,engine.state,owners,peer) if engine!=null else data,peer);return
	var recipients: Array=[];recipients.assign(members)
	if not pending_join.is_empty() and not recipients.has(int(pending_join.peer)):recipients.append(int(pending_join.peer))
	for recipient in recipients:net.publish(Wire.project_packet(data,engine.state,owners,int(recipient)),int(recipient))
	var observers: Array[int]=coordinator.observer_recipients(self)
	if observers.is_empty():return
	var public:=_public_packet(data)
	if not public.is_empty():
		for observer in observers:net.publish(public,observer)

func _public_packet(data: Dictionary) -> Dictionary:
	if str(data.get("op","")) not in ["observe","step","round_batch","roster","join_admit","close"]:return {}
	return Wire.project_packet(data,engine.state,owners,0)

func _public_state(state: Dictionary) -> Dictionary:
	var result: Dictionary=state.duplicate(true)
	var fields: Dictionary=result.get("fields",{})
	fields.actions={}
	for unit in fields.get("units",[]):
		var body: Dictionary=unit.get("fields",{})
		body.planned_action=null
		body.deck={"$type":"DeckStateV2","fields":{}}
	return result
