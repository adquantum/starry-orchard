extends VBoxContainer
const ModernSkin=preload("res://scripts/fusion_3d/modern_inventory_skin.gd")
signal preview_requested(value: Dictionary)
signal preview_cleared
const Rules=preload("res://scripts/worlds/equipment_rules.gd")
const ShopSkin=preload("res://scripts/fusion_3d/shop_ui_skin.gd")
var shop_id:="treasure"
var store: Node
var offers: Array=[]
var selected: Dictionary={}
var snapshot: Dictionary={}
var busy:=false
var request_id:=""
var request_body:=""
var balance: HBoxContainer
var status: Label
var listing: GridContainer
var detail: Label
var quantity: SpinBox
var purchase: Button
var preview_button: Button
var confirmation: ConfirmationDialog
var connected_state:=false
var offer_buttons: Dictionary={}
const PAGE_SIZE:=12
const CATEGORIES:={"全部":"","武器":"teen_weapon","帽子":"teen_hat","衣服":"teen_clothes","鞋子":"teen_boots","背饰":"teen_back"}
var filters: VBoxContainer
var category: HFlowContainer
var category_index:=0
var shop_tabs: TabBar
var search: LineEdit
var pager: HBoxContainer
var page_label: Label
var previous_page: Button
var next_page: Button
var page_number:=0
var scroll: ScrollContainer

func _ready() -> void:
	store=get_node("/root/Wardrobe")
	add_theme_constant_override("separation",8)
	shop_tabs=TabBar.new();shop_tabs.custom_minimum_size.y=48
	for title in ["宝藏卡","装备","装扮"]:shop_tabs.add_tab(title)
	for index in 3:shop_tabs.set_tab_icon(index,ModernSkin.icon(["cards","equipment","appearance"][index]));shop_tabs.set_tab_icon_max_width(index,28)
	shop_tabs.tab_changed.connect(func(index: int):open_shop(["treasure","equipment","cosmetic"][index]));add_child(shop_tabs)
	balance=preload("res://scripts/fusion_3d/currency_badge.gd").new();add_child(balance);balance.hide()
	filters=VBoxContainer.new();filters.add_theme_constant_override("separation",8);add_child(filters)
	category=HFlowContainer.new();category.add_theme_constant_override("h_separation",5);category.add_theme_constant_override("v_separation",5);filters.add_child(category)
	var category_number:=0
	for title in CATEGORIES:
		var picked:=category_number
		var choice:=_button(category,title,func():category_index=picked;page_number=0;refresh());choice.toggle_mode=true;choice.set_meta("category_index",picked);ModernSkin.button(choice,["all","weapon","hat","appearance","boots","back"][picked]);choice.add_theme_font_size_override("font_size",15)
		category_number+=1
	search=LineEdit.new();search.placeholder_text="搜索商品";search.clear_button_enabled=true;search.custom_minimum_size.y=40;filters.add_child(search)
	search.text_changed.connect(func(_value: String):page_number=0;refresh())
	scroll=ScrollContainer.new();scroll.size_flags_vertical=SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	listing=GridContainer.new();listing.columns=3;listing.add_theme_constant_override("h_separation",8);listing.add_theme_constant_override("v_separation",8);listing.size_flags_horizontal=SIZE_EXPAND_FILL;listing.add_theme_constant_override("separation",6);scroll.add_child(listing)
	pager=HBoxContainer.new();pager.add_theme_constant_override("separation",6);add_child(pager)
	previous_page=_button(pager,"‹",func():page_number-=1;refresh())
	page_label=_label(pager,"");page_label.size_flags_horizontal=SIZE_EXPAND_FILL;page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	next_page=_button(pager,"›",func():page_number+=1;refresh())
	previous_page.custom_minimum_size=Vector2(48,30);next_page.custom_minimum_size=Vector2(48,30)
	detail=_label(_frame(self,"DetailPanel"),"")
	var actions:=HBoxContainer.new();add_child(actions)
	actions.add_theme_constant_override("separation",6)
	quantity=SpinBox.new();quantity.min_value=1;quantity.max_value=40;quantity.step=1;quantity.custom_minimum_size.x=90;actions.add_child(quantity);quantity.value_changed.connect(func(_value: float):update_detail())
	preview_button=_button(actions,"试穿预览",preview_selected)
	purchase=_button(actions,"购买",confirm_purchase);purchase.size_flags_horizontal=SIZE_EXPAND_FILL
	status=_label(self,"");status.add_theme_font_size_override("font_size",15)
	confirmation=ConfirmationDialog.new();confirmation.title="确认购买";confirmation.ok_button_text="确认支付";confirmation.cancel_button_text="再想想";confirmation.confirmed.connect(buy);add_child(confirmation)
	confirmation.add_theme_stylebox_override("panel",ShopSkin.panel())
	ShopSkin.apply_button(confirmation.get_ok_button());ShopSkin.apply_button(confirmation.get_cancel_button())
	store.changed.connect(func(_school: String):
		if visible and not busy:refresh())

