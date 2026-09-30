extends "res://scripts/worlds/creative_mode.gd"
## Temporary Star Orchard editor with animated library actors.

const CharacterLibrary = preload("res://scripts/fusion_3d/character_library.gd")
const MonsterActor = preload("res://scripts/fusion_3d/world_one_monster.gd")
const OrchardStyle = preload("res://scripts/worlds/star_orchard_npc_style.gd")

var chosen_actor := ""
var chosen_clip := ""
var actor_choice_label: Label
var sections: Dictionary = {}
var section_buttons: Dictionary = {}
var terrain_buttons: Dictionary = {}
var selection_label: Label
var advanced: VBoxContainer
var gizmo: Node3D
var drag_axis := ""
var drag_start := Vector2.ZERO
var drag_position := Vector3.ZERO
var drag_rotation := Vector3.ZERO
var drag_screen_axis := Vector2.ZERO
var drag_pixels_per_unit := 1.0

func _ready() -> void:
	super._ready()
	_create_gizmo()
	_update_gizmo()

func _load_saved() -> void:
	if world.has_meta("orchard_procedural_world"):
		# Keep the former town's authoring save intact and out of the new landscape.
		save_path = "user://creative_worlds/star_orchard_landscape_v2.json"
		entries = []
		terrain_edits = {}
		if FileAccess.file_exists(save_path):
			var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
			if current is Dictionary and str(current.get("terrain_revision","")) == str(world.get_meta("orchard_generated_terrain")):
				entries = current.get("objects",[]).duplicate(true)
		_rebuild_objects()
		notice.text = "函数地形 · 高山天空城与海港城镇"
		return
	if FileAccess.file_exists(save_path):
		var local: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
		if local is Dictionary and local.get("world_root", "") == world.world_root:
			if world.has_meta("orchard_generated_terrain") and str(local.get("terrain_revision",""))!=str(world.get_meta("orchard_generated_terrain")):
				entries=local.get("objects",[]).duplicate(true)
				terrain_edits={}
				_rebuild_objects()
				_merge_satellite_anchors()
				notice.text="已保留物件布置，地形使用新版主岛生成结果"
				return
			super._load_saved()
			_merge_satellite_anchors()
			return
	var saved := preload("res://scripts/worlds/star_orchard_saved_layout.gd").document()
	entries = saved.get("objects", []).duplicate(true)
	terrain_edits = saved.get("terrain", {}).duplicate(true)
	if world.has_meta("orchard_generated_terrain"):terrain_edits={}
	if not terrain_edits.is_empty():_restore_terrain()
	_rebuild_objects()
	_merge_satellite_anchors()
	notice.text = "已载入正式星界果园布置，可继续编辑"

func _document() -> Dictionary:
	var result := super._document()
	result["terrain_revision"]=str(world.get_meta("orchard_generated_terrain",""))
	return result

func _merge_satellite_anchors() -> void:
	if world.has_meta("orchard_procedural_world"):return
	for anchor in preload("res://scripts/worlds/star_orchard_satellites.gd").document().get("anchors", []):
		var found := false
		for entry in entries:
			if str(entry.get("satellite_anchor_id", "")) != str(anchor.id):continue
			if int(entry.get("satellite_layout_version",1)) < 2 and anchor.has("legacy_center"):
				for axis in 3:entry.position[axis] = float(anchor.center[axis])+float(entry.position[axis])-float(anchor.legacy_center[axis])
				for axis in 3:entry.scale[axis] = float(entry.scale[axis])*float(anchor.scale)/float(anchor.get("legacy_scale",2.0))
			elif int(entry.get("satellite_layout_version",1)) < 3 and anchor.has("layout_v2_center"):
				for axis in 3:entry.position[axis] = float(anchor.center[axis])+float(entry.position[axis])-float(anchor.layout_v2_center[axis])
			entry["satellite_layout_version"]=3
			found=true
			break
		if found:continue
		entries.append({"kind":"battle", "path":"", "name":anchor.name,
			"position":anchor.center.duplicate(), "rotation":[0,0,0], "scale":[anchor.scale,anchor.scale,anchor.scale],
			"solid":false, "encounter":"", "enabled":false, "satellite_anchor_id":anchor.id, "satellite_layout_version":3})
	_rebuild_objects()

