extends Button
const SkinUI = preload("res://scenes/battle_v2/ui/compact_battle_skin.gd")
const Painted = preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd")
var school := "ice"

func _ready() -> void:
	for state in ["normal","hover","pressed","disabled","focus"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	toggled.connect(func(_pressed: bool):queue_redraw())
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR

func _draw() -> void:
	var radius := minf(size.x,size.y)*0.46
	var center := size*0.5
	SkinUI.roundel(self,center,radius,Color("b4e9ff") if is_hovered() or button_pressed else Color("829bb1"))
	var texture := Painted.ui_symbol(StringName("school_"+school))
	if texture!=null:
		draw_texture_rect(texture,Rect2(center-Vector2.ONE*radius*0.7,Vector2.ONE*radius*1.4),false,Color(1,1,1,0.35 if disabled else 1.0))
	if button_pressed:draw_arc(center,radius+1,0,TAU,48,Color("e4dbb8"),1.5,true)
