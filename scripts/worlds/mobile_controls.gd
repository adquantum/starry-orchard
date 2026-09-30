extends CanvasLayer

const Joystick = preload("res://scripts/worlds/mobile_joystick.gd")
const TouchIcon = preload("res://scripts/worlds/mobile_touch_icon.gd")
const ICONS := {
	"sprint": preload("res://assets/ui/mobile_controls/sprint.png"),
	"jump": preload("res://assets/ui/mobile_controls/jump.png"),
	"bag": preload("res://assets/ui/mobile_controls/bag.png"),
	"wardrobe": preload("res://assets/ui/mobile_controls/wardrobe.png"),
	"bestiary": preload("res://assets/ui/mobile_controls/bestiary.png"),
	"map": preload("res://assets/ui/mobile_controls/map.png"),
	"layout": preload("res://assets/ui/mobile_controls/layout.png"),
	"reset": preload("res://assets/ui/mobile_controls/reset.png"),
}
const LAYOUT_PATH := "user://mobile_control_layout.cfg"
const TWO_FINGER_TAP_MS := 450
const TWO_FINGER_MOVE_LIMIT := 28.0

var atlas: Node
var world: Node3D
var root: Control
var movement_group: Control
var joystick: Control
var jump_button: Control
var sprint_button: Control
var editor_panel: PanelContainer
var editor_label: Label
var controls := {}
var move_vector := Vector2.ZERO
var jump_pressed := false
var sprint_pressed := false
var look_touch := -1
var layout_edit_mode := false
var selected_control: Control
var touch_points := {}

var defaults := {
	"joystick": {"name": "摇杆", "center": Vector2(0.13, 0.79), "size": Vector2(270, 270), "scale": 1.18},
	"sprint": {"name": "加速", "center": Vector2(0.83, 0.83), "size": Vector2(126, 126), "scale": 1.0},
	"jump": {"name": "跳跃", "center": Vector2(0.935, 0.80), "size": Vector2(138, 138), "scale": 1.08},
	"chat": {"name": "聊天", "center": Vector2(0.69, 0.063), "size": Vector2(82, 82), "scale": 1.0},
	"bag": {"name": "背包/卡组", "center": Vector2(0.745, 0.063), "size": Vector2(82, 82), "scale": 1.0},
	"wardrobe": {"name": "衣橱", "center": Vector2(0.80, 0.063), "size": Vector2(82, 82), "scale": 1.0},
	"bestiary": {"name": "图鉴", "center": Vector2(0.855, 0.063), "size": Vector2(82, 82), "scale": 1.0},
	"map": {"name": "地图", "center": Vector2(0.91, 0.063), "size": Vector2(82, 82), "scale": 1.0},
	"layout": {"name": "布局", "center": Vector2(0.965, 0.063), "size": Vector2(82, 82), "scale": 1.0},
}
var layout := {}


static func should_enable() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("mobile_lite") or "--mobile-preview" in OS.get_cmdline_user_args()


func setup(owner_atlas: Node) -> void:
	atlas = owner_atlas
	layer = 45
	_build_ui()


func bind_world(value: Node3D) -> void:
	world = value
	if is_instance_valid(world):
		world.mobile_input = self


func _build_ui() -> void:
	root = Control.new()
	root.name = "MobileTouchControls"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	movement_group = Control.new()
	movement_group.name = "MovementControls"
	movement_group.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	movement_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(movement_group)

	joystick = Joystick.new()
	joystick.name = "MovementJoystick"
	joystick.vector_changed.connect(func(value: Vector2): move_vector = value)
	_register_control("joystick", joystick, movement_group)

	sprint_button = _icon_control("sprint", movement_group, _sprint_pressed)
	sprint_button.button_down.connect(_sprint_down)
	sprint_button.button_up.connect(_sprint_up)
	jump_button = _icon_control("jump", movement_group, _jump_pressed)
	jump_button.button_down.connect(_jump_down)
	jump_button.button_up.connect(_jump_up)

	_icon_control("chat", root, func(): atlas.world_chat.toggle_input(), null, "chat")
	_icon_control("bag", root, func(): atlas.game_menu.toggle())
	_icon_control("wardrobe", root, atlas.toggle_wardrobe)
	_icon_control("bestiary", root, atlas.toggle_character_library)
	_icon_control("map", root, func(): atlas.player_minimap.set_expanded(not atlas.player_minimap.expanded))
	_icon_control("layout", root, _open_layout_editor)
	_build_editor()

	layout = defaults.duplicate(true)
	_load_layout()
	_apply_layout()
	root.resized.connect(_apply_layout)


