extends RefCounted
## Data-only codec. No remote objects, scripts, paths, or executable variants.
const TYPES={
 "BattleStateV2":preload("res://scripts/battle_v2/model/battle_state_v2.gd"),
 "BattleUnitStateV2":preload("res://scripts/battle_v2/model/battle_unit_state_v2.gd"),
 "ResourceStateV2":preload("res://scripts/battle_v2/model/resource_state_v2.gd"),
 "DeckStateV2":preload("res://scripts/battle_v2/model/deck_state_v2.gd"),
 "CardInstanceV2":preload("res://scripts/battle_v2/model/card_instance_v2.gd"),
 "StatusInstanceV2":preload("res://scripts/battle_v2/model/status_instance_v2.gd"),
 "ActionIntentV2":preload("res://scripts/battle_v2/model/action_intent_v2.gd"),
 "BattleEventV2":preload("res://scripts/battle_v2/model/battle_event_v2.gd")}
const FIELDS={
 "BattleStateV2":["units","pvp","first_team","active_team","round_index","phase","winner_team","actions","global_statuses"],
 "BattleUnitStateV2":["id","character_id","name_key","team","slot","school_id","max_hp","hp","archmastery","ai_profile_id","alive","stats","resources","deck","statuses","planned_action","action_slot_passed"],
 "ResourceStateV2":["pips","pip_schools","shadow_pips","shadow_progress","archmastery_charge","charge_school","next_charge_school"],
 "DeckStateV2":["draw_pile","hand","discard_pile","treasure_pile","removed_cards","discard_count_this_round","treasure_draw_count_this_round","fusion_draw_credits"],
 "CardInstanceV2":["instance_id","definition","treasure_locked","temporary","inventory_token","equipment"],
 "StatusInstanceV2":["instance_id","definition_id","kind","source_id","source_group","caster_id","school_filter","school_filters","value","ticks","payload"],
 "ActionIntentV2":["actor_id","card_instance_id","card_definition_id","target_ids","pass_action","cancelled"],
 "BattleEventV2":["type","sequence","round_index","payload"]}
const PRIVATE_EVENTS=["ActionQueued","CardDrawn","TreasureDrawn","CardDiscarded","TreasureConsumed","DeckConfigured","ChargeSchoolSelected","CardsFused"]

static func round_packet(steps: Array[Dictionary],encounter: int,sequence: int) -> Dictionary:
	var packed_steps: Array[Dictionary]=[]
	var previous: Dictionary={}
	for original in steps:
		var step: Dictionary=original.duplicate()
		if step.has("before") and not previous.is_empty() and step.before==previous:
			step.erase("before");step.before_previous=true
		packed_steps.append(step)
		previous=original.get("state",{})
	return {"op":"round_batch","encounter":encounter,"seq":sequence,"steps":packed_steps}

static func expand_round(packet: Dictionary) -> Array[Dictionary]:
	var steps: Array[Dictionary]=[]
	var previous: Dictionary={}
	for original in packet.get("steps",[]):
		var step: Dictionary=original.duplicate()
		if bool(step.get("before_previous",false)):
			if previous.is_empty():return []
			step.before=previous
		steps.append(step)
		previous=step.get("state",{})
	return steps

static func pack(value: Variant) -> Variant:
	if value is CardDefinitionV2:return {"$card":str(value.id)}
	if value is CardInstanceV2:
		return {"$type":"CardInstanceV2","fields":{
			"instance_id":value.instance_id,"definition":pack(value.definition),
			"treasure_locked":value.treasure_locked,"temporary":value.temporary,
			"inventory_token":value.inventory_token,"equipment":value.equipment}}
	# Deck subclasses may hold local runtime references. Only transmit base data.
	if value is DeckStateV2:
		var fields: Dictionary={}
		for name in ["draw_pile","hand","discard_pile","treasure_pile","removed_cards","discard_count_this_round","treasure_draw_count_this_round","fusion_draw_credits"]:
			fields[name]=pack(value.get(name))
		return {"$type":"DeckStateV2","fields":fields}
	if value is RefCounted:
		for type in TYPES:
			if not is_instance_of(value,TYPES[type]):continue
			var fields: Dictionary={}
			for field in FIELDS[type]:fields[field]=pack(value.get(field))
			return {"$type":type,"fields":fields}
		push_error("BattleWire rejected unregistered object")
		return null
	if value is Array:
		var result: Array=[]
		for item in value:result.append(pack(item))
		return result
	if value is Dictionary:
		var result: Dictionary={}
		for key in value:result[key]=pack(value[key])
		return result
	return value
