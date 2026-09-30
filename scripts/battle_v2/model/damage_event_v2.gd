class_name DamageEventV2
extends RefCounted

var source_id: StringName
var source_snapshot: Dictionary = {}
var target_id: StringName
# `school_id` remains the resolved school for backwards compatibility.
var original_school_id: StringName
var school_id: StringName
var base_amount: int
var outgoing_multiplier: float = 1.0
var incoming_multiplier: float = 1.0
var stat_multiplier: float = 1.0
var resistance_multiplier: float = 1.0
var critical_multiplier: float = 1.0
var flat_damage: int = 0
var flat_resistance: int = 0
var pierce: float = 0.0
var critical: bool = false
var absorbed_amount: int = 0
var final_amount: int = 0
var origin: StringName = &"spell"
var hit_index: int = 0
var tags: Array[StringName] = []


func to_dict() -> Dictionary:
	return {
		"source_id": str(source_id), "target_id": str(target_id),
		"original_school": str(original_school_id), "school": str(school_id),
		"base_amount": base_amount, "outgoing_multiplier": outgoing_multiplier,
		"incoming_multiplier": incoming_multiplier, "stat_multiplier": stat_multiplier,
		"resistance_multiplier": resistance_multiplier, "critical_multiplier": critical_multiplier,
		"flat_damage": flat_damage, "flat_resistance": flat_resistance, "pierce": pierce,
		"critical": critical, "absorbed_amount": absorbed_amount,
		"final_amount": final_amount, "origin": str(origin), "hit_index": hit_index,
		"tags": Array(tags).map(func(tag): return str(tag))
	}
