class_name CostResolverV2
extends RefCounted


func can_pay(unit: BattleUnitStateV2, card: CardDefinitionV2) -> bool:
	return bool(resolve_payment(card, unit.resources, unit).get("valid", false))


func resolve_payment(card: CardDefinitionV2, resources: ResourceStateV2, unit: BattleUnitStateV2 = null) -> Dictionary:
	resources.sort_pips()
	var plan := _empty_plan(card, resources)
	if resources.shadow_pips < card.shadow_cost:
		plan["failure_reason"] = "shadow_pips"
		return plan

	# Typed School Pip requirements are reserved before ordinary Main Pip value is solved.
	var reserved: Array[int] = []
	for school_key in card.school_pip_requirements:
		var school_id := StringName(str(school_key))
		var required := int(card.school_pip_requirements[school_key])
		var found := 0
		for index in resources.pips.size():
			if found >= required:
				break
			if not reserved.has(index) and resources.pips[index] == ResourceStateV2.PipKind.SCHOOL and resources.pip_schools[index] == school_id:
				reserved.append(index)
				found += 1
		if found < required:
			plan["failure_reason"] = "school_requirement_%s" % school_id
			return plan
	plan["school_requirements_satisfied"] = true
	plan["reserved_school_indices"] = reserved.duplicate()

	var candidates: Array[int] = []
	for index in resources.pips.size():
		if not reserved.has(index):
			candidates.append(index)
	# Preserve valuable pips only after equal overpay and equal consumed count.
	candidates.sort_custom(func(a: int, b: int):
		return a > b if resources.pips[a] == resources.pips[b] else resources.pips[a] < resources.pips[b])

	var best: Array[int] = []
	if card.x_pip:
		best.assign(candidates)
	var best_value := 0
	var best_overpay := 1 << 20
	var best_count := 1 << 20
	var best_priority := 1 << 20
	if card.x_pip:
		for pip_index in best:
			best_value += get_pip_payment_value(resources, pip_index, unit, card)
		best_overpay = 0
		best_count = best.size()
	for mask in range(0 if card.x_pip else (1 << candidates.size())):
		var value := 0
		var chosen: Array[int] = []
		var priority := 0
		for bit in candidates.size():
			if mask & (1 << bit):
				var pip_index := candidates[bit]
				chosen.append(pip_index)
				priority += 8 if resources.pips[pip_index] == ResourceStateV2.PipKind.SCHOOL else (1 if resources.pips[pip_index] == ResourceStateV2.PipKind.POWER else 0)
				value += get_pip_payment_value(resources, pip_index, unit, card)
		if value < card.minimum_pip_cost:
			continue
		var overpay := value - card.pip_cost
		# Exact payment first, then fewer pips; Power wins an equal-count School tie.
		if overpay < best_overpay or (overpay == best_overpay and (chosen.size() < best_count or (chosen.size() == best_count and priority < best_priority))):
			best = chosen
			best_value = value
			best_overpay = overpay
			best_count = chosen.size()
			best_priority = priority

	if card.minimum_pip_cost > 0 and best.is_empty():
		plan["failure_reason"] = "main_pip_value"
		return plan

	var all_indices: Array[int] = reserved + best
	all_indices.sort()
	var consumed: Array[Dictionary] = []
	for index in all_indices:
		consumed.append({
			"slot": index,
			"kind": resources.pips[index],
			"school": str(resources.pip_schools[index]),
			"value": 0 if reserved.has(index) else get_pip_payment_value(resources, index, unit, card),
			"role": "school_requirement" if reserved.has(index) else "main_value"
		})
	plan["valid"] = true
	plan["pip_indices"] = all_indices
	plan["consumed_pips"] = consumed
	plan["provided_value"] = best_value
	plan["shadow_consumed"] = card.shadow_cost
	plan["shadow"] = card.shadow_cost
	plan["overpay"] = 0 if card.x_pip else maxi(best_value - card.pip_cost, 0)
	plan["failure_reason"] = ""
	return plan


