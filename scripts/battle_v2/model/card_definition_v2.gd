class_name CardDefinitionV2
extends RefCounted

var id: StringName
var name_key: StringName
var school_id: StringName
var target_type: StringName
var pip_cost: int
var x_pip: bool = false
var minimum_pip_cost: int = 0
var required_school_pips: int
var school_pip_requirements: Dictionary = {}
var shadow_cost: int
var accuracy: float
var learned: bool
var treasure: bool
var enemy_only: bool
var tags: Array[StringName] = []
var keywords: Array[StringName] = []
var effects: Array[Dictionary] = []
var art_path: String
var presentation: Dictionary = {}


static func from_dict(data: Dictionary) -> CardDefinitionV2:
	var result := CardDefinitionV2.new()
	result.id = StringName(str(data.get("id", "unknown")))
	result.name_key = StringName(str(data.get("name_key", "CARD_%s_NAME" % str(result.id).to_upper())))
	result.school_id = StringName(str(data.get("school", "fire")))
	result.target_type = StringName(str(data.get("target", "enemy")))
	var raw_cost: Variant = data.get("pip_cost", data.get("cost", 0))
	result.x_pip = str(raw_cost).to_upper() == "X" or bool(data.get("x_pip", false))
	result.pip_cost = int(data.get("minimum_pip_cost", 0)) if result.x_pip else int(raw_cost)
	result.minimum_pip_cost = int(data.get("minimum_pip_cost", result.pip_cost))
	result.required_school_pips = int(data.get("school_pips", 0))
	result.school_pip_requirements = (data.get("school_pip_requirements", {}) as Dictionary).duplicate(true)
	if result.school_pip_requirements.is_empty() and result.required_school_pips > 0:
		result.school_pip_requirements[str(result.school_id)] = result.required_school_pips
	result.shadow_cost = int(data.get("shadow_cost", 0))
	result.accuracy = float(data.get("accuracy", 1.0))
	result.learned = bool(data.get("learned", not bool(data.get("treasure", false))))
	result.treasure = bool(data.get("treasure", false))
	result.enemy_only = bool(data.get("enemy_only", false))
	result.art_path = str(data.get("art_path", ""))
	result.presentation = (data.get("presentation", {}) as Dictionary).duplicate(true)
	for tag in data.get("tags", []):
		result.tags.append(StringName(str(tag)))
	for keyword in data.get("keywords", []):
		result.keywords.append(StringName(str(keyword)))
	for effect in data.get("effects", []):
		result.effects.append((effect as Dictionary).duplicate(true))
	return result


func cost_label() -> String:
	return "X" if x_pip else str(pip_cost)


func school_requirement_label() -> String:
	var parts: Array[String] = []
	for school_key in school_pip_requirements:
		parts.append("%d %s" % [int(school_pip_requirements[school_key]), str(school_key).to_upper()])
	return " + ".join(parts)
