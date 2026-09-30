class_name DeckBuilderPanelV2
extends PanelContainer
signal apply_requested(card_counts: Dictionary)
signal collection_changed
const SCHOOL_ORDER=["fire","ice","storm","myth","life","death","balance"]
const SCHOOL_NAMES=["火焰","寒冰","风暴","神话","生命","死亡","平衡"]
const BOOK_SIZE=Vector2(1160,760)
const INK=Color("573e28")
const CREAM=Color("ffe8bb")
const Modern=preload("res://scripts/fusion_3d/modern_inventory_skin.gd")
const Painted=preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd")
const SpellButton=preload("res://scenes/battle_v2/ui/deck_spell_button.gd")
var embedded:=false
var max_pip_cost:=99
var content: ContentRegistryV2
var loadout: RefCounted
var counts: Dictionary={}
var normal_counts: Dictionary={}
var treasure_counts: Dictionary={}
var stock: Dictionary={}
var treasure_ids: Array=[]
var character_title:="当前角色"
var treasure_mode:=false
var selected_school:=""
var definitions: Array[CardDefinitionV2]=[]
var filtered: Array[CardDefinitionV2]=[]
var page:=0
var equipment_page:=0
var canvas: Control
var scrim: ColorRect
var slots: Control
var cards_page: Control
var treasure_slots: Control
var character_label: Label
var total_label: Label
var hint_label: Label
var page_label: Label
var equipment_label: Label
var normal_mode_button: Button
var treasure_mode_button: Button
var search: LineEdit
var prev_button: Button
var next_button: Button
var equipment_prev: Button
var equipment_next: Button
var school_buttons: Array[Button]=[]
var preset_buttons: Array[Button]=[]
var preset_load_buttons: Array[Button]=[]
var preset_export_buttons: Array[Button]=[]

func _ready() -> void:
	visible=false
	add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	canvas=Control.new();canvas.custom_minimum_size=BOOK_SIZE;canvas.mouse_filter=Control.MOUSE_FILTER_PASS;add_child(canvas)
	_build_shell()
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()

func _fit() -> void:
	if embedded:
		position=Vector2(40,0);scale=Vector2.ONE*0.93;size=BOOK_SIZE
		return
	set_anchors_preset(Control.PRESET_TOP_LEFT);size=BOOK_SIZE
	scale=Vector2.ONE*maxf(0.1,minf((get_viewport_rect().size.x-36)/BOOK_SIZE.x,(get_viewport_rect().size.y-36)/BOOK_SIZE.y))
	position=(get_viewport_rect().size-BOOK_SIZE*scale)*0.5
	queue_redraw()

func set_character_context(title: String, treasures: Array) -> void:
	character_title=title;treasure_ids=treasures.duplicate()

func open(p_content: ContentRegistryV2, initial_counts: Dictionary) -> void:
	if not embedded and not is_instance_valid(scrim):
		scrim=ColorRect.new();scrim.color=Color(0.04,0.03,0.02,0.65);scrim.z_index=z_index-1
		get_parent().add_child(scrim);scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if is_instance_valid(scrim):scrim.show()
	content=p_content
	normal_counts=initial_counts.duplicate(true)
	treasure_counts={};stock={}
	if loadout!=null:
		treasure_counts=loadout.treasure_counts();stock=loadout.inventory()
	else:
		for id in treasure_ids:treasure_counts[str(id)]=int(treasure_counts.get(str(id),0))+1
		stock=treasure_counts.duplicate(true)
	_read_authoritative_stock()
	treasure_mode=false;counts=normal_counts;selected_school="";page=0;equipment_page=0;search.text=""
	_rebuild_rows();_build_equipment();_refresh_preset_buttons();show();_fit()
	if not embedded:move_to_front()

func resume_embedded() -> void:
	if loadout!=null:
		normal_counts=loadout.counts().duplicate(true);treasure_counts=loadout.treasure_counts();stock=loadout.inventory()
		counts=treasure_counts if treasure_mode else normal_counts
	_read_authoritative_stock();_rebuild_rows();_build_equipment();_refresh_preset_buttons();show();_fit()

func close() -> void:
	hide()
	if is_instance_valid(scrim):scrim.hide()

func _exit_tree() -> void:
	if is_instance_valid(scrim):scrim.queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if not embedded and visible and event.is_action_pressed("ui_cancel"):close();get_viewport().set_input_as_handled()

