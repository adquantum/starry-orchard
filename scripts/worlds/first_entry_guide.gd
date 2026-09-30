extends Control

signal closed

const ART:=preload("res://assets/ui/onboarding/adventurer_controls.png")

var save_path:="user://first_entry_guide.cfg"
var profile_key:="default"
var close_button: Button

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	mouse_filter=Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index=100
	var shade:=ColorRect.new()
	shade.color=Color("02070dcc")
	shade.mouse_filter=Control.MOUSE_FILTER_STOP
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center:=CenterContainer.new()
	center.mouse_filter=Control.MOUSE_FILTER_STOP
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var modal:=Control.new()
	modal.custom_minimum_size=Vector2(1672,941)
	center.add_child(modal)
	if Locale.locale == "en":
		_build_english_guide(modal)
	else:
		var artwork:=TextureRect.new()
		artwork.texture=ART
		artwork.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		artwork.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		artwork.mouse_filter=Control.MOUSE_FILTER_IGNORE
		modal.add_child(artwork)
	var route_note:=Label.new()
	route_note.text="New characters start without wings. Challenge the port camp for treasure cards, trade for gear, then face the golden Windwing Eagle boss.\nDefeat it to unlock your first permanent wings. Press B to equip them. Other blue camps are optional." if Locale.locale == "en" else "新角色无翅膀：港口入门营地可重复挑战，用获得的宝藏卡兑换装备，再前往金色风翼鹰首 Boss。\n击败风翼鹰可永久解锁第一副翼；按 B 打开衣橱装备或收起。其余蓝色营地为可选挑战。"
	route_note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	route_note.add_theme_font_size_override("font_size",22)
	route_note.add_theme_color_override("font_color",Color("fff0c8"))
	route_note.add_theme_color_override("font_shadow_color",Color("08121ad9"))
	route_note.add_theme_constant_override("shadow_offset_x",2)
	route_note.add_theme_constant_override("shadow_offset_y",2)
	route_note.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	route_note.offset_left=180;route_note.offset_right=-180;route_note.offset_top=-126;route_note.offset_bottom=-42
	modal.add_child(route_note)
	close_button=Button.new()
	close_button.name="CloseGuide"
	close_button.text="×"
	close_button.tooltip_text="Close controls guide" if Locale.locale == "en" else "关闭操作指南"
	close_button.focus_mode=Control.FOCUS_NONE
	close_button.add_theme_font_size_override("font_size",36)
	close_button.add_theme_color_override("font_color",Color("fff0c8"))
	close_button.add_theme_color_override("font_hover_color",Color.WHITE)
	close_button.add_theme_stylebox_override("normal",_close_style(Color("18343ee8"),Color("c49a54")))
	close_button.add_theme_stylebox_override("hover",_close_style(Color("285966f2"),Color("f0d18a")))
	close_button.add_theme_stylebox_override("pressed",_close_style(Color("10262fee"),Color("fff0b0")))
	close_button.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
	close_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_button.offset_left=-94
	close_button.offset_right=-26
	close_button.offset_top=26
	close_button.offset_bottom=94
	close_button.pressed.connect(close)
	modal.add_child(close_button)
	hide()

func _build_english_guide(modal: Control) -> void:
	var panel:=PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parchment:=StyleBoxFlat.new()
	parchment.bg_color=Color("e7d4ac")
	parchment.border_color=Color("a27c40")
	parchment.set_border_width_all(8)
	parchment.set_corner_radius_all(18)
	panel.add_theme_stylebox_override("panel",parchment)
	modal.add_child(panel)
	var layout:=VBoxContainer.new()
	layout.add_theme_constant_override("separation",18)
	panel.add_child(layout)
	var title:=Label.new();title.text="ADVENTURER'S GUIDE";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",42);title.add_theme_color_override("font_color",Color("3b3027"));layout.add_child(title)
	var subtitle:=Label.new();subtitle.text="Explore the seven schools of magic";subtitle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;subtitle.add_theme_font_size_override("font_size",24);subtitle.add_theme_color_override("font_color",Color("665035"));layout.add_child(subtitle)
	var rows:=[["WASD","Move your character"],["Mouse + Ctrl","Look around"],["P","Edit your deck"],["B","Open inventory and change outfit"],["R","Return to a safe location"],["Enter","Open chat and send a message"],["Space × 2","Take off or fold your wings"],["Right click","Flap toward the camera direction"]]
	var grid:=GridContainer.new();grid.columns=2;grid.add_theme_constant_override("h_separation",32);grid.add_theme_constant_override("v_separation",16);layout.add_child(grid)
	for pair in rows:
		var key:=Label.new();key.text=pair[0];key.custom_minimum_size.x=360;key.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;key.add_theme_font_size_override("font_size",27);key.add_theme_color_override("font_color",Color("215466"));grid.add_child(key)
		var description:=Label.new();description.text=pair[1];description.add_theme_font_size_override("font_size",27);description.add_theme_color_override("font_color",Color("3b3027"));grid.add_child(description)

func _close_style(fill: Color,edge: Color) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=fill
	style.border_color=edge
	style.set_border_width_all(2)
	style.set_corner_radius_all(34)
	return style

func open_for(key: String,force: bool=false) -> bool:
	var identity:=key.strip_edges().to_lower()
	if identity.is_empty():identity="default"
	profile_key=identity.sha256_text()
	var saved:=ConfigFile.new()
	saved.load(save_path)
	if not force and bool(saved.get_value("seen",profile_key,false)):return false
	show()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	return true

func close() -> void:
	if not visible:return
	var saved:=ConfigFile.new()
	saved.load(save_path)
	saved.set_value("seen",profile_key,true)
	var error:=saved.save(save_path)
	if error != OK:push_error("无法保存首次操作指南状态：%s" % error_string(error))
	hide()
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
