extends Node
## Per-world, additive authoring layer. Source worlds are never overwritten.
var world: Node3D
var atlas: Node
var enabled := false
var entries: Array = []
var selected := -1
var history: Array = []
var terrain_edits: Dictionary = {}
var original_heights: Dictionary = {}
var terrain_nodes: Dictionary = {}
var objects: Node3D
var layer: CanvasLayer
var panel: PanelContainer
var toggle: Button
var model_picker: OptionButton
var category_picker: OptionButton
var model_gallery: ItemList
var thumbnails: Dictionary = {}
var thumbnail_queue: Array[String] = []
var thumbnail_busy := false
var preview_viewport: SubViewport
var preview_camera: Camera3D
var preview_object: Node3D
var reset_revision := 0
const CATEGORIES := ["全部","树木植被","岩石冰晶","建筑构件","围栏路障","灯火特效","旗帜路标","箱桶家具","车辆船只","装饰其他"]
var tool_picker: OptionButton
var object_list: ItemList
var search: LineEdit
var title_field: LineEdit
var solid: CheckBox
var fields: Array[SpinBox] = []
var radius: SpinBox
var strength: SpinBox
var notice: Label
var marker: MeshInstance3D
var model_paths: Array[String] = []
var filtered_paths: Array[String] = []
var loading_fields := false
var saved_camera := Transform3D.IDENTITY
var saved_mouse := Input.MOUSE_MODE_VISIBLE
var aim := Vector3.ZERO
var aim_valid := false
var looking := false
var save_path := ""

func _ready() -> void:
	save_path = "user://creative_worlds/"+str(world.world_root).trim_suffix("/").get_file()+".json"
	if world.has_meta("orchard_procedural_world"):
		save_path = "user://creative_worlds/star_orchard_landscape_v2.json"
	var revisions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/creative_reset_revisions.json"))
	reset_revision = int(revisions.get(str(world.world_root).trim_suffix("/").get_file(),0))
	for key in world.heights:original_heights[key] = world.heights[key].duplicate()
	for child in world.get_children():
		if child.has_meta("creator_terrain_tile"):terrain_nodes[child.get_meta("creator_terrain_tile")] = child
	objects = Node3D.new()
	objects.name = "CreativePlacements"
	world.add_child(objects)
	for path in world.prototypes:model_paths.append(str(path))
	model_paths.sort()
	_build_ui()
	marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.92
	ring.outer_radius = 1.0
	ring.rings = 32
	ring.ring_segments = 8
	marker.mesh = ring
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("64efdc")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(marker)
	marker.hide()
	_load_saved()

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _caption(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)

