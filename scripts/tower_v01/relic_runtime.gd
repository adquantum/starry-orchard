extends RefCounted
## All triggers belong to one battle; secondary damage cannot trigger relic chains.
var engine_ref: WeakRef
var members: Dictionary={}
var counters: Dictionary={}
var cast: Dictionary={}
var serial:=0
var effect_index:=-1
var pending_counters: Array=[]
var active:=false

func configure(engine,contexts: Array) -> void:
	engine_ref=weakref(engine)
	for index in contexts.size():
		var id:="P%d" % index
		members[id]=contexts[index]
		counters[id]={"swift_round":-1,"core_used":false,"detonations":0,"thorn_round":-1,"thorns":0,"pods":0,"ledger_charges":0,"ledger_ready":false,"shard_charges":0,"shard_ready":false,"last_school":"","scales_ready":false}
	engine.event_stream.subscribe(on_event)

func has_relic(actor: String,id: String) -> bool:
	return members.has(actor) and id in members[actor].relics

func begin(actor: BattleUnitStateV2,card: CardInstanceV2) -> void:
	serial+=1;effect_index=-1;active=true
	cast={"actor":str(actor.id),"card":card,"paid":0,"bonus":0.0,"ledger_bonus":false,"shard_bonus":false,"scales_bonus":false,"swift":false,"core":false,"damage_used":false,"heal_used":false,"drain_used":false,"self_loss":0,"removed":[],"detonated":0,"overheals":[]}

func contract(target: String="",origin: String="spell") -> Dictionary:
	var engine=engine_ref.get_ref()
	var card: CardInstanceV2=cast.get("card")
	return {"run_id":engine.trial.run_id,"battle_id":"%s:%d" % [engine.trial.run_id,engine.trial.node_index],"round_id":engine.state.round_index,"action_id":serial,"cast_id":serial,"actor_id":cast.get("actor",""),"target_id":target,"base_spell_id":str(card.card_id()) if card!=null else "","card_instance_id":card.instance_id if card!=null else -1,"origin":origin,"actual_paid_pip_value":cast.get("paid",0),"resolved_hp_loss":0,"removed_status_ids":[],"effect_index":effect_index}

func trigger(actor: String,id: String,target: String="",extra: Dictionary={}) -> void:
	var engine=engine_ref.get_ref()
	var data:=contract(target,"relic_secondary")
	data.merge({"relic":id,"owner_id":actor});data.merge(extra,true)
	engine.event_stream.publish(&"RelicTriggered",engine.state.round_index,data)

func on_event(event: BattleEventV2) -> void:
	if not active:return
	var actor:=str(cast.get("actor",""))
	match event.type:
		&"ResourceSpent":
			if str(event.payload.get("unit_id",""))!=actor:return
			cast.paid=int(event.payload.get("provided_value",0))
			if not members.has(actor):return
			var engine=engine_ref.get_ref()
			var card: CardDefinitionV2=cast.card.definition
			var state: Dictionary=counters[actor]
			var direct:=card.effects.any(func(e):return str(e.type) in ["damage","drain"])
			var heal:=card.effects.any(func(e):return str(e.type)=="heal")
			cast.swift=has_relic(actor,"swift_flask") and direct and card.target_type==&"enemy" and int(cast.paid) in [1,2] and int(state.swift_round)!=engine.state.round_index
			cast.core=has_relic(actor,"charged_core") and direct and int(cast.paid)>=4 and not state.core_used
			cast.ledger_bonus=has_relic(actor,"shadow_ledger") and state.ledger_ready
			cast.shard_bonus=has_relic(actor,"seal_shard") and state.shard_ready and direct
			cast.scales_bonus=has_relic(actor,"twin_scales") and state.scales_ready and (direct or heal)
		&"HealthSpent":
			if str(event.payload.get("unit_id",""))==actor:cast.self_loss+=int(event.payload.get("amount",0))
		&"DotDetonated":cast.detonated+=1
		&"SpellResolved":
			if str(event.payload.get("caster_id",""))!=actor:return
			if bool(event.payload.get("success",false)):complete()
			active=false;flush_counters()

func damage_bonus(source: String,origin: String) -> float:
	if not active or source!=cast.actor or not members.has(source) or origin not in ["spell","drain"]:return 0.0
	cast.damage_used=true
	if origin=="drain":cast.drain_used=true
	return minf(0.6,(0.25 if cast.swift else 0.0)+(0.2 if cast.core else 0.0)+(0.2 if cast.shard_bonus else 0.0)+(0.15 if cast.scales_bonus else 0.0)+(0.2 if origin=="drain" and cast.ledger_bonus else 0.0))

func healing_bonus(source: String,origin: String) -> float:
	if not active or source!=cast.actor or not members.has(source) or origin!="spell":return 0.0
	cast.heal_used=true
	return 0.15 if cast.scales_bonus else 0.0

