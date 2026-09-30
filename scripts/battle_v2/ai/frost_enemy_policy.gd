extends RefCounted
## Opt-in policy for authored Frost PvE enemies only. Never reads player hands.
const Query = preload("res://scripts/battle_v2/core/status_query_v2.gd")

static func choose(policy, engine: BattleEngineV2, unit: BattleUnitStateV2) -> ActionIntentV2:
	var profile: Dictionary = policy._active_profile(unit)
	profile["utility_streak"] = _utility_streak(engine, unit)
	profile["charging_attack"] = _has_unaffordable_attack(engine, unit, profile)
	var candidates: Array[Dictionary] = []
	var useless: Array[int] = []
	var charging := false
	var signature_ready := false
	for instance: CardInstanceV2 in unit.deck.hand:
		var card: CardDefinitionV2 = instance.definition
		if card == null or not _phase_allows(engine, unit, card, profile):continue
		var can_pay := engine.cost_resolver.can_pay(unit, card)
		if profile.has("reserve_hp_ratio") and float(unit.hp)/unit.max_hp <= float(profile.reserve_hp_ratio) and card.pip_cost >= int(profile.get("reserve_cost_min", 5)):
			if can_pay:signature_ready = true
			else:charging = true
		if not can_pay:continue
		var useful := false
		for target: BattleUnitStateV2 in engine.target_resolver.valid_targets(engine.state, unit, card):
			var score := _score(policy, engine, unit, card, target, profile)
			if score <= -90000.0:continue
			useful = true
			candidates.append({"instance":instance.instance_id, "target":target.id, "score":score})
		if not useful:useless.append(instance.instance_id)
	# Boss charge windows use normal turns/pips: no free casts, cards or resources.
	if charging and not signature_ready:
		var preparation: Array[Dictionary] = []
		for candidate: Dictionary in candidates:
			if engine.card_in_hand(unit, int(candidate.instance)).definition.pip_cost == 0:preparation.append(candidate)
		if preparation.is_empty():return ActionIntentV2.pass_turn(unit.id)
		candidates = preparation
	if candidates.is_empty():
		# Discard via the existing legal API, not a free extra draw or a deck refill.
		# Remaining cards are drawn by the normal next-round hand refill.
		if not unit.deck.draw_pile.is_empty() and not useless.is_empty():
			engine.discard_for_treasure(unit.id, useless[0])
		return ActionIntentV2.pass_turn(unit.id)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.score), float(b.score)):return float(a.score) > float(b.score)
		if int(a.instance) != int(b.instance):return int(a.instance) < int(b.instance)
		return str(a.target) < str(b.target))
	var best: Dictionary = candidates[0]
	return ActionIntentV2.cast(unit.id, int(best.instance), [StringName(str(best.target))])

static func _phase_allows(engine: BattleEngineV2, unit: BattleUnitStateV2, card: CardDefinitionV2, profile: Dictionary) -> bool:
	var family := _group_disruption(card)
	var interval := int(profile.get("disruptive_group_interval", 0))
	if not family.is_empty() and interval > 0:
		for index in range(engine.event_stream.events.size()-1, -1, -1):
			var event: BattleEventV2 = engine.event_stream.events[index]
			if engine.state.round_index-event.round_index >= interval:break
			if event.type != &"SpellResolved":continue
			var actor := engine.state.unit_by_id(StringName(str(event.payload.get("caster_id", ""))))
			if actor == null or actor.team != unit.team:continue
			var recent := engine.content.card(StringName(str(event.payload.get("card_id", ""))))
			if recent != null and _group_disruption(recent) == family:return false
	var gate: float = float(profile.get("card_hp_gates", {}).get(str(card.id), 1.0))
	var min_round: int = int(profile.get("card_min_round", {}).get(str(card.id), 0))
	return float(unit.hp)/maxf(1.0, unit.max_hp) <= gate and engine.state.round_index >= min_round

static func _group_disruption(card: CardDefinitionV2) -> String:
	if card.target_type != &"all_enemies":return ""
	for effect: Dictionary in card.effects:
		if str(effect.get("status", "")) in ["weakness", "accuracy_weakness"]:return str(effect.status)
	return ""

