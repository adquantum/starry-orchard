class_name SpellArtSafeZoneV2
extends Control

@export_file("*.png") var art_path := "res://assets/battle_v2/spell_art/fire_bolt_v2_transparent.png"
var art_texture: Texture2D


func _ready() -> void:
	art_texture = load(art_path) as Texture2D if ResourceLoader.exists(art_path) else null
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	var rect := Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side)
	var cell := side / 16.0
	for y in 16:
		for x in 16:
			var checker := Color("#28303a") if (x + y) % 2 == 0 else Color("#3a4552")
			draw_rect(Rect2(rect.position + Vector2(x, y) * cell, Vector2.ONE * cell), checker)
	if art_texture != null:
		draw_texture_rect(art_texture, rect, false)
	draw_rect(rect, Color("#74d8ff"), false, 2)
	var center := rect.get_center()
	var radius := side * 0.35
	draw_arc(center, radius, 0, TAU, 96, Color("#fff0a6"), 3)
	draw_line(center - Vector2(radius, 0), center + Vector2(radius, 0), Color(1, 1, 1, 0.30), 1)
	draw_line(center - Vector2(0, radius), center + Vector2(0, radius), Color(1, 1, 1, 0.30), 1)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(12, 24), "CIRCULAR SAFE ZONE · 70%", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#fff0a6"))
