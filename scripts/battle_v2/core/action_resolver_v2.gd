class_name ActionResolverV2
extends RefCounted

const StatusQuery = preload("res://scripts/battle_v2/core/status_query_v2.gd")
const Conditions = preload("res://scripts/battle_v2/core/condition_resolver_v2.gd")

var event_stream: BattleEventStreamV2
var cost_resolver: CostResolverV2
var target_resolver: TargetResolverV2
var status_resolver: StatusResolverV2
var effect_registry: EffectRegistryV2


func resolve(engine, actor: BattleUnitStateV2) -> void:
	actor.action_slot_passed = true
	if _consume_control_status(engine, actor, &"stun"):
		event_stream.publish(&"ActionStunned", engine.state.round_index, {"unit_id":str(actor.id)})
		return
	var intent := engine.state.actions.get(actor.id) as ActionIntentV2
	if intent == null or intent.cancelled or intent.pass_action:
		event_stream.publish(&"ActionPassed", engine.state.round_index, {"unit_id": str(actor.id)})
		return
	if not actor.alive:
		return
	var card := _find_card(actor, intent.card_instance_id)
	if card == null or card.definition == null:
		event_stream.publish(&"ActionFizzled", engine.state.round_index, {"unit_id": str(actor.id), "reason": "card_missing"})
		return
	var targets := target_resolver.resolve_selected(engine.state, actor, card.definition, intent.target_ids)
	if targets.is_empty():
		event_stream.publish(&"ActionFizzled", engine.state.round_index, {"unit_id": str(actor.id), "card_id": str(card.card_id()), "reason": "target_unavailable"})
		return
	var payment := cost_resolver.resolve_payment(card.definition, actor.resources, actor)
	if not bool(payment.get("valid", false)):
		event_stream.publish(&"ActionFizzled", engine.state.round_index, {"unit_id": str(actor.id), "card_id": str(card.card_id()), "reason": "payment_failed"})
		return
	event_stream.publish(&"SpellCastStarted", engine.state.round_index, {
		"caster_id": str(actor.id), "card_id": str(card.card_id()),
		"target_ids": targets.map(func(unit): return str((unit as BattleUnitStateV2).id))
	})
	var accuracy_bonus := _consume_accuracy_modifiers(engine, actor, card.definition.school_id)
	if engine.rng.randf() > effective_accuracy(actor, card.definition, accuracy_bonus):
		actor.deck.hand.erase(card)
		actor.deck.draw_pile.push_front(card)
		event_stream.publish(&"SpellMissed", engine.state.round_index, {"caster_id": str(actor.id), "card_id": str(card.card_id()), "returned_to_deck":true})
		event_stream.publish(&"SpellResolved", engine.state.round_index, {"caster_id": str(actor.id), "card_id": str(card.card_id()), "success": false})
		return
	if not cost_resolver.apply_payment_plan(actor, payment):
		event_stream.publish(&"ActionFizzled", engine.state.round_index, {"unit_id": str(actor.id), "card_id": str(card.card_id()), "reason": "payment_changed"})
		return
	_consume_card(actor, card)
	if not card.inventory_token.is_empty():
		event_stream.publish(&"TreasureConsumed",engine.state.round_index,{"unit_id":str(actor.id),"card_id":str(card.card_id()),"token":card.inventory_token})
	event_stream.publish(&"ResourceSpent", engine.state.round_index, {
		"unit_id": str(actor.id), "card_id": str(card.card_id()),
		"pip_count": (payment.pip_indices as Array).size(), "provided_value": int(payment.provided_value),
		"shadow": int(payment.shadow_consumed), "overpay": int(payment.overpay)
	})
	if _consume_matching_status(engine, actor, &"dispel", card.definition.school_id):
		event_stream.publish(&"SpellDispelled", engine.state.round_index, {"caster_id":str(actor.id), "card_id":str(card.card_id()), "school":str(card.definition.school_id)})
		event_stream.publish(&"SpellResolved", engine.state.round_index, {"caster_id":str(actor.id), "card_id":str(card.card_id()), "success":false})
		return
	var caster_status_plans: Dictionary = {}
	# One deterministic roll per cast; target-specific block still affects each hit.
	engine.damage_resolver.cast_roll = engine.rng.randf()
	engine.healing_resolver.cast_roll = engine.damage_resolver.cast_roll
	engine.healing_resolver.cast_school = card.definition.school_id
	for effect: Dictionary in card.definition.effects:
		_execute_effect(engine, actor, card.definition, effect, targets, payment, caster_status_plans)
	engine.damage_resolver.cast_roll = -1.0
	engine.healing_resolver.cast_roll = -1.0
	engine.healing_resolver.cast_school = &"life"
	var consumed_plan_ids: Dictionary = {}
	for plan_value in caster_status_plans.values():
		var plan := plan_value as Dictionary
		for status_id in plan.get("consumed_status_ids", []):
			consumed_plan_ids[int(status_id)] = true
	var ordered_ids: Array[int] = []
	for status: StatusInstanceV2 in StatusQuery.newest_first(actor):
		if consumed_plan_ids.has(status.instance_id):
			ordered_ids.append(status.instance_id)
	status_resolver.apply_consumption_plan(actor, {"consumed_status_ids":ordered_ids}, engine.state.round_index)
	event_stream.publish(&"SpellResolved", engine.state.round_index, {"caster_id": str(actor.id), "card_id": str(card.card_id()), "success": true})


