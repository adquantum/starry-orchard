extends BattleEngineV2
var trial: RefCounted
var party: Array[StringName] = []
var party_decks: Dictionary = {}
var encounter_id := "garden_familiars"
var campaign_level := 0
var boss_phase := 1
var reorganized: Dictionary = {}
var reorganizing: Dictionary = {}
var encounter: Dictionary = {}
var enemy_cast_counts: Dictionary = {}
var announced_round := -1
var boss_announcements := 0
var telegraph_text := ""
var relic_runtime: RefCounted
var passive_runtime: RefCounted
var network_trial_info:=""
var initial_hp: Dictionary={}
var started_msec:=0

func setup(p_content: ContentRegistryV2, _scenario: Dictionary, _seed: int = 0) -> bool:
	if trial == null:return false
	encounter = trial.encounter()
	enemy_cast_counts.clear();announced_round=-1;boss_announcements=0
	var members: Array = [trial]
	if trial.teammate!=null:members.append(trial.teammate)
	var characters: Array=[]
	cost_resolver = preload("res://scripts/tower_v01/trial_cost.gd").new()
	for index in members.size():
		var main := ""
		for key in p_content.characters:
			if str(p_content.characters[key].school)==members[index].school and str(key) not in ["ember_skeleton","frost_golem","thorn_witch","storm_wraith"]:
				main=str(key);break
		if main.is_empty():return false
		characters.append(main)
		cost_resolver.secondaries["P%d" % index]=members[index].secondary
	resource_resolver = preload("res://scripts/tower_v01/trial_resources.gd").new()
	for index in members.size():resource_resolver.power_rates["P%d" % index]=0.48 if "steady_pips" in members[index].relics else 0.4
	action_resolver=preload("res://scripts/tower_v01/trial_action.gd").new()
	status_resolver=preload("res://scripts/tower_v01/trial_status.gd").new()
	var scenario := {"teams":[characters,["ember_skeleton","frost_golem"]],
		"starting_resources":{"normal":1}, "rules":{"school_pip_enabled":false,"shadow_pip_enabled":false}}
	if not super.setup(p_content,scenario,int(trial.seed_value)+int(trial.node_index)*1009):return false
	relic_runtime=preload("res://scripts/tower_v01/relic_runtime.gd").new()
	relic_runtime.configure(self,members)
	passive_runtime=preload("res://scripts/tower_v01/enemy_passives.gd").new()
	passive_runtime.configure(self)
	_next_card_instance_id = int(trial.next_instance)+100
	for unit in state.units:
		unit.deck = preload("res://scripts/tower_v01/trial_deck.gd").new() if unit.team==0 else DeckStateV2.new()
		if unit.team==0:unit.deck.actor=unit;unit.deck.cost=cost_resolver
		unit.stats = {"damage":30 if unit.team==0 else 0,"resistance":10 if unit.team==0 else 0,"pierce":5 if unit.team==0 else 0}
		if unit.team==0:
			var member: RefCounted=members[unit.slot]
			unit.max_hp=member.main_max_hp()
			unit.hp=int(member.hp[0]) if not member.hp.is_empty() else unit.max_hp
		if unit.team==1:
			var spec: Dictionary=encounter.enemies[unit.slot]
			unit.name_key=StringName(spec.name);unit.school_id=StringName(spec.school)
			unit.resources.charge_school=unit.school_id;unit.resources.next_charge_school=unit.school_id
			unit.max_hp=int(spec.hp);unit.hp=unit.max_hp
			unit.stats={"damage":spec.damage,"resistance":spec.resistance,"pierce":spec.pierce}
		if unit.team==0:
			var member: RefCounted=members[unit.slot]
			for record in member.deck:
				unit.deck.draw_pile.append(CardInstanceV2.new(int(record.instance_id)+unit.slot*10000,member.definition(record)))
		else:
			var counts: Dictionary=encounter.enemies[unit.slot].cards
			for id in counts:
				if not trial.sources.has(id):return false
				for copy in int(counts[id]):unit.deck.draw_pile.append(_new_card(CardDefinitionV2.from_dict(trial.sources[id])))
		_shuffle_cards(unit.deck.draw_pile)
		if unit.team==0 and "ready_seed" in members[unit.slot].relics:unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
		initial_hp[str(unit.id)]=unit.hp
	started_msec=Time.get_ticks_msec()
	return true

