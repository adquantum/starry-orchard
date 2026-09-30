class_name PositionRuneRegistryV2
extends RefCounted

const SLOT_TO_RUNE := {
	&"P0": &"crown", &"P1": &"chalice", &"P2": &"river", &"P3": &"mountain",
	&"E0": &"dagger", &"E1": &"eye", &"E2": &"moon", &"E3": &"tower",
}


static func rune_for_slot(slot_id: StringName) -> StringName:
	return SLOT_TO_RUNE.get(slot_id, &"") as StringName


static func asset_id(rune_id: StringName) -> StringName:
	return StringName("position_rune_%s" % str(rune_id)) if SLOT_TO_RUNE.values().has(rune_id) else rune_id
