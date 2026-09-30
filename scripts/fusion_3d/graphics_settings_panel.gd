extends CanvasLayer

var quality_choice: OptionButton
var particles: CheckButton
var mode_choice: OptionButton
var resolution: OptionButton
var status: Label
var restart_button: Button

func _l(zh: String, en: String) -> String:
	return en if Locale.locale == "en" else zh

func _ready() -> void:
	layer = 120
	var shade := ColorRect.new()
	shade.color = Color(0.015,0.025,0.04,0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 520
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102236")
	style.border_color = Color("c4a76c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel",style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",16)
	panel.add_child(box)
	_label(box,_l("设置 · 画面","Settings · Graphics"),28)
	quality_choice = _choice(box,_l("画质","Quality"),[_l("高画质","High"),_l("低画质 · 兼容模式","Low · Compatibility")])
	quality_choice.selected = 1 if GraphicsSettings.quality == "low" else 0
	particles = CheckButton.new()
	particles.text = _l("粒子效果","Particle effects")
	particles.add_theme_font_size_override("font_size",21)
	particles.custom_minimum_size.y = 44
	particles.button_pressed = GraphicsSettings.particles_enabled
	box.add_child(particles)
	mode_choice = _choice(box,_l("显示模式","Display mode"),[_l("窗口化","Windowed"),_l("全屏","Fullscreen")])
	mode_choice.selected = 1 if GraphicsSettings.fullscreen else 0
	var sizes: Array = []
	for value in GraphicsSettings.RESOLUTIONS:sizes.append("%d × %d" % [value.x,value.y])
	resolution = _choice(box,_l("窗口分辨率","Window resolution"),sizes)
	resolution.selected = GraphicsSettings.RESOLUTIONS.find(GraphicsSettings.window_size)
	resolution.disabled = GraphicsSettings.fullscreen
	mode_choice.item_selected.connect(func(index: int):resolution.disabled = index == 1)
	var note := _label(box,_l("切换画质需重启；粒子和显示设置即时生效。","Quality needs a restart; particles and display apply immediately."),16)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 440
	status = _label(box,_l("窗口尺寸会适配当前屏幕。","Window size fits your screen."),16)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 440
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation",14)
	box.add_child(buttons)
	_button(buttons,_l("应用并保存","Apply & save"),_apply)
	_button(buttons,_l("关闭","Close"),queue_free)
	restart_button = Button.new()
	restart_button.text = _l("现在重启游戏","Restart game now")
	restart_button.custom_minimum_size.y = 44
	restart_button.add_theme_font_size_override("font_size",20)
	restart_button.visible = GraphicsSettings.restart_required()
	restart_button.pressed.connect(func():
		if _apply() == OK:GraphicsSettings.restart_game())
	box.add_child(restart_button)
	quality_choice.grab_focus()

func _label(parent: Node, value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",font_size)
	parent.add_child(label)
	return label

func _choice(parent: Node, caption: String, values: Array) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(row,caption,21)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var choice := OptionButton.new()
	choice.custom_minimum_size = Vector2(240,44)
	choice.add_theme_font_size_override("font_size",20)
	for value in values:choice.add_item(value)
	row.add_child(choice)
	return choice

func _button(parent: Node, caption: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size.y = 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size",21)
	button.pressed.connect(callback)
	parent.add_child(button)

func _apply() -> Error:
	GraphicsSettings.quality = "low" if quality_choice.selected == 1 else "high"
	GraphicsSettings.particles_enabled = particles.button_pressed
	GraphicsSettings.fullscreen = mode_choice.selected == 1
	GraphicsSettings.window_size = GraphicsSettings.RESOLUTIONS[resolution.selected]
	GraphicsSettings.apply_graphics()
	GraphicsSettings.apply_display()
	var error: Error = GraphicsSettings.save_settings()
	status.text = _l("已应用并保存。","Applied and saved.") if error == OK else _l("已应用，但保存失败，请检查磁盘权限。","Applied; could not save to disk.")
	restart_button.visible = error == OK and GraphicsSettings.restart_required()
	if restart_button.visible:status.text = _l("已保存；画质将在重启游戏后生效。","Saved; quality takes effect after restarting.")
	return error

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()
