extends PanelContainer
## Directory-first library, with independent readiness and review filters.
signal placement_requested(model_id: String, clip: String)
const Library = preload("res://scripts/fusion_3d/character_library.gd")
const MonsterActor = preload("res://scripts/fusion_3d/world_one_monster.gd")
const CATEGORY_IDS = ["all", "monster", "npc", "animal", "pet", "avatar", "other"]
const CATEGORY_NAMES = ["全部", "怪物来源", "NPC 来源", "动物来源", "宠物来源", "人形 / 测试", "其他来源"]
var listing: ItemList
var search: LineEdit
var category_buttons: Array[Button] = []
var selected_category: int = 0
var source_tree: Tree
var region_filter: OptionButton
var usage_filter: OptionButton
var readiness_filter: OptionButton
var review_filter: OptionButton
var hide_lod: CheckButton
var family_key: String = "all"
var family_label: Label
var counter: Label
var info: RichTextLabel
var clips: OptionButton
var viewport: SubViewport
var actor: Node3D
var animation: AnimationPlayer
var camera: Camera3D
var rows: Array = []
var turning: bool = false
var looping: bool = true
var playing: bool = true
var speed: float = 1.0
var selected_id: String = ""
var debounce: Timer
var placement_mode := false
var placement_button: Button

func _ready() -> void:
	name = "CharacterLibrary"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 36; offset_right = -36; offset_top = 32; offset_bottom = -32
	theme = preload("res://scripts/fusion_3d/frontend_theme.gd").make_theme()
	_apply_library_theme()
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	add_child(stack)
	var bar := HBoxContainer.new()
	stack.add_child(bar)
	var title := Label.new()
	title.text = "学院图鉴 · 角色资源库"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(title)
	placement_button = Button.new()
	placement_button.text = "用此角色放置到地图"
	placement_button.pressed.connect(_request_placement)
	placement_button.hide()
	bar.add_child(placement_button)
	var close_button := Button.new()
	close_button.text = "返回探索"
	close_button.pressed.connect(hide)
	bar.add_child(close_button)
	var search_bar := HBoxContainer.new()
	stack.add_child(search_bar)
	search = LineEdit.new()
	search.placeholder_text = "搜索名称 / 原目录 / 冰岛 / 家族 / ID（空格组合搜索）"
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_bar.add_child(search)
	var reset := Button.new()
	reset.text = "重置筛选"
	reset.pressed.connect(reset_filters)
	search_bar.add_child(reset)
	debounce = Timer.new()
	debounce.one_shot = true; debounce.wait_time = 0.18
	debounce.timeout.connect(filter_rows)
	add_child(debounce)
	search.text_changed.connect(func(_text: String) -> void: debounce.start())
	var tabs := HFlowContainer.new()
	stack.add_child(tabs)
	var group := ButtonGroup.new()
	for index in CATEGORY_IDS.size():
		var button := Button.new()
		button.toggle_mode = true; button.button_group = group
		var count: int = Library.query({"source_type": CATEGORY_IDS[index]}).size() if index > 0 else Library.data().get("entries", {}).size()
		button.text = "%s (%d)" % [CATEGORY_NAMES[index], count]
		button.pressed.connect(select_category.bind(index))
		tabs.add_child(button); category_buttons.append(button)
	category_buttons[0].button_pressed = true
	var filters := HFlowContainer.new()
	stack.add_child(filters)
	var taxonomy: Dictionary = Library.data().get("taxonomy", {})
	region_filter = _picker(filters, "来源地区", taxonomy.get("source_regions", {}), "source_region")
	usage_filter = _picker(filters, "用途建议", taxonomy.get("usage_categories", {}), "usage_category")
	readiness_filter = _picker(filters, "动作能力", taxonomy.get("readiness", {}), "readiness")
	review_filter = _picker(filters, "复核状态", {"structural_checked": "结构检查无提示", "needs_review": "需要复核"}, "review")
	hide_lod = CheckButton.new()
	hide_lod.text = "隐藏 LOD 变体"
	hide_lod.toggled.connect(func(_value: bool) -> void: filter_rows())
	filters.add_child(hide_lod)
	family_label = Label.new()
	family_label.text = "目录家族：全部（家族分组不代表骨架兼容）"
	stack.add_child(family_label)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(body)
	source_tree = Tree.new()
	source_tree.custom_minimum_size = Vector2(280, 280)
	source_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	source_tree.set_column_clip_content(0, true)
	source_tree.item_selected.connect(_on_source_selected)
	body.add_child(source_tree)
	var content := HSplitContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	listing = ItemList.new()
	listing.custom_minimum_size = Vector2(350, 280)
	listing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	listing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	listing.item_selected.connect(select_model)
	content.add_child(listing)
	var preview := SubViewportContainer.new()
	preview.custom_minimum_size = Vector2(400, 280)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.stretch = true
	content.add_child(preview)
	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 500)
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	preview.add_child(viewport)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("24232a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("e3dece")
	env.environment.ambient_light_energy = 0.7
	viewport.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	viewport.add_child(light)
	camera = Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 1.7, -6.2)
	camera.look_at(Vector3(0, 1.25, 0)); camera.fov = 38
	counter = Label.new()
	stack.add_child(counter)
	var controls := HBoxContainer.new()
	stack.add_child(controls)
	clips = OptionButton.new()
	clips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clips.item_selected.connect(play_clip)
	controls.add_child(clips)
	var pause_button := CheckButton.new()
	pause_button.text = "播放"; pause_button.button_pressed = true
	pause_button.toggled.connect(_toggle_play)
	controls.add_child(pause_button)
	var loop_button := CheckButton.new()
	loop_button.text = "循环预览"; loop_button.button_pressed = true
	loop_button.toggled.connect(_toggle_loop)
	controls.add_child(loop_button)
	var turn := CheckButton.new()
	turn.text = "旋转"
	turn.toggled.connect(func(value: bool) -> void: turning = value)
	controls.add_child(turn)
	var speed_picker := OptionButton.new()
	for value in [0.5, 1.0, 1.5, 2.0]:
		speed_picker.add_item("%s×" % value)
		speed_picker.set_item_metadata(speed_picker.item_count - 1, value)
	speed_picker.select(1)
	speed_picker.item_selected.connect(func(index: int) -> void:
		speed = float(speed_picker.get_item_metadata(index))
		if is_instance_valid(animation): animation.speed_scale = speed)
	controls.add_child(speed_picker)
	var zoom := HSlider.new()
	zoom.min_value = 0.4; zoom.max_value = 1.6; zoom.step = 0.05; zoom.value = 1.0
	zoom.custom_minimum_size.x = 120; zoom.tooltip_text = "预览缩放"
	zoom.value_changed.connect(func(value: float) -> void:
		camera.position = Vector3(0, 1.25, 0) + Vector3(0, 0.45, -6.2) / value)
	controls.add_child(zoom)
	info = RichTextLabel.new()
	info.custom_minimum_size.y = 135
	info.selection_enabled = true
	info.bbcode_enabled = false
	stack.add_child(info)
	_build_source_tree()
	filter_rows()
	visibility_changed.connect(_sync_preview_visibility)
	_sync_preview_visibility()

