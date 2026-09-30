extends Node
const DEFAULT_GAME_SERVER:="101.43.174.221"
var atlas: Node
var loadout: RefCounted
var panel: PanelContainer
var builder: Control
var inventory: Control
var message: Label
var school_buttons: Array[Button] = []
var save_timer: Timer
var cloud_syncing:=false
var cloud_dirty:=false
var lan_panel: HBoxContainer
var connection_hud: Label
var retry_timer: Timer
var retry_attempt:=0
var cloud_enabled:=false
var auth_deadline:=0
var last_online:=false
var login_redirect_pending:=false

func _l(zh: String,en: String) -> String:
	return en if Locale.locale == "en" else zh

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F10 and Accounts.is_verified_admin():
		lan_panel.visible=not lan_panel.visible
		if lan_panel.visible:
			if is_instance_valid(inventory):inventory.close()
			panel.show()
		get_viewport().set_input_as_handled()

func setup(owner_atlas: Node, profile: RefCounted) -> void:
	atlas = owner_atlas
	loadout = profile
	var bar := HBoxContainer.new()
	bar.name = "IslandQuickIcons"
	bar.add_theme_constant_override("separation",10)
	bar.visible = not (OS.has_feature("mobile") or OS.has_feature("android") or "--mobile-preview" in OS.get_cmdline_user_args())
	atlas.ui.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bar.offset_left=-234;bar.offset_right=-22;bar.offset_top=-86;bar.offset_bottom=-22
	_quick_icon(bar,"book",_l("卡组 [P]","Deck [P]"),toggle)
	_quick_icon(bar,"bag",_l("背包 [B]","Inventory [B]"),func():open_inventory("equipment"))
	_quick_icon(bar,"party",_l("队伍","Party"),open_party)
	panel = PanelContainer.new()
	atlas.ui.add_child(panel)
	panel.position = Vector2(22,76)
	panel.custom_minimum_size = Vector2(660,340)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("102236f5")
	style.border_color = Color("c4a76c")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left=20;style.content_margin_right=20;style.content_margin_top=16;style.content_margin_bottom=16
	panel.add_theme_stylebox_override("panel",style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",12)
	panel.add_child(box)
	var title := Label.new()
	title.text = _l("我的角色与卡组 · 每人控制一名学徒","My Character and Deck · One wizard per player")
	title.add_theme_font_size_override("font_size",23)
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	var identity := Label.new()
	identity.text=str(Accounts.active_character.get("name",_l("学徒","Wizard")))+" · "+Locale.text("SCHOOL_"+str(Accounts.active_character.get("school",loadout.school)).to_upper())+_l("（固定学院）"," (fixed school)")
	row.add_child(identity)
	_button(box,_l("编辑当前学院卡组","Edit current school deck"),edit_deck)
	var helpers := HBoxContainer.new()
	box.add_child(helpers)
	var partner_school: String = preload("res://scripts/worlds/island_ai_allies.gd").partner(loadout.school)
	var partner_name := Locale.text("SCHOOL_"+partner_school.to_upper())
	var caption := Label.new();caption.text=_l("固定 AI 搭档：%s（最多一位，真人优先）","Fixed AI partner: %s (one maximum, players first)") % partner_name;helpers.add_child(caption)
	var choice := OptionButton.new()
	for count in 2:choice.add_item(_l("不带助战","No AI ally") if count==0 else _l("召唤固定搭档","Summon fixed partner"))
	choice.selected=clampi(loadout.ai_count,0,1);helpers.add_child(choice)
	choice.item_selected.connect(func(index: int):loadout.ai_count=index;loadout.save();atlas.encounters.session.send_profile())
	var distant_main := CheckButton.new()
	distant_main.text = "新手区加载远方主岛景观（低配置建议关闭，下次进入生效）"
	distant_main.button_pressed = bool(atlas.preferences.get_value("graphics", "tutorial_distant_main", false))
	box.add_child(distant_main)
	distant_main.toggled.connect(func(enabled: bool):
		atlas.preferences.set_value("graphics", "tutorial_distant_main", enabled)
		atlas.preferences.save("user://island_explorer.cfg"))
	var network := HBoxContainer.new();box.add_child(network)
	lan_panel=network;network.hide()
	var address := LineEdit.new();address.placeholder_text=_l("服务器 IP 或 IP:端口","Server IP or IP:port");address.text=DEFAULT_GAME_SERVER;address.custom_minimum_size.x=200;network.add_child(address)
	_button(network,_l("创建房间","Host room"),func():connect_room(true,address.text))
	_button(network,_l("加入房间","Join room"),func():connect_room(false,address.text))
	_button(network,_l("返回云端","Return to cloud"),return_to_cloud)
	message=Label.new();message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;message.custom_minimum_size.x=620;box.add_child(message)
	message.text=_l("寒冰岛 · 任意队员靠近怪物 2 米即可开战，附近队员一起入场\nP 配置卡组 · F12 世界旅行 · 右键取消已选行动","Frost Island · Approach a monster to start battle; nearby allies join\nP edit deck · F12 world travel · Right click to cancel an action")
	_button(box,_l("收起","Close"),close)
	_button(box,_l("返回角色选择","Character select"),atlas._open_accounts)
	inventory=atlas.wardrobe_panel
	inventory.visibility_changed.connect(func():
		if GraphicsSettings.is_low() and is_instance_valid(atlas.world):atlas.world.visible=not inventory.visible)
	inventory.loadout=loadout
	builder=inventory.builder
	builder.loadout=loadout
	builder.apply_requested.connect(func(counts: Dictionary):
		if not loadout.valid_counts(counts):return
		loadout.saved[loadout.character()]=counts.duplicate(true)
		loadout.save();_queue_sync())
	builder.collection_changed.connect(_queue_sync)
	save_timer=Timer.new();save_timer.one_shot=true;save_timer.wait_time=0.8;add_child(save_timer);save_timer.timeout.connect(_sync_deck)
	retry_timer=Timer.new();retry_timer.one_shot=true;add_child(retry_timer);retry_timer.timeout.connect(_connect_cloud)
	var connection_layer:=CanvasLayer.new();connection_layer.layer=90;add_child(connection_layer)
	connection_hud=Label.new();connection_hud.add_theme_font_size_override("font_size",22)
	connection_hud.add_theme_color_override("font_shadow_color",Color.BLACK);connection_hud.add_theme_constant_override("shadow_outline_size",5)
	connection_hud.mouse_filter=Control.MOUSE_FILTER_IGNORE;connection_layer.add_child(connection_hud)
	connection_hud.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	connection_hud.offset_left=360;connection_hud.offset_right=-360;connection_hud.offset_top=22;connection_hud.offset_bottom=54
	connection_hud.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	Accounts.identity_changed.connect(_identity_changed)
	panel.hide()
	_update_buttons()

func _queue_sync() -> void:
	message.text=_l("已自动保存，下次战斗使用。","Saved automatically for the next battle.")
	cloud_dirty=true;save_timer.start()

func _sync_deck() -> void:
	atlas.encounters.session.send_profile()
	if cloud_syncing or not cloud_dirty:return
	cloud_dirty=false
	if Accounts.active_character.is_empty():return
	cloud_syncing=true
	var result: Dictionary=await Accounts.sync_save()
	cloud_syncing=false
	message.text=_l("卡组已自动同步云端。","Deck synced to cloud.") if result.ok else _l("卡组已保存本地，云端暂未同步。","Deck saved locally; cloud sync pending.")
	if cloud_dirty:save_timer.start()

func _quick_icon(parent: Node,id: String,hint: String,callback: Callable) -> void:
	var button := Button.new()
	button.custom_minimum_size=Vector2(64,64)
	button.tooltip_text=hint
	button.focus_mode=Control.FOCUS_NONE
	button.icon=preload("res://scripts/fusion_3d/frontend_theme.gd").icon(id)
	button.expand_icon=true
	button.add_theme_constant_override("icon_max_width",48)
	for state in ["normal","hover","pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color=Color("102236e8") if state=="normal" else Color("28505af5")
		style.border_color=Color("c4a76c")
		style.set_border_width_all(1)
		style.set_corner_radius_all(12)
		style.set_content_margin_all(8)
		button.add_theme_stylebox_override(state,style)
	parent.add_child(button)
	button.pressed.connect(callback)

func _button(parent: Node,text: String,callback: Callable) -> Button:
	var button := Button.new();button.text=text;button.custom_minimum_size.y=38;button.focus_mode=Control.FOCUS_NONE
	parent.add_child(button);button.pressed.connect(callback);return button

func is_open() -> bool:return panel.visible or (is_instance_valid(inventory) and inventory.visible)
func close() -> void:
	panel.hide()
	if is_instance_valid(inventory):inventory.close()
func toggle() -> void:
	if is_open():close()
	else:open_inventory("cards")
func open_party() -> void:
	if atlas.busy or atlas.encounters.active:return
	if is_instance_valid(inventory):inventory.close()
	panel.show();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
func open_inventory(tab_id: String="equipment") -> void:
	if atlas.busy or atlas.encounters.active:return
	panel.hide();atlas.wardrobe_panel.hide()
	if atlas.library_is_open():atlas.character_library_panel.hide()
	inventory.open_tab(tab_id)
func open_shop(shop_id: String) -> void:
	if atlas.busy or atlas.encounters.active:return
	panel.hide();atlas.wardrobe_panel.hide()
	if atlas.library_is_open():atlas.character_library_panel.hide()
	inventory.open_shop(shop_id)
func edit_deck() -> void:open_inventory("cards")
func _update_buttons() -> void:
	for index in school_buttons.size():school_buttons[index].set_pressed_no_signal(loadout.SCHOOLS[index]==loadout.school)
func connect_room(hosting: bool,address: String) -> void:
	if not Accounts.is_verified_admin():return
	if not await Accounts.verify_admin_session():return
	if atlas.encounters.site_entries.is_empty():message.text=_l("请先返回寒冰岛，再开始联机。","Return to Frost Island before connecting.");return
	var net: Node=atlas.encounters.session.net
	cloud_enabled=false;retry_timer.stop();net.disconnect_town();net.lan_debug=true
	var error: int=net.host() if hosting else net.join(address.strip_edges())
	message.text=_l("房间已创建 · 让队友输入你的局域网 IP","Room hosted · Ask friends to enter your LAN IP") if error==OK and hosting else (_l("正在连接…","Connecting…") if error==OK else _l("未连到服务器","Could not connect to server"))
	message.modulate=Color("f06c6c") if error!=OK else Color.WHITE

func connect_default_server() -> void:
	cloud_enabled=true
	_connect_cloud()

func return_to_cloud() -> void:
	if not Accounts.is_verified_admin():return
	var net: Node=atlas.encounters.session.net
	net.lan_debug=false;net.disconnect_town();retry_attempt=0
	connect_default_server()

func _connect_cloud() -> void:
	if not cloud_enabled or not Accounts.character_ready:return
	var net: Node=atlas.encounters.session.net
	if net.lan_debug or net.connected or net.connecting:return
	var address:=DEFAULT_GAME_SERVER
	# Explicit loopback-only test override; never read a saved LAN address for production.
	for arg in OS.get_cmdline_user_args():
		if arg=="--weekend-local-services":address="127.0.0.1:29760"
	auth_deadline=Time.get_ticks_msec()+30000
	if net.join(address)!=OK:_schedule_retry()

func _schedule_retry() -> void:
	if not cloud_enabled or not retry_timer.is_stopped():return
	retry_timer.start(minf(30.0,pow(2.0,mini(retry_attempt,5))))
	retry_attempt+=1

func _process(_delta: float) -> void:
	if not is_instance_valid(connection_hud):return
	var net: Node=atlas.encounters.session.net
	if net.lan_debug:
		connection_hud.show();connection_hud.text=_l("管理员 LAN 调试 · 云端重连已暂停","Admin LAN debug · Cloud reconnect paused");connection_hud.modulate=Color("ffce70");return
	var online: bool=net.connected and net.authenticated
	connection_hud.visible=not online
	connection_hud.offset_top=146 if atlas.encounters.session.active_local else 22
	connection_hud.offset_bottom=178 if atlas.encounters.session.active_local else 54
	connection_hud.text=_l("云端在线","Cloud online") if online else _l("已断线，正在重连 · 云端认证中","Disconnected; reconnecting · Authenticating") if net.connected else _l("已断线，正在重连","Disconnected; reconnecting")
	connection_hud.modulate=Color("8ee5ad") if online else Color("ff6868")
	if online:retry_attempt=0;retry_timer.stop()
	elif cloud_enabled and Accounts.character_ready:
		if (net.connected or net.connecting) and Time.get_ticks_msec()>auth_deadline:net.disconnect_town()
		if not net.connected and not net.connecting:_schedule_retry()
	last_online=online

func authentication_failed(code: String) -> void:
	if code=="unauthorized":
		cloud_enabled=false;retry_timer.stop()
		Accounts.verified_username="";Accounts.token="";Accounts.account.clear();Accounts.leave_character()
		Accounts.message("登录已过期，请重新登录。")
		_return_to_login()
	else:
		atlas.encounters.session.net.disconnect_town();_schedule_retry()

func _identity_changed() -> void:
	if not Accounts.is_verified_admin():
		lan_panel.hide()
		if atlas.encounters.session.net.lan_debug:
			atlas.encounters.session.net.lan_debug=false;atlas.encounters.session.net.disconnect_town()
	if not Accounts.character_ready:
		cloud_enabled=false;retry_timer.stop();atlas.encounters.session.net.disconnect_town()
		if Accounts.token.is_empty():_return_to_login()

func _return_to_login() -> void:
	if login_redirect_pending:return
	login_redirect_pending=true
	get_tree().call_deferred("change_scene_to_file","res://scenes/fusion_3d/account_menu.tscn")

func _exit_tree() -> void:
	cloud_enabled=false
	if is_instance_valid(retry_timer):retry_timer.stop()
