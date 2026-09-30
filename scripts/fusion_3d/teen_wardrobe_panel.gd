extends Control
const ModernSkin=preload("res://scripts/fusion_3d/modern_inventory_skin.gd")
signal close_requested
signal legacy_requested
const ITEM_SLOTS: Array[String]=["teen_clothes","teen_boots","teen_hat","teen_back","teen_weapon"]
const SHAPE_SLOTS: Array[String]=["teen_body_shape","teen_boot_shape","teen_back_shape"]
var embedded:=false
var shop_page: Control
var shop_preview: Dictionary={}
var category_choice: HFlowContainer
var dragging_preview:=false
var profile:="fire"
var store: Node
var preview: Node3D
var camera: Camera3D
var grid: GridContainer
var search: LineEdit
var category:="teen_clothes"
var mode:=0
var page:=0
var category_tabs: TabBar
var mode_tabs: TabBar
var gender_tabs: TabBar
var school_tabs: TabBar
var main_tabs: TabBar
var appearance_page: VBoxContainer
var equipment_page: Control
var personal_mode:=false
var status_label: Label
var equipped_summary: Label
var dye_search_button: Button
var pager: Label
var selected: Label
var previous_button: Button
var next_button: Button
var scroll: ScrollContainer
var hair_panel: VBoxContainer
var hair_picker: ColorPickerButton
var dye_panel: VBoxContainer
var dye_buttons: Array[ColorPickerButton]=[]
var matching_boots_button: Button
var action_grid: GridContainer
var current_animation:=""
var last_gender:=""
var preview_hair_mode:=false
var columns:=4
var right: VBoxContainer
static var thumbnails: Dictionary={}
func label(parent: Node,value: String,font_size: int=17) -> Label:
	var node:=Label.new();node.text=value;node.add_theme_font_size_override("font_size",font_size);parent.add_child(node);return node
func button(parent: Node,value: String,callback: Callable) -> Button:
	var node:=Button.new();node.text=value;node.custom_minimum_size.y=36;node.pressed.connect(callback);parent.add_child(node);return node
func row(parent: Node) -> HBoxContainer:
	var node:=HBoxContainer.new();node.add_theme_constant_override("separation",8);parent.add_child(node);return node
func style(color: String,border: String="32465b") -> StyleBoxFlat:
	if embedded:return ModernSkin.panel(Color("24445d") if border=="dfbd80" else Color("142336"),ModernSkin.ACCENT if border=="dfbd80" else Color("30465e"))
	var box:=StyleBoxFlat.new();box.bg_color=Color(color);box.border_color=Color(border)
	box.set_border_width_all(1);box.set_corner_radius_all(8)
	box.content_margin_left=12;box.content_margin_right=12;box.content_margin_top=7;box.content_margin_bottom=7
	return box
func tabs(parent: Node,names: Array) -> TabBar:
	var bar:=TabBar.new();bar.custom_minimum_size.y=40;bar.clip_tabs=true;bar.tab_alignment=TabBar.ALIGNMENT_LEFT
	for title in names:bar.add_tab(str(title))
	parent.add_child(bar);return bar
