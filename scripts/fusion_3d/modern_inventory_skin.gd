extends RefCounted
const INK=Color("e5effa")
const MUTED=Color("92a9c3")
const ACCENT=Color("84dcff")
const ICONS=["cards","equipment","appearance","personal","shop","weapon","hat","boots","back","hair","dye","all"]
static func panel(color: Color=Color("142336"),border: Color=Color("30465e"),padding: float=12.0) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=color;box.border_color=border
	box.set_border_width_all(1);box.set_corner_radius_all(12);box.set_content_margin_all(padding)
	return box
static func icon(id: String) -> Texture2D:
	var index:=ICONS.find(id)
	if index<0:index=11
	var source: Texture2D=load("res://assets/ui/modern_inventory/navigation_atlas_v1.png")
	var cell:=source.get_size()/Vector2(4,3)
	var result:=AtlasTexture.new();result.atlas=source
	result.region=Rect2(Vector2(index%4,index/4)*cell,cell);result.filter_clip=true
	return result
static func button(node: Button,id: String="") -> void:
	node.custom_minimum_size.y=maxf(node.custom_minimum_size.y,42);node.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	if not id.is_empty():node.icon=icon(id);node.expand_icon=true;node.add_theme_constant_override("icon_max_width",34)
	for state in ["normal","hover","pressed","disabled","focus"]:
		node.add_theme_stylebox_override(state,panel(Color("24445d") if state=="pressed" else Color("1e354b") if state=="hover" else Color("142336"),ACCENT if state in ["pressed","focus"] else Color("30465e"),8))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:node.add_theme_color_override(state,INK)
	node.add_theme_color_override("font_disabled_color",Color("61738a"))
static func make_theme() -> Theme:
	var result:=Theme.new();result.default_font_size=17
	for type in ["Label","Button","TabBar","LineEdit","SpinBox","CheckBox"]:
		for key in ["font_color","font_hover_color","font_pressed_color","font_selected_color","font_focus_color"]:result.set_color(key,type,INK)
		result.set_color("font_disabled_color",type,MUTED)
	for type in ["Button","TabBar"]:
		for state in ["normal","hover","pressed","disabled","focus","tab_unselected","tab_selected","tab_hovered","tab_focus"]:
			result.set_stylebox(state,type,panel(Color("24445d") if state in ["pressed","tab_selected"] else Color("142336"),ACCENT if state in ["pressed","tab_selected","focus","tab_focus"] else Color("30465e"),9))
	result.set_stylebox("normal","LineEdit",panel());result.set_stylebox("focus","LineEdit",panel(Color("142336"),ACCENT))
	result.set_color("font_placeholder_color","LineEdit",MUTED)
	return result
