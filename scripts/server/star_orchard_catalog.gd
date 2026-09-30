extends RefCounted
## Explicit SO1 catalog; the legacy Frost catalog and its ordering stay intact.
const Tutorial = preload("res://scripts/server/star_orchard_tutorial.gd")
const CAMPAIGN := "star_orchard_world1_v2"
const SERVER_DATA := "res://resources/fusion_3d/star_orchard_world1_server.json"
const ROAMING_IDS := ["SO1_E03", "SO1_E10", "SO1_E12", "SO1_E21", "SO1_W01", "SO1_W02", "SO1_W03", "SO1_W04", "SO1_W05"]

static func all_sites() -> Array:
	var content: Variant = JSON.parse_string(FileAccess.get_file_as_string(SERVER_DATA))
	if not content is Dictionary:
		push_error("SO1 catalog or placements are unavailable")
		return []
	var locations: Dictionary = content.get("battle_sites", {})
	var mappings: Dictionary = content.get("encounter_sites", {})
	var result: Array = []
	for raw in content.get("encounters", []):
		var id := str(raw.get("id", ""))
		var placement: Dictionary = locations.get(str(mappings.get(id, "")), {})
		if not id.begins_with("SO1_") or not _point_valid(placement.get("center")) or not _point_valid(placement.get("approach")):
			push_error("SO1 encounter missing authored arena: " + id)
			return []
		var site: Dictionary = raw.duplicate(true)
		site.merge(placement, true)
		site["id"] = id
		site["encounter"] = id
		site["campaign_id"] = CAMPAIGN
		site["order"] = result.size() + 1
		site["fixed_roam_height"] = true
		site["roam_surface_y"] = float(site.center[1])
		site["battle_height_offset"] = 0.0
		site["cooldown_seconds"] = 20.0
		site["pvp"] = false
		site["requires_explicit_entry"] = true
		if id in ROAMING_IDS:
			site["approach"] = site.center.duplicate()
			site["requires_explicit_entry"] = false
		site["requires_victories"] = prerequisites(id)
		result.append(site)
	# Existing encounter positions keep their collision courts; all wilderness uses T4+ tuning.
	for entry in result:
		if str(entry.id) not in ROAMING_IDS:continue
		entry["recommended_equipment"] = "t4_complete"
		entry["name"] = str(entry.get("label", entry.get("name", "果园"))) + " · 游荡精英"
		for enemy in entry.enemies:
			var school := str(enemy.school)
			enemy.hp = 3800 if school != "ice" else 4600
			enemy.starting_resources = {"normal":1, "power":1}
			enemy.archmastery = 80
			enemy.stats = {"damage":{school:38}, "resistance":{"*":18}, "pierce":{school:6}, "accuracy_floor":{school:0.95}, "extra_power_pip_chance":0.35}
	var wilderness: Array = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/orchard_wilderness.json"))
	for entry in wilderness:
		entry["approach"] = entry.center.duplicate()
		entry.merge({"encounter":str(entry.id), "campaign_id":CAMPAIGN, "order":result.size()+1, "pvp":false, "fixed_roam_height":true, "roam_surface_y":float(entry.center[1]), "battle_height_offset":0.0, "cooldown_seconds":25.0, "requires_explicit_entry":false, "requires_victories":[]})
		result.append(entry)
	result.append_array(Tutorial.all_sites())
	return result

static func _point_valid(value: Variant) -> bool:
	if not value is Array or value.size() != 3:return false
	for n in value:
		if typeof(n) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(n)):return false
	return true

static func prerequisites(id: String) -> Array:
	if Tutorial.is_tutorial(id):
		var n := Tutorial.lesson(id)
		return [] if n == 1 else [Tutorial.IDS[n-2]]
	if id in ROAMING_IDS:return []
	if id == "SO1_E01":return []
	if id in ["SO1_E21", "SO1_E22"]:return ["SO1_E20"]
	if id == "SO1_E23":return ["SO1_E21", "SO1_E22"]
	if id == "SO1_ES02":return ["SO1_E07"]
	if id.begins_with("SO1_ES07_"):return ["SO1_E20"]
	if id == "SO1_E26_CHALLENGE":return ["SO1_E26"]
	if id.length() == 7 and id.begins_with("SO1_E") and id.substr(5).is_valid_int():
		var number := int(id.substr(5))
		if number >= 2 and number <= 26:return ["SO1_E%02d" % (number - 1)]
	return ["invalid_campaign_encounter"]
