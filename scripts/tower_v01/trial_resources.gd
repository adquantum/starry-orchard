extends ResourceResolverV2
var power_rates: Dictionary={}
func _generate_main_pip(state: BattleStateV2, unit: BattleUnitStateV2, _top: int) -> void:
	var kind := ResourceStateV2.PipKind.POWER if rng.randf()<clampf(float(power_rates.get(str(unit.id),0.4)),0,1) else ResourceStateV2.PipKind.NORMAL
	if unit.resources.append_pip(kind):
		event_stream.publish(&"ResourceGenerated",state.round_index,{"unit_id":str(unit.id),"resource":"power" if kind==ResourceStateV2.PipKind.POWER else "normal","origin":"trial_profile"})