func _spin(parent: Node, minimum: float, maximum: float, step_value: float, initial: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step_value
	spin.value = initial
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	toggle = _button(layer,"创造模式 [F6]",_toggle)
	toggle.position = Vector2(24,190)
	panel = PanelContainer.new()
	panel.position = Vector2(20,235)
	panel.custom_minimum_size = Vector2(370,420)
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(370,420)
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_caption(box,"创造模式 · 当前地图独立保存")
	_caption(box,"右键拖动视角 · WASD 飞行 · Q/E 升降\nShift 加速 · 左键执行工具 · F6 返回游玩")
	search = LineEdit.new()
	search.placeholder_text = "筛选当前地图的模型名称"
	box.add_child(search)
	search.text_changed.connect(_filter_models)
	category_picker = OptionButton.new()
	for category in CATEGORIES:category_picker.add_item(category)
	box.add_child(category_picker)
	category_picker.item_selected.connect(func(_index: int):_filter_models(search.text))
	model_picker = OptionButton.new()
	model_picker.clip_text = true
	box.add_child(model_picker)
	model_picker.hide()
	model_gallery = ItemList.new()
	model_gallery.custom_minimum_size = Vector2(340,235)
	model_gallery.max_columns = 3
	model_gallery.fixed_column_width = 108
	model_gallery.fixed_icon_size = Vector2i(96,96)
	model_gallery.icon_mode = ItemList.ICON_MODE_TOP
	model_gallery.max_text_lines = 2
	model_gallery.add_theme_font_size_override("font_size",13)
	box.add_child(model_gallery)
	model_gallery.item_selected.connect(func(index: int):model_picker.select(index);tool_picker.select(1))
	_filter_models("")
	tool_picker = OptionButton.new()
	for text in ["选择已添加物件","放置所选模型","放置战斗盘（规划）","移动选中物件到地面","地形：抬高","地形：压低","地形：平整到点击高度","地形：平滑"]:tool_picker.add_item(text)
	box.add_child(tool_picker)
	_caption(box,"地形笔刷半径 / 每次强度")
	var brush_row := HBoxContainer.new()
	box.add_child(brush_row)
	radius = _spin(brush_row,5,180,1,30)
	strength = _spin(brush_row,0.1,20,0.5,3)
	_caption(box,"已添加物件（选择后可修改参数）")
	object_list = ItemList.new()
	object_list.custom_minimum_size.y = 110
	box.add_child(object_list)
	object_list.item_selected.connect(func(index: int):selected=index;_show_properties())
	title_field = LineEdit.new()
	title_field.placeholder_text = "物件 / 未来战斗区域名称"
	box.add_child(title_field)
	for group in ["坐标 X / Y / Z","旋转 X / Y / Z（度）","缩放 X / Y / Z"]:
		_caption(box,group)
		var row := HBoxContainer.new()
		box.add_child(row)
		for i in 3:
			var scaling: bool = fields.size() >= 6
			fields.append(_spin(row,0.05 if scaling else -100000,100 if scaling else 100000,0.05 if scaling else 0.1,1 if scaling else 0))
	solid = CheckBox.new()
	solid.text = "模型启用碰撞（战斗盘仅规划）"
	box.add_child(solid)
	_button(box,"应用名称 / 坐标 / 旋转 / 缩放",_apply_properties)
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row,"复制",_duplicate_selected)
	_button(row,"删除选中",_delete_selected)
	_button(row,"撤销",_undo)
	_button(box,"保存当前地图",_save)
	_button(box,"导出布置 JSON 到桌面",_export)
	notice = Label.new()
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size.x = 340
	box.add_child(notice)
	panel.hide()

func _filter_models(value: String) -> void:
	if model_picker == null:return
	var previous := filtered_paths[model_picker.selected] if model_picker.selected >= 0 and model_picker.selected < filtered_paths.size() else ""
	model_picker.clear()
	model_gallery.clear()
	filtered_paths.clear()
	thumbnail_queue.clear()
	for path in model_paths:
		var category := _model_category(path)
		var caption := _model_caption(path)
		if category_picker.selected > 0 and category != category_picker.selected:continue
		if value.is_empty() or value.to_lower() in (path.get_file()+caption+CATEGORIES[category]).to_lower():
			filtered_paths.append(path)
			model_picker.add_item(caption)
			model_gallery.add_item(caption,thumbnails.get(path,null))
			model_gallery.set_item_tooltip(model_gallery.item_count-1,CATEGORIES[category]+" · "+path.get_file().get_basename())
			if not thumbnails.has(path):thumbnail_queue.append(path)
	var selected_index := maxi(0,filtered_paths.find(previous))
	if not filtered_paths.is_empty():
		model_picker.select(selected_index)
		model_gallery.select(selected_index)

