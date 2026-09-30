class_name StatusResolverV2
extends RefCounted

const StatusQuery = preload("res://scripts/battle_v2/core/status_query_v2.gd")

var event_stream: BattleEventStreamV2


func resolve_damage_wards(unit: BattleUnitStateV2, school: StringName, amount: float, pierce: float, round_index: int, origin: StringName) -> Dictionary:
	var used_sources: Dictionary = {}
	var absorbed := 0.0
	var multiplier := 1.0
	# One ordered traversal: never reconsider a skipped ward after a prism.
	for status: StatusInstanceV2 in StatusQuery.newest_first(unit):
		if status.kind not in [&"prism", &"shield", &"trap", &"absorb"] or not status.matches_school(school) or not _matches_origin(status, origin):continue
		if status.kind == &"prism":
			var converted := StringName(str(status.payload.get("to_school", school)))
			unit.statuses.erase(status)
			event_stream.publish(&"PrismConsumed", round_index, {"unit_id":str(unit.id),"status_id":status.instance_id,"from_school":str(school),"to_school":str(converted)})
			school = converted
			continue
		if status.kind == &"absorb":
			var used := minf(maxf(0.0, amount), maxf(0.0, status.value))
			amount -= used
			absorbed += used
			status.value -= used
			event_stream.publish(&"AbsorbTriggered", round_index, {"unit_id":str(unit.id),"status_id":status.instance_id,"absorbed":roundi(used),"remaining_capacity":maxi(0,roundi(status.value))})
			if status.value <= 0.0:unit.statuses.erase(status)
			continue
		var group := status.source_group if status.source_group != &"" else status.source_id
		var key := "%s:%s" % [status.kind, group]
		if used_sources.has(key):continue
		used_sources[key] = true
		var value := status.value
		if status.kind == &"shield" and value < 0.0:
			var spent := minf(pierce, -value)
			pierce -= spent
			value += spent
		var factor := maxf(0.0, 1.0 + value / 100.0)
		amount *= factor
		multiplier *= factor
		apply_consumption_plan(unit, {"consumed_status_ids":[status.instance_id]}, round_index)
	return {"amount":amount,"school":school,"pierce":pierce,"absorbed":roundi(absorbed),"multiplier":multiplier}


func consume_multiplier(unit: BattleUnitStateV2, kinds: Array[StringName], school_id: StringName, round_index: int, origin: StringName = &"spell") -> float:
	var plan := resolve_multiplier_plan(unit, kinds, school_id, origin)
	apply_consumption_plan(unit, plan, round_index)
	return float(plan.multiplier)


func resolve_multiplier_plan(unit: BattleUnitStateV2, kinds: Array[StringName], school_id: StringName, origin: StringName = &"spell") -> Dictionary:
	var multiplier := 1.0
	var used_sources: Dictionary = {}
	var consumed_ids: Array[int] = []
	for status in StatusQuery.newest_first(unit):
		if status.kind not in kinds or not status.matches_school(school_id) or not _matches_origin(status, origin):
			continue
		var group := status.source_group if status.source_group != &"" else status.source_id
		# Duplicate instances of the same status kind/source only trigger once.
		# Different kinds (for example Shield + Trap) multiply even when one card supplied both.
		var trigger_key := "%s:%s" % [str(status.kind), str(group)]
		if used_sources.has(trigger_key):
			continue
		used_sources[trigger_key] = true
		multiplier *= 1.0 + status.value / 100.0
		consumed_ids.append(status.instance_id)
	return {"multiplier":multiplier, "consumed_status_ids":consumed_ids, "school":str(school_id)}


func consume_prism(unit: BattleUnitStateV2, school_id: StringName, round_index: int) -> StringName:
	for status: StatusInstanceV2 in StatusQuery.newest_first(unit):
		if status.kind != &"prism" or not status.matches_school(school_id):
			continue
		var converted := StringName(str(status.payload.get("to_school", school_id)))
		unit.statuses.erase(status)
		event_stream.publish(&"PrismConsumed", round_index, {
			"unit_id":str(unit.id), "status_id":status.instance_id,
			"from_school":str(school_id), "to_school":str(converted)
		})
		return converted
	return school_id


func absorb_damage(unit: BattleUnitStateV2, school_id: StringName, amount: int, round_index: int, origin: StringName = &"spell") -> Dictionary:
	var remaining := amount
	var absorbed := 0
	var statuses: Array[StatusInstanceV2] = StatusQuery.newest_first(unit)
	for status: StatusInstanceV2 in statuses:
		if remaining <= 0:
			break
		if status.kind != &"absorb" or not status.matches_school(school_id) or not _matches_origin(status, origin):
			continue
		var available := maxi(0, int(roundi(status.value)))
		var used := mini(available, remaining)
		remaining -= used
		absorbed += used
		status.value -= used
		event_stream.publish(&"AbsorbTriggered", round_index, {
			"unit_id":str(unit.id), "status_id":status.instance_id,
			"absorbed":used, "remaining_capacity":maxi(0, roundi(status.value))
		})
		if status.value <= 0.0:
			unit.statuses.erase(status)
	return {"remaining":remaining, "absorbed":absorbed}


func _matches_origin(status: StatusInstanceV2, origin: StringName) -> bool:
	var allowed: Array = status.payload.get("origins", []) as Array
	if not allowed.is_empty() and not allowed.has(str(origin)) and not allowed.has(origin):
		return false
	var excluded: Array = status.payload.get("exclude_origins", []) as Array
	return not excluded.has(str(origin)) and not excluded.has(origin)