func _label(parent: Node,text: String) -> Label:
	var node:=Label.new();node.text=text;node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;node.add_theme_color_override("font_color",ShopSkin.INK);node.add_theme_font_size_override("font_size",17);parent.add_child(node);return node

func _frame(parent: Node,frame_name: String) -> PanelContainer:
	var panel:=PanelContainer.new();panel.name=frame_name;panel.add_theme_stylebox_override("panel",ShopSkin.panel());parent.add_child(panel);return panel

func _button(parent: Node,text: String,callback: Callable) -> Button:
	var button:=Button.new();button.text=text;ShopSkin.apply_button(button);parent.add_child(button);button.pressed.connect(callback);return button

func connected() -> bool:
	return Accounts.character_ready and is_instance_valid(Accounts.game_transport) and Accounts.game_transport.connected and Accounts.game_transport.authenticated

func _process(_delta: float) -> void:
	var now:=connected()
	if connected_state!=now:
		connected_state=now
		if is_instance_valid(purchase):update_detail()

func open_shop(value: String) -> void:
	shop_id=value;selected.clear();quantity.value=1;page_number=0;category_index=0;shop_tabs.set_block_signals(true);shop_tabs.current_tab=["treasure","equipment","cosmetic"].find(value);shop_tabs.set_block_signals(false);search.set_text("");preview_cleared.emit();status.text="";refresh()

func refresh() -> void:
	confirmation.hide();snapshot=store.progression()
	for child in listing.get_children():listing.remove_child(child);child.queue_free()
	offers.clear();offer_buttons.clear()
	var path:="res://resources/fusion_3d/weekend_shop_catalog.json"
	filters.show();category.visible=shop_id!="treasure"
	for choice in category.get_children():choice.set_pressed_no_signal(int(choice.get_meta("category_index"))==category_index)
	var sex:=str(snapshot.get("appearance",{}).get("gender","male"))
	var wanted: String=CATEGORIES.values()[category_index]
	if FileAccess.file_exists(path):
		var catalog: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if catalog is Dictionary:
			for offer in catalog.get("offers",[]):
				if str(offer.get("shop_id",""))!=shop_id or str(offer.get("school","any")) not in ["any",str(snapshot.get("school",""))]:continue
				if str(offer.get("gender","both")) not in ["both",sex]:continue
				if shop_id!="treasure":
					var slot: String={"staff":"teen_weapon","hat":"teen_hat","robe":"teen_clothes","boots":"teen_boots","cape":"teen_back"}.get(str(offer.get("slot","")),str(offer.get("slot","")))
					if not wanted.is_empty() and slot!=wanted:continue
				if not search.text.is_empty() and not offer_title(offer).to_lower().contains(search.text.to_lower()):continue
				offers.append(offer)
	balance.refresh(snapshot)
	var page_count:=maxi(1,ceili(offers.size()/float(PAGE_SIZE)))
	page_number=clampi(page_number,0,page_count-1);pager.visible=page_count>1
	page_label.text="%d / %d · %d 件"%[page_number+1,page_count,offers.size()]
	previous_page.disabled=busy or page_number==0;next_page.disabled=busy or page_number==page_count-1
	scroll.scroll_vertical=0
	for offer in offers.slice(page_number*PAGE_SIZE,(page_number+1)*PAGE_SIZE):
		var button:=_button(listing,"",func():selected=offer.duplicate(true);quantity.value=1;update_detail())
		button.custom_minimum_size=Vector2(180,220);button.size_flags_horizontal=SIZE_EXPAND_FILL;button.disabled=busy
		button.tooltip_text=offer_title(offer)+"\n"+("账号已拥有" if owned(offer) else "%d 赋能"%int(offer.cost_empower))
		button.set_meta("offer_id",str(offer.id));offer_buttons[str(offer.id)]=button
		var row:=VBoxContainer.new();row.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left=10;row.offset_right=-10;row.offset_top=10;row.offset_bottom=-10;row.add_theme_constant_override("separation",10);button.add_child(row)
		var icon:=TextureRect.new();icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;icon.custom_minimum_size=Vector2(128,122);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.texture=offer_texture(offer);row.add_child(icon)
		var column:=VBoxContainer.new();column.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.size_flags_horizontal=SIZE_EXPAND_FILL;column.alignment=BoxContainer.ALIGNMENT_CENTER;column.add_theme_constant_override("separation",2);row.add_child(column)
		var title:=_label(column,offer_title(offer));title.name="OfferTitle";title.mouse_filter=Control.MOUSE_FILTER_IGNORE;title.custom_minimum_size.y=38;title.add_theme_font_size_override("font_size",15);title.max_lines_visible=2;title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		var price:=_label(column,"已拥有" if owned(offer) else "%d 赋能"%int(offer.cost_empower));price.mouse_filter=Control.MOUSE_FILTER_IGNORE;price.add_theme_font_size_override("font_size",16);price.add_theme_color_override("font_color",Color("8dd9ba") if owned(offer) else ModernSkin.ACCENT)
	if offers.is_empty():_label(listing,"没有符合条件的商品。" if not search.text.is_empty() or not wanted.is_empty() else "商店目录暂不可用，请更新客户端或稍后再试。")
	update_detail()

