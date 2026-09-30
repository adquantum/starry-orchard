class_name ArcaneUIThemeV2
extends RefCounted

const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const UIFont = preload("res://assets/fonts/pixelify_sans/PixelifySans-Bold.ttf")

const PANEL := &"ui_v2_tooltip"
const PANEL_SMALL := &"ui_v2_nameplate"
const TOOLTIP := &"ui_v2_tooltip"
const BUTTON := &"ui_v2_action_button"
const NAMEPLATE := &"ui_v2_nameplate"
const PORTRAIT_FRAME := &"ui_v2_portrait_frame"
const HP_FRAME := &"ui_v2_hp_frame"
const PIP_SOCKET := &"ui_v2_pip_socket"
const GOLD_DIVIDER := &"ui_v2_gold_divider"
const RUNE_GLOW := &"ui_v2_rune_glow"


static func texture(asset_id: StringName) -> Texture2D:
	return ArtRegistryScript.texture(asset_id)


static func style(asset_id: StringName, margin := 18.0, tint := Color.WHITE) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture(asset_id)
	box.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, margin)
		box.set_content_margin(side, 7.0)
	return box


static func apply_button(button: BaseButton) -> void:
	button.add_theme_font_override("font", UIFont)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", style(BUTTON, 7.0, Color("#dce3f2")))
	button.add_theme_stylebox_override("hover", style(BUTTON, 7.0, Color("#fff0b0")))
	button.add_theme_stylebox_override("pressed", style(BUTTON, 7.0, Color("#aeb6c9")))
	button.add_theme_stylebox_override("disabled", style(BUTTON, 7.0, Color("#777b86")))
	button.add_theme_color_override("font_color", Color("#f5e5bd"))
	button.add_theme_color_override("font_hover_color", Color("#fff4c7"))
	button.add_theme_color_override("font_disabled_color", Color("#8a8790"))