func overhealed(source: String,target: String,overflow: int,origin: String) -> void:
	if active and source==cast.actor and origin=="spell" and overflow>0 and int(cast.paid)>0:
		cast.overheals.append({"target":target,"amount":overflow})

func removed(target: BattleUnitStateV2,statuses: Array) -> void:
	if not active or not members.has(str(cast.actor)):return
	var engine=engine_ref.get_ref()
	var actor: BattleUnitStateV2=engine.state.unit_by_id(StringName(cast.actor))
	if target==null or actor==null or target.team==actor.team:return
	for status in statuses:
		if status.kind in [&"blade",&"shield",&"absorb",&"healing_blade",&"accuracy_blade",&"stun_block"]:cast.removed.append(status.instance_id)

func complete() -> void:
	var actor:=str(cast.actor)
	if not members.has(actor):return
	var engine=engine_ref.get_ref()
	var state: Dictionary=counters[actor]
	if cast.damage_used:
		if cast.swift:state.swift_round=engine.state.round_index;trigger(actor,"swift_flask")
		if cast.core:state.core_used=true;trigger(actor,"charged_core")
		if cast.shard_bonus:state.shard_ready=false;trigger(actor,"seal_shard")
	if cast.drain_used and cast.ledger_bonus:state.ledger_ready=false;trigger(actor,"shadow_ledger")
	if (cast.damage_used or cast.heal_used) and cast.scales_bonus:
		state.scales_ready=false;state.last_school="";trigger(actor,"twin_scales")
	elif has_relic(actor,"twin_scales") and not state.scales_ready:
		var school:=str(cast.card.definition.school_id)
		if int(cast.paid)>0:
			if not str(state.last_school).is_empty() and state.last_school!=school:state.scales_ready=true
			state.last_school=school
		else:state.last_school=""
	if cast.self_loss>0 and has_relic(actor,"shadow_ledger") and not state.ledger_ready and int(state.ledger_charges)<2:
		state.ledger_ready=true;state.ledger_charges+=1;trigger(actor,"shadow_ledger","",{"charged":true,"resolved_hp_loss":cast.self_loss})
	if not cast.removed.is_empty() and has_relic(actor,"seal_shard") and not state.shard_ready and int(state.shard_charges)<2:
		state.shard_ready=true;state.shard_charges+=1;trigger(actor,"seal_shard","",{"charged":true,"removed_status_ids":cast.removed.duplicate()})
	if cast.detonated>0 and has_relic(actor,"detonation_seed") and int(state.detonations)<2:
		var unit: BattleUnitStateV2=engine.state.unit_by_id(StringName(actor))
		if unit.alive and unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL):
			state.detonations+=1;trigger(actor,"detonation_seed")
	if has_relic(actor,"abundance_pod") and int(state.pods)<2 and not cast.overheals.is_empty():
		cast.overheals.sort_custom(func(a,b):return a.amount>b.amount)
		for item in cast.overheals:
			var target: BattleUnitStateV2=engine.state.unit_by_id(StringName(item.target))
			if target==null or not target.alive:continue
			var existing:=0
			for status in target.statuses:
				if str(status.source_id)=="trial:pod:"+actor:existing+=roundi(status.value)
			var amount:=mini(roundi(float(item.amount)*0.4),maxi(0,roundi(target.max_hp*0.1)-existing))
			if amount<=0:continue
			engine.add_status(target.id,&"absorb",StringName("trial:pod:"+actor),StringName(actor),"*",amount,0,{"origin":"relic_secondary"})
			state.pods+=1;trigger(actor,"abundance_pod",str(target.id),{"capacity":amount});break

func shield_hit(owner: String,target: String,blocked: int) -> void:
	if blocked<=0 or not has_relic(owner,"frost_thorn"):return
	var engine=engine_ref.get_ref();var state: Dictionary=counters[owner]
	if int(state.thorn_round)==engine.state.round_index or int(state.thorns)>=3:return
	state.thorn_round=engine.state.round_index;state.thorns+=1
	pending_counters.append({"owner":owner,"target":target,"blocked":blocked})
	if not active:flush_counters()

func flush_counters() -> void:
	var engine=engine_ref.get_ref()
	var pending:=pending_counters.duplicate();pending_counters.clear()
	for item in pending:
		var owner: BattleUnitStateV2=engine.state.unit_by_id(StringName(item.owner))
		var target: BattleUnitStateV2=engine.state.unit_by_id(StringName(item.target))
		if owner==null or target==null or not owner.alive or not target.alive:continue
		engine.resolve_damage(owner.id,target.id,&"ice",35,1.0,&"relic_secondary")
		trigger(str(owner.id),"frost_thorn",str(target.id),{"blocked":item.blocked})

func end() -> void:
	active=false;flush_counters()