func owned(offer: Dictionary) -> bool:
	if shop_id=="treasure":return false
	var key:=str(offer.get("slot",""))+":"+str(offer.get("tier",""))
	if shop_id=="equipment":return snapshot.get("equipment_unlocks",[]).has(key)
	if offer.has("cosmetic_id"):return store.cosmetic_id_owned(str(offer.cosmetic_id))
	for cosmetic in store.economic_cosmetics:
		if str(cosmetic.slot)==str(offer.get("slot","")) and str(cosmetic.get("tier",""))==str(offer.get("tier","")) and str(cosmetic.school)==str(snapshot.get("school","")):
			return store.cosmetic_id_owned(str(cosmetic.id))
	return false

func offer_title(offer: Dictionary) -> String:
	var sex:=str(snapshot.get("appearance",{}).get("gender","male"))
	var display: Dictionary=offer.get("display_by_school",{}).get(str(snapshot.get("school","")),{}).get(sex,{})
	var title:=str(display.get("title",offer.get("title",offer.get("id",""))))
	var parts:=title.strip_edges().split(" · ")
	if parts.size()>1 and parts[-1].is_valid_int():parts.remove_at(parts.size()-1)
	title=" · ".join(parts)
	return str(offer.get("tier","")).to_upper()+" · "+title if str(offer.get("kind",""))=="equipment" else title

func offer_texture(offer: Dictionary) -> Texture2D:
	if str(offer.get("kind",""))=="treasure":
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://resources/battle_v2/cards/treasure_cards.json"))
		if data is Dictionary:
			for card in data.get("cards",[]):
				if str(card.get("id",""))==str(offer.get("card_id","")) and ResourceLoader.exists(str(card.get("art_path",""))):return load(str(card.art_path))
	else:
		if offer.has("cosmetic_id"):return store.cosmetic_texture(str(offer.cosmetic_id))
		return store.equipment_texture({"school":snapshot.get("school",""),"slot":offer.get("slot",""),"tier":offer.get("tier","")})
	return null

