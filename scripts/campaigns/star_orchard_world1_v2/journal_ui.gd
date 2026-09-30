extends CanvasLayer
## All interface nodes belong to the campaign runner and disappear with its world.
signal interaction_requested
signal journal_requested
signal close_requested

var hud: PanelContainer
var heading: Label
var objective: Label
var note: Label
var interact: Button
var dialog: PanelContainer
var dialog_title: Label
var dialog_text: RichTextLabel
var dialog_actions: VBoxContainer
var journal: PanelContainer
var journal_body: VBoxContainer
var dialog_scroll: ScrollContainer
var _dialog_commit := Callable()
var _dialog_options: Array = []
var _dialog_continue := "继续"
var _pages: Array = []
var _page := 0
var speaker_name := ""

func set_speaker(value: String, actor: String = "") -> void:
	speaker_name = value
	dialog.set_actor(actor)

func build() -> void:
	layer = 12
	hud = _panel()
	add_child(hud)
	var box := _box(hud)
	heading = _label("星界果园 · 巡园簿", 18)
	box.add_child(heading)
	objective = _label("正在打开巡园簿…", 16)
	box.add_child(objective)
	note = _label("", 13)
	note.modulate = Color(0.78, 0.85, 0.86)
	box.add_child(note)
	var row := HBoxContainer.new()
	box.add_child(row)
	interact = _button("交互 [E]", func(): interaction_requested.emit())
	interact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(interact)
	row.add_child(_button("巡园簿 [J]", func(): journal_requested.emit()))
	dialog = preload("res://scripts/fusion_3d/npc_dialogue_panel.gd").new()
	add_child(dialog)
	dialog.hide()
	dialog_title = dialog.heading
	dialog.add_action("收起 · Esc", func(): close_requested.emit())
	dialog.body.hide()
	dialog_scroll = dialog.scroll
	dialog_text = RichTextLabel.new()
	dialog_text.bbcode_enabled = false
	dialog_text.fit_content = true
	dialog_text.scroll_active = false
	dialog_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_text.add_theme_font_size_override("normal_font_size", 23)
	dialog_text.selection_enabled = true
	dialog_scroll.add_child(dialog_text)
	dialog_actions = VBoxContainer.new()
	dialog_actions.add_theme_constant_override("separation", 5)
	dialog.actions.add_child(dialog_actions)
	journal = _panel()
	add_child(journal)
	journal.hide()
	var jb := _box(journal)
	var jrow := HBoxContainer.new()
	jb.add_child(jrow)
	var jtitle := _label("巡园簿 · 任务、证据与旅途记录", 22)
	jtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	jrow.add_child(jtitle)
	jrow.add_child(_button("关闭 ×", func(): close_requested.emit()))
	var js := ScrollContainer.new()
	js.size_flags_vertical = Control.SIZE_EXPAND_FILL
	js.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	jb.add_child(js)
	journal_body = VBoxContainer.new()
	journal_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	journal_body.add_theme_constant_override("separation", 12)
	js.add_child(journal_body)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.045, 0.075, 0.105, 0.92)
	skin.border_color = Color(0.49, 0.62, 0.56, 0.8)
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(9)
	skin.content_margin_left = 16
	skin.content_margin_right = 16
	skin.content_margin_top = 12
	skin.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", skin)
	return panel

func _box(parent: Node) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)
	return box

func _label(value: String, font_size: int = 16) -> Label:
	var result := Label.new()
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size", font_size)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _button(value: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 36
	result.add_theme_font_size_override("font_size", 16)
	result.pressed.connect(callback)
	return result

func _layout() -> void:
	var area := get_viewport().get_visible_rect().size
	hud.position = Vector2(14, 106)
	hud.size = Vector2(minf(326, area.x - 28), 0)
	dialog.layout_dialogue()
	journal.position = Vector2(maxf(14, (area.x - 880) * 0.5), 42)
	journal.size = Vector2(minf(880, area.x - 28), maxf(220, area.y - 84))

func update_hud(title: String, task: String, message: String, can_interact: bool, action: String = "交互 [E]") -> void:
	heading.text = title
	objective.text = task
	note.text = message
	note.visible = not message.is_empty()
	interact.disabled = not can_interact
	interact.text = action

func show_pages(title: String, pages: Array, action: String, commit: Callable, options: Array = []) -> void:
	journal.hide()
	dialog_title.text = title if speaker_name.is_empty() else speaker_name + " · " + title
	_pages = pages.duplicate()
	if _pages.is_empty():
		_pages = [title]
	_page = 0
	_dialog_commit = commit
	_dialog_continue = action
	_dialog_options = options
	dialog.show()
	_render_page()

func _dialog_button(value: String, callback: Callable) -> Button:
	var result := _button(value, callback)
	preload("res://scenes/battle_v2/ui/compact_battle_skin.gd").button(result)
	result.custom_minimum_size = Vector2(170, 44)
	result.add_theme_font_size_override("font_size", 21)
	return result

func _render_page() -> void:
	dialog_text.text = str(_pages[_page])
	dialog_scroll.scroll_vertical = 0
	for child in dialog_actions.get_children():
		dialog_actions.remove_child(child)
		child.queue_free()
	if _page < _pages.size() - 1:
		dialog_actions.add_child(_dialog_button("下一段  %d / %d" % [_page + 1, _pages.size()], func():
			_page += 1
			_render_page()))
		return
	for entry in _dialog_options:
		var option: Dictionary = entry
		dialog_actions.add_child(_dialog_button(str(option.get("text", "选择")), option.get("callback", Callable())))
	if not _dialog_continue.is_empty():
		dialog_actions.add_child(_dialog_button(_dialog_continue, func():
			var callback := _dialog_commit
			if callback.is_valid():
				callback.call()))

func begin_journal() -> void:
	dialog.hide()
	for child in journal_body.get_children():
		journal_body.remove_child(child)
		child.queue_free()
	journal.show()

func journal_text(text: String, font_size: int = 16) -> void:
	journal_body.add_child(_label(text, font_size))

func journal_button(text: String, callback: Callable) -> void:
	journal_body.add_child(_button(text, callback))

func hide_modal() -> void:
	dialog.hide()
	journal.hide()
	_dialog_commit = Callable()
	_dialog_options.clear()

func is_open() -> bool:
	return (is_instance_valid(dialog) and dialog.visible) or (is_instance_valid(journal) and journal.visible)
