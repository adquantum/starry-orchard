extends RefCounted

const BASE_PATH := "res://resources/fusion_3d/frost_encounter_progression.json"
const CIRCLED_PATH := "res://resources/fusion_3d/frost_circled_encounters.json"

static func all_sites() -> Array:
	var base_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(BASE_PATH))
	var circled_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CIRCLED_PATH))
	var base: Array = base_value if base_value is Array else []
	var circled: Array = circled_value if circled_value is Array else []
	var result: Array = base.duplicate(true)
	var templates: Dictionary = {}
	for definition in base:
		templates[int(definition.order)] = definition
	for addition in circled:
		var template_order := int(addition.get("template_order", 0))
		if not templates.has(template_order):
			push_error("Missing Frost encounter template order %d for %s" % [template_order, addition.get("id", "unknown")])
			continue
		var definition: Dictionary = templates[template_order].duplicate(true)
		for key in addition:
			if key != "template_order":
				definition[key] = addition[key]
		for index in definition.enemies.size():
			definition.enemies[index].id = "%s_%d" % [definition.id, index]
		result.append(definition)
	# Apply PvP after copying templates: field additions that reuse tier six remain PvE.
	for definition in result:
		if str(definition.id)=="frost_pvp_01":
			definition.merge({"name":"红蓝 PVP 法阵", "pvp":true, "red_axis":[0,0,1], "encounter":"frost_pvp", "enemies":[]},true)
	# One authored route drives map destinations and quest guidance. Keep order
	# unchanged: it is also the legacy template key used by the reward ledger.
	result.sort_custom(func(a: Dictionary,b: Dictionary)->bool:
		return int(a.get("challenge_order",999)) < int(b.get("challenge_order",999)))
	return result