func _duplicate_selected() -> void:
	super._duplicate_selected()
	# A duplicate is a free planning disc, never a second override of the same ID.
	if selected >= 0 and entries[selected].has("satellite_anchor_id"):
		entries[selected].erase("satellite_anchor_id")
		_save()

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	toggle = _button(layer, "编辑星界果园  F6", _toggle)
	toggle.position = Vector2(16, 68)
	toggle.custom_minimum_size = Vector2(244, 48)
	toggle.add_theme_font_size_override("font_size", 20)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 16
	panel.offset_top = 124
	panel.offset_right = 568
	panel.offset_bottom = -16
	var editor_theme := Theme.new()
	editor_theme.default_font_size = 19
	panel.theme = editor_theme
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("142332f5")
	skin.border_color = Color("6a8594")
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(12)
	skin.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", skin)
	layer.add_child(panel)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 10)
	panel.add_child(shell)
	var heading := Label.new()
	heading.text = "星界果园 · 地图编辑"
	heading.add_theme_font_size_override("font_size", 27)
	shell.add_child(heading)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	shell.add_child(tabs)
	for item in [["terrain", "地形"], ["models", "模型"], ["npcs", "动画角色"], ["objects", "已放置"]]:
		var key: String = item[0]
		var tab := _button(tabs, item[1], func():_show_section(key))
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 46
		section_buttons[key] = tab
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	for key in ["terrain", "models", "npcs", "objects"]:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 8)
		pages.add_child(page)
		sections[key] = page
	tool_picker = OptionButton.new()
	for label in ["选择", "放置模型", "战斗盘", "移动到地面", "抬高", "压低", "平整", "平滑"]:tool_picker.add_item(label)
	tool_picker.hide()
	pages.add_child(tool_picker)
	_build_terrain_page(sections["terrain"])
	_build_models_page(sections["models"])
	_build_npc_page(sections["npcs"])
	_build_objects_page(sections["objects"])
	notice = Label.new()
	notice.text = "F6 开关编辑 · 右键转视角 · WASD 移动 · Q/E 升降"
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size.y = 42
	shell.add_child(notice)
	_show_section("terrain")
	panel.hide()

func _build_terrain_page(page: VBoxContainer) -> void:
	_caption(page, "选择笔刷，然后在地面单击")
	for item in [[4,"抬高地形"],[5,"压低地形"],[6,"平整到点击高度"],[7,"平滑地形"]]:
		var tool: int = item[0]
		var button := _button(page, item[1], func():_select_terrain_tool(tool))
		button.custom_minimum_size.y = 52
		terrain_buttons[tool] = button
	_caption(page, "笔刷半径")
	radius = _spin(page, 5, 180, 1, 30)
	_caption(page, "每次改动强度")
	strength = _spin(page, 0.1, 20, 0.5, 3)
	_caption(page, "左键逐次修改；顶部「已放置」可撤销。")

func _build_models_page(page: VBoxContainer) -> void:
	_caption(page, "选模型后，在地面单击放置")
	search = LineEdit.new()
	search.placeholder_text = "搜索模型名称"
	page.add_child(search)
	search.text_changed.connect(_filter_models)
	category_picker = OptionButton.new()
	for category in CATEGORIES:category_picker.add_item(category)
	page.add_child(category_picker)
	category_picker.item_selected.connect(func(_index: int):_filter_models(search.text))
	model_picker = OptionButton.new()
	model_picker.hide()
	page.add_child(model_picker)
	model_gallery = ItemList.new()
	model_gallery.custom_minimum_size.y = 340
	model_gallery.size_flags_vertical = Control.SIZE_EXPAND_FILL
	model_gallery.max_columns = 3
	model_gallery.fixed_column_width = 118
	model_gallery.fixed_icon_size = Vector2i(96, 96)
	model_gallery.icon_mode = ItemList.ICON_MODE_TOP
	model_gallery.max_text_lines = 2
	page.add_child(model_gallery)
	model_gallery.item_selected.connect(func(index: int):
		model_picker.select(index)
		tool_picker.select(1)
		notice.text = "已选择模型；在地面单击放置。")
	_filter_models("")

