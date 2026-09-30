extends CanvasLayer
## Small world chat: Enter opens, Enter sends, and idle messages disappear.
const IDLE_SECONDS:=8.0
const MAX_VISIBLE:=7
var atlas: Node
var session: Node
var shell: MarginContainer
var history: VBoxContainer
var input: LineEdit
var expires_at:=0.0
var entries: Array[Dictionary]=[]
var closed_by_user:=false
var dragging:=false
var drag_offset:=Vector2.ZERO

func setup(owner_atlas: Node,battle_session: Node) -> void:
	atlas=owner_atlas;session=battle_session
	layer=35
	shell=MarginContainer.new()
	shell.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	shell.offset_left=22;shell.offset_top=-350;shell.offset_right=650;shell.offset_bottom=-24
	add_child(shell)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",8);shell.add_child(column)
	var panel:=PanelContainer.new();panel.custom_minimum_size=Vector2(610,240);column.add_child(panel)
	var panel_style:=StyleBoxFlat.new();panel_style.bg_color=Color("07111bcc");panel_style.set_corner_radius_all(8);panel_style.set_content_margin_all(12);panel.add_theme_stylebox_override("panel",panel_style)
	var panel_column:=VBoxContainer.new();panel_column.add_theme_constant_override("separation",5);panel.add_child(panel_column)
	var header:=HBoxContainer.new();header.mouse_filter=Control.MOUSE_FILTER_STOP;panel_column.add_child(header)
	var title:=Label.new();title.text="世界聊天  ·  拖动此栏";title.mouse_filter=Control.MOUSE_FILTER_IGNORE;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_theme_font_size_override("font_size",14);title.modulate=Color("b9c8d4");header.add_child(title)
	var close_button:=Button.new();close_button.text="×";close_button.tooltip_text="关闭聊天（按 Enter 重新打开）";close_button.custom_minimum_size=Vector2(26,26);header.add_child(close_button)
	close_button.pressed.connect(_close_chat)
	header.gui_input.connect(_on_header_input)
	history=VBoxContainer.new();history.add_theme_constant_override("separation",3);panel_column.add_child(history)
	input=LineEdit.new();input.placeholder_text="输入世界消息，按 Enter 发送";input.max_length=160;input.custom_minimum_size.y=44;input.add_theme_font_size_override("font_size",19);column.add_child(input)
	input.hide()
	input.text_submitted.connect(_submit)
	input.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			close_input();get_viewport().set_input_as_handled())
	shell.hide()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER,KEY_KP_ENTER]:
		if not input.visible or not input.has_focus():open_input()
		get_viewport().set_input_as_handled()

func open_input() -> void:
	closed_by_user=false;shell.show();input.show();input.grab_focus();expires_at=INF
	if is_instance_valid(atlas.world) and is_instance_valid(atlas.world.player):atlas.world.player.velocity=Vector3.ZERO

func toggle_input() -> void:
	if input.visible:
		close_input()
	else:
		open_input()

func close_input() -> void:
	input.release_focus();input.hide();expires_at=Time.get_ticks_msec()/1000.0+IDLE_SECONDS
	if entries.is_empty():shell.hide()

func _close_chat() -> void:
	closed_by_user=true
	dragging=false
	input.release_focus();input.hide();shell.hide()

func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		dragging=true
		drag_offset=event.global_position-shell.global_position
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not dragging:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
		dragging=false
	elif event is InputEventMouseMotion:
		var viewport_size:=get_viewport().get_visible_rect().size
		var target: Vector2=event.global_position-drag_offset
		shell.global_position=Vector2(clampf(target.x,0,maxf(0,viewport_size.x-shell.size.x)),clampf(target.y,0,maxf(0,viewport_size.y-shell.size.y)))

func _submit(value: String) -> void:
	var clean: String=session.net.clean_chat_text(value)
	input.clear()
	if not clean.is_empty():
		if session.net.connected:session.send_chat(clean)
		else:receive_message("系统","未连到服务器")
	close_input()

func receive_message(sender: String,message: String) -> void:
	if message.is_empty():return
	entries.append({"sender":sender,"message":message})
	while entries.size()>MAX_VISIBLE:entries.pop_front()
	for child in history.get_children():child.queue_free()
	for entry in entries:
		var line:=Label.new();line.text="<%s> %s"%[str(entry.sender),str(entry.message)];line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;line.add_theme_font_size_override("font_size",18);line.modulate=Color("f3d89c") if str(entry.sender)!="系统" else Color("f06c6c");history.add_child(line)
	if not closed_by_user:shell.show()
	if not input.visible:expires_at=Time.get_ticks_msec()/1000.0+IDLE_SECONDS

func _process(_delta: float) -> void:
	if shell.visible and not input.visible and Time.get_ticks_msec()/1000.0>=expires_at:shell.hide()
