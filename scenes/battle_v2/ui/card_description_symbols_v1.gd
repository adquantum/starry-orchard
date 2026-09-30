extends RefCounted
## Card-description-only artwork. Never register these school variants globally.
const REGISTRY := "res://assets/game/card_description_v1/art_registry.generated.json"
const Painted = preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd")
static var paths: Dictionary = {}
static var textures: Dictionary = {}

static func texture(id: StringName) -> Texture2D:
	if paths.is_empty() and FileAccess.file_exists(REGISTRY):
		paths = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))
	var key := str(id)
	if not paths.has(key):
		return Painted.ui_symbol(id)
	if not textures.has(key):
		textures[key] = load(str(paths[key]))
	return textures[key] as Texture2D
