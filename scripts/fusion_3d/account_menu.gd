extends Control
const SCHOOLS=["fire","ice","storm","myth","life","death","balance"]
const SCHOOL_NAMES=["火焰学院","冰霜学院","风暴学院","神话学院","生命学院","死亡学院","平衡学院"]
var content: VBoxContainer
var heading: Label
var subtitle: Label
var feedback: Label
var preview: Node3D
var username: LineEdit
var password: LineEdit
var confirm: LineEdit
var endpoint: LineEdit
var name_field: LineEdit
var school_choice:=3
var gender_choice:=1
var hair_choice:=0
var face_choice:=0
var face_buttons: Array[Button]=[]
var creation_hairs: Array=[]
var creation_faces: Array=[]
var creation_hair_row: HFlowContainer
var creation_face_row: HFlowContainer
var school_buttons: Array[Button]=[]
var gender_buttons: Array[Button]=[]
var hair_buttons: Array[Button]=[]
var import_check: CheckBox
var selected: Dictionary={}
var characters: Array=[]
var busy:=false
var registering:=false
var travel_requested:=true
var angle:=0.0
var shell_margin: MarginContainer
var showcase: Control
var account_card: PanelContainer
var character_grid: GridContainer
var shell_stack: VBoxContainer
var masthead_crest: TextureRect
var brand_caption: Label
var masthead_trail: Label
var card_gap: Control
var bottom_guard: Control
var preview_viewport: SubViewport
var preview_status: Label
var page_generation:=0
var menu_music: AudioStreamPlayer
var language_button: Button
var current_page := "login"
var settings_button: Button

const UI_EN := {
	"星 界 果 园": "STARRY ORCHARD", "七大学院 · 联机冒险": "SEVEN SCHOOLS · ONLINE ADVENTURE",
	"你的魔法旅程": "Your magical journey", "选择角色，踏入寒冰岛。": "Choose a character and enter Frost Island.",
	"选择角色后显示当前外观": "Select a character to preview their appearance", "学院通行证": "ACADEMY PASSPORT",
	"注册账号": "Create an account", "欢迎回到学院": "Welcome back", "使用账号登录，管理你的角色与云存档。": "Sign in to manage your characters and cloud saves.",
	"账号名 · 3–24 位字母、数字或下划线": "Username · 3–24 letters, numbers, or underscores",
	"输入账号名": "Enter username", "密码 · 至少 8 个字符": "Password · at least 8 characters", "输入密码": "Enter password",
	"再次输入密码": "Confirm password", "注册并登录": "Create account", "登录": "Sign in", "已有账号": "Have an account?",
	"创建账号": "Create account", "账号服务器地址": "Account server address", "检查服务器连接": "Check connection",
	"请输入有效的服务器地址。": "Enter a valid server address.", "服务器连接正常": "Server connection successful",
	"未连到服务器": "Could not connect to server", "两次输入的密码不一致。": "Passwords do not match.",
	"正在连接账号服务器…": "Connecting to account server…", "选择角色": "Choose a character",
	"还没有角色，点击下方卡片创建你的第一位巫师。": "No characters yet. Create your first wizard below.",
	"账号安全": "Account security", "退出登录": "Sign out", "重试": "Retry", "返回登录": "Back to sign in",
	"进入寒冰岛": "Enter Frost Island", "角色资料": "Character details", "角色名称": "Character name",
	"保存名字": "Save name", "返回列表": "Back to list", "删除这个角色…": "Delete this character…",
	"正在读取角色存档…": "Loading character save…", "选择要保留的进度": "Choose which progress to keep",
	"本地和云端都有更新，选择前会备份两个版本。": "Both local and cloud saves changed. Both will be backed up before you choose.",
	"使用云端存档": "Use cloud save", "保留本地进度并上传": "Keep local progress and upload",
	"暂不处理，返回列表": "Decide later; return to list", "创建新角色": "Create a character",
	"全部选项直接点击；进入游戏后仍可在衣橱更换外观。": "Choose each option below. You can change your look later.",
	"角色名称 · 2–20 个字符": "Character name · 2–20 characters", "所属学院": "School of magic",
	"角色性别": "Gender", "脸型": "Face", "可染色发型": "Dyeable hairstyle", "男生": "Male", "女生": "Female",
	"导入这台电脑已有的冒险进度": "Import existing progress on this device",
	"导入会沿用原队伍与外观；不勾选则从新生进度开始。": "Import keeps your old party and appearance; otherwise start fresh.",
	"创建并选择": "Create and select", "删除角色": "Delete character", "请输入完整角色名确认": "Enter the full character name to confirm",
	"确认删除这个角色": "Confirm deletion", "取消": "Cancel", "修改密码": "Change password",
	"修改后，其他设备的登录会失效。": "Signing in on other devices will be required again.",
	"原密码": "Current password", "新密码 · 至少 8 个字符": "New password · at least 8 characters",
	"更新密码": "Update password", "密码已更新。": "Password updated.", "返回角色列表": "Back to characters",
	"正在读取人物外观…": "Loading character appearance…", "人物预览资源读取失败": "Could not load character preview",
	"暂时无法读取角色外观，请重试。": "Could not fetch character appearance. Please retry.",
	"死亡学院 · 与幽影同行，守望灵魂的秘密。": "Death School · Walk with shadows and guard the secrets of souls.",
}