func _label(text: String, at: Vector2, extent: Vector2, font_size: int=16, parent: Control=null, color: Color=INK) -> Label:
	var n:=Label.new();n.text=text;n.position=at;n.size=extent;n.add_theme_font_size_override("font_size",font_size);n.add_theme_color_override("font_color",Modern.INK if embedded and color==INK else color)
	n.mouse_filter=Control.MOUSE_FILTER_IGNORE;n.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	(parent if parent!=null else canvas).add_child(n)
	return n

func _button(text: String, at: Vector2, extent: Vector2, callback: Callable, parent: Control=null) -> Button:
	var b:=Button.new();b.text=text;b.position=at;b.size=extent;b.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("815b3a") if state=="normal" else (Color("9b7047") if state=="hover" else Color("62452f"))
		style.border_color=Color("c7a15b");style.set_border_width_all(2);style.set_corner_radius_all(mini(10,int(extent.y/2)))
		style.content_margin_left=10;style.content_margin_right=10
		b.add_theme_stylebox_override(state,style)
	b.add_theme_font_size_override("font_size",15);b.add_theme_color_override("font_color",CREAM)
	if embedded:Modern.button(b)
	b.pressed.connect(callback);(parent if parent!=null else canvas).add_child(b)
	return b

func _build_shell() -> void:
	# Layered nine-slice art: independent pages keep their corners while the book scales to the viewport.
	if not embedded:
		_nine_panel("res://assets/ui/deck_builder/page_panel_v2_ui.png",Rect2(25,23,552,686),Vector4i(30,28,30,28),true)
		_nine_panel("res://assets/ui/deck_builder/page_panel_v2_ui.png",Rect2(572,23,522,686),Vector4i(30,28,30,28),true)
		_nine_panel("res://assets/ui/deck_builder/book_outer_frame_v2_ui.png",Rect2(4,5,1152,752),Vector4i(54,48,54,48),false)
		_nine_panel("res://assets/ui/deck_builder/page_panel_v2_ui.png",Rect2(374,11,412,94),Vector4i(24,22,24,22),true)
		var title:=_label("法 术 之 书",Vector2(400,25),Vector2(360,42),30);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var en:=_label("S P E L L   D E C K",Vector2(400,69),Vector2(360,22),12);en.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	normal_mode_button=_mode_button(false,Vector2(58,35))
	treasure_mode_button=_mode_button(true,Vector2(126,35))
	if not embedded:
		_label("普通卡",Vector2(51,92),Vector2(72,20),12).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		_label("宝藏卡",Vector2(119,92),Vector2(72,20),12).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	if not embedded:_button("×",Vector2(1039,42),Vector2(46,42),close)
	# Keep every school bookmark visually separate. The old 52 px first offset made
	# the "all" bookmark overlap fire even though the remaining tabs had a gap.
	var school_tab_origin:=Vector2(1060,143)
	var school_tab_step:=68.0
	var all_button:=_school_tab_button(0,school_tab_origin)
	_school_badge_icon(all_button,"all",Vector2(25,8),Vector2(34,38))
	all_button.tooltip_text="全部学院";school_buttons.append(all_button)
	for i in 7:
		var b:=_school_tab_button(i+1,school_tab_origin+Vector2(0,school_tab_step*float(i+1)))
		_school_icon(b,SCHOOL_ORDER[i],Vector2(25,8),Vector2(34,38));b.tooltip_text=SCHOOL_NAMES[i];school_buttons.append(b)
	character_label=_label("",Vector2(62,168),Vector2(470,31),22)
	total_label=_label("",Vector2(63,201),Vector2(471,28),14)
	slots=Control.new();slots.position=Vector2(63,240);slots.size=Vector2(475,265);canvas.add_child(slots)
	equipment_label=_label("装备卡 · 由穿戴装备提供",Vector2(64,517),Vector2(360,28),17)
	equipment_prev=_turn_art_button(false,Vector2(451,513),Vector2(39,34),_equipment_turn.bind(-1))
	equipment_next=_turn_art_button(true,Vector2(496,513),Vector2(39,34),_equipment_turn.bind(1))
	treasure_slots=Control.new();treasure_slots.position=Vector2(63,556);treasure_slots.size=Vector2(475,108);canvas.add_child(treasure_slots)
	_label("点击切换启用 / 禁用 · 随装备自动加入",Vector2(64,669),Vector2(472,24),13)
	_label("法术收藏",Vector2(605,111),Vector2(150,34),21)
	search=LineEdit.new();search.position=Vector2(758,110);search.size=Vector2(300,40);search.placeholder_text="搜索法术…"
	search.add_theme_color_override("font_color",Modern.INK if embedded else INK);search.add_theme_color_override("font_placeholder_color",(Color("92a9c3") if embedded else Color("8a6a44")))
	var field:=StyleBoxFlat.new();field.bg_color=(Color("142336") if embedded else Color("f3dfb7"));field.border_color=(Color("30465e") if embedded else Color("a78652"));field.set_border_width_all(2);field.set_content_margin_all(7)
	search.add_theme_stylebox_override("normal",field);search.add_theme_font_size_override("font_size",15);canvas.add_child(search)
	search.text_changed.connect(func(_v):page=0;_rebuild_rows())
	cards_page=Control.new();cards_page.position=Vector2(602,169);cards_page.size=Vector2(466,471);canvas.add_child(cards_page)
	prev_button=_turn_art_button(false,Vector2(598,646),Vector2(61,50),_turn_page.bind(-1))
	next_button=_turn_art_button(true,Vector2(1004,646),Vector2(61,50),_turn_page.bind(1))
	page_label=_label("",Vector2(663,655),Vector2(344,34),15);page_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	hint_label=_label("点击加减，自动保存 · 普通卡组允许 0–40 张",Vector2(70,693),Vector2(1000,20),13,null,CREAM)
	_build_preset_toolbar()

