extends RefCounted
const SCHOOLS=["fire","ice","storm","life","death","myth","balance"]
static var textures: Dictionary={}
static var masks: Dictionary={}
static func texture(school: String) -> Texture2D:
	if textures.has(school):return textures[school]
	var name: String=school if school in SCHOOLS else "balance"
	var result=load("res://assets/game/card_backplates_v7/"+name+".png") as Texture2D
	textures[school]=result
	return result
static func inset_texture(school: String) -> Texture2D:
	if masks.has(school):return masks[school]
	var source:=texture(school)
	var pixels:=source.get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	pixels.resize(256,256,Image.INTERPOLATE_LANCZOS)
	# Keep the Imagegen painting intact; blend only its outer edge into the lining.
	for y in pixels.get_height():
		for x in pixels.get_width():
			var p:=Vector2((x+.5)/256.0-.5,(y+.5)/256.0-.5)
			var edge:=1.0-smoothstep(.44,.50,maxf(absf(p.x),absf(p.y)))
			var color:=Color("393227").lerp(pixels.get_pixel(x,y),edge)
			color.a=1.0
			pixels.set_pixel(x,y,color)
	var result:=ImageTexture.create_from_image(pixels)
	masks[school]=result
	return result
static func draw_backplate(canvas: CanvasItem, rect: Rect2, school: String, _strength: float) -> void:
	canvas.draw_rect(rect,Color("393227"))
	canvas.draw_texture_rect(inset_texture(school),rect,false)
