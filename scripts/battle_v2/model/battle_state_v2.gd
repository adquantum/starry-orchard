class_name BattleStateV2
extends RefCounted

enum Phase { SETUP, PLANNING, RESOLVING, FINISHED }

var units: Array[BattleUnitStateV2] = []
var pvp: bool = false
var first_team: int = 0
var active_team: int = 0
var round_index: int = 0
var phase: Phase = Phase.SETUP
var winner_team: int = -1
var actions: Dictionary = {}
var global_statuses: Array[StatusInstanceV2] = []


func unit_by_id(unit_id: StringName) -> BattleUnitStateV2:
	for unit in units:
		if unit.id == unit_id:
			return unit
	return null


func team_units(team: int) -> Array[BattleUnitStateV2]:
	var result: Array[BattleUnitStateV2] = []
	for unit in units:
		if unit.team == team:
			result.append(unit)
	result.sort_custom(func(a, b): return a.slot < b.slot)
	return result


func living_units(team: int = -1) -> Array[BattleUnitStateV2]:
	var result: Array[BattleUnitStateV2] = []
	for unit in units:
		if unit.alive and (team < 0 or unit.team == team):
			result.append(unit)
	return result


func snapshot() -> Dictionary:
	return {
		"round": round_index, "phase": Phase.keys()[phase], "winner_team": winner_team,
		"units": units.map(func(unit): return (unit as BattleUnitStateV2).snapshot()),
		"global_statuses": global_statuses.map(func(status): return (status as StatusInstanceV2).to_dict())
	}
