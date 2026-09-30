extends Node3D
const Motion=preload("res://scripts/fusion_3d/character_motion.gd")
var jump_requested:=false
const Figure = preload("res://scenes/characters/wizard.tscn")
const SCHOOL_IDS := ["fire","ice","storm","myth","life","death","balance"]
const CHARACTER_IDS := [&"fire_student",&"ice_guardian",&"storm_duelist",&"myth_scholar",&"life_healer",&"death_reaper",&"balance_adept"]
const TINTS := [Color("f18150"),Color("94cef1"),Color("b999e8"),Color("e4bd69"),Color("79b883"),Color("9682b6"),Color("d6b787")]
const QUESTS := ["向十字街守望者 Astra 报到", "前往西侧河畔市场，询问 Maribel", "前往东门，与守卫 Sable 交谈", "在东门广场击退裂隙来客", "返回十字街，向 Astra 汇报", "完成：获得星辉学院见习徽章"]
var player: CharacterBody3D
var player_figure: Node3D
var overview:=false
var world_layout: Dictionary
var terrain_world: Node3D
var camera: Camera3D
var view_controller: Node
var citizens: Dictionary = {}
var citizen_labels: Dictionary = {}
var hud: Control
var character_library_panel: Control
var icon_menu: Control
var hint: Label
var quest_label: Label
var zone_label: Label
var quest_indicator: Control
var dialogue: PanelContainer
var dialogue_label: Label
var reply: Button
var wardrobe_panel: Control
var party_panel: PanelContainer
var school_options: Array[OptionButton] = []
var battle: Node3D
var active_dialogue := ""
var quest_step := 0
var persist_progress := true
var party: Array[StringName] = [&"death_reaper",&"ice_guardian",&"life_healer",&"storm_duelist"]
var battle_origin := Vector3(23,0.12,0)
var saved_position := Vector3.ZERO
var network: Node
var shared_battle: Node
var appearance_clock:=0.0
var remote_avatars: Dictionary = {}
var target_position: Vector3
var walk_target := false
var chapter_enabled := true
var account_transition:=false
var chapter: Node
var exploration_music: Node

func _ready() -> void:
	get_node("/root/Wardrobe").save_enabled=persist_progress
	_build_world()
	_build_ui()
	view_controller=preload("res://scripts/fusion_3d/exploration_camera.gd").new()
	add_child(view_controller)
	view_controller.configure(self)
	if "--academy-overview" in OS.get_cmdline_user_args(): overview=true
	_load_progress()
	network = preload("res://scripts/fusion_3d/town_network.gd").new()
	network.name = "TownNetwork"
	add_child(network)
	network.state_changed.connect(func(message: String): hint.text = message)
	shared_battle=preload("res://scripts/fusion_3d/shared_battle.gd").new()
	add_child(shared_battle)
	shared_battle.setup(self)
	ResourceLoader.load_threaded_request("res://scenes/fusion_3d/battle_stage.tscn")
	_update_quest()
	exploration_music = preload("res://scripts/fusion_3d/exploration_music.gd").new()
	add_child(exploration_music)
	if chapter_enabled:
		chapter = preload("res://scripts/fusion_3d/world_one_chapter.gd").new()
		add_child(chapter)
		chapter.configure(self)
	_restore_account_location()
	if persist_progress:
		get_tree().auto_accept_quit=false
		var autosave:=Timer.new()
		autosave.wait_time=30
		autosave.autostart=true
		autosave.timeout.connect(save_account_progress)
		add_child(autosave)

func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	if glow:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = 0.6
	return result