func ui(value: String) -> String:
	return str(UI_EN.get(value, value)) if Locale.locale == "en" else value

func school_name(index: int) -> String:
	return Locale.text("SCHOOL_"+SCHOOLS[maxi(index,0)].to_upper()) if Locale.locale == "en" else SCHOOL_NAMES[maxi(index,0)]

func _on_language_changed() -> void:
	settings_button.text = "Settings" if Locale.locale == "en" else "设置"
	DisplayServer.window_set_title("Starry Orchard" if Locale.locale == "en" else "星界果园")
	var masthead:=shell_stack.get_child(0)
	masthead.find_child("BrandTitle",true,false).text=ui("星 界 果 园")
	masthead_trail.text=ui("七大学院 · 联机冒险")
	showcase.find_child("JourneyTitle",true,false).text=ui("你的魔法旅程")
	showcase.find_child("JourneyDetail",true,false).text=ui("选择角色，踏入寒冰岛。")
	if is_instance_valid(preview_status) and preview_status.visible:preview_status.text=ui("选择角色后显示当前外观")
	account_card.find_child("PassportTitle",true,false).text=ui("学院通行证")
	match current_page:
		"login":
			var old_username:=username.text if is_instance_valid(username) else ""
			var old_password:=password.text if is_instance_valid(password) else ""
			var old_confirm:=confirm.text if is_instance_valid(confirm) else ""
			var old_endpoint:=endpoint.text if is_instance_valid(endpoint) else ""
			show_login(registering)
			username.text=old_username;password.text=old_password
			if registering:confirm.text=old_confirm
			endpoint.text=old_endpoint
		"characters":_render_characters(characters)
		"selected":show_selected(selected)
		"create":
			var old_name:=name_field.text if is_instance_valid(name_field) else ""
			var old_school:=school_choice
			var old_gender:=gender_choice
			var old_hair:=hair_choice
			var old_face:=face_choice
			var old_import:=import_check.button_pressed if is_instance_valid(import_check) else false
			show_create()
			name_field.text=old_name;school_choice=old_school;gender_choice=old_gender;hair_choice=old_hair;face_choice=old_face;import_check.button_pressed=old_import
			_build_creation_looks();_refresh_creation_choices();update_preview()
		"delete":show_delete()
		"password":show_password()
		"conflict":show_conflict()
func _ready() -> void:
	Accounts.leave_character()
	DisplayServer.window_set_title("Starry Orchard" if Locale.locale == "en" else "星界果园")
	get_tree().auto_accept_quit=true
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_build_shell()
	Locale.language_changed.connect(_on_language_changed)
	menu_music=preload("res://scripts/fusion_3d/frontend_music.gd").start(self)
	if Accounts.account.is_empty():show_login(false)
	else:await show_characters()
func _process(delta: float) -> void:
	angle+=delta
	if is_instance_valid(preview):preview.rotation.y=sin(angle*.35)*.28
func style(color: String) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=Color(color)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(24)
	return box
func text(parent: Node,value: String,size: int=20,color: String="d9e1ed") -> Label:
	var node:=Label.new()
	node.text=ui(value)
	node.add_theme_font_size_override("font_size",size)
	node.modulate=Color(color)
	parent.add_child(node)
	return node
