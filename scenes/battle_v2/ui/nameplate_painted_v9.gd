extends RefCounted
const ROOT="res://assets/game/nameplate_v9/"
const SAMPLE_ONLY=false
static var textures={}
static var frames={}
static func texture(id:String)->Texture2D:
	if not textures.has(id):textures[id]=load(ROOT+id+".png")
	return textures[id]
static func nine(canvas:CanvasItem,id:String,rect:Rect2,margins:Vector4)->void:
	if not frames.has(id):
		var box=StyleBoxTexture.new();box.texture=texture(id)
		box.texture_margin_left=margins.x;box.texture_margin_top=margins.y;box.texture_margin_right=margins.z;box.texture_margin_bottom=margins.w
		frames[id]=box
	canvas.draw_style_box(frames[id],rect)
static func enabled(school:String)->bool:return not SAMPLE_ONLY or school=="fire"
static func panel(canvas:CanvasItem,rect:Rect2,school:String)->void:
	canvas.draw_texture_rect(texture("base_"+school),rect.grow(-12),false)
	nine(canvas,"frame",rect,Vector4(24,15,24,15))
static func health(canvas:CanvasItem,rect:Rect2,ratio:float)->void:
	health_piece(canvas,"hp_trough",rect)
	if ratio>0:
		var fill=texture("hp_fill")
		canvas.draw_texture_rect_region(fill,Rect2(rect.position,Vector2(rect.size.x*ratio,rect.size.y)),Rect2(Vector2.ZERO,Vector2(fill.get_width()*ratio,fill.get_height())))
	health_piece(canvas,"hp_frame",rect)
static func socket(canvas:CanvasItem,at:Vector2,shadow:bool=false)->void:
	var extent=14.0 if shadow else 13.0
	canvas.draw_texture_rect(texture("shadow_socket" if shadow else "socket"),Rect2(at-Vector2.ONE*extent*.5,Vector2.ONE*extent),false)

static func health_piece(canvas:CanvasItem,id:String,rect:Rect2)->void:
	var tex=texture(id)
	var sx=[0.0,12.0,244.0,256.0]
	var sy=[0.0,10.0,22.0,32.0]
	var tx=[rect.position.x,rect.position.x+4,rect.end.x-4,rect.end.x]
	var ty=[rect.position.y,rect.position.y+1,rect.end.y-1,rect.end.y]
	for y in 3:
		for x in 3:
			canvas.draw_texture_rect_region(tex,Rect2(tx[x],ty[y],tx[x+1]-tx[x],ty[y+1]-ty[y]),Rect2(sx[x],sy[y],sx[x+1]-sx[x],sy[y+1]-sy[y]))