func _ready() -> void:
	store=get_node("/root/Wardrobe")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);z_index=0 if embedded else 110
	if not embedded:
		theme=Theme.new();theme.default_font_size=17
		for type in ["Button","TabBar"]:
			for state in (["normal","hover","pressed","disabled","focus"] if type=="Button" else ["tab_unselected","tab_hovered","tab_selected","tab_disabled","tab_focus"]):
				theme.set_stylebox(state,type,style("29415a" if state in ["hover","tab_hovered"] else "34485d" if state in ["pressed","tab_selected"] else "1c2b3e","dfbd80" if state in ["pressed","tab_selected"] else "32465b"))
		var shade:=ColorRect.new();shade.color=Color("101b2a");shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,0 if embedded else 24)
	add_child(margin)
	var layout:=VBoxContainer.new();layout.add_theme_constant_override("separation",10);margin.add_child(layout)
	var header:=row(layout)
	var title:=label(header,str(Accounts.active_character.get("name","学徒"))+" · "+Locale.text("SCHOOL_"+profile.to_upper()),26);title.modulate=ModernSkin.ACCENT;title.size_flags_horizontal=SIZE_EXPAND_FILL
	button(header,"个人形象",open_personal)

	button(header,"关闭  ×",close)
	header.visible=not embedded
	main_tabs=tabs(layout,["属性装备","外观衣橱"])
	main_tabs.tab_changed.connect(select_main_page)
	main_tabs.tab_clicked.connect(func(index: int):
		if personal_mode:select_main_page(index))
	main_tabs.visible=not embedded
	var content:=row(layout);content.size_flags_vertical=SIZE_EXPAND_FILL;content.add_theme_constant_override("separation",24 if embedded else 20)
	var left:=VBoxContainer.new();left.custom_minimum_size.x=420 if embedded else 330;left.size_flags_horizontal=SIZE_FILL if embedded else SIZE_EXPAND_FILL;left.size_flags_stretch_ratio=0.5 if embedded else 0.65;content.add_child(left)
	gender_tabs=tabs(left,["男学徒","女学徒"])
	gender_tabs.hide()
	gender_tabs.tab_changed.connect(func(index: int):page=0;store.equip_teen(profile,"gender","male" if index==0 else "female"))
	var view_box:=SubViewportContainer.new();view_box.stretch=true;view_box.custom_minimum_size.y=240;view_box.size_flags_vertical=SIZE_EXPAND_FILL;left.add_child(view_box);view_box.gui_input.connect(_preview_input);view_box.mouse_default_cursor_shape=Control.CURSOR_DRAG;view_box.tooltip_text="拖动旋转 · 滚轮缩放"
	var viewport:=SubViewport.new();viewport.size=Vector2i(480,600);viewport.own_world_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;view_box.add_child(viewport)
	var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color("1b2d40");world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color("d4dfef");world.environment.ambient_light_energy=0.7;viewport.add_child(world)
	for angle in [-35,145]:
		var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-30,angle,0);light.light_energy=0.9 if angle==-35 else 0.45;viewport.add_child(light)
	camera=Camera3D.new();viewport.add_child(camera);camera.position=Vector3(0,1.35,-5.2);camera.look_at(Vector3(0,1.05,0));camera.fov=32
	preview=preload("res://scenes/characters/modular_wizard.tscn").instantiate();preview.follow_local_wardrobe=false;viewport.add_child(preview)
	equipped_summary=label(left,"",15);equipped_summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var rotate:=row(left)
	button(rotate,"↺ 重置视角",func():preview.rotation.y=0;camera.position.z=-5.2;camera.look_at(Vector3(0,1.05,0)))
	button(rotate,"背面",func():preview.rotation.y=PI)
	label(rotate,"拖动旋转 · 滚轮缩放",14).modulate=ModernSkin.MUTED
	var action_row:=row(left);action_row.visible=not embedded
	for entry in [["待机",""],["行走","base_004"],["施法","base_071"]]:button(action_row,entry[0],func():play_animation(entry[1]))
	var action_scroll:=ScrollContainer.new();action_scroll.custom_minimum_size.y=120;action_scroll.visible=false
	button(action_row,"更多动作",func():action_scroll.visible=not action_scroll.visible)
	left.add_child(action_scroll);action_grid=GridContainer.new();action_grid.columns=2;action_grid.size_flags_horizontal=SIZE_EXPAND_FILL;action_scroll.add_child(action_grid)
	right=VBoxContainer.new();right.size_flags_horizontal=SIZE_EXPAND_FILL;right.size_flags_stretch_ratio=1.35;right.add_theme_constant_override("separation",8);content.add_child(right)
	equipment_page=preload("res://scripts/fusion_3d/equipment_panel.gd").new();equipment_page.size_flags_horizontal=SIZE_EXPAND_FILL;equipment_page.size_flags_vertical=SIZE_EXPAND_FILL;right.add_child(equipment_page)
	shop_page=preload("res://scripts/fusion_3d/inventory_shop_panel.gd").new();shop_page.size_flags_vertical=SIZE_EXPAND_FILL;right.add_child(shop_page);shop_page.hide()
	shop_page.preview_requested.connect(show_shop_preview)
	shop_page.preview_cleared.connect(end_shop_preview)
	appearance_page=VBoxContainer.new();appearance_page.size_flags_vertical=SIZE_EXPAND_FILL;right.add_child(appearance_page)
	mode_tabs=tabs(appearance_page,["整套搭配","单件混搭","版型调整"])
	mode_tabs.tab_changed.connect(func(index: int):mode=index;page=0;search.text="";rebuild_categories();refresh_list())
	category_tabs=tabs(appearance_page,[])
	category_tabs.tab_changed.connect(func(index: int):
		if personal_mode:category=["teen_hair","teen_skin"][index]
		elif mode==1:category=ITEM_SLOTS[index]
		elif mode==2:category=SHAPE_SLOTS[index]
		page=0;refresh_list())
	mode_tabs.visible=not embedded;category_tabs.visible=not embedded
	category_choice=HFlowContainer.new();category_choice.add_theme_constant_override("h_separation",6);category_choice.add_theme_constant_override("v_separation",6);appearance_page.add_child(category_choice);category_choice.visible=embedded
	var search_row:=row(appearance_page)
	search=LineEdit.new();search.placeholder_text="搜索套装、名称或编号…";search.clear_button_enabled=true;search.custom_minimum_size.y=38;search.size_flags_horizontal=SIZE_EXPAND_FILL;search_row.add_child(search)
	search.text_changed.connect(func(_value: String):page=0;refresh_list())
	dye_search_button=button(search_row,"可染色",func():mode_tabs.current_tab=1;category_tabs.current_tab=0;search.text="可染色";page=0;refresh_list())
	selected=label(appearance_page,"",16);selected.modulate=ModernSkin.ACCENT;selected.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	build_colors(appearance_page)
	scroll=ScrollContainer.new();scroll.size_flags_vertical=SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;appearance_page.add_child(scroll)
	grid=GridContainer.new();grid.columns=columns;grid.size_flags_horizontal=SIZE_EXPAND_FILL;grid.add_theme_constant_override("h_separation",10);grid.add_theme_constant_override("v_separation",10);scroll.add_child(grid)
	var pages:=row(appearance_page)
	previous_button=button(pages,"‹ 上一页",func():page-=1;scroll.scroll_vertical=0;refresh_list())
	pager=label(pages,"");pager.size_flags_horizontal=SIZE_EXPAND_FILL;pager.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	next_button=button(pages,"下一页 ›",func():page+=1;scroll.scroll_vertical=0;refresh_list())
	if not embedded:label(layout,"整套搭配保留脸型、肤色和发型。",15)
	rebuild_categories();store.changed.connect(_changed)
	right.resized.connect(func():
		var count:=clampi(int(right.size.x/(190 if embedded else 250)),2,4)
		if columns!=count:columns=count;grid.columns=count)
	status_label=label(layout,"换装只改变外观；保存成功后生效。",16)
	status_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	store.appearance_status.connect(func(message: String):status_label.text=message)
	select_main_page(0)
	refresh()
