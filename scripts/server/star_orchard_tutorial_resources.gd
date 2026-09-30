extends ResourceResolverV2
## Lesson-only predictable resource generation. Ordinary encounters keep their resolver.
var lesson := 1

func _generate_main_pip(state: BattleStateV2, unit: BattleUnitStateV2, _top_archmastery: int) -> void:
	var kind := ResourceStateV2.PipKind.POWER if unit.team == 0 and ((lesson == 2 and state.round_index == 2) or (lesson == 5 and state.round_index in [2,6])) else ResourceStateV2.PipKind.NORMAL
	unit.resources.append_pip(kind)
	event_stream.publish(&"ResourceGenerated", state.round_index, {"unit_id": str(unit.id), "resource": "power" if kind == ResourceStateV2.PipKind.POWER else "normal", "charge_school": str(unit.school_id), "charge": 0})
