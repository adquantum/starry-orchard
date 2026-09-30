class_name EffectRowV2
extends Control
const Tokens=preload("res://scenes/battle_v2/ui/effect_tokens_v2.gd")
const Explanation=preload("res://scenes/battle_v2/ui/effect_tooltip_v2.gd")
const Icon=preload("res://scenes/battle_v2/ui/effect_icon_v2.gd")
const School=preload("res://scenes/battle_v2/ui/school_icon_v2.gd")
const Target=preload("res://scenes/battle_v2/ui/target_badge_v2.gd")
const Duration=preload("res://scenes/battle_v2/ui/duration_badge_v2.gd")
var data: Dictionary={}
var font: Font=Tokens.number_font()
var accent: Color
var hovered:=false
func setup(row: Dictionary) -> void:
	data=row;size=Vector2(Tokens.WIDTH,Tokens.HEIGHT)
	accent=Tokens.accent(str(data.school_icon).trim_prefix("school_"))
	tooltip_text=Explanation.describe(data)
	mouse_filter=Control.MOUSE_FILTER_PASS
	mouse_entered.connect(func():hovered=true;queue_redraw())
	mouse_exited.connect(func():hovered=false;queue_redraw())
	icon(School,"SchoolIcon",data.school_icon,36)
	icon(Icon,"EffectIcon",data.effect_icon,54)
	var target_x:=72.0
	if int(data.duration)>0 or int(data.repeat_count)>1 or str(data.qualifier)!="":
		var badge:=Duration.new();badge.name="DurationBadge";badge.position=Vector2(72,0);badge.size=Vector2(24,19)
		add_child(badge);badge.setup(data)
		badge.size.x=badge.text.length()*6.0+2.0
		target_x+=badge.size.x
	icon(Target,"TargetBadge",data.target_icon,target_x)
	queue_redraw()
func icon(script: Script,node_name: String,id: StringName,x: float) -> void:
	var glyph=script.new();glyph.name=node_name;glyph.position=Vector2(x,.5);glyph.size=Vector2.ONE*Tokens.ICON
	glyph.setup(id,accent);add_child(glyph)
func _draw() -> void:
	if data.is_empty():return
	if hovered:draw_style_box(hover_style(),Rect2(Vector2.ZERO,size))
	Tokens.draw_number(self,str(data.value),0,14,32,font)
func hover_style() -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=Color(accent,.06);return style
func _make_custom_tooltip(text: String) -> Object:return Explanation.panel(text)
