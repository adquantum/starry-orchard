class_name DamageResolverV2
extends RefCounted

const CriticalRules = preload("res://scripts/battle_v2/core/critical_rules_v2.gd")
var event_stream: BattleEventStreamV2
var status_resolver: StatusResolverV2
var death_resolver: DeathResolverV2
var rng: RandomNumberGenerator
var cast_roll := -1.0

func snapshot_source(state: BattleStateV2, source_id: StringName, school: StringName) -> Dictionary:
	var source := state.unit_by_id(source_id)
	var result := {"damage":0.0,"flat":0.0,"pierce":0.0,"critical":0.0,"aura":1.0,"global":1.0,"roll":cast_roll}
	if source != null:
		for pair in [["damage", "damage"], ["flat", "flat_damage"], ["pierce", "pierce"], ["critical", "critical"]]:
			result[pair[0]] = source.school_stat(StringName(pair[1]), school) + status_resolver.stat_bonus(source, StringName(pair[1]), school)
		result.aura = maxf(0.0, 1.0 + status_resolver.stat_bonus(source, &"outgoing_damage", school) / 100.0)
		result.global = status_resolver.global_multiplier(state, &"outgoing_damage", school, source.team)
	if float(result.roll) < 0.0:result.roll = rng.randf() if rng != null else 1.0
	return result

func resolve(state: BattleStateV2, event: DamageEventV2) -> int:
	var target := state.unit_by_id(event.target_id)
	if target == null or not target.alive:return 0
	if event.original_school_id == &"":event.original_school_id = event.school_id
	# Source stats use the original school, even when a target prism converts the hit.
	var outgoing := event.source_snapshot if not event.source_snapshot.is_empty() else snapshot_source(state, event.source_id, event.original_school_id)
	event.flat_damage = roundi(float(outgoing.flat))
	event.pierce = maxf(0.0, float(outgoing.pierce))
	event.stat_multiplier = maxf(0.0, 1.0 + float(outgoing.damage) / 100.0)
	var block := target.school_stat(&"block", event.original_school_id) + status_resolver.stat_bonus(target, &"block", event.original_school_id)
	var critical := CriticalRules.evaluate(float(outgoing.critical), block, float(outgoing.roll))
	event.critical = bool(critical.critical)
	event.critical_multiplier = float(critical.multiplier)
	var amount := maxf(0.0, event.base_amount * event.stat_multiplier + event.flat_damage)
	amount *= event.outgoing_multiplier * event.critical_multiplier * float(outgoing.global) * float(outgoing.aura)
	# Pierce is a finite budget: defensive aura, ordered wards, innate resistance.
	var pierce_left := event.pierce
	var aura := status_resolver.stat_bonus(target, &"incoming_damage", event.school_id)
	if aura < 0.0:
		var used := minf(pierce_left, -aura)
		pierce_left -= used
		aura += used
	amount *= maxf(0.0, 1.0 + aura / 100.0)
	amount *= status_resolver.global_multiplier(state, &"incoming_damage", event.school_id, target.team)
	var wards := status_resolver.resolve_damage_wards(target, event.school_id, amount, pierce_left, state.round_index, event.origin)
	event.school_id = wards.school
	event.incoming_multiplier = float(wards.multiplier)
	event.absorbed_amount = int(wards.absorbed)
	var resistance := target.school_stat(&"resistance", event.school_id) + status_resolver.stat_bonus(target, &"resistance", event.school_id)
	# Keep native weakness; excess pierce cannot create extra vulnerability.
	var effective_resistance := maxf(0.0, resistance - float(wards.pierce)) if resistance >= 0.0 else resistance
	event.resistance_multiplier = maxf(0.0, 1.0 - clampf(effective_resistance, -100.0, 100.0) / 100.0)
	event.flat_resistance = roundi(target.school_stat(&"flat_resistance", event.school_id) + status_resolver.stat_bonus(target, &"flat_resistance", event.school_id))
	event.final_amount = maxi(0, roundi(float(wards.amount) * event.resistance_multiplier) - event.flat_resistance)
	var hp_before := target.hp
	target.hp = maxi(0, target.hp - event.final_amount)
	var payload := event.to_dict()
	payload["hp_before"] = hp_before
	payload["hp_after"] = target.hp
	event_stream.publish(&"DamageResolved", state.round_index, payload)
	if target.hp <= 0:death_resolver.kill(state, target)
	return event.final_amount
