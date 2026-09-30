extends RefCounted
## Provenance, proposed use and animation readiness are intentionally independent.
static var catalog: Dictionary = {}
static func data() -> Dictionary:
	if catalog.is_empty():
		var path: String = "res://resources/fusion_3d/mobile_lite/character_library.json" if OS.has_feature("mobile_lite") else "res://resources/fusion_3d/character_library.json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				catalog = parsed
	return catalog

static func entry(id: String) -> Dictionary:
	return data().get("entries", {}).get(id, {})

static func model_path(id: String) -> String:
	return str(entry(id).get("model", ""))

static func action_clips(id: String, role: String) -> Array:
	return entry(id).get("action_map", {}).get(role, [])

static func matches(item: Dictionary, filters: Dictionary) -> bool:
	for key in ["source_type", "source_region", "usage_category", "family_key"]:
		var value: String = str(filters.get(key, "all"))
		if value != "all" and str(item.get(key, "")) != value:
			return false
	var readiness: String = str(filters.get("readiness", "all"))
	if readiness != "all" and str(item.get("animation_audit", {}).get("readiness", "unavailable")) != readiness:
		return false
	var review: String = str(filters.get("review", "all"))
	if review != "all" and str(item.get("review_status", "needs_review")) != review:
		return false
	if bool(filters.get("hide_lod", false)) and bool(item.get("is_lod", false)):
		return false
	var query: String = str(filters.get("search", "")).strip_edges().to_lower()
	if not query.is_empty():
		var text: String = ""
		for key in ["id", "name", "source", "original", "source_type_label", "source_region_label", "family_name", "usage_category_label", "source_version", "variant_name"]:
			text += " " + str(item.get(key, ""))
		for label in item.get("review_labels", []):
			text += " " + str(label)
		text += " " + str(item.get("animation_audit", {}).get("readiness_label", ""))
		# Every whitespace-separated token must match; source and region terms combine.
		for token in query.split(" ", false):
			if not text.to_lower().contains(token):
				return false
	return true

static func query(filters: Dictionary = {}) -> Array:
	var result: Array = []
	for item in data().get("entries", {}).values():
		if matches(item, filters):
			result.append(item)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (str(a.get("family_key", "")) + "/" + str(a.get("id", ""))) < (str(b.get("family_key", "")) + "/" + str(b.get("id", ""))))
	return result