func build_colors(parent: Node) -> void:
	hair_panel=VBoxContainer.new();parent.add_child(hair_panel)
	var hair_row:=HFlowContainer.new();hair_panel.add_child(hair_row);label(hair_row,"发色",16)
	hair_picker=ColorPickerButton.new();hair_picker.custom_minimum_size=Vector2(45,32);hair_picker.edit_alpha=false;hair_picker.get_picker().deferred_mode=true;hair_row.add_child(hair_picker)
	hair_picker.color_changed.connect(func(color: Color):store.set_teen_hair_color(profile,color))
	for title in store.hair_catalog.presets:
		var color:=Color(str(store.hair_catalog.presets[title]))
		var swatch:=button(hair_row,"●",func():store.set_teen_hair_color(profile,color));swatch.modulate=color;swatch.tooltip_text=str(title)
	button(hair_row,"恢复",func():store.reset_teen_hair_color(profile))
	dye_panel=VBoxContainer.new();parent.add_child(dye_panel)
	var dye_row:=HFlowContainer.new();dye_panel.add_child(dye_row)
	for zone in 4:
		label(dye_row,str(store.dye_catalog.zones[zone]),15)
		var picker:=ColorPickerButton.new();picker.custom_minimum_size=Vector2(45,32);picker.edit_alpha=false;picker.get_picker().deferred_mode=true;dye_row.add_child(picker);dye_buttons.append(picker)
		picker.color_changed.connect(func(color: Color):store.set_teen_dye(profile,zone,color))
	var colors:=HFlowContainer.new();dye_panel.add_child(colors)
	for school in store.catalog.themes:
		var id:=str(school.id);button(colors,store.theme_name(id).left(2),func():store.set_teen_dye_preset(profile,id))
	button(colors,"恢复",func():store.set_teen_dye_preset(profile,"default"))
	matching_boots_button=button(colors,"配套鞋",func():
		var spec: Dictionary=store.dye_spec(store.outfit(profile))
		if spec.has("matching_boots"):store.equip_teen(profile,"teen_boots",str(spec.matching_boots)))
