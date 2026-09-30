class_name BattleEventV2
extends RefCounted

var type: StringName
var sequence: int
var round_index: int
var payload: Dictionary


func _init(p_type: StringName = &"Unknown", p_sequence: int = 0, p_round: int = 0, p_payload: Dictionary = {}) -> void:
	type = p_type
	sequence = p_sequence
	round_index = p_round
	payload = p_payload.duplicate(true)


func to_dict() -> Dictionary:
	return {"type": str(type), "sequence": sequence, "round": round_index, "payload": payload.duplicate(true)}
