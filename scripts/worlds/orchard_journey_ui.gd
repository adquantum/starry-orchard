extends Node
const Rules = preload("res://scripts/worlds/orchard_journey_rules.gd")
var atlas: Node
var world: Node3D
var state: Dictionary = {}
var layer: CanvasLayer
var dialog: PanelContainer
var prompt: Button
var status: Label
var status_until := 0
var skip: Button
var next_button: Button
var marker: Label3D
var glow: OmniLight3D
var pending := false
var pending_since := 0
var page := 0
var action := ""
var anchor := Vector3.ZERO
var crystal_materials: Array[StandardMaterial3D] = []

func setup(owner_atlas: Node) -> void:
	atlas = owner_atlas;world = atlas.world
	layer = CanvasLayer.new();layer.layer = 36;add_child(layer)
	dialog = preload("res://scripts/fusion_3d/npc_dialogue_panel.gd").new()
	layer.add_child(dialog)
	next_button = dialog.add_action("下一页", _next)
	dialog.add_action("暂不出发", func():dialog.hide())
	dialog.hide()
	prompt = Button.new();prompt.hide();prompt.text = "[E] 交互"
	layer.add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left=-200;prompt.offset_right=200;prompt.offset_top=-125;prompt.offset_bottom=-75
	prompt.pressed.connect(_open)
	status = Label.new();status.hide();status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	status.offset_left=-430;status.offset_right=430;status.offset_top=-175;status.offset_bottom=-130
	status.add_theme_font_size_override("font_size", 22)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 6)
	skip = Button.new();skip.text = "跳过新手教程 · 直接前往寒冰岛";skip.hide()
	layer.add_child(skip)
	skip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	skip.position = Vector2(24, 195);skip.pressed.connect(func():_send("skip"))
	if bool(world.get_meta("tutorial_instance", false)):
		action = "crystal";anchor = Rules.CRYSTAL
		_find_crystal(world.windchime_garden)
		glow = OmniLight3D.new();glow.omni_range=24.0;glow.light_color=Color("80ddff");glow.light_energy=0.0
		world.add_child(glow);glow.position=anchor+Vector3.UP*5.0
	elif atlas.orchard_main_mode:
		action = "return";anchor = Rules.MAIN_ENTRY
	elif "frostroarisland_teen" in str(atlas.MAPS[atlas.current_map][1]):
		action = "ship";anchor = Rules.SHIP
	if not action.is_empty():
		marker = Label3D.new();marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		marker.font_size=42;marker.pixel_size=0.04;marker.no_depth_test=false
		world.add_child(marker);marker.position=anchor+Vector3.UP*(14.0 if action=="ship" else 7.0)
	set_state(atlas.journey_state)

func _find_crystal(node: Node) -> void:
	if not is_instance_valid(node):return
	if node is MeshInstance3D and str(node.name).begins_with("Crystal_blue"):
		var center: Vector3 = node.global_transform * node.get_aabb().get_center()
		if center.distance_to(Rules.CRYSTAL+Vector3.UP*4.84) < 2.0:
			for slot in node.mesh.get_surface_count():
				var original: Material = node.get_active_material(slot)
				if original is StandardMaterial3D:
					var material: StandardMaterial3D = original.duplicate()
					node.set_surface_override_material(slot, material)
					crystal_materials.append(material)
	for child in node.get_children():_find_crystal(child)

func set_state(value: Dictionary) -> void:
	state = value.duplicate(true)
	var unlocked := bool(state.get("admitted", false))
	if is_instance_valid(glow):glow.light_energy=3.0 if unlocked else 0.0
	for material in crystal_materials:
		material.emission_enabled=unlocked;material.emission=Color("7adfff");material.emission_energy_multiplier=1.2 if unlocked else 0.0
	if is_instance_valid(marker):
		marker.text = ("山顶大水晶 · 寒冰岛航路" if unlocked else "沉睡的大水晶 · 完成西岛五课后开启") if action=="crystal" else ("星界果园航船 · T4 毕业后挑战" if action=="ship" else "返回寒冰岛")

func _process(_delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player):return
	if pending and Time.get_ticks_msec()-pending_since>12000:
		pending=false;show_status("服务器未确认传送，请重新连接后重试。")
	status.visible=pending or Time.get_ticks_msec()<status_until
	var busy: bool = atlas.busy or atlas.encounters.active or world.input_suspended or is_open()
	var online: bool = atlas.encounters.session.net.authenticated
	var unlocked := action!="crystal" or bool(state.get("admitted", false))
	prompt.visible=not busy and not pending and online and unlocked and not action.is_empty() and Rules.near(world.player.position,anchor,18.0 if action=="ship" else 16.0)
	prompt.text="[E] 与山顶水晶交互" if action=="crystal" else ("[E] 前往星界果园主世界" if action=="ship" else "[E] 返回寒冰岛")
	skip.visible=bool(world.get_meta("tutorial_instance",false)) and bool(state.get("can_skip",false)) and not busy and not pending and online

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_ESCAPE and is_open():dialog.hide();get_viewport().set_input_as_handled()
	elif event.keycode==KEY_E and prompt.visible:
		_open();get_viewport().set_input_as_handled()

func _open() -> void:
	page=0
	dialog.heading.text="星界果园 · 新的航程" if action=="crystal" else "星界果园航船"
	if action=="crystal":
		dialog.body.text="感谢你对星界果园的支持，目前后续剧情还在开发中，你可以前往寒冰岛进行游玩。"
		next_button.text="下一页 · 寒冰岛玩法"
	else:
		dialog.body.text="前往星界果园主世界，与其他玩家一起游览海港、山地和天空城。各区域有高难度游荡野怪，建议完成 T4 毕业装备后组队挑战。请沿道路游览，靠近野怪会进入战斗。\n\n目前开放游览与挑战，后续剧情仍在开发。" if action=="ship" else "返回寒冰岛，继续营地挑战、装备兑换与 PvP 对战。"
		next_button.text="启程"
	dialog.show();_layout_dialog();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func _next() -> void:
	if action=="crystal" and page==0:
		page=1;dialog.heading.text="寒冰岛 · 联机玩法"
		dialog.body.text="营地挑战：从港口营地开始，与附近玩家一起战斗，收集赋能并兑换宝藏卡与属性装备，逐步挑战更强的敌人。\n\n翅膀 Boss：挑战风翼鹰与后续翼 Boss，解锁翅膀，探索更远的区域。\n\nPvP 法阵：前往对战法阵，与其他玩家展开队伍对战，检验你的卡组与配合。\n\n主世界游览：寒冰岛船上可前往星界果园主世界。那里的游荡怪面向 T4 毕业后的挑战。"
		next_button.text="前往寒冰岛 · 联机游玩"
		_layout_dialog()
	else:
		dialog.hide();_send(action)

func _send(request_action: String) -> void:
	if pending or atlas.busy or atlas.encounters.active:return
	pending=true;pending_since=Time.get_ticks_msec()
	show_status("正在确认航线，请稍候……")
	atlas.encounters.session.net.send_request({"op":"journey", "action":request_action})

func show_status(message: String) -> void:
	status.text=message;status_until=Time.get_ticks_msec()+8000;status.show()

func is_open() -> bool:
	return is_instance_valid(dialog) and dialog.visible

func _layout_dialog() -> void:
	dialog.layout_dialogue()
	dialog.size.y = 570.0 if action == "crystal" and page == 1 else 360.0
	dialog.position.y = dialog.get_viewport_rect().size.y - dialog.size.y * dialog.scale.y - 24.0