func update_detail() -> void:
	for id in offer_buttons:
		var button: Button=offer_buttons[id]
		button.add_theme_stylebox_override("normal",ShopSkin.panel(Color("d8e8da")) if id==str(selected.get("id","")) else ShopSkin.panel())
		button.disabled=busy
	if selected.is_empty():
		detail.text="选择一件商品查看详情。";purchase.text="选择商品";purchase.disabled=true;preview_button.hide();quantity.hide();return
	quantity.visible=shop_id=="treasure";quantity.editable=not busy
	preview_button.visible=shop_id=="cosmetic";preview_button.disabled=busy
	var count:=int(quantity.value) if shop_id=="treasure" else 1
	var cost:=int(selected.cost_empower)*count
	var available:=maxi(0,int(snapshot.get("treasure_inventory",{}).get("tc_empower",0))-int(snapshot.get("treasure_reserved",{}).get("tc_empower",0)))
	detail.text=offer_title(selected)+"\n"+("账号已拥有此权益。" if owned(selected) else "共 %d 赋能 · 购买后可用 %d"%[cost,maxi(0,available-cost)])
	if shop_id=="cosmetic":detail.text+=" · 永久装扮，不改变属性"
	if shop_id=="equipment":
		detail.text+="\n同步解锁对应外观，可在衣柜中选择穿戴。"
		var rules:=Rules.new();rules.load_default()
		var id:="eq_"+str(snapshot.get("school",""))+"_"+str(selected.slot)+"_"+str(selected.tier)
		var comparison: Dictionary=rules.compare_item(snapshot,str(selected.slot),id)
		if bool(comparison.get("ok",false)):
			var delta: Dictionary=comparison.delta
			detail.text+="\n相比当前：HP %+d · 伤害 %+.0f%% · 抗性 %+.0f%%"%[int(delta.max_hp),float(delta.damage),float(delta.resistance)]
	var prerequisite:=false
	if shop_id=="equipment":
		var economy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/weekend_treasure_economy.json"))
		for requirement in economy.get("exchange",{}).get("prerequisites",{}).get(str(selected.get("tier","")),[]):
			var key:=str(requirement).replace("{slot}",str(selected.slot))
			if not snapshot.get("equipment_unlocks",[]).has(key):prerequisite=true;detail.text+="\n需先解锁该槽 "+key.get_slice(":",1).to_upper()+"。"
	purchase.text="已拥有" if owned(selected) else "支付 %d 赋能 · 购买"%cost
	purchase.disabled=busy or not connected() or owned(selected) or available<cost or prerequisite
	if not connected():status.text="已断线，连接恢复后才能购买。"
	elif available<cost and not owned(selected):status.text="赋能不足；本场保留的卡不能支付。"
	elif not busy:status.text=""

func preview_selected() -> void:
	if selected.is_empty() or shop_id!="cosmetic":return
	var value: Dictionary=store.preview_cosmetic_id(str(selected.cosmetic_id)) if selected.has("cosmetic_id") else store.preview_equipment_cosmetic(str(selected.slot),str(selected.tier))
	if not value.is_empty():preview_requested.emit(value)

func confirm_purchase() -> void:
	if busy or purchase.disabled:return
	confirmation.dialog_text=detail.text+"\n消耗赋能卡后，这些卡将不能再施放。"
	confirmation.popup_centered(Vector2i(510,240))

func buy() -> void:
	if busy or selected.is_empty() or not connected():return
	var count:=int(quantity.value) if shop_id=="treasure" else 1
	var fingerprint:=str(snapshot.get("character_id",""))+":"+str(selected.id)+":"+str(count)
	if request_body!=fingerprint or request_id.is_empty():request_body=fingerprint;request_id="shop-"+str(Time.get_unix_time_from_system())+"-"+str(Time.get_ticks_usec())
	busy=true;update_detail();status.text="正在等待确认…"
	var result: Dictionary
	if shop_id=="equipment":result=await Accounts.exchange_equipment(str(selected.slot),str(selected.tier),{"tc_empower":int(selected.cost_empower)},request_id)
	elif Accounts.has_method("buy_shop_offer"):result=await Accounts.call("buy_shop_offer",str(selected.id),count,request_id)
	else:result={"ok":false,"code":"service_unavailable"}
	busy=false
	if bool(result.get("ok",false)):request_id="";request_body=""
	refresh()
	var code:=str(result.get("code","unknown"))
	if bool(result.get("ok",false)):status.text="已拥有，没有重复扣款。" if code=="already_unlocked" else "购买成功，权益已到账。"
	elif code=="catalog_version_mismatch":status.text="商品目录已更新，请更新客户端后再购买。"
	else:status.text="购买未完成："+str(result.get("error",code))+"；未应用本地扣款。"