func apply_payment_plan(unit: BattleUnitStateV2, plan: Dictionary) -> bool:
	if not bool(plan.get("valid", false)) or unit.resources.shadow_pips < int(plan.get("shadow_consumed", 0)):
		return false
	var consumed := plan.get("consumed_pips", []) as Array
	for entry_value in consumed:
		var entry := entry_value as Dictionary
		var index := int(entry.get("slot", -1))
		if index < 0 or index >= unit.resources.pips.size():
			return false
		if unit.resources.pips[index] != int(entry.get("kind", -1)) or str(unit.resources.pip_schools[index]) != str(entry.get("school", "")):
			return false
	unit.resources.shadow_pips -= int(plan.get("shadow_consumed", 0))
	var indices: Array[int] = []
	for entry_value in consumed:
		indices.append(int((entry_value as Dictionary).get("slot", -1)))
	indices.sort()
	indices.reverse()
	for index in indices:
		unit.resources.pips.remove_at(index)
		unit.resources.pip_schools.remove_at(index)
	return true


func payment_plan(unit: BattleUnitStateV2, card: CardDefinitionV2) -> Dictionary:
	return resolve_payment(card, unit.resources, unit)


func spend(unit: BattleUnitStateV2, card: CardDefinitionV2) -> Dictionary:
	var plan := resolve_payment(card, unit.resources, unit)
	if not apply_payment_plan(unit, plan):
		return {}
	return plan


func available_payment_summary(unit: BattleUnitStateV2, card: CardDefinitionV2) -> Dictionary:
	var counts := {"normal":0, "power":0, "school":0}
	var value := 0
	var items: Array[Dictionary] = []
	for index in unit.resources.pips.size():
		match unit.resources.pips[index]:
			ResourceStateV2.PipKind.NORMAL: counts.normal += 1
			ResourceStateV2.PipKind.POWER: counts.power += 1
			ResourceStateV2.PipKind.SCHOOL: counts.school += 1
		var pip_value := get_pip_payment_value(unit.resources, index, unit, card)
		value += pip_value
		items.append({
			"slot": index, "kind": unit.resources.pips[index],
			"school": str(unit.resources.pip_schools[index]), "value": pip_value
		})
	return {"counts": counts, "items":items, "available_value": value, "plan": resolve_payment(card, unit.resources, unit)}


func get_pip_payment_value(resources: ResourceStateV2, index: int, caster: BattleUnitStateV2, spell: CardDefinitionV2) -> int:
	if index < 0 or index >= resources.pips.size():
		return 0
	var caster_school := caster.school_id if caster != null else &""
	var spell_school := spell.school_id if spell != null else &""
	match resources.pips[index]:
		ResourceStateV2.PipKind.NORMAL:
			return 1
		ResourceStateV2.PipKind.POWER:
			return 2 if not caster_school.is_empty() and caster_school == spell_school else 1
		ResourceStateV2.PipKind.SCHOOL:
			var pip_school := resources.pip_schools[index]
			return 2 if spell_school == caster_school or spell_school == pip_school else 1
	return 0


func pip_payment_value(resources: ResourceStateV2, index: int, card: CardDefinitionV2, unit: BattleUnitStateV2 = null) -> int:
	return get_pip_payment_value(resources, index, unit, card)


func _empty_plan(card: CardDefinitionV2, resources: ResourceStateV2) -> Dictionary:
	return {
		"valid": false,
		"consumed_pips": [],
		"pip_indices": [],
		"provided_value": 0,
		"required_value": card.minimum_pip_cost if card.x_pip else card.pip_cost,
		"x_pip": card.x_pip,
		"school_requirements_satisfied": card.school_pip_requirements.is_empty(),
		"reserved_school_indices": [],
		"shadow_consumed": 0,
		"shadow": card.shadow_cost,
		"overpay": 0,
		"available_slots": resources.pips.size(),
		"failure_reason": ""
	}
