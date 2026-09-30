extends BattleEngineV2
## Demo-only time limit: retain finite decks while guaranteeing an end to stalemates.
const ROUND_LIMIT := 30
func start_next_round() -> bool:
	if state.phase == BattleStateV2.Phase.FINISHED:
		return false
	if state.round_index >= ROUND_LIMIT:
		var health: Array[float] = [0.0,0.0]
		for unit in state.units:
			health[unit.team] += float(unit.hp) / float(unit.max_hp)
		state.winner_team = -1 if is_equal_approx(health[0],health[1]) else (0 if health[0] > health[1] else 1)
		state.phase = BattleStateV2.Phase.FINISHED
		event_stream.publish(&"BattleFinished",state.round_index,{"winner_team":state.winner_team,"reason":"round_limit","health_ratios":health})
		return false
	return super.start_next_round()
