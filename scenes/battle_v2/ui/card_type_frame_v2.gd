extends Control

func _draw() -> void:
	draw_style_box(preload("res://scenes/battle_v2/ui/compact_battle_skin.gd").panel(true),Rect2(Vector2.ZERO,size))
