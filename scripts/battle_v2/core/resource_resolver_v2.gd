class_name ResourceResolverV2
extends RefCounted

var event_stream: BattleEventStreamV2
var rng: RandomNumberGenerator
var shadow_min: int = 18
var shadow_max: int = 30
var school_pip_enabled := true
var shadow_pip_enabled := true
var skip_first_round_main_generation := false


func begin_round(state: BattleStateV2) -> void:
	var top_archmastery := 1
	for unit in state.living_units():
		top_archmastery = maxi(top_archmastery, unit.archmastery)
	for unit in state.living_units():
		unit.resources.charge_school = unit.resources.next_charge_school
		if not (skip_first_round_main_generation and state.round_index == 1):
			_generate_main_pip(state, unit, top_archmastery)
		if shadow_pip_enabled:
			_generate_shadow(state, unit)
		unit.deck.unlock_treasures()
		var drawn := unit.deck.draw_opening_hand() if state.round_index == 1 and unit.deck.hand.is_empty() else unit.deck.draw_to_limit()
		for card in drawn:
			event_stream.publish(&"CardDrawn", state.round_index, {"unit_id": str(unit.id), "card_id": str(card.card_id()), "instance_id": card.instance_id})


func begin_pvp_turn(state: BattleStateV2) -> void:
	var top_archmastery := 1
	for unit in state.living_units():top_archmastery = maxi(top_archmastery, unit.archmastery)
	for unit in state.living_units():
		if unit.team != state.active_team:
			unit.resources.charge_school = unit.resources.next_charge_school
			_generate_main_pip(state, unit, top_archmastery)
			if shadow_pip_enabled:_generate_shadow(state, unit)
		else:
			unit.deck.unlock_treasures()
			for card in unit.deck.draw_to_limit():
				event_stream.publish(&"CardDrawn", state.round_index, {"unit_id":str(unit.id), "card_id":str(card.card_id()), "instance_id":card.instance_id})

func _generate_main_pip(state: BattleStateV2, unit: BattleUnitStateV2, top_archmastery: int) -> void:
	var generated_kind := -1
	if unit.resources.pips.size() < ResourceStateV2.MAX_PIPS:
		var kind := ResourceStateV2.PipKind.NORMAL
		var aura_chance := StatusResolverV2.new().stat_bonus(unit, &"extra_power_pip_chance", unit.school_id)
		var extra_power_chance := clampf(unit.school_stat(&"extra_power_pip_chance", unit.school_id) + aura_chance, 0.0, 1.0)
		# Preserve the legacy RNG stream exactly at 0%, and never sample on a full bar.
		if extra_power_chance > 0.0 and rng.randf() < extra_power_chance:
			kind = ResourceStateV2.PipKind.POWER
		if unit.resources.append_pip(kind):
			generated_kind = kind
	var ratio := 1.0 if unit.archmastery >= top_archmastery else clampf(float(unit.archmastery) / float(top_archmastery), 0.1, 0.95)
	unit.resources.archmastery_charge += 4 if rng.randf() <= ratio else 1
	var conversion := "power" if generated_kind == ResourceStateV2.PipKind.POWER else ("normal" if generated_kind == ResourceStateV2.PipKind.NORMAL else "charge")
	while unit.resources.archmastery_charge >= 4:
		var power_index := unit.resources.pips.find(ResourceStateV2.PipKind.POWER) if school_pip_enabled else -1
		if power_index >= 0:
			unit.resources.pips[power_index] = ResourceStateV2.PipKind.SCHOOL
			unit.resources.pip_schools[power_index] = unit.resources.charge_school
			conversion = "school"
		else:
			var normal_index := unit.resources.pips.find(ResourceStateV2.PipKind.NORMAL)
			if normal_index < 0:
				break
			unit.resources.pips[normal_index] = ResourceStateV2.PipKind.POWER
			conversion = "power"
		unit.resources.archmastery_charge -= 4
	unit.resources.sort_pips()
	event_stream.publish(&"ResourceGenerated", state.round_index, {
		"unit_id": str(unit.id), "resource": conversion,
		"charge_school": str(unit.resources.charge_school), "charge": unit.resources.archmastery_charge
	})


func _generate_shadow(state: BattleStateV2, unit: BattleUnitStateV2) -> void:
	if unit.resources.shadow_pips >= ResourceStateV2.MAX_SHADOW_PIPS:
		unit.resources.shadow_progress = mini(unit.resources.shadow_progress, 99)
		return
	unit.resources.shadow_progress += rng.randi_range(shadow_min, shadow_max)
	if unit.resources.shadow_progress >= 100:
		unit.resources.shadow_progress -= 100
		unit.resources.shadow_pips += 1
		event_stream.publish(&"ResourceGenerated", state.round_index, {"unit_id": str(unit.id), "resource": "shadow", "count": unit.resources.shadow_pips})