static func _score(policy, engine: BattleEngineV2, unit: BattleUnitStateV2, card: CardDefinitionV2, target: BattleUnitStateV2, profile: Dictionary) -> float:
	if _offensive(card):
		for effect: Dictionary in card.effects:
			if str(effect.get("type", "")) == "detonate" and policy._status_kind_count(target, &"dot") == 0:return -100000.0
		return policy._score(engine, unit, card, target, profile) + float(profile.get("card_priority", {}).get(str(card.id), 0.0))
	# Resolve every actual recipient. One shielded/full-health ally must not veto
	# an otherwise useful team spell, nor count as another benefiting recipient.
	var primary := engine.target_resolver.resolve_selected(engine.state, unit, card, [target.id])
	var per_recipient: Dictionary = {}
	var emergency := false
	var interference := false
	var drawback := 0.0
	for effect: Dictionary in card.effects:
		if str(effect.get("type", "")) == "health_cost":
			if unit.hp <= maxf(unit.max_hp * 0.25, unit.max_hp * float(effect.get("max_hp_ratio", 0.0))):return -100000.0
			continue
		for affected: BattleUnitStateV2 in engine.target_resolver.resolve_effect_targets(engine.state, unit, effect, primary):
			# Feint's trap on the caster is its price, not a second beneficiary.
			if affected.team == unit.team and str(effect.get("status", "")) == "trap":
				if float(unit.hp)/unit.max_hp < 0.35:return -100000.0
				drawback += absf(float(effect.get("value", 0))) * 1.5
				continue
			var value := _utility_value(engine, unit, card, effect, affected, profile)
			if value <= 0.0:continue
			if affected.team != unit.team:interference = true
			per_recipient[affected.id] = float(per_recipient.get(affected.id, 0.0)) + value
			if str(effect.get("type", "")) in ["heal", "apply_hot"] and float(affected.hp)/maxf(1, affected.max_hp)<0.3:emergency=true
	if per_recipient.is_empty():return -100000.0
	var values: Array = per_recipient.values();values.sort();values.reverse()
	var score := float(values[0])
	for index in range(1, values.size()):score += float(values[index]) * 0.72
	if card.pip_cost == 0:
		score += float(profile.get("zero_pip_priority", 55.0))
		if bool(profile.get("charging_attack", false)):score += float(profile.get("setup_while_charging", 120.0))
	if values.size()>1:score += float(profile.get("group_utility_priority", 35.0))
	if interference:score += float(profile.get("interference_priority", 0.0))
	if str(profile.get("preferred_role", "")) == "support":score += 45.0
	if not emergency:score -= int(profile.get("utility_streak", 0)) * float(profile.get("utility_chain_penalty", 120.0))
	return score - drawback - card.pip_cost * 12.0 + float(profile.get("card_priority", {}).get(str(card.id), 0.0))

static func _offensive(card: CardDefinitionV2) -> bool:
	for effect: Dictionary in card.effects:
		if str(effect.get("type", "")) in ["damage", "drain", "apply_dot", "delay_damage", "detonate"]:return true
	return false

static func _utility_streak(engine: BattleEngineV2, unit: BattleUnitStateV2) -> int:
	var count := 0
	for index in range(engine.event_stream.events.size()-1, -1, -1):
		var event: BattleEventV2 = engine.event_stream.events[index]
		if event.type != &"SpellResolved" or str(event.payload.get("caster_id", "")) != str(unit.id):continue
		var card := engine.content.card(StringName(str(event.payload.get("card_id", ""))))
		if card == null or _offensive(card):break
		count += 1
		if count >= 3:break
	return count

static func _has_unaffordable_attack(engine: BattleEngineV2, unit: BattleUnitStateV2, profile: Dictionary) -> bool:
	for instance: CardInstanceV2 in unit.deck.hand:
		var card := instance.definition
		if _offensive(card) and card.pip_cost >= 3 and _phase_allows(engine, unit, card, profile) and not engine.cost_resolver.can_pay(unit, card):return true
	return false

static func _matches(filters: Variant, school: StringName) -> bool:
	var values: Array = filters if filters is Array else [filters]
	return values.is_empty() or "*" in values or str(school) in values

static func _team_matches(engine: BattleEngineV2, team: int, filters: Variant) -> bool:
	for member: BattleUnitStateV2 in engine.state.living_units(team):
		if _matches(filters, member.school_id):return true
	return false

static func _covered(engine: BattleEngineV2, caster: BattleUnitStateV2, target: BattleUnitStateV2, kind: String, filters: Variant) -> bool:
	if not Query.select(target, {"kinds":[kind], "school_filters":filters}).is_empty():return true
	# Friendly queued actions are available to the team; never inspect enemy hands
	# or their planned actions. Avoid two guards scheduling the same group ward.
	for ally: BattleUnitStateV2 in engine.state.living_units(caster.team):
		if ally == caster:continue
		var action: ActionIntentV2 = engine.state.actions.get(ally.id)
		if action == null or action.pass_action or action.cancelled:continue
		var instance := engine.card_in_hand(ally, action.card_instance_id)
		if instance == null:continue
		var primary := engine.target_resolver.resolve_selected(engine.state, ally, instance.definition, action.target_ids)
		for effect: Dictionary in instance.definition.effects:
			if str(effect.get("type", "")) != "apply_status" or str(effect.get("status", "")) != kind:continue
			var existing: Variant=effect.get("school_filters", "*")
			var values: Array=filters if filters is Array else [filters]
			var overlaps := false
			for school in values:
				if str(school)=="*" or _matches(existing, StringName(str(school))):overlaps=true
			if overlaps and target in engine.target_resolver.resolve_effect_targets(engine.state, ally, effect, primary):return true
	return false

