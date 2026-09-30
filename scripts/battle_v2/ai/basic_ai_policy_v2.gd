class_name BasicAIPolicyV2
extends AIPolicyV2

var profiles: Dictionary = {}


func choose_action(engine: BattleEngineV2, unit: BattleUnitStateV2) -> ActionIntentV2:
	if not engine.state.pvp and unit.ai_profile_id==&"island_ally":
		return preload("res://scripts/battle_v2/ai/island_ally_policy.gd").choose(self,engine,unit)
	if not engine.state.pvp and unit.ai_profile_id==&"orchard_finale":
		return preload("res://scripts/server/star_orchard_finale.gd").choose(engine,unit)
	if unit.team == 1 and not engine.state.pvp and str(unit.ai_profile_id).begins_with("orchard_lesson_"):
		return preload("res://scripts/server/star_orchard_fixed_lessons.gd").enemy_action(engine,unit)
	if unit.team == 1 and not engine.state.pvp and str(unit.ai_profile_id).begins_with("frost_"):
		return preload("res://scripts/battle_v2/ai/frost_enemy_policy.gd").choose(self, engine, unit)
	var candidates: Array[Dictionary] = []
	var profile := _active_profile(unit)
	for card in unit.deck.hand:
		if not engine.cost_resolver.can_pay(unit, card.definition):
			continue
		var targets := engine.target_resolver.valid_targets(engine.state, unit, card.definition)
		if targets.is_empty():
			continue
		var target := _choose_target(card.definition, targets, profile)
		candidates.append({"card": card, "target": target, "score": _score(engine, unit, card.definition, target, profile)})
	if candidates.is_empty():
		return ActionIntentV2.pass_turn(unit.id)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.score) > float(b.score))
	var top_count := mini(2, candidates.size())
	var chosen: Dictionary = candidates[engine.rng.randi_range(0, top_count - 1)] if top_count > 1 and engine.rng.randf() < 0.10 else candidates[0]
	var card := chosen.card as CardInstanceV2
	var target := chosen.target as BattleUnitStateV2
	return ActionIntentV2.cast(unit.id, card.instance_id, [target.id])


func _choose_target(card: CardDefinitionV2, targets: Array[BattleUnitStateV2], profile: Dictionary = {}) -> BattleUnitStateV2:
	if card.target_type == &"dead_ally":
		return targets[0]
	if _is_healing(card):
		targets.sort_custom(func(a, b): return float(a.hp) / a.max_hp < float(b.hp) / b.max_hp)
		return targets[0]
	if card.target_type in [&"ally", &"all_allies"]:
		targets.sort_custom(func(a, b): return _duplicate_status_count(card, a) < _duplicate_status_count(card, b))
		return targets[0]
	if _has_status_effect(card):
		targets.sort_custom(func(a, b): return _duplicate_status_count(card, a) < _duplicate_status_count(card, b))
		return targets[0]
	targets.sort_custom(func(a, b): return a.hp < b.hp)
	return targets[0]


func _score(engine: BattleEngineV2, caster: BattleUnitStateV2, card: CardDefinitionV2, target: BattleUnitStateV2, profile: Dictionary = {}) -> float:
	var score := 0.0
	var missing_hp := maxi(0, target.max_hp - target.hp)
	for effect: Dictionary in card.effects:
		match StringName(str(effect.get("type", ""))):
			&"damage":
				var power := _estimated_power(engine, caster, card, effect, target)
				score += power
				if power >= target.hp:
					score += 220.0
			&"drain": score += _estimated_power(engine, caster, card, effect, target) * 1.25
			&"apply_dot": score += (float(effect.get("damage_per_tick", 0)) + float(effect.get("damage_per_pip", 0)) * _payment_value(engine, caster, card)) * float(effect.get("ticks", 1)) * 0.8
			&"delay_damage": score += float(effect.get("power", 0)) * 0.7
			&"heal": score += minf(float(effect.get("power", 0)), missing_hp) * 1.45 if missing_hp > target.max_hp * 0.12 else -500.0
			&"apply_hot": score += float(effect.get("healing_per_tick", 0)) * float(effect.get("ticks", 1)) * (1.15 if missing_hp > target.max_hp * 0.25 else -1.0)
			&"revive": score += 1000.0
			&"apply_status": score += absf(float(effect.get("value", 0))) * 2.0
			&"absorb": score += float(effect.get("value", 0)) * 0.8
			&"stun": score += 180.0
			&"dispel": score += 95.0
			&"prism": score += 70.0
			&"apply_aura", &"apply_global": score += 130.0
			&"remove_status", &"cleanse", &"steal_status": score += 110.0
			&"detonate": score += 150.0 if _status_kind_count(target, &"dot") > 0 else -300.0
			&"resource": score += 75.0
			&"conditional": score += 100.0
	if card.target_type == &"all_enemies":
		score *= maxf(1.0, float(engine.state.living_units(1 - caster.team).size()) * 0.72)
	elif card.target_type == &"all_allies":
		score *= maxf(1.0, float(engine.state.living_units(caster.team).size()) * 0.58)
	if _duplicate_status_count(card, target) > 0:
		score -= 600.0
	if card.school_id == caster.school_id:
		score += 24.0
	score += _profile_bonus(card, target, profile)
	var cost_weight := float(profile.get("high_cost_preference", 0.0))
	var shadow_weight := float(profile.get("shadow_preference", 0.0))
	score += float(card.pip_cost) * cost_weight * 18.0
	score += float(card.shadow_cost) * shadow_weight * 120.0
	return score - float(_payment_value(engine, caster, card) if card.x_pip else card.pip_cost) * 5.0


