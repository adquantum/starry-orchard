extends BasicAIPolicyV2
func choose_action(engine: BattleEngineV2,unit: BattleUnitStateV2) -> ActionIntentV2:
	if engine.encounter_id!="magister" or unit.id!=&"E0":return super.choose_action(engine,unit)
	var allowed: Array=["fire_serpent","frost_ward","ice_shard"]
	if engine.boss_phase==2:allowed=["time_bomb","labyrinth_echo","ember_trap","storm_lance"]
	elif engine.boss_phase==3:allowed=["life_bloom","soft_weakness","bal_001"]
	var chosen: CardInstanceV2
	var chosen_target: BattleUnitStateV2
	var best:=-INF
	for card in unit.deck.hand:
		if not str(card.card_id()) in allowed:continue
		if engine.boss_healed and str(card.card_id())=="life_bloom":continue
		if not engine.cost_resolver.can_pay(unit,card.definition):continue
		var targets:=engine.target_resolver.valid_targets(engine.state,unit,card.definition)
		if targets.is_empty():continue
		var target:=_choose_target(card.definition,targets)
		var score:=_score(engine,unit,card.definition,target)
		if score>best:best=score;chosen=card;chosen_target=target
	if chosen:return ActionIntentV2.cast(unit.id,chosen.instance_id,[chosen_target.id])
	# Discard an unusable phase card through the normal engine rule; no free cards or resources.
	for card in unit.deck.hand:
		if not str(card.card_id()) in allowed:
			engine.discard_for_treasure(unit.id,card.instance_id)
			break
	return ActionIntentV2.pass_turn(unit.id)
