extends Node
## Cursor capture is a preference, separate from temporary UI suspension.
var world: Node3D
var look_mode := false
var was_blocked := false
var focused := true
var drag_buttons := 0
var drag_origin := Vector2.ZERO
var reminder: Label

func setup(value: Node3D) -> void:
	world = value
	var layer := CanvasLayer.new()
	layer.layer = 36
	add_child(layer)
	reminder = Label.new()
	reminder.name = "CameraModeHint"
	reminder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	reminder.offset_left = 22
	reminder.offset_top = -25
	reminder.offset_right = 740
	reminder.offset_bottom = -3
	reminder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reminder.add_theme_font_size_override("font_size", 16)
	reminder.add_theme_color_override("font_shadow_color", Color.BLACK)
	reminder.add_theme_constant_override("shadow_offset_x", 1)
	reminder.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(reminder)

func blocked() -> bool:
	if not is_instance_valid(world) or not world.ready_world or world.input_suspended:return true
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit

func _process(_delta: float) -> void:
	if not is_instance_valid(world):return
	if is_instance_valid(world.mobile_input):
		reminder.hide()
		return
	var editor := world.get_node_or_null("CreativeMode")
	if editor != null and editor.enabled:
		reminder.hide()
		return
	var suspended := blocked()
	if suspended:
		drag_buttons = 0
	elif was_blocked:
		# Closing chat, menus or a battle resumes looking without a second Ctrl.
		look_mode = true
	was_blocked = suspended
	_apply_capture()
	reminder.visible = world.ready_world and world.is_visible_in_tree() and not is_instance_valid(world.mobile_input)
	var atlas := world.get_parent()
	if atlas != null and "encounters" in atlas and atlas.encounters != null and atlas.encounters.active:
		reminder.hide()
	reminder.text = "Ctrl 切换视角 / 鼠标模式 · 当前：%s · 鼠标模式按住左键或右键拖动视角" % ("视角" if look_mode and not suspended else "鼠标")

func _apply_capture() -> void:
	var mode := Input.MOUSE_MODE_CAPTURED if focused and not blocked() and (look_mode or drag_buttons != 0) else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != mode:Input.mouse_mode = mode

func handle_event(event: InputEvent) -> void:
	if blocked() or not focused or is_instance_valid(world.mobile_input):return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_CTRL:
			look_mode = not look_mode
			drag_buttons = 0
			_apply_capture()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			look_mode = false
			drag_buttons = 0
			_apply_capture()
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and not look_mode:
		if drag_buttons == 0:drag_origin = event.position
		drag_buttons |= 1 << event.button_index
		_apply_capture()
	if event is InputEventMouseMotion and look_mode and drag_buttons == 0:
		_rotate(event.relative)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT] and drag_buttons != 0:
		drag_buttons &= ~(1 << event.button_index)
		_apply_capture()
		if drag_buttons == 0 and not look_mode:Input.warp_mouse(drag_origin)
	elif event is InputEventMouseMotion and drag_buttons != 0 and not blocked():
		_rotate(event.relative)
		get_viewport().set_input_as_handled()

func _rotate(relative: Vector2) -> void:
	world.yaw -= relative.x * 0.003
	world.pitch = clampf(world.pitch - relative.y * 0.003, -1.1, 1.1)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		drag_buttons = 0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