func rebuild_categories() -> void:
	category_tabs.set_block_signals(true);category_tabs.clear_tabs()
	var titles: Array=["全部套装","等级套装","主题装束","重制试装"] if mode==0 else ["服装","鞋子","帽子","背饰","武器"] if mode==1 else ["衣服版型","鞋子版型","背饰版型"]
	if personal_mode:titles=["发型 / 发色","脸部预设 / 肤色"]
	for title in titles:category_tabs.add_tab(title)
	category_tabs.current_tab=0;category_tabs.set_block_signals(false)
	if personal_mode:category="teen_hair"
	elif mode==1:category=ITEM_SLOTS[0]
	elif mode==2:category=SHAPE_SLOTS[0]
func play_animation(id: String) -> void:
	current_animation=id
	if preview.teen!=null:preview.teen.preview_animation(id)
func _changed(school: String) -> void:
	if school==profile:
		shop_preview.clear();refresh()
func refresh() -> void:
	var outfit: Dictionary=store.clean_teen(store.outfit(profile))
	if last_gender!=str(outfit.gender):last_gender=str(outfit.gender);page=0;current_animation=""
	update_preview(shop_preview if not shop_preview.is_empty() else outfit)
	var worn: Dictionary=store.progression().get("equipped_stats",{})
	var slots: PackedStringArray=[]
	for slot in ["staff","hat","robe","boots"]:
		var item_id:=str(worn.get(slot,"eq_"+profile+"_"+slot+"_t0"))
		slots.append(str({"staff":"法杖","hat":"帽子","robe":"衣服","boots":"鞋子"}[slot])+" · "+item_id.get_slice("_",3).to_upper())
	equipped_summary.text="属性装备\n"+"  /  ".join(slots)
	gender_tabs.set_block_signals(true);gender_tabs.current_tab=0 if outfit.gender=="male" else 1;gender_tabs.set_block_signals(false)
	for child in action_grid.get_children():action_grid.remove_child(child);child.queue_free()
	for clip in store.teen_catalog.rigs[outfit.gender].clips:
		var id:=str(clip.id);var b:=button(action_grid,str(clip.name),func():play_animation(id));b.size_flags_horizontal=SIZE_EXPAND_FILL;b.clip_text=true
	refresh_list()
func update_preview(outfit: Dictionary) -> void:
	preview_hair_mode=personal_mode and mode==1 and category=="teen_hair"
	var appearance:=outfit.duplicate(true)
	if preview_hair_mode:appearance.teen_hat="none"
	var old_rig: int=preview.teen.get_instance_id() if preview.teen!=null else 0
	preview.school_id=profile;preview.apply_outfit(appearance)
	# Swatch updates keep the current action; only rebuilt rigs need preview playback.
	if preview.teen!=null and preview.teen.get_instance_id()!=old_rig:play_animation(current_animation)
func filtered_options(outfit: Dictionary) -> Array:
	var options: Array=[]
	var source: Array=store.teen_sets.get("sets",[]) if mode==0 else store.options_for(category)
	for item in source:
		if not store.can_use_item(item):continue
		if store.school_key(str(item.get("school","any"))) not in ["any",profile]:continue
		if mode!=0 and not store.cosmetic_visible(profile,category,str(item.id)):continue
		if str(item.get("gender","both")) not in [str(outfit.gender),"both"]:continue
		if mode==0 and not store.set_allowed(profile,item):continue
		if mode!=0 and not store.cosmetic_allowed(profile,category,str(item.id)):continue
		if mode==0 and not embedded:
			if category_tabs.current_tab==1 and not str(item.family).is_empty():continue
			if category_tabs.current_tab==2 and str(item.family).is_empty():continue
			if category_tabs.current_tab==3 and int(item.get("restyle_version",0))<1:continue
		var words: String=str(item.name)+" "+str(item.get("source",item.get("search","")))
		if not search.text.is_empty() and not words.to_lower().contains(search.text.to_lower()):continue
		options.append(item)
	return options