func _build_npc_page(page: VBoxContainer) -> void:
	_caption(page, "从 N 图鉴选择任何有动画的角色")
	var browse := _button(page, "打开 N 图鉴 · 预览并选择动作", _open_actor_library)
	browse.custom_minimum_size.y = 56
	actor_choice_label = Label.new()
	actor_choice_label.text = "尚未选择角色"
	actor_choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(actor_choice_label)
	_caption(page, "图鉴里选择角色与动作，点击「用此角色放置到地图」")
	_caption(page, "按 F6 回到人物，走到位置并转好朝向")
	_caption(page, "按 F7 放置；地图角色会循环播放所选动作")
	var place := _button(page, "在人物位置放置角色  F7", _place_actor_at_player)
	place.custom_minimum_size.y = 52

func _build_objects_page(page: VBoxContainer) -> void:
	_caption(page, "点画面里的物件选中它")
	_caption(page, "拖红/绿/蓝箭头移动 · 拖黄色圆环旋转")
	selection_label = Label.new()
	selection_label.text = "尚未选中物件"
	page.add_child(selection_label)
	object_list = ItemList.new()
	object_list.custom_minimum_size.y = 150
	page.add_child(object_list)
	object_list.item_selected.connect(func(index: int):selected=index;_show_properties())
	var row := HBoxContainer.new()
	page.add_child(row)
	_button(row, "复制", _duplicate_selected)
	_button(row, "删除", _delete_selected)
	_button(row, "撤销", _undo)
	_button(page, "保存地图", _save)
	_button(page, "导出 JSON 到桌面", _export)
	var exact := _button(page, "精确数值（可选） ▾", func():advanced.visible = not advanced.visible)
	exact.custom_minimum_size.y = 42
	advanced = VBoxContainer.new()
	advanced.add_theme_constant_override("separation", 6)
	page.add_child(advanced)
	advanced.hide()
	title_field = LineEdit.new()
	title_field.placeholder_text = "名称"
	advanced.add_child(title_field)
	for group in ["位置 X / Y / Z", "旋转 X / Y / Z（度）", "缩放 X / Y / Z"]:
		_caption(advanced, group)
		var field_row := HBoxContainer.new()
		advanced.add_child(field_row)
		for axis in ["X", "Y", "Z"]:
			var scaling: bool = fields.size() >= 6
			var field := _spin(field_row, 0.05 if scaling else -100000, 100 if scaling else 100000, 0.05 if scaling else 0.1, 1 if scaling else 0)
			field.prefix = axis
			fields.append(field)
	solid = CheckBox.new()
	solid.text = "模型碰撞"
	advanced.add_child(solid)
	_button(advanced, "应用精确数值", _apply_properties)

func _show_section(key: String) -> void:
	for name in sections:
		(sections[name] as Control).visible = name == key
		(section_buttons[name] as Button).modulate = Color("fff0bf") if name == key else Color("a9bbca")
	if key == "terrain":_select_terrain_tool(4)
	elif key == "models":tool_picker.select(1)
	else:tool_picker.select(0)
	_update_gizmo()

func _select_terrain_tool(tool: int) -> void:
	tool_picker.select(tool)
	for index in terrain_buttons:
		(terrain_buttons[index] as Button).modulate = Color("fff0bf") if index == tool else Color("a9bbca")

func _toggle() -> void:
	super._toggle()
	toggle.text = "关闭编辑  F6" if enabled else "编辑星界果园  F6"
	_update_gizmo()

func _execute_tool() -> void:
	var placing_model := tool_picker.selected == 1
	super._execute_tool()
	if placing_model and selected >= 0:_show_section("objects")

func _show_properties() -> void:
	super._show_properties()
	if selection_label != null:
		selection_label.text = "选中：" + str(entries[selected].get("name", "物件")) if selected >= 0 and selected < entries.size() else "尚未选中物件"
	_update_gizmo()

