class_name AIPolicyV2
extends RefCounted


func choose_action(_engine: BattleEngineV2, unit: BattleUnitStateV2) -> ActionIntentV2:
	return ActionIntentV2.pass_turn(unit.id)
