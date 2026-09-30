class_name TargetSigilV2
extends Control

const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const RuneRegistryScript = preload("res://scripts/battle_v2/presentation/position_rune_registry_v2.gd")

const POSITION_VISUAL_OFFSETS := {
	&"crown": Vector2(4.5, 6.5), &"chalice": Vector2(1.5, 4.5), &"river": Vector2(1.5, 2.5), &"mountain": Vector2(0, 4.5),
	&"dagger": Vector2(-2.5, 0), &"eye": Vector2(1, -0.5), &"moon": Vector2(1.5, 0.5), &"tower": Vector2(4.5, 0)
}

var sigil_id: StringName = &"battle_circle"
var accent := Color("#e8cf85")
var intensity := 0.32
var pulse_time := 0.0
var sigil_texture: Texture2D
var ground_variant := false
var glow_enabled := true
var texture_radius_ratio := 0.38


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func setup(p_sigil_id: StringName, p_accent: Color = Color("#e8cf85"), p_intensity: float = 0.32) -> void:
	sigil_id = p_sigil_id
	accent = p_accent
	intensity = p_intensity
	sigil_texture = ArtRegistryScript.texture(RuneRegistryScript.asset_id(sigil_id))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func set_ground_variant(value: bool) -> void:
	ground_variant = value
	var asset_id := RuneRegistryScript.asset_id(sigil_id)
	sigil_texture = ArtRegistryScript.texture(asset_id)
	queue_redraw()


func set_intensity(value: float) -> void:
	intensity = value
	queue_redraw()


func set_glow_enabled(value: bool) -> void:
	glow_enabled = value
	queue_redraw()


func set_texture_radius_ratio(value: float) -> void:
	texture_radius_ratio = clampf(value, 0.28, 0.48)
	queue_redraw()


func _process(delta: float) -> void:
	pulse_time += delta
	if intensity > 0.5:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * texture_radius_ratio
	var color := Color(accent, clampf(intensity + sin(pulse_time * 5.0) * 0.08, 0.08, 1.0))
	if glow_enabled and intensity > 0.48:
		var glow := ArtRegistryScript.texture(&"ui_v2_rune_glow")
		if glow != null:
			draw_texture_rect(glow, Rect2(c - Vector2.ONE * radius * 1.18, Vector2.ONE * radius * 2.36), false, Color(accent, color.a * 0.55))
	if sigil_texture != null:
		var offset := (POSITION_VISUAL_OFFSETS.get(sigil_id, Vector2.ZERO) as Vector2) * (radius * 2.0 / 64.0)
		var visual_center := c + offset
		draw_texture_rect(sigil_texture, Rect2(visual_center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, Color(1, 1, 1, color.a))
		return
	match sigil_id:
		&"crown":
			_line([c + Vector2(-12, 7), c + Vector2(-9, -7), c, c + Vector2(0, -10), c + Vector2(9, -7), c + Vector2(12, 7), c + Vector2(-12, 7)], color)
		&"chalice":
			draw_arc(c + Vector2(0, -5), 10, 0, PI, 14, color, 2)
			_line([c + Vector2(-10, -5), c + Vector2(-7, 3), c, c + Vector2(0, 11)], color)
			_line([c + Vector2(-7, 11), c + Vector2(7, 11)], color)
		&"river":
			for y in [-7, 0, 7]:
				_line([c + Vector2(-12, y), c + Vector2(-5, y - 3), c + Vector2(5, y + 3), c + Vector2(12, y)], color)
		&"mountain":
			_line([c + Vector2(-13, 9), c + Vector2(-4, -8), c + Vector2(1, 0), c + Vector2(7, -11), c + Vector2(14, 9)], color)
		&"dagger":
			_line([c + Vector2(0, -13), c + Vector2(5, 5), c, c + Vector2(-5, 5), c + Vector2(0, -13)], color)
			_line([c + Vector2(-8, 7), c + Vector2(8, 7)], color)
		&"eye":
			_line([c + Vector2(-13, 0), c + Vector2(-5, -7), c + Vector2(5, -7), c + Vector2(13, 0), c + Vector2(5, 7), c + Vector2(-5, 7), c + Vector2(-13, 0)], color)
			draw_circle(c, 3.5, color)
		&"moon":
			draw_arc(c, 11, -PI * 0.65, PI * 0.65, 18, color, 2)
			draw_arc(c + Vector2(6, 0), 9, -PI * 0.65, PI * 0.65, 18, color, 2)
		&"tower":
			draw_rect(Rect2(c + Vector2(-7, -8), Vector2(14, 18)), color, false, 2)
			_line([c + Vector2(-9, -8), c + Vector2(-9, -13), c + Vector2(-3, -9), c + Vector2(3, -13), c + Vector2(9, -8)], color)
		&"enemy_arc", &"ally_arc":
			for x in [-9, -3, 3, 9]:
				draw_circle(c + Vector2(x, 1), 2.5, color)
			draw_arc(c, 14, PI, TAU, 18, color, 2)
		&"pass":
			_line([c + Vector2(-10, -10), c + Vector2(10, 10)], color)
			_line([c + Vector2(10, -10), c + Vector2(-10, 10)], color)
		_:
			draw_arc(c, 11, 0, TAU, 8, color, 2)
			draw_circle(c, 3, color)


func _line(points: Array, color: Color) -> void:
	draw_polyline(PackedVector2Array(points), color, 2.0, true)