func _picker(parent: Control, title: String, values: Dictionary, key: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.add_item(title + "：全部"); picker.set_item_metadata(0, "all")
	for id in values:
		var filter: Dictionary = {key: id}
		var count: int = Library.query(filter).size()
		if count == 0: continue
		picker.add_item("%s (%d)" % [str(values[id]), count])
		picker.set_item_metadata(picker.item_count - 1, str(id))
	picker.item_selected.connect(func(_index: int) -> void:
		if key == "source_region": family_key = "all"
		filter_rows())
	parent.add_child(picker)
	return picker

func _pick_value(picker: OptionButton) -> String:
	return str(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else "all"

func _choose(picker: OptionButton, value: String) -> void:
	for index in picker.item_count:
		if str(picker.get_item_metadata(index)) == value:
			picker.select(index)
			return
	picker.select(0)

func select_category(index: int) -> void:
	selected_category = clampi(index, 0, CATEGORY_IDS.size() - 1)
	family_key = "all"
	region_filter.select(0)
	filter_rows()

func reset_filters() -> void:
	selected_category = 0; family_key = "all"; search.text = ""
	for picker in [region_filter, usage_filter, readiness_filter, review_filter]: picker.select(0)
	hide_lod.set_pressed_no_signal(false)
	filter_rows()

func category_label(item: Dictionary) -> String:
	return str(item.get("usage_category_label", item.get("source_type_label", "用途待复核")))

func current_filters() -> Dictionary:
	return {"source_type": CATEGORY_IDS[selected_category], "source_region": _pick_value(region_filter),
		"usage_category": _pick_value(usage_filter), "readiness": _pick_value(readiness_filter),
		"review": _pick_value(review_filter), "family_key": family_key,
		"hide_lod": hide_lod.button_pressed, "search": search.text}

func filter_rows() -> void:
	if not is_instance_valid(listing): return
	debounce.stop()
	for index in category_buttons.size():
		category_buttons[index].set_pressed_no_signal(index == selected_category)
	rows = Library.query(current_filters())
	if placement_mode:rows = rows.filter(func(item: Dictionary) -> bool:return not (item.get("animations", []) as Array).is_empty())
	listing.clear()
	var keep: int = -1
	var families: Dictionary = {}
	for index in rows.size():
		var item: Dictionary = rows[index]
		var badge: String = " · LOD%s" % int(item.get("lod_level", -1)) if bool(item.get("is_lod", false)) else ""
		var review: String = " [复核]" if item.get("review_status", "") == "needs_review" else ""
		listing.add_item(str(item.get("name", item.id)) + badge + review)
		listing.set_item_tooltip(index, str(item.get("source", "")) + "\n" + category_label(item))
		families[item.get("family_key", item.id)] = true
		if str(item.id) == selected_id: keep = index
	family_label.text = "目录家族：" + ("全部（家族分组不代表骨架兼容）" if family_key == "all" else family_key)
	counter.text = "匹配 %d 个模型文件 · %d 个目录家族 · 原始地区 ≠ 学派 / 投放地图" % [rows.size(), families.size()]
	if rows.is_empty():
		clear_actor(); info.text = "没有匹配模型。可点击“重置筛选”，或取消用途、动作与复核条件。"
	else:
		var index: int = keep if keep >= 0 else 0
		listing.select(index)
		select_model(index)

func set_placement_mode(value: bool, refresh: bool = true) -> void:
	if value and not placement_mode and is_instance_valid(search) and search.text.is_empty():selected_id = "npc_kapaishangren_ec91f121"
	placement_mode = value
	if is_instance_valid(placement_button):placement_button.visible = value
	if refresh and is_instance_valid(listing):filter_rows()

func _request_placement() -> void:
	if not placement_mode or selected_id.is_empty() or not is_instance_valid(animation) or clips.selected < 0:return
	placement_requested.emit(selected_id, str(clips.get_item_metadata(clips.selected)))
	hide()

func _build_source_tree() -> void:
	source_tree.clear()
	var all_item: TreeItem = source_tree.create_item()
	all_item.set_text(0, "所有来源 (%d)" % Library.data().get("entries", {}).size())
	all_item.set_metadata(0, {"source_type": "all"})
	var categories: Dictionary = {}
	var regions: Dictionary = {}
	var families: Dictionary = {}
	for item in Library.query():
		var source_id: String = str(item.get("source_type", "other"))
		var region_id: String = source_id + "/" + str(item.get("source_region", "unassigned"))
		var key: String = str(item.get("family_key", item.id))
		if not categories.has(source_id):
			var branch: TreeItem = source_tree.create_item(all_item)
			branch.set_text(0, str(item.get("source_type_label", source_id)))
			branch.set_metadata(0, {"source_type": source_id})
			branch.collapsed = true
			categories[source_id] = branch
		if not regions.has(region_id):
			var branch: TreeItem = source_tree.create_item(categories[source_id])
			branch.set_text(0, str(item.get("source_region_label", "未标注地区")))
			branch.set_metadata(0, {"source_type": source_id, "source_region": item.get("source_region", "unassigned")})
			branch.collapsed = true
			regions[region_id] = branch
		if not families.has(key):
			var branch: TreeItem = source_tree.create_item(regions[region_id])
			branch.set_text(0, str(item.get("family_name", key)))
			branch.set_tooltip_text(0, key)
			branch.set_metadata(0, {"source_type": source_id, "source_region": item.get("source_region", "unassigned"), "family_key": key})
			families[key] = {"item": branch, "count": 0}
		families[key]["count"] += 1
	for key in families:
		var branch: TreeItem = families[key]["item"]
		branch.set_text(0, branch.get_text(0) + " (%d)" % int(families[key]["count"]))

func _on_source_selected() -> void:
	var selected: TreeItem = source_tree.get_selected()
	if selected == null: return
	var filters: Dictionary = selected.get_metadata(0)
	selected_category = maxi(0, CATEGORY_IDS.find(filters.get("source_type", "all")))
	_choose(region_filter, str(filters.get("source_region", "all")))
	family_key = str(filters.get("family_key", "all"))
	filter_rows()

func clear_actor() -> void:
	animation = null; selected_id = ""
	if is_instance_valid(actor):
		viewport.remove_child(actor)
		actor.queue_free()
	actor = null; clips.clear(); clips.disabled = true

func select_model(index: int) -> void:
	if index < 0 or index >= rows.size(): return
	var item: Dictionary = rows[index]
	if selected_id == str(item.id) and is_instance_valid(actor): return
	clear_actor()
	selected_id = str(item.id)
	actor = MonsterActor.new()
	actor.set("model_id", item.id)
	viewport.add_child(actor)
	if actor.get("visual") == null:
		info.text = "模型尚未成功导入：" + str(item.id) + "\n" + str(item.get("model", ""))
		return
	animation = actor.get("animation") as AnimationPlayer
	if is_instance_valid(animation):
		# Own the preview animation resources: changing loop mode must not affect world actors.
		animation.stop()
		for library_name in animation.get_animation_library_list():
			var copy: AnimationLibrary = animation.get_animation_library(library_name).duplicate(true) as AnimationLibrary
			animation.remove_animation_library(library_name)
			animation.add_animation_library(library_name, copy)
		for clip in animation.get_animation_list():
			if clip == "RESET": continue
			clips.add_item(str(item.get("animation_labels", {}).get(clip, "其他动作")) + " · " + clip)
			clips.set_item_metadata(clips.item_count - 1, clip)
		var selected: int = 0
		for clip_index in clips.item_count:
			if str(clips.get_item_metadata(clip_index)) == str(actor.get("idle")): selected = clip_index
		if clips.item_count > 0:
			clips.select(selected); play_clip(selected)
	clips.disabled = clips.item_count == 0
	var audit: Dictionary = item.get("animation_audit", {})
	var capable: PackedStringArray = []
	var role_labels: Dictionary = {"idle": "待机", "walk": "移动", "cast": "施法/攻击", "hit": "受击", "death": "死亡"}
	for role in role_labels:
		capable.append(str(role_labels[role]) + ("：多帧" if audit.get("animated_roles", {}).get(role, false) else "：未检出多帧"))
	var notes: PackedStringArray = []
	for note in item.get("review_labels", []): notes.append(str(note))
	info.text = "%s | %s | %s | %s\n用途建议：%s · 骨骼关节 %d · %d 段导入动作 · %s\n%s\n%s\n来源：%s\n复核：%s。动作按项目编号映射，未逐段视觉验收。" % [
		str(item.get("name", item.id)), str(item.get("source_type_label", "")), str(item.get("source_region_label", "")), str(item.get("source_version", "")),
		category_label(item), int(audit.get("joint_count", 0)), clips.item_count, str(audit.get("readiness_label", "未检查")),
		" / ".join(capable), str(item.get("classification_reason", "")), str(item.get("source", "")),
		"；".join(notes) if not notes.is_empty() else "结构检查无异常提示"]

func play_clip(index: int) -> void:
	if not is_instance_valid(animation) or index < 0 or index >= clips.item_count: return
	clips.select(index)
	var clip: String = str(clips.get_item_metadata(index))
	animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE
	animation.speed_scale = speed
	animation.play(clip, 0.15)
	animation.advance(0.0)
	if not playing: animation.pause()

func _toggle_play(value: bool) -> void:
	playing = value
	if not is_instance_valid(animation): return
	if playing: animation.play()
	else: animation.pause()

func _toggle_loop(value: bool) -> void:
	looping = value
	if is_instance_valid(animation) and clips.selected >= 0:
		var clip: String = str(clips.get_item_metadata(clips.selected))
		animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR if looping else Animation.LOOP_NONE

func _sync_preview_visibility() -> void:
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
		viewport.process_mode = Node.PROCESS_MODE_INHERIT if is_visible_in_tree() else Node.PROCESS_MODE_DISABLED

func _process(delta: float) -> void:
	if is_visible_in_tree() and turning and is_instance_valid(actor): actor.rotation.y += delta * 0.5

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide(); get_viewport().set_input_as_handled()

func _apply_library_theme() -> void:
	# Local compact controls; keep the game's font, not ornate button frames.
	theme = theme.duplicate(true) as Theme
	theme.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("15202ff5")
	panel.border_color = Color("928064")
	panel.set_border_width_all(1); panel.set_corner_radius_all(8)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		panel.set_content_margin(side, 18)
	add_theme_stylebox_override("panel", panel)
	for type_name in ["Button", "OptionButton", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var box := StyleBoxFlat.new()
			box.bg_color = Color("253449"); box.border_color = Color("43536a")
			if state == "hover" or state == "hover_pressed": box.bg_color = Color("354961")
			if state == "pressed":
				box.bg_color = Color("354c60"); box.border_color = Color("b59e70")
			if state == "disabled": box.bg_color = Color("202b3b")
			if state == "focus":
				box.bg_color = Color(0, 0, 0, 0); box.border_color = Color("b59e70")
			box.set_border_width_all(1); box.set_corner_radius_all(4)
			box.content_margin_left = 12; box.content_margin_right = 12
			box.content_margin_top = 6; box.content_margin_bottom = 6
			theme.set_stylebox(state, type_name, box)
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			theme.set_color(color_name, type_name, Color("edf1f6"))
	for type_name in ["Tree", "ItemList", "LineEdit", "RichTextLabel", "PopupMenu"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("111b29"); box.border_color = Color("354357")
		box.set_border_width_all(1); box.set_corner_radius_all(4)
		box.content_margin_left = 10; box.content_margin_right = 10
		box.content_margin_top = 6; box.content_margin_bottom = 6
		for state in (["normal", "read_only"] if type_name == "LineEdit" else ["panel", "normal"]):
			theme.set_stylebox(state, type_name, box)
		theme.set_color("font_color", type_name, Color("e0e7f0"))
	theme.set_constant("v_separation", "Tree", 6)
	theme.set_constant("v_separation", "ItemList", 6)
