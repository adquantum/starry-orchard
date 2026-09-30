extends Control
signal closed
const ModernSkin=preload("res://scripts/fusion_3d/modern_inventory_skin.gd")
const BOOK_SIZE=Vector2(1200,840)
const TABS={"cards":"卡组","equipment":"装备","appearance":"装扮","personal":"个人形象","shop":"商店"}
var loadout: RefCounted
var builder: Control
var page: Control
var book: Control
var identity: Label
var tab_buttons: Dictionary={}
var active_tab:="cards"
var last_shop:="treasure"
var deck_initialized:=false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);z_index=100
	var shade:=ColorRect.new();shade.color=Color(0.05,0.04,0.03,0.22);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	book=Control.new();book.size=BOOK_SIZE;add_child(book)
	book.theme=ModernSkin.make_theme()
	var background:=Panel.new();background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.add_theme_stylebox_override("panel",ModernSkin.panel(Color("0e1a29"),Color("46617b"),0));background.mouse_filter=MOUSE_FILTER_IGNORE;book.add_child(background)
	preload("res://scenes/battle_v2/ui/compact_battle_skin.gd").outline(background)
	# Content is clipped below navigation, so embedded pages cannot intercept its clicks.
	var body:=Control.new();body.position=Vector2(20,112);body.size=Vector2(1160,708);body.clip_contents=true;book.add_child(body)
	builder=preload("res://scenes/battle_v2/ui/deck_builder_panel_v2.gd").new();builder.embedded=true;builder.loadout=loadout;body.add_child(builder)
	page=preload("res://scripts/fusion_3d/teen_wardrobe_panel.gd").new();page.embedded=true
	page.profile=str(get_node("/root/Wardrobe").progression().get("school",Accounts.active_character.get("school","fire")))
	body.add_child(page);page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var header:=HBoxContainer.new();header.position=Vector2(24,18);header.size=Vector2(1020,58);header.add_theme_constant_override("separation",10);book.add_child(header)
	for id in TABS:
		var button:=Button.new();button.text=TABS[id];button.tooltip_text=TABS[id];button.toggle_mode=true;button.custom_minimum_size=Vector2(168,56);ModernSkin.button(button,id);header.add_child(button)
		button.pressed.connect(open_tab.bind(str(id)));tab_buttons[id]=button
	var close_button:=Button.new();close_button.text="×";close_button.tooltip_text="关闭 · Esc";close_button.position=Vector2(1124,20);close_button.size=Vector2(50,50);ModernSkin.button(close_button);book.add_child(close_button);close_button.pressed.connect(close)
	identity=Label.new();identity.position=Vector2(30,84);identity.size=Vector2(780,24);identity.add_theme_color_override("font_color",ModernSkin.MUTED);book.add_child(identity)
	var currency:=preload("res://scripts/fusion_3d/currency_badge.gd").new();currency.compact=true;currency.position=Vector2(960,81);book.add_child(currency);currency.amount.add_theme_color_override("font_color",ModernSkin.INK)
	get_viewport().size_changed.connect(_fit);_fit();hide()
	visibility_changed.connect(func():
		if not visible and is_instance_valid(page):page.end_shop_preview())

func _fit() -> void:
	var extent:=get_viewport_rect().size
	book.scale=Vector2.ONE*maxf(0.1,minf(1.0,minf((extent.x-40)/BOOK_SIZE.x,(extent.y-40)/BOOK_SIZE.y)))
	book.position=(extent-BOOK_SIZE*book.scale)*0.5

func open_tab(tab_id: String) -> void:
	if tab_id=="shop":open_shop(str(page.shop_page.shop_id) if is_instance_valid(page.shop_page) else last_shop);return
	if not TABS.has(tab_id):tab_id="equipment"
	active_tab=tab_id;show();_fit();page.end_shop_preview()
	for id in tab_buttons:tab_buttons[id].set_pressed_no_signal(id==tab_id)
	identity.text=str(Accounts.active_character.get("name","学徒"))+" · "+Locale.text("SCHOOL_"+page.profile.to_upper())
	builder.visible=tab_id=="cards";page.visible=tab_id!="cards"
	if tab_id=="cards":
		if loadout!=null and not deck_initialized:
			builder.set_character_context(identity.text,[]);builder.open(loadout.content,loadout.counts());deck_initialized=true
		elif deck_initialized:builder.resume_embedded()
	else:page.set_view(tab_id)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func open_shop(shop_id: String) -> void:
	if shop_id not in ["treasure","equipment","cosmetic"]:return
	last_shop=shop_id;active_tab="shop";show();_fit();builder.hide();page.show()
	for id in tab_buttons:tab_buttons[id].set_pressed_no_signal(id=="shop")
	identity.text="港口商店 · "+str(Accounts.active_character.get("name","学徒"))
	page.open_shop(shop_id);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func close() -> void:
	page.end_shop_preview();builder.close();hide();closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close();get_viewport().set_input_as_handled()