func _create_gizmo() -> void:
	gizmo = Node3D.new()
	gizmo.name = "ObjectGizmo"
	world.add_child(gizmo)
	for data in [["x",Vector3.RIGHT,Color("ef6868")], ["y",Vector3.UP,Color("79da8b")], ["z",Vector3.BACK,Color("71b8ff")]]:
		var axis: Vector3 = data[1]
		var material := StandardMaterial3D.new()
		material.albedo_color = data[2]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		var shaft := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.025
		cylinder.bottom_radius = 0.025
		cylinder.height = 0.82
		shaft.mesh = cylinder
		shaft.material_override = material
		shaft.position = axis * 0.41
		shaft.quaternion = Quaternion(Vector3.UP, axis)
		gizmo.add_child(shaft)
		var head := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.11
		cone.height = 0.23
		head.mesh = cone
		head.material_override = material
		head.position = axis * 0.94
		head.quaternion = Quaternion(Vector3.UP, axis)
		gizmo.add_child(head)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.25
	torus.outer_radius = 1.31
	torus.rings = 64
	torus.ring_segments = 8
	ring.mesh = torus
	var ring_material := StandardMaterial3D.new()
	ring_material.albedo_color = Color("ffe189")
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.no_depth_test = true
	ring.material_override = ring_material
	gizmo.add_child(ring)
	gizmo.hide()

func _update_gizmo() -> void:
	if gizmo == null:return
	var visible_now := enabled and tool_picker != null and tool_picker.selected == 0 and selected >= 0 and selected < objects.get_child_count() and sections.has("objects") and (sections["objects"] as Control).visible
	gizmo.visible = visible_now
	if not visible_now:return
	var target := objects.get_child(selected) as Node3D
	gizmo.global_position = target.global_position + Vector3.UP * 0.8
	var distance: float = world.camera.global_position.distance_to(gizmo.global_position)
	gizmo.scale = Vector3.ONE * clampf(distance * 0.09, 2.2, 20.0)

func _gizmo_hit(mouse: Vector2) -> String:
	if gizmo == null or not gizmo.visible:return ""
	var origin: Vector3 = gizmo.global_position
	var screen_origin: Vector2 = world.camera.unproject_position(origin)
	var size: float = gizmo.scale.x
	var nearest := 18.0
	var result := ""
	for data in [["x",Vector3.RIGHT], ["y",Vector3.UP], ["z",Vector3.BACK]]:
		var tip: Vector2 = world.camera.unproject_position(origin + (data[1] as Vector3) * size)
		var gap: float = Geometry2D.get_closest_point_to_segment(mouse, screen_origin, tip).distance_to(mouse)
		if gap < nearest and mouse.distance_to(screen_origin) > 12.0:
			nearest = gap
			result = data[0]
	if not result.is_empty():return result
	for index in 64:
		var a: float = TAU * index / 64.0
		var b: float = TAU * (index + 1) / 64.0
		var p1: Vector2 = world.camera.unproject_position(origin + Vector3(cos(a), 0, sin(a)) * size * 1.28)
		var p2: Vector2 = world.camera.unproject_position(origin + Vector3(cos(b), 0, sin(b)) * size * 1.28)
		if Geometry2D.get_closest_point_to_segment(mouse, p1, p2).distance_to(mouse) < 12.0:return "rotate"
	return ""

func _begin_gizmo_drag(axis: String, mouse: Vector2) -> void:
	_snapshot()
	drag_axis = axis
	drag_start = mouse
	drag_position = _vector(entries[selected].position)
	drag_rotation = _vector(entries[selected].rotation)
	if axis == "rotate":return
	var direction := Vector3.RIGHT if axis == "x" else (Vector3.UP if axis == "y" else Vector3.BACK)
	var origin: Vector3 = gizmo.global_position
	var screen_delta: Vector2 = world.camera.unproject_position(origin + direction) - world.camera.unproject_position(origin)
	drag_pixels_per_unit = maxf(screen_delta.length(), 1.0)
	drag_screen_axis = screen_delta.normalized()

