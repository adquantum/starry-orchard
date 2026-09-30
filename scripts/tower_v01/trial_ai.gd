extends BasicAIPolicyV2
## Uses ordinary visible-state scoring, legal targets and the unchanged cost resolver.
func choose_action(engine: BattleEngineV2, unit: BattleUnitStateV2) -> ActionIntentV2:
	if unit.team==0:return super.choose_action(engine,unit)
	var best: CardInstanceV2
	var best_target: BattleUnitStateV2
	var best_score := -INF
	var profile := _active_profile(unit)
	for card in unit.deck.hand:
		if not engine.enemy_card_allowed(unit,card.definition):continue
		if not engine.cost_resolver.can_pay(unit,card.definition):continue
		var targets := engine.target_resolver.valid_targets(engine.state,unit,card.definition)
		# Enemy healing is finite and never revives a defeated support.
		if _is_healing(card.definition) and not card.definition.effects.any(func(e):return str(e.type) in ["damage","drain"]):targets=targets.filter(func(t):return t.alive and float(t.hp)/t.max_hp<0.65)
		if targets.is_empty():continue
		var target := _choose_target(card.definition,targets,profile)
		var score := _score(engine,unit,card.definition,target,profile)
		if engine.boss_cast_ready(unit,card.definition):score+=1000
		if score>best_score:best_score=score;best=card;best_target=target
	if best==null:return ActionIntentV2.pass_turn(unit.id)
	return ActionIntentV2.cast(unit.id,best.instance_id,[best_target.id])
