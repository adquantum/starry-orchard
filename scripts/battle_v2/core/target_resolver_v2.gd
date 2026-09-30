class_name TargetResolverV2
extends RefCounted


func valid_targets(state: BattleStateV2, caster: BattleUnitStateV2, card: CardDefinitionV2) -> Array[BattleUnitStateV2]:
	var result: Array[BattleUnitStateV2] = []
	var allies := state.team_units(caster.team)
	var enemies := state.team_units(1 - caster.team)
	match card.target_type:
		&"self":
			if caster.alive:
				result.append(caster)
		&"ally", &"all_allies":
			for unit in allies:
				if unit.alive or _heals_selected_ally(card):
					result.append(unit)
		&"dead_ally":
			for unit in allies:
				if not unit.alive:
					result.append(unit)
		&"enemy", &"all_enemies":
			for unit in enemies:
				if unit.alive:
					result.append(unit)
	return result


func resolve_selected(state: BattleStateV2, caster: BattleUnitStateV2, card: CardDefinitionV2, selected_ids: Array[StringName]) -> Array[BattleUnitStateV2]:
	var valid := valid_targets(state, caster, card)
	if card.target_type in [&"all_allies", &"all_enemies"]:
		return valid
	# Single-target spells must not turn client arrays into extra free effects.
	if selected_ids.size() != 1:
		return []
	var result: Array[BattleUnitStateV2] = []
	for id in selected_ids:
		var unit := state.unit_by_id(id)
		if unit != null and valid.has(unit):
			result.append(unit)
	return result


func resolve_effect_targets(state: BattleStateV2, caster: BattleUnitStateV2, effect: Dictionary, primary_targets: Array[BattleUnitStateV2], rng: RandomNumberGenerator = null) -> Array[BattleUnitStateV2]:
	var mode := StringName(str(effect.get("target", "selected")))
	var result: Array[BattleUnitStateV2] = []
	match mode:
		&"selected", &"primary":
			result.assign(primary_targets)
		&"self", &"caster":
			if caster.alive:
				result.append(caster)
		&"enemy", &"selected_enemy":
			for unit in primary_targets:
				if unit.alive and unit.team != caster.team:
					result.append(unit)
		&"ally", &"selected_ally":
			for unit in primary_targets:
				if (unit.alive or str(effect.get("type", "")) == "heal") and unit.team == caster.team:
					result.append(unit)
		&"all_enemies":
			result.assign(state.living_units(1 - caster.team))
		&"all_allies":
			result.assign(state.team_units(caster.team) if str(effect.get("type", "")) == "heal" else state.living_units(caster.team))
		&"dead_ally":
			for unit in state.team_units(caster.team):
				if not unit.alive:
					result.append(unit)
		&"random_enemy", &"random_ally":
			var pool := state.living_units(1 - caster.team if mode == &"random_enemy" else caster.team)
			if not pool.is_empty():
				result.append(pool[rng.randi_range(0, pool.size() - 1) if rng != null else 0])
	return result

# Only an immediate heal aimed at the selected ally can select a downed unit.
# A heal targeting the caster must not make unrelated selected buffs revive-capable.
func _heals_selected_ally(card: CardDefinitionV2) -> bool:
	for effect: Dictionary in card.effects:
		if str(effect.get("type", "")) == "heal" and str(effect.get("target", "selected")) in ["selected", "primary", "ally", "selected_ally", "all_allies"]:
			return true
	return false