func _register_control(id: String, control: Control, parent: Control) -> void:
	control.set_meta("mobile_layout_id", id)
	control.tooltip_text = str(defaults[id]["name"])
	control.layout_selected.connect(_select_control)
	control.layout_changed.connect(_remember_control)
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(control)
	controls[id] = control


func _icon_control(id: String, parent: Control, callback: Callable, texture: Texture2D = null, symbol: String = "") -> Control:
	var button := TouchIcon.new()
	button.name = id.capitalize() + "TouchButton"
	button.set_icon(null if not symbol.is_empty() else (texture if texture != null else ICONS[id]))
	button.set_symbol(symbol)
	button.set_caption(str(defaults[id]["name"]))
	if callback.is_valid():
		button.pressed.connect(callback)
	_register_control(id, button, parent)
	return button


func _build_editor() -> void:
	editor_panel = PanelContainer.new()
	editor_panel.name = "MobileLayoutEditor"
	editor_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	editor_panel.offset_left = -310
	editor_panel.offset_right = 310
	editor_panel.offset_top = 112
	editor_panel.offset_bottom = 190
	editor_panel.visible = false
	editor_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("102236eb")
	panel_style.border_color = Color("e4c881")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(18)
	panel_style.content_margin_left = 18
	panel_style.content_margin_right = 18
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	editor_panel.add_theme_stylebox_override("panel", panel_style)
	root.add_child(editor_panel)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	editor_panel.add_child(row)
	editor_label = Label.new()
	editor_label.text = "拖动图标调整位置"
	editor_label.add_theme_font_size_override("font_size", 22)
	row.add_child(editor_label)
	_editor_button(row, "－", func(): _resize_selected(0.90))
	_editor_button(row, "＋", func(): _resize_selected(1.10))
	var reset := TouchIcon.new()
	reset.custom_minimum_size = Vector2(52, 52)
	reset.set_icon(ICONS["reset"])
	reset.tooltip_text = "恢复默认布局"
	reset.pressed.connect(_reset_layout)
	row.add_child(reset)
	_editor_button(row, "完成", _finish_layout_editor)