func action(parent: Node,value: String,callback: Callable,kind: String="normal") -> Button:
	var node:=Button.new()
	node.text=ui(value)
	node.custom_minimum_size.y=50 if size.x<760 else 58
	node.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size",21)
	if kind=="primary":node.add_theme_color_override("font_color",Color("fff2c6"));node.add_theme_font_size_override("font_size",23)
	elif kind=="danger":node.add_theme_color_override("font_color",Color("ffb4aa"));node.modulate=Color("d79b9b")
	elif kind=="quiet":node.modulate=Color("a9b5c6")
	if kind!="primary":_skin_flat_button(node,kind)
	node.pressed.connect(func():
		if busy:return
		busy=true
		_set_enabled(self,false)
		await callback.call()
		if not is_inside_tree():return
		busy=false
		_set_enabled(self,true))
	parent.add_child(node)
	return node

func _skin_flat_button(node: Button,kind: String="normal") -> void:
	var ui=preload("res://scripts/fusion_3d/frontend_theme.gd")
	node.add_theme_stylebox_override("normal",ui.button_style())
	node.add_theme_stylebox_override("hover",ui.button_style(true))
	node.add_theme_stylebox_override("pressed",ui.button_style(true))
	node.add_theme_stylebox_override("focus",StyleBoxEmpty.new())
func _set_enabled(node: Node,value: bool) -> void:
	if node is BaseButton:node.disabled=not value
	if node is LineEdit:node.editable=value
	for child in node.get_children():_set_enabled(child,value)
func field(parent: Node,title: String,secret: bool=false) -> LineEdit:
	text(parent,title,17,"9caec6")
	var node:=LineEdit.new()
	node.secret=secret
	node.custom_minimum_size.y=46 if size.x<760 else 52
	node.add_theme_font_size_override("font_size",22)
	parent.add_child(node)
	return node
func _build_shell() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme=preload("res://scripts/fusion_3d/frontend_theme.gd").make_theme()
	var background:=TextureRect.new()
	background.name="AcademyBackdrop"
	background.texture=load("res://assets/ui/academy_frontend/login_background.png")
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade:=ColorRect.new();shade.color=Color("06111dc0");shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(shade)
	shell_margin=MarginContainer.new();shell_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shell_margin)
	shell_stack=VBoxContainer.new();shell_stack.add_theme_constant_override("separation",18);shell_margin.add_child(shell_stack)
	var masthead:=HBoxContainer.new();shell_stack.add_child(masthead)
	masthead_crest=TextureRect.new();masthead_crest.texture=preload("res://scripts/fusion_3d/frontend_theme.gd").icon("star")
	masthead_crest.custom_minimum_size=Vector2(54,54);masthead_crest.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;masthead_crest.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;masthead.add_child(masthead_crest)
	var brand:=VBoxContainer.new();brand.add_theme_constant_override("separation",2);masthead.add_child(brand)
	var brand_title:=text(brand,"星 界 果 园",30,"f1d395");brand_title.name="BrandTitle"
	brand_caption=text(brand,"ARCANE ACADEMY  ·  TINY LAZE STUDIO",13,"91a9ba")
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;masthead.add_child(spacer)
	masthead_trail=text(masthead,"七大学院 · 联机冒险",17,"c8d7dc")
	language_button=Button.new();language_button.text="中文 / English";language_button.tooltip_text="切换语言 / Switch language";language_button.custom_minimum_size=Vector2(156,46);language_button.add_theme_font_size_override("font_size",18);_skin_flat_button(language_button,"quiet");language_button.pressed.connect(Locale.toggle);masthead.add_child(language_button)
	var row:=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",28);shell_stack.add_child(row)
	settings_button=Button.new();settings_button.name="SettingsButton";settings_button.text="Settings" if Locale.locale=="en" else "设置";settings_button.custom_minimum_size=Vector2(90,46);settings_button.add_theme_font_size_override("font_size",18);_skin_flat_button(settings_button,"quiet");settings_button.pressed.connect(func():GraphicsSettings.open_panel(self));masthead.add_child(settings_button)
	showcase=PanelContainer.new();showcase.custom_minimum_size.x=420;showcase.size_flags_horizontal=Control.SIZE_EXPAND_FILL;showcase.add_theme_stylebox_override("panel",StyleBoxEmpty.new());row.add_child(showcase)
	var left:=VBoxContainer.new();left.add_theme_constant_override("separation",8);showcase.add_child(left)
	var left_gap:=Control.new();left_gap.custom_minimum_size.y=28;left.add_child(left_gap)
	var journey:=text(left,"你的魔法旅程",30,"f6e6c0");journey.name="JourneyTitle"
	var journey_detail:=text(left,"选择角色，踏入寒冰岛。",18,"a9c1ca");journey_detail.name="JourneyDetail"
	var box:=SubViewportContainer.new();box.custom_minimum_size=Vector2(360,300);box.size_flags_vertical=Control.SIZE_EXPAND_FILL;box.stretch=true;left.add_child(box)
	preview_viewport=SubViewport.new();preview_viewport.size=Vector2i(570,650);preview_viewport.own_world_3d=true;preview_viewport.transparent_bg=true;preview_viewport.render_target_update_mode=SubViewport.UPDATE_WHEN_VISIBLE;box.add_child(preview_viewport)
	var placeholder:=CenterContainer.new();placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);placeholder.mouse_filter=Control.MOUSE_FILTER_IGNORE;box.add_child(placeholder)
	preview_status=text(placeholder,"选择角色后显示当前外观",18,"9fb2c4")
	preview_status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	account_card=PanelContainer.new();account_card.name="AccountCard";account_card.custom_minimum_size.x=610;account_card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	account_card.add_theme_stylebox_override("panel",preload("res://scripts/fusion_3d/frontend_theme.gd").panel());row.add_child(account_card)
	var stack:=VBoxContainer.new();stack.add_theme_constant_override("separation",12);account_card.add_child(stack)
	card_gap=Control.new();card_gap.custom_minimum_size.y=24;stack.add_child(card_gap)
	var passport_row:=HBoxContainer.new();stack.add_child(passport_row)
	var passport_pad:=Control.new();passport_pad.custom_minimum_size.x=52;passport_row.add_child(passport_pad)
	var passport:=text(passport_row,"学院通行证",15,"cfb37f");passport.name="PassportTitle"
	heading=text(stack,"",30,"f1e5d0")
	subtitle=text(stack,"",18,"aabfbd");subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var divider:=HSeparator.new();stack.add_child(divider)
	feedback=text(stack,"",17,"e5c888");feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;feedback.custom_minimum_size.y=24
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;stack.add_child(scroll)
	content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",10);scroll.add_child(content)
	bottom_guard=Control.new();bottom_guard.custom_minimum_size.y=28;stack.add_child(bottom_guard)
	resized.connect(_responsive);_responsive()