func _model_category(path: String) -> int:
	var name_lower := path.get_file().to_lower()
	var groups := [
		[1,["tree","grass","bush","cactus","cedar","populus","flower","fern","shumu"]],
		[6,["flag","banner","guidepost","sign","mingwangqi"]],
		[7,["box","barrel","cask","shelf","chair","table","pot","bowl","bottle","mutong","kongxiang"]],
		[8,["boat","ship","cart","wagon","feichuan","zhanche","toushiche"]],
		[4,["fence","stake","barricade","railing","lanshan","cage","tielong"]],
		[5,["brazier","fire","torch","light","lamp","flame","huolu","huoji","lazhu","dengzhu","xuanwo"]],
		[2,["rock","stone","crystal","ice","shijing","shui jing","stong"]],
		[3,["house","castle","temple","wall","pillar","tower","bridge","door","gate","tent","ladder","camp","shendian","shimen","shizhu","shenzhu","zhangpeng","gongqiao","pao","shengtang","majiu","tiejiang","shaobing","shoupeng","dating","fengche"]]
	]
	for group in groups:
		for word in group[1]:
			if word in name_lower:return int(group[0])
	return 9

func _model_caption(path: String) -> String:
	var stem := path.get_file().get_basename()
	var prefix := RegEx.new()
	prefix.compile("^(?:[0-9a-fA-F]{16}|[0-9]{3})_")
	stem = prefix.sub(stem,"")
	return stem

func _setup_thumbnail_viewport() -> void:
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(128,128)
	preview_viewport.own_world_3d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(preview_viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("253342")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.75
	preview_viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40,-35,0)
	sun.light_energy = 1.0
	preview_viewport.add_child(sun)
	preview_camera = Camera3D.new()
	preview_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	preview_camera.current = true
	preview_viewport.add_child(preview_camera)

func _render_thumbnail() -> void:
	thumbnail_busy = true
	var path: String = thumbnail_queue.pop_front()
	if preview_viewport == null:_setup_thumbnail_viewport()
	preview_object = Node3D.new()
	preview_viewport.add_child(preview_object)
	var bounds := AABB()
	var first := true
	for part in world.prototypes[path]:
		var display := MultiMeshInstance3D.new()
		display.multimesh = MultiMesh.new()
		display.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		display.multimesh.mesh = part.mesh
		display.multimesh.instance_count = 1
		display.multimesh.set_instance_transform(0,part.transform)
		world._configure_visual_group(display,{"path":path,"transforms":[Transform3D.IDENTITY],"placement_ids":[-1]},part)
		preview_object.add_child(display)
		var part_bounds: AABB = part.transform*part.mesh.get_aabb()
		bounds = part_bounds if first else bounds.merge(part_bounds)
		first = false
	var diameter := maxf(bounds.size.length(),0.1)
	preview_camera.size = diameter*1.18
	preview_camera.near = maxf(diameter*0.001,0.001)
	preview_camera.far = diameter*6.0+10.0
	preview_camera.position = bounds.get_center()+Vector3(1,0.65,1).normalized()*diameter*2.0
	preview_camera.look_at(bounds.get_center())
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_inside_tree():return
	var image := preview_viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		thumbnails[path] = ImageTexture.create_from_image(image)
		var index := filtered_paths.find(path)
		if index >= 0:model_gallery.set_item_icon(index,thumbnails[path])
	preview_object.queue_free()
	thumbnail_busy = false

func _toggle() -> void:
	if atlas.busy or atlas.encounters.active:return
	enabled = not enabled
	panel.visible = enabled
	toggle.text = "结束创造 [F6]" if enabled else "创造模式 [F6]"
	world.input_suspended = enabled
	if enabled:
		atlas.wardrobe_panel.hide()
		if atlas.library_is_open():atlas.character_library_panel.hide()
		saved_camera = world.camera.global_transform
		saved_mouse = Input.mouse_mode
		world.player.velocity = Vector3.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		looking = false
		marker.hide()
		world.camera.global_transform = saved_camera
		world.player.position.y = maxf(world.player.position.y,world._height(world.player.position)+1.0)
		Input.mouse_mode = saved_mouse
		_save()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6:
		_toggle()
		get_viewport().set_input_as_handled()
		return
	if not enabled:return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		looking = event.pressed
		if looking:get_viewport().gui_release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion and looking:
		world.camera.rotation.y -= event.relative.x*0.003
		world.camera.rotation.x = clampf(world.camera.rotation.x-event.relative.y*0.003,-1.5,1.5)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not looking:
		if tool_picker.selected == 0:_pick_object()
		elif aim_valid:_execute_tool()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not enabled:return
	if not thumbnail_busy and not thumbnail_queue.is_empty() and DisplayServer.get_name() != "headless":_render_thumbnail()
	world.input_suspended = true
	var focus := get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit or focus is TextEdit):
		var axis := Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
		var speed := 100.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 30.0
		world.camera.global_position += (world.camera.global_basis*Vector3(axis.x,0,axis.z)+Vector3.UP*axis.y).normalized()*speed*delta
	_update_aim()
	marker.visible = aim_valid and tool_picker.selected != 0 and not looking
	if marker.visible:
		marker.position = aim+Vector3.UP*0.4
		marker.scale = Vector3.ONE*(radius.value if tool_picker.selected >= 4 else 2.0)

