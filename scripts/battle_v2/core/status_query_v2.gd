extends RefCounted
## One predicate for conditions, removal, stealing and Ramp conversions.
const HELPFUL := ["blade", "shield", "hot", "aura", "absorb", "stun_block", "accuracy_blade", "healing_blade"]
const CATEGORIES := {
	"charm":["blade", "weakness", "accuracy_blade", "accuracy_weakness", "healing_blade", "infection", "dispel"],
	"ward":["shield", "trap", "absorb", "prism", "stun_block"],
	"over_time":["dot", "hot"]
}

static func criteria_from(data: Dictionary, default_polarity: String = "any") -> Dictionary:
	var result: Dictionary = (data.get("criteria", {}) as Dictionary).duplicate(true)
	for key in ["kinds", "exclude_kinds", "category", "polarity", "school_filters", "source_ids", "source_groups", "caster_ids", "definition_ids"]:
		if data.has(key) and not result.has(key):
			result[key] = data[key]
	if data.has("status") and not result.has("kinds"):
		result["kinds"] = [str(data.status)]
	if data.has("school_filter") and not result.has("school_filters"):
		result["school_filters"] = data.school_filter
	if not result.has("polarity"):
		result["polarity"] = default_polarity
	return result

static func _list(value: Variant) -> Array:
	return value if value is Array else [value]

static func _contains(values: Variant, key: String) -> bool:
	for value in _list(values):
		if str(value) == key:
			return true
	return false

static func matches(status: StatusInstanceV2, criteria: Dictionary) -> bool:
	var kinds: Array = _list(criteria.get("kinds", []))
	if not kinds.is_empty() and not _contains(kinds, str(status.kind)):
		return false
	if _contains(criteria.get("exclude_kinds", []), str(status.kind)):
		return false
	if criteria.has("category"):
		var category := str(criteria.category)
		if not CATEGORIES.has(category) or not _contains(CATEGORIES[category], str(status.kind)):
			return false
	var polarity := str(criteria.get("polarity", "any"))
	if polarity not in ["any", "helpful", "harmful"]:
		return false
	var helpful: bool = HELPFUL.has(str(status.kind))
	if status.kind == &"aura" and str(status.payload.get("polarity", "helpful")) == "harmful":
		helpful = false
	if (polarity == "helpful" and not helpful) or (polarity == "harmful" and helpful):
		return false
	for key in ["source_ids", "source_groups", "caster_ids", "definition_ids"]:
		var field: String = {"source_ids":"source_id", "source_groups":"source_group", "caster_ids":"caster_id", "definition_ids":"definition_id"}[key]
		if criteria.has(key) and not _contains(criteria[key], str(status.get(field))):
			return false
	var schools: Array = _list(criteria.get("school_filters", "*"))
	if schools.is_empty() or _contains(schools, "*") or status.school_filters.is_empty() or status.school_filters.has(&"*"):
		return true
	for school in status.school_filters:
		if _contains(schools, str(school)):
			return true
	return false

static func newest_first(unit: BattleUnitStateV2) -> Array[StatusInstanceV2]:
	var result: Array[StatusInstanceV2] = []
	if unit != null:
		result.assign(unit.statuses)
		# Append order records placement on this unit, including stolen/transferred
		# statuses whose original instance id may be older than existing statuses.
		result.reverse()
	return result

static func select(unit: BattleUnitStateV2, criteria: Dictionary) -> Array[StatusInstanceV2]:
	var result: Array[StatusInstanceV2] = []
	if unit != null:
		for status in newest_first(unit):
			if matches(status, criteria):
				result.append(status)
	return result

