extends Node3D
@export_dir var world_root: String = "res://assets/worlds/haqi_town/"
@export_file("*.json") var water_config_path: String = "res://resources/fusion_3d/haqi_water.json"
@export var world_title: String = "哈奇小镇"
@export_dir var capture_root: String = "res://docs/haqi_town/"
@export_file("*.mp3") var exploration_music_path: String = ""
@export var exploration_music_volume_db_offset := 0.0
@export var explorer_scale: float = 2.0
@export var fall_reset_height: float = -100.0
var flight:Node
var production_mode := false
var input_suspended := false
var exploration_context: Node
var mobile_input: Node
var camera_input: Node
var use_session_appearance := false
var session_school := "life"
var capsule_node: CollisionShape3D
var data: Dictionary
var player: CharacterBody3D
var avatar: Node3D
var camera: Camera3D
var yaw:=0.0
var pitch:=-0.4
var distance:=9.0
var water_config: Dictionary
var swimming:=false
var water_jump_cooldown:=0.0
var ready_world:=false
var friend_groups: Array=[]
var friend_group_tick:=0.0
var loading_progress:=0.0
var heights: Dictionary={}
var label: Label
var terrain_size:=533.333313
var origin:=Vector2.ZERO
var prototypes: Dictionary={}
var collision_pool: Array=[]
var collision_nodes: Dictionary={}
var collider_tick:=0.0
var spawn:=Vector3(425,80,1050)
var destinations=[Vector3(425,80,1050),Vector3(0,40,0),Vector3(400,50,400)]
var destination_names=["五学院广场","城镇腹地","城郊道路"]
var tour_index:=0
func _ready() -> void:
	_setup_view()
	camera_input = preload("res://scripts/worlds/exploration_camera_input.gd").new()
	add_child(camera_input)
	camera_input.setup(self)
	_load_world.call_deferred()
func _setup_view() -> void:
	var env:=WorldEnvironment.new()
	env.environment=Environment.new()
	env.environment.background_mode=Environment.BG_COLOR
	env.environment.background_color=Color("a6c9dd")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color("c9d9e6")
	env.environment.ambient_light_energy=0.72
	env.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.light_color=Color("fff0d4");sun.light_energy=0.8;sun.shadow_enabled=true;sun.directional_shadow_max_distance=120;add_child(sun)
	camera=Camera3D.new();camera.far=2800;camera.current=true;add_child(camera)
	var ui:=CanvasLayer.new();add_child(ui)
	var panel:=PanelContainer.new();panel.position=Vector2(22,20);ui.add_child(panel);panel.visible=not production_mode
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.035,0.065,0.1,0.91);style.border_color=Color("a68c56");style.set_border_width_all(1);style.content_margin_left=18;style.content_margin_right=18;style.content_margin_top=12;style.content_margin_bottom=12;panel.add_theme_stylebox_override("panel",style)
	label=Label.new();label.add_theme_font_size_override("font_size",18);label.text=world_title+" · 原世界探索\n正在载入原始地形与建筑…";panel.add_child(label)
func _world_document() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(world_root.path_join("world.json")))