func _responsive() -> void:
	if shell_margin==null:return
	var compact:=size.x<1080
	showcase.visible=not compact
	brand_caption.visible=not compact
	masthead_trail.visible=not compact
	masthead_crest.custom_minimum_size=Vector2(42,42) if compact else Vector2(54,54)
	var narrow:=size.x<760
	var brand_title:=shell_stack.find_child("BrandTitle",true,false) as Label
	if brand_title!=null:brand_title.add_theme_font_size_override("font_size",20 if narrow else 30)
	if is_instance_valid(language_button):
		language_button.text="中 / EN" if narrow else "中文 / English"
		language_button.custom_minimum_size.x=100 if narrow else 156
	shell_stack.add_theme_constant_override("separation",8 if compact else 18)
	card_gap.custom_minimum_size.y=0 if compact else 24
	bottom_guard.custom_minimum_size.y=12 if compact else 28
	account_card.custom_minimum_size.x=0 if compact else 610
	var side:=18 if size.x<760 else 42
	var vertical:=8 if size.y<700 else 30
	for name in ["left","right"]:shell_margin.add_theme_constant_override("margin_"+name,side)
	for name in ["top","bottom"]:shell_margin.add_theme_constant_override("margin_"+name,vertical)
	if character_grid!=null:character_grid.columns=1 if size.x<760 else 2
func clear_page(title: String,detail: String) -> void:
	page_generation+=1
	heading.text=ui(title)
	subtitle.text=ui(detail)
	feedback.text=""
	character_grid=null
	for node in content.get_children():
		content.remove_child(node)
		node.queue_free()