func _build_preset_toolbar() -> void:
	var x:=62.0
	var clear_button:=_button("清空当前",Vector2(x,716),Vector2(104,32),_clear_all)
	clear_button.tooltip_text="清空当前普通卡组或宝藏卡组";x+=112
	for slot in range(1,4):
		var save_button:=_button("保存 %d"%slot,Vector2(x,716),Vector2(72,32),_save_preset.bind(slot));x+=76
		save_button.tooltip_text="把当前普通卡组保存到预设 %d"%slot
		var load_button:=_button("读取 %d"%slot,Vector2(x,716),Vector2(72,32),_load_preset.bind(slot));x+=76
		var export_button:=_button("导出 %d"%slot,Vector2(x,716),Vector2(72,32),_export_preset.bind(slot));x+=80
		preset_buttons.append_array([save_button,load_button,export_button])
		preset_load_buttons.append(load_button);preset_export_buttons.append(export_button)
	_refresh_preset_buttons()

func _clear_all() -> void:
	counts.clear()
	if treasure_mode:
		treasure_counts.clear()
		if loadout!=null:loadout.save_treasures({})
		collection_changed.emit()
	else:
		normal_counts.clear()
		apply_requested.emit({})
	_refresh_counts();hint_label.text="当前卡组已清空 · 可以保持 0 张或重新加入法术"

func _save_preset(slot: int) -> void:
	if loadout==null:return
	if loadout.save_preset(slot,normal_counts):
		hint_label.text="已把普通卡组保存到预设 %d · 共 %d 张"%[slot,_dictionary_total(normal_counts)]
	else:hint_label.text="预设保存失败，请检查本地存档空间"
	_refresh_preset_buttons()

func _load_preset(slot: int) -> void:
	if loadout==null:return
	var entry: Dictionary=loadout.preset(slot)
	if entry.is_empty():hint_label.text="预设 %d 还没有保存卡组"%slot;return
	normal_counts=entry.counts.duplicate(true)
	if not treasure_mode:counts=normal_counts
	apply_requested.emit(normal_counts.duplicate(true))
	_refresh_counts();hint_label.text="已读取预设 %d · 共 %d 张"%[slot,_dictionary_total(normal_counts)]

func _export_preset(slot: int) -> void:
	if loadout==null:return
	var exported: String=loadout.export_preset(slot)
	if exported.is_empty():hint_label.text="预设 %d 为空，请先保存"%slot;return
	var absolute:=ProjectSettings.globalize_path(exported)
	if DisplayServer.get_name()!="headless":DisplayServer.clipboard_set(absolute)
	hint_label.text="预设 %d 已导出 JSON · 文件路径已复制"%slot