func _editor_button(parent: Control, title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(76, 52)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(callback)
	parent.add_child(button)


func _load_layout() -> void:
	var config := ConfigFile.new()
	if config.load(LAYOUT_PATH) != OK:
		return
	for id in defaults:
		var saved_center: Variant = config.get_value("controls", id + "_center", defaults[id]["center"])
		var saved_scale: float = float(config.get_value("controls", id + "_scale", defaults[id]["scale"]))
		layout[id]["center"] = saved_center if saved_center is Vector2 else defaults[id]["center"]
		layout[id]["scale"] = clampf(saved_scale, 0.65, 1.75)


func _save_layout() -> void:
	var config := ConfigFile.new()
	for id in layout:
		config.set_value("controls", id + "_center", layout[id]["center"])
		config.set_value("controls", id + "_scale", layout[id]["scale"])
	config.save(LAYOUT_PATH)


func _apply_layout() -> void:
	if not is_instance_valid(root) or root.size.x <= 0.0 or root.size.y <= 0.0:
		return
	for id in controls:
		var control: Control = controls[id]
		var item: Dictionary = layout[id]
		var target_size: Vector2 = item["size"] * float(item["scale"])
		control.size = target_size
		control.position = item["center"] * root.size - target_size * 0.5
		_clamp_control(control)


func _clamp_control(control: Control) -> void:
	control.position.x = clampf(control.position.x, 0.0, maxf(0.0, root.size.x - control.size.x))
	control.position.y = clampf(control.position.y, 0.0, maxf(0.0, root.size.y - control.size.y))


func _control_id(control: Control) -> String:
	return str(control.get_meta("mobile_layout_id", ""))


func _remember_control(control: Control) -> void:
	var id := _control_id(control)
	if id.is_empty() or root.size.x <= 0.0 or root.size.y <= 0.0:
		return
	_clamp_control(control)
	layout[id]["center"] = (control.position + control.size * 0.5) / root.size
	_save_layout()


func _select_control(control: Control) -> void:
	if not layout_edit_mode:
		return
	if is_instance_valid(selected_control) and selected_control.has_method("set_selected"):
		selected_control.set_selected(false)
	selected_control = control
	selected_control.set_selected(true)
	editor_label.text = "正在调整：" + str(defaults[_control_id(control)]["name"])


func _open_layout_editor() -> void:
	layout_edit_mode = true
	editor_panel.visible = true
	movement_group.visible = true
	_release_movement()
	for control in controls.values():
		control.set_editing(true)
	selected_control = joystick
	_select_control(joystick)


func _finish_layout_editor() -> void:
	layout_edit_mode = false
	editor_panel.visible = false
	for control in controls.values():
		control.set_editing(false)
	selected_control = null
	_save_layout()


func _resize_selected(factor: float) -> void:
	if not is_instance_valid(selected_control):
		return
	var id := _control_id(selected_control)
	layout[id]["scale"] = clampf(float(layout[id]["scale"]) * factor, 0.65, 1.75)
	_apply_layout()
	_select_control(selected_control)
	_save_layout()


func _reset_layout() -> void:
	layout = defaults.duplicate(true)
	_apply_layout()
	_save_layout()
	if is_instance_valid(selected_control):
		_select_control(selected_control)


func _jump_pressed() -> void:
	pass


func _jump_down() -> void:
	jump_pressed = true
	if is_instance_valid(world) and world.ready_world and not world.input_suspended:
		world.mobile_jump_action()


func _jump_up() -> void:
	jump_pressed = false


func _sprint_pressed() -> void:
	pass


func _sprint_down() -> void:
	sprint_pressed = true
	if is_instance_valid(world) and world.ready_world and not world.input_suspended:
		world.mobile_boost_action()


func _sprint_up() -> void:
	sprint_pressed = false


func _process(_delta: float) -> void:
	if not is_instance_valid(root):
		return
	var usable: bool = is_instance_valid(world) and world.ready_world and not atlas.busy and not atlas.encounters.active
	root.visible = usable
	if not usable:
		_release_movement()
		return
	var blocked: bool = world.input_suspended
	movement_group.visible = layout_edit_mode or not blocked
	if blocked and not layout_edit_mode:
		_release_movement()
	else:
		jump_pressed = jump_button.is_held()
		sprint_pressed = sprint_button.is_held()
		if sprint_pressed and is_instance_valid(world.flight) and world.flight.flying and world.flight.boost_remaining <= 0.0:
			world.mobile_boost_action()


func _release_movement() -> void:
	move_vector = Vector2.ZERO
	jump_pressed = false
	sprint_pressed = false
	look_touch = -1
	if is_instance_valid(jump_button):
		jump_button.cancel_press()
	if is_instance_valid(sprint_button):
		sprint_button.cancel_press()
	if is_instance_valid(joystick) and joystick.value != Vector2.ZERO:
		joystick.reset()


func _input(event: InputEvent) -> void:
	_track_two_finger_right_click(event)
	if layout_edit_mode or not is_instance_valid(root) or not root.visible or not is_instance_valid(world) or world.input_suspended:
		return
	if event is InputEventScreenTouch:
		if event.pressed and look_touch < 0 and not _touch_hits_control(event.position):
			look_touch = event.index
		elif not event.pressed and event.index == look_touch:
			look_touch = -1
	elif event is InputEventScreenDrag and event.index == look_touch:
		world.yaw -= event.relative.x * 0.0042
		world.pitch = clampf(world.pitch - event.relative.y * 0.0042, -1.1, 1.1)
		get_viewport().set_input_as_handled()


func _right_click_context() -> bool:
	if not is_instance_valid(atlas):
		return false
	if is_instance_valid(atlas.encounters) and atlas.encounters.active:
		return true
	return is_instance_valid(world) and world.input_suspended


func _track_two_finger_right_click(event: InputEvent) -> void:
	if not _right_click_context():
		touch_points.clear()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = {
				"start": event.position,
				"position": event.position,
				"time": Time.get_ticks_msec(),
			}
			if touch_points.size() > 2:
				touch_points.clear()
		elif touch_points.has(event.index):
			if touch_points.size() == 2:
				var released: Dictionary = touch_points[event.index]
				var duration := Time.get_ticks_msec() - int(released["time"])
				var valid := duration <= TWO_FINGER_TAP_MS
				for point in touch_points.values():
					valid = valid and Vector2(point["start"]).distance_to(Vector2(point["position"])) <= TWO_FINGER_MOVE_LIMIT
				if valid:
					_emit_right_click(_touch_center())
				touch_points.clear()
			else:
				touch_points.erase(event.index)
	elif event is InputEventScreenDrag and touch_points.has(event.index):
		touch_points[event.index]["position"] = event.position


func _touch_center() -> Vector2:
	var result := Vector2.ZERO
	for point in touch_points.values():
		result += Vector2(point["position"])
	return result / maxf(1.0, float(touch_points.size()))


func _emit_right_click(at: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = at
	press.global_position = at
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	get_viewport().push_input(press, true)
	var release := InputEventMouseButton.new()
	release.position = at
	release.global_position = at
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	get_viewport().push_input(release, true)


func _touch_hits_control(point: Vector2) -> bool:
	for control in controls.values():
		if is_instance_valid(control) and control.visible and control.get_global_rect().grow(8.0).has_point(point):
			return true
	if is_instance_valid(atlas.player_minimap) and atlas.player_minimap.visible and atlas.player_minimap.get_global_rect().has_point(point):
		return true
	return false