func start_next_round() -> bool:
	if state.round_index>=50 and state.phase!=BattleStateV2.Phase.FINISHED:
		state.phase=BattleStateV2.Phase.FINISHED;state.winner_team=1
		event_stream.publish(&"BattleEnded",state.round_index,{"winner_team":1,"reason":"trial_stall"})
		return false
	var result := super.start_next_round()
	telegraph_text=""
	if trial.node_index==8 and result and state.unit_by_id(&"E0").alive:
		if announced_round<0 and state.round_index>=2 and boss_announcements<2:
			announced_round=state.round_index+1;boss_announcements+=1
		while announced_round>=0 and (announced_round%3==0 or announced_round==passive_runtime.rage_round):announced_round+=1
		telegraph_text="守望者预告：第 %d 回合起，支付足够时施放寒冰重击" % announced_round if announced_round>=0 else ""
	if result:
		passive_runtime.round_started()
		telegraph_text=passive_runtime.warning(telegraph_text)
		for unit in state.living_units(0):
			var available: Array=[];available.append_array(unit.deck.hand);available.append_array(unit.deck.draw_pile)
			if not reorganized.has(unit.id):available.append_array(unit.deck.discard_pile.filter(func(card):return &"no_reshuffle" not in card.definition.tags))
			if not available.any(func(card):return card.definition.effects.any(func(effect):return str(effect.type) in ["damage","drain","apply_dot","detonate"])):
				telegraph_text+="\n%s 已无剩余或可回收的攻击牌；可选择放弃本局。" % str(unit.id)
		if state.round_index>=30:telegraph_text+="\n局面僵持：第50回合后未突破将结束本局，可主动放弃。"
		if state.round_index==1:
			for unit in state.team_units(0):
				event_stream.publish(&"TrialOpening",1,{"unit_id":str(unit.id),"adjusted":unit.deck.adjusted,"hand":unit.deck.hand.map(func(card):return card.instance_id)})
	return result

func boss_cast_ready(unit: BattleUnitStateV2, card: CardDefinitionV2) -> bool:
	return trial.node_index==8 and unit.id==&"E0" and card.id==&"ice_017" and announced_round>=0 and state.round_index>=announced_round and state.round_index%3!=0 and state.round_index!=passive_runtime.rage_round

func enemy_card_allowed(unit: BattleUnitStateV2, card: CardDefinitionV2) -> bool:
	if card.target_type==&"all_enemies" and state.round_index<=2:return false
	if trial.node_index==8 and unit.id==&"E0" and card.id==&"ice_017" and not boss_cast_ready(unit,card):return false
	var counts: Dictionary=enemy_cast_counts.get(str(unit.id),{})
	for effect in card.effects:
		if str(effect.type) in ["heal","apply_hot"] and int(counts.get("heal",0))>=2 and not card.effects.any(func(e):return str(e.type) in ["damage","drain"]):return false
		if str(effect.get("status",""))=="shield" and int(counts.get("shield",0))>=2 and not card.effects.any(func(e):return str(e.type) in ["damage","drain"]):return false
	return true

func card_cost_cap() -> int:return 7
func configure_deck(_unit_id: StringName, _counts: Dictionary) -> bool:return false
func fuse_cards(_unit_id: StringName, _first: int, _second: int) -> CardInstanceV2:return null

func request_reorganize(actor: BattleUnitStateV2) -> bool:
	if actor == null or not actor.alive or not actor.deck.draw_pile.is_empty() or not actor.deck.discard_pile.any(func(card):return &"no_reshuffle" not in card.definition.tags) or reorganized.has(actor.id):return false
	if not queue_pass(actor.id):return false
	reorganizing[actor.id] = true
	return true

