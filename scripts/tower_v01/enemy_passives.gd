extends RefCounted
## Explicit trial mechanics, separate from the unchanged source spells.
var engine_ref: WeakRef
var frost_armor:=false
var storm_charge:=false
var resonance:=false
var boss:=false
var fractured_round:=-1
var fracture_until:=-1
var fracture_remaining:=0
var fracture_casts: Dictionary={}
var charges:=0
var attack_had_charge:=false
var rage_round:=-1
var pulse_round:=-1

func configure(engine) -> void:
	engine_ref=weakref(engine)
	var elite: bool=engine.encounter.risk=="精英"
	frost_armor=(engine.trial.node_index==1 and elite) or engine.trial.node_index==6
	storm_charge=engine.trial.node_index==4 and elite
	boss=engine.trial.node_index==8
	resonance=boss or engine.trial.node_index==6
	engine.event_stream.subscribe(on_event)

func emit(name: String,data: Dictionary={}) -> void:
	var engine=engine_ref.get_ref()
	data.merge({"origin":"enemy_passive","passive":name,"run_id":engine.trial.run_id,"battle_id":"%s:%d" % [engine.trial.run_id,engine.trial.node_index],"actor_id":"E0"})
	engine.event_stream.publish(&"TrialPassive",engine.state.round_index,data)

func has_status(source: String) -> bool:
	var unit: BattleUnitStateV2=engine_ref.get_ref().state.unit_by_id(&"E0")
	return unit!=null and unit.statuses.any(func(s):return str(s.source_id)==source)

func round_started() -> void:
	var engine=engine_ref.get_ref();var unit: BattleUnitStateV2=engine.state.unit_by_id(&"E0")
	if unit==null or not unit.alive:return
	if frost_armor and engine.state.round_index%3==1 and not has_status("trial:frost_armor"):
		var amount:=120 if engine.trial.party_size==1 else 180
		engine.add_status(unit.id,&"absorb",&"trial:frost_armor",unit.id,"*",amount,0,{"origin":"enemy_passive"})
		emit("霜壳再凝",{"capacity":amount})
	if boss and rage_round==engine.state.round_index:
		engine.add_status(unit.id,&"absorb",&"trial:rage_armor",unit.id,"*",120 if engine.trial.party_size==1 else 180,0,{"origin":"enemy_passive"})
		emit("碎核狂怒",{"damage_bonus":20})

func modify_damage(source: StringName,target: StringName,amount: int,origin: StringName) -> int:
	var engine=engine_ref.get_ref()
	var result:=float(amount)
	if target==&"E0":
		var support: BattleUnitStateV2=engine.state.unit_by_id(&"E1")
		if resonance and support!=null and support.alive:result*=0.85
		if engine.state.round_index<=fracture_until and origin in [&"spell",&"drain"] and engine.relic_runtime.active:
			var caster: BattleUnitStateV2=engine.state.unit_by_id(source)
			var serial: int=engine.relic_runtime.serial
			if caster!=null and caster.team==0 and (fracture_casts.has(serial) or fracture_remaining>0):
				if not fracture_casts.has(serial):
					fracture_casts[serial]=true;fracture_remaining-=1
					engine.telegraph_text=warning(engine.telegraph_text)
				result*=1.2
	if source==&"E0" and boss and rage_round>=0 and engine.state.round_index>=rage_round:result*=1.2
	return roundi(result)

func damage_resolved(target_id: StringName,before: Array) -> void:
	if target_id!=&"E0":return
	var engine=engine_ref.get_ref();var unit: BattleUnitStateV2=engine.state.unit_by_id(&"E0")
	for status in before:
		if str(status.source_id) in ["trial:frost_armor","trial:rage_armor"] and status not in unit.statuses:
			open_fracture()
	if boss and unit.alive and unit.hp<=unit.max_hp/2 and rage_round<0:
		rage_round=engine.state.round_index+1
		emit("碎核狂怒预告",{"activates_round":rage_round})
		engine.telegraph_text=warning(engine.telegraph_text)

func statuses_removed(target_id: StringName, removed: Array) -> void:
	if target_id!=&"E0":return
	for status in removed:
		if str(status.source_id) in ["trial:frost_armor","trial:rage_armor"]:open_fracture();return

