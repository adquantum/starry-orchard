class_name DeathResolverV2
extends RefCounted

var event_stream: BattleEventStreamV2


func kill(state: BattleStateV2, unit: BattleUnitStateV2) -> void:
	if not unit.alive:
		return
	unit.hp = 0
	unit.alive = false
	unit.statuses.clear()
	unit.resources.clear_on_death()
	unit.deck.clear_hand_on_death()
	if unit.planned_action != null:
		unit.planned_action.cancelled = true
	unit.planned_action = null
	state.actions.erase(unit.id)
	event_stream.publish(&"UnitDied", state.round_index, {"unit_id": str(unit.id), "team": unit.team, "slot": unit.slot})


func revive(state: BattleStateV2, unit: BattleUnitStateV2, amount: int) -> bool:
	if unit.alive:
		return false
	unit.alive = true
	unit.hp = clampi(amount, 1, unit.max_hp)
	unit.statuses.clear()
	unit.resources.clear_on_death()
	unit.deck.hand.clear()
	unit.deck.restore_unplayed_cards_after_revive()
	unit.planned_action = null
	state.actions.erase(unit.id)
	event_stream.publish(&"UnitRevived", state.round_index, {"unit_id": str(unit.id), "hp": unit.hp})
	return true
