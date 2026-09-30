class_name BattleLayoutProfileV2
extends RefCounted

# The single source of truth for Battle V2 presentation geometry.
const REFERENCE_VIEWPORT := Vector2(1600, 900)
const PLATE_ASPECT := 1.5
const BATTLE_ART_WIDTH_RATIO := 0.72
const BATTLE_ART_MAX_HEIGHT_RATIO := 0.97
const BATTLE_ART_CENTER_Y := 0.52
const BATTLE_CENTER_NORMALIZED := Vector2(0.50, 0.47)
# The painted vortex sits above the plate ellipse's geometric center because of
# the top-down perspective. Pointer and summon presentations use this anchor.
const SPELL_STAGE_CENTER_NORMALIZED := Vector2(0.50, 0.41)
const BATTLE_RADII_NORMALIZED := Vector2(0.37, 0.38)

const SLOT_ANGLES_DEGREES := {
	&"E0": -144.0, &"E1": -110.0, &"E2": -70.0, &"E3": -36.0,
	&"P0": 36.0, &"P1": 70.0, &"P2": 110.0, &"P3": 144.0,
}

const CHARACTER_SCALE_NEAR := 1.0
const CHARACTER_SCALE_FAR := 0.82
const UNIT_LOCAL_FOOT := Vector2(110, 132)
const RUNE_FORWARD_DISTANCE := 104.0

const NAMEPLATE_SIZE := Vector2(302, 100)
const NAMEPLATE_FOOT_GAP := 7.0
const NAMEPLATE_SIDE_GAP := 8.0
const PLAYER_HUD_HAND_GAP := 10.0

const HAND_VISIBLE_HEIGHT := 222.0
const HAND_CARD_SIZE := Vector2(138, 208)
const HAND_HOVER_RISE := 54.0
const CARD_TITLE_RECT := Rect2(25, 4, 88, 23)
const CARD_COST_CENTER := Vector2(17, 35)
const CARD_SCHOOL_CENTER := Vector2(121, 35)
const CARD_ART_RECT := Rect2(14, 31, 110, 104)
const CARD_EFFECT_RECT := Rect2(12, 141, 114, 63)
const BOTTOM_DOCK_SIZE := Vector2(240, 210)
const BOTTOM_DOCK_MARGIN := 14.0
const HAND_DOCK_WIDTH := 1040.0
const TOP_HUD_HEIGHT := 58.0


static func scale_for_viewport(viewport_size: Vector2) -> float:
	return clampf(minf(viewport_size.x / REFERENCE_VIEWPORT.x, viewport_size.y / REFERENCE_VIEWPORT.y), 0.78, 1.28)


static func battle_art_rect(viewport_size: Vector2) -> Rect2:
	var width := viewport_size.x * BATTLE_ART_WIDTH_RATIO
	var height := width / PLATE_ASPECT
	var max_height := viewport_size.y * BATTLE_ART_MAX_HEIGHT_RATIO
	if height > max_height:
		height = max_height
		width = height * PLATE_ASPECT
	var center := Vector2(viewport_size.x * 0.5, viewport_size.y * BATTLE_ART_CENTER_Y)
	return Rect2(center - Vector2(width, height) * 0.5, Vector2(width, height))


static func aspect_cover_rect(viewport_size: Vector2, texture_size: Vector2) -> Rect2:
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return Rect2(Vector2.ZERO, viewport_size)
	var scale := maxf(viewport_size.x / texture_size.x, viewport_size.y / texture_size.y)
	var drawn_size := texture_size * scale
	return Rect2((viewport_size - drawn_size) * 0.5, drawn_size)


static func battle_center(viewport_size: Vector2) -> Vector2:
	var art_rect := battle_art_rect(viewport_size)
	return art_rect.position + art_rect.size * BATTLE_CENTER_NORMALIZED


static func spell_stage_center(viewport_size: Vector2) -> Vector2:
	var art_rect := battle_art_rect(viewport_size)
	return art_rect.position + art_rect.size * SPELL_STAGE_CENTER_NORMALIZED


static func battle_radii(viewport_size: Vector2) -> Vector2:
	return battle_art_rect(viewport_size).size * BATTLE_RADII_NORMALIZED


static func slot_anchor(slot_id: StringName, viewport_size: Vector2) -> Vector2:
	var angle := deg_to_rad(float(SLOT_ANGLES_DEGREES.get(slot_id, 0.0)))
	var center := battle_center(viewport_size)
	var radii := battle_radii(viewport_size)
	return center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)


static func character_scale(slot_id: StringName, viewport_size: Vector2) -> float:
	return scale_for_viewport(viewport_size) * (CHARACTER_SCALE_FAR if str(slot_id).begins_with("E") else CHARACTER_SCALE_NEAR)


static func hand_safe_area(viewport_size: Vector2) -> Rect2:
	return Rect2(0, viewport_size.y - HAND_VISIBLE_HEIGHT, viewport_size.x, HAND_VISIBLE_HEIGHT)


static func hand_dock_rect(viewport_size: Vector2) -> Rect2:
	var ui_scale := scale_for_viewport(viewport_size)
	var width := minf(HAND_DOCK_WIDTH * ui_scale, viewport_size.x - (BOTTOM_DOCK_SIZE.x + BOTTOM_DOCK_MARGIN * 2.0) * 2.0 * ui_scale)
	var height := maxf(HAND_VISIBLE_HEIGHT * ui_scale, HAND_CARD_SIZE.y)
	return Rect2(Vector2((viewport_size.x - width) * 0.5, viewport_size.y - height), Vector2(width, height))


static func bottom_action_dock_rect(viewport_size: Vector2) -> Rect2:
	var ui_scale := scale_for_viewport(viewport_size)
	var dock_size := BOTTOM_DOCK_SIZE * ui_scale
	return Rect2(Vector2(BOTTOM_DOCK_MARGIN * ui_scale, viewport_size.y - dock_size.y - BOTTOM_DOCK_MARGIN * ui_scale), dock_size)


static func bottom_deck_dock_rect(viewport_size: Vector2) -> Rect2:
	var ui_scale := scale_for_viewport(viewport_size)
	var dock_size := BOTTOM_DOCK_SIZE * ui_scale
	return Rect2(Vector2(viewport_size.x - dock_size.x - BOTTOM_DOCK_MARGIN * ui_scale, viewport_size.y - dock_size.y - BOTTOM_DOCK_MARGIN * ui_scale), dock_size)


static func player_hud_safe_area(viewport_size: Vector2) -> Rect2:
	var hand := hand_safe_area(viewport_size)
	return Rect2(0, TOP_HUD_HEIGHT, viewport_size.x, hand.position.y - TOP_HUD_HEIGHT - PLAYER_HUD_HAND_GAP)