func _box(at: Vector3, dimensions: Vector3, color: Color, solid: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = dimensions
	mesh.mesh = shape
	mesh.material_override = _mat(color)
	mesh.position = at
	add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		var collider := CollisionShape3D.new()
		var volume := BoxShape3D.new()
		volume.size = dimensions
		collider.shape = volume
		body.add_child(collider)
		mesh.add_child(body)
	return mesh
func _cylinder(at: Vector3, radius: float, height: float, color: Color, cone: bool = false) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = 0.02 if cone else radius
	shape.height = height
	shape.radial_segments = 20
	mesh.mesh = shape
	mesh.material_override = _mat(color)
	mesh.position = at
	add_child(mesh)
	return mesh
func _sign(text_value: String, at: Vector3, size_value: int = 40) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.add_to_group("academy_world_labels")
	label.position = at
	label.font_size = size_value
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("f2dbaa")
	add_child(label)
	return label
func _building(at: Vector3, title: String, color: Color) -> void:
	_box(at+Vector3(0,2.4,0),Vector3(6,4.8,5),Color("363646"),true)
	_cylinder(at+Vector3(0,6.0,0),4.5,3.2,color.darkened(0.4),true)
	for x in [-1.6,1.6]:
		var window := _box(at+Vector3(x,2.9,2.52),Vector3(1,1.5,0.06),Color("f2c77d"))
		window.material_override = _mat(Color("dcab65"),true)
	_box(at+Vector3(0,1.25,2.56),Vector3(1.4,2.5,0.1),Color("201c2b"))
	_sign(title,at+Vector3(0,5.0,2.7),34)
func _citizen(id: String, name_value: String, school: int, at: Vector3) -> void:
	var figure: Node3D = preload("res://scripts/fusion_3d/imported_professor.gd").new() if id=="gardener" else Figure.instantiate()
	add_child(figure)
	figure.position = at
	figure.scale=Vector3.ONE*Motion.SIZE_RATIO
	figure.configure(TINTS[school],SCHOOL_IDS[school],false)
	figure.rotation.y = PI
	citizens[id] = figure
	citizen_labels[id] = _sign(name_value,at+Vector3(0,3.35*Motion.SIZE_RATIO,0),28)

func _build_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101827")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a3b6d3")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.ssao_enabled = true
	environment.ssao_radius = 1.5
	environment.ssao_intensity = 1.7
	environment.glow_enabled = true
	environment.glow_intensity = 0.5
	environment.fog_enabled = true
	environment.fog_light_color = Color("acbac7")
	environment.fog_density = 0.0008
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("566e96")
	sky_material.sky_horizon_color = Color("c1ccd0")
	sky_material.ground_horizon_color = Color("b8c6ca")
	sky.sky_material=sky_material
	environment.sky=sky
	environment.background_mode=Environment.BG_SKY
	world.environment = environment
	add_child(world)
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50,-30,0)
	moon.light_color = Color("fff0d4")
	moon.light_energy = 1.35
	moon.shadow_enabled = true
	add_child(moon)
	world_layout=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/academy_world_layout.json"))
	terrain_world=preload("res://scripts/fusion_3d/terraced_academy.gd").new()
	add_child(terrain_world)
	terrain_world.build(self)
	_citizen("keeper","Astra · 星仪城守望者",6,world_point("keeper"))
	_citizen("merchant","Maribel · 学院商人",6,Vector3(78,6,-28))
	_citizen("warden","Sable · 决斗导师",5,Vector3(13,0,14))
	_citizen("prefect","Elowen · 宿舍导师",1,world_point("prefect"))
	battle_origin=layout_vector(world_layout.practice_arena)
	player = CharacterBody3D.new()
	player.position = Vector3(0,0.12,7)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35*Motion.SIZE_RATIO
	capsule.height = 2.4*Motion.SIZE_RATIO
	collision.shape = capsule
	collision.position.y = 1.2*Motion.SIZE_RATIO
	player.add_child(collision)
	add_child(player)
	player_figure = Figure.instantiate()
	player_figure.replacement_model=preload("res://scenes/characters/modular_wizard.tscn")
	player.add_child(player_figure)
	var primary:=CHARACTER_IDS.find(party[0])
	player_figure.configure(TINTS[primary],SCHOOL_IDS[primary],false)
	var player_light := OmniLight3D.new()
	player_light.position = Vector3(0,3,1)
	player_light.light_color = Color("e2dcff")
	player_light.light_energy = 0.7
	player_light.omni_range = 5
	player.add_child(player_light)
	camera = Camera3D.new()
	camera.fov = 48
	camera.near=0.4
	camera.far=650.0
	add_child(camera)
	camera.current = true

func _panel(parent: Node) -> PanelContainer:
	var panel := PanelContainer.new()
	var style = preload("res://scripts/fusion_3d/frontend_theme.gd").panel()
	panel.add_theme_stylebox_override("panel",style)
	parent.add_child(panel)
	return panel
func _label(parent: Node, value: String, font_size: int = 20) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",font_size)
	parent.add_child(label)
	return label
