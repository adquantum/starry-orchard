extends Node3D
const GalleryScene := preload("res://scenes/worlds/old_root_gallery.tscn")
const Gallery := preload("res://scripts/worlds/old_root_gallery.gd")
const ENTRANCE := Vector3(1072,336.74,-734)
const AUDIO := "res://assets/audio/ambience/old_root_gallery/running_water_loop.wav"
var world: Node3D
var inside := false
var busy := false
var gallery: Node3D
var saved: Dictionary = {}
var actor_layers: Dictionary = {}
var cooldown := 0.0
var sources: Array[Dictionary] = []
var stream: AudioStreamWAV
var hint: Label
var fade: ColorRect
var gate: Node3D
var interior_ambience: AudioStreamPlayer

func install(owner_world: Node3D) -> void:
	world = owner_world
	name = "OldRootGateway"
	world.camera.cull_mask &= ~Gallery.LAYER
	stream = load(AUDIO) as AudioStreamWAV
	if stream != null:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length()*stream.mix_rate)
	_build_entrance()
	var sky := world.get_node_or_null("BlenderSkySanctuary")
	var mother: Node = sky.find_child("V_HERO_AncientCherry__SM_VEG_01_ElderCherry",true,false) if sky != null else null
	if mother != null: gate.reparent(mother,true)
	_audio(gate.to_global(Vector3(0,3,-3)),42,-12,false)
	var ui := CanvasLayer.new()
	ui.layer = 65
	add_child(ui)
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-260,-115)
	hint.size = Vector2(520,70)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size",22)
	hint.add_theme_color_override("font_shadow_color",Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x",2)
	hint.add_theme_constant_override("shadow_offset_y",2)
	ui.add_child(hint)
	interior_ambience = AudioStreamPlayer.new()
	interior_ambience.name = "GalleryContinuousWater"
	interior_ambience.stream = stream
	interior_ambience.volume_db = -80
	add_child(interior_ambience)
	fade = ColorRect.new()
	fade.color = Color(0.025,.055,.065,0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(fade)
	world.set_meta("old_root_gateway",{"entrance":ENTRANCE,"scene":"res://scenes/worlds/old_root_gallery.tscn","audio_license":"CC-BY-3.0"})

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not world.ready_world: return
	cooldown = maxf(0,cooldown-delta)
	var at: Vector3 = world.player.position
	if inside and not interior_ambience.playing: interior_ambience.play()
	interior_ambience.volume_db = move_toward(interior_ambience.volume_db,-27.0 if inside else -80.0,delta*45)
	if not inside and interior_ambience.volume_db<=-79: interior_ambience.stop()
	for entry in sources:
		var sound: AudioStreamPlayer3D = entry.node
		var separation := at.distance_to(sound.global_position)
		var gain := 1.0-smoothstep(4.0,float(entry.radius),separation)
		if bool(entry.interior) != inside: gain = 0
		var wanted := float(entry.db)+linear_to_db(maxf(.0001,gain))
		sound.volume_db = move_toward(sound.volume_db,wanted,delta*55)
		if gain>.001 and not sound.playing: sound.play()
		elif gain<=.001 and sound.volume_db < -65: sound.stop()
	if busy:
		hint.text = "正在进入旧根回廊…" if not inside else "正在返回母树…"
		return
	if world.input_suspended:
		hint.text = ""
		return
	var near := at.distance_to(Gallery.EXIT if inside else ENTRANCE) < (7.0 if inside else 13.0)
	hint.text = ("旧根回廊 · 返回母树\n走进根门 / E 返回" if inside else "旧根回廊 · 母树之下，万水归流\n走进根门 / E 进入") if near else ""
	if inside:
		if at.y < -8: reset_to_safe()
		# Complete the short west-facing return passage before switching.
		var local_at: Vector3 = gallery.to_local(at)
		if cooldown<=0 and local_at.x < -58 and absf(local_at.z-42)<3.4 and absf(local_at.y-8)<3: leave()
	elif cooldown<=0:
		var local_at := gate.to_local(at)
		if absf(local_at.x)<3.1 and absf(local_at.y)<4 and local_at.z < -2.4 and local_at.z > -6: enter()

func _unhandled_input(event: InputEvent) -> void:
	if busy or cooldown>0 or not world.ready_world or world.input_suspended: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E:
		if world.player.position.distance_to(Gallery.EXIT if inside else ENTRANCE)<(7.0 if inside else 13.0):
			get_viewport().set_input_as_handled()
			if inside: leave()
			else: enter()

func enter() -> void:
	if busy or inside or world.input_suspended: return
	busy = true
	world.input_suspended = true
	await _fade_to(1)
	if gallery == null:
		gallery = GalleryScene.instantiate()
		add_child(gallery)
		var error: Error = gallery.build()
		if error != OK:
			gallery.queue_free()
			gallery = null
			push_error("Old Root Gallery could not load: "+str(error))
			await _fade_to(0)
			world.input_suspended = false
			busy = false
			return
		for location in [Vector3(-67,8,26),Vector3(60,19,-17),Vector3(28,31,-68)]: _audio(location*Gallery.WORLD_SCALE,72*Gallery.WORLD_SCALE,-18,true)
	world.flight.land()
	saved = {"position":gate.to_global(Vector3(0,1,9)),"yaw":world.yaw,"pitch":world.pitch,"distance":world.distance,"mask":world.player.collision_mask,"layer":world.player.collision_layer,"cull":world.camera.cull_mask,"far":world.camera.far,"environment":world.camera.environment,"water":world.water_config.duplicate(),"fall":world.fall_reset_height,"destinations":world.destinations.duplicate(),"names":world.destination_names.duplicate(),"tour":world.tour_index,"lights":[]}
	for child in world.get_children():
		if child is Light3D:
			saved.lights.append([child,child.visible])
			child.visible = false
	_change_actor_layers(world.player)
	world.player.collision_mask = Gallery.LAYER
	world.player.collision_layer = Gallery.LAYER
	world.camera.cull_mask = Gallery.LAYER
	saved["msaa"] = get_viewport().msaa_3d
	get_viewport().msaa_3d = Viewport.MSAA_4X
	world.camera.far = 400*Gallery.WORLD_SCALE
	world.camera.environment = gallery.environment
	world.water_config = {"sea_level":-1000.0,"swim_depth":1.15,"swim_speed":4.2,"float_offset":.85}
	world.fall_reset_height = -8
	world.destinations = [Gallery.SPAWN]
	world.destination_names = ["旧根回廊 · 入口平台"]
	world.tour_index = 0
	world.player.position = Gallery.SPAWN+Vector3.UP
	world.player.velocity = Vector3.ZERO
	world.yaw = 0.0
	world.avatar.rotation.y = 0.0
	world.pitch = -.2
	world.distance = 12
	gallery.show()
	gallery.process_mode = Node.PROCESS_MODE_INHERIT
	world.ambient_life.set_effects_enabled(false)
	inside = true
	cooldown = 2
	world.input_suspended = false
	await get_tree().physics_frame
	await _fade_to(0)
	busy = false
	print("OLD_ROOT_ENTERED")

func leave() -> void:
	if busy or not inside: return
	busy = true
	world.input_suspended = true
	await _fade_to(1)
	world.player.position = saved.position
	world.player.velocity = Vector3.ZERO
	world.player.collision_mask = saved.mask
	world.player.collision_layer = saved.layer
	world.camera.cull_mask = saved.cull
	get_viewport().msaa_3d = saved.msaa
	world.camera.far = saved.far
	world.camera.environment = saved.environment
	world.water_config = saved.water
	world.fall_reset_height = saved.fall
	world.destinations = saved.destinations
	world.destination_names = saved.names
	world.tour_index = saved.tour
	world.yaw = gate.global_rotation.y+PI
	world.pitch = saved.pitch
	world.distance = saved.distance
	for node in actor_layers:
		if is_instance_valid(node): node.layers = actor_layers[node]
	actor_layers.clear()
	for item in saved.lights:
		if is_instance_valid(item[0]): item[0].visible = item[1]
	gallery.hide()
	gallery.process_mode = Node.PROCESS_MODE_DISABLED
	world.ambient_life.set_effects_enabled(true)
	inside = false
	cooldown = 2.0
	world.input_suspended = false
	world._refresh_collisions()
	await get_tree().physics_frame
	await _fade_to(0)
	busy = false
	print("OLD_ROOT_RETURNED")

func reset_to_safe() -> void:
	world.player.position = Gallery.SPAWN+Vector3.UP
	world.player.velocity = Vector3.ZERO
	world.yaw = 0
	cooldown = 2

func _change_actor_layers(node: Node) -> void:
	if node is VisualInstance3D:
		actor_layers[node] = node.layers
		node.layers = Gallery.LAYER
	for child in node.get_children(): _change_actor_layers(child)

func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade,"color:a",alpha,.4)
	await tween.finished

func _audio(at: Vector3,radius: float,db: float,is_interior: bool) -> void:
	if stream == null: return
	var sound := AudioStreamPlayer3D.new()
	sound.name = "WaterFlow"
	sound.stream = stream
	sound.position = at
	sound.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	sound.volume_db = -80
	sound.max_db = 0
	sound.panning_strength = .65
	add_child(sound)
	sources.append({"node":sound,"radius":radius,"db":db,"interior":is_interior})

func _material(color: String,emission: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = .92
	if emission>0:
		material.emission_enabled = true
		material.emission = Color(color)
		material.emission_energy_multiplier = emission
	return material

func _box(at: Vector3,size: Vector3,material: Material,solid: bool = true) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = material
	gate.add_child(node)
	if solid: node.create_trimesh_collision()
	return node

func _root_segment(a: Vector3,b: Vector3,radius: float,material: Material) -> void:
	var node := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius*.86
	cylinder.bottom_radius = radius
	cylinder.height = a.distance_to(b)
	cylinder.radial_segments = 9
	node.mesh = cylinder
	node.material_override = material
	node.position = (a+b)*.5
	var direction := (b-a).normalized()
	var side := direction.cross(Vector3.FORWARD).normalized()
	node.basis = Basis(side,direction,side.cross(direction))
	gate.add_child(node)

func _build_entrance() -> void:
	gate = Node3D.new()
	gate.name = "MotherTreeRootDoor"
	gate.position = ENTRANCE
	gate.rotation.y = -PI*.5
	add_child(gate)
	var stone := _material("b4bc9b")
	var inset := _material("344a47")
	var bark := _material("655240")
	var glow := _material("499ca9",.8)
	_box(Vector3(0,-.2,-1),Vector3(11,.4,11),stone)
	for sign_value in [-1,1]:
		_box(Vector3(sign_value*4.9,2.7,-1.5),Vector3(1.7,5.4,6),inset)
		_box(Vector3(sign_value*4.3,2.5,1),Vector3(1.2,5,1.7),stone)
		_box(Vector3(sign_value*5.1,1.0,3.5),Vector3(2.2,2,2.3),inset)
		_box(Vector3(sign_value*4.8,3.3,2.1),Vector3(.55,1.4,.55),glow,false)
	for index in 13:
		var angle := float(index)/12*PI
		var arch := _box(Vector3(cos(angle)*4.3,4.6+sin(angle)*4.3,1),Vector3(1.2,1.35,1.8),stone)
		arch.rotation.z = angle-PI*.5
	_box(Vector3(0,8,-1.7),Vector3(8,2.2,5.6),inset)
	# Dark back wall creates a short sheltered passage; switching happens in front.
	_box(Vector3(0,4.2,-4.5),Vector3(8,8.4,.4),_material("102f34"))
	for sign_value in [-1,1]:
		var points := [Vector3(sign_value*8,-.2,4),Vector3(sign_value*6,2,1.5),Vector3(sign_value*5.5,6,-.4),Vector3(sign_value*3.4,9.7,-2),Vector3(sign_value*1.6,12,-5)]
		for index in points.size()-1: _root_segment(points[index],points[index+1],1.1-float(index)*.12,bark)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0,4,-1)
	lamp.light_color = Color("52c6d0")
	lamp.light_energy = 1.8
	lamp.omni_range = 13
	gate.add_child(lamp)
	var title := Label3D.new()
	title.text = "旧 根 回 廊"
	title.font_size = 64
	title.pixel_size = .025
	title.position = Vector3(0,10.5,1.7)
	title.modulate = Color("f0dbaa")
	gate.add_child(title)
