extends VBoxContainer
## UI only. All rights, prices, inventory and calculations come from shared sources.
const ModernSkin=preload("res://scripts/fusion_3d/modern_inventory_skin.gd")
const Rules=preload("res://scripts/worlds/equipment_rules.gd")
const SLOT_NAMES={"staff":"法杖","hat":"帽子","robe":"衣服","boots":"鞋子","cape":"披风"}
var selected_slot:="staff"
var slot_tabs: TabBar
var store: Node
var rules: RefCounted
var snapshot: Dictionary={}
var selected: Dictionary={}
var payment: Dictionary={}
var busy:=false
var request_id:=""
var request_body:=""
var body: VBoxContainer
var status: Label
var confirm: ConfirmationDialog
var payment_summary: Label
var buy_button: Button
var refresh_button: Button
var price:=0
var economy: Dictionary={}
var connected_state:=false

func _connected() -> bool:
	var accounts:=get_node_or_null("/root/Accounts")
	return accounts!=null and accounts.character_ready and is_instance_valid(accounts.game_transport) and accounts.game_transport.connected and accounts.game_transport.authenticated

func _process(_delta: float) -> void:
	var available:=_connected()
	if is_instance_valid(refresh_button):refresh_button.disabled=busy or not available
	if available==connected_state:return
	connected_state=available
	if is_instance_valid(body):
		refresh()
		status.text="连接已恢复，可继续操作。" if available else "已断线，重连后才能兑换或换装。"

func _ready() -> void:
	store=get_node("/root/Wardrobe")
	connected_state=_connected()
	var top:=HBoxContainer.new();add_child(top)
	_text(top,"属性装备",19).size_flags_horizontal=SIZE_EXPAND_FILL
	refresh_button=_button(top,"刷新权益",refresh_account)
	status=_text(self,"",15)
	slot_tabs=TabBar.new();slot_tabs.custom_minimum_size.y=48;add_child(slot_tabs)
	var index:=0
	for slot in SLOT_NAMES:
		slot_tabs.add_tab(SLOT_NAMES[slot]);slot_tabs.set_tab_icon(index,ModernSkin.icon({"staff":"weapon","hat":"hat","robe":"appearance","boots":"boots","cape":"back"}[slot]));slot_tabs.set_tab_icon_max_width(index,28);index+=1
	slot_tabs.tab_changed.connect(func(chosen: int):selected_slot=SLOT_NAMES.keys()[chosen];selected.clear();refresh())
	var scroll:=ScrollContainer.new();scroll.size_flags_vertical=SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",10);scroll.add_child(body)
	confirm=ConfirmationDialog.new();confirm.title="确认消耗宝藏卡";confirm.ok_button_text="确认兑换";confirm.cancel_button_text="继续挑选";confirm.confirmed.connect(exchange);add_child(confirm)
	store.changed.connect(func(_school: String):
		if not busy:refresh())
	refresh()

func _text(parent: Node,value: String,font_size: int=16) -> Label:
	var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",font_size);parent.add_child(label);return label

func _button(parent: Node,value: String,callback: Callable) -> Button:
	var button:=Button.new();button.text=value;button.custom_minimum_size.y=36;button.pressed.connect(callback);parent.add_child(button);button.disabled=busy or not _connected();return button

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):return {}
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func refresh_account() -> void:
	if busy:return
	var accounts:=get_node("/root/Accounts")
	if not accounts.has_method("refresh_progression"):status.text="账号权益接口尚未就绪。";return
	busy=true;status.text="正在刷新…"
	var result: Dictionary=await accounts.call("refresh_progression")
	busy=false;refresh();show_result(result)

