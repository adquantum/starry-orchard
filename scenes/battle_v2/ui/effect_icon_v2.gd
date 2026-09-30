extends "res://scenes/battle_v2/ui/effect_glyph_v2.gd"
const Explanation=preload("res://scenes/battle_v2/ui/effect_tooltip_v2.gd")
func setup(id: StringName, color: Color) -> void:
	super.setup(id,color)
	glyph_texture=preload("res://scenes/battle_v2/ui/card_description_symbols_v1.gd").texture(id)
	mouse_filter=Control.MOUSE_FILTER_PASS
	tooltip_text=Explanation.icon_text(id)
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
func _make_custom_tooltip(text: String) -> Object:return Explanation.panel(text)
