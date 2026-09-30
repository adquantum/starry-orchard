extends "res://scenes/battle_v2/ui/compact_school_button.gd"
const SchoolButton = preload("res://scenes/battle_v2/ui/compact_school_button.gd")
const SCHOOLS = ["fire","ice","storm","myth","life","death","balance"]
const NAMES = ["火焰","冰霜","风暴","神话","生命","亡灵","平衡"]
# Clockwise from the top: balance, death, life, myth, ice, fire, storm.
# Preserve source indices so the selected school sent to the server never changes.
const RADIAL_SLOTS = [5,4,6,3,2,1,0]
var source: OptionButton
var choices: Panel
var school_buttons: Array[Button] = []
var last_index := -1
var last_disabled := false
var expanded := false
var expansion := 0.0
var expansion_tween: Tween

func _ready() -> void:
	super._ready()
	choices=Panel.new();choices.name="SchoolChoices"
	choices.position=Vector2(-94,-94);choices.size=Vector2(272,272)
	choices.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	choices.mouse_filter=Control.MOUSE_FILTER_IGNORE
	choices.z_index=-1
	add_child(choices);choices.hide()
	for index in 7:
		var pick := SchoolButton.new()
		pick.school=SCHOOLS[index];pick.toggle_mode=true
		pick.position=Vector2(136,136)+Vector2.from_angle(-PI/2+TAU*RADIAL_SLOTS[index]/7.0)*100-Vector2(31,31);pick.size=Vector2(62,62)
		pick.pivot_offset=Vector2(31,31)
		pick.tooltip_text=NAMES[index]+"学院豆"
		choices.add_child(pick);school_buttons.append(pick)
		pick.pressed.connect(_choose.bind(index))
	pressed.connect(func():
		if not disabled:_set_expanded(not expanded))
	visibility_changed.connect(func():
		if not is_visible_in_tree():_reset_expansion())
	_apply_expansion(0.0)

func sync() -> void:
	if not is_instance_valid(source):return
	disabled=source.disabled
	var index := clampi(source.selected,0,6)
	if last_index!=index or last_disabled!=disabled:
		school=SCHOOLS[index]
		tooltip_text="下轮学院豆："+NAMES[index]+" · 点击展开七学院"
		for i in school_buttons.size():school_buttons[i].set_pressed_no_signal(i==index);school_buttons[i].queue_redraw()
		last_index=index;last_disabled=disabled;queue_redraw()
	if disabled:_set_expanded(false)

func _draw() -> void:
	var glow := sin(clampf(expansion,0.0,1.0)*PI)
	var center := size*0.5
	if glow>0.01:
		draw_arc(center,38.0+expansion*19.0,0,TAU,64,Color("d4be86",glow*0.42),1.5,true)
		for slot in 7:
			var radial := Vector2.from_angle(-PI/2+TAU*slot/7.0)
			var end := center+radial*(100.0*expansion)
			draw_line(end-radial*18.0*glow,end,Color("dce9ef",glow*0.40),1.6,true)
	super._draw()
	var at := size*0.5+Vector2(0,30)
	var direction := 1.0 if expanded else -1.0
	draw_polyline(PackedVector2Array([at+Vector2(-4,-direction*2),at+Vector2(0,direction*2),at+Vector2(4,-direction*2)]),Color("b5c9d8"),1.5,true)

func _choose(index: int) -> void:
	if disabled or not is_instance_valid(source) or source.disabled:return
	source.select(index)
	source.item_selected.emit(index)
	_set_expanded(false);sync()

func _input(event: InputEvent) -> void:
	if not choices.visible:return
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		_set_expanded(false);get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if not choices.get_global_rect().has_point(event.position) and not get_global_rect().has_point(event.position):_set_expanded(false)

func _set_expanded(value: bool) -> void:
	if expanded==value:return
	expanded=value
	if expansion_tween!=null and expansion_tween.is_valid():expansion_tween.kill()
	choices.show()
	# Closing controls stop accepting clicks immediately; opening controls wait until settled.
	_apply_expansion(expansion)
	var duration := (0.34 if value else 0.26)*maxf(0.35,absf((1.0 if value else 0.0)-expansion))
	expansion_tween=create_tween()
	expansion_tween.tween_method(_apply_expansion,expansion,1.0 if value else 0.0,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT if value else Tween.EASE_IN_OUT)
	expansion_tween.tween_callback(func():
		if not expanded:choices.hide())

func _apply_expansion(value: float) -> void:
	expansion=value
	for index in school_buttons.size():
		var pick := school_buttons[index]
		var radial := Vector2.from_angle(-PI/2+TAU*RADIAL_SLOTS[index]/7.0)*100.0
		pick.position=Vector2(105,105)+radial*value
		pick.scale=Vector2.ONE*lerpf(0.30,1.0,value)
		pick.modulate.a=value
		pick.mouse_filter=Control.MOUSE_FILTER_STOP if expanded and value>=0.99 else Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _reset_expansion() -> void:
	if expansion_tween!=null and expansion_tween.is_valid():expansion_tween.kill()
	expanded=false
	_apply_expansion(0.0)
	choices.hide()
