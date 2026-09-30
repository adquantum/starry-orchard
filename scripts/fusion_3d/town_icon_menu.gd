extends Control
const Art=preload("res://scripts/fusion_3d/frontend_theme.gd")
var town: Node3D
var drawer: PanelContainer
var stack: VBoxContainer
var rail: VBoxContainer
var selected: String=""
var category_buttons: Dictionary={}
var quest_host: VBoxContainer
var drawer_tween: Tween
func setup(value: Node3D) -> void:
	town=value
	name="AcademyIconMenu"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	rail=VBoxContainer.new();rail.name="IconRail"
	rail.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	rail.position=Vector2(-104,30);rail.add_theme_constant_override("separation",12);add_child(rail)
	for spec in [["bag","背包"],["party","小队"],["quest","任务"],["compass","探索"],["network","联机"],["settings","设置"]]:
		var button=Button.new();button.name=spec[0];button.custom_minimum_size=Vector2(76,82);button.tooltip_text=spec[1]+" · 点击展开";button.toggle_mode=true
		button.add_theme_stylebox_override("normal",Art.panel(Color("0c1b2bdf"),Color("816d4a")))
		button.add_theme_stylebox_override("hover",Art.panel(Color("1c3a43f5"),Color("e2bd72")))
		button.add_theme_stylebox_override("pressed",Art.panel(Color("205045f5"),Color("f2d28b")))
		var picture=TextureRect.new();picture.texture=Art.icon(spec[0]);picture.position=Vector2(13,4);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.size=Vector2(50,50);picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(picture);picture.set_deferred("size",Vector2(50,50));button.clip_contents=true
		var label=Label.new();label.text=spec[1];label.position=Vector2(0,55);label.size=Vector2(76,24);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;label.add_theme_font_size_override("font_size",16);label.mouse_filter=Control.MOUSE_FILTER_IGNORE;button.add_child(label)
		button.pressed.connect(func():toggle_category(spec[0]))
		rail.add_child(button);category_buttons[spec[0]]=button
	drawer=PanelContainer.new();drawer.name="Drawer";drawer.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);drawer.position=Vector2(-510,30);drawer.custom_minimum_size=Vector2(382,0);add_child(drawer)
	stack=VBoxContainer.new();stack.add_theme_constant_override("separation",13);drawer.add_child(stack)
	quest_host=VBoxContainer.new();quest_host.name="QuestTracking";quest_host.custom_minimum_size.x=330
	town.quest_label.reparent(quest_host)
	town.quest_label.custom_minimum_size.x=330
	town.quest_label.add_theme_font_size_override("font_size",18)
	add_child(quest_host);quest_host.hide()
	drawer.hide()
func is_open() -> bool:return drawer!=null and drawer.visible
func close() -> void:
	if drawer_tween!=null and drawer_tween.is_valid():drawer_tween.kill()
	drawer.hide();selected=""
	for button in category_buttons.values():button.set_pressed_no_signal(false)
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE and is_open():
		close();get_viewport().set_input_as_handled()
func add_action(label: String, id: String, callback: Callable) -> Button:
	var b=Button.new();b.text=label;b.icon=Art.icon(id);b.expand_icon=true;b.add_theme_constant_override("icon_max_width",28);b.custom_minimum_size=Vector2(330,54);b.alignment=HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():close();callback.call())
	stack.add_child(b);return b
func toggle_category(id: String) -> void:
	if town.battle!=null:return
	if selected==id and is_open():close();return
	if drawer_tween!=null and drawer_tween.is_valid():drawer_tween.kill()
	selected=id
	if town.view_controller!=null:town.view_controller.set_capture(false)
	quest_host.reparent(self);quest_host.hide()
	for child in stack.get_children():stack.remove_child(child);child.queue_free()
	var heading=HBoxContainer.new();stack.add_child(heading)
	var title=Label.new();title.text={"bag":"行囊与装束","party":"学院小队","quest":"旅途记录","compass":"探索学院","network":"结伴同行","settings":"旅途设置"}[id];title.add_theme_font_size_override("font_size",24);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title)
	var dismiss=Button.new();dismiss.text="×";dismiss.tooltip_text="收起菜单 [Esc]";dismiss.custom_minimum_size=Vector2(42,42);dismiss.pressed.connect(close);heading.add_child(dismiss)
	stack.add_child(HSeparator.new())
	match id:
		"bag":add_action("背包与角色换装  [B]","bag",town.toggle_wardrobe)
		"party":add_action("选择四人小队","party",func():town.party_panel.show())
		"quest":
			quest_host.reparent(stack);quest_host.show()
			add_action("打开调查簿  [J]","book",func():
				if town.chapter!=null:town.chapter.toggle_journal())
		"compass":
			add_action("怪物与 NPC 图鉴","book",town.open_character_library)
			add_action("与附近角色交谈  [E]","talk",town.interact)
			add_action("近景 / 俯视切换","compass",func():town.view_controller.toggle_view())
			add_action("学院全景 / 返回","star",func():town.overview=not town.overview)
		"network":
			add_action("开放局域网城镇","network",func():
				var error: Error=town.network.host()
				if error!=OK:town.hint.text="开放失败："+error_string(error))
			var address=LineEdit.new();address.name="HostAddress";address.text="127.0.0.1";address.placeholder_text="城镇主机 IP";address.custom_minimum_size.y=48;stack.add_child(address)
			add_action("加入好友城镇","network",func():
				var error: Error=town.network.join(address.text.strip_edges())
				if error!=OK:town.hint.text="加入失败："+error_string(error))
			add_action("断开联网","account",func():town.network.disconnect_town();town.hint.text="已返回本地城镇")
		"settings":
			add_action("保存冒险进度","save",town.save_account_progress)
			var muted: bool=town.exploration_music!=null and town.exploration_music.muted
			add_action("开启背景音乐" if muted else "关闭背景音乐","music",func():
				if town.exploration_music!=null:
					town.exploration_music.toggle_mute()
					town.hint.text="背景音乐已关闭" if town.exploration_music.muted else "背景音乐已开启")
			add_action("角色与账号管理","account",town.return_to_accounts)
			var help=Label.new();help.text="WASD 移动 · 空格跳跃\nCtrl 切换视角与光标\nE 交谈 · B 背包 · J 调查簿";help.add_theme_font_size_override("font_size",17);stack.add_child(help)
	drawer.size=Vector2(382,0)
	drawer.show();drawer.modulate.a=0
	drawer_tween=create_tween();drawer_tween.tween_property(drawer,"modulate:a",1.0,.16)
	for key in category_buttons:category_buttons[key].set_pressed_no_signal(key==id)
