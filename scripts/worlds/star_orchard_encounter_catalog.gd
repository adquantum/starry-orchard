extends RefCounted
## Independent Star Orchard encounter data. World placement and quest state stay outside this catalog.
const DATA_PATH := "res://resources/fusion_3d/star_orchard_encounters.json"
const MAIN_ISLANDS := ["orchard_start", "orchard_grove", "orchard_guard", "orchard_frost", "orchard_wind", "orchard_trial", "orchard_return", "orchard_temple"]

static func all_encounters() -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary or not parsed.get("encounters") is Array:
		push_error("Invalid Star Orchard encounter catalog: " + DATA_PATH)
		return []
	var result: Array[Dictionary] = []
	for value in parsed.encounters:
		if value is Dictionary: result.append(value.duplicate(true))
	return result

static func get_encounter(encounter_id: String) -> Dictionary:
	for definition in all_encounters():
		if str(definition.get("id", "")) == encounter_id: return definition
	return {}

static func main_encounters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in all_encounters():
		if str(definition.get("track", "")) == "main": result.append(definition)
	return result

static func school_encounters(school: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in all_encounters():
		if str(definition.get("track", "")) == "school" and (school.is_empty() or str(definition.get("school", "")) == school):
			result.append(definition)
	return result

## Anchor supplies world coordinates. Returns the site shape expected by IslandBattleSession.
## Use the returned encounter id and enemy spec on both client and authority.
static func site_for_anchor(encounter_id: String, anchor: Dictionary) -> Dictionary:
	var definition := get_encounter(encounter_id)
	if definition.is_empty() or not anchor.get("center") is Array or not anchor.get("approach") is Array:
		return {}
	if anchor.center.size() != 3 or anchor.approach.size() != 3: return {}
	var site: Dictionary = definition.duplicate(true)
	site["encounter"] = encounter_id
	site["center"] = anchor.center.duplicate()
	site["approach"] = anchor.approach.duplicate()
	site["scale"] = float(anchor.get("scale", 2.0))
	site["radius"] = float(anchor.get("radius", 16.6))
	site["cooldown_seconds"] = float(anchor.get("cooldown_seconds", 20.0))
	if anchor.has("battle_height_offset"): site["battle_height_offset"] = float(anchor.battle_height_offset)
	return site

## BattleStage or FusionEngine should receive this in encounter_spec.
static func battle_spec(encounter_id: String) -> Dictionary:
	var definition := get_encounter(encounter_id)
	if definition.is_empty(): return {}
	return {"enemies": definition.enemies.duplicate(true)}