func show_login(register: bool) -> void:
	current_page="login"
	registering=register
	clear_page("注册账号" if register else "欢迎回到学院","使用账号登录，管理你的角色与云存档。")
	username=field(content,"账号名 · 3–24 位字母、数字或下划线")
	username.max_length=24
	username.text=Accounts.last_username
	username.placeholder_text=ui("输入账号名")
	password=field(content,"密码 · 至少 8 个字符",true)
	password.max_length=128
	password.placeholder_text=ui("输入密码")
	if register:
		confirm=field(content,"再次输入密码",true)
		confirm.max_length=128
	var row:=HBoxContainer.new();content.add_child(row)
	action(row,"注册并登录" if register else "登录",submit_login,"primary")
	action(row,"已有账号" if register else "创建账号",func():show_login(not register),"quiet" if register else "primary")
	var connection:=VBoxContainer.new()
	content.add_child(connection)
	connection.hide()
	endpoint=field(connection,"账号服务器地址")
	endpoint.text=Accounts.server_url
	action(connection,"检查服务器连接",func():
		if not Accounts.configure_server(endpoint.text):feedback.text=ui("请输入有效的服务器地址。");return
		var result: Dictionary=await Accounts.api("/health")
		feedback.text=ui("服务器连接正常") if result.ok else ui("未连到服务器")
		feedback.modulate=Color("d9e1ed") if result.ok else Color("f06c6c"))
	text(connection,"默认账号服务：http://101.43.174.221:8787",17,"75879f")
	_show_default_preview(register)
func submit_login() -> void:
	if registering and password.text!=confirm.text:feedback.text=ui("两次输入的密码不一致。");return
	if not Accounts.configure_server(endpoint.text):feedback.text=ui("请输入有效的服务器地址。");return
	feedback.text=ui("正在连接账号服务器…")
	var result: Dictionary=await Accounts.authenticate(username.text.strip_edges(),password.text,registering)
	password.text=""
	if registering:confirm.text=""
	if result.ok:await show_characters()
	else:
		feedback.text=ui("未连到服务器") if int(result.get("status",0))==0 else str(result.error)
		feedback.modulate=Color("f06c6c")
func show_characters() -> void:
	current_page="characters"
	clear_page("选择角色",str(Accounts.account.get("username",""))+(" · Choose a wizard to continue" if Locale.locale=="en" else " · 选择一位巫师继续冒险"))
	_show_default_preview()
	var result: Dictionary=await Accounts.list_characters()
	if not result.ok:
		feedback.text=str(result.error)
		action(content,"重试",show_characters)
		action(content,"返回登录",func():await Accounts.logout();show_login(false))
		return
	_render_characters(result.characters)

func _render_characters(values: Array) -> void:
	current_page="characters"
	characters=values
	clear_page("选择角色",str(Accounts.account.get("username",""))+(" · Choose a wizard to continue" if Locale.locale=="en" else " · 选择一位巫师继续冒险"))
	if characters.is_empty():text(content,"还没有角色，点击下方卡片创建你的第一位巫师。",21)
	character_grid=GridContainer.new();character_grid.columns=1 if size.x<760 else 2;character_grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;character_grid.add_theme_constant_override("h_separation",12);character_grid.add_theme_constant_override("v_separation",12);content.add_child(character_grid)
	for character in characters:
		var i:=SCHOOLS.find(str(character.school))
		var title: String=str(character.name)+"\n"+school_name(i)+"  ·  XP "+str(character.xp)+"  ·  "+("Progress " if Locale.locale=="en" else "进度 ")+str(character.step)
		var card:=action(character_grid,title,func():await show_selected(character))
		card.custom_minimum_size=Vector2(250,102);card.alignment=HORIZONTAL_ALIGNMENT_LEFT
		card.icon=ArtRegistryV2.texture(StringName("school_badge_"+str(character.school)));card.expand_icon=true;card.add_theme_constant_override("icon_max_width",48)
	var create:=action(character_grid,("＋  Create character\n" if Locale.locale=="en" else "＋  创建新角色\n")+str(characters.size())+(" / 12 characters" if Locale.locale=="en" else " / 12 个角色"),show_create)
	create.custom_minimum_size=Vector2(250,102);create.alignment=HORIZONTAL_ALIGNMENT_LEFT
	var divider:=HSeparator.new();content.add_child(divider)
	var footer:=HBoxContainer.new()
	content.add_child(footer)
	action(footer,"账号安全",show_password,"quiet")
	action(footer,"退出登录",func():await Accounts.logout();show_login(false),"quiet")

func _show_default_preview(initial: bool=false) -> void:
	var saved: Dictionary={} if initial else Accounts.last_character_preview
	var school:=str(saved.get("school","myth"))
	if school not in SCHOOLS:school="myth"
	var outfit: Dictionary=get_node("/root/Wardrobe").creation_outfit(school,"female","f1")
	var appearance: Variant=saved.get("appearance",{})
	if appearance is Dictionary and not appearance.is_empty():outfit=appearance.duplicate(true)
	_apply_preview(school,outfit)