static func _utility_value(engine: BattleEngineV2, caster: BattleUnitStateV2, card: CardDefinitionV2, effect: Dictionary, target: BattleUnitStateV2, profile: Dictionary) -> float:
	var kind := str(effect.get("type", ""))
	var ratio := float(target.hp)/maxf(1, target.max_hp)
	var missing := maxi(0, target.max_hp-target.hp)
	var filters: Variant = effect.get("school_filters", "*")
	if kind in ["heal", "apply_hot"]:
		if kind == "apply_hot":
			if _hot_covered(engine, caster, target):return 0.0
			if bool(profile.get("prepare_hot", false)) and not engine.state.living_units(1-caster.team).is_empty():
				var total := float(effect.get("healing_per_tick", 0))*int(effect.get("ticks", 1))
				return total * 0.65 + minf(missing, total) * 0.35 + float(profile.get("hot_priority", 0.0))
		if ratio > float(profile.get("heal_threshold", 0.5)):return 0.0
		var amount := float(effect.get("power", 0)) if kind == "heal" else float(effect.get("healing_per_tick", 0))*int(effect.get("ticks", 1))*0.65
		return minf(amount, missing) * 1.3 + (90.0 if ratio<0.3 else 0.0)
	if not target.alive:return 0.0
	if kind in ["remove_status", "cleanse", "steal_status"]:
		var matches := Query.select(target, Query.criteria_from(effect))
		var count := mini(matches.size(), maxi(1, int(effect.get("count", 1))))
		var result := count * 145.0
		# Removing a visible damage boost prevents the next amplified hit. The
		# value follows existing public statuses, never the opponent's hand.
		for index in count:
			var entry: StatusInstanceV2 = matches[index]
			if target.team != caster.team and entry.kind == &"blade":
				result += absf(entry.value) * 3.0 + mini(5, target.resources.pips.size()) * 12.0
		return result
	if kind == "modify_dot":
		for status: StatusInstanceV2 in target.statuses:
			if status.kind==&"dot" and status.ticks>0:return 125.0
		return 0.0
	if kind == "resource":
		var count := mini(int(effect.get("count", 1)), ResourceStateV2.MAX_PIPS-target.resources.pips.size())
		if count<=0:return 0.0
		var needed := _has_unaffordable_attack(engine, target, profile)
		if caster.school_id == &"balance":
			for instance: CardInstanceV2 in target.deck.hand:
				if instance.definition.pip_cost >= 3 and not engine.cost_resolver.can_pay(target,instance.definition):needed=true
		if not needed:return 0.0
		return count*55.0 + float(profile.get("resource_priority", 0.0)) + (45.0 if target != caster else 0.0)
	if kind == "apply_aura":
		var polarity := str(effect.get("payload", {}).get("polarity", "helpful"))
		if not Query.select(target,{"kinds":["aura"],"polarity":polarity}).is_empty():return 0.0
		if polarity=="helpful" and not _matches(filters, target.school_id):return 0.0
		return 165.0
	if kind == "apply_status":
		var status_kind := str(effect.get("status", ""))
		if _covered(engine, caster, target, status_kind, filters):return 0.0
		var value := absf(float(effect.get("value", 0)))
		match status_kind:
			"blade":
				if not _matches(filters, target.school_id):return 0.0
				return value*2.6 + (35.0 if str(target.ai_profile_id) in ["frost_burst","frost_boss_storm","frost_boss_death"] else 0.0)
			"shield":
				if not _team_matches(engine, 1-caster.team, filters):return 0.0
				return value*2.0 + (1.0-ratio)*65.0
			"trap":
				if not _team_matches(engine, caster.team, filters):return 0.0
				return value*2.2
			"weakness", "accuracy_weakness":
				if not _matches(filters,target.school_id):return 0.0
				var pressure := mini(5,target.resources.pips.size())*16.0
				for entry: StatusInstanceV2 in Query.select(target,{"kinds":["blade"]}):
					if entry.matches_school(target.school_id):pressure += absf(entry.value)*1.5
				return value*2.8 + pressure
			"infection":
				if ratio>0.75 or not _team_matches(engine,target.team,"life"):return 0.0
				return value*1.6
			"accuracy_blade":
				if not _matches(filters,target.school_id) or target.school_stat(&"accuracy_floor",target.school_id)>=1.0:return 0.0
				return value*2.5
			"healing_blade":
				if target.school_id!=&"life":return 0.0
				for ally: BattleUnitStateV2 in engine.state.living_units(caster.team):
					if float(ally.hp)/ally.max_hp<0.65:return value*2.5
	return 0.0

static func _hot_covered(engine: BattleEngineV2, caster: BattleUnitStateV2, target: BattleUnitStateV2) -> bool:
	if not Query.select(target,{"kinds":["hot"]}).is_empty():return true
	for ally: BattleUnitStateV2 in engine.state.living_units(caster.team):
		if ally == caster:continue
		var action: ActionIntentV2 = engine.state.actions.get(ally.id)
		if action == null or action.pass_action or action.cancelled:continue
		var instance := engine.card_in_hand(ally, action.card_instance_id)
		if instance == null:continue
		var primary := engine.target_resolver.resolve_selected(engine.state, ally, instance.definition, action.target_ids)
		for effect: Dictionary in instance.definition.effects:
			if str(effect.get("type", "")) == "apply_hot" and target in engine.target_resolver.resolve_effect_targets(engine.state, ally, effect, primary):return true
	return false
