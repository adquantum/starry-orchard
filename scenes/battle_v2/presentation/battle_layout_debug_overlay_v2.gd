class_name BattleLayoutDebugOverlayV2
extends Control

const LayoutProfile = preload("res://scripts/battle_v2/presentation/battle_layout_profile_v2.gd")
const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")

var shell: Control


func _ready() -> void:
	shell = get_parent()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	queue_redraw()


func _draw() -> void:
	if shell == null:
		return
	var viewport_size := size
	var background_texture := ArtRegistryScript.texture(&"background_arcane_academy_duel_hall")
	var background_rect := LayoutProfile.aspect_cover_rect(viewport_size, background_texture.get_size() if background_texture != null else viewport_size)
	var art_rect := LayoutProfile.battle_art_rect(viewport_size)
	var center := LayoutProfile.battle_center(viewport_size)
	var spell_stage_center := LayoutProfile.spell_stage_center(viewport_size)
	var radii := LayoutProfile.battle_radii(viewport_size)
	draw_rect(background_rect, Color("#ff4f8b"), false, 2.0)
	draw_string(ThemeDB.fallback_font, background_rect.position + Vector2(8, 18), "BACKGROUND RECT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ff8fb2"))
	draw_rect(art_rect, Color("#ffc14d"), false, 2.0)
	draw_string(ThemeDB.fallback_font, art_rect.position + Vector2(8, 18), "BATTLE ART RECT", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffd580"))
	_draw_ellipse(center, radii, Color("#45e6ff"), 2.0)
	draw_line(center - Vector2(radii.x, 0), center + Vector2(radii.x, 0), Color("#45e6ffaa"), 1.0)
	draw_line(center - Vector2(0, radii.y), center + Vector2(0, radii.y), Color("#45e6ffaa"), 1.0)
	draw_circle(center, 6.0, Color.CYAN)
	draw_string(ThemeDB.fallback_font, center + Vector2(10, -9), "BATTLE CENTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.CYAN)
	draw_line(center, spell_stage_center, Color("#dd7dff99"), 1.0)
	draw_circle(spell_stage_center, 6.0, Color("#dd7dff"))
	draw_string(ThemeDB.fallback_font, spell_stage_center + Vector2(10, -9), "SPELL STAGE CENTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ecb3ff"))
	var player_hud_safe := LayoutProfile.player_hud_safe_area(viewport_size)
	var hand_safe := LayoutProfile.hand_safe_area(viewport_size)
	draw_rect(player_hud_safe, Color("#65ff8a55"), false, 1.0)
	draw_rect(hand_safe, Color("#ff5f5f77"), false, 2.0)
	draw_string(ThemeDB.fallback_font, hand_safe.position + Vector2(8, 18), "HAND SAFE AREA", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ff9898"))
	for slot_id in LayoutProfile.SLOT_ANGLES_DEGREES:
		var foot := LayoutProfile.slot_anchor(slot_id, viewport_size)
		draw_circle(foot, 5.0, Color("#fff36b"))
		draw_string(ThemeDB.fallback_font, foot + Vector2(7, -5), str(slot_id), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#fff6a6"))
		if not shell.unit_views.has(slot_id):
			continue
		var view: Control = shell.unit_views[slot_id]
		var rune_center: Vector2 = view.ground_sigil.get_global_rect().get_center()
		var plate_center: Vector2 = view.nameplate.get_global_rect().get_center()
		draw_line(foot, rune_center, Color("#b36cff"), 1.5)
		draw_circle(rune_center, 4.0, Color("#c58cff"))
		draw_circle(plate_center, 4.0, Color("#68ff9d"))
		draw_line(foot, plate_center, Color("#68ff9d77"), 1.0)


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in 65:
		var angle := TAU * float(index) / 64.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_polyline(points, color, width, true)