func _load_world() -> void:
	data=_world_document();terrain_size=float(data.tile_size);origin=Vector2(data.origin[0],data.origin[1])
	for entry in data.terrain:
		_build_terrain(entry)
		loading_progress+=30.0/maxi(1,data.terrain.size())
		await get_tree().process_frame
	_build_water()
	var groups: Dictionary={}
	var done:=0
	for path in data.models.values():
		var instance: Node3D=load(path).instantiate()
		var parts: Array=[]
		_collect_meshes(instance,Transform3D.IDENTITY,parts)
		prototypes[path]=parts;instance.free()
		done+=1
		loading_progress=30.0+40.0*done/maxi(1,data.models.size())
		if done%12==0:
			label.text=world_title+" · 原世界探索\n正在整理建筑与植被 %d / %d"%[done,data.models.size()]
			await get_tree().process_frame
	var placement_index := -1
	for p in data.placements:
		placement_index += 1
		if p.model.is_empty():continue
		var m: Array=p.matrix
		var tr:=Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[3],m[4],m[5]),Vector3(m[6],m[7],m[8])),Vector3(p.position[0]+m[9],p.position[1]+m[10],p.position[2]+m[11]))
		if absf(tr.basis.determinant())<0.00001:continue
		var region:=Vector2i(floori(tr.origin.x/100),floori(tr.origin.z/100))
		var key:=str(p.model)+"|"+str(region)
		if not groups.has(key):groups[key]={"path":p.model,"transforms":[],"placement_ids":[]}
		groups[key].transforms.append(tr)
		groups[key].placement_ids.append(placement_index)
		if p.solid:collision_pool.append({"path":p.model,"transform":tr})
	if GraphicsSettings.is_low():
		friend_groups.clear()
		for g in groups.values():
			var first:=true
			var bounds:=AABB()
			for transform in g.transforms:
				for part in prototypes[g.path]:
					var box: AABB=(transform*part.transform)*part.mesh.get_aabb()
					bounds=box if first else bounds.merge(box);first=false
			g["friend_bounds"]=bounds;g["friend_nodes"]=[]
			friend_groups.append(g)
		_friend_update_groups(destinations[tour_index],0)
	else:
		for g in groups.values():
			for part in prototypes[g.path]:
				var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=part.mesh;mm.instance_count=g.transforms.size()
				for i in g.transforms.size():mm.set_instance_transform(i,g.transforms[i]*part.transform)
				var node:=MultiMeshInstance3D.new();node.multimesh=mm;node.visibility_range_end=1100;node.visibility_range_end_margin=100
				_configure_visual_group(node,g,part)
				add_child(node)
	loading_progress=80.0
	await get_tree().process_frame
	player=CharacterBody3D.new();player.name="Explorer";player.floor_snap_length=0.7;player.floor_max_angle=deg_to_rad(52);add_child(player)
	var capsule:=CollisionShape3D.new();var shape:=CapsuleShape3D.new();shape.radius=0.4;shape.height=1.9;capsule.shape=shape;capsule.position.y=0.95;player.add_child(capsule);capsule_node=capsule
	var school:=_load_formal_appearance()
	avatar=preload("res://scenes/characters/modular_wizard.tscn").instantiate()
	player.add_child(avatar)
	avatar.configure(Color.WHITE,school,false)
	avatar.set_battle_mode(false)
	flight=preload("res://scripts/worlds/wing_flight.gd").new();flight.world=self;add_child(flight);flight.equip(flight.equipped_id)
	apply_explorer_scale(explorer_scale)
	distance=minf(distance,9.0)
	print("HAQI_FORMAL_AVATAR school=",school," style=",avatar.equipped.get("model_style")," gender=",avatar.equipped.get("gender"))
	_reset_player()
	var music=load("res://scripts/fusion_3d/exploration_music.gd").new()
	if production_mode:music.in_battle=true # Atlas releases music after all loading and warmup finish.
	if not exploration_music_path.is_empty(): music.town_track_override=exploration_music_path
	music.town_volume_db_offset=exploration_music_volume_db_offset
	add_child(music)
	ready_world=true
	_refresh_collisions()
	print("HAQI_WORLD_READY terrains=",data.terrain.size()," instances=",data.placements.size()," models=",prototypes.size())
	if "--haqi-water-test" in OS.get_cmdline_user_args():
		tour_index=destinations.size()-1;_reset_player();_refresh_collisions()
		await get_tree().create_timer(2).timeout
		assert(swimming)
		assert(str(avatar.teen.player.current_animation).ends_with("base_041"))
		var key:=InputEventKey.new();key.physical_keycode=KEY_D;key.pressed=true;Input.parse_input_event(key)
		await get_tree().create_timer(0.3).timeout
		assert(str(avatar.teen.player.current_animation).ends_with("base_042"))
		get_viewport().get_texture().get_image().save_png(capture_root.path_join("swimming.png"))
		key.pressed=false;Input.parse_input_event(key)
		tour_index=0;_reset_player();_refresh_collisions()
		await get_tree().create_timer(1).timeout
		assert(not swimming and not avatar.teen.swimming)
		print("HAQI_WATER_TEST_OK sea_level=",water_config.sea_level," idle/swim/land")
		get_tree().quit()
	if "--haqi-validate" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1).timeout
		assert(avatar.equipped==get_node("/root/Wardrobe").outfit(avatar.school_id))
		assert(avatar.teen!=null)
		var start_position:=player.position
		var key:=InputEventKey.new();key.physical_keycode=KEY_D;key.pressed=true;Input.parse_input_event(key)
		await get_tree().create_timer(0.3).timeout
		key.pressed=false;Input.parse_input_event(key)
		assert(player.position.distance_to(start_position)>0.2)
		await get_tree().create_timer(0.3).timeout
		var floor_y:=player.position.y
		key=InputEventKey.new();key.physical_keycode=KEY_SPACE;key.pressed=true;Input.parse_input_event(key)
		await get_tree().create_timer(0.2).timeout
		key.pressed=false;Input.parse_input_event(key)
		assert(player.position.y>floor_y+0.1)
		await get_tree().create_timer(1).timeout
		assert(player.is_on_floor())
		print("HAQI_AVATAR_GROUND_TEST_OK appearance movement jump landing")
		get_tree().quit()
	if "--haqi-capture" in OS.get_cmdline_user_args():
		await get_tree().create_timer(3).timeout
		get_viewport().get_texture().get_image().save_png(capture_root.path_join("exploration.png"))
		camera.position=player.position+Vector3(110,125,120);camera.look_at(player.position+Vector3(0,0,0));set_physics_process(false)
		await get_tree().create_timer(1).timeout
		get_viewport().get_texture().get_image().save_png(capture_root.path_join("overview.png"))
		get_tree().quit()