func refresh_list() -> void:
	if grid==null:return
	for child in grid.get_children():grid.remove_child(child);child.queue_free()
	var outfit: Dictionary=store.clean_teen(store.outfit(profile))
	if preview_hair_mode!=(personal_mode and mode==1 and category=="teen_hair"):update_preview(outfit)
	hair_panel.visible=personal_mode and category=="teen_hair" and not store.hair_spec(outfit).is_empty();hair_picker.color=Color(store.hair_color(outfit))
	var colors: Array=store.dye_colors(outfit)
	dye_panel.visible=personal_mode and category=="teen_clothes" and colors.size()==4
	if colors.size()==4:
		for zone in 4:dye_buttons[zone].color=Color(str(colors[zone]))
	matching_boots_button.visible=store.dye_spec(outfit).has("matching_boots")
	var options:=filtered_options(outfit);var pages:=maxi(1,ceili(options.size()/12.0));page=clampi(page,0,pages-1)
	pager.text="%d / %d 页 · %d %s"%[page+1,pages,options.size(),"套" if mode==0 else "件"]
	previous_button.disabled=page==0;next_button.disabled=page>=pages-1
	selected.text="当前服装："+store.option_name("teen_clothes",str(outfit.teen_clothes)) if mode==0 else "已穿戴："+store.option_name(category,str(outfit.get(category,"")))
	if preview_hair_mode:selected.text+=" · 预览暂时隐藏帽子"
	if options.is_empty():label(grid,"没有找到匹配的装扮\n试试清空搜索或切换分类",17)
	for item in options.slice(page*12,mini(options.size(),page*12+12)):add_card(item,outfit)
func add_card(item: Dictionary,outfit: Dictionary) -> void:
	var id:=str(item.id);var slot:=category;var is_set:=mode==0;var equipped:=false
	if is_set:
		equipped=true
		for part in item.pieces:
			if str(outfit.get(part,""))!=str(item.pieces[part]):equipped=false
	else:equipped=id==str(outfit.get(slot,""))
	var card:=button(grid,"",func():
		if is_set:store.equip_teen_set(profile,id)
		else:store.equip_teen(profile,slot,id))
	var allowed: bool=store.set_allowed(profile,item) if is_set else store.cosmetic_allowed(profile,slot,id)
	card.disabled=not allowed or store.appearance_busy
	card.set_meta("item_id",id);card.custom_minimum_size=Vector2(145,215) if embedded else Vector2(155,296);card.size_flags_horizontal=SIZE_EXPAND_FILL
	card.tooltip_text="来源："+str(item.get("source","账号外观收藏"))+"\n"+str(item.name)+("\n一次穿戴衣服、鞋子和配饰，缺少的配饰会卸下。" if is_set else "\n点击穿戴")
	card.add_theme_stylebox_override("normal",style("2c3d4e","dfbd80") if equipped else style("1b2d40"))
	var content:=VBoxContainer.new();content.mouse_filter=MOUSE_FILTER_IGNORE;content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);content.offset_left=8;content.offset_right=-8;content.offset_top=6;content.offset_bottom=-6;card.add_child(content)
	var key:=id if is_set else slot+"_"+str(outfit.gender)+"_"+id
	var texture:=thumbnail(key)
	if texture!=null:
		var picture:=TextureRect.new();picture.texture=texture;picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.custom_minimum_size.y=140 if embedded else 216;picture.size_flags_vertical=SIZE_EXPAND_FILL;picture.mouse_filter=MOUSE_FILTER_IGNORE;content.add_child(picture)
	else:
		var placeholder:=label(content,"—" if id=="none" else "装扮预览",22);placeholder.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;placeholder.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;placeholder.size_flags_vertical=SIZE_EXPAND_FILL;placeholder.mouse_filter=MOUSE_FILTER_IGNORE
	var title:=label(content,str(item.name),16);title.custom_minimum_size.y=38;title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;title.max_lines_visible=2;title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.mouse_filter=MOUSE_FILTER_IGNORE
	var source: String="账号收藏（所有部件均需可用）" if is_set else store.cosmetic_source(profile,slot,id)
	card.tooltip_text+="\n"+source
	var status:=label(content,"未解锁" if not allowed else "已穿戴  ✓" if equipped else "一键穿戴 · %d 件"%int(item.count) if is_set else "点击穿戴",14);status.modulate=ModernSkin.ACCENT if equipped else Color("a1b3c9");status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;status.mouse_filter=MOUSE_FILTER_IGNORE
