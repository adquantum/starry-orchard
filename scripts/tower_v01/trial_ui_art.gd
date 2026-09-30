extends RefCounted
## Generated image assets for the tower UI. Every scalable surface uses
## StyleBoxTexture nine-slice margins; text remains native Godot UI.
const ROOT := "res://assets/game/tower_v02_ui/"
static var cache: Dictionary={}
const TRAIT_HINTS := {
	"fire":["持续伤害后选择引爆时机","刃与陷阱准备后集中爆发"],
	"ice":["盾挡关键攻击后反击","虚弱压制并积累高费终结"],
	"storm":["廉价攻击优先削减威胁","防护蓄豆后打出重击"],
	"myth":["主动拆除防护再突击","多段攻击分解护盾"],
	"life":["提前铺设持续治疗并进攻","即时治疗转化有限防护"],
	"death":["虚弱与吸血保持血线","真实自损换豆后吸血回收"],
	"balance":["刃陷阱与资源牌调度","主副系交替形成增幅"],
}

static func texture(path: String) -> Texture2D:
	if cache.has(path):return cache[path]
	var image:=Image.load_from_file(ROOT+path)
	if image==null:return null
	var result:=ImageTexture.create_from_image(image);cache[path]=result;return result

static func _style(path: String, margins: Vector4, content := Vector4(22,16,22,16), tile := true) -> StyleBoxTexture:
	var box:=StyleBoxTexture.new()
	box.texture=texture(path)
	box.set_texture_margin(SIDE_LEFT,margins.x)
	box.set_texture_margin(SIDE_TOP,margins.y)
	box.set_texture_margin(SIDE_RIGHT,margins.z)
	box.set_texture_margin(SIDE_BOTTOM,margins.w)
	# Decorative borders and textured centers keep their authored texel scale.
	# TILE_FIT only adjusts the final partial repeat, avoiding a single long stretch.
	box.axis_stretch_horizontal=StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT if tile else StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.axis_stretch_vertical=StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT if tile else StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	box.content_margin_left=content.x;box.content_margin_top=content.y
	box.content_margin_right=content.z;box.content_margin_bottom=content.w
	return box

static func panel_style() -> StyleBoxTexture:
	return _style("source/refined_panel_9slice.png",Vector4(112,112,112,112),Vector4(96,108,96,104))

static func flat_panel(color: Color=Color("10263be6"), border:=Color("6f91aa"), radius:=10, content:=16) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=color;box.border_color=border;box.set_border_width_all(1);box.set_corner_radius_all(radius)
	box.content_margin_left=content;box.content_margin_top=content;box.content_margin_right=content;box.content_margin_bottom=content
	return box

static func tooltip_style() -> StyleBoxFlat:
	return flat_panel(Color("0d2134ed"),Color("66869e"),10,14)

static func _button_style(color: Color, border: Color, pressed:=false) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=color;box.border_color=border;box.set_border_width_all(1 if not pressed else 2);box.set_corner_radius_all(8)
	box.content_margin_left=18;box.content_margin_right=18;box.content_margin_top=11;box.content_margin_bottom=11
	if not pressed:box.shadow_color=Color("00000055");box.shadow_size=3;box.shadow_offset=Vector2(0,2)
	return box

static func apply_button(value: Button, secondary := false) -> void:
	if secondary:
		value.add_theme_stylebox_override("normal",_button_style(Color("13283bd9"),Color("55738a")))
		value.add_theme_stylebox_override("hover",_button_style(Color("1d3a52ef"),Color("9fc1cf")))
		value.add_theme_stylebox_override("pressed",_button_style(Color("0b1e2eea"),Color("c5e8ee"),true))
	else:
		value.add_theme_stylebox_override("normal",_button_style(Color("245172f2"),Color("c69b49")))
		value.add_theme_stylebox_override("hover",_button_style(Color("32749af7"),Color("f1ce78")))
		value.add_theme_stylebox_override("pressed",_button_style(Color("173f5beF"),Color("fff0b0"),true))
	value.add_theme_stylebox_override("focus",_button_style(Color("284e68ef"),Color("dff7ff"),true))
	value.add_theme_stylebox_override("disabled",_button_style(Color("172531aa"),Color("425464")))
	value.add_theme_color_override("font_color",Color("fff2ca"))
	value.add_theme_color_override("font_hover_color",Color.WHITE)
	value.add_theme_color_override("font_pressed_color",Color("c9f4ff"))
	value.add_theme_color_override("font_disabled_color",Color("8799a9"))
	value.add_theme_font_size_override("font_size",18)
	value.custom_minimum_size.y=maxf(value.custom_minimum_size.y,54)

static func relic(id: String) -> Texture2D:
	return texture("relics/"+id+".png")

static func trait_icon(school: String, branch: String) -> Texture2D:
	return texture("traits/%s_%s.png" % [school,branch])

static func _framed(frame_path: String, icon_path: String) -> Texture2D:
	var key:="framed:"+frame_path+":"+icon_path
	if cache.has(key):return cache[key]
	var frame:=Image.load_from_file(ROOT+frame_path);var image:=Image.load_from_file(ROOT+icon_path)
	if frame==null or image==null:return null
	frame.resize(256,256,Image.INTERPOLATE_LANCZOS);image.resize(196,196,Image.INTERPOLATE_LANCZOS)
	frame.blend_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i(30,30))
	var result:=ImageTexture.create_from_image(frame);cache[key]=result;return result

static func framed_relic(id: String) -> Texture2D:
	return _framed("ui/relic_socket.png","relics/"+id+".png")

static func framed_trait(school: String, branch: String) -> Texture2D:
	return _framed("ui/icon_socket.png","traits/%s_%s.png" % [school,branch])

static func progress(active: bool) -> Texture2D:
	return texture("ui/node_active.png" if active else "ui/node_inactive.png")

static func icon(texture_value: Texture2D, size: Vector2, parent: Node) -> TextureRect:
	var view:=TextureRect.new();view.texture=texture_value;view.custom_minimum_size=size
	view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(view);return view