func resolve_actor_action(actor: BattleUnitStateV2) -> Array[BattleEventV2]:
	if actor != null and actor.alive and reorganizing.has(actor.id) and state.phase == BattleStateV2.Phase.RESOLVING:
		reorganizing.erase(actor.id)
		reorganized[actor.id] = true
		var retained: Array[CardInstanceV2] = []
		for card in actor.deck.discard_pile:
			if &"no_reshuffle" in card.definition.tags:retained.append(card)
			else:actor.deck.draw_pile.append(card)
		actor.deck.discard_pile = retained
		_shuffle_cards(actor.deck.draw_pile)
		actor.action_slot_passed = true
		event_stream.publish(&"ActionPassed",state.round_index,{"unit_id":str(actor.id),"origin":"system_reorganize"})
		return []
	var intent: ActionIntentV2=state.actions.get(actor.id) if actor!=null else null
	var card: CardInstanceV2=card_in_hand(actor,intent.card_instance_id) if intent!=null and not intent.pass_action else null
	if actor!=null:relic_runtime.begin(actor,card)
	var events := super.resolve_actor_action(actor)
	relic_runtime.end()
	if actor!=null and actor.team==1:
		for event in events:
			if event.type==&"SpellResolved" and bool(event.payload.get("success",false)):
				var id:=str(event.payload.card_id)
				var data: Dictionary=trial.sources.get(id,{})
				var counts: Dictionary=enemy_cast_counts.get(str(actor.id),{})
				for kind in ["heal","shield"]:
					if data.get("effects",[]).any(func(e):return str(e.get("type","")) in ["heal","apply_hot"] if kind=="heal" else str(e.get("status",""))=="shield"):
						counts[kind]=int(counts.get(kind,0))+1
				enemy_cast_counts[str(actor.id)]=counts
				if id=="ice_017" and actor.id==&"E0":announced_round=-1
	return events

func restore_trial_definitions() -> void:
	var members: Array=[trial]
	if trial.teammate!=null:members.append(trial.teammate)
	for unit in state.team_units(0):
		if unit.slot>=members.size():continue
		var member: RefCounted=members[unit.slot]
		var definitions: Dictionary={}
		for record in member.deck:definitions[int(record.instance_id)+unit.slot*10000]=member.definition(record)
		for pile in [unit.deck.hand,unit.deck.draw_pile,unit.deck.discard_pile,unit.deck.removed_cards]:
			for card in pile:
				if definitions.has(card.instance_id):card.definition=definitions[card.instance_id]

func modifier_amount(amount: int,bonus: float) -> int:
	if bonus==0 or not relic_runtime.active:return amount
	var record_level:=0.0
	var card: CardInstanceV2=relic_runtime.cast.get("card")
	var owner:=str(relic_runtime.cast.get("actor",""))
	if card!=null and relic_runtime.members.has(owner):
		for record in relic_runtime.members[owner].deck:
			if int(record.instance_id)==card.instance_id%10000:
				record_level=float(record.level)*0.1 if str(record.get("upgrade_path","power")) in ["","power"] else 0.0
				break
	return roundi(float(amount)/(1.0+record_level)*(1.0+minf(0.6,record_level+bonus)))

func resolve_damage(source_id: StringName,target_id: StringName,school_id: StringName,amount: int,outgoing: float=1.0,origin: StringName=&"spell",source_snapshot: Dictionary={}) -> int:
	var target:=state.unit_by_id(target_id)
	if target==null or not target.alive:return 0
	var before_statuses: Array=target.statuses.duplicate()
	var hp_before := target.hp
	var event_start:=event_stream.events.size()
	var bonus: float=relic_runtime.damage_bonus(str(source_id),str(origin))
	amount=modifier_amount(amount,bonus)
	amount=passive_runtime.modify_damage(source_id,target_id,amount,origin)
	var result:=super.resolve_damage(source_id,target_id,school_id,amount,outgoing,origin,source_snapshot)
	var damage: Dictionary={};var consumed: Array=[]
	for index in range(event_start,event_stream.events.size()):
		var event: BattleEventV2=event_stream.events[index]
		if event.type==&"DamageResolved" and str(event.payload.target_id)==str(target_id):damage=event.payload
		if event.type==&"StatusConsumed":consumed.append(int(event.payload.get("status_id",-1)))
	if origin!=&"relic_secondary" and not damage.is_empty():
		for status in before_statuses:
			if status.kind!=&"shield" or status.value>=0 or status.instance_id not in consumed:continue
			var potential: float=(float(damage.base_amount)*float(damage.stat_multiplier)+float(damage.flat_damage))*float(damage.outgoing_multiplier)*float(damage.critical_multiplier)*float(damage.resistance_multiplier)
			var blocked:=roundi(maxf(0,potential*(-status.value/100.0)))
			relic_runtime.shield_hit(str(status.caster_id),str(source_id),blocked)
	passive_runtime.damage_resolved(target_id,before_statuses)
	var hp_loss := maxi(0,hp_before-target.hp)
	if not damage.is_empty():damage["resolved_hp_loss"]=hp_loss;damage["calculated_damage"]=result
	return hp_loss if origin==&"drain" else result

