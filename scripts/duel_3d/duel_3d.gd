extends Node3D
## Presentation only: every action, cost, target and outcome goes through BattleEngineV2.
const Encounter = preload("res://scripts/duel_3d/duel_encounter.gd")
const GOLD := Color("e8c780")
const INK := Color("241d30")
const COLORS := {"fire":Color("ff905b"), "life":Color("7be3b0"), "ice":Color("80cfff"), "storm":Color("c2a0ff"), "balance":Color("f5d48b"), "death":Color("a394c9"), "myth":Color("e4bb64")}
const NAMES := {"P0":"赤焰学徒", "P1":"苔光医师", "E0":"灰烬术士", "E1":"寒霜守卫"}
var session: BattleSandboxControllerV2
var engine: BattleEngineV2
var actors: Dictionary = {}
var plates: Dictionary = {}
var markers: Dictionary = {}
var units_ui: Dictionary = {}
var camera: Camera3D
var hud: Control
var hand: HBoxContainer
var round_label: Label
var hint: Label
var resource_label: Label
var log_label: Label
var resolve_button: Button
var pass_button: Button
var auto_button: Button
var restart_button: Button
var result_panel: PanelContainer
var result_label: Label
var active_id: StringName = &"P0"
var selected: int = -1
var busy := false
var messages: Array[String] = []
var elapsed := 0.0
var orbit := 0.0
var fast_mode := false
var theatre: Node3D
var unit_names: Dictionary = {}
var unit_stats: Dictionary = {}
var unit_health: Dictionary = {}
var persistent_fx: Dictionary = {}
var cinematic_weight := 0.0
var cinematic_target := Vector3.ZERO

func _ready() -> void:
	_build_world()
	_build_ui()
	_start()

func _start() -> void:
	if busy:
		return
	session = Encounter.create()
	if session == null:
		hint.text = "战斗数据加载失败，请查看 Godot 输出。"
		return
	engine = session.engine
	active_id = &"P0"
	selected = -1
	busy = false
	messages.clear()
	theatre.clear()
	result_panel.hide()
	for actor in actors.values():
		actor.queue_free()
	actors.clear()
	persistent_fx.clear()
	plates.clear()
	markers.clear()
	for unit in engine.state.units:
		_build_actor(unit)
	_log("法阵已启动。选择卡牌，再点击角色或队伍面板指定目标。")
	_refresh()