func _collect_meshes(node: Node, tr: Transform3D, parts: Array) -> void:
	if node is Node3D:tr=tr*node.transform
	if node is MeshInstance3D and node.mesh!=null:
		parts.append({"mesh":node.mesh,"transform":tr})
	for child in node.get_children():_collect_meshes(child,tr,parts)
func _build_terrain(t: Dictionary) -> void:
	# Per-source repaints baked with the original terrain masks, limited to opted-in worlds.
	var painted_path := world_root.path_join("terrain_paint_layers_v1/ground_%d_%d.png"%[int(t.tile[0]),int(t.tile[1])])
	if not "--terrain-layer-repaint-off" in OS.get_cmdline_user_args() and ResourceLoader.exists(painted_path):
		t=t.duplicate()
		t["ground_texture"]=painted_path
	var h:=FileAccess.get_file_as_bytes(t.height).to_float32_array()
	var tile:=Vector2i(t.tile[0],t.tile[1]);heights[tile]=h
	var verts:=PackedVector3Array();var normals:=PackedVector3Array();var uv:=PackedVector2Array();var indices:=PackedInt32Array()
	for z in 129:
		for x in 129:
			verts.append(Vector3(x*terrain_size/128,h[z*129+x],z*terrain_size/128))
			var dx:=h[z*129+mini(x+1,128)]-h[z*129+maxi(x-1,0)]
			var dz:=h[mini(z+1,128)*129+x]-h[maxi(z-1,0)*129+x]
			normals.append(Vector3(-dx,2*terrain_size/128,-dz).normalized());uv.append(Vector2(x,z)/128.0 if t.has("ground_texture") else Vector2(x,z)*0.4)
	for z in 128:
		for x in 128:
			var a:=z*129+x;indices.append_array(PackedInt32Array([a,a+1,a+129,a+1,a+130,a+129]))
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=verts;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv;arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=StandardMaterial3D.new();material.roughness=1.0
	if t.has("ground_texture"):
		material.albedo_texture=load(t.ground_texture)
		# Baked tiles cover UV 0..1 once; wrapping blends in the opposite edge.
		material.texture_repeat=false
	elif not t.get("texture","").is_empty():material.albedo_texture=load(t.texture)
	else:material.albedo_color=Color("74905d")
	mesh.surface_set_material(0,material)
	var node:=MeshInstance3D.new();node.mesh=mesh;node.position=Vector3(tile.x*terrain_size-origin.x,0,tile.y*terrain_size-origin.y);add_child(node)
	node.set_meta("creator_terrain_tile",tile)
	var body:=StaticBody3D.new();node.add_child(body);var collision:=CollisionShape3D.new();collision.shape=mesh.create_trimesh_shape();body.add_child(collision)
