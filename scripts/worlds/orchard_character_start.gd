extends RefCounted
## Presentation-only entry policy. Never infer a new character from level or XP.
const ORIGIN := "orchard_west_tutorial_v1"
const MAP := "res://scenes/worlds/star_orchard.tscn"
const ENTRY := Vector3(221.6, 228.0, -343.0)

static func is_new_orchard_character(save: Dictionary) -> bool:
	return str(save.get("fusion_3d_story.json", {}).get("starting_world", "")) == ORIGIN

static func startup_map(save: Dictionary, saved_map: String, maps: Array) -> String:
	# A character's saved destination always wins over their birth place.
	for row in maps:
		if str(row[1]) == saved_map:
			return saved_map
	return MAP if is_new_orchard_character(save) else "frostroarisland_teen"

static func preference_section(server: String, account: String, character: String) -> String:
	return "character_" + JSON.stringify([server, account, character]).sha256_text()