func _button(parent: Node, value: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.focus_mode=Control.FOCUS_NONE
	button.custom_minimum_size.y = 50
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Control.new()
	hud.theme = preload("res://scripts/fusion_3d/frontend_theme.gd").make_theme()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hud)
	var title := _panel(hud)
	title.position = Vector2(26,24)
	var stack := VBoxContainer.new()
	title.add_child(stack)
	_label(stack,"✦ 星辉学院",22).modulate = Color("e9cb91")
	zone_label = _label(stack,"十字街",18)
	quest_label = _label(stack,"",17)
	quest_label.custom_minimum_size.x = 430
	quest_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	icon_menu=preload("res://scripts/fusion_3d/town_icon_menu.gd").new()
	hud.add_child(icon_menu);icon_menu.setup(self)
	hint=Label.new();hint.name="ExplorationHint";hint.text="E 交谈  ·  B 背包  ·  J 调查簿  ·  Ctrl 显示光标"
	hint.add_theme_font_size_override("font_size",18)
	hint.add_theme_color_override("font_shadow_color",Color("07111c"));hint.add_theme_constant_override("shadow_offset_x",2);hint.add_theme_constant_override("shadow_offset_y",2)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);hint.offset_left=28;hint.offset_right=-130;hint.offset_top=-142;hint.offset_bottom=-112;hint.mouse_filter=Control.MOUSE_FILTER_IGNORE;hud.add_child(hint)
	dialogue = _panel(hud)
	dialogue.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	dialogue.offset_left = 24
	dialogue.offset_right = -24
	dialogue.offset_top = -240
	dialogue.offset_bottom = -12
	dialogue.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var conversation := VBoxContainer.new()
	conversation.add_theme_constant_override("separation",18)
	dialogue.add_child(conversation)
	dialogue_label = _label(conversation,"",22)
	dialogue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_label.custom_minimum_size = Vector2(0,100)
	var replies := HBoxContainer.new()
	replies.alignment = BoxContainer.ALIGNMENT_END
	conversation.add_child(replies)
	reply = _button(replies,"继续",advance_dialogue)
	reply.custom_minimum_size.x = 210
	_button(replies,"稍后再来",func(): dialogue.hide()).custom_minimum_size.x = 210
	dialogue.hide()
	dialogue.visibility_changed.connect(func():
		hint.visible = not dialogue.visible
		if is_instance_valid(quest_indicator):quest_indicator.refresh()
		if chapter != null and is_instance_valid(chapter.marker):chapter.marker.visible = not dialogue.visible and battle == null and chapter.step < chapter.steps.size())
	quest_indicator=preload("res://scripts/fusion_3d/quest_indicator.gd").new()
	hud.add_child(quest_indicator);quest_indicator.setup(self)
	party_panel = _panel(hud)
	party_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	party_panel.offset_left = -260
	party_panel.offset_right = 260
	party_panel.offset_top = -230
	party_panel.offset_bottom = 230
	var party_box := VBoxContainer.new()
	party_panel.add_child(party_box)
	_label(party_box,"七大学院 · 四人小队",25)
	_label(party_box,"P1 王冠 · P2 圣杯 · P3 河流 · P4 山峰",16)
	for i in 4:
		var option := OptionButton.new()
		for school in SCHOOL_IDS: option.add_item(Locale.text("SCHOOL_"+school.to_upper()))
		option.select(CHARACTER_IDS.find(party[i]))
		party_box.add_child(option)
		school_options.append(option)
	_button(party_box,"确认编组",func():
		var chosen: Array[StringName] = []
		for option in school_options:
			var character: StringName = CHARACTER_IDS[option.selected]
			if chosen.has(character):
				hint.text = "每名角色只能占一个站位，请选择四名不同队友。"
				return
			chosen.append(character)
		party = chosen
		player_figure.configure(TINTS[school_options[0].selected],SCHOOL_IDS[school_options[0].selected],false)
		party_panel.hide()
		if chapter != null: chapter.party_confirmed()
		_save_progress())
	_button(party_box,"关闭",func(): party_panel.hide())
	party_panel.hide()
	wardrobe_panel=preload("res://scripts/fusion_3d/wardrobe_panel.gd").new()
	hud.add_child(wardrobe_panel)
	wardrobe_panel.hide()

