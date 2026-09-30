class_name BattleSlotConfigV2
extends RefCounted

var id: StringName
var normalized_position: Vector2
var visual_scale: float
var z_order: int
var facing: StringName
var sigil_id: StringName
var character_anchor := Vector2.ZERO
var nameplate_anchor := Vector2(0, 8)
var floating_text_anchor := Vector2(0, -118)
var spell_target_anchor := Vector2(0, -62)


func _init(p_id: StringName, position: Vector2, p_scale: float, p_z: int, p_facing: StringName, p_sigil_id: StringName) -> void:
	id = p_id
	normalized_position = position
	visual_scale = p_scale
	z_order = p_z
	facing = p_facing
	sigil_id = p_sigil_id


static func default_slots() -> Dictionary:
	var reference := BattleLayoutProfileV2.REFERENCE_VIEWPORT
	var result := {}
	for slot_id in [&"P0", &"P1", &"P2", &"P3", &"E0", &"E1", &"E2", &"E3"]:
		var anchor := BattleLayoutProfileV2.slot_anchor(slot_id, reference)
		var normalized := anchor / reference
		var team_scale := BattleLayoutProfileV2.CHARACTER_SCALE_FAR if str(slot_id).begins_with("E") else BattleLayoutProfileV2.CHARACTER_SCALE_NEAR
		var z_order := 20 + roundi(normalized.y * 100.0)
		result[slot_id] = BattleSlotConfigV2.new(slot_id, normalized, team_scale, z_order, &"center", PositionRuneRegistryV2.rune_for_slot(slot_id))
	return result