func _material(color: Color, emission: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.72
	if emission > 0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emission * 0.25
	return mat

func _mesh(parent: Node3D, shape: Mesh, at: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = shape
	node.position = at
	node.material_override = _material(color, glow)
	parent.add_child(node)
	return node

func _cylinder(parent: Node3D, at: Vector3, bottom: float, top: float, height: float, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = bottom
	shape.top_radius = top
	shape.height = height
	shape.radial_segments = 32
	return _mesh(parent, shape, at, color, glow)

func _orb(parent: Node3D, at: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2
	return _mesh(parent, shape, at, color, 1.0)

func _ring(parent: Node3D, radius: float, y: float, color: Color, thickness: float = 0.035) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - thickness
	shape.outer_radius = radius + thickness
	shape.rings = 64
	shape.ring_segments = 8
	return _mesh(parent, shape, Vector3(0,y,0), color, 1.0)

func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("090914")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4a4d3")
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-28,0)
	sun.light_color = Color("f0d6b0")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.position = Vector3(0,17.5,18.6)
	camera.fov = 45
	add_child(camera)
	camera.look_at(Vector3(0,0,2.1))
	camera.current = true
	# The original plate is already an oblique ellipse. Mapping its complete UVs
	# onto a square world plane removes that baked foreshortening before the 3D camera.
	var plate := PlaneMesh.new()
	plate.size = Vector2(17,17)
	var surface := _mesh(self,plate,Vector3(0,0.08,0),Color.WHITE)
	surface.name = "ReferenceBattlePlate"
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ArtRegistryV2.texture(&"battle_plate_user_v2")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	surface.material_override = mat
	_cylinder(self,Vector3(0,-0.25,0),8.32,8.32,0.50,Color("302033"))
	_cylinder(self,Vector3(0,-0.48,0),8.6,8.45,0.16,Color("735339"))
	# Dim paved surroundings, stone pillars and gothic pointed arches keep focus on the plate.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(120,120)
	_mesh(self,floor_mesh,Vector3(0,-0.68,0),Color("0b0910"))
	for i in 14:
		var a := float(i)*TAU/14.0
		var pos := Vector3(sin(a)*11.8,0,cos(a)*11.8)
		_cylinder(self,pos+Vector3(0,1.6,0),0.30,0.24,4.4,Color("312940"))
		_cylinder(self,pos+Vector3(0,-0.28,0),0.52,0.50,0.25,Color("493951"))
		_cylinder(self,pos+Vector3(0,3.82,0),0.43,0.43,0.18,Color("8a684b"))
		var next_angle := float(i+1)*TAU/14.0
		var next_pos := Vector3(sin(next_angle)*11.8,0,cos(next_angle)*11.8)
		for j in 12:
			var t0 := float(j)/12.0
			var t1 := float(j+1)/12.0
			var start := pos.lerp(next_pos,t0)+Vector3.UP*(3.9+1.7*sin(t0*PI))
			var finish := pos.lerp(next_pos,t1)+Vector3.UP*(3.9+1.7*sin(t1*PI))
			var beam := _cylinder(self,(start+finish)*0.5,0.15,0.15,start.distance_to(finish),Color("332a3c"))
			beam.quaternion = Quaternion(Vector3.UP,(finish-start).normalized())
		_orb(self,pos+Vector3(0,4.16,0),0.11,Color("b899ed"))
		var light := OmniLight3D.new()
		light.position = pos+Vector3(0,3.5,0)
		light.light_color = Color("b187ea")
		light.light_energy = 0.65
		light.omni_range = 7.0
		add_child(light)
	var random := RandomNumberGenerator.new()
	random.seed = 55
	for i in 80:
		_orb(self,Vector3(random.randf_range(-25,25),random.randf_range(5,18),random.randf_range(-24,-14)),random.randf_range(0.018,0.038),Color("b5a6d1"))
	var theatre_script = preload("res://scripts/duel_3d/spell_theatre.gd")
	theatre = theatre_script.new()
	add_child(theatre)
	theatre.configure(self)

func _build_actor(unit: BattleUnitStateV2) -> void:
	var root := Node3D.new()
	# Centers measured from the reference plate's inner pair of top/bottom pads.
	root.position = Vector3(-2.17 if unit.slot == 0 else 2.16,0.10,5.30 if unit.team == 0 else -6.55)
	add_child(root)
	actors[unit.id] = root
	var color: Color = COLORS.get(str(unit.school_id),GOLD)
	var body = preload("res://scenes/characters/wizard.tscn").instantiate()
	body.name = "Body"
	root.add_child(body)
	body.rotation.y = 0.18 if unit.team == 0 else PI-0.18
	body.configure(color,str(unit.school_id),unit.team == 1)
	var circle := _ring(root,0.78,0.10,color,0.018)
	markers[unit.id] = circle
	var label := Label3D.new()
	label.position.y = 3.48
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 32
	label.pixel_size = 0.007
	label.no_depth_test = true
	label.modulate = Color("f3dfb1")
	root.add_child(label)
	plates[unit.id] = label
	var area := Area3D.new()
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.70
	shape.height = 3.1
	collision.shape = shape
	collision.position.y = 1.5
	area.add_child(collision)
	root.add_child(area)
	area.input_event.connect(func(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _index: int):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_pick_unit(unit.id))

func _style(color: Color, border: Color = Color("435574")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _label(parent: Node, text_value: String, size_value: int = 20) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size",size_value)
	parent.add_child(label)
	return label

func _button(parent: Node, text_value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_stylebox_override("normal",_style(INK))
	button.add_theme_stylebox_override("hover",_style(Color("493650"),GOLD))
	button.add_theme_stylebox_override("pressed",_style(Color("5a435c"),GOLD))
	button.add_theme_stylebox_override("disabled",_style(Color("141c2c"),Color("273146")))
	button.add_theme_font_size_override("font_size",18)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _texture(parent: Node, id: StringName, rect: Rect2) -> TextureRect:
	var item := TextureRect.new()
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.texture = ArtRegistryV2.texture(id)
	item.position = rect.position
	item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	item.size = rect.size
	item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(item)
	item.set_deferred("size",rect.size)
	return item

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	var title := VBoxContainer.new()
	title.position = Vector2(34,23)
	hud.add_child(title)
	_label(title,"星 辉 学 院",29).modulate = GOLD
	_label(title,"A S T R A L   ·   D U E L",13).modulate = Color("aa94be")
	var round_panel := PanelContainer.new()
	round_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	round_panel.offset_left = -155
	round_panel.offset_right = 155
	round_panel.offset_top = 18
	round_panel.offset_bottom = 87
	round_panel.add_theme_stylebox_override("panel",_style(Color("211b30e8"),Color("826842")))
	hud.add_child(round_panel)
	round_label = _label(round_panel,"",19)
	round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	round_label.modulate = GOLD
	var commands := HBoxContainer.new()
	commands.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	commands.position = Vector2(-333,26)
	commands.add_theme_constant_override("separation",7)
	hud.add_child(commands)
	_button(commands,"镜头 ↻",func(): orbit += 0.3)
	var speed_button := _button(commands,"演出 ×1",func(): fast_mode = not fast_mode)
	speed_button.pressed.connect(func(): speed_button.text = "演出 ×5" if fast_mode else "演出 ×1")
	restart_button = _button(commands,"重新挑战",_start)
	for team in 2:
		var column := VBoxContainer.new()
		if team == 0:
			column.position = Vector2(28,130)
		else:
			column.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			column.position = Vector2(-264,130)
		column.custom_minimum_size.x = 236
		column.add_theme_constant_override("separation",12)
		hud.add_child(column)
		_label(column,"✦  星辉守护者" if team == 0 else "✦  裂隙挑战者",17).modulate = GOLD
		for i in 2:
			var id := StringName(("P" if team == 0 else "E")+str(i))
			var school: String = ("fire" if i == 0 else "life") if team == 0 else ("fire" if i == 0 else "ice")
			var button := _button(column,"",func(): _pick_unit(id))
			button.custom_minimum_size = Vector2(236,128)
			button.add_theme_stylebox_override("normal",_style(Color("181624ed"),Color("74603e")))
			units_ui[id] = button
			_texture(button,StringName("wizard_"+school+"_front"),Rect2(2,8,79,112))
			var name_label := _label(button,_name(id),18)
			name_label.position = Vector2(84,17)
			name_label.modulate = GOLD
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			unit_names[id] = name_label
			var stats := _label(button,"",14)
			stats.position = Vector2(84,48)
			stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
			unit_stats[id] = stats
			var bar := ProgressBar.new()
			bar.position = Vector2(84,80)
			bar.size = Vector2(134,8)
			bar.show_percentage = false
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.add_theme_stylebox_override("background",_style(Color("0c0d13")))
			bar.add_theme_stylebox_override("fill",_style(Color("8bab71") if team == 0 else Color("b15f61")))
			for style_id in ["background","fill"]:
				var bar_style := bar.get_theme_stylebox(style_id)
				for edge in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
					bar_style.set_content_margin(edge,0)
			bar.size = Vector2(134,8)
			button.add_child(bar)
			bar.set_deferred("size",Vector2(134,8))
			unit_health[id] = bar
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 18
	bottom.offset_right = -18
	bottom.offset_top = -349
	bottom.offset_bottom = -12
	bottom.add_theme_stylebox_override("panel",_style(Color("13121de8"),Color("65503e")))
	hud.add_child(bottom)
	var ornament := TextureRect.new()
	ornament.texture = ArtRegistryV2.texture(&"ui_bottom_hand_tray")
	ornament.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ornament.stretch_mode = TextureRect.STRETCH_SCALE
	ornament.modulate = Color(0.72,0.64,0.8,0.55)
	ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(ornament)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",6)
	bottom.add_child(stack)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation",12)
	stack.add_child(toolbar)
	resource_label = _label(toolbar,"",17)
	resource_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resource_label.modulate = Color("f3e3bd")
	pass_button = _button(toolbar,"蓄能",_pass)
	auto_button = _button(toolbar,"AI 补全",_auto_plan)
	resolve_button = _button(toolbar,"✦  开始施法",_resolve)
	resolve_button.add_theme_stylebox_override("normal",_style(Color("59402b"),GOLD))
	hint = _label(stack,"",15)
	hint.modulate = Color("c4b1cf")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hand = HBoxContainer.new()
	hand.alignment = BoxContainer.ALIGNMENT_CENTER
	hand.add_theme_constant_override("separation",12)
	hand.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(hand)
	log_label = Label.new()
	log_label.position = Vector2(30,474)
	log_label.add_theme_font_size_override("font_size",13)
	log_label.modulate = Color("aa9cb7")
	log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(log_label)
	result_panel = PanelContainer.new()
	result_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	result_panel.offset_left = -255
	result_panel.offset_right = 255
	result_panel.offset_top = -115
	result_panel.offset_bottom = 65
	result_panel.add_theme_stylebox_override("panel",_style(Color("241c31"),GOLD))
	hud.add_child(result_panel)
	var result_stack := VBoxContainer.new()
	result_stack.add_theme_constant_override("separation",18)
	result_panel.add_child(result_stack)
	result_label = _label(result_stack,"",25)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.modulate = GOLD
	_button(result_stack,"再次挑战",_start)

func _card_widget(card: CardInstanceV2, planning: bool, active: BattleUnitStateV2) -> void:
	var definition := card.definition
	var button := _button(hand,"",func(): _select_card(card.instance_id))
	button.custom_minimum_size = Vector2(166,248)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.disabled = not planning or not engine.cost_resolver.can_pay(active,definition) or engine.state.actions.has(active_id) or not active.alive
	var color: Color = COLORS.get(str(definition.school_id),GOLD)
	button.add_theme_stylebox_override("normal",_style(Color("171320"),GOLD if selected == card.instance_id else color.darkened(0.50)))
	button.add_theme_stylebox_override("hover",_style(Color("302039"),GOLD))
	var frame := _texture(button,StringName("card_frame_"+str(definition.school_id)),Rect2(0,0,166,248))
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	var title := _label(button,_card_name(definition),16)
	title.position = Vector2(12,36)
	title.size = Vector2(142,25)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.modulate = Color("ffedc5")
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not definition.art_path.is_empty() and ResourceLoader.exists(definition.art_path):
		var art := TextureRect.new()
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.texture = load(definition.art_path)
		art.position = Vector2(18,63)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.size = Vector2(130,112)
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(art)
		art.set_deferred("size",Vector2(130,112))
	var cost := _label(button,definition.cost_label(),21)
	cost.position = Vector2(7,9)
	cost.size = Vector2(31,28)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.modulate = Color("fff2cc")
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var detail := _label(button,_description(definition)+"\n命中 %d%%" % int(definition.accuracy*100),14)
	detail.position = Vector2(12,165)
	detail.size = Vector2(142,42)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.tooltip_text = "右键：弃牌换宝藏。\n"+_description(definition)
	if button.disabled: button.modulate = Color(0.56,0.54,0.60)
	button.mouse_entered.connect(func():
		if not button.disabled:
			button.pivot_offset = button.size*Vector2(0.5,1)
			button.z_index = 2
			create_tween().tween_property(button,"scale",Vector2.ONE*1.045,0.12))
	button.mouse_exited.connect(func():
		button.z_index = 0
		create_tween().tween_property(button,"scale",Vector2.ONE,0.12))
	button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and planning and not engine.state.actions.has(active_id):
			if engine.discard_for_treasure(active_id,card.instance_id):
				selected = -1
				_refresh())

func _name(id: StringName) -> String:
	return NAMES.get(str(id),str(id))

func _card_name(card: CardDefinitionV2) -> String:
	return {"fire_serpent":"烈焰灵蛇", "ember_trap":"余烬陷阱"}.get(str(card.id),Locale.text(str(card.name_key)))

func _description(card: CardDefinitionV2) -> String:
	var lines: Array[String] = []
	for effect in card.effects:
		match str(effect.get("type","")):
			"damage": lines.append("伤害 %d" % int(effect.get("power",0)))
			"heal": lines.append("治疗 %d" % int(effect.get("power",0)))
			"apply_dot": lines.append("每轮伤害 %d × %d" % [int(effect.get("damage_per_tick",0)),int(effect.get("ticks",0))])
			"apply_hot": lines.append("每轮治疗 %d × %d" % [int(effect.get("healing_per_tick",0)),int(effect.get("ticks",0))])
			"apply_status": lines.append("%s %+d%%" % [_status_name(str(effect.get("status",""))),int(effect.get("value",0))])
	return "\n".join(lines)

func _status_name(kind: String) -> String:
	return {"shield":"护盾", "blade":"刀刃", "trap":"陷阱", "weakness":"虚弱", "dot":"持续伤害", "hot":"持续治疗"}.get(kind,kind)

func _refresh() -> void:
	var finished := engine.state.phase == BattleStateV2.Phase.FINISHED
	var planning := not busy and not finished
	round_label.text = "第 %02d / 30 回合\n%s" % [engine.state.round_index,"结算中" if busy else ("对决结束" if finished else "规划行动")]
	var active := engine.state.unit_by_id(active_id)
	resource_label.text = "%s  |  普通豆 %d · 超级豆 %d  |  牌库 %d" % [_name(active_id),active.resources.pips.count(ResourceStateV2.PipKind.NORMAL),active.resources.pips.count(ResourceStateV2.PipKind.POWER),active.deck.draw_pile.size()]
	resource_label.tooltip_text = "普通豆提供1点；超级豆对本学院法术提供2点，对其他学院提供1点。每轮生成一枚魔豆，最多7枚。"
	pass_button.disabled = not planning or engine.state.actions.has(active_id) or not active.alive
	auto_button.disabled = not planning
	resolve_button.disabled = not planning or not _all_players_planned()
	restart_button.disabled = busy
	for unit in engine.state.units:
		var states: Array[String] = []
		for status in unit.statuses:
			states.append("%s %s" % [_status_name(str(status.kind)), str(status.value)])
		var state_text := " · ".join(states) if not states.is_empty() else "无状态"
		var queued := " ✓" if engine.state.actions.has(unit.id) else ""
		unit_names[unit.id].text = _name(unit.id)+queued
		unit_stats[unit.id].text = "%d / %d  HP\n\n魔豆 %d · %s" % [unit.hp,unit.max_hp,unit.resources.pips.size(),("就绪" if states.is_empty() else _status_name(str(unit.statuses[0].kind)))]
		unit_health[unit.id].max_value = unit.max_hp
		unit_health[unit.id].value = unit.hp
		units_ui[unit.id].tooltip_text = state_text
		var valid := selected >= 0 and engine.valid_targets(active_id,selected).has(unit)
		units_ui[unit.id].modulate = GOLD if valid or (unit.id == active_id and planning) else Color.WHITE
		plates[unit.id].text = "%s\n%d / %d" % [_name(unit.id),unit.hp,unit.max_hp]
		actors[unit.id].get_node("Body").set_alive(unit.alive)
		_sync_status_art(unit)
		markers[unit.id].visible = unit.alive
		markers[unit.id].scale = Vector3.ONE * (1.2 if valid else 1.0)
	for child in hand.get_children():
		hand.remove_child(child)
		child.queue_free()
	for card in active.deck.hand:
		_card_widget(card,planning,active)
	if finished and not busy:
		result_label.text = ("平局 · 双方势均力敌" if engine.state.winner_team == -1 else ("胜利 · 法阵重归宁静" if engine.state.winner_team == 0 else "战败 · 再试一种策略"))+"\n完成 %d 回合" % engine.state.round_index
		result_panel.show()
	elif not busy:
		hint.text = "点击发光角色选择目标 · Esc 取消" if selected >= 0 else ("小队行动已就绪，点击「开始结算」" if _all_players_planned() else "选牌 → 目标  |  右键换宝藏  |  Q / E 转镜头  |  30轮后按剩余生命比例裁定")

func _select_card(instance_id: int) -> void:
	if busy or engine.state.phase != BattleStateV2.Phase.PLANNING:
		return
	selected = instance_id
	_refresh()

func _pick_unit(id: StringName) -> void:
	if busy or engine.state.phase != BattleStateV2.Phase.PLANNING:
		return
	if selected >= 0:
		if engine.queue_action(ActionIntentV2.cast(active_id,selected,[id])):
			_log("%s 已锁定行动 → %s" % [_name(active_id),_name(id)])
			selected = -1
			_next_player()
	elif engine.state.unit_by_id(id).team == 0:
		active_id = id
	_refresh()

func _next_player() -> void:
	for unit in engine.state.living_units(0):
		if not engine.state.actions.has(unit.id):
			active_id = unit.id
			return

func _all_players_planned() -> bool:
	for unit in engine.state.living_units(0):
		if not engine.state.actions.has(unit.id):
			return false
	return true

func _pass() -> void:
	if busy:
		return
	if engine.queue_pass(active_id):
		selected = -1
		_next_player()
	_refresh()

func _auto_plan() -> void:
	if busy:
		return
	for unit in engine.state.living_units(0):
		if not engine.state.actions.has(unit.id):
			engine.queue_action(session.ai_policy.choose_action(engine,unit))
	selected = -1
	_refresh()

func _resolve() -> void:
	if busy or not _all_players_planned() or engine.state.phase != BattleStateV2.Phase.PLANNING:
		return
	busy = true
	selected = -1
	session.plan_all_with_ai()
	engine.begin_resolution()
	_refresh()
	for actor in engine.turn_manager.resolution_order(engine.state):
		if engine.state.phase == BattleStateV2.Phase.FINISHED:
			break
		if not actor.alive:
			continue
		_process_events(engine.begin_actor_turn(actor))
		_refresh()
		if not actor.alive or engine.state.phase == BattleStateV2.Phase.FINISHED:
			continue
		var intent: ActionIntentV2 = engine.state.actions.get(actor.id)
		if intent != null and not intent.pass_action:
			var card := engine.card_in_hand(actor,intent.card_instance_id)
			if card != null:
				hint.text = "%s 正在施放「%s」" % [_name(actor.id),_card_name(card.definition)]
				_log(hint.text)
				var targets := engine.target_resolver.resolve_selected(engine.state,actor,card.definition,intent.target_ids)
				await theatre.play(actor,card.definition,targets,fast_mode)
		_process_events(engine.resolve_actor_action(actor))
		_refresh()
		await get_tree().create_timer(0.12 if fast_mode else 0.65).timeout
	engine.end_resolution()
	if engine.state.phase != BattleStateV2.Phase.FINISHED:
		var event_start := engine.event_stream.events.size()
		engine.start_next_round()
		_process_events(engine.event_stream.events.slice(event_start))
	busy = false
	_next_player()
	_refresh()

func _process_events(events: Array[BattleEventV2]) -> void:
	for event in events:
		var data := event.payload
		if event.type in [&"DamageResolved",&"HealingResolved",&"HealthSpent"]:
			var id := StringName(str(data.get("target_id",data.get("unit_id",""))))
			var heal := event.type == &"HealingResolved"
			var amount := int(data.get("final_amount",data.get("amount",0)))
			var visual_origin:=str(data.get("origin","spell"))
			if not heal and visual_origin=="spell" and str(data.get("source_id",""))==str(id):visual_origin="self_damage"
			var dot_played: bool=not heal and str(data.get("origin",""))=="dot" and theatre.dot_impact(id,str(data.get("school","")))
			if not dot_played:theatre.impact(id,str(data.get("school","life" if heal else "fire")),heal,visual_origin)
			var school := str(data.get("school", ""))
			var icon_id := &"heal" if heal else StringName("school_%s" % school)
			if event.type == &"HealthSpent": icon_id = &"health_cost"
			elif not heal and school not in preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd").SCHOOLS: icon_id = &"damage"
			_float_text(id,("+" if heal else "−")+str(amount),Color("81f0b1") if heal else Color("ffc591"),icon_id)
			_log("%s %s %d" % [_name(id),"恢复" if heal else "受到伤害",amount])
		elif event.type in [&"SpellMissed",&"ActionFizzled",&"SpellDispelled",&"ActionStunned"]:
			var id := StringName(str(data.get("caster_id",data.get("unit_id",""))))
			_float_text(id,"施法未生效",GOLD)
			_log("%s 施法未生效" % _name(id))

func _float_text(id: StringName, value: String, color: Color, icon_id: StringName = &"", _school_icons: Array[StringName] = []) -> void:
	if not actors.has(id):
		return
	value = preload("res://scripts/fusion_3d/floating_popup_anchor.gd").display_text(value)
	var popup := preload("res://scripts/fusion_3d/floating_popup_anchor.gd").new()
	popup.camera = camera
	popup.position = actors[id].position+Vector3(0,2.9,0)
	add_child(popup)
	var label := Label3D.new()
	label.text = value
	label.font_size = 72
	label.pixel_size = 0.012
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = true
	popup.add_child(label)
	var icon_texture: Texture2D = null
	if icon_id != &"":
		icon_texture = preload("res://scripts/fusion_3d/floating_popup_art.gd").texture(icon_id)
	var icon: Sprite3D
	var popup_icon_width := 0.0
	if icon_texture != null:
		icon = Sprite3D.new()
		icon.texture = icon_texture
		icon.pixel_size = 0.8 / float(icon_texture.get_height())
		icon.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		icon.no_depth_test = true
		icon.modulate = Color(1,1,1,color.a)
		var text_width := ThemeDB.fallback_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x * label.pixel_size
		var icon_width := float(icon_texture.get_width()) * icon.pixel_size
		popup_icon_width = icon_width + 0.1
		var left := -(icon_width + 0.1 + text_width) * 0.5
		icon.position.x = left + icon_width * 0.5
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.position.x = left + icon_width + 0.1
		popup.add_child(icon)
	popup.configure_layout(Vector2(popup_icon_width + ThemeDB.fallback_font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x * label.pixel_size,float(label.font_size) * label.pixel_size))
	var tween := create_tween().set_parallel(true)
	tween.tween_property(popup,"position:y",popup.position.y+1.0,1.1)
	tween.tween_property(label,"modulate:a",0.0,1.1)
	if icon != null: tween.tween_property(icon,"modulate:a",0.0,1.1)
	tween.chain().tween_callback(popup.queue_free)

func _log(message: String) -> void:
	messages.append(message)
	if messages.size() > 3:
		messages.pop_front()
	log_label.text = "\n".join(messages)

func _process(delta: float) -> void:
	elapsed += delta
	if Input.is_physical_key_pressed(KEY_Q):
		orbit -= delta * 0.6
	if Input.is_physical_key_pressed(KEY_E):
		orbit += delta * 0.6
	camera.position = Vector3(sin(orbit)*18.6,17.5,cos(orbit)*18.6)
	camera.fov = 45.0-4.0*cinematic_weight
	camera.look_at(Vector3(0,0,2.1).lerp(cinematic_target,0.38*cinematic_weight))
	for id in actors:
		var body: Node3D = actors[id].get_node("Body")
		body.position.y = sin(elapsed*1.8+float(str(id).unicode_at(1)))*0.035

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and event is InputEventKey and event.keycode == KEY_ESCAPE:
		selected = -1
		_refresh()






func _sync_status_art(unit: BattleUnitStateV2) -> void:
	var signature := str(unit.resources.pips)+str(unit.alive)
	for status in unit.statuses: signature += str(status.instance_id)
	if persistent_fx.get(unit.id,"") == signature: return
	persistent_fx[unit.id] = signature
	var root: Node3D = actors[unit.id]
	var old := root.get_node_or_null("StatusArt")
	if old != null:
		root.remove_child(old)
		old.queue_free()
	var container := Node3D.new()
	container.name = "StatusArt"
	root.add_child(container)
	if not unit.alive: return
	for i in unit.resources.pips.size():
		var angle := float(i)*0.29-0.85
		var color := Color("f6d074") if unit.resources.pips[i] == ResourceStateV2.PipKind.POWER else Color("dfdaf3")
		_orb(container,Vector3(sin(angle)*1.02,0.18,cos(angle)*1.02),0.055,color)
	for i in mini(4,unit.statuses.size()):
		var status: StatusInstanceV2 = unit.statuses[i]
		var id := StringName("world_"+str(status.kind))
		if not ArtRegistryV2.has(id): continue
		var icon := Sprite3D.new()
		icon.texture = ArtRegistryV2.texture(id)
		icon.pixel_size = 0.85/float(icon.texture.get_width())
		icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		icon.position = Vector3(-0.85+float(i)*0.55,1.45,-0.05)
		container.add_child(icon)
		if status.kind == &"shield":
			var bubble := SphereMesh.new()
			bubble.radius = 0.80
			bubble.height = 2.9
			var dome := _mesh(container,bubble,Vector3(0,1.35,0),Color("88bde329"))
			var mat := dome.material_override as StandardMaterial3D
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED





