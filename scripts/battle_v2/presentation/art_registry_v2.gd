class_name ArtRegistryV2
extends RefCounted

const REGISTRY_PATHS := [
	"res://assets/game/nameplate_painted_v1/art_registry.generated.json",
	"res://assets/game/nameplate_transparent_v1/art_registry.generated.json",
	"res://assets/game/compact_battle_ui_v1/art_registry.generated.json",
	"res://assets/game/card_components_v1/art_registry.generated.json",
	"res://assets/game/combat_scroll_panel_v1/art_registry.generated.json",
	"res://assets/game/combat_scroll_card_v1/art_registry.generated.json",
	"res://assets/game/status_symbols_v3/art_registry.json",
	"res://assets/game/glyphs/art_registry.generated.json",
	"res://assets/game/glyphs_clean/art_registry.generated.json",
	"res://assets/game/status_world/art_registry.generated.json",
	"res://assets/game/school_magic/art_registry.generated.json",
	"res://assets/game/pips_v2/art_registry.generated.json",
	"res://assets/game/characters_wizard_v1/art_registry.generated.json",
	"res://assets/game/characters_wizard_cardinal_v1/art_registry.generated.json",
	"res://assets/game/spell_actors/fire_serpent/art_registry.generated.json",
	"res://assets/game/backgrounds/art_registry.generated.json",
	"res://assets/game/school_cast_fx_v1/art_registry.generated.json",
	"res://assets/game/spell_icons_1_6_v1/art_registry.generated.json",
	"res://assets/game/hand_actions_v1/art_registry.generated.json",
	"res://assets/game/battle_bottom_hud_v1/art_registry.generated.json",
	"res://assets/game/battle_bottom_hand_tray_v2/art_registry.generated.json",
	"res://assets/game/card_frames_v1/art_registry.generated.json",
	"res://assets/game/ui_v2/art_registry.generated.json",
	"res://assets/game/position_runes_v2/art_registry.generated.json",
	"res://assets/game/spell_icons_v2/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_01/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_02/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_03/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_04/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_05/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_06/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_07/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_08/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_09/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_10/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_11/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_12/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_13/art_registry.generated.json",
	"res://assets/game/spell_icons_wave_14/art_registry.generated.json",
	"res://assets/game/school_badges_v1/art_registry.generated.json",
	"res://assets/game/status_tokens_v4/art_registry.generated.json",
	"res://assets/game/card_mechanic_icons_v5/art_registry.generated.json",
	"res://assets/game/card_mechanic_icons_v6/art_registry.generated.json",
	"res://assets/game/target_glyphs_v6/art_registry.generated.json",
	"res://assets/game/utility_icons_v11/art_registry.generated.json",
	"res://assets/game/spell_creatures_v12/art_registry.generated.json",
	"res://assets/game/global_spells_v17/art_registry.generated.json",
	"res://assets/game/utility_spells_v18/art_registry.generated.json",
	"res://assets/game/utility_icons_v19/art_registry.generated.json",
	"res://assets/game/status_minimal_v1/art_registry.generated.json",
	"res://assets/game/status_tokens_v6/art_registry.generated.json",
	"res://assets/game/status_relief_v2/art_registry.generated.json",
	"res://assets/game/universal_school_v1/art_registry.generated.json",
	"res://assets/game/auras_shields_v22/art_registry.generated.json",
	"res://assets/game/universal_cast_hd_v1/art_registry.generated.json",
	"res://assets/game/cast_symbols_hd_v1/art_registry.generated.json",
	"res://assets/game/spell_icons_review_20260923/art_registry.generated.json",
	]

static var _paths: Dictionary = {}
static var _textures: Dictionary = {}


static func path(asset_id: StringName) -> String:
	_ensure_loaded()
	return str(_paths.get(str(asset_id), ""))


static func has(asset_id: StringName) -> bool:
	return not path(asset_id).is_empty()


static func texture(asset_id: StringName) -> Texture2D:
	var key := str(asset_id)
	if _textures.has(key):
		return _textures[key] as Texture2D
	var asset_path := path(asset_id)
	if asset_path.is_empty() or not ResourceLoader.exists(asset_path):
		return null
	var loaded := load(asset_path) as Texture2D
	if loaded != null:
		_textures[key] = loaded
	return loaded


static func ids() -> Array[StringName]:
	_ensure_loaded()
	var result: Array[StringName] = []
	for key in _paths:
		result.append(StringName(str(key)))
	result.sort()
	return result


static func _ensure_loaded() -> void:
	if not _paths.is_empty():
		return
	for registry_path in REGISTRY_PATHS:
		if not FileAccess.file_exists(registry_path):
			continue
		var file := FileAccess.open(registry_path, FileAccess.READ)
		if file == null:
			push_warning("Battle V2 ArtRegistry could not open: %s" % registry_path)
			continue
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_paths.merge(parsed, true)
		else:
			push_warning("Battle V2 ArtRegistry is not a dictionary: %s" % registry_path)


static func status_school_key(status: StatusInstanceV2) -> String:
	if status.kind in [&"healing_blade", &"infection"]:return "all"
	if status.school_filters.is_empty() or status.school_filters.has(&"*") or status.school_filters.has(&""):
		return "all"
	return str(status.school_filters[0])
