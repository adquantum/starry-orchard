class_name EffectGlyphV2
extends Control

const RegistryScript = preload("res://scripts/battle_v2/presentation/effect_icon_registry_v2.gd")
const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")

var glyph_id: StringName
var accent := Color("#e7cf8a")
var glyph_texture: Texture2D
var hovered := false
var pulse_time := 0.0


func setup(p_glyph_id: StringName, p_accent: Color) -> void:
	glyph_id = p_glyph_id
	accent = p_accent
	glyph_texture = preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd").ui_symbol(glyph_id)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): hovered = true; queue_redraw())
	mouse_exited.connect(func(): hovered = false; queue_redraw())
	var metadata := RegistryScript.entry(glyph_id)
	tooltip_text = "%s\n%s" % [str(metadata.get("label", glyph_id)), str(metadata.get("tooltip", ""))]
	queue_redraw()
	set_process(true)


func _process(delta: float) -> void:
	pulse_time += delta
	if hovered:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var id := str(glyph_id)
	if glyph_texture != null:
		if hovered:
			var pulse := 0.5 + sin(pulse_time * 7.0) * 0.5
			draw_circle(c, minf(size.x, size.y) * 0.48, Color(accent, 0.10 + pulse * 0.12))
		draw_texture_rect(glyph_texture, Rect2(Vector2.ZERO, size), false)
		return
	draw_circle(c, minf(size.x, size.y) * 0.43, Color("#101827"))
	draw_arc(c, minf(size.x, size.y) * 0.40, 0, TAU, 18, Color(accent, 0.85), 1.3)
	if id.begins_with("school_"):
		_draw_school(c, id.trim_prefix("school_"))
	elif id.begins_with("target_"):
		_draw_target(c, id.trim_prefix("target_"))
	else:
		_draw_effect(c, id)


func _draw_school(c: Vector2, school: String) -> void:
	if school == "fire":
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, -1), c + Vector2(3, 6), c + Vector2(-4, 7), c + Vector2(-6, 1)]), accent)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -2), c + Vector2(2, 4), c + Vector2(-2, 4)]), Color("#fff0a0"))
	else:
		draw_string(ThemeDB.fallback_font, c + Vector2(-4, 4), school.left(1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 8, 9, accent)


func _draw_target(c: Vector2, target: String) -> void:
	match target:
		"self":
			draw_circle(c, 3, accent)
			draw_arc(c, 7, 0, TAU, 16, accent, 1.5)
		"ally", "dead_ally":
			draw_circle(c + Vector2(-3, -2), 3, accent)
			draw_circle(c + Vector2(4, -1), 2.5, accent)
			draw_line(c + Vector2(-7, 6), c + Vector2(7, 6), accent, 2)
		"enemy":
			draw_circle(c, 5, accent, false, 1.5)
			draw_line(c + Vector2(-7, -6), c + Vector2(-3, -3), accent, 2)
			draw_line(c + Vector2(7, -6), c + Vector2(3, -3), accent, 2)
		"all_allies", "all_enemies":
			for x in [-5, 0, 5]:
				draw_circle(c + Vector2(x, 0), 2.5, accent)
			draw_arc(c, 8, PI, TAU, 12, accent, 1.5)
		_:
			draw_arc(c, 6, 0, TAU, 8, accent, 1.5)


func _draw_effect(c: Vector2, id: String) -> void:
	match id:
		"summon":
			draw_arc(c+Vector2(0,4),6,0,TAU,24,accent,1.5)
			draw_circle(c+Vector2(0,-3),2.5,accent)
			draw_line(c+Vector2(0,0),c+Vector2(0,4),accent,2)
			draw_line(c+Vector2(-4,1),c+Vector2(4,1),accent,2)
		"stun":
			var points:=PackedVector2Array()
			for i in 10:
				var a: float=-PI/2+i*PI/5
				points.append(c+Vector2(cos(a),sin(a))*(7 if i%2==0 else 3))
			draw_colored_polygon(points,accent)
		"damage":
			draw_line(c + Vector2(-6, 6), c + Vector2(6, -6), accent, 2)
			draw_line(c + Vector2(1, -5), c + Vector2(6, -6), accent, 2)
			draw_line(c + Vector2(5, -1), c + Vector2(6, -6), accent, 2)
		"heal", "revive":
			draw_rect(Rect2(c + Vector2(-2, -7), Vector2(4, 14)), accent)
			draw_rect(Rect2(c + Vector2(-7, -2), Vector2(14, 4)), accent)
		"shield", "trap":
			var pts := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, -4), c + Vector2(5, 5), c + Vector2(0, 8), c + Vector2(-5, 5), c + Vector2(-7, -4)])
			draw_polyline(PackedVector2Array(Array(pts) + [pts[0]]), accent, 1.5)
			if id == "trap": draw_circle(c, 2, accent)
		"dot", "hot":
			for x in [-5, 0, 5]:
				draw_colored_polygon(PackedVector2Array([c + Vector2(x, -4), c + Vector2(x + 3, 0), c + Vector2(x, 4), c + Vector2(x - 3, 0)]), accent)
			if id == "hot": draw_line(c + Vector2(-2, 0), c + Vector2(2, 0), Color("#10202a"), 1)
		"delay_damage", "duration":
			draw_line(c + Vector2(-5, -6), c + Vector2(5, -6), accent, 1.5)
			draw_line(c + Vector2(-5, 6), c + Vector2(5, 6), accent, 1.5)
			draw_line(c + Vector2(-4, -5), c + Vector2(4, 5), accent, 1.5)
			draw_line(c + Vector2(4, -5), c + Vector2(-4, 5), accent, 1.5)
		"blade", "weakness":
			draw_arc(c, 6, -2.5, 0.7, 10, accent, 2)
			if id == "weakness": draw_line(c + Vector2(-5, -5), c + Vector2(5, 5), Color("#ef7683"), 2)
		_:
			draw_string(ThemeDB.fallback_font, c + Vector2(-4, 4), id.left(1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 8, 9, accent)