func _height(at: Vector3) -> float:
	if is_instance_valid(exploration_context) and exploration_context.inside:
		return exploration_context.floor_height(at)
	var x: float=at.x+origin.x;var z: float=at.z+origin.y;var tile:=Vector2i(floori(x/terrain_size),floori(z/terrain_size))
	if not heights.has(tile):return -999.0
	var h: PackedFloat32Array=heights[tile];var u:=clampf((x/terrain_size-tile.x)*128,0,128);var v:=clampf((z/terrain_size-tile.y)*128,0,128)
	var ix:=mini(int(u),127);var iz:=mini(int(v),127)
	return lerpf(lerpf(h[iz*129+ix],h[iz*129+ix+1],u-ix),lerpf(h[(iz+1)*129+ix],h[(iz+1)*129+ix+1],u-ix),v-iz)
func _reset_player() -> void:
	if is_instance_valid(exploration_context) and exploration_context.inside:
		exploration_context.reset_to_safe()
		return
	if flight!=null:flight.land()
	player.position=destinations[tour_index];player.position.y=_height(player.position)+maxf(3.0,explorer_scale*2.0);player.velocity=Vector3.ZERO
func _refresh_collisions() -> void:
	if is_instance_valid(exploration_context) and exploration_context.inside:return
	for i in collision_pool.size():
		var p: Dictionary=collision_pool[i]
		if not p.has("bounds"):
			var bounds := AABB()
			var first := true
			for part in prototypes[p.path]:
				var transformed: AABB = (p.transform * part.transform) * part.mesh.get_aabb()
				bounds = transformed if first else bounds.merge(transformed)
				first = false
			p.bounds = bounds
		var near: bool = p.bounds.grow(150.0).has_point(player.position)
		if near and not collision_nodes.has(i):
			var body:=StaticBody3D.new();body.transform=p.transform
			for part in prototypes[p.path]:
				if not part.has("shape"):part.shape=part.mesh.create_trimesh_shape()
				var node:=CollisionShape3D.new();node.shape=part.shape;node.transform=part.transform;body.add_child(node)
			add_child(body);collision_nodes[i]=body
		elif not near and collision_nodes.has(i):collision_nodes[i].queue_free();collision_nodes.erase(i)
func _unhandled_input(event: InputEvent) -> void:
	if input_suspended:return
	if camera_input != null:camera_input.handle_event(event)
	if is_instance_valid(exploration_context) and exploration_context.inside:
		if event is InputEventKey and event.keycode == KEY_SPACE:return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_SPACE and ready_world:flight.space_pressed()
		if event.keycode==KEY_R and ready_world:_reset_player()
		if event.keycode==KEY_TAB and ready_world and not production_mode:tour_index=(tour_index+1)%destinations.size();_reset_player()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT and ready_world:flight.flap()
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(3,distance-1)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(35,distance+1)
func mobile_jump_action() -> void:
	if ready_world and flight!=null:flight.space_pressed()
func mobile_boost_action() -> void:
	if ready_world and flight!=null and flight.flying:flight.flap()