func _update_aim() -> void:
	aim_valid = false
	var mouse := get_viewport().get_mouse_position()
	if panel.get_global_rect().has_point(mouse):return
	var ray: Vector3 = world.camera.project_ray_normal(mouse)
	var start: Vector3 = world.camera.project_ray_origin(mouse)
	var previous := start
	for step_index in range(1,1001):
		var point := start+ray*float(step_index)*2.0
		var ground: float = world._height(point)
		if ground > -990 and point.y <= ground:
			var low := previous
			var high := point
			for iteration in 10:
				var mid := (low+high)*0.5
				if mid.y > world._height(mid):low=mid
				else:high=mid
			aim = (low+high)*0.5
			aim.y = world._height(aim)
			aim_valid = true
			return
		previous = point

func _snapshot() -> void:
	history.append({"objects":entries.duplicate(true),"terrain":terrain_edits.duplicate(true)})
	if history.size()>20:history.pop_front()

func _execute_tool() -> void:
	var tool := tool_picker.selected
	if tool == 1 and filtered_paths.is_empty():return
	if tool == 3 and selected < 0:return
	_snapshot()
	if tool == 1 or tool == 2:
		var path := filtered_paths[model_picker.selected] if tool == 1 else ""
		entries.append({"kind":"model" if tool == 1 else "battle","path":path,"name":path.get_file().get_basename() if tool == 1 else "未来战斗区域 %d"%entries.size(),"position":[aim.x,aim.y+0.05,aim.z],"rotation":[0,0,0],"scale":[1,1,1],"solid":false,"encounter":"","enabled":false})
		selected = entries.size()-1
		_rebuild_objects()
	elif tool == 3:
		entries[selected].position = [aim.x,aim.y,aim.z]
		_rebuild_objects()
	else:_brush(tool)
	_save()

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _rebuild_objects() -> void:
	for child in objects.get_children():
		objects.remove_child(child)
		child.queue_free()
	object_list.clear()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		object_list.add_item(str(entry.name))
		var node := Node3D.new()
		node.set_meta("entry_index",index)
		objects.add_child(node)
		node.position = _vector(entry.position)
		node.rotation_degrees = _vector(entry.rotation)
		node.scale = _vector(entry.scale)
		if entry.kind == "battle":
			var board := preload("res://scripts/fusion_3d/battle_board.gd").new()
			node.add_child(board)
			board.setup(preload("res://scripts/fusion_3d/battle_stage.gd").SLOT_COORDS)
			board.transparency = 0.0
			var label := Label3D.new()
			label.text = str(entry.name)+"\n规划区域 · 尚未绑定战斗"
			label.position.y = 4
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			node.add_child(label)
		elif world.prototypes.has(entry.path):
			for part in world.prototypes[entry.path]:
				var display := MultiMeshInstance3D.new()
				display.multimesh = MultiMesh.new()
				display.multimesh.transform_format = MultiMesh.TRANSFORM_3D
				display.multimesh.mesh = part.mesh
				display.multimesh.instance_count = 1
				display.multimesh.set_instance_transform(0,part.transform)
				world._configure_visual_group(display,{"path":entry.path,"transforms":[node.transform],"placement_ids":[-1]},part)
				node.add_child(display)
				if bool(entry.get("solid",false)):
					var body := StaticBody3D.new()
					var shape := CollisionShape3D.new()
					shape.shape = part.mesh.create_trimesh_shape()
					shape.transform = part.transform
					body.add_child(shape)
					node.add_child(body)
	if selected >= entries.size():selected=entries.size()-1
	if selected >= 0:object_list.select(selected)
	_show_properties()

