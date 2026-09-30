class_name HealingResolverV2
extends RefCounted
const CriticalRules = preload("res://scripts/battle_v2/core/critical_rules_v2.gd")
var rng: RandomNumberGenerator
var cast_roll := -1.0
var cast_school: StringName = &"life"

var event_stream: BattleEventStreamV2
var status_resolver: StatusResolverV2


func resolve(state: BattleStateV2, event: HealingEventV2, apply_charms:bool=true) -> int:
	var target := state.unit_by_id(event.target_id)
	if target == null:
		return 0
	var source := state.unit_by_id(event.source_id)
	if not target.alive and (event.origin != &"spell" or source == null or source.team != target.team):
		return 0
	var source_bonus := source.school_stat(&"outgoing_heal") + status_resolver.stat_bonus(source, &"outgoing_heal", &"*") if source != null else 0.0
	var target_bonus := target.school_stat(&"incoming_heal") + status_resolver.stat_bonus(target, &"incoming_heal", &"*")
	var source_team := source.team if source != null else -1
	# Drains and periodic ticks must not roll healing criticals again.
	if source != null and event.origin == &"spell":
		var rating := source.school_stat(&"critical", cast_school) + status_resolver.stat_bonus(source, &"critical", cast_school)
		var roll := cast_roll if cast_roll >= 0.0 else (rng.randf() if rng != null else 1.0)
		var critical := CriticalRules.evaluate(rating, 0.0, roll)
		event.critical = bool(critical.critical)
		event.critical_multiplier = float(critical.multiplier)
	var global_outgoing := status_resolver.global_multiplier(state, &"outgoing_heal", &"*", source_team)
	var global_incoming := status_resolver.global_multiplier(state, &"incoming_heal", &"*", target.team)
	var charm_plan := status_resolver.resolve_multiplier_plan(source, [&"healing_blade", &"infection"], &"*") if source != null and apply_charms and event.origin==&"spell" else {"multiplier":1.0, "consumed_status_ids":[]}
	var requested := maxi(0, roundi(
		event.base_amount * event.outgoing_multiplier * event.incoming_multiplier * event.critical_multiplier *
		(1.0 + source_bonus / 100.0) * (1.0 + target_bonus / 100.0) *
		float(charm_plan.multiplier) * global_outgoing * global_incoming
	))
	if source != null:
		status_resolver.apply_consumption_plan(source, charm_plan, state.round_index)
	event.final_amount = mini(requested, target.max_hp - target.hp)
	var hp_before := target.hp
	if not target.alive:
		if event.final_amount <= 0:
			return 0
		var revival := DeathResolverV2.new()
		revival.event_stream = event_stream
		revival.revive(state, target, event.final_amount)
	else:
		target.hp += event.final_amount
	var payload := event.to_dict()
	payload["hp_before"] = hp_before
	payload["hp_after"] = target.hp
	event_stream.publish(&"HealingResolved", state.round_index, payload)
	return event.final_amount