func _refresh_preset_buttons() -> void:
	for button in preset_buttons:button.visible=loadout!=null
	if loadout==null:return
	for i in 3:
		var entry: Dictionary=loadout.preset(i+1)
		var available:=not entry.is_empty()
		if i<preset_load_buttons.size():
			preset_load_buttons[i].disabled=not available
			preset_load_buttons[i].tooltip_text=("读取预设 %d · %d 张"%[i+1,int(entry.get("card_total",_dictionary_total(entry.get("counts",{}))))]) if available else "预设 %d 尚未保存"%(i+1)
		if i<preset_export_buttons.size():
			preset_export_buttons[i].disabled=not available
			preset_export_buttons[i].tooltip_text="导出预设 %d 为 JSON"%(i+1)

func _dictionary_total(value: Dictionary) -> int:
	var total:=0
	for count in value.values():total+=int(count)
	return total

func _school_icon(parent: Control, school: String, at: Vector2, extent: Vector2) -> void:
	var icon:=TextureRect.new();icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.texture=Painted.ui_symbol(StringName("school_"+school));icon.position=at;icon.size=extent
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(icon)

func _school_badge_icon(parent: Control, school: String, at: Vector2, extent: Vector2) -> void:
	var icon:=TextureRect.new();icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.texture=Painted.ui_symbol(StringName("school_badge_"+school));icon.position=at;icon.size=extent
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(icon)

func _art_style(path: String, margins: Vector4, draw_center: bool=true) -> StyleBoxTexture:
	var style:=StyleBoxTexture.new();style.texture=load(path);style.draw_center=draw_center
	style.texture_margin_left=margins.x;style.texture_margin_top=margins.y;style.texture_margin_right=margins.z;style.texture_margin_bottom=margins.w
	return style

func _nine_panel(path: String, rect: Rect2, margins: Vector4i, center: bool) -> NinePatchRect:
	var panel:=NinePatchRect.new();panel.texture=load(path);panel.position=rect.position;panel.size=rect.size;panel.draw_center=center
	panel.patch_margin_left=margins.x;panel.patch_margin_top=margins.y;panel.patch_margin_right=margins.z;panel.patch_margin_bottom=margins.w
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.add_child(panel);return panel

func _school_tab_button(index: int, at: Vector2) -> Button:
	var b:=Button.new();b.position=at;b.size=Vector2(82,54);b.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","disabled"]:
		var style:=_art_style("res://assets/ui/deck_builder/school_side_tab_v2_ui.png",Vector4(21,20,21,20))
		style.modulate_color=Color.WHITE if state=="normal" else (Color("ffdea1") if state=="hover" else Color("aa9478"))
		b.add_theme_stylebox_override(state,style)
	if embedded:Modern.button(b)
	b.add_theme_color_override("font_color",CREAM);b.add_theme_font_size_override("font_size",15)
	b.pressed.connect(_on_filter_changed.bind(index));canvas.add_child(b);return b

func _turn_art_button(right: bool, at: Vector2, extent: Vector2, callback: Callable) -> Button:
	if embedded:return _button("›" if right else "‹",at,extent,callback)
	var b:=Button.new();b.position=at;b.size=extent;b.focus_mode=Control.FOCUS_NONE
	for state in ["normal","hover","pressed","disabled"]:b.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	b.pressed.connect(callback);canvas.add_child(b)
	var art:=TextureRect.new();art.texture=load("res://assets/ui/deck_builder/page_turn_right_v2_ui.png");art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;art.flip_h=not right;art.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(art)
	return b

func _mode_button(treasure: bool, at: Vector2) -> Button:
	if embedded:
		var toggle:=_button("宝藏卡" if treasure else "普通卡",Vector2(218 if treasure else 58,35),Vector2(150,48),_set_mode.bind(treasure))
		toggle.toggle_mode=true;Modern.button(toggle,"cards");return toggle
	var b:=Button.new();b.position=at;b.size=Vector2(58,58);b.focus_mode=Control.FOCUS_NONE
	var normal:=StyleBoxFlat.new();normal.bg_color=(Color("142336") if embedded else Color("d9bd89"));normal.border_color=(Color("30465e") if embedded else Color("9b753e"));normal.set_border_width_all(2);normal.set_corner_radius_all(8)
	var hover:=normal.duplicate();hover.bg_color=(Color("1e354b") if embedded else Color("f0d59e"));hover.border_color=(Color("84dcff") if embedded else Color("e2b85e"))
	var active:=normal.duplicate();active.bg_color=(Color("24445d") if embedded else Color("f7dda3"));active.border_color=(Color("84dcff") if embedded else Color("fff0a4"));active.set_border_width_all(3)
	b.add_theme_stylebox_override("normal",normal);b.add_theme_stylebox_override("hover",hover);b.add_theme_stylebox_override("pressed",active)
	b.tooltip_text="宝藏卡配卡" if treasure else "普通卡配卡"
	b.pressed.connect(_set_mode.bind(treasure));canvas.add_child(b)
	var icon:=TextureRect.new();icon.position=Vector2(7,5);icon.size=Vector2(44,48);icon.texture=load("res://assets/ui/deck_builder/mode_treasure_card_v1.png" if treasure else "res://assets/ui/deck_builder/mode_normal_card_v1.png")
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(icon)
	return b