func _show_properties() -> void:
	if selected < 0:return
	var entry: Dictionary = entries[selected]
	title_field.text = str(entry.name)
	solid.button_pressed = bool(entry.get("solid",false))
	for i in 3:
		fields[i].value = entry.position[i]
		fields[i+3].value = entry.rotation[i]
		fields[i+6].value = entry.scale[i]

func _apply_properties() -> void:
	if selected < 0:return
	_snapshot()
	entries[selected].name = title_field.text
	entries[selected].solid = solid.button_pressed
	for i in 3:
		entries[selected].position[i] = fields[i].value
		entries[selected].rotation[i] = fields[i+3].value
		entries[selected].scale[i] = fields[i+6].value
	_rebuild_objects()
	_save()

func _duplicate_selected() -> void:
	if selected < 0:return
	_snapshot()
	var copy: Dictionary = entries[selected].duplicate(true)
	copy.position[0] += 3.0
	copy.name = str(copy.name)+" 副本"
	entries.append(copy)
	selected = entries.size()-1
	_rebuild_objects()
	_save()

func _delete_selected() -> void:
	if selected < 0:return
	_snapshot()
	entries.remove_at(selected)
	selected = -1
	_rebuild_objects()
	_save()

func _pick_object() -> void:
	var best := 60.0
	var mouse := get_viewport().get_mouse_position()
	for index in entries.size():
		var at := _vector(entries[index].position)
		if world.camera.is_position_behind(at):continue
		var gap: float = world.camera.unproject_position(at).distance_to(mouse)
		if gap < best:best=gap;selected=index
	if selected >= 0:object_list.select(selected);_show_properties()

func _brush(tool: int) -> void:
	var changed: Array = []
	var spacing: float = world.terrain_size/128.0
	for tile in world.heights:
		var base := Vector2(tile.x*world.terrain_size-world.origin.x,tile.y*world.terrain_size-world.origin.y)
		if not Rect2(base,Vector2.ONE*world.terrain_size).grow(radius.value).has_point(Vector2(aim.x,aim.z)):continue
		var h: PackedFloat32Array = world.heights[tile].duplicate()
		var old: PackedFloat32Array = h.duplicate()
		var tile_key := "%d,%d"%[tile.x,tile.y]
		if not terrain_edits.has(tile_key):terrain_edits[tile_key]={}
		for z in 129:
			for x in 129:
				var distance_to_brush := Vector2(base.x+x*spacing,base.y+z*spacing).distance_to(Vector2(aim.x,aim.z))
				if distance_to_brush >= radius.value:continue
				var weight := smoothstep(1.0,0.0,distance_to_brush/radius.value)
				var i: int = z*129+x
				if tool == 4:h[i]+=strength.value*weight
				elif tool == 5:h[i]-=strength.value*weight
				elif tool == 6:h[i]=lerpf(h[i],aim.y,minf(1.0,strength.value*0.1)*weight)
				else:
					var average: float = (old[z*129+maxi(0,x-1)]+old[z*129+mini(128,x+1)]+old[maxi(0,z-1)*129+x]+old[mini(128,z+1)*129+x])*0.25
					h[i]=lerpf(h[i],average,minf(1.0,strength.value*0.1)*weight)
				terrain_edits[tile_key][str(i)] = h[i]
		world.heights[tile] = h
		changed.append(tile)
	# Shared edge vertices get one identical height, including a smooth stroke.
	var shared: Dictionary = {}
	for tile in changed:
		var h: PackedFloat32Array = world.heights[tile]
		for z in 129:
			for x in 129:
				if x != 0 and x != 128 and z != 0 and z != 128:continue
				var key := Vector2i(tile.x*128+x,tile.y*128+z)
				if shared.has(key):
					h[z*129+x] = shared[key]
					terrain_edits["%d,%d"%[tile.x,tile.y]][str(z*129+x)] = h[z*129+x]
				else:shared[key]=h[z*129+x]
		world.heights[tile]=h
		_rebuild_terrain(tile)