func _drag_gizmo(mouse: Vector2) -> void:
	if drag_axis.is_empty() or selected < 0 or selected >= entries.size():return
	var node := objects.get_child(selected) as Node3D
	if drag_axis == "rotate":
		var degrees := (mouse.x - drag_start.x) * 0.6
		if Input.is_key_pressed(KEY_SHIFT):degrees = snappedf(degrees, 15.0)
		var angles := drag_rotation
		angles.y += degrees
		entries[selected].rotation = [angles.x, angles.y, angles.z]
		node.rotation_degrees = angles
	else:
		var units: float = (mouse - drag_start).dot(drag_screen_axis) / drag_pixels_per_unit
		if Input.is_key_pressed(KEY_SHIFT):units = snappedf(units, 0.5)
		var at := drag_position
		if drag_axis == "x":at.x += units
		elif drag_axis == "y":at.y += units
		else:at.z += units
		entries[selected].position = [at.x, at.y, at.z]
		node.position = at
	_update_gizmo()

func _finish_gizmo_drag() -> void:
	if drag_axis.is_empty():return
	drag_axis = ""
	_show_properties()
	_save()
	notice.text = "物件已移动或旋转；可继续拖动箭头和圆环。"

func _process(delta: float) -> void:
	if is_instance_valid(atlas) and atlas.library_is_open():return
	super._process(delta)
	_update_gizmo()

func _exit_tree() -> void:
	if not is_instance_valid(atlas) or not is_instance_valid(atlas.character_library_panel):return
	var library: Control = atlas.character_library_panel
	var callback := Callable(self, "_choose_actor_from_library")
	if library.placement_requested.is_connected(callback):library.placement_requested.disconnect(callback)
	var visibility_callback := Callable(self, "_on_library_visibility_changed")
	if library.visibility_changed.is_connected(visibility_callback):library.visibility_changed.disconnect(visibility_callback)
	library.set_placement_mode(false, false)

func _open_actor_library() -> void:
	if not is_instance_valid(atlas) or atlas.busy or atlas.encounters.active:return
	if not atlas.library_is_open():atlas.toggle_character_library()
	var library: Control = atlas.character_library_panel
	if library == null:return
	library.set_placement_mode(true)
	var callback := Callable(self, "_choose_actor_from_library")
	if not library.placement_requested.is_connected(callback):library.placement_requested.connect(callback)
	var visibility_callback := Callable(self, "_on_library_visibility_changed")
	if not library.visibility_changed.is_connected(visibility_callback):library.visibility_changed.connect(visibility_callback)
	layer.hide()
	library.show()

func _on_library_visibility_changed() -> void:
	if not is_instance_valid(atlas) or not atlas.library_is_open():layer.show()

func _choose_actor_from_library(model_id: String, clip: String) -> void:
	var item := CharacterLibrary.entry(model_id)
	if item.is_empty() or clip.is_empty():return
	chosen_actor = model_id
	chosen_clip = clip
	actor_choice_label.text = "已选择：%s\n动作：%s" % [str(item.get("name", model_id)), str(item.get("animation_labels", {}).get(clip, clip)) + " · " + clip]
	notice.text = "角色与动作已选好。按 F6 行走，按 F7 放置。"

func _input(event: InputEvent) -> void:
	if enabled and is_instance_valid(atlas) and atlas.library_is_open():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_N] and not (get_viewport().gui_get_focus_owner() is LineEdit):
			atlas.character_library_panel.hide()
			get_viewport().set_input_as_handled()
		return
	super._input(event)
	if not drag_axis.is_empty():
		if event is InputEventMouseMotion:
			_drag_gizmo(event.position)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_gizmo_drag()
			get_viewport().set_input_as_handled()
			return
	if enabled and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
		_open_actor_library()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_F7:return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:return
	if atlas.library_is_open():return
	_place_actor_at_player()
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if enabled and tool_picker.selected == 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var mouse: Vector2 = event.position
		if panel.get_global_rect().has_point(mouse):return
		var handle := _gizmo_hit(mouse)
		if not handle.is_empty():
			_begin_gizmo_drag(handle, mouse)
			get_viewport().set_input_as_handled()
			return
		_pick_object()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)

