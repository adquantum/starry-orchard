class_name UnitHUDSkinDefinitionV2
extends RefCounted

var show_portrait := false
var panel_texture: StringName = &"ui_v2_nameplate"
var rune_holder: StringName = &"ui_v2_rune_glow"
var hp_frame: StringName = &"ui_v2_hp_frame"
var pip_socket: StringName = &"ui_v2_pip_socket"
var shadow_socket: StringName = &"ui_v2_pip_socket"
var action_spell_frame: StringName = &"ui_v2_rune_glow"
var action_target_frame: StringName = &"ui_v2_rune_glow"
var status_panel: StringName = &"ui_v2_tooltip"


static func arcane_v5() -> UnitHUDSkinDefinitionV2:
	return UnitHUDSkinDefinitionV2.new()
