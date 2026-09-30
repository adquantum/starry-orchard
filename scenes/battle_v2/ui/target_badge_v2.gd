extends "res://scenes/battle_v2/ui/effect_icon_v2.gd"
var invalid:=false
func set_invalid(value: bool) -> void:
	if invalid!=value:invalid=value;queue_redraw()
func _draw() -> void:
	super._draw()
	if invalid:
		draw_arc(size/2,8,0,TAU,24,Color("df977d"),1.5,true)
		draw_line(Vector2(13,1),Vector2(17,5),Color("df977d"),2)
		draw_line(Vector2(17,1),Vector2(13,5),Color("df977d"),2)