func _pick_object() -> void:
	var mouse := get_viewport().get_mouse_position()
	var best := INF
	var found := -1
	for index in entries.size():
		var node := objects.get_child(index) as Node3D
		var origin: Vector3 = node.global_position
		if world.camera.is_position_behind(origin):continue
		var screen: Vector2 = world.camera.unproject_position(origin)
		var distance: float = mouse.distance_to(screen)
		if distance < 44.0 and distance < best:
			best = distance
			found = index
		for visual in node.find_children("*", "VisualInstance3D", true, false):
			var rect := _visual_screen_rect(visual)
			if rect.has_point(mouse):
				var score: float = mouse.distance_to(rect.get_center()) * 0.01 + maxf(0.0, world.camera.global_position.distance_to(origin) * 0.001)
				if score < best:
					best = score
					found = index
	selected = found
	if found >= 0:object_list.select(found)
	else:object_list.deselect_all()
	_show_properties()

func _visual_screen_rect(visual: VisualInstance3D) -> Rect2:
	var bounds := visual.get_aabb()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner in 8:
		var local := bounds.position + bounds.size * Vector3(float(corner & 1), float((corner >> 1) & 1), float((corner >> 2) & 1))
		var point: Vector3 = visual.global_transform * local
		if world.camera.is_position_behind(point):continue
		var projected: Vector2 = world.camera.unproject_position(point)
		minimum = minimum.min(projected)
		maximum = maximum.max(projected)
	if minimum.x == INF:return Rect2()
	return Rect2(minimum, maximum - minimum).grow(8.0)

func _place_actor_at_player() -> void:
	if chosen_actor.is_empty() or chosen_clip.is_empty() or not is_instance_valid(world.player) or not is_instance_valid(world.avatar):return
	if atlas.busy or atlas.encounters.active:return
	if is_instance_valid(atlas.game_menu) and atlas.game_menu.is_open():return
	var at: Vector3 = world.player.position
	var ground: float = world._height(at)
	if ground > -990:at.y = ground
	_snapshot()
	var title := str(CharacterLibrary.entry(chosen_actor).get("name", chosen_actor))
	entries.append({
		"kind":"actor", "actor_id":chosen_actor, "animation_clip":chosen_clip, "path":"", "name":title,
		"position":[at.x,at.y,at.z],
		"rotation":[0.0,rad_to_deg(world.avatar.global_rotation.y),0.0],
		"scale":[1.0,1.0,1.0], "solid":false
	})
	selected = entries.size()-1
	_rebuild_objects()
	_save()
	if enabled:_show_section("objects")
	notice.text = "已放置动画角色：" + title

func _rebuild_objects() -> void:
	for entry in entries:
		if str(entry.get("kind", "")) in ["actor", "npc"]:OrchardStyle.prepare_entry(entry)
	super._rebuild_objects()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		if entry.has("satellite_anchor_id") and not preload("res://scripts/worlds/star_orchard_features.gd").SATELLITES_ENABLED:
			objects.get_child(index).hide()
			continue
		if entry.has("satellite_anchor_id") and not str(entry.satellite_anchor_id).begins_with("orchard_temple") and not preload("res://scripts/worlds/star_orchard_satellites.gd").battle_courts_enabled():
			objects.get_child(index).hide()
		if str(entry.get("kind", "")) not in ["actor", "npc"]:continue
		var id := str(entry.get("actor_id", entry.get("npc_id", "")))
		if id.is_empty():continue
		var holder := MonsterActor.new()
		holder.model_id = id
		objects.get_child(index).add_child(holder)
		if holder.visual == null:
			push_warning("星界果园角色模型未找到：" + id)
			continue
		OrchardStyle.apply_to(holder, id)
		_play_placed_actor(holder, id, str(entry.get("animation_clip", "")))
	_update_gizmo()

func _play_placed_actor(holder: Node3D, model_id: String, requested_clip: String) -> void:
	var players := holder.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():return
	var player := players[0] as AnimationPlayer
	var clip := requested_clip
	if clip.is_empty() or not player.has_animation(clip):
		for candidate in player.get_animation_list():
			if "000" in candidate or "Idle" in candidate:
				clip = candidate
				break
		if clip.is_empty() and not player.get_animation_list().is_empty():clip = player.get_animation_list()[0]
	if clip.is_empty():return
	for library_name in player.get_animation_library_list():
		var original := player.get_animation_library(library_name)
		var copy := original.duplicate(true) as AnimationLibrary
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, copy)
	player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	player.play(clip)
	player.advance(0.0)
	holder.set_meta("orchard_actor_id", model_id)
	holder.set_meta("orchard_animation_clip", clip)