static func unpack(value: Variant,content: ContentRegistryV2) -> Variant:
	if value is Array:
		var result: Array=[]
		for item in value:result.append(unpack(item,content))
		return result
	if value is Dictionary:
		if value.has("$card"):return content.card(StringName(value["$card"]))
		if value.has("$type"):
			if not TYPES.has(value["$type"]):return null
			var object: RefCounted=TYPES[value["$type"]].new()
			for field in FIELDS[value["$type"]]:
				if value.fields.has(field):assign(object,StringName(field),unpack(value.fields[field],content))
			return object
		var result: Dictionary={}
		for key in value:result[key]=unpack(value[key],content)
		return result
	return value
static func assign(object: Object,key: StringName,value: Variant) -> void:
	var existing: Variant=object.get(key)
	if existing is Array and value is Array:
		existing.assign(value)
	else:object.set(key,value)
static func apply(engine: BattleEngineV2,data: Dictionary) -> void:
	var next: BattleStateV2=unpack(data,engine.content)
	# Preserve units referenced by HUD and ongoing animation.
	for unit in next.units:
		var live:=engine.state.unit_by_id(unit.id)
		if live==null:
			engine.state.units.append(unit)
			continue
		for field in FIELDS.BattleUnitStateV2:assign(live,StringName(field),unit.get(field))
	var retained_ids: Array=next.units.map(func(unit):return unit.id)
	engine.state.units.assign(engine.state.units.filter(func(unit):return retained_ids.has(unit.id)))
	engine.state.pvp=next.pvp
	engine.state.first_team=next.first_team
	engine.state.active_team=next.active_team
	engine.state.phase=next.phase
	engine.state.round_index=next.round_index
	engine.state.winner_team=next.winner_team
	engine.state.actions=next.actions
	engine.state.global_statuses.assign(next.global_statuses)

	if engine.has_method("restore_trial_definitions"):engine.restore_trial_definitions()

static func pack_planning_delta(state: BattleStateV2,owners: Dictionary,peer: int,include_deck: bool) -> Dictionary:
	var units: Dictionary={}
	for unit: BattleUnitStateV2 in state.units:
		if int(owners.get(str(unit.id),0))!=peer:continue
		var changed: Dictionary={"resources":pack(unit.resources),"planned_action":pack(unit.planned_action)}
		if include_deck:changed.deck=pack(unit.deck)
		units[str(unit.id)]=changed
	return {"round_index":state.round_index,"actions":pack(state.actions),"units":units}

static func apply_planning_delta(engine: BattleEngineV2,data: Dictionary) -> bool:
	# Reliable battle ordering supplies a full baseline at entry and each new round.
	if int(data.get("round_index",-1))!=engine.state.round_index or engine.state.phase!=BattleStateV2.Phase.PLANNING:return false
	var units: Dictionary=data.get("units",{})
	for id in units:
		if engine.state.unit_by_id(StringName(str(id)))==null:return false
	engine.state.actions=unpack(data.get("actions",{}),engine.content)
	for id in units:
		var unit:=engine.state.unit_by_id(StringName(str(id)))
		var changed: Dictionary=units[id]
		for field in ["resources","planned_action","deck"]:
			if changed.has(field):assign(unit,StringName(field),unpack(changed[field],engine.content))
	return true

static func pack_view(state: BattleStateV2) -> Dictionary:
	var units: Dictionary={}
	for unit: BattleUnitStateV2 in state.units:
		units[str(unit.id)]={
			"hp":unit.hp,"alive":unit.alive,
			"resources":pack(unit.resources),"statuses":pack(unit.statuses),
			"action_slot_passed":unit.action_slot_passed}
	return {
		"phase":state.phase,"winner_team":state.winner_team,
		"round_index":state.round_index,"active_team":state.active_team,
		"global_statuses":pack(state.global_statuses),"units":units}

static func apply_view(engine: BattleEngineV2,data: Dictionary) -> void:
	engine.state.phase=int(data.get("phase",engine.state.phase))
	engine.state.winner_team=int(data.get("winner_team",engine.state.winner_team))
	engine.state.round_index=int(data.get("round_index",engine.state.round_index))
	engine.state.active_team=int(data.get("active_team",engine.state.active_team))
	var packed_units: Dictionary=data.get("units",{})
	for id in packed_units:
		var unit:=engine.state.unit_by_id(StringName(str(id)))
		if unit==null:continue
		var packed: Dictionary=packed_units[id]
		unit.hp=int(packed.get("hp",unit.hp));unit.alive=bool(packed.get("alive",unit.alive))
		unit.action_slot_passed=bool(packed.get("action_slot_passed",unit.action_slot_passed))
		var resources: Variant=unpack(packed.get("resources",{}),engine.content)
		if resources is ResourceStateV2:
			for field in FIELDS.ResourceStateV2:assign(unit.resources,StringName(field),resources.get(field))
		var statuses: Variant=unpack(packed.get("statuses",[]),engine.content)
		if statuses is Array:unit.statuses.assign(statuses)
	var globals: Variant=unpack(data.get("global_statuses",[]),engine.content)
	if globals is Array:engine.state.global_statuses.assign(globals)

