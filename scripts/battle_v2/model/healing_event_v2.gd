class_name HealingEventV2
extends RefCounted

var source_id: StringName
var target_id: StringName
var base_amount: int
var critical: bool = false
var critical_multiplier: float = 1.0
var outgoing_multiplier: float = 1.0
var incoming_multiplier: float = 1.0
var final_amount: int = 0
var origin: StringName = &"spell"


func to_dict() -> Dictionary:
	return {
		"source_id": str(source_id), "target_id": str(target_id), "base_amount": base_amount,
		"outgoing_multiplier": outgoing_multiplier, "incoming_multiplier": incoming_multiplier,
		"final_amount": final_amount, "origin": str(origin), "critical":critical, "critical_multiplier":critical_multiplier
	}
