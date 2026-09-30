extends Control

signal pressed
signal button_down
signal button_up
signal layout_selected(control: Control)
signal layout_changed(control: Control)

var touch_id := -1
var mouse_active := false
var edit_mode := false
var selected := false
var icon: TextureRect
var caption: Label
var symbol := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	icon = TextureRect.new()
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	caption = Label.new()
	caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -25.0
	caption.offset_bottom = -2.0
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color("fff3d6"))
	caption.add_theme_color_override("font_shadow_color", Color("07111bd9"))
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(caption)
	queue_redraw()


func set_icon(texture: Texture2D) -> void:
	if not is_instance_valid(icon):
		await ready
	icon.texture = texture


func set_caption(value: String) -> void:
	if not is_instance_valid(caption):
		await ready
	caption.text = value


func set_symbol(value: String) -> void:
	symbol = value
	queue_redraw()


func is_held() -> bool:
	return touch_id >= 0 or mouse_active


func cancel_press() -> void:
	var was_held := is_held()
	touch_id = -1
	mouse_active = false
	if was_held and not edit_mode:
		button_up.emit()


func set_editing(value: bool) -> void:
	edit_mode = value
	selected = false
	touch_id = -1
	mouse_active = false
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Android also emits an emulated mouse click for this same touch.
	if event is InputEventMouse and event.device == -1:
		accept_event()
		return
	if event is InputEventScreenTouch:
		if event.pressed and touch_id < 0:
			touch_id = event.index
			if edit_mode:
				layout_selected.emit(self)
			else:
				button_down.emit()
			accept_event()
		elif not event.pressed and event.index == touch_id:
			touch_id = -1
			if edit_mode:
				layout_changed.emit(self)
			else:
				button_up.emit()
				if Rect2(Vector2.ZERO, size).has_point(event.position):
					pressed.emit()
			accept_event()
	elif event is InputEventScreenDrag and event.index == touch_id:
		if edit_mode:
			position += event.relative
			_clamp_to_parent()
			layout_changed.emit(self)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			mouse_active = true
			if edit_mode:
				layout_selected.emit(self)
			else:
				button_down.emit()
		else:
			mouse_active = false
			if edit_mode:
				layout_changed.emit(self)
			else:
				button_up.emit()
				if Rect2(Vector2.ZERO, size).has_point(event.position):
					pressed.emit()
		accept_event()
	elif event is InputEventMouseMotion and mouse_active and edit_mode and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		position += event.relative
		_clamp_to_parent()
		layout_changed.emit(self)
		accept_event()


func _clamp_to_parent() -> void:
	var bounds := get_parent_control().size if get_parent_control() else get_viewport_rect().size
	position.x = clampf(position.x, 0.0, maxf(0.0, bounds.x - size.x))
	position.y = clampf(position.y, 0.0, maxf(0.0, bounds.y - size.y))


func _draw() -> void:
	if symbol == "chat":
		var center := size * Vector2(0.5, 0.43)
		var radius := minf(size.x, size.y) * 0.36
		draw_circle(center, radius + 5.0, Color("1022369e"))
		draw_arc(center, radius, 0.0, TAU, 48, Color("e8d49bd9"), 3.0, true)
		var bubble := Rect2(center - Vector2(radius * 0.52, radius * 0.34), Vector2(radius * 1.04, radius * 0.68))
		draw_style_box(_chat_style(), bubble)
		var tail := PackedVector2Array([bubble.position + Vector2(radius * 0.20, bubble.size.y), bubble.position + Vector2(radius * 0.08, bubble.size.y + radius * 0.23), bubble.position + Vector2(radius * 0.43, bubble.size.y)])
		draw_colored_polygon(tail, Color("fff3d6dd"))
	if edit_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color("ffde86") if selected else Color("8fdcff"), false, 4.0)


func _chat_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("00000000")
	style.border_color = Color("fff3d6dd")
	style.set_border_width_all(3)
	style.set_corner_radius_all(7)
	return style