func effective_accuracy(actor: BattleUnitStateV2, card: CardDefinitionV2, status_bonus: float = 0.0) -> float:
	var base := card.accuracy
	# Equipment floors only the wearer's own-school base chance. Status modifiers are
	# applied afterwards, so a blind/weakness still lowers an equipped 100% floor.
	if card.school_id == actor.school_id:
		base = maxf(base, actor.school_stat(&"accuracy_floor", card.school_id))
	return clampf(base + status_bonus / 100.0, 0.0, 1.0)


func _execute_effect(engine, actor: BattleUnitStateV2, card: CardDefinitionV2, effect: Dictionary, primary_targets: Array[BattleUnitStateV2], payment: Dictionary, caster_status_plans: Dictionary) -> void:
	var type := StringName(str(effect.get("type", "")))
	if type == &"conditional":
		_execute_conditional(engine, actor, card, effect, primary_targets, payment, caster_status_plans)
		return
	if type == &"convert_status":
		_execute_conversion(engine, actor, card, effect, primary_targets, payment, caster_status_plans)
		return
	var effect_targets := target_resolver.resolve_effect_targets(engine.state, actor, effect, primary_targets, engine.rng)
	if effect_targets.is_empty():
		event_stream.publish(&"EffectRejected", engine.state.round_index, {"card_id":str(card.id), "effect_type":str(type), "reason":"no_effect_target"})
		return
	var effect_school := StringName(str(effect.get("school", card.school_id)))
	var outgoing_multiplier := 1.0
	if type in [&"damage", &"drain", &"apply_dot", &"delay_damage"]:
		var key := str(effect_school)
		if not caster_status_plans.has(key):
			var kinds: Array[StringName] = [&"blade", &"weakness"]
			caster_status_plans[key] = status_resolver.resolve_multiplier_plan(actor, kinds, effect_school)
		outgoing_multiplier = float((caster_status_plans[key] as Dictionary).multiplier)
	if type in [&"heal", &"apply_hot"]:
		if not caster_status_plans.has("healing"):
			caster_status_plans["healing"]=status_resolver.resolve_multiplier_plan(actor,[&"healing_blade",&"infection"],&"*")
		outgoing_multiplier=float(caster_status_plans.healing.multiplier)
	for target in effect_targets:
		var context := {
			"engine":engine, "action_resolver":self, "caster":actor, "target":target,
			"card":card, "effect":effect, "primary_targets":primary_targets,
			"payment_value":int(payment.get("provided_value", 0)),
			"outgoing_multiplier":outgoing_multiplier
		}
		if not effect_registry.execute(type, context):
			event_stream.publish(&"EffectRejected", engine.state.round_index, {"card_id":str(card.id), "effect_type":str(type)})


func _condition_matches(_engine, actor: BattleUnitStateV2, condition: Dictionary, primary_targets: Array[BattleUnitStateV2]) -> bool:
	var target: BattleUnitStateV2 = primary_targets[0] if not primary_targets.is_empty() else null
	return Conditions.matches(actor, target, condition)


