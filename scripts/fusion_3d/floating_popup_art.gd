extends RefCounted

const Painted = preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd")
const CardSymbols = preload("res://scenes/battle_v2/ui/card_description_symbols_v1.gd")
static var cached_textures: Dictionary = {}

static func texture(asset_id: StringName) -> Texture2D:
	if cached_textures.has(asset_id): return cached_textures[asset_id]
	var source: Texture2D = Painted.ui_symbol(asset_id) if str(asset_id).begins_with("school_") else CardSymbols.texture(asset_id)
	if source == null: return null
	var result: Texture2D = source
	var pixels := source.get_image()
	if pixels != null:
		var bounds := pixels.get_used_rect()
		if bounds.has_area() and Vector2(bounds.size) != source.get_size():
			var cropped := AtlasTexture.new()
			cropped.atlas = source
			cropped.region = Rect2(bounds)
			result = cropped
	cached_textures[asset_id] = result
	return result
