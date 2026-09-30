class_name TurnManagerV2
extends RefCounted


func resolution_order(state: BattleStateV2) -> Array[BattleUnitStateV2]:
	if state.pvp:return state.team_units(state.active_team)
	var team_zero := state.team_units(0)
	var team_one := state.team_units(1)
	var result: Array[BattleUnitStateV2] = []
	# Alternate occupied slots, then retain the larger team's remaining turns.
	# Keep dead slots here: the resolver handles death/revival without shifting order.
	for index in maxi(team_zero.size(), team_one.size()):
		if state.round_index % 2 == 1:
			if index < team_zero.size():result.append(team_zero[index])
			if index < team_one.size():result.append(team_one[index])
		else:
			if index < team_one.size():result.append(team_one[index])
			if index < team_zero.size():result.append(team_zero[index])
	return result
