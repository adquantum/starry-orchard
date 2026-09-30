extends Node

var encounter_id: StringName = &""
var selected_team: Array[StringName] = []
var charge_schools: Dictionary = {}
var launch_pending := false


func configure(p_encounter_id: StringName, p_team: Array[StringName], p_charge_schools: Dictionary = {}) -> void:
	encounter_id = p_encounter_id
	selected_team.assign(p_team)
	charge_schools = p_charge_schools.duplicate(true)
	launch_pending = true


func has_launch() -> bool:
	return launch_pending and not encounter_id.is_empty() and not selected_team.is_empty()


func consume_launch() -> Dictionary:
	var result := {
		"encounter_id": encounter_id,
		"selected_team": selected_team.duplicate(),
		"charge_schools": charge_schools.duplicate(true),
	}
	launch_pending = false
	return result


func clear() -> void:
	encounter_id = &""
	selected_team.clear()
	charge_schools.clear()
	launch_pending = false