func _movement_axis() -> Vector2:
	var keyboard:=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))).normalized()
	if is_instance_valid(mobile_input) and mobile_input.move_vector.length()>keyboard.length():return mobile_input.move_vector
	return keyboard
func _jump_is_pressed() -> bool:
	return Input.is_physical_key_pressed(KEY_SPACE) or (is_instance_valid(mobile_input) and mobile_input.jump_pressed)
func _sprint_is_pressed() -> bool:
	return Input.is_physical_key_pressed(KEY_SHIFT) or (is_instance_valid(mobile_input) and mobile_input.sprint_pressed)
func _physics_process(delta: float) -> void:
	if not ready_world or input_suspended:return
	if is_instance_valid(exploration_context) and exploration_context.inside:
		exploration_context.check_bounds()
	var axis:=_movement_axis()
	var direction:=Basis(Vector3.UP,yaw)*Vector3(axis.x,0,axis.y)
	if flight.flying:
		flight.step(delta,axis)
	else:
		water_jump_cooldown=maxf(0,water_jump_cooldown-delta)
		var level:=float(water_config.sea_level)
		var ground:=_height(player.position)
		var deep:=level-ground>float(water_config.swim_depth)*explorer_scale and ground>-900
		swimming=deep and player.position.y<level-(0.25 if swimming else 0.45)*explorer_scale and water_jump_cooldown<=0
		var speed:=float(water_config.swim_speed) if swimming else (30.0 if _sprint_is_pressed() else 8.0)
		player.velocity.x=direction.x*speed;player.velocity.z=direction.z*speed
		if swimming:
			var target_y:=level-float(water_config.float_offset)*explorer_scale
			player.velocity.y=clampf((target_y-player.position.y)*5,-3,3)
			if _jump_is_pressed():
				player.velocity.y=float(water_config.get("jump_speed",7.0))
				water_jump_cooldown=maxf(0.65,player.velocity.y/24.0)
				swimming=false
		elif not player.is_on_floor():player.velocity.y-=24*delta
		elif _jump_is_pressed():player.velocity.y=9
		else:player.velocity.y=0
		avatar.set_swimming(swimming)
		player.move_and_slide()
		if direction.length()>0.1:avatar.rotation.y=lerp_angle(avatar.rotation.y,atan2(-direction.x,-direction.z),delta*10)
		avatar.set_locomotion(not player.is_on_floor() and not swimming,player.velocity.y,speed*axis.length())
	flight.update_visual(delta)
	if player.position.y<fall_reset_height or _height(player.position)<-900:_reset_player()
	var target:=player.position+Vector3(0,1.45*explorer_scale,0)
	var offset:=Basis(Vector3.UP,yaw)*Vector3(0,-sin(pitch)*distance,cos(pitch)*distance)
	var desired:=target+offset
	var query:=PhysicsRayQueryParameters3D.create(target,desired);query.exclude=[player.get_rid()]
	var hit:=get_world_3d().direct_space_state.intersect_ray(query)
	camera.position=hit.position+(target-hit.position).normalized()*0.35 if not hit.is_empty() else desired
	camera.look_at(target)
	collider_tick+=delta
	if collider_tick>1.0:collider_tick=0;_refresh_collisions()
	label.text=world_title+" · 地图探索  /  "+destination_names[tour_index]+"\nWASD 移动 · Shift 快跑 · 双空格起降 · 右键振翅 · Ctrl 视角\n滚轮缩放 · Tab 切换区域 · R 返回落脚点 · Esc 释放鼠标\n%.0f, %.0f  |  %d FPS"%[player.position.x,player.position.z,Engine.get_frames_per_second()]

	if flight.flying:
		label.text+="\n滑翔 %.1f / %.0f · %s" % [player.velocity.length(),flight.max_flight_speed,"推进冷却 %.1f 秒" % flight.boost_remaining if flight.boost_remaining>0 else "右键推进就绪"]

