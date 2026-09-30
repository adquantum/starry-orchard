class_name CardSkinDefinitionV2
extends RefCounted

var card_bg: StringName = &"ui_v2_card_bg"
var card_outer_frame: StringName = &"ui_v2_card_outer_frame"
var card_header: StringName = &"ui_v2_card_header"
var card_art_frame: StringName = &"ui_v2_card_art_frame"
var card_effect_panel: StringName = &"ui_v2_card_effect_panel"
var card_footer: StringName = &"ui_v2_card_footer"
var cost_holder: StringName = &"ui_v2_cost_holder"
var school_holder: StringName = &"ui_v2_school_holder"
var selected_overlay: StringName = &"ui_v2_rune_glow"
var hover_overlay: StringName = &"ui_v2_rune_glow"
var disabled_overlay: StringName = &"ui_v2_card_bg"
var treasure_overlay: StringName = &"ui_v2_gold_divider"
var fusion_overlay: StringName = &"ui_v2_gold_divider"


static func arcane_v2() -> CardSkinDefinitionV2:
	return CardSkinDefinitionV2.new()