func _apply_preview(school: String,outfit: Dictionary) -> void:
	_ensure_preview()
	if not is_instance_valid(preview):return
	preview.school_id=school
	preview.apply_outfit(outfit)
	preview.show()
	preview_status.hide()

func _preview_character(character: Dictionary) -> void:
	var generation:=page_generation
	var session:=Accounts.session_generation
	var school:=str(character.school)
	if is_instance_valid(preview):preview.hide()
	preview_status.text=ui("正在读取人物外观…")
	preview_status.show()
	var outfit: Dictionary=await _selected_character_outfit(character)
	if generation!=page_generation or session!=Accounts.session_generation:return
	if outfit.is_empty():
		preview_status.text=ui("暂时无法读取角色外观，请重试。")
		action(content,"重试",func():await show_selected(character))
		return
	_apply_preview(school,outfit)

func show_selected(character: Dictionary) -> void:
	current_page="selected"
	selected=character
	clear_page(str(character.name),("Quest progress " if Locale.locale=="en" else "任务进度 ")+str(character.step)+" · XP "+str(character.xp)+(" · Cloud revision " if Locale.locale=="en" else " · 云存档版本 ")+str(character.revision))
	_preview_character(character)
	var school_index:=SCHOOLS.find(str(character.school))
	var identity:=HBoxContainer.new();content.add_child(identity)
	var badge:=TextureRect.new();badge.texture=ArtRegistryV2.texture(StringName("school_badge_"+str(character.school)));badge.custom_minimum_size=Vector2(62,62);badge.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;badge.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;identity.add_child(badge)
	text(identity,school_name(school_index)+("\nLevel progress " if Locale.locale=="en" else "\n等级进度 ")+str(character.step)+"  ·  XP "+str(character.xp),19,"c7d6dc")
	action(content,"进入寒冰岛",func():travel_requested=true;await enter_selected(),"primary")
	var divider:=HSeparator.new();content.add_child(divider)
	text(content,"角色资料",17,"bd9f70")
	name_field=field(content,"角色名称")
	name_field.text=str(character.name)
	name_field.max_length=20
	var controls:=HBoxContainer.new();content.add_child(controls)
	action(controls,"保存名字",func():
		var result: Dictionary=await Accounts.api("/v1/characters/"+str(selected.id),HTTPClient.METHOD_PATCH,{"name":name_field.text})
		if result.ok:await show_characters()
		else:feedback.text=str(result.error))
	action(controls,"返回列表",show_characters,"quiet")
	action(content,"删除这个角色…",show_delete,"danger")

func _selected_character_outfit(character: Dictionary) -> Dictionary:
	var store:=get_node("/root/Wardrobe")
	var outfit: Dictionary=await Accounts.preview_character(character)
	if outfit.is_empty():return {}
	return store.clean_teen(outfit) if str(outfit.get("model_style","teen"))=="teen" else outfit

func enter_selected() -> void:
	feedback.text=ui("正在读取角色存档…")
	var result: Dictionary=await Accounts.activate_character(str(selected.id))
	if result.ok:
		_handoff_loading()
		get_tree().change_scene_to_file("res://scenes/worlds/world_atlas.tscn" if travel_requested or OS.has_feature("mobile_lite") else "res://scenes/fusion_3d/academy_town.tscn")
	elif result.get("code","")=="save_conflict":show_conflict()
	else:feedback.text=str(result.error)
func show_conflict() -> void:
	current_page="conflict"
	clear_page("选择要保留的进度","本地和云端都有更新，选择前会备份两个版本。")
	text(content,("Cloud revision: " if Locale.locale=="en" else "云端版本：")+str(Accounts.conflict.revision)+(" / Local based on: " if Locale.locale=="en" else "  /  本地基于版本：")+str(Accounts.revision),20)
	action(content,"使用云端存档",func():await resolve(false))
	action(content,"保留本地进度并上传",func():await resolve(true))
	action(content,"暂不处理，返回列表",func():Accounts.leave_character();await show_characters())
func resolve(keep_local: bool) -> void:
	var result: Dictionary=await Accounts.resolve_conflict(keep_local)
	if result.ok:
		_handoff_loading()
		get_tree().change_scene_to_file("res://scenes/worlds/world_atlas.tscn" if travel_requested or OS.has_feature("mobile_lite") else "res://scenes/fusion_3d/academy_town.tscn")
	else:feedback.text=str(result.error)
