class_name BattleSandboxControllerV2
extends RefCounted

var content := ContentRegistryV2.new()
var engine := BattleEngineV2.new()
var ai_policy := BasicAIPolicyV2.new()
var scenario_factory := ScenarioFactoryV2.new()
var seed: int = 20260816


func setup_default(p_seed: int = 20260816) -> bool:
	seed = p_seed
	if not content.load_default():
		return false
	if not engine.setup(content, scenario_factory.default_scenario(content), seed):
		return false
	engine.start_battle()
	return true


func setup_scenario(scenario: Dictionary, p_seed: int = 20260816) -> bool:
	seed = p_seed
	if content.cards.is_empty() and not content.load_default():
		return false
	if not engine.setup(content, scenario, seed):
		return false
	engine.start_battle()
	return true


func plan_all_with_ai() -> void:
	for unit in engine.state.living_units():
		if engine.state.actions.has(unit.id):
			continue
		var intent := ai_policy.choose_action(engine, unit)
		if not engine.queue_action(intent):
			engine.queue_pass(unit.id)


func run_one_round() -> void:
	if engine.state.phase == BattleStateV2.Phase.FINISHED:
		return
	plan_all_with_ai()
	engine.resolve_round()
	if engine.state.phase != BattleStateV2.Phase.FINISHED:
		engine.start_next_round()


func run_auto_battle(max_rounds: int = 60) -> int:
	while engine.state.phase != BattleStateV2.Phase.FINISHED and engine.state.round_index <= max_rounds:
		run_one_round()
	return engine.state.winner_team


func set_hp(unit_id: StringName, hp: int) -> bool:
	var unit := engine.state.unit_by_id(unit_id)
	if unit == null:
		return false
	unit.hp = clampi(hp, 0, unit.max_hp)
	unit.alive = unit.hp > 0
	return true


func set_resources(unit_id: StringName, normal: int, power: int, school: int, school_id: StringName, shadow: int) -> bool:
	var unit := engine.state.unit_by_id(unit_id)
	if unit == null:
		return false
	unit.resources.pips.clear()
	unit.resources.pip_schools.clear()
	for index in mini(normal, ResourceStateV2.MAX_PIPS):
		unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
	for index in mini(power, ResourceStateV2.MAX_PIPS - unit.resources.pips.size()):
		unit.resources.append_pip(ResourceStateV2.PipKind.POWER)
	for index in mini(school, ResourceStateV2.MAX_PIPS - unit.resources.pips.size()):
		unit.resources.append_pip(ResourceStateV2.PipKind.SCHOOL, school_id)
	unit.resources.shadow_pips = clampi(shadow, 0, ResourceStateV2.MAX_SHADOW_PIPS)
	return true


func give_card_to_hand(unit_id: StringName, card_id: StringName) -> CardInstanceV2:
	var unit := engine.state.unit_by_id(unit_id)
	var definition := content.card(card_id)
	if unit == null or definition == null or unit.deck.hand.size() >= DeckStateV2.HAND_LIMIT:
		return null
	var card := engine._new_card(definition)
	unit.deck.hand.append(card)
	return card


func set_hand(unit_id: StringName, card_ids: Array[StringName]) -> bool:
	var unit := engine.state.unit_by_id(unit_id)
	if unit == null or card_ids.size() > DeckStateV2.HAND_LIMIT:
		return false
	unit.deck.hand.clear()
	for card_id in card_ids:
		var definition := content.card(card_id)
		if definition == null:
			return false
		unit.deck.hand.append(engine._new_card(definition))
	return true


func set_draw_pile(unit_id: StringName, card_ids: Array[StringName]) -> bool:
	var unit := engine.state.unit_by_id(unit_id)
	if unit == null:
		return false
	unit.deck.draw_pile.clear()
	for card_id in card_ids:
		var definition := content.card(card_id)
		if definition == null:
			return false
		unit.deck.draw_pile.append(engine._new_card(definition))
	return true


func clear_statuses(unit_id: StringName) -> bool:
	var unit := engine.state.unit_by_id(unit_id)
	if unit == null:
		return false
	unit.statuses.clear()
	return true


func apply_status(unit_id: StringName, status_id: StringName, source_id: StringName, caster_id: StringName, value: float, ticks: int = 0, school_filter: StringName = &"*") -> StatusInstanceV2:
	return engine.add_status(unit_id, status_id, source_id, caster_id, school_filter, value, ticks, {})


func queue_direct_cast(unit_id: StringName, card_id: StringName, target_ids: Array[StringName]) -> bool:
	var unit := engine.state.unit_by_id(unit_id)
	if unit != null and unit.deck.hand.size() >= DeckStateV2.HAND_LIMIT:
		unit.deck.removed_cards.append(unit.deck.hand.pop_back())
	var card := give_card_to_hand(unit_id, card_id)
	return engine.queue_action(ActionIntentV2.cast(unit_id, card.instance_id, target_ids)) if card != null else false


func skip_unit(unit_id: StringName) -> bool:
	return engine.queue_pass(unit_id)


func snapshot() -> Dictionary:
	return engine.state.snapshot()


func event_log() -> Array[Dictionary]:
	return engine.event_stream.as_dicts()