func toggle_wardrobe() -> void:
	if icon_menu!=null:icon_menu.close()
	if battle!=null or dialogue.visible or party_panel.visible:return
	if wardrobe_panel.visible:
		wardrobe_panel.hide()
	else:
		view_controller.set_capture(false)
		wardrobe_panel.open_for(SCHOOL_IDS[school_options[0].selected])

func can_move_player() -> bool:
	var focus:=get_viewport().gui_get_focus_owner()
	return battle==null and not (is_instance_valid(character_library_panel) and character_library_panel.visible) and (icon_menu==null or not icon_menu.is_open()) and (chapter==null or chapter.journal==null or not chapter.journal.visible) and (shared_battle==null or not shared_battle.pending.has(multiplayer.get_unique_id())) and not dialogue.visible and not party_panel.visible and not wardrobe_panel.visible and not overview and not (focus is LineEdit or focus is TextEdit)
func request_jump() -> bool:
	if not can_move_player() or not player.is_on_floor():return false
	jump_requested=true
	return true
func _physics_process(delta: float) -> void:
	if player == null:return
	if battle == null:
		var direction:=Vector3.ZERO
		if can_move_player():
			direction=Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
			direction=view_controller.movement_direction(direction)
			if direction.length_squared()>0:
				direction=direction.normalized()
				player_figure.rotation.y=atan2(-direction.x,-direction.z)
			if jump_requested and player.is_on_floor():player.velocity.y=Motion.JUMP_SPEED
		player.velocity.x=direction.x*Motion.MOVE_SPEED
		player.velocity.z=direction.z*Motion.MOVE_SPEED
		player.velocity.y-=Motion.GRAVITY*delta
		player.move_and_slide()
		var actual_velocity:=player.get_real_velocity()
		player_figure.external.set_locomotion(not player.is_on_floor(),player.velocity.y,Vector2(actual_velocity.x,actual_velocity.z).length())
		if player.position.y< -42:
			player.position=chapter.checkpoint if chapter!=null else Vector3(0,0.12,9)
			player.velocity=Vector3.ZERO
	jump_requested=false
	if battle == null:
		view_controller.update_camera(delta)
		zone_label.text = region_at(player.position).name
	if battle == null and exploration_music != null:
		exploration_music.set_region("garden" if region_at(player.position).id=="life" else "town")
	if network != null:
		network.local_position = player.position
		network.local_yaw=player_figure.rotation.y
		appearance_clock+=delta
		if appearance_clock>0.4 or network.local_appearance.is_empty():
			appearance_clock=0
			var outfits: Dictionary={}
			for school in SCHOOL_IDS:outfits[school]=get_node("/root/Wardrobe").outfit(school)
			network.local_appearance={"school":player_figure.external.school_id,"outfits":outfits}
		_sync_peers(delta)
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_B:
			toggle_wardrobe()
			get_viewport().set_input_as_handled()
		elif event.keycode==KEY_ESCAPE and wardrobe_panel.visible:
			wardrobe_panel.hide()
			get_viewport().set_input_as_handled()
		elif event.keycode==KEY_SPACE or event.physical_keycode==KEY_SPACE:
			if request_jump():get_viewport().set_input_as_handled()
		elif event.keycode==KEY_E:interact()
func interact() -> void:
	if battle != null or party_panel.visible or wardrobe_panel.visible: return
	if dialogue.visible:
		advance_dialogue()
		return
	if chapter != null and chapter.interact(): return
	var nearest := ""
	var distance := 3.5
	for id in citizens:
		var candidate := player.position.distance_to(citizens[id].position)
		if candidate < distance:
			distance = candidate
			nearest = id
	if nearest.is_empty():
		hint.text = "靠近 NPC 后按 E。Astra 在出生点左前方。"
		return
	open_dialogue(nearest)
func open_dialogue(id: String) -> void:
	if chapter != null and id in ["keeper","prefect","gardener"]:
		chapter.open(id)
		return
	active_dialogue = id
	reply.text = "继续"
	match id:
		"keeper": dialogue_label.text = "Astra：十字街的结界联通着学院、市场和宿舍。东门的符文最近开始闪烁。请先去河畔市场向 Maribel 打听材料运输的异常。" if quest_step < 4 else "Astra：你稳定了东门法阵。这枚星辉见习徽章属于你，学院的七系课程也向你开放。"
		"merchant": dialogue_label.text = "Maribel：河上的货船带来了法术材料，也带来了裂隙的消息。去东门找 Sable，留意那些逆向旋转的符文。"
		"warden":
			dialogue_label.text = "Sable：裂隙来客就在这片广场。召集四名队友，利用刀刃、护盾和学院豆，在原地法阵中击退它们。"
			reply.text = "展开 4v4 成果展示"
		"prefect": dialogue_label.text = "Elowen：月钟过后保持安静。宿舍是安全区；编组面板可选择七大学院的伙伴，进入战斗后通过 DECK 配置卡组。"
	dialogue.show()
