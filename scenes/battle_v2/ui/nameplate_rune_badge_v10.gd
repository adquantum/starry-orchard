extends RefCounted
const ROOT="res://assets/game/nameplate_runes_v10/"
const RUNE_SIZE=54.0
static var cache={}
static func glyph(id:StringName)->Texture2D:
	if not cache.has(id):
		var tex=load(ROOT+str(id)+".png") as Texture2D
		var atlas=AtlasTexture.new();atlas.atlas=tex;atlas.region=tex.get_image().get_used_rect();atlas.filter_clip=true
		cache[id]=atlas
	return cache[id]
static func draw(canvas:CanvasItem,id:StringName,school:String,left:float)->void:
	var tex=glyph(id)
	var scale_factor=RUNE_SIZE/maxf(tex.get_width(),tex.get_height())
	var extent=tex.get_size()*scale_factor
	var rect=Rect2(Vector2(left+30,45)-extent*.5,extent)
	canvas.draw_texture_rect(tex,rect,false)
	var badge_center=Vector2(minf(left+47,rect.end.x-3),minf(79,rect.end.y-3))
	var badge=Rect2(badge_center-Vector2(13,13),Vector2(26,26))
	canvas.draw_texture_rect(preload("res://scenes/battle_v2/ui/nameplate_painted_v9.gd").texture("badge_base"),badge,false)
	canvas.draw_texture_rect(preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd").ui_symbol(StringName("school_"+school)),badge,false)