func resolve_healing(source_id: StringName,target_id: StringName,amount: int,outgoing: float=1.0,origin: StringName=&"spell",apply_charms: bool=true) -> int:
	var target:=state.unit_by_id(target_id);var source:=state.unit_by_id(source_id)
	if target==null or source==null:return super.resolve_healing(source_id,target_id,amount,outgoing,origin,apply_charms)
	var alive_before:=target.alive
	amount=modifier_amount(amount,relic_runtime.healing_bonus(str(source_id),str(origin)))
	var source_bonus:=source.school_stat(&"outgoing_heal")+status_resolver.stat_bonus(source,&"outgoing_heal",&"*")
	var target_bonus:=target.school_stat(&"incoming_heal")+status_resolver.stat_bonus(target,&"incoming_heal",&"*")
	var charms: float=float(status_resolver.resolve_multiplier_plan(source,[&"healing_blade",&"infection"],&"*").multiplier) if apply_charms and origin==&"spell" else 1.0
	var requested:=maxi(0,roundi(amount*outgoing*(1+source_bonus/100)*(1+target_bonus/100)*charms*status_resolver.global_multiplier(state,&"outgoing_heal",&"*",source.team)*status_resolver.global_multiplier(state,&"incoming_heal",&"*",target.team)))
	var event_start:=event_stream.events.size()
	var result:=super.resolve_healing(source_id,target_id,amount,outgoing,origin,apply_charms)
	for index in range(event_start,event_stream.events.size()):
		var event: BattleEventV2=event_stream.events[index]
		if event.type==&"HealingResolved" and str(event.payload.target_id)==str(target_id):event.payload["overheal"]=maxi(0,requested-result)
	if alive_before:relic_runtime.overhealed(str(source_id),str(target_id),maxi(0,requested-result),str(origin))
	return result

func remove_statuses(target_id: StringName,criteria: Dictionary,count: int=-1,reason: StringName=&"removed") -> Array[StatusInstanceV2]:
	var removed:=super.remove_statuses(target_id,criteria,count,reason)
	if relic_runtime!=null:relic_runtime.removed(state.unit_by_id(target_id),removed)
	if passive_runtime!=null:passive_runtime.statuses_removed(target_id,removed)
	return removed

func steal_statuses(from_id: StringName,to_id: StringName,criteria: Dictionary,count: int=1) -> int:
	var source:=state.unit_by_id(from_id)
	var before: Array=source.statuses.duplicate() if source!=null else []
	var result:=super.steal_statuses(from_id,to_id,criteria,count)
	var removed: Array=[]
	for status in before:
		if status not in source.statuses:removed.append(status)
	relic_runtime.removed(source,removed)
	if passive_runtime!=null:passive_runtime.statuses_removed(from_id,removed)
	return result

func begin_actor_turn(actor: BattleUnitStateV2) -> Array[BattleEventV2]:
	var event_start:=event_stream.events.size()
	super.begin_actor_turn(actor)
	if actor!=null and actor.alive and state.phase!=BattleStateV2.Phase.FINISHED:passive_runtime.actor_turn(actor)
	check_battle_end()
	var result: Array[BattleEventV2]=[]
	for index in range(event_start,event_stream.events.size()):result.append(event_stream.events[index])
	return result

func trial_info() -> String:
	if not network_trial_info.is_empty():return network_trial_info
	var text: String=passive_runtime.description()+"\n\n局内遗物（增幅加算，上限 60%）"
	for actor in relic_runtime.members:
		text+="\n\n"+actor
		for id in relic_runtime.members[actor].relics:text+="\n"+str(preload("res://scripts/tower_v01/relic_catalog.gd").DATA[id].name)
		var count: Dictionary=relic_runtime.counters[actor]
		text+="\n反击 %d/3 · 溢疗 %d/2 · 引爆返豆 %d/2" % [count.thorns,count.pods,count.detonations]
		text+="\n天秤记录：%s · %s" % [str(count.last_school),"增幅就绪" if count.scales_ready else "尚未就绪"]
		var unit := state.unit_by_id(StringName(actor))
		text+="\n整备剩余 %d 次 · 可回收 %d 张" % [0 if reorganized.has(unit.id) else 1,unit.deck.discard_pile.filter(func(card):return &"no_reshuffle" not in card.definition.tags).size()]
	text+="\n\n弃置普通牌后下回合补抽。抽牌堆为空即可整备，不要求手牌全空；整备占一次行动。\n每回合一次行动，豆可积累。强力豆本系/研习副系按2点支付，其他系按1点。\n遗物的实付豆指支付价值，不是豆槽数；多付部分也计入。\n第30回合提示僵持，第50回合未突破结束本局。"
	return text