static func peer_team(state: BattleStateV2, owners: Dictionary, peer: int) -> int:
	if peer <= 0:return -1
	for unit in state.units:
		if int(owners.get(str(unit.id),0)) == peer:return unit.team
	return -1

static func private_deck(deck: Dictionary) -> Dictionary:
	var result: Dictionary=deck.duplicate(true)
	var fields: Dictionary=result.get("fields",{})
	for pile in ["hand","draw_pile","treasure_pile","discard_pile","removed_cards"]:
		for card in fields.get(pile,[]):
			card.fields.erase("inventory_token")
			if pile != "hand":card.fields.instance_id=-1
		# Keep the existing composition viewer, never reveal the shuffle order.
		if pile != "hand":fields.get(pile,[]).sort_custom(func(a,b):return str(a.fields.definition.get("$card","")) < str(b.fields.definition.get("$card","")))
	return result

static func visible_actions(actions: Dictionary, state: BattleStateV2, owners: Dictionary, peer: int) -> Dictionary:
	var result: Dictionary={}
	var team:=peer_team(state,owners,peer)
	for id in actions:
		var unit:=state.unit_by_id(StringName(str(id)))
		if unit==null or team<0 or unit.team!=team:continue
		var action: Dictionary=actions[id].duplicate(true)
		if int(owners.get(str(id),0))!=peer:action.fields.card_instance_id=-1
		result[id]=action
	return result

static func project_state(packed: Dictionary,state: BattleStateV2,owners: Dictionary,peer: int) -> Dictionary:
	var result: Dictionary=packed.duplicate(true)
	if not result.has("fields"):return result # Public compact view.
	var fields: Dictionary=result.fields
	fields.actions=visible_actions(fields.get("actions",{}),state,owners,peer)
	for unit in fields.get("units",[]):
		var body: Dictionary=unit.fields
		var mine:=peer>0 and int(owners.get(str(body.id),0))==peer
		body.deck=private_deck(body.deck) if mine else {"$type":"DeckStateV2","fields":{}}
		body.planned_action=fields.actions.get(body.id)
	return result

static func project_packet(data: Dictionary,state: BattleStateV2,owners: Dictionary,peer: int) -> Dictionary:
	var result: Dictionary=data.duplicate(true)
	result.wire_version=3
	if peer<=0:result.observer_only=true
	if result.has("steps"):
		for index in result.steps.size():result.steps[index]=project_packet(result.steps[index],state,owners,peer)
	if result.has("descriptor"):
		var descriptor: Dictionary={"wire_version":3,"loadouts":[]}
		for field in ["id","battle_id","site","party","origins","pvp","first_team","campaign_id","encounter_id","tutorial"]:
			if result.descriptor.has(field):descriptor[field]=result.descriptor[field]
		descriptor.appearances={}
		for owner in owners.values():
			if result.descriptor.get("appearances",{}).has(owner):descriptor.appearances[owner]=result.descriptor.appearances[owner]
		descriptor.observer_only=peer<=0
		result.descriptor=descriptor
	if result.has("pending"):
		var pending: Dictionary={}
		for field in ["team","peer","slot","appearance","origin","round","deadline"]:
			if result.pending.has(field):pending[field]=result.pending[field]
		pending.profile={"school":result.pending.get("profile",{}).get("school","fire")}
		result.pending=pending
	if bool(result.get("planning_delta",false)):
		result.state.actions=visible_actions(result.state.get("actions",{}),state,owners,peer)
		for id in result.state.get("units",{}):
			var changed: Dictionary=result.state.units[id]
			changed.planned_action=result.state.actions.get(id)
			if changed.has("deck"):
				if peer>0 and int(owners.get(str(id),0))==peer:changed.deck=private_deck(changed.deck)
				else:changed.erase("deck")
	else:
		for key in ["state","before"]:
			if result.has(key):result[key]=project_state(result[key],state,owners,peer)
	if result.has("events"):
		result.events=result.events.filter(func(event):return str(event.get("fields",{}).get("type","")) not in PRIVATE_EVENTS)
	return result