func thumbnail(key: String) -> Texture2D:
	if thumbnails.has(key):return thumbnails[key]
	var path:="res://assets/ui/wardrobe/thumbs/"+key+".png"
	var texture: Texture2D
	if ResourceLoader.exists(path):texture=load(path)
	elif FileAccess.file_exists(path):
		var image:=Image.load_from_file(path)
		if image!=null:texture=ImageTexture.create_from_image(image)
	else:return null
	if texture!=null:thumbnails[key]=texture
	return texture
func close() -> void:
	close_requested.emit();queue_free()
func _unhandled_key_input(event: InputEvent) -> void:
	if not embedded and event.is_action_pressed("ui_cancel"):get_viewport().set_input_as_handled();close()

func select_main_page(index: int) -> void:
	personal_mode=false
	dye_search_button.show();search.placeholder_text="搜索套装、名称或编号…"
	appearance_page.visible=index==1
	equipment_page.visible=index==0
	mode_tabs.show()
	gender_tabs.hide()
	mode=mode_tabs.current_tab
	rebuild_categories()
	if index==1:refresh_list()

func open_personal() -> void:
	personal_mode=true
	dye_search_button.hide();search.placeholder_text="搜索发型或脸部预设…"
	appearance_page.show();equipment_page.hide();mode_tabs.hide()
	mode=1;page=0;search.text=""
	rebuild_categories();refresh_list()

func set_view(tab_id: String) -> void:
	end_shop_preview();shop_page.hide()
	equipment_page.visible=tab_id=="equipment";appearance_page.visible=tab_id!="equipment"
	personal_mode=tab_id=="personal";equipped_summary.visible=tab_id=="equipment"
	status_label.text="属性穿戴下一场生效；不改变已选外观。" if tab_id=="equipment" else "换装只改变外观；保存成功后生效。"
	mode_tabs.visible=not embedded;category_tabs.visible=not embedded
	for child in category_choice.get_children():category_choice.remove_child(child);child.queue_free()
	var names: Array=["发型","脸型","染色","衣服版型","鞋子版型","背饰版型"] if personal_mode else ["整套搭配","服装","鞋子","帽子","背饰","武器"]
	for index in names.size():
		var picked:=index
		var icons: Array=["hair","personal","dye","appearance","boots","back"] if personal_mode else ["all","appearance","boots","hat","back","weapon"]
		var choice:=button(category_choice,str(names[index]),_category_selected.bind(picked));choice.toggle_mode=true;choice.set_meta("category_index",index);ModernSkin.button(choice,str(icons[index]));choice.add_theme_font_size_override("font_size",15)
	dye_search_button.hide();search.text="";search.placeholder_text="搜索已拥有的装扮…" if not personal_mode else "搜索个人形象…"
	_category_selected(0)

func _category_selected(index: int) -> void:
	for choice in category_choice.get_children():choice.set_pressed_no_signal(int(choice.get_meta("category_index",-1))==index)
	page=0
	if personal_mode:
		mode=1;category=["teen_hair","teen_skin","teen_clothes","teen_body_shape","teen_boot_shape","teen_back_shape"][index]
		if index>=3:mode=2
	else:
		mode=0 if index==0 else 1
		if index>0:category=ITEM_SLOTS[index-1]
	refresh_list()

func open_shop(shop_id: String) -> void:
	status_label.text="选择商品查看详情；装扮可直接试穿。"
	personal_mode=false;end_shop_preview();update_preview(store.outfit(profile))
	appearance_page.hide();equipment_page.hide();equipped_summary.hide();shop_page.show()
	shop_page.open_shop(shop_id)

func show_shop_preview(value: Dictionary) -> void:
	shop_preview=value.duplicate(true);update_preview(shop_preview)
	status_label.text="试穿预览 · 尚未改变穿戴；离开商店恢复。"

func end_shop_preview() -> void:
	if shop_preview.is_empty():return
	shop_preview.clear()
	if is_instance_valid(preview):update_preview(store.outfit(profile))
	if is_instance_valid(status_label):status_label.text="已恢复实际穿戴。"

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT:dragging_preview=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			camera.position.z=clampf(camera.position.z+(0.35 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -0.35),-8.0,-2.5);camera.look_at(Vector3(0,1.05,0))
	elif event is InputEventMouseMotion and dragging_preview:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):preview.rotation.y+=event.relative.x*0.012
		else:dragging_preview=false
