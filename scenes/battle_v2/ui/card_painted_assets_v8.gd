extends RefCounted
const SCHOOLS=["fire","ice","storm","life","death","myth","balance"]
static var cache: Dictionary={}
static func asset(name: String) -> Texture2D:
	if not cache.has(name):cache[name]=load("res://assets/game/card_polish_v8/"+name+".png")
	return cache[name]
# Explicit opt-in: existing registry/world symbols remain gold and unchanged.
static func ui_symbol(id: StringName) -> Texture2D:
	var school:=str(id).trim_prefix("school_badge_").trim_prefix("school_")
	if school in SCHOOLS:return asset("color_"+school)
	return ArtRegistryV2.texture(id)
static func gold_symbol(school: String) -> Texture2D:
	return asset("gold_"+school)
static func draw_rules(canvas: CanvasItem,rect: Rect2,school: String) -> void:
	if school in SCHOOLS:canvas.draw_texture_rect(asset("rules_"+school),rect,false)