func _appearance_candidates(folder: String, result: Array[String]) -> void:
	var dir:=DirAccess.open(folder)
	if dir==null:return
	for sub in dir.get_directories():_appearance_candidates(folder.path_join(sub),result)
	if FileAccess.file_exists(folder.path_join("academy_wardrobe.json")) and FileAccess.file_exists(folder.path_join("fusion_3d_story.json")):
		result.append(folder)
func _load_formal_appearance() -> String:
	if use_session_appearance:return session_school
	var store:=get_node("/root/Wardrobe")
	var folder:=Accounts.cache_root
	if folder.is_empty():
		var candidates: Array[String]=[]
		_appearance_candidates(Accounts.cache_base,candidates)
		candidates.sort_custom(func(a: String,b: String):return FileAccess.get_modified_time(a.path_join("academy_wardrobe.json"))>FileAccess.get_modified_time(b.path_join("academy_wardrobe.json")))
		if not candidates.is_empty():folder=candidates[0]
	var wardrobe_path: String=folder.path_join("academy_wardrobe.json") if not folder.is_empty() else "user://academy_wardrobe.json"
	store.save_path=wardrobe_path
	store.save_enabled=false
	store.load_save()
	var story_path: String=folder.path_join("fusion_3d_story.json") if not folder.is_empty() else "user://fusion_3d_story.json"
	var school:=str(Accounts.active_character.get("school","life"))
	if FileAccess.file_exists(story_path):
		var story: Variant=JSON.parse_string(FileAccess.get_file_as_string(story_path))
		if story is Dictionary and not story.get("party",[]).is_empty():
			var schools: Dictionary={"fire_student":"fire","ice_guardian":"ice","storm_duelist":"storm","life_healer":"life","death_reaper":"death","myth_scholar":"myth","balance_adept":"balance"}
			school=schools.get(str(story.party[0]),school)
	return school

func _build_water() -> void:
	water_config=JSON.parse_string(FileAccess.get_file_as_string(water_config_path))
	var plane:=PlaneMesh.new();plane.size=Vector2(6000,6000);plane.subdivide_width=240;plane.subdivide_depth=240
	var water:=MeshInstance3D.new();water.name="Ocean";water.mesh=plane;water.position.y=float(water_config.sea_level)
	var material:=ShaderMaterial.new();material.shader=load("res://scripts/worlds/haqi_water.gdshader");water.material_override=material;water.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(water)
	_configure_world_water(material)
	destinations.append(Vector3(water_config.test_water_position[0],water_config.sea_level,water_config.test_water_position[2]))
	destination_names.append("海岸 · 游泳体验")

func apply_explorer_scale(value: float) -> void:
	explorer_scale = clampf(value, 1.0, 3.0)
	if not is_instance_valid(avatar):return
	avatar.scale = Vector3.ONE * explorer_scale
	if capsule_node != null:
		var capsule := capsule_node.shape as CapsuleShape3D
		capsule.radius = 0.4 * explorer_scale
		capsule.height = 1.9 * explorer_scale
		capsule_node.position.y = capsule.height * 0.5
	player.floor_snap_length = 0.7 * explorer_scale

# Rendering-only extension: collision_pool always retains source transforms.
func _configure_visual_group(_node: MultiMeshInstance3D, _group: Dictionary, _part: Dictionary) -> void:
	pass