func advance_dialogue() -> void:
	if not dialogue.visible: return
	if active_dialogue == "chapter" and chapter != null:
		chapter.advance()
		return
	dialogue.hide()
	if active_dialogue == "keeper":
		if quest_step == 0: quest_step = 1
		elif quest_step == 4: quest_step = 5
	elif active_dialogue == "merchant" and quest_step == 1: quest_step = 2
	elif active_dialogue == "warden":
		if quest_step == 2: quest_step = 3
		battle_origin = layout_vector(world_layout.practice_arena)
		begin_battle()
	_update_quest()
	_save_progress()
func begin_battle() -> void:
	if icon_menu!=null:icon_menu.close()
	if network!=null and network.connected and (chapter==null or not chapter.encounter_active):
		shared_battle.start()
		return
	if battle != null: return
	wardrobe_panel.hide()
	view_controller.set_capture(false)
	if exploration_music != null: exploration_music.set_battle(true)
	saved_position = player.position
	player.hide()
	for label in get_tree().get_nodes_in_group("academy_world_labels"): label.hide()
	for creature in get_tree().get_nodes_in_group("garden_familiars"): creature.hide()
	for id in citizens:
		if citizens[id].position.distance_to(battle_origin) < 14.0:
			citizens[id].hide()
			citizen_labels[id].hide()
	hud.hide()
	battle = load("res://scenes/fusion_3d/battle_stage.tscn").instantiate()
	battle.embedded = true
	battle.party = party.duplicate()
	if chapter != null and chapter.encounter_active: battle.encounter_id = chapter.active_encounter_id
	if chapter != null: battle.campaign_level = chapter.level()
	battle.position = battle_origin
	battle.entry_origin = player.position-battle_origin
	battle.encounter_finished.connect(finish_battle)
	add_child(battle)
func finish_battle(winner: int) -> void:
	if battle == null: return
	battle.queue_free()
	battle = null
	player.position = saved_position
	player.show()
	for label in get_tree().get_nodes_in_group("academy_world_labels"): label.show()
	for creature in get_tree().get_nodes_in_group("garden_familiars"): creature.show()
	for id in citizens:
		citizens[id].show()
		citizen_labels[id].show()
	camera.current = true
	hud.show()
	if exploration_music != null: exploration_music.set_battle(false)
	if winner == 0 and quest_step == 3: quest_step = 4
	hint.text = "东门恢复平静，返回 Astra 处交付任务。" if winner == 0 else "队伍返回广场。调整卡组后可再向守卫发起挑战。"
	_update_quest()
	_save_progress()
	if chapter != null: chapter.battle_finished(winner)
func _update_quest() -> void:
	quest_label.text = "任务 · "+QUESTS[quest_step]
func _save_progress() -> void:
	if not persist_progress: return
	var at: Vector3=saved_position if battle!=null else player.position
	Accounts.write_save("fusion_3d_story.json",{"quest_step":quest_step,"party":party,"position":[at.x,at.y,at.z],"camera_yaw":view_controller.yaw})
func _load_progress() -> void:
	if not persist_progress or not FileAccess.file_exists(Accounts.path_for("fusion_3d_story.json")): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(Accounts.path_for("fusion_3d_story.json")))
	if data is Dictionary:
		quest_step = clampi(int(data.get("quest_step",0)),0,5)
		var chosen: Array[StringName] = []
		for id in data.get("party",[]):
			if CHARACTER_IDS.has(StringName(id)) and not chosen.has(StringName(id)): chosen.append(StringName(id))
		if chosen.size() == 4: party = chosen
		for i in 4: school_options[i].select(CHARACTER_IDS.find(party[i]))
		var primary := CHARACTER_IDS.find(party[0])
		player_figure.configure(TINTS[primary],SCHOOL_IDS[primary],false)
