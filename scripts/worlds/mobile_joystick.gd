extends Control

signal vector_changed(value: Vector2)
signal layout_selected(control: Control)
signal layout_changed(control: Control)

var value := Vector2.ZERO
var touch_id := -1
var mouse_active := false
var edit_mode := false
var selected := false
var radius := 98.0
var knob_radius := 39.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(270, 270)
	resized.connect(_update_geometry)
	_update_geometry()
	queue_redraw()

func set_editing(value: bool) -> void:
	edit_mode=value;selected=false;touch_id=-1;mouse_active=false;reset();queue_redraw()
func set_selected(value: bool) -> void:selected=value;queue_redraw()
func _update_geometry() -> void:
	var side:=minf(size.x,size.y)
	radius=side*0.36;knob_radius=side*0.145;queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_id < 0:
			touch_id = event.index
			if edit_mode:layout_selected.emit(self)
			else:_set_from_position(event.position)
			accept_event()
		elif not event.pressed and event.index == touch_id:
			touch_id=-1
			if edit_mode:layout_changed.emit(self)
			else:reset()
			accept_event()
	elif event is InputEventScreenDrag and event.index == touch_id:
		if edit_mode:
			position+=event.relative;_clamp_to_parent();layout_changed.emit(self)
		else:_set_from_position(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_active=true
			if edit_mode:layout_selected.emit(self)
			else:touch_id=-2;_set_from_position(event.position)
		else:
			mouse_active=false
			if edit_mode:layout_changed.emit(self)
			else:reset()
		accept_event()
	elif event is InputEventMouseMotion and mouse_active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if edit_mode:
			position+=event.relative;_clamp_to_parent();layout_changed.emit(self)
		else:_set_from_position(event.position)
		accept_event()

func _clamp_to_parent() -> void:
	var bounds:=get_parent_control().size if get_parent_control() else get_viewport_rect().size
	position.x=clampf(position.x,0.0,maxf(0.0,bounds.x-size.x))
	position.y=clampf(position.y,0.0,maxf(0.0,bounds.y-size.y))

func _set_from_position(at: Vector2) -> void:
	var center := size * 0.5
	var delta := at - center
	value = delta.limit_length(radius) / radius
	if value.length() < 0.08:
		value = Vector2.ZERO
	vector_changed.emit(value)
	queue_redraw()

func reset() -> void:
	touch_id = -1
	value = Vector2.ZERO
	vector_changed.emit(value)
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	draw_circle(center, radius + 13.0, Color("10223686"))
	draw_arc(center, radius + 5.0, 0.0, TAU, 64, Color("e4c881a8"), 3.0, true)
	draw_circle(center, radius - 10.0, Color("46677b4f"))
	draw_circle(center + value * radius, knob_radius + 6.0, Color("0a1724a8"))
	draw_circle(center + value * radius, knob_radius, Color("e8d49bd9"))
	draw_arc(center + value * radius, knob_radius, 0.0, TAU, 40, Color("fff3d6e8"), 2.0, true)
	if edit_mode:draw_rect(Rect2(Vector2.ZERO,size),Color("ffde86") if selected else Color("8fdcff"),false,4.0)