func show_create() -> void:
	current_page="create"
	clear_page("创建新角色","全部选项直接点击；进入游戏后仍可在衣橱更换外观。")
	name_field=field(content,"角色名称 · 2–20 个字符")
	name_field.max_length=20
	school_choice=3;gender_choice=1;hair_choice=0;face_choice=0
	text(content,"所属学院",17,"bd9f70")
	var schools:=GridContainer.new();schools.columns=3 if size.x<760 else 4;schools.add_theme_constant_override("h_separation",8);schools.add_theme_constant_override("v_separation",8);content.add_child(schools)
	school_buttons.clear()
	for index in SCHOOLS.size():
		var picked:=index
		var choice:=Button.new();choice.text=school_name(index).trim_suffix("学院");choice.icon=ArtRegistryV2.texture(StringName("school_badge_"+SCHOOLS[index]));choice.expand_icon=true;choice.add_theme_constant_override("icon_max_width",28);choice.custom_minimum_size=Vector2(104,46);_skin_flat_button(choice);choice.pressed.connect(func():school_choice=picked;_refresh_creation_choices();update_preview());schools.add_child(choice);school_buttons.append(choice)
	text(content,"角色性别",17,"bd9f70")
	var gender_row:=HBoxContainer.new();content.add_child(gender_row)
	gender_buttons=_direct_choices(gender_row,["男生","女生"],func(index: int):gender_choice=index;hair_choice=0;face_choice=0;_build_creation_looks())
	text(content,"脸型",17,"bd9f70")
	creation_face_row=HFlowContainer.new();creation_face_row.add_theme_constant_override("h_separation",6);creation_face_row.add_theme_constant_override("v_separation",6);content.add_child(creation_face_row)
	text(content,"可染色发型",17,"bd9f70")
	creation_hair_row=HFlowContainer.new();creation_hair_row.add_theme_constant_override("h_separation",6);creation_hair_row.add_theme_constant_override("v_separation",6);content.add_child(creation_hair_row)
	_build_creation_looks()
	import_check=CheckBox.new()
	import_check.text=ui("导入这台电脑已有的冒险进度")
	import_check.visible=not Accounts.legacy_snapshot().is_empty()
	import_check.button_pressed=false
	content.add_child(import_check)
	text(content,"导入会沿用原队伍与外观；不勾选则从新生进度开始。",17,"9caec6")
	var create_row:=HBoxContainer.new();content.add_child(create_row)
	action(create_row,"创建并选择",submit_create,"primary")
	action(create_row,"返回列表",show_characters,"quiet")
	_refresh_creation_choices()
	await get_tree().process_frame
	_ensure_preview()
	update_preview()

func _direct_choices(parent: Container,names: Array,setter: Callable) -> Array[Button]:
	var result: Array[Button]=[]
	for index in names.size():
		var picked:=index
		var choice:=Button.new();choice.text=ui(names[index]);choice.custom_minimum_size=Vector2(92,46);_skin_flat_button(choice);choice.pressed.connect(func():setter.call(picked);_refresh_creation_choices();update_preview());parent.add_child(choice);result.append(choice)
	return result
func _refresh_creation_choices() -> void:
	for index in school_buttons.size():school_buttons[index].modulate=Color.WHITE if index==school_choice else Color("75869b")
	for index in gender_buttons.size():gender_buttons[index].modulate=Color.WHITE if index==gender_choice else Color("75869b")
	for index in hair_buttons.size():hair_buttons[index].modulate=Color.WHITE if index==hair_choice else Color("75869b")
	for index in face_buttons.size():face_buttons[index].modulate=Color.WHITE if index==face_choice else Color("75869b")