func _sync_peers(delta: float) -> void:
	for id in remote_avatars.keys():
		if not network.positions.has(id):
			remote_avatars[id].queue_free()
			remote_avatars.erase(id)
	for id in network.positions:
		if id==multiplayer.get_unique_id():continue
		var profile: Dictionary=network.appearances.get(id,{"school":"fire"})
		var school:=str(profile.get("school","fire"))
		var outfit: Dictionary=profile.get("outfits",{}).get(school,get_node("/root/Wardrobe").default_outfit(school))
		if not remote_avatars.has(id):
			var figure: Node3D=load("res://scenes/characters/modular_wizard.tscn").instantiate()
			figure.follow_local_wardrobe=false
			add_child(figure)
			figure.configure(Color.WHITE,school,true)
			figure.position=network.positions[id]
			remote_avatars[id]=figure
		var figure: Node3D=remote_avatars[id]
		if figure.equipped!=outfit or figure.school_id!=school:
			figure.school_id=school
			figure.apply_outfit(outfit)
		figure.position=figure.position.lerp(network.positions[id],minf(1,delta*12))
		figure.rotation.y=lerp_angle(figure.rotation.y,float(network.rotations.get(id,0)),minf(1,delta*12))
		figure.visible=not (shared_battle!=null and is_instance_valid(shared_battle.stage) and (shared_battle.members.has(id) or shared_battle.pending.has(id)))

func layout_vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])
func world_point(id: String) -> Vector3:
	return layout_vector(world_layout.points[id])
func region_at(at: Vector3) -> Dictionary:
	if chapter != null and chapter.world != null:
		var expanded: Dictionary=chapter.world.region(at)
		if not expanded.is_empty():return expanded
	var result: Dictionary=world_layout.regions[0]
	var nearest:=INF
	for region in world_layout.regions:
		var center:=layout_vector(region.center)
		var distance:=Vector2(center.x-at.x,center.z-at.z).length()
		if distance<nearest:
			nearest=distance
			result=region
	return result

func save_account_progress() -> void:
	if not persist_progress:return
	Accounts.local_write_failed=false
	_save_progress()
	if chapter!=null:chapter.save()
	get_node("/root/Wardrobe").save()
	if Accounts.local_write_failed:
		hint.text="本地存档写入失败，请检查磁盘空间。"
		return
	var result: Dictionary=await Accounts.sync_save()
	if is_instance_valid(hint):hint.text="进度已保存" if result.ok else str(result.error)
func return_to_accounts() -> void:
	if account_transition:return
	if battle!=null:
		hint.text="请先结束当前战斗。"
		return
	account_transition=true
	await save_account_progress()
	view_controller.set_capture(false)
	if network!=null:network.disconnect_town()
	Accounts.leave_character()
	get_tree().change_scene_to_file("res://scenes/fusion_3d/account_menu.tscn")

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_CLOSE_REQUEST and persist_progress and not account_transition:
		account_transition=true
		await save_account_progress()
		get_tree().quit()

func _restore_account_location() -> void:
	if not persist_progress or Accounts.active_character.is_empty():return
	var path: String=Accounts.path_for("fusion_3d_story.json")
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
	if not data is Dictionary:return
	var coordinates: Variant=data.get("position",[])
	if coordinates is Array and coordinates.size()==3:
		if coordinates.all(func(v: Variant):return (v is float or v is int) and is_finite(float(v)) and absf(float(v))<5000):
			player.position=Vector3(float(coordinates[0]),float(coordinates[1]),float(coordinates[2]))
	var yaw_value: Variant=data.get("camera_yaw",0.0)
	if (yaw_value is float or yaw_value is int) and is_finite(float(yaw_value)):view_controller.yaw=float(yaw_value)
	if player.has_node("PlayerName"):return
	var nameplate:=Label3D.new()
	nameplate.name="PlayerName"
	nameplate.text=str(Accounts.active_character.name)
	nameplate.font_size=32
	nameplate.pixel_size=.008
	nameplate.position.y=2.55
	nameplate.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	player.add_child(nameplate)


func open_character_library() -> void:
	if not is_instance_valid(character_library_panel):
		character_library_panel=preload("res://scripts/fusion_3d/character_library_view.gd").new()
		hud.add_child(character_library_panel)
	character_library_panel.show()
	view_controller.set_capture(false)
