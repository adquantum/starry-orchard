class_name ScenarioFactoryV2
extends RefCounted


func default_scenario(content: ContentRegistryV2) -> Dictionary:
	return content.scenario(&"basic_4v4")


func with_character(scenario: Dictionary, team: int, slot: int, character_id: StringName) -> Dictionary:
	var result := scenario.duplicate(true)
	var teams := result.get("teams", []) as Array
	if team >= 0 and team < teams.size() and slot >= 0 and slot < (teams[team] as Array).size():
		(teams[team] as Array)[slot] = str(character_id)
	return result