func _execute_conditional(engine, actor: BattleUnitStateV2, card: CardDefinitionV2, effect: Dictionary, primary_targets: Array[BattleUnitStateV2], payment: Dictionary, plans: Dictionary) -> void:
	var targets := target_resolver.resolve_effect_targets(engine.state, actor, effect, primary_targets, engine.rng)
	var once := str(effect.get("scope", "per_target")) == "once"
	var branches: Array[Dictionary] = []
	# Snapshot all decisions before any branch consumes or creates state.
	for target in targets:
		var scoped: Array[BattleUnitStateV2] = [target]
		var passed := _condition_matches(engine, actor, effect.get("condition", {}) as Dictionary, scoped)
		branches.append({"target":target, "passed":passed})
		if once:
			break
	for branch in branches:
		var scoped: Array[BattleUnitStateV2] = []
		if once:
			scoped.assign(targets)
		else:
			scoped.append(branch.target)
		engine.event_stream.publish(&"ConditionEvaluated", engine.state.round_index, {
			"caster_id":str(actor.id), "target_id":str(branch.target.id), "card_id":str(card.id), "passed":branch.passed
		})
		for nested in effect.get("then" if branch.passed else "else", []):
			_execute_effect(engine, actor, card, nested as Dictionary, scoped, payment, plans)


func _execute_conversion(engine, actor: BattleUnitStateV2, card: CardDefinitionV2, effect: Dictionary, primary_targets: Array[BattleUnitStateV2], payment: Dictionary, plans: Dictionary) -> void:
	var targets := target_resolver.resolve_effect_targets(engine.state, actor, effect, primary_targets, engine.rng)
	var criteria := StatusQuery.criteria_from(effect)
	var limit := int(effect.get("count", 1))
	var minimum := maxi(0, int(effect.get("minimum", 0)))
	var conversions: Array[Dictionary] = []
	# Remove all inputs first: newly generated states can never become inputs to this conversion.
	for target in targets:
		var available := StatusQuery.select(target, criteria).size()
		var removable := available if limit < 0 else mini(available, limit)
		if removable < minimum:
			continue
		var removed: Array = engine.remove_statuses(target.id, criteria, limit, &"converted")
		conversions.append({"target":target, "removed":removed})
	for conversion in conversions:
		var scoped: Array[BattleUnitStateV2] = [conversion.target]
		var removed: Array = conversion.removed
		for _status in removed:
			for nested in effect.get("per_status", []):
				_execute_effect(engine, actor, card, nested as Dictionary, scoped, payment, plans)
		engine.event_stream.publish(&"StatusConverted", engine.state.round_index, {
			"caster_id":str(actor.id), "target_id":str(conversion.target.id), "card_id":str(card.id),
			"count":removed.size(), "status_ids":removed.map(func(status): return status.instance_id)
		})


func _consume_control_status(engine, unit: BattleUnitStateV2, kind: StringName) -> bool:
	for status: StatusInstanceV2 in StatusQuery.newest_first(unit):
		if status.kind == kind:
			if status.ticks > 1:
				status.ticks -= 1
			else:
				unit.statuses.erase(status)
			event_stream.publish(&"StatusConsumed", engine.state.round_index, {"unit_id":str(unit.id), "status_id":status.instance_id, "kind":str(kind)})
			return true
	return false


func _consume_matching_status(engine, unit: BattleUnitStateV2, kind: StringName, school_id: StringName) -> bool:
	for status: StatusInstanceV2 in StatusQuery.newest_first(unit):
		if status.kind == kind and status.matches_school(school_id):
			unit.statuses.erase(status)
			event_stream.publish(&"StatusConsumed", engine.state.round_index, {"unit_id":str(unit.id), "status_id":status.instance_id, "kind":str(kind)})
			return true
	return false


func _consume_accuracy_modifiers(engine, unit: BattleUnitStateV2, school_id: StringName) -> float:
	var total := 0.0
	var statuses: Array[StatusInstanceV2] = StatusQuery.newest_first(unit)
	for status: StatusInstanceV2 in statuses:
		if status.kind in [&"accuracy_blade", &"accuracy_weakness"] and status.matches_school(school_id):
			total += status.value
			unit.statuses.erase(status)
			event_stream.publish(&"StatusConsumed", engine.state.round_index, {"unit_id":str(unit.id), "status_id":status.instance_id, "kind":str(status.kind)})
	return total


func _find_card(unit: BattleUnitStateV2, instance_id: int) -> CardInstanceV2:
	for card in unit.deck.hand:
		if card.instance_id == instance_id:
			return card
	return null


func _consume_card(unit: BattleUnitStateV2, card: CardInstanceV2) -> void:
	unit.deck.hand.erase(card)
	if card.definition.treasure or card.equipment:
		unit.deck.removed_cards.append(card)
	else:
		unit.deck.discard_pile.append(card)


func _has_offensive_effect(card: CardDefinitionV2) -> bool:
	for effect: Dictionary in card.effects:
		if StringName(str(effect.get("type", ""))) in [&"damage", &"apply_dot", &"delay_damage"]:
			return true
	return false

