class_name BattleEngineV2
extends RefCounted

const StatusQuery = preload("res://scripts/battle_v2/core/status_query_v2.gd")

var content: ContentRegistryV2
var state := BattleStateV2.new()
var rng := RandomNumberGenerator.new()
var event_stream := BattleEventStreamV2.new()
var turn_manager := TurnManagerV2.new()
var cost_resolver := CostResolverV2.new()
var target_resolver := TargetResolverV2.new()
var status_resolver := StatusResolverV2.new()
var death_resolver := DeathResolverV2.new()
var damage_resolver := DamageResolverV2.new()
var healing_resolver := HealingResolverV2.new()
var resource_resolver := ResourceResolverV2.new()
var effect_registry := EffectRegistryV2.new()
var action_resolver := ActionResolverV2.new()
var rules: Dictionary = {}
var presentation_only := false
var _next_card_instance_id: int = 1
var _next_status_instance_id: int = 1


func setup(p_content: ContentRegistryV2, scenario: Dictionary, seed: int = 20260816) -> bool:
	presentation_only = false
	content = p_content
	if content == null or not content.errors.is_empty() or scenario.is_empty():
		return false
	rng.seed = seed
	event_stream.clear()
	state = BattleStateV2.new()
	rules = (scenario.get("rules", {}) as Dictionary).duplicate(true)
	_next_card_instance_id = 1
	_next_status_instance_id = 1
	_wire_resolvers()
	var teams: Array = scenario.get("teams", [])
	if teams.size() != 2:
		return false
	for team in 2:
		var members: Array = teams[team]
		if members.is_empty() or members.size() > 4:
			return false
		for slot in members.size():
			var unit := _create_unit(StringName(str(members[slot])), team, slot)
			if unit == null:
				return false
			state.units.append(unit)
			_apply_starting_resources(unit, scenario)
	return true


func _wire_resolvers() -> void:
	status_resolver.event_stream = event_stream
	death_resolver.event_stream = event_stream
	damage_resolver.event_stream = event_stream
	damage_resolver.status_resolver = status_resolver
	damage_resolver.death_resolver = death_resolver
	damage_resolver.rng = rng
	healing_resolver.event_stream = event_stream
	healing_resolver.status_resolver = status_resolver
	healing_resolver.rng = rng
	resource_resolver.event_stream = event_stream
	resource_resolver.rng = rng
	resource_resolver.shadow_min = int(rules.get("shadow_progress_min", 18))
	resource_resolver.shadow_max = int(rules.get("shadow_progress_max", 30))
	resource_resolver.school_pip_enabled = bool(rules.get("school_pip_enabled", true))
	resource_resolver.shadow_pip_enabled = bool(rules.get("shadow_pip_enabled", true))
	resource_resolver.skip_first_round_main_generation = bool(rules.get("skip_first_round_main_generation", false))
	action_resolver.event_stream = event_stream
	action_resolver.cost_resolver = cost_resolver
	action_resolver.target_resolver = target_resolver
	action_resolver.status_resolver = status_resolver
	action_resolver.effect_registry = effect_registry


func _create_unit(character_id: StringName, team: int, slot: int) -> BattleUnitStateV2:
	if not content.characters.has(character_id):
		return null
	var character := (content.characters[character_id] as Dictionary).duplicate(true)
	character["battle_id"] = "%s%d" % ["P" if team == 0 else "E", slot]
	character["character_id"] = str(character_id)
	var unit := BattleUnitStateV2.new()
	unit.setup(character, team, slot)
	var deck_id := str(character.get("default_deck", ""))
	var deck_overrides := rules.get("deck_overrides", {}) as Dictionary
	deck_id = str(deck_overrides.get(str(unit.id), deck_overrides.get(str(character_id), deck_id)))
	var deck_counts := content.decks.get(deck_id, {}) as Dictionary
	for card_id in deck_counts:
		var definition := content.card(StringName(str(card_id)))
		for copy_index in int(deck_counts[card_id]):
			unit.deck.draw_pile.append(_new_card(definition))
	_shuffle_cards(unit.deck.draw_pile)
	for treasure_id in content.treasure_deck:
		unit.deck.treasure_pile.append(_new_card(content.card(treasure_id)))
	_shuffle_cards(unit.deck.treasure_pile)
	return unit