func _clear(node: Node) -> void:
	for child in node.get_children():node.remove_child(child);child.queue_free()

func _small(card: CardDefinitionV2, at: Vector2, parent: Control, equipment: Dictionary={}) -> void:
	var b:=SpellButton.new();b.definition=card;b.position=at;b.size=Vector2(54,48);b.focus_mode=Control.FOCUS_NONE;b.clip_contents=true
	var frame:=StyleBoxFlat.new();frame.bg_color=(Color("142336") if embedded else Color("b99a69a8")) if card==null else (Color("1b3047") if embedded else Color("d0ae75d4"));frame.border_color=(Color("46617b") if embedded else Color("8f6e3f"));frame.set_border_width_all(2);frame.set_corner_radius_all(3)
	var hover:=frame.duplicate();hover.bg_color=(Color("24445d") if embedded else Color("e2c58e"));hover.border_color=(Color("84dcff") if embedded else Color("f3cf72"))
	var disabled:=frame.duplicate();disabled.bg_color=(Color("111d2b") if embedded else Color("b69a70a0"));disabled.border_color=(Color("30465e") if embedded else Color("9a8058"))
	b.add_theme_stylebox_override("normal",frame);b.add_theme_stylebox_override("hover",hover);b.add_theme_stylebox_override("pressed",hover);b.add_theme_stylebox_override("disabled",disabled)
	b.disabled=card==null;parent.add_child(b)
	if card==null:return
	var icon:=TextureRect.new();icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	# Most source icons carry transparent atlas padding. Oversize the texture rect
	# and clip it to the slot so the visible glyph fills the cell consistently.
	icon.texture=load(card.art_path) if ResourceLoader.exists(card.art_path) else null;icon.position=Vector2(-7,-6);icon.size=Vector2(68,60)
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(icon)
	b.tooltip_text=Locale.text(str(card.name_key))
	if card.treasure:b.extra_description=_treasure_stock_text(str(card.id))+"\n命中并成功付豆后扣卡；被驱散仍扣。未命中、跳过、弃牌不扣。"
	if equipment.is_empty():b.pressed.connect(_change_count.bind(card.id,-1))
	else:
		b.pressed.connect(_toggle_equipment.bind(str(equipment.key)))
		b.extra_description="属性装备附带（换外观不改变）："+str(equipment.get("source",""))+"\n"+("已启用 · 点击禁用" if equipment.enabled else "已禁用 · 点击启用")
		icon.modulate=Color.WHITE if equipment.enabled else Color(0.48,0.48,0.48,0.6)
		_label("✓" if equipment.enabled else "×",Vector2(36,28),Vector2(17,17),14,b,Color("aaffb0") if equipment.enabled else Color("ffb4a2"))

func _build_equipment() -> void:
	_clear(treasure_slots)
	var items: Array=loadout.equipment_cards() if loadout!=null else []
	equipment_page=clampi(equipment_page,0,maxi(0,ceili(items.size()/16.0)-1))
	for i in 16:
		var index:=equipment_page*16+i
		var item: Dictionary=items[index] if index<items.size() else {}
		_small(content.card(StringName(item.card)) if not item.is_empty() else null,Vector2((i%8)*59,(i/8)*54),treasure_slots,item)
	equipment_label.text="装备卡 · %d 张 · %d/%d 页"%[items.size(),equipment_page+1,maxi(1,ceili(items.size()/16.0))]
	equipment_prev.disabled=equipment_page==0;equipment_next.disabled=(equipment_page+1)*16>=items.size()

func _toggle_equipment(key: String) -> void:
	if loadout==null:return
	loadout.toggle_equipment(key);_build_equipment();collection_changed.emit();_saved_hint()

