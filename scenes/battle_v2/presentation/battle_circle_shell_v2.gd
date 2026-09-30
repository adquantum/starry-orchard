class_name BattleCircleShellV2
extends Control

const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const LayoutProfile = preload("res://scripts/battle_v2/presentation/battle_layout_profile_v2.gd")

var debug_mode := false
var background_texture: Texture2D
var battle_plate_texture: Texture2D
var environment_visible := true
var arena_offset := Vector2.ZERO

func _ready() -> void:
	background_texture = ArtRegistryScript.texture(&"background_arcane_academy_duel_hall")
	battle_plate_texture = ArtRegistryScript.texture(&"battle_plate_user_v2")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	queue_redraw()


func set_debug_mode(value: bool) -> void:
	debug_mode = value
	queue_redraw()

func set_environment_visible(value: bool) -> void:
	environment_visible = value
	queue_redraw()


func set_arena_offset(value: Vector2) -> void:
	arena_offset = value
	queue_redraw()



func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	if environment_visible:
		_draw_environment(s)
	draw_set_transform(arena_offset)
	var plate_rect := LayoutProfile.battle_art_rect(s)
	var center := LayoutProfile.battle_center(s)
	var radii := LayoutProfile.battle_radii(s)
	if battle_plate_texture != null:
		draw_texture_rect(battle_plate_texture, plate_rect, false, Color(0.88, 0.91, 1.0, 0.94))
		if debug_mode:
			draw_rect(plate_rect, Color("#ffbf47"), false, 2.0)
			_draw_debug(center, radii)
		return
	draw_colored_polygon(_ellipse_points(center, radii, 72), Color("#10142770"))
	_draw_ellipse(center, radii + Vector2(12, 7), Color("#111827d9"), 72, 10.0)
	_draw_ellipse(center, radii, Color("#9b7139"), 72, 4.0)
	_draw_ellipse(center, radii - Vector2(7, 4), Color("#4b366b"), 72, 2.0)
	_draw_ellipse(center, radii * Vector2(0.72, 0.66), Color("#405d82b0"), 64, 2.0)
	_draw_ellipse(center, radii * Vector2(0.46, 0.39), Color("#77518d99"), 64, 2.0)
	_draw_slot_pads(s)
	_draw_runes(center, radii)
	if debug_mode:
		_draw_debug(center, radii)


func _draw_environment(s: Vector2) -> void:
	if background_texture != null:
		var background_rect := LayoutProfile.aspect_cover_rect(s, background_texture.get_size())
		draw_texture_rect(background_texture, background_rect, false, Color(0.82, 0.86, 0.94, 1.0))
		draw_rect(Rect2(Vector2.ZERO, s), Color(0.01, 0.02, 0.04, 0.10))
		if debug_mode:
			draw_rect(background_rect, Color("#ff5c8a"), false, 2.0)
		return
	draw_rect(Rect2(Vector2.ZERO, s), Color("#07101f"))
	draw_rect(Rect2(0, 0, s.x, s.y * 0.34), Color("#0b1930"))
	for index in 18:
		var x := s.x * float(index) / 17.0
		var h := 25.0 + float((index * 31) % 58)
		draw_rect(Rect2(x - 12, s.y * 0.22 - h, 24, h), Color("#111d34"))
		if index % 3 == 0:
			draw_circle(Vector2(x, s.y * 0.22 - h * 0.55), 2.0, Color("#d3a64b"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, s.y * 0.23), Vector2(s.x, s.y * 0.23), Vector2(s.x, s.y), Vector2(0, s.y)
	]), Color("#162536"))
	for index in 12:
		var y := s.y * (0.28 + index * 0.055)
		draw_line(Vector2(0, y), Vector2(s.x, y), Color(0.12, 0.20, 0.28, 0.35), 1.0)
	draw_circle(Vector2(s.x * 0.11, s.y * 0.10), 39, Color("#d9e4d4"))
	draw_circle(Vector2(s.x * 0.12, s.y * 0.09), 39, Color("#0b1930"))


func _draw_runes(center: Vector2, radii: Vector2) -> void:
	var star := PackedVector2Array()
	for index in 13:
		var source_index := (index * 5) % 12
		var angle := -PI * 0.5 + TAU * float(source_index) / 12.0
		star.append(center + Vector2(cos(angle) * radii.x * 0.31, sin(angle) * radii.y * 0.25))
	draw_polyline(star, Color("#8d65b899"), 2.0, true)
	for index in 12:
		var angle := TAU * float(index) / 12.0
		var point := center + Vector2(cos(angle) * radii.x * 0.58, sin(angle) * radii.y * 0.51)
		draw_circle(point, 2.5, Color("#d6ad59a8"))
	draw_circle(center, 5.0, Color("#d3a64b"))


func _draw_slot_pads(s: Vector2) -> void:
	var pad_radii := Vector2(s.x * 0.056, s.y * 0.027)
	for slot_id in LayoutProfile.SLOT_ANGLES_DEGREES:
		var center := LayoutProfile.slot_anchor(slot_id, s)
		draw_colored_polygon(_ellipse_points(center, pad_radii, 40), Color("#111522b8"))
		_draw_ellipse(center, pad_radii + Vector2(3, 2), Color("#171d2b"), 40, 6.0)
		_draw_ellipse(center, pad_radii, Color("#b17b3c"), 40, 3.0)
		_draw_ellipse(center, pad_radii - Vector2(6, 3), Color("#4a5f85a8"), 40, 2.0)


func _draw_debug(center: Vector2, radii: Vector2) -> void:
	_draw_ellipse(center, radii, Color("#43d8ff"), 64, 1.0)
	draw_line(center - Vector2(radii.x, 0), center + Vector2(radii.x, 0), Color("#3de7ff99"), 1.0)
	draw_line(center - Vector2(0, radii.y), center + Vector2(0, radii.y), Color("#3de7ff99"), 1.0)
	draw_circle(center, 5.0, Color.CYAN)
	draw_string(ThemeDB.fallback_font, center + Vector2(18, -8), "BATTLE ELLIPSE CENTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.CYAN)
	var spell_center := LayoutProfile.spell_stage_center(size) + arena_offset
	draw_circle(spell_center, 5.0, Color("#dd7dff"))
	draw_string(ThemeDB.fallback_font, spell_center + Vector2(18, -8), "SPELL STAGE / VORTEX", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ecb3ff"))


func battle_art_rect() -> Rect2:
	var base := LayoutProfile.battle_art_rect(size)
	return Rect2(base.position + arena_offset, base.size)


func battle_center() -> Vector2:
	return LayoutProfile.battle_center(size) + arena_offset


func battle_radii() -> Vector2:
	return LayoutProfile.battle_radii(size)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, segments: int, width: float) -> void:
	var points := _ellipse_points(center, radii, segments)
	draw_polyline(points, color, width, true)


func _ellipse_points(center: Vector2, radii: Vector2, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in segments + 1:
		var angle := TAU * float(index) / float(segments)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points