func refresh() -> void:
	if confirm.visible:confirm.hide()
	for child in body.get_children():body.remove_child(child);child.queue_free()
	buy_button=null;payment_summary=null
	snapshot=store.progression()
	if snapshot.is_empty():_text(body,"请先登录角色并刷新账号权益。");return
	if rules==null:
		rules=Rules.new()
		rules.call("load_default")
	economy=_read("res://resources/fusion_3d/weekend_treasure_economy.json")
	var result: Dictionary=rules.call("available_equipment",snapshot)
	if not bool(result.get("ok",false)):_text(body,"无法读取装备："+str(result.get("code","unknown")));return
	var current: Dictionary=rules.call("derive_loadout",snapshot)
	_text(body,"当前装备",20)
	_text(body,stats_text(current.get("bonuses",{})))
	var base_id: String={"fire":"fire_student","ice":"ice_guardian","storm":"storm_duelist","myth":"myth_scholar","life":"life_healer","death":"death_reaper","balance":"balance_adept"}.get(str(snapshot.get("school","")),"")
	for base in _read("res://resources/battle_v2/characters/characters_demo.json").get("characters",[]):
		if str(base.get("id",""))!=base_id:continue
		var actual: Dictionary=rules.call("build_battle_spec",base,snapshot)
		if bool(actual.get("ok",false)):_text(body,"下一场最大生命：%d"%int(actual.max_hp),18)
	body.tooltip_text="基础命中仍受负命中影响；额外超豆率为新豆直接生成概率。"
	var slots:=GridContainer.new();slots.columns=1;slots.size_flags_horizontal=SIZE_EXPAND_FILL;body.add_child(slots)
	for slot in SLOT_NAMES:
		if slot!=selected_slot:continue
		var column:=GridContainer.new();column.columns=3;column.add_theme_constant_override("h_separation",8);column.add_theme_constant_override("v_separation",8);column.size_flags_horizontal=SIZE_EXPAND_FILL;slots.add_child(column)
		for item in result.get("slots",{}).get(slot,[]):
			if not bool(item.get("unlocked",false)):continue
			var equipped: bool=str(current.get("equipped_stats",{}).get(slot,""))==str(item.id)
			var caption:=_display_title(str(store.equipment_display(item).title))+"\n"+str(item.tier).to_upper()+" · "+("已穿戴" if equipped else "可穿戴")
			var button:=_button(column,caption,func():selected=item.duplicate(true);payment.clear();refresh())
			button.gui_input.connect(_equipment_card_input.bind(button,item.duplicate(true)))
			button.icon=store.equipment_texture(item);button.expand_icon=true;button.add_theme_constant_override("icon_max_width",52);button.custom_minimum_size=Vector2(180,118);button.clip_text=true;ModernSkin.button(button);button.toggle_mode=true;button.set_pressed_no_signal(equipped)
			button.tooltip_text=str(store.equipment_display(item).title)+"\n"+stats_text(item.stats)+"\n双击穿戴"
			button.toggle_mode=true;button.set_pressed_no_signal(str(selected.get("id",""))==str(item.id))
	if not selected.is_empty() and str(selected.get("school",""))==str(snapshot.get("school","")):
		# Replace the selected view with fresh rights from the rules module.
		for item in result.get("slots",{}).get(str(selected.slot),[]):
			if str(item.id)==str(selected.id):selected=item.duplicate(true)
		build_selection(current)
	else:selected.clear();payment.clear()
	build_wings()

func _equipment_card_input(event: InputEvent,button: Button,item: Dictionary) -> void:
	if not event is InputEventMouseButton:return
	var click:=event as InputEventMouseButton
	if click.button_index!=MOUSE_BUTTON_LEFT or not click.pressed or not click.double_click:return
	if busy or button.disabled or not _connected() or not bool(item.get("unlocked",false)):return
	if str(snapshot.get("equipped_stats",{}).get(str(item.slot),""))==str(item.id):return
	selected=item.duplicate(true);payment.clear()
	equip_selected()

func stats_text(stats: Dictionary) -> String:
	var accuracy:=float(stats.get("accuracy_floor",0))
	var accuracy_text:="无" if accuracy<=0 else str(accuracy*100)+"%"
	return "HP +%d · 本系伤害 +%s%% · 抗性 +%s%%\n本系基础命中保障：%s · 额外超豆率 +%s%%" % [int(stats.get("max_hp",0)),str(stats.get("damage",0)),str(stats.get("resistance",0)),accuracy_text,str(float(stats.get("extra_power_pip_chance",0))*100)]

func card_name(id: String) -> String:
	# Card display names remain owned by the card catalog/localization.
	for path in ["res://resources/battle_v2/cards/treasure_cards.json","res://resources/battle_v2/cards/item_cards.json"]:
		var data:=_read(path)
		for card in data.get("cards",[]):
			if str(card.get("id",""))==id:return Locale.text(str(card.get("name_key",id)))
	return id

func build_selection(current: Dictionary) -> void:
	_text(body,"选择："+str(SLOT_NAMES[selected.slot])+" "+str(selected.tier).to_upper(),20)
	_text(body,"单件属性：\n"+stats_text(selected.stats))
	var comparisons: Array=[]
	for item in current.get("items",[]):
		if str(item.slot)==str(selected.slot):comparisons.append(stats_text(item.stats))
	if not comparisons.is_empty():_text(body,"当前同槽：\n"+str(comparisons[0]))
	var comparison: Dictionary=rules.call("compare_item",snapshot,str(selected.slot),str(selected.id))
	if bool(comparison.get("ok",false)):
		var delta: Dictionary=comparison.delta
		_text(body,"换装变化：HP %+d · 伤害 %+.0f%% · 抗性 %+.0f%% · 命中 %+.0f%% · 超豆 %+.0f%%"%[int(delta.max_hp),float(delta.damage),float(delta.resistance),float(delta.base_accuracy),float(delta.extra_power_pip_chance)])
	var names: PackedStringArray=[]
	for id in selected.get("item_cards",[]):names.append(card_name(str(id)))
	_text(body,"装备附卡："+("无" if names.is_empty() else "、".join(names)))
	if bool(selected.get("unlocked",false)):
		var equip:=_button(body,"穿戴这件属性装备 · 不改变外观",equip_selected)
		equip.disabled=busy or not _connected() or str(current.get("equipped_stats",{}).get(selected.slot,""))==str(selected.id)
		return
	_text(body,"此装备尚未解锁，请前往港口装备商人处兑换。")

