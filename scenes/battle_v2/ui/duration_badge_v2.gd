extends Control
const Tokens=preload("res://scenes/battle_v2/ui/effect_tokens_v2.gd")
const Explanation=preload("res://scenes/battle_v2/ui/effect_tooltip_v2.gd")
var text: String=""
var font: Font=Tokens.number_font()
func setup(row: Dictionary) -> void:
	text="×"+str(row.duration) if int(row.duration)>0 else ("×"+str(row.repeat_count) if int(row.repeat_count)>1 else str(row.qualifier))
	tooltip_text=Explanation.duration_text(row)
	mouse_filter=Control.MOUSE_FILTER_PASS
	queue_redraw()
func _draw() -> void:
	Tokens.draw_number(self,text,0,14,size.x-2.0,font,11,6)
func _make_custom_tooltip(value: String) -> Object:return Explanation.panel(value)
