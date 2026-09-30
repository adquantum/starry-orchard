extends "res://scenes/battle_v2/ui/effect_icon_v2.gd"
func _draw() -> void:
	draw_circle(size/2,8,Color(accent,0.08))
	super._draw()