func open_fracture() -> void:
	var engine=engine_ref.get_ref()
	fractured_round=engine.state.round_index;fracture_until=engine.state.round_index+1;fracture_remaining=2;fracture_casts.clear()
	emit("霜壳击破",{"incoming_direct_bonus":20,"casts":2,"expires_after_round":fracture_until})
	engine.telegraph_text=warning(engine.telegraph_text)

func actor_turn(actor: BattleUnitStateV2) -> void:
	var engine=engine_ref.get_ref()
	if not boss or actor.id!=&"E0" or engine.state.round_index%3!=0 or pulse_round==engine.state.round_index:return
	pulse_round=engine.state.round_index
	emit("寒潮脉冲",{"base_damage":85 if engine.trial.party_size==1 else 110})
	for target in engine.state.living_units(0):
		engine.resolve_damage(actor.id,target.id,&"ice",85 if engine.trial.party_size==1 else 110,1.0,&"enemy_passive")

func on_event(event: BattleEventV2) -> void:
	if not storm_charge:return
	var engine=engine_ref.get_ref()
	if event.type==&"SpellCastStarted" and event.payload.get("caster_id")=="E0":attack_had_charge=has_status("trial:storm_charge")
	if event.type!=&"SpellResolved" or event.payload.get("caster_id")!="E0" or not bool(event.payload.get("success",false)):return
	var card: Dictionary=engine.trial.sources.get(str(event.payload.card_id),{})
	if not card.get("effects",[]).any(func(e):return str(e.type) in ["damage","drain"]):return
	if attack_had_charge:charges=0;return
	charges+=1
	if charges>=2:
		charges=0
		engine.add_status(&"E0",&"blade",&"trial:storm_charge",&"E0","*",25,0,{"origin":"enemy_passive"})
		emit("蓄雷就绪",{"outgoing_bonus":25})

func description() -> String:
	var text:="敌人机制"
	if frost_armor:text+="\n霜壳再凝：第 1/4/7…回合获得吸收盾。击破/拆除/偷取后，两次主动直伤施法 +20%，最迟下一回合结束失效。多段共享一次，多跳与反击不消费窗口。"
	if storm_charge:text+="\n蓄雷：每两次成功攻击获得可拆除的 +25% 刃，强化下一次攻击。"
	if resonance:text+="\n寒核共鸣：祭司活着时，主怪受到伤害降低 15%。击杀祭司立即解除。"
	if boss:text+="\n寒潮脉冲：第 3/6/9…回合首领行动开始时，对全队造成基础寒冰伤害（单人85 / 双人110）；上一回合预告，可用盾和吸收抵挡。击杀首领可取消。\n碎核狂怒：HP 首次低于 50%，下一回合起伤害 +20%，获得一次吸收盾；击破/拆除/偷取盾后两次直伤施法 +20%，最迟下一回合结束失效。\n寒冰重击：至少提前一个选牌阶段预告，实际支付足够才施放。"
	if not (frost_armor or storm_charge or resonance or boss):text+="\n普通守卫没有额外被动。留意治疗支援、刃和盾；敌人的法术同样需要实际支付。"
	return text

func warning(attack_warning: String) -> String:
	var engine=engine_ref.get_ref()
	var lines: Array[String]=[]
	if boss:
		var next: int=engine.state.round_index+(3-engine.state.round_index%3)%3
		lines.append("寒潮：第 %d 回合首领行动时 · 护盾可挡" % next)
		if rage_round>=0:lines.append("狂怒：第 %d 回合起伤害 +20%%" % rage_round)
	elif frost_armor:lines.append("霜壳：击破或拆除后，两次直伤施法 +20%")
	elif storm_charge:lines.append("蓄雷：两次攻击后获得 +25% 刃，可拆除")
	if fracture_remaining>0 and engine.state.round_index<=fracture_until:lines.append("碎壳：直伤 +20%% · 剩余%d次 · 第%d回合结束失效" % [fracture_remaining,fracture_until])
	for line in attack_warning.split("\n"):
		if line.is_empty() or line.begins_with("寒潮：") or line.begins_with("狂怒：") or line.begins_with("霜壳：") or line.begins_with("蓄雷：") or line.begins_with("碎壳："):continue
		lines.append(line)
	return "\n".join(lines)
