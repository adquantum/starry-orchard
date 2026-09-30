extends RefCounted
const BASE="res://assets/ui/academy_frontend/"
static func icon(id: String) -> Texture2D:
	return load(BASE+"icons/"+id+".png")
static func panel(_fill: Color=Color("514538"),_edge: Color=Color("9d8355")) -> StyleBoxTexture:
	var s=StyleBoxTexture.new()
	s.texture=load(BASE+"nine_slice_v2/panel_frame.png")
	s.texture_margin_left=92;s.texture_margin_right=92;s.texture_margin_top=92;s.texture_margin_bottom=92
	s.content_margin_left=52;s.content_margin_right=52;s.content_margin_top=48;s.content_margin_bottom=48
	return s
static func button_style(bright: bool=false,padding: float=34.0) -> StyleBoxTexture:
	var s=StyleBoxTexture.new()
	s.texture=load(BASE+"nine_slice_v2/"+("button_hover" if bright else "button")+".png")
	s.texture_margin_left=105;s.texture_margin_right=105;s.texture_margin_top=26;s.texture_margin_bottom=26
	s.content_margin_left=padding;s.content_margin_right=padding;s.content_margin_top=15;s.content_margin_bottom=15
	return s
static func input_style(fill: Color,edge: Color) -> StyleBoxFlat:
	var s:=StyleBoxFlat.new();s.bg_color=fill;s.border_color=edge;s.set_border_width_all(2);s.set_corner_radius_all(10)
	s.content_margin_top=11;s.content_margin_bottom=11;s.content_margin_left=18;s.content_margin_right=18
	return s
static func make_theme() -> Theme:
	var t=preload("res://scripts/fusion_3d/academy_ui.gd").make_theme()
	t.default_font_size=20
	for type in ["Button","OptionButton"]:
		t.set_stylebox("normal",type,button_style())
		t.set_stylebox("hover",type,button_style(true))
		t.set_stylebox("pressed",type,button_style(true))
		t.set_stylebox("disabled",type,button_style())
		t.set_stylebox("focus",type,StyleBoxEmpty.new())
		t.set_color("font_color",type,Color("f3e5c8"))
		t.set_color("font_hover_color",type,Color.WHITE)
		t.set_color("font_focus_color",type,Color("fff0bd"))
		t.set_color("font_pressed_color",type,Color("fff0bd"))
	t.set_stylebox("panel","PanelContainer",panel())
	for state in ["normal","read_only"]:t.set_stylebox(state,"LineEdit",button_style(false,96))
	t.set_stylebox("focus","LineEdit",button_style(true,96))
	t.set_color("font_color","LineEdit",Color("f1e6cf"))
	t.set_color("font_placeholder_color","LineEdit",Color("a5b5b5"))
	t.set_color("font_color","Label",Color("ede2cc"))
	t.set_stylebox("panel","PopupMenu",panel())
	t.set_stylebox("hover","PopupMenu",panel(Color("234a45")))
	t.set_stylebox("panel","TooltipPanel",panel())
	t.set_color("font_color","TooltipLabel",Color("f9e8bf"))
	t.set_constant("separation","VBoxContainer",12)
	t.set_constant("separation","HBoxContainer",14)
	return t
