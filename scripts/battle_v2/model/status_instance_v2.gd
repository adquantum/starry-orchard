class_name StatusInstanceV2
extends RefCounted

var instance_id: int
var definition_id: StringName
var kind: StringName
var source_id: StringName
var source_group: StringName
var caster_id: StringName
var school_filter: StringName = &"*"
var school_filters: Array[StringName] = [&"*"]
var value: float = 0.0
var ticks: int = 0
var payload: Dictionary = {}


func _init(p_id: int = 0) -> void:
	instance_id = p_id


func matches_school(school_id: StringName) -> bool:
	return school_filters.is_empty() or school_filters.has(&"*") or school_filters.has(&"") or school_filters.has(school_id)


func set_school_filters(value: Variant) -> void:
	school_filters.clear()
	if value is Array:
		for item in value:
			school_filters.append(StringName(str(item)))
	else:
		school_filters.append(StringName(str(value)))
	if school_filters.is_empty():
		school_filters.append(&"*")
	school_filter = school_filters[0]


func to_dict() -> Dictionary:
	return {
		"instance_id": instance_id, "definition_id": str(definition_id), "kind": str(kind),
		"source_id": str(source_id), "source_group": str(source_group),
		"caster_id": str(caster_id), "school_filter": str(school_filter),
		"school_filters": Array(school_filters).map(func(school): return str(school)),
		"value": value, "ticks": ticks, "payload": payload.duplicate(true)
	}