func _rebuild_terrain(tile: Vector2i) -> void:
	if not terrain_nodes.has(tile):return
	var node: MeshInstance3D = terrain_nodes[tile]
	var arrays := node.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var h: PackedFloat32Array = world.heights[tile]
	var spacing: float = world.terrain_size/128.0
	for z in 129:
		for x in 129:
			var index: int = z*129+x
			verts[index].y = h[index]
			normals[index] = Vector3(h[z*129+maxi(x-1,0)]-h[z*129+mini(x+1,128)],2*spacing,h[maxi(z-1,0)*129+x]-h[mini(z+1,128)*129+x]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.surface_set_material(0,node.mesh.surface_get_material(0))
	node.mesh = mesh
	for body in node.get_children():
		if body is StaticBody3D:
			for shape in body.get_children():
				if shape is CollisionShape3D:shape.shape = mesh.create_trimesh_shape()

func _restore_terrain() -> void:
	for tile in original_heights:
		world.heights[tile] = original_heights[tile].duplicate()
		var key := "%d,%d"%[tile.x,tile.y]
		if terrain_edits.has(key):
			var h: PackedFloat32Array = world.heights[tile]
			for index in terrain_edits[key]:h[int(index)] = float(terrain_edits[key][index])
			world.heights[tile] = h
		_rebuild_terrain(tile)

func _undo() -> void:
	if history.is_empty():return
	var previous: Dictionary = history.pop_back()
	entries = previous.objects
	terrain_edits = previous.terrain
	_restore_terrain()
	_rebuild_objects()
	_save()

func _document() -> Dictionary:
	var result := {"version":1,"reset_revision":reset_revision,"world_root":world.world_root,"objects":entries,"terrain":terrain_edits}
	if world.has_meta("orchard_procedural_world"):
		result["terrain_revision"] = str(world.get_meta("orchard_generated_terrain",""))
	return result

func _save() -> void:
	DirAccess.make_dir_recursive_absolute("user://creative_worlds")
	var file := FileAccess.open(save_path+".tmp",FileAccess.WRITE)
	if file == null:notice.text="保存失败，请检查磁盘权限";return
	file.store_string(JSON.stringify(_document()))
	file.close()
	var error := DirAccess.rename_absolute(save_path+".tmp",save_path)
	notice.text = "已保存 · %d 个物件 / 战斗区域"%entries.size() if error == OK else "保存失败：%s"%error

func _load_saved() -> void:
	if not FileAccess.file_exists(save_path):return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary or parsed.get("world_root","") != world.world_root:return
	if int(parsed.get("reset_revision",0)) < reset_revision:
		notice.text = "云端要塞已恢复原地图，可重新布置"
		return
	entries = parsed.get("objects",[])
	terrain_edits = parsed.get("terrain",{})
	if not terrain_edits.is_empty():_restore_terrain()
	_rebuild_objects()
	notice.text = "已载入上次保存的创造内容"

func _export() -> void:
	var path := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP).path_join(str(world.world_root).trim_suffix("/").get_file()+"_creative.json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:notice.text="导出失败；可使用保存按钮保存到游戏目录";return
	file.store_string(JSON.stringify(_document(),"\t"))
	file.close()
	notice.text = "已导出："+path