func _apply_starting_resources(unit: BattleUnitStateV2, scenario: Dictionary) -> void:
	var config := (scenario.get("starting_resources", {}) as Dictionary).duplicate(true)
	var team_key := "player" if unit.team == 0 else "enemy"
	config.merge(scenario.get("%s_starting_resources" % team_key, {}) as Dictionary, true)
	var by_unit := scenario.get("unit_starting_resources", {}) as Dictionary
	config.merge(by_unit.get(str(unit.character_id), {}) as Dictionary, true)
	for index in maxi(0, int(config.get("normal", 0))):
		unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
	for index in maxi(0, int(config.get("power", 0))):
		unit.resources.append_pip(ResourceStateV2.PipKind.POWER)
	for school_value in config.get("school", []):
		unit.resources.append_pip(ResourceStateV2.PipKind.SCHOOL, StringName(str(school_value)))
	unit.resources.shadow_pips = clampi(int(config.get("shadow", 0)), 0, ResourceStateV2.MAX_SHADOW_PIPS)


func _new_card(definition: CardDefinitionV2) -> CardInstanceV2:
	var card := CardInstanceV2.new(_next_card_instance_id, definition)
	_next_card_instance_id += 1
	return card


func _shuffle_cards(cards: Array[CardInstanceV2]) -> void:
	for index in range(cards.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var temp := cards[index]
		cards[index] = cards[swap_index]
		cards[swap_index] = temp


func start_battle() -> void:
	if presentation_only:return
	state.phase = BattleStateV2.Phase.SETUP
	event_stream.publish(&"BattleStarted", 0, {"unit_ids": state.units.map(func(unit): return str((unit as BattleUnitStateV2).id))})
	start_next_round()


func start_next_round() -> bool:
	if state.phase == BattleStateV2.Phase.FINISHED:
		return false
	state.round_index += 1
	if state.pvp:state.active_team = state.first_team if state.round_index % 2 == 1 else 1-state.first_team
	state.phase = BattleStateV2.Phase.RESOLVING
	state.actions.clear()
	for unit in state.units:
		unit.planned_action = null
		unit.action_slot_passed = false
	event_stream.publish(&"TurnStarted", state.round_index, {"round": state.round_index})
	if not state.pvp or state.round_index % 2 == 1:
		status_resolver.process_round_start(self)
	if check_battle_end():
		return false
	if state.pvp:resource_resolver.begin_pvp_turn(state)
	else:resource_resolver.begin_round(state)
	state.phase = BattleStateV2.Phase.PLANNING
	event_stream.publish(&"PlanningStarted", state.round_index, {})
	return true


func queue_action(intent: ActionIntentV2) -> bool:
	if state.phase != BattleStateV2.Phase.PLANNING:
		return false
	var actor := state.unit_by_id(intent.actor_id)
	if actor == null or not actor.alive or state.actions.has(actor.id):
		return false
	if state.pvp and actor.team != state.active_team:return false
	if intent.pass_action:
		state.actions[actor.id] = intent
		actor.planned_action = intent
		event_stream.publish(&"ActionQueued", state.round_index, {"unit_id": str(actor.id), "pass": true})
		return true
	var card := card_in_hand(actor, intent.card_instance_id)
	if card == null or not cost_resolver.can_pay(actor, card.definition):
		return false
	if target_resolver.resolve_selected(state, actor, card.definition, intent.target_ids).is_empty():
		return false
	intent.card_definition_id = card.card_id()
	state.actions[actor.id] = intent
	actor.planned_action = intent
	event_stream.publish(&"ActionQueued", state.round_index, {"unit_id": str(actor.id), "card_id": str(card.card_id()), "targets": Array(intent.target_ids).map(func(id): return str(id))})
	return true


func queue_pass(unit_id: StringName) -> bool:
	return queue_action(ActionIntentV2.pass_turn(unit_id))


func all_living_units_planned() -> bool:
	for unit in state.living_units(state.active_team if state.pvp else -1):
		if not state.actions.has(unit.id):
			return false
	return true


func resolve_round() -> void:
	if not begin_resolution():
		return
	for actor in turn_manager.resolution_order(state):
		if state.phase == BattleStateV2.Phase.FINISHED:
			return
		resolve_actor(actor)
		if state.phase == BattleStateV2.Phase.FINISHED:
			return
	end_resolution()


func begin_resolution() -> bool:
	if state.phase != BattleStateV2.Phase.PLANNING:
		return false
	state.phase = BattleStateV2.Phase.RESOLVING
	return true


func resolve_actor(actor: BattleUnitStateV2) -> Array[BattleEventV2]:
	var result := begin_actor_turn(actor)
	if actor != null and actor.alive and state.phase == BattleStateV2.Phase.RESOLVING:
		result.append_array(resolve_actor_action(actor))
	return result


func begin_actor_turn(actor: BattleUnitStateV2) -> Array[BattleEventV2]:
	var event_start := event_stream.events.size()
	if state.phase != BattleStateV2.Phase.RESOLVING or actor == null:
		return []
	if not actor.alive:
		actor.action_slot_passed = true
		return []
	event_stream.publish(&"ActionTurnStarted", state.round_index, {"unit_id": str(actor.id)})
	status_resolver.process_action_start(self, actor)
	check_battle_end()
	var result: Array[BattleEventV2] = []
	for index in range(event_start, event_stream.events.size()):
		result.append(event_stream.events[index])
	return result


func resolve_actor_action(actor: BattleUnitStateV2) -> Array[BattleEventV2]:
	var event_start := event_stream.events.size()
	if state.phase != BattleStateV2.Phase.RESOLVING or actor == null or not actor.alive:
		if actor != null:
			actor.action_slot_passed = true
		return []
	action_resolver.resolve(self, actor)
	status_resolver.process_action_end(self, actor)
	check_battle_end()
	var result: Array[BattleEventV2] = []
	for index in range(event_start, event_stream.events.size()):
		result.append(event_stream.events[index])
	return result

func end_resolution() -> void:
	if state.phase == BattleStateV2.Phase.RESOLVING:
		event_stream.publish(&"TurnEnded", state.round_index, {})


func card_in_hand(unit: BattleUnitStateV2, instance_id: int) -> CardInstanceV2:
	for card in unit.deck.hand:
		if card.instance_id == instance_id:
			return card
	return null


func valid_targets(unit_id: StringName, card_instance_id: int) -> Array[BattleUnitStateV2]:
	var unit := state.unit_by_id(unit_id)
	if unit == null:
		return []
	var card := card_in_hand(unit, card_instance_id)
	return target_resolver.valid_targets(state, unit, card.definition) if card != null else []


func resolve_damage(source_id: StringName, target_id: StringName, school_id: StringName, amount: int, outgoing: float = 1.0, origin: StringName = &"spell", source_snapshot: Dictionary = {}) -> int:
	var event := DamageEventV2.new()
	event.source_snapshot = source_snapshot
	event.source_id = source_id
	event.target_id = target_id
	event.original_school_id = school_id
	event.school_id = school_id
	event.base_amount = amount
	event.outgoing_multiplier = outgoing
	event.origin = origin
	return damage_resolver.resolve(state, event)


func resolve_healing(source_id: StringName, target_id: StringName, amount: int, outgoing: float = 1.0, origin: StringName = &"spell", apply_charms:bool=true) -> int:
	var event := HealingEventV2.new()
	event.source_id = source_id
	event.target_id = target_id
	event.base_amount = amount
	event.outgoing_multiplier = outgoing
	event.origin = origin
	return healing_resolver.resolve(state, event, apply_charms)


func add_status(target_id: StringName, status_definition_id: StringName, source_id: StringName, caster_id: StringName, school_filter: Variant, value: float, ticks: int, payload: Dictionary) -> StatusInstanceV2:
	var target := state.unit_by_id(target_id)
	var definition := content.statuses.get(status_definition_id, {}) as Dictionary
	if target == null or definition.is_empty():
		return null
	var status := StatusInstanceV2.new(_next_status_instance_id)
	_next_status_instance_id += 1
	status.definition_id = status_definition_id
	status.kind = StringName(str(definition.get("kind", status_definition_id)))
	status.source_id = source_id
	status.source_group = StringName(str(payload.get("source_group", source_id)))
	status.caster_id = caster_id
	status.set_school_filters(school_filter)
	status.value = value
	status.ticks = ticks
	status.payload = payload.duplicate(true)
	target.statuses.append(status)
	event_stream.publish(&"StatusApplied", state.round_index, {"target_id": str(target.id), "status": status.to_dict()})
	return status


func add_global_status(status_definition_id: StringName, source_id: StringName, caster_id: StringName, school_filter: Variant, value: float, ticks: int, payload: Dictionary) -> StatusInstanceV2:
	var definition := content.statuses.get(status_definition_id, {}) as Dictionary
	if definition.is_empty():
		return null
	var status := StatusInstanceV2.new(_next_status_instance_id)
	_next_status_instance_id += 1
	status.definition_id = status_definition_id
	status.kind = StringName(str(definition.get("kind", status_definition_id)))
	status.source_id = source_id
	status.source_group = StringName(str(payload.get("source_group", source_id)))
	status.caster_id = caster_id
	status.set_school_filters(school_filter)
	status.value = value
	status.ticks = ticks
	status.payload = payload.duplicate(true)
	state.global_statuses.append(status)
	event_stream.publish(&"GlobalApplied", state.round_index, {"status":status.to_dict()})
	return status


func clear_statuses(target_id: StringName, reason: StringName = &"debug_clear") -> int:
	var target := state.unit_by_id(target_id)
	if target == null:
		return 0
	var removed: Array[StatusInstanceV2] = target.statuses.duplicate()
	target.statuses.clear()
	for status: StatusInstanceV2 in removed:
		event_stream.publish(&"StatusConsumed", state.round_index, {
			"unit_id": str(target.id), "status_id": status.instance_id,
			"definition_id": str(status.definition_id), "kind": str(status.kind),
			"source_id": str(status.source_id), "value": status.value, "reason": str(reason)
		})
	return removed.size()


func remove_statuses(target_id: StringName, criteria: Dictionary, count: int = -1, reason: StringName = &"removed") -> Array[StatusInstanceV2]:
	var target := state.unit_by_id(target_id)
	var removed: Array[StatusInstanceV2] = []
	if target == null:
		return removed
	for status: StatusInstanceV2 in StatusQuery.newest_first(target):
		if count >= 0 and removed.size() >= count:
			break
		if not _status_matches_criteria(status, criteria):
			continue
		target.statuses.erase(status)
		removed.append(status)
		event_stream.publish(&"StatusRemoved", state.round_index, {
			"unit_id":str(target.id), "status_id":status.instance_id,
			"kind":str(status.kind), "reason":str(reason)
		})
	return removed


func consume_first_status(target_id: StringName, criteria: Dictionary, reason: StringName = &"consumed") -> bool:
	return not remove_statuses(target_id, criteria, 1, reason).is_empty()


func steal_statuses(from_id: StringName, to_id: StringName, criteria: Dictionary, count: int = 1) -> int:
	var source := state.unit_by_id(from_id)
	var recipient := state.unit_by_id(to_id)
	if source == null or recipient == null or source == recipient:
		return 0
	var moved := 0
	for status: StatusInstanceV2 in StatusQuery.newest_first(source):
		if count >= 0 and moved >= count:
			break
		if not _status_matches_criteria(status, criteria):
			continue
		source.statuses.erase(status)
		status.caster_id = recipient.id
		recipient.statuses.append(status)
		moved += 1
		event_stream.publish(&"StatusStolen", state.round_index, {
			"from_id":str(from_id), "to_id":str(to_id), "status_id":status.instance_id, "kind":str(status.kind)
		})
	return moved


func detonate_dots(target_id: StringName, count: int = 1, school_filter: Variant = "*") -> int:
	var target := state.unit_by_id(target_id)
	if target == null:
		return 0
	var allowed := _school_filter_array(school_filter)
	var detonated := 0
	for status: StatusInstanceV2 in StatusQuery.newest_first(target):
		if detonated >= count or status.kind != &"dot" or not _filter_accepts(allowed, status.school_filter):
			continue
		target.statuses.erase(status)
		var amount := int(status.payload.get("amount", 0)) * maxi(status.ticks, 0)
		resolve_damage(status.caster_id, target.id, status.school_filter, amount, float(status.payload.get("outgoing_multiplier",1.0)), &"detonate", status.payload.get("source_snapshot",{}))
		detonated += 1
		event_stream.publish(&"DotDetonated", state.round_index, {"target_id":str(target.id), "status_id":status.instance_id, "amount":amount})
	return detonated


func transfer_dot(from_id:StringName,to_id:StringName) -> bool:
	var source:=state.unit_by_id(from_id)
	var target:=state.unit_by_id(to_id)
	if source==null or target==null or source==target:return false
	for status:StatusInstanceV2 in StatusQuery.newest_first(source):
		if status.kind!=&"dot":continue
		source.statuses.erase(status);target.statuses.append(status)
		event_stream.publish(&"StatusTransferred",state.round_index,{"from_id":str(from_id),"to_id":str(to_id),"status_id":status.instance_id,"kind":"dot"})
		return true
	return false

func modify_dot_duration(target_id: StringName, delta: int, count: int = 1, school_filter: Variant = "*") -> int:
	var target := state.unit_by_id(target_id)
	if target == null:
		return 0
	var allowed := _school_filter_array(school_filter)
	var modified := 0
	for status: StatusInstanceV2 in StatusQuery.newest_first(target):
		if (count>=0 and modified >= count) or status.kind != &"dot" or not _filter_accepts(allowed, status.school_filter):
			continue
		status.ticks = maxi(0, status.ticks + delta)
		if status.ticks == 0:
			target.statuses.erase(status)
		modified += 1
		event_stream.publish(&"DotDurationChanged", state.round_index, {"target_id":str(target.id), "status_id":status.instance_id, "ticks":status.ticks})
	return modified


func modify_resources(target_id: StringName, effect: Dictionary) -> bool:
	var target := state.unit_by_id(target_id)
	if target == null:
		return false
	var operation := StringName(str(effect.get("operation", "add")))
	var count := maxi(0, int(effect.get("count", 1)))
	var changed := 0
	match operation:
		&"add_normal", &"add_power", &"add_school":
			var kind := ResourceStateV2.PipKind.NORMAL if operation == &"add_normal" else ResourceStateV2.PipKind.POWER if operation == &"add_power" else ResourceStateV2.PipKind.SCHOOL
			for index in count:
				changed += 1 if target.resources.append_pip(kind, StringName(str(effect.get("school", target.school_id)))) else 0
		&"add_shadow":
			var before := target.resources.shadow_pips
			target.resources.shadow_pips = mini(ResourceStateV2.MAX_SHADOW_PIPS, before + count)
			changed = target.resources.shadow_pips - before
		&"remove_main":
			for index in mini(count, target.resources.pips.size()):
				target.resources.pips.pop_back()
				target.resources.pip_schools.pop_back()
				changed += 1
		&"remove_shadow":
			changed = mini(count, target.resources.shadow_pips)
			target.resources.shadow_pips -= changed
		&"normal_to_power", &"power_to_school":
			var from_kind := ResourceStateV2.PipKind.NORMAL if operation == &"normal_to_power" else ResourceStateV2.PipKind.POWER
			for pip_index in target.resources.pips.size():
				if changed >= count:
					break
				if target.resources.pips[pip_index] == from_kind:
					target.resources.pips[pip_index] = ResourceStateV2.PipKind.POWER if operation == &"normal_to_power" else ResourceStateV2.PipKind.SCHOOL
					target.resources.pip_schools[pip_index] = &"" if operation == &"normal_to_power" else StringName(str(effect.get("school", target.school_id)))
					changed += 1
	event_stream.publish(&"ResourceModified", state.round_index, {"unit_id":str(target.id), "operation":str(operation), "count":changed})
	return changed > 0


func remove_global_statuses(criteria: Dictionary, reason: StringName = &"removed") -> int:
	var removed := 0
	for status: StatusInstanceV2 in state.global_statuses.duplicate():
		if not _status_matches_criteria(status, criteria):
			continue
		state.global_statuses.erase(status)
		removed += 1
		event_stream.publish(&"GlobalRemoved", state.round_index, {"status_id":status.instance_id, "reason":str(reason)})
	return removed


func _status_matches_criteria(status: StatusInstanceV2, criteria: Dictionary) -> bool:
	return StatusQuery.matches(status, criteria)


func _school_filter_array(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if value is Array:
		for item in value:
			result.append(StringName(str(item)))
	else:
		result.append(StringName(str(value)))
	return result


func _filter_accepts(allowed: Array[StringName], school_id: StringName) -> bool:
	return allowed.is_empty() or allowed.has(&"*") or allowed.has(school_id)


func _filters_intersect(left: Array[StringName], right: Array[StringName]) -> bool:
	if left.is_empty() or right.is_empty() or left.has(&"*") or right.has(&"*"):
		return true
	for school_id in left:
		if right.has(school_id):
			return true
	return false


func revive_unit(target_id: StringName, amount: int) -> bool:
	var target := state.unit_by_id(target_id)
	return death_resolver.revive(state, target, amount) if target != null else false


func set_next_charge(unit_id: StringName, school_id: StringName) -> bool:
	var unit := state.unit_by_id(unit_id)
	if unit == null or not content.schools.has(school_id):
		return false
	unit.resources.next_charge_school = school_id
	event_stream.publish(&"ChargeSchoolSelected", state.round_index, {"unit_id": str(unit.id), "school": str(school_id)})
	return true


func discard_for_treasure(unit_id: StringName, card_instance_id: int) -> bool:
	if state.phase != BattleStateV2.Phase.PLANNING or state.actions.has(unit_id):
		return false
	var unit := state.unit_by_id(unit_id)
	if unit == null or not unit.alive or unit.deck.discard_count_this_round >= DeckStateV2.HAND_LIMIT:
		return false
	var card := card_in_hand(unit, card_instance_id)
	if card == null or card.treasure_locked:
		return false
	unit.deck.hand.erase(card)
	if card.definition.treasure or card.equipment:
		unit.deck.removed_cards.append(card)
	else:
		unit.deck.discard_pile.append(card)
	unit.deck.discard_count_this_round += 1
	event_stream.publish(&"CardDiscarded", state.round_index, {
		"unit_id": str(unit.id), "card_id": str(card.card_id()),
		"instance_id": card.instance_id, "treasure_credit": unit.deck.discard_count_this_round - unit.deck.treasure_draw_count_this_round
	})
	return true


func draw_one_treasure(unit_id: StringName) -> CardInstanceV2:
	if state.phase != BattleStateV2.Phase.PLANNING:
		return null
	var unit := state.unit_by_id(unit_id)
	if unit == null or not unit.alive or state.actions.has(unit.id):
		return null
	if unit.deck.hand.size() >= DeckStateV2.HAND_LIMIT or unit.deck.treasure_pile.is_empty():
		return null
	if unit.deck.treasure_draw_count_this_round >= unit.deck.discard_count_this_round + unit.deck.fusion_draw_credits:
		return null
	var treasure: CardInstanceV2 = unit.deck.treasure_pile.pop_back()
	treasure.treasure_locked = true
	unit.deck.hand.append(treasure)
	unit.deck.treasure_draw_count_this_round += 1
	event_stream.publish(&"TreasureDrawn", state.round_index, {
		"unit_id": str(unit.id), "card_id": str(treasure.card_id()),
		"instance_id": treasure.instance_id, "manual": true
	})
	return treasure


func configure_deck(unit_id: StringName, card_counts: Dictionary) -> bool:
	if state.phase not in [BattleStateV2.Phase.SETUP, BattleStateV2.Phase.PLANNING]:
		return false
	var unit := state.unit_by_id(unit_id)
	if unit == null or not unit.alive or state.actions.has(unit.id):
		return false
	var total := 0
	for card_id_value in card_counts:
		var count := int(card_counts[card_id_value])
		var definition := content.card(StringName(str(card_id_value)))
		if count < 0 or definition == null or not definition.learned or definition.treasure or definition.enemy_only:
			return false
		total += count
	if total > 40:
		return false
	unit.deck.removed_cards.append_array(unit.deck.hand)
	unit.deck.removed_cards.append_array(unit.deck.draw_pile)
	unit.deck.removed_cards.append_array(unit.deck.discard_pile)
	unit.deck.hand.clear()
	unit.deck.draw_pile.clear()
	unit.deck.discard_pile.clear()
	unit.deck.discard_count_this_round = 0
	unit.deck.treasure_draw_count_this_round = 0
	unit.deck.fusion_draw_credits = 0
	for card_id_value in card_counts:
		var definition := content.card(StringName(str(card_id_value)))
		for copy_index in int(card_counts[card_id_value]):
			unit.deck.draw_pile.append(_new_card(definition))
	_shuffle_cards(unit.deck.draw_pile)
	var drawn := unit.deck.draw_to_limit()
	for card in drawn:
		event_stream.publish(&"CardDrawn", state.round_index, {"unit_id": str(unit.id), "card_id": str(card.card_id()), "instance_id": card.instance_id, "deck_config": true})
	event_stream.publish(&"DeckConfigured", state.round_index, {"unit_id": str(unit.id), "card_count": total})
	return true


func fuse_cards(unit_id: StringName, first_id: int, second_id: int) -> CardInstanceV2:
	if state.phase != BattleStateV2.Phase.PLANNING or state.actions.has(unit_id):
		return null
	var unit := state.unit_by_id(unit_id)
	if unit == null or not unit.alive or first_id == second_id:
		return null
	var first := card_in_hand(unit, first_id)
	var second := card_in_hand(unit, second_id)
	if first == null or second == null:
		return null
	for card in [first, second]:
		if card.definition.treasure or card.equipment or card.temporary or not card.definition.learned or card.definition.enemy_only:
			return null
	var ids := [str(first.card_id()), str(second.card_id())]
	ids.sort()
	var result_id := content.fusion_recipes.get("+".join(ids), &"") as StringName
	if result_id == &"" or content.card(result_id) == null:
		return null
	unit.deck.hand.erase(first)
	unit.deck.hand.erase(second)
	unit.deck.discard_pile.append_array([first, second])
	var result := _new_card(content.card(result_id))
	unit.deck.hand.append(result)
	unit.deck.fusion_draw_credits += 1
	event_stream.publish(&"CardsFused", state.round_index, {"unit_id": str(unit.id), "inputs": ids, "result": str(result_id), "instance_id": result.instance_id})
	return result


func check_battle_end() -> bool:
	var team_zero_alive := not state.living_units(0).is_empty()
	var team_one_alive := not state.living_units(1).is_empty()
	if team_zero_alive and team_one_alive:
		return false
	state.phase = BattleStateV2.Phase.FINISHED
	state.winner_team = 0 if team_zero_alive else 1 if team_one_alive else -1
	event_stream.publish(&"BattleEnded", state.round_index, {"winner_team": state.winner_team})
	return true



