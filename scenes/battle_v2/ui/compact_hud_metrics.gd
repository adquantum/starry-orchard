extends RefCounted

# HUD-only dimensions, authored at 1920x1080. Never scale the hand or world.
const SIZE := Vector2(360, 78)
const GAP := 9.0
const MARGIN := 16.0
const TOP := 88.0
const SCHOOL := 46.0
const RUNE := 18.0
const PIP := 14.0
const PIP_STEP := 16.0
const STATUS := 18.0
const NAME_FONT := 18
const AUX_FONT := 14
const HP_HEIGHT := 7.0
const BACKGROUND_ALPHA := 0.21
const CONTENT_X := 58.0
const CONTENT_WIDTH := 240.0
const SHADOW_X := 127.0
const STATUS_X := 158.0
const ACTION_TARGET := 24.0
const ACTION_SIZE := Vector2(54, 74)
const ACTION_LABEL_Y := 70.0
const FRIEND_HP := Color("52d9b3")
const ENEMY_HP := Color("f27683")
const TEXT := Color("f4f7fa")

static func scale_for(viewport: Vector2) -> float:
	return clampf(viewport.x / 1920.0, 0.85, 1.0)