func _build_creation_looks() -> void:
	if not is_instance_valid(creation_hair_row):return
	var store:=get_node("/root/Wardrobe")
	var sex:="female" if gender_choice==1 else "male"
	creation_hairs=store.creation_options("teen_hair",sex);creation_faces=store.creation_options("teen_skin",sex)
	for row in [creation_hair_row,creation_face_row]:
		for child in row.get_children():row.remove_child(child);child.queue_free()
	hair_choice=clampi(hair_choice,0,maxi(0,creation_hairs.size()-1));face_choice=clampi(face_choice,0,maxi(0,creation_faces.size()-1))
	var hair_names: Array=[];var face_names: Array=[]
	for index in creation_hairs.size():hair_names.append(("Hairstyle %d" if Locale.locale=="en" else "发型 %d")%[index+1])
	for index in creation_faces.size():face_names.append(("Face %d" if Locale.locale=="en" else "脸 %d")%[index+1])
	hair_buttons=_direct_choices(creation_hair_row,hair_names,func(index: int):hair_choice=index)
	face_buttons=_direct_choices(creation_face_row,face_names,func(index: int):face_choice=index)
	for index in hair_buttons.size():hair_buttons[index].tooltip_text=str(creation_hairs[index].name)+(" · Dyeable" if Locale.locale=="en" else " · 可染色")
	for index in face_buttons.size():face_buttons[index].tooltip_text=str(creation_faces[index].name)

func update_preview() -> void:
	if not is_instance_valid(preview) or creation_hairs.is_empty() or creation_faces.is_empty():return
	var school: String=SCHOOLS[school_choice]
	var store:=get_node("/root/Wardrobe")
	var sex: String="female" if gender_choice==1 else "male"
	var outfit: Dictionary=store.creation_outfit(school,sex,str(creation_hairs[hair_choice].id),str(creation_faces[face_choice].id))
	preview.school_id=school
	preview.apply_outfit(outfit)
	feedback.text=ui("死亡学院 · 与幽影同行，守望灵魂的秘密。") if school=="death" else ""

func _ensure_preview() -> void:
	if is_instance_valid(preview) or not is_instance_valid(preview_viewport):return
	if is_instance_valid(preview_status):preview_status.text=ui("正在读取人物外观…")
	var environment:=WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color("cfdbf6")
	environment.environment.ambient_light_energy=.7
	preview_viewport.add_child(environment)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-30,-35,0)
	light.light_energy=1.2
	preview_viewport.add_child(light)
	var camera:=Camera3D.new()
	preview_viewport.add_child(camera)
	camera.position=Vector3(0,1.4,-4.7)
	camera.look_at(Vector3(0,1.18,0))
	camera.fov=34
	var wizard_scene:=load("res://scenes/characters/modular_wizard.tscn") as PackedScene
	if wizard_scene==null:
		if is_instance_valid(preview_status):preview_status.text=ui("人物预览资源读取失败")
		return
	preview=wizard_scene.instantiate()
	preview.follow_local_wardrobe=false
	preview_viewport.add_child(preview)
	if is_instance_valid(preview_status):preview_status.hide()
func submit_create() -> void:
	var sex:="female" if gender_choice==1 else "male"
	var creation: Dictionary=get_node("/root/Wardrobe").creation_outfit(SCHOOLS[school_choice],sex,str(creation_hairs[hair_choice].id),str(creation_faces[face_choice].id))
	var result: Dictionary=await Accounts.create_character(name_field.text,SCHOOLS[school_choice],sex,("f" if sex=="female" else "m")+str(mini(hair_choice+1,3)),import_check.button_pressed,creation)
	if result.ok:await show_selected(result.character)
	else:feedback.text=str(result.error)
func show_delete() -> void:
	current_page="delete"
	clear_page("删除角色",str(selected.name)+(" · Will be removed from your character list" if Locale.locale=="en" else " · 删除后将从角色列表移除"))
	name_field=field(content,"请输入完整角色名确认")
	action(content,"确认删除这个角色",func():
		var result: Dictionary=await Accounts.api("/v1/characters/"+str(selected.id),HTTPClient.METHOD_DELETE,{"confirm_name":name_field.text})
		if result.ok:await show_characters()
		else:feedback.text=str(result.error))
	action(content,"取消",func():await show_selected(selected))
func show_password() -> void:
	current_page="password"
	clear_page("修改密码","修改后，其他设备的登录会失效。")
	password=field(content,"原密码",true)
	confirm=field(content,"新密码 · 至少 8 个字符",true)
	action(content,"更新密码",func():
		var result: Dictionary=await Accounts.change_password(password.text,confirm.text)
		password.text=""
		confirm.text=""
		feedback.text=ui("密码已更新。") if result.ok else str(result.error))
	action(content,"返回角色列表",show_characters)

func _handoff_loading() -> void:
	if not travel_requested:return
	preload("res://scripts/worlds/world_loading.gd").obtain(get_tree()).begin("正在前往寒冰岛…",menu_music)
	menu_music=null