func _equipment_turn(delta: int) -> void:equipment_page+=delta;_build_equipment()

func _switch_mode() -> void:_set_mode(not treasure_mode)

func _set_mode(value: bool) -> void:
	if treasure_mode==value and content!=null:return
	treasure_mode=value;counts=treasure_counts if treasure_mode else normal_counts;page=0;_rebuild_rows()

func _on_filter_changed(index: int) -> void:
	selected_school="" if index==0 else SCHOOL_ORDER[index-1];page=0;_rebuild_rows()

func _rebuild_rows() -> void:
	if content==null:return
	definitions.clear();filtered.clear()
	for card: CardDefinitionV2 in content.cards.values():
		if card.enemy_only or card.treasure!=treasure_mode:continue
		if treasure_mode and int(stock.get(str(card.id),0))<=0:continue
		if not treasure_mode and (not card.learned or (not card.x_pip and card.pip_cost>max_pip_cost)):continue
		definitions.append(card)
	definitions.sort_custom(func(a,b):return str(a.school_id)+str(a.id)<str(b.school_id)+str(b.id))
	for card in definitions:
		if not selected_school.is_empty() and str(card.school_id)!=selected_school and not card.tags.has(&"universal_aura"):continue
		if not search.text.is_empty() and not search.text.to_lower() in (Locale.text(str(card.name_key))+" "+str(card.id)).to_lower():continue
		filtered.append(card)
	page=clampi(page,0,maxi(0,ceili(filtered.size()/6.0)-1))
	for i in school_buttons.size():school_buttons[i].modulate=Color.WHITE if (i==0 and selected_school.is_empty()) or (i>0 and selected_school==SCHOOL_ORDER[i-1]) else (Color("92a9c3") if embedded else Color("cbb996"))
	_refresh_counts()

func _refresh_counts() -> void:
	_clear(slots)
	var index:=0
	for card in definitions:
		for _copy in int(counts.get(str(card.id),0)):
			if index>=40:break
			_small(card,Vector2((index%8)*59,(index/8)*53),slots);index+=1
	while index<40:_small(null,Vector2((index%8)*59,(index/8)*53),slots);index+=1
	character_label.text=character_title+(" · 宝藏卡组" if treasure_mode else " · 普通卡组")
	total_label.text="%d / 40 张 · %s"%[_total(),"命中并成功付豆后扣卡（被驱散仍扣）" if treasure_mode else "点击右页加入 · 点击左页移除"]
	if is_instance_valid(normal_mode_button):
		if embedded:normal_mode_button.set_pressed_no_signal(not treasure_mode);treasure_mode_button.set_pressed_no_signal(treasure_mode)
		normal_mode_button.modulate=Color.WHITE if not treasure_mode else Color(0.63,0.59,0.52,0.82)
		treasure_mode_button.modulate=Color.WHITE if treasure_mode else Color(0.63,0.59,0.52,0.82)
	_build_page()

func _ignore_input(node: Node) -> void:
	if node is Control:node.mouse_filter=Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():_ignore_input(child)

func _build_page() -> void:
	_clear(cards_page)
	for i in mini(6,filtered.size()-page*6):
		var card:=filtered[page*6+i]
		var b:=SpellButton.new();b.definition=card;b.position=Vector2((i%3)*156,(i/3)*235);b.size=Vector2(146,234);b.focus_mode=Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal",StyleBoxEmpty.new());b.add_theme_stylebox_override("hover",StyleBoxEmpty.new());b.add_theme_stylebox_override("pressed",StyleBoxEmpty.new())
		b.tooltip_text=Locale.text(str(card.name_key));b.pressed.connect(_change_count.bind(card.id,1));cards_page.add_child(b)
		if card.treasure:b.extra_description=_treasure_stock_text(str(card.id))+"\n命中并成功付豆后扣卡；被驱散仍扣。未命中、跳过、弃牌不扣。"
		# Use the hand's card renderer and frame together for the hover preview.
		var card_stack:=Control.new();card_stack.name="CardStack";card_stack.position=Vector2(8,1);card_stack.size=Vector2(138,208)
		card_stack.pivot_offset=Vector2(69,104);card_stack.scale=Vector2.ONE*0.94;card_stack.mouse_filter=Control.MOUSE_FILTER_IGNORE;b.add_child(card_stack)
		var view:=BattleCardViewV2.new();view.bind(CardInstanceV2.new(i,card),true);card_stack.add_child(view);view.set_process(false);view.position=Vector2.ZERO;_ignore_input(view)
		b.mouse_entered.connect(func():card_stack.scale=Vector2.ONE;view.queue_redraw())
		b.mouse_exited.connect(func():card_stack.scale=Vector2.ONE*0.94;view.queue_redraw())
		if treasure_mode:
			var inv:=_label(_treasure_stock_text(str(card.id),true),Vector2(0,209),Vector2(146,24),16,b)
			inv.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		else:
			var n:=int(counts.get(str(card.id),0))
			var circles:=_label("●".repeat(n)+"○".repeat(maxi(0,9-n)),Vector2(0,201),Vector2(146,20),14,b)
			circles.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		# Keep hover and details available even at the copy limit or with zero inventory.
	if filtered.is_empty():_label("没有找到法术\n试试其他学院或名称",Vector2(30,150),Vector2(400,90),20,cards_page)
	page_label.text="%d / %d 页 · %d 种法术"%[page+1,maxi(1,ceili(filtered.size()/6.0)),filtered.size()]
	prev_button.disabled=page<=0;next_button.disabled=(page+1)*6>=filtered.size()