func stat_bonus(unit: BattleUnitStateV2, stat_id: StringName, school_id: StringName) -> float:
	var result := 0.0
	for status: StatusInstanceV2 in unit.statuses:
		if status.kind not in [&"aura", &"stat_modifier"]:
			continue
		if stat_id != &"extra_power_pip_chance" and not status.matches_school(school_id):
			continue
		var modifiers := status.payload.get("modifiers", {}) as Dictionary
		result += float(modifiers.get(str(stat_id), modifiers.get(stat_id, 0.0)))
	return result


func global_multiplier(state: BattleStateV2, stat_id: StringName, school_id: StringName, team: int) -> float:
	var multiplier := 1.0
	for status: StatusInstanceV2 in state.global_statuses:
		if not status.matches_school(school_id):
			continue
		var affected_team := int(status.payload.get("team", -1))
		if affected_team >= 0 and affected_team != team:
			continue
		var modifiers := status.payload.get("modifiers", {}) as Dictionary
		multiplier *= 1.0 + float(modifiers.get(str(stat_id), modifiers.get(stat_id, 0.0))) / 100.0
	return multiplier


func apply_consumption_plan(unit: BattleUnitStateV2, plan: Dictionary, round_index: int) -> void:
	var consumed_ids := plan.get("consumed_status_ids", []) as Array
	for status_id in consumed_ids:
		var status := _status_by_instance_id(unit, int(status_id))
		if status == null:
			continue
		unit.statuses.erase(status)
		event_stream.publish(&"StatusConsumed", round_index, {
			"unit_id": str(unit.id), "status_id": status.instance_id, "definition_id": str(status.definition_id),
			"kind": str(status.kind), "source_id": str(status.source_id), "value": status.value
		})


func _status_by_instance_id(unit: BattleUnitStateV2, instance_id: int) -> StatusInstanceV2:
	for status: StatusInstanceV2 in unit.statuses:
		if status.instance_id == instance_id:
			return status
	return null


func process_round_start(engine) -> void:
	_process_global_durations(engine)


func process_action_end(engine, unit: BattleUnitStateV2) -> void:
	for status: StatusInstanceV2 in unit.statuses.duplicate():
		if status.kind != &"aura" or status.ticks <= 0:
			continue
		# Casting round is free; only this target's subsequent turns consume time.
		if int(status.payload.get("applied_round", -1)) == engine.state.round_index:
			continue
		if int(status.payload.get("last_tick_round", -1)) == engine.state.round_index:
			continue
		status.payload["last_tick_round"] = engine.state.round_index
		status.ticks -= 1
		event_stream.publish(&"AuraTicked", engine.state.round_index, {"unit_id":str(unit.id), "status_id":status.instance_id, "ticks_left":status.ticks})
		if status.ticks == 0:
			unit.statuses.erase(status)
			event_stream.publish(&"StatusExpired", engine.state.round_index, {"unit_id":str(unit.id), "status_id":status.instance_id, "kind":"aura"})


func process_action_start(engine, unit: BattleUnitStateV2) -> void:
	if unit == null or not unit.alive:
		return
	# Status ids are monotonic, so sorting guarantees first-applied-first-resolved.
	var timed: Array[StatusInstanceV2] = unit.statuses.duplicate()
	timed.sort_custom(func(a: StatusInstanceV2, b: StatusInstanceV2): return a.instance_id < b.instance_id)
	for status: StatusInstanceV2 in timed:
		if not unit.alive:
			break
		if not unit.statuses.has(status):
			continue
		var timed_status := true
		match status.kind:
			&"dot":
				engine.resolve_damage(status.caster_id, unit.id, status.school_filter, int(status.payload.get("amount", 0)), float(status.payload.get("outgoing_multiplier",1.0)), &"dot", status.payload.get("source_snapshot",{}))
				status.ticks -= 1
				event_stream.publish(&"DotTicked", engine.state.round_index, {"target_id": str(unit.id), "status_id": status.instance_id, "ticks_left": status.ticks})
			&"hot":
				engine.resolve_healing(status.caster_id, unit.id, int(status.payload.get("amount", 0)), 1.0, &"hot")
				status.ticks -= 1
				event_stream.publish(&"HotTicked", engine.state.round_index, {"target_id": str(unit.id), "status_id": status.instance_id, "ticks_left": status.ticks})
			&"delay_damage":
				status.ticks -= 1
				if status.ticks <= 0:
					var dealt: int = int(engine.resolve_damage(status.caster_id, unit.id, status.school_filter, int(status.payload.get("amount", 0)), float(status.payload.get("outgoing_multiplier",1.0)), &"delay_damage", status.payload.get("source_snapshot",{})))
					if status.payload.has("heal_ratio"):
						var healing := roundi(dealt * float(status.payload.heal_ratio))
						engine.resolve_healing(status.caster_id, status.caster_id, healing, 1.0, &"delay_drain")
			&"aura", &"stun_block":
				if status.kind == &"aura":
					timed_status = false
				elif status.ticks > 0:
					status.ticks -= 1
				else:
					timed_status = false
			_:
				timed_status = false
		if timed_status and (status.ticks <= 0 or not unit.alive):
			unit.statuses.erase(status)
			event_stream.publish(&"StatusExpired", engine.state.round_index, {
				"unit_id": str(unit.id), "status_id": status.instance_id, "kind": str(status.kind)
			})

func _process_global_durations(engine) -> void:
	var statuses: Array[StatusInstanceV2] = engine.state.global_statuses.duplicate()
	for status: StatusInstanceV2 in statuses:
		if status.ticks <= 0:
			continue
		status.ticks -= 1
		if status.ticks <= 0:
			engine.state.global_statuses.erase(status)
			event_stream.publish(&"GlobalExpired", engine.state.round_index, {"status_id":status.instance_id})
