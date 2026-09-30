extends RefCounted
## Support considers every legal target and never spends a turn on empty healing/cleansing.
static func choose(policy, engine: BattleEngineV2, unit: BattleUnitStateV2) -> ActionIntentV2:
	var best := 0.0
	var chosen: CardInstanceV2
	var chosen_target: BattleUnitStateV2
	var useless: Array[int] = []
	for card in unit.deck.hand:
		if not engine.cost_resolver.can_pay(unit,card.definition):continue
		var useful := false
		for target in engine.target_resolver.valid_targets(engine.state,unit,card.definition):
			var score := _score(policy,engine,unit,card.definition,target)
			if score <= 0.0:continue
			useful = true
			if score > best:best=score;chosen=card;chosen_target=target
		if not useful:useless.append(card.instance_id)
	if chosen != null:return ActionIntentV2.cast(unit.id,chosen.instance_id,[chosen_target.id])
	if not useless.is_empty() and not unit.deck.draw_pile.is_empty():engine.discard_for_treasure(unit.id,useless[0])
	return ActionIntentV2.pass_turn(unit.id)

static func _score(policy, engine: BattleEngineV2, unit: BattleUnitStateV2, card: CardDefinitionV2, target: BattleUnitStateV2) -> float:
	var score: float = policy._score(engine,unit,card,target,{"heal_threshold":0.55})
	for effect: Dictionary in card.effects:
		var kind := str(effect.get("type",""))
		if kind == "cleanse":
			var found := false
			for status in target.statuses:
				if str(status.kind) in effect.get("kinds",[]):found=true;break
			if not found:return -1.0
		if kind == "heal" and target.hp >= target.max_hp:return -1.0
		if kind == "apply_status" and str(effect.get("status","")) == "blade":
			var filter := str(effect.get("school_filters","*"))
			if filter != "*" and filter != str(target.school_id):return -1.0
		if kind == "apply_status" and str(effect.get("status","")) == "shield":
			# Prefer protecting the wounded; existing identical shields are already penalized.
			score += (1.0-float(target.hp)/maxi(1,target.max_hp))*220.0
	return score