func update_payment() -> void:
	if payment_summary==null:return
	var total:=0;var lines: PackedStringArray=[]
	for id in payment:
		var count:=int(payment[id]);total+=count
		if count>0:lines.append("%s × %d → 剩余 %d"%[card_name(str(id)),count,int(snapshot.get("treasure_inventory",{}).get(id,0))-count])
	payment_summary.text="已选择 %d / %d 张；支付后这些卡将无法施放。\n%s"%[total,price,"\n".join(lines)]
	var prerequisites: Dictionary=economy.get("exchange",{}).get("prerequisites",{})
	var needs_previous:=false
	for requirement in prerequisites.get(str(selected.get("tier","")),[]):
		var key:=str(requirement).replace("{slot}",str(selected.slot))
		if not snapshot.get("equipment_unlocks",[]).has(key):
			needs_previous=true;payment_summary.text+="\n需先解锁："+key
	buy_button.disabled=busy or not _connected() or total!=price or needs_previous

func preview_payment() -> void:
	if busy or buy_button.disabled:return
	confirm.dialog_text="%s %s\n%s\n\n只解锁权益，不会自动换装。"%[SLOT_NAMES[selected.slot],str(selected.tier).to_upper(),payment_summary.text]
	confirm.popup_centered(Vector2i(560,320))

func stable_request(method: String,args: Array) -> String:
	var body_text:=method+JSON.stringify(args)
	if request_body!=body_text or request_id.is_empty():
		request_body=body_text;request_id="equipment-"+str(Time.get_unix_time_from_system())+"-"+str(Time.get_ticks_usec())
	return request_id

func exchange() -> void:
	if busy:return
	var chosen: Dictionary={}
	for id in payment:
		if int(payment[id])>0:chosen[id]=int(payment[id])
	var args: Array=[str(selected.slot),str(selected.tier),chosen]
	args.append(stable_request("exchange_equipment",args))
	await perform("exchange_equipment",args)

func equip_selected() -> void:
	var args: Array=[str(selected.slot),str(selected.id)]
	args.append(stable_request("equip_stat",args));await perform("equip_stat",args)

func perform(method: String,args: Array) -> void:
	if busy:return
	if not _connected():status.text="已断线，重连后才能兑换或换装。";return
	var accounts:=get_node("/root/Accounts")
	if not accounts.has_method(method):status.text="账号接口尚未就绪："+method;return
	busy=true;status.text="正在等待服务器确认…";refresh()
	var result: Dictionary=await accounts.callv(method,args)
	busy=false
	if bool(result.get("ok",false)):request_id="";request_body="";payment.clear()
	refresh();show_result(result)

func show_result(result: Dictionary) -> void:
	if bool(result.get("ok",false)):
		status.text="账号已经解锁，没有再次扣卡。" if str(result.get("code",""))=="already_unlocked" else "服务器已确认，已刷新账号权益。"
		return
	var code:=str(result.get("code","unknown"))
	var messages: Dictionary={"insufficient_treasure":"可用宝藏卡不足，战斗保留中的卡不能支付。","equipment_not_unlocked":"该档装备尚未解锁。","prerequisite_missing":"需先解锁同槽上一档装备。","battle_active":"本场战斗中不能更换属性装备。","already_unlocked":"账号已经解锁，无需再次支付。"}
	messages.merge({"insufficient_cards":"可用宝藏卡不足，战斗保留中的卡不能支付。","in_battle":"本场战斗中不能更换属性装备。","invalid_equipment":"尚未解锁、不属于本系，或尚未满足上一档要求。","unauthorized":"请先登录角色。","service_unavailable":"账号服务暂不可用，请稍后重试。","revision_conflict":"账号权益已更新，请刷新后重试。"})
	status.text=str(messages.get(code,"操作失败："+code))+" 当前库存以服务器快照为准。"

func build_wings() -> void:
	_text(body,"永久翅膀收藏",19)
	var wings: Array=snapshot.get("wing_unlocks",[])
	if wings.is_empty():_text(body,"尚未解锁翅膀 · 挑战共享首领营地获得。");return
	if not str(snapshot.get("equipped_wing","")).is_empty():
		_button(body,"收起翅膀",func():
			var args: Array=[""];args.append(stable_request("equip_wing",args));await perform("equip_wing",args))
	for wing in wings:
		var id:=str(wing)
		var display_name:=id
		var catalog: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/wing_mounts.json"))
		if catalog is Array:
			for entry in catalog:
				if str(entry.get("id",""))==id:display_name=str(entry.get("name",id));break
		var button:=_button(body,display_name+(" · 已装备" if str(snapshot.get("equipped_wing",""))==id else " · 装备"),func():
			var args: Array=[id];args.append(stable_request("equip_wing",args));await perform("equip_wing",args))
		button.disabled=busy or not _connected() or str(snapshot.get("equipped_wing",""))==id

func _display_title(value: String) -> String:
	var parts:=value.split(" · ")
	if parts.size()>1 and parts[-1].is_valid_int():parts.remove_at(parts.size()-1)
	return " · ".join(parts)