func _configure_world_water(material: ShaderMaterial) -> void:
	var palettes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/water_palettes.json"))
	var key := world_root.trim_suffix("/").get_file()
	var palette: Dictionary = palettes.get(key,{})
	var attrs: Dictionary = data.get("attributes",{})
	var base := Color("246775")
	if attrs.has("OceanColor_R"):
		var authored := Color(float(attrs.OceanColor_R),float(attrs.OceanColor_G),float(attrs.OceanColor_B))
		# Retain authored hue while taming fluorescent legacy RGB values.
		base = Color.from_hsv(authored.h,clampf(authored.s*0.72,0.12,0.72),clampf(authored.v*0.53,0.19,0.53))
	var shallow := base.lerp(Color("c2d2ce"),0.28)
	var reflection := base.lerp(Color("abbacb"),0.43)
	var foam := base.lerp(Color("e0e8de"),0.72)
	material.set_shader_parameter("deep_color",Color(palette.get("deep",base.to_html(false))))
	material.set_shader_parameter("shallow_color",Color(palette.get("shallow",shallow.to_html(false))))
	material.set_shader_parameter("reflection_color",Color(palette.get("reflection",reflection.to_html(false))))
	material.set_shader_parameter("foam_color",Color(palette.get("foam",foam.to_html(false))))
	material.set_shader_parameter("sea_level",float(water_config.sea_level))
	if heights.is_empty():return
	var min_tile := Vector2i(10000,10000)
	var max_tile := Vector2i(-10000,-10000)
	for tile: Vector2i in heights:
		min_tile=min_tile.min(tile)
		max_tile=max_tile.max(tile)
	# Bound sparse world height atlases to at most 2048 per axis.
	var stride := 1
	while ((max_tile-min_tile+Vector2i.ONE)*128/stride).x > 2047 or ((max_tile-min_tile+Vector2i.ONE)*128/stride).y > 2047:
		stride *= 2
	var samples: int = 128/stride
	var size := (max_tile-min_tile+Vector2i.ONE)*samples+Vector2i.ONE
	var pixels := PackedFloat32Array()
	pixels.resize(size.x*size.y)
	pixels.fill(float(water_config.sea_level)-30.0)
	for tile: Vector2i in heights:
		var source: PackedFloat32Array=heights[tile]
		var offset := (tile-min_tile)*samples
		for z in range(samples+1):
			for x in range(samples+1):
				pixels[(offset.y+z)*size.x+offset.x+x]=source[z*stride*129+x*stride]
	var height_image := Image.create_from_data(size.x,size.y,false,Image.FORMAT_RF,pixels.to_byte_array())
	material.set_shader_parameter("terrain_height",ImageTexture.create_from_image(height_image))
	material.set_shader_parameter("has_terrain_height",true)
	var sample_step := terrain_size/float(samples)
	material.set_shader_parameter("terrain_start",Vector2(min_tile)*terrain_size-origin-Vector2.ONE*sample_step*0.5)
	material.set_shader_parameter("terrain_extent",Vector2(size)*sample_step)


# Geometry is streamed in cell-sized groups; source meshes and collision data
# remain shared/resident. This reduces instances, not all texture allocations.
func _friend_spawn_group(g: Dictionary) -> void:
	for part in prototypes[g.path]:
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=part.mesh;mm.instance_count=g.transforms.size()
		for i in g.transforms.size():mm.set_instance_transform(i,g.transforms[i]*part.transform)
		var node:=MultiMeshInstance3D.new();node.multimesh=mm;node.visibility_range_end=100;node.visibility_range_end_margin=10
		_configure_visual_group(node,g,part)
		add_child(node);g.friend_nodes.append(node)

func _friend_update_groups(at: Vector3,budget: int=1) -> void:
	var created:=0
	for g in friend_groups:
		var resident: bool=not g.friend_nodes.is_empty()
		var bounds: AABB=g.friend_bounds
		if resident and not bounds.grow(120.0).has_point(at):
			for node in g.friend_nodes:
				if is_instance_valid(node):node.hide()
			pass # Keep small instance buffers available for reuse.
		elif resident and bounds.grow(100.0).has_point(at):
			for node in g.friend_nodes:node.show()
		elif not resident and bounds.grow(80.0).has_point(at):
			if budget>0 and created>=budget:continue
			_friend_spawn_group(g);created+=1
func _process(delta: float) -> void:
	if not GraphicsSettings.is_low() or not ready_world or input_suspended:return
	friend_group_tick-=delta
	if friend_group_tick<=0.0:
		friend_group_tick=0.05
		_friend_update_groups(player.position)