func _active_profile(unit: BattleUnitStateV2) -> Dictionary:
	var profile := (profiles.get(str(unit.ai_profile_id), profiles.get("default", {})) as Dictionary).duplicate(true)
	for phase_value in profile.get("phases", []):
		var phase := phase_value as Dictionary
		var hp_ratio := float(unit.hp) / maxf(float(unit.max_hp), 1.0)
		if hp_ratio <= float(phase.get("max_hp_ratio", 1.0)) and hp_ratio > float(phase.get("min_hp_ratio", -0.01)):
			profile.merge(phase, true)
			break
	return profile


func _profile_bonus(card: CardDefinitionV2, target: BattleUnitStateV2, profile: Dictionary) -> float:
	var bonus := 0.0
	var heal_threshold := float(profile.get("heal_threshold", 0.5))
	var hp_ratio := float(target.hp) / maxf(float(target.max_hp), 1.0)
	for effect: Dictionary in card.effects:
		var type := StringName(str(effect.get("type", "")))
		var status := StringName(str(effect.get("status", "")))
		if type in [&"heal", &"apply_hot"] and hp_ratio <= heal_threshold:
			bonus += 260.0
		if type == &"apply_dot" and _status_kind_count(target, &"dot") == 0:
			bonus += float(profile.get("dot_priority", 0.0)) * 180.0
		if type == &"apply_status" and status == &"shield" and _status_kind_count(target, &"shield") == 0:
			bonus += float(profile.get("shield_priority", 0.0)) * 160.0
		if type == &"apply_status" and status == &"weakness":
			bonus += float(profile.get("weakness_priority", 0.0)) * 130.0
		if type == &"remove_status":
			bonus += float(profile.get("remove_priority", 0.0)) * 150.0
	var role := str(profile.get("preferred_role", ""))
	if role == "damage" and card.target_type in [&"enemy", &"all_enemies"]:
		bonus += 45.0
	elif role == "support" and card.target_type in [&"ally", &"all_allies", &"self"]:
		bonus += 55.0
	return bonus


func _estimated_power(engine: BattleEngineV2, caster: BattleUnitStateV2, card: CardDefinitionV2, effect: Dictionary, target: BattleUnitStateV2) -> float:
	var school := StringName(str(effect.get("school", card.school_id)))
	var power := float(effect.get("power", 0)) + float(effect.get("power_per_pip", 0)) * _payment_value(engine, caster, card)
	var damage := caster.school_stat(&"damage", school)
	var pierce := caster.school_stat(&"pierce", school)
	var resistance := target.school_stat(&"resistance", school)
	return power * maxf(0.0, 1.0 + damage / 100.0) * maxf(0.0, 1.0 - clampf(resistance - pierce, -100.0, 100.0) / 100.0)


func _payment_value(engine: BattleEngineV2, caster: BattleUnitStateV2, card: CardDefinitionV2) -> int:
	return int(engine.cost_resolver.payment_plan(caster, card).get("provided_value", 0))


func _status_kind_count(unit: BattleUnitStateV2, kind: StringName) -> int:
	return unit.statuses.filter(func(status): return status.kind == kind).size()


func _duplicate_status_count(card: CardDefinitionV2, target: BattleUnitStateV2) -> int:
	var count := 0
	for status: StatusInstanceV2 in target.statuses:
		if status.source_id == card.id:
			count += 1
	return count


func _has_status_effect(card: CardDefinitionV2) -> bool:
	for effect: Dictionary in card.effects:
		if StringName(str(effect.get("type", ""))) in [&"apply_status", &"apply_dot", &"apply_hot", &"delay_damage", &"prism", &"absorb", &"stun", &"dispel", &"apply_aura"]:
			return true
	return false


func _is_healing(card: CardDefinitionV2) -> bool:
	for effect: Dictionary in card.effects:
		if StringName(str(effect.get("type", ""))) in [&"heal", &"apply_hot"]:
			return true
	return false