func _turn_page(delta: int) -> void:page+=delta;_rebuild_rows()

func _change_count(card_id: StringName, delta: int) -> void:
	var key:=str(card_id);var current:=int(counts.get(key,0))
	var cap:=mini(9,int(stock.get(key,0))) if treasure_mode else 9
	if delta>0 and (_total()>=40 or current>=cap):
		hint_label.text="宝藏卡库存不足或已达配卡上限" if treasure_mode else "已达配卡上限：总计 40 张，单卡 9 张";return
	counts[key]=clampi(current+delta,0,cap)
	if counts[key]==0:counts.erase(key)
	if treasure_mode:
		if loadout!=null:loadout.save_treasures(counts)
		collection_changed.emit()
	else:apply_requested.emit(counts.duplicate(true))
	_refresh_counts();_saved_hint()

func _saved_hint() -> void:hint_label.text="已自动保存 · 普通卡组允许 0–40 张 · 悬浮查看完整卡牌说明"

func _total() -> int:
	var total:=0
	for value in counts.values():total+=int(value)
	return total

func _flat(bg: Color,border: Color,radius: int) -> StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=bg;style.border_color=border;style.set_border_width_all(2);style.set_corner_radius_all(radius);return style

func _draw() -> void:
	if embedded:
		var frame = preload("res://scenes/battle_v2/ui/compact_battle_skin.gd")
		draw_style_box(frame.panel(true,Color(0.83,0.9,1,0.8)),Rect2(38,152,522,543))
		draw_style_box(frame.panel(true,Color(0.83,0.9,1,0.8)),Rect2(586,99,494,608))
	if not embedded:draw_style_box(_flat(Color("4c3426"),Color("7c5737"),20),Rect2(7,8,1146,748))
	draw_style_box(_flat((Color("142336") if embedded else Color("b89a6a55")),(Color("30465e") if embedded else Color("9f7d48")),7),Rect2(48,228,503,283))
	draw_style_box(_flat((Color("142336") if embedded else Color("b89a6a55")),(Color("30465e") if embedded else Color("9f7d48")),7),Rect2(48,548,503,121))
	for i in 18:draw_line(Vector2(566+i,41),Vector2(566+i,700),Color(0.25,0.15,0.07,0.025*(9-abs(i-9))),1)

func _read_authoritative_stock() -> void:
	var wardrobe:=get_node_or_null("/root/Wardrobe")
	if wardrobe==null or not wardrobe.has_method("progression"):return
	var snapshot: Dictionary=wardrobe.progression()
	if snapshot.is_empty():return
	stock=snapshot.get("treasure_inventory",{}).duplicate(true)

func _treasure_stock_text(id: String,compact: bool=false) -> String:
	var wardrobe:=get_node_or_null("/root/Wardrobe")
	var snapshot: Dictionary=wardrobe.progression() if wardrobe!=null and wardrobe.has_method("progression") else {}
	var total:=int(snapshot.get("treasure_inventory",stock).get(id,0))
	var packed:=int(treasure_counts.get(id,0))
	if compact:return "%d/%d"%[packed,total]
	return "已放入卡盒 / 拥有数量：%d/%d"%[packed,total]
