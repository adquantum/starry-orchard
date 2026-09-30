extends "res://scripts/worlds/cloudfortress_explorer.gd"

const REUSED_MATERIALS := "res://assets/worlds/star_orchard/reused_materials.json"
const THEME_MATERIALS := "res://assets/worlds/star_orchard/theme_v1/material_map.json"
const TREE_V4_ROOT := "res://assets/worlds/star_orchard/paint_v1/models/"
const TREE_PAINT_ROOT := "res://assets/worlds/star_orchard/paint_v1/"
const ORCHARD_SKY := "res://assets/worlds/star_orchard/sky_v1/panorama.png"
const TOWN_POLISH_ROOT := "res://assets/worlds/star_orchard/town_polish_v2/"
const GROUND_GATE := Vector3(1247.0, 272.0, -311.0)
const SKY_GATE := Vector3(1138.0, 10265.0, -46.0)
const GATE_RADIUS := 5.0
const GATE_HEIGHT := 5.0
var reused_materials: Dictionary = {}
var reused_meshes: Dictionary = {}
var tree_v4_parts: Dictionary = {}
var tree_v4_scales: Dictionary = {}
var orchard_textures: Dictionary = {}
var gate_armed := true
var town_polish_ids: Dictionary = {}
var town_polish_status: Dictionary = {"terrain": false, "environment": false, "props": 0, "solid_props": 0}
var satellites: Node3D
var coastal_expansion: Node3D
var procedural_landscape: Node3D
var sky_city: RefCounted
var harbor_city: RefCounted
var mountain_dressing: RefCounted
var route_details: RefCounted
var ambient_life: Node3D
var root_gateway: Node3D
var windchime_garden: Node3D
const SEA_LEVEL := 220.0
const SEA_FLOOR := 190.0
const MainTerrain := preload("res://scripts/worlds/orchard_main_terrain.gd")

func _procedural_world_enabled() -> bool:
	return preload("res://scripts/worlds/star_orchard_features.gd").PROCEDURAL_WORLD_ENABLED and not "--orchard-legacy-town" in OS.get_cmdline_user_args()

func _world_document() -> Dictionary:
	var document := super._world_document()
	if _procedural_world_enabled():
		# Keep the authored document on disk, but do not load its town or colliders.
		document["terrain"] = []
		document["models"] = {}
		document["placements"] = []
	return document

func _town_polish_enabled(part: String = "") -> bool:
	var args := OS.get_cmdline_user_args()
	return not "--town-polish-off" in args and (part.is_empty() or not ("--town-polish-" + part + "-off") in args)

func _town_polish_config(relative_path: String) -> Dictionary:
	var path := TOWN_POLISH_ROOT.path_join(relative_path)
	if not FileAccess.file_exists(path):return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _load_world() -> void:
	if _procedural_world_enabled():
		await _load_procedural_world()
		return
	await super._load_world()
	var editor_args := OS.get_cmdline_user_args()
	if not ("--orchard-editor" in editor_args and "--offline" in editor_args and not OS.has_feature("mobile")):
		preload("res://scripts/worlds/star_orchard_saved_layout.gd").install(self)
	if preload("res://scripts/worlds/star_orchard_features.gd").SATELLITES_ENABLED:
		satellites = preload("res://scripts/worlds/star_orchard_satellites.gd").new()
		satellites.name = "OrchardSatellites"
		add_child(satellites)
		satellites.install(self)
	coastal_expansion=preload("res://scripts/worlds/orchard_coastal_expansion.gd").new()
	add_child(coastal_expansion)
	coastal_expansion.install(self)
	if is_instance_valid(camera):camera.far=14000.0
	# Append an isolated set after source loading. The original placements and
	# collision indices stay unchanged, and each fresh scene owns its additions.
	if not _town_polish_enabled("props"):return
	var config := _town_polish_config("props/placements.json")
	var props_root := Node3D.new()
	props_root.name = "TownPolishV2"
	add_child(props_root)
	for entry in config.get("placements", []):
		var id := str(entry.get("id", ""))
		var model := str(entry.get("model", ""))
		if id.is_empty() or town_polish_ids.has(id) or not ResourceLoader.exists(model):continue
		if not prototypes.has(model):
			var scene := load(model) as PackedScene
			if scene == null:continue
			var instance := scene.instantiate()
			var parts: Array = []
			_collect_meshes(instance, Transform3D.IDENTITY, parts)
			instance.free()
			prototypes[model] = parts
		var at: Array = entry.position
		var size: Array = entry.get("scale", [1, 1, 1])
		var basis := Basis(Vector3.UP, deg_to_rad(float(entry.get("rotation_y_degrees", 0))))
		basis = basis.scaled(Vector3(size[0], size[1], size[2]))
		var transform := Transform3D(basis, Vector3(at[0], at[1], at[2]))
		for part in prototypes[model]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = part.mesh
			mm.instance_count = 1
			mm.set_instance_transform(0, transform * part.transform)
			var node := MultiMeshInstance3D.new()
			node.name = id
			node.multimesh = mm
			node.visibility_range_end = 1100
			node.visibility_range_end_margin = 100
			_configure_visual_group(node, {"path": model}, part)
			props_root.add_child(node)
		if bool(entry.get("solid", false)):
			collision_pool.append({"path": model, "transform": transform, "town_polish_id": id})
			town_polish_status.solid_props += 1
		town_polish_ids[id] = {"model": model, "transform": transform}
		town_polish_status.props += 1
	_refresh_collisions()

func _load_west_only() -> void:
	set_meta("orchard_procedural_world", true)
	set_meta("orchard_west_only", true)
	label.text = "正在进入西岛单人教程…"
	windchime_garden = preload("res://scripts/worlds/orchard_windchime_garden.gd").new()
	add_child(windchime_garden)
	windchime_garden.install(self)
	destinations = [preload("res://scripts/worlds/orchard_journey_rules.gd").WEST_ENTRY]
	destination_names = ["西岛 · 新手入口"]
	source_spawn = destinations[0];spawn = source_spawn;tour_index = 0
	fall_reset_height = 210.0
	await super._load_world()
	if is_instance_valid(camera):camera.far = 1800.0
	pitch = -0.32;distance = 14.0;loading_progress = 100.0
	print("ORCHARD_WEST_ONLY_READY main_terrain=false main_props=false")

func _load_procedural_world() -> void:
	if bool(get_meta("tutorial_instance", false)) and not bool(get_meta("tutorial_distant_main", false)):
		await _load_west_only()
		return
	var load_started := Time.get_ticks_msec()
	var phase_started := load_started
	var load_timings: Dictionary = {}
	set_meta("orchard_procedural_world",true)
	set_meta("orchard_generated_terrain","orchard_landscape_v2")
	label.text = "星界果园 · 正在生成山地与海岸…"
	procedural_landscape = load("res://scripts/worlds/orchard_procedural_landscape.gd").new()
	add_child(procedural_landscape)
	procedural_landscape.install(self)
	phase_started = _record_load_phase(load_timings, "terrain", phase_started)
	loading_progress = 20.0
	await get_tree().process_frame
	label.text = "星界果园 · 正在接入高山天空城…"
	sky_city = load("res://scripts/worlds/orchard_sky_city.gd").new()
	var city_loaded: bool = sky_city.install(self)
	phase_started = _record_load_phase(load_timings, "sky_city", phase_started)
	loading_progress = 35.0
	await get_tree().process_frame
	label.text = "星界果园 · 正在接入海港城镇…"
	harbor_city = load("res://scripts/worlds/orchard_harbor_city.gd").new()
	var harbor_loaded: bool = harbor_city.install(self)
	phase_started = _record_load_phase(load_timings, "harbor_city", phase_started)
	loading_progress = 50.0
	await get_tree().process_frame
	windchime_garden = preload("res://scripts/worlds/orchard_windchime_garden.gd").new()
	add_child(windchime_garden)
	windchime_garden.install(self)
	phase_started = _record_load_phase(load_timings, "west_garden", phase_started)
	loading_progress = 58.0
	await get_tree().process_frame
	label.text = "星界果园 · 正在布置山路树木与岩石…"
	mountain_dressing = preload("res://scripts/worlds/orchard_mountain_dressing.gd").new()
	mountain_dressing.install(self, procedural_landscape)
	phase_started = _record_load_phase(load_timings, "forest", phase_started)
	loading_progress = 76.0
	await get_tree().process_frame
	label.text = "星界果园 · 正在铺设山路石阶与路灯…"
	route_details = preload("res://scripts/worlds/orchard_route_details.gd").new()
	route_details.install(self, procedural_landscape)
	phase_started = _record_load_phase(load_timings, "route_details", phase_started)
	loading_progress = 82.0
	await get_tree().process_frame
	ambient_life = preload("res://scripts/worlds/orchard_ambient_life.gd").new()
	add_child(ambient_life)
	ambient_life.install(self, procedural_landscape)
	phase_started = _record_load_phase(load_timings, "ambient_life", phase_started)
	destinations = []
	destination_names = []
	if harbor_loaded:
		destinations.append(harbor_city.entry_point())
		destination_names.append("星果海港 · 中央广场")
	if city_loaded:
		destinations.append(sky_city.entry_point())
		destination_names.append("高山天空城 · 入口")
	var landscape_points: Array = procedural_landscape.destination_points()
	var landscape_names: Array = procedural_landscape.destination_names()
	for index in range(1 if harbor_loaded else 0, landscape_points.size()):
		destinations.append(landscape_points[index])
		destination_names.append(landscape_names[index])
	windchime_garden.add_destinations(self)
	source_spawn = destinations[0]
	spawn = source_spawn
	tour_index = 0
	fall_reset_height = 150.0
	yaw = 0.0
	await super._load_world()
	phase_started = _record_load_phase(load_timings, "base_world", phase_started)
	if is_instance_valid(camera):camera.far = 14000.0
	root_gateway = preload("res://scripts/worlds/orchard_root_gateway.gd").new()
	add_child(root_gateway)
	root_gateway.install(self)
	_record_load_phase(load_timings, "root_entrance", phase_started)
	load_timings["total_ms"] = Time.get_ticks_msec() - load_started
	set_meta("orchard_load_timings", load_timings)
	if "--orchard-profile-load" in OS.get_cmdline_user_args():
		print("ORCHARD_LOAD_TIMINGS ", JSON.stringify(load_timings))
	pitch = -0.32
	distance = 14.0
	loading_progress = 100.0
	if bool(get_meta("tutorial_instance", false)):
		destinations = [preload("res://scripts/worlds/orchard_journey_rules.gd").WEST_ENTRY]
		destination_names = ["西岛 · 新手入口"]
		tour_index = 0;source_spawn = destinations[0];spawn = source_spawn
	print("ORCHARD_PROCEDURAL_WORLD_READY legacy_town=false harbor_loaded=",harbor_loaded)

func _record_load_phase(timings: Dictionary, phase: String, started: int) -> int:
	var now := Time.get_ticks_msec()
	timings[phase + "_ms"] = now - started
	return now

func _ready() -> void:
	reused_materials = JSON.parse_string(FileAccess.get_file_as_string(REUSED_MATERIALS))
	if not "--orchard-theme-off" in OS.get_cmdline_user_args() and FileAccess.file_exists(THEME_MATERIALS):
		var theme: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(THEME_MATERIALS))
		for model in theme:
			if not reused_materials.has(model):
				reused_materials[model] = {"materials": {}}
			for slot in theme[model].materials:
				# Already repainted slots remain authoritative.
				if not reused_materials[model].materials.has(slot):
					reused_materials[model].materials[slot] = theme[model].materials[slot]
	super._ready()

func _setup_view() -> void:
	super._setup_view()
	var panorama := _orchard_texture(ORCHARD_SKY)
	if panorama == null:return
	var sky_material := PanoramaSkyMaterial.new()
	sky_material.panorama = panorama
	var sky := Sky.new()
	sky.sky_material = sky_material
	for child in get_children():
		if child is WorldEnvironment:
			var environment := (child as WorldEnvironment).environment
			environment.background_mode = Environment.BG_SKY
			environment.sky = sky
			# Dim the panorama separately so bright clouds do not overpower the orchard.
			environment.background_energy_multiplier = 0.68
			environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			environment.ambient_light_color = Color("b7c7d8")
			environment.ambient_light_energy = 0.40
			environment.tonemap_exposure = 0.85
			if _town_polish_enabled("environment"):
				var fog := _town_polish_config("environment/environment.json")
				if not fog.is_empty():
					environment.fog_enabled = bool(fog.get("fog_enabled", false))
					environment.fog_light_color = Color(str(fog.get("fog_light_color", "b7c7d8")))
					environment.fog_density = float(fog.get("fog_density", 0.0))
					environment.fog_sky_affect = float(fog.get("fog_sky_affect", 0.0))
					town_polish_status.environment = environment.fog_enabled
			break
	for child in get_children():
		if child is DirectionalLight3D:
			child.light_energy = 0.46

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if is_instance_valid(root_gateway) and root_gateway.inside and ready_world and not input_suspended:
		var target := player.position+Vector3(0,1.45*explorer_scale,0)
		var desired := target+Basis(Vector3.UP,yaw)*Vector3(0,-sin(pitch)*distance,cos(pitch)*distance)
		var ray := PhysicsRayQueryParameters3D.create(target,desired,root_gateway.Gallery.LAYER)
		ray.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		camera.position = hit.position+(target-hit.position).normalized()*.35 if not hit.is_empty() else desired
		camera.look_at(target)
	if _procedural_world_enabled():return
	if not ready_world or input_suspended or not is_instance_valid(player):return
	if not gate_armed:
		if not _inside_gate(player.position, GROUND_GATE) and not _inside_gate(player.position, SKY_GATE):
			gate_armed = true
		return
	if _inside_gate(player.position, GROUND_GATE):
		_travel_gate(SKY_GATE)
	elif _inside_gate(player.position, SKY_GATE):
		_travel_gate(GROUND_GATE)

func _inside_gate(point: Vector3, gate: Vector3) -> bool:
	return absf(point.y - gate.y) <= GATE_HEIGHT and Vector2(point.x - gate.x, point.z - gate.z).length() <= GATE_RADIUS

func _height(at: Vector3) -> float:
	if is_instance_valid(root_gateway) and root_gateway.inside:
		return root_gateway.gallery.floor_height(at)
	if _procedural_world_enabled():
		var ground: float = procedural_landscape.surface_height(at) if is_instance_valid(procedural_landscape) else SEA_FLOOR
		if is_instance_valid(windchime_garden):
			var garden_floor: float = windchime_garden.surface_height(at)
			if is_finite(garden_floor):ground = maxf(ground,garden_floor)
		if is_instance_valid(sky_city):
			var city_floor: float = sky_city.surface_height(at)
			if is_finite(city_floor):ground = maxf(ground,city_floor)
		if is_instance_valid(harbor_city):
			var port_floor: float = harbor_city.surface_height(at)
			if is_finite(port_floor):ground = maxf(ground,port_floor)
		if is_instance_valid(route_details):
			var step_floor: float = route_details.surface_height(at)
			if is_finite(step_floor):ground = maxf(ground,step_floor)
		var quest_places := get_node_or_null("StarOrchardWorld1Placements")
		if quest_places != null:
			var quest_floor: float = quest_places.surface_height(at)
			if is_finite(quest_floor):ground = maxf(ground,quest_floor)
		return ground
	if is_instance_valid(coastal_expansion):
		var coast_height: float=coastal_expansion.surface_height(at)
		if is_finite(coast_height):return coast_height
	if is_instance_valid(satellites):
		var surface: float = satellites.surface_height(at)
		if is_finite(surface):return surface
	# Catalog's missing-tile fallback is the town spawn height, which prevents swimming.
	# The connected sea instead has a real continuous bottom below the water surface.
	var tile := Vector2i(floori((at.x+origin.x)/terrain_size),floori((at.z+origin.y)/terrain_size))
	if not heights.has(tile):return SEA_FLOOR
	return maxf(SEA_FLOOR,super._height(at))

func _reset_player() -> void:
	if is_instance_valid(root_gateway) and root_gateway.inside:
		root_gateway.reset_to_safe()
		return
	super._reset_player()

func _refresh_collisions() -> void:
	if is_instance_valid(root_gateway) and root_gateway.inside: return
	super._refresh_collisions()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(root_gateway) and root_gateway.inside:
		if event is InputEventKey and event.keycode in [KEY_SPACE,KEY_TAB]: return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT: return
	super._unhandled_input(event)

func _build_water() -> void:
	water_config = {"sea_level":SEA_LEVEL,"swim_depth":1.15,"float_offset":0.85,"swim_speed":7.0,"sea_floor":SEA_FLOOR}
	var plane := PlaneMesh.new()
	plane.size = Vector2(30000,30000)
	plane.subdivide_width = 128
	plane.subdivide_depth = 128
	var water := MeshInstance3D.new()
	water.name = "Ocean"
	water.mesh = plane
	water.position = Vector3(960,SEA_LEVEL,-225)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/worlds/star_orchard/sea_routes/ocean.gdshader")
	water.material_override = material
	add_child(water)
	_configure_world_water(material)
	var bed := MeshInstance3D.new()
	bed.name = "ConnectedSeaFloor"
	var box := BoxMesh.new()
	box.size = Vector3(30000,4,30000)
	bed.mesh = box
	# Keep the continuous fallback bed below the clamped terrain, never coplanar.
	bed.position = Vector3(960,SEA_FLOOR-2.35,-225)
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color("7c998e")
	sand.roughness = 1.0
	bed.material_override = sand
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed)
	var body := StaticBody3D.new()
	bed.add_child(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	body.add_child(collision)

func _travel_gate(destination: Vector3) -> void:
	gate_armed = false
	if is_instance_valid(flight):flight.land()
	var displacement := destination - player.global_position
	player.global_position = destination
	player.velocity = Vector3.ZERO
	if is_instance_valid(camera):camera.global_position += displacement
	_refresh_collisions()

func _build_terrain(tile: Dictionary) -> void:
	var x := int(tile.tile[0])
	var z := int(tile.tile[1])
	var painted_path := world_root.path_join("terrain_paint_layers_v1/ground_%d_%d.png" % [x, z])
	var entry := tile.duplicate()
	entry["ground_texture"] = painted_path
	var generated := FileAccess.file_exists(MainTerrain.height_path(tile.tile))
	if generated:
		MainTerrain.prepare_placements(self)
		entry["height"]=MainTerrain.height_path(tile.tile)
	super._build_terrain(entry)
	var texture := _orchard_texture(painted_path)
	if texture == null:return
	var terrain_node := get_child(get_child_count() - 1) as MeshInstance3D
	if terrain_node == null:return
	var mesh := terrain_node.mesh
	var material := (mesh.surface_get_material(0) as StandardMaterial3D).duplicate() as StandardMaterial3D
	material.albedo_texture = texture
	mesh.surface_set_material(0, material)
	if _town_polish_enabled("terrain"):
		var plaza := _town_polish_config("terrain/plaza_parameters.json")
		var target_tile: Array = plaza.get("tile", [])
		if target_tile.size() == 2 and int(target_tile[0]) == x and int(target_tile[1]) == z and bool(plaza.get("enabled", true)):
			var overlay := ShaderMaterial.new()
			overlay.shader = load(TOWN_POLISH_ROOT.path_join("terrain/plaza_paving.gdshader"))
			overlay.set_shader_parameter("base_texture", texture)
			overlay.set_shader_parameter("paving_texture", _orchard_texture(str(plaza.get("paving_texture", ""))))
			overlay.set_shader_parameter("tile_origin_xz", Vector2(x * terrain_size - origin.x, z * terrain_size - origin.y))
			overlay.set_shader_parameter("tile_size", terrain_size)
			var center: Array = plaza.get("plaza_center_xz", [0, 0])
			overlay.set_shader_parameter("plaza_center_xz", Vector2(center[0], center[1]))
			for key in ["inner_radius", "outer_radius", "inner_feather", "outer_feather", "paving_repeats_per_tile", "paving_strength"]:
				if plaza.has(key):overlay.set_shader_parameter(key, float(plaza[key]))
			if plaza.has("paving_tint"):
				var tint: Array = plaza.paving_tint
				overlay.set_shader_parameter("paving_tint", Vector3(tint[0], tint[1], tint[2]))
			mesh.surface_set_material(0, overlay)
			town_polish_status.terrain = true
	_raise_undersea_floor(terrain_node,Vector2i(x,z))
	if generated:
		MainTerrain.finish(terrain_node,Vector2i(x,z),texture,_town_polish_enabled("terrain"))

func _raise_undersea_floor(node: MeshInstance3D, tile: Vector2i) -> void:
	# Only the submerged runtime bed changes; land and on-disk source heights stay intact.
	var h: PackedFloat32Array = heights[tile].duplicate()
	var changed := false
	for index in h.size():
		if h[index] < SEA_FLOOR:
			h[index] = SEA_FLOOR
			changed = true
	if not changed:return
	var arrays: Array = node.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for z in 129:
		for x in 129:
			var index := z*129+x
			vertices[index].y = h[index]
			normals[index] = Vector3(h[z*129+maxi(x-1,0)]-h[z*129+mini(x+1,128)],2.0*terrain_size/128.0,h[maxi(z-1,0)*129+x]-h[mini(z+1,128)*129+x]).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var replacement := ArrayMesh.new()
	replacement.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	replacement.surface_set_material(0,node.mesh.surface_get_material(0))
	node.mesh = replacement
	heights[tile] = h
	for body in node.get_children():
		if body is StaticBody3D:
			for shape in body.get_children():
				if shape is CollisionShape3D:shape.shape = replacement.create_trimesh_shape()

func _orchard_texture(path: String) -> Texture2D:
	if orchard_textures.has(path):return orchard_textures[path]
	var texture := ResourceLoader.load(path) as Texture2D
	if texture == null:
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		push_error("Star Orchard texture failed to load: " + path)
		return null
	orchard_textures[path] = texture
	return texture

func _configure_visual_group(node: MultiMeshInstance3D, group: Dictionary, part: Dictionary) -> void:
	var model := str(group.path).get_file().get_basename()
	var tree_type := model.substr(model.find("_") + 1)
	var school := _school_for_tree(tree_type)
	if not school.is_empty():
		# Keep the source prototypes for collisions; replace only their visuals.
		node.visible = false
		if not group.get("v4_built", false):
			group["v4_built"] = true
			_build_v4_trees(node, group, school)
		return
	if not reused_materials.has(model):return
	var key: int = part.mesh.get_instance_id()
	if not reused_meshes.has(key):
		var mesh: Mesh = part.mesh.duplicate()
		var slots: Dictionary = reused_materials[model].materials
		for surface in mesh.get_surface_count():
			var original := mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null or not slots.has(original.resource_name):continue
			var material := original.duplicate() as StandardMaterial3D
			material.albedo_texture = load(str(slots[original.resource_name]))
			if str(slots[original.resource_name]).begins_with("res://assets/worlds/star_orchard/theme_v1/") and original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				var cutout := ShaderMaterial.new()
				cutout.shader = load("res://assets/worlds/star_orchard/theme_v1/" + ("cutout.gdshader" if original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else "blend.gdshader"))
				cutout.set_shader_parameter("painted", material.albedo_texture)
				cutout.set_shader_parameter("original_alpha", original.albedo_texture)
				cutout.set_shader_parameter("tint", original.albedo_color)
				cutout.set_shader_parameter("cutoff", original.alpha_scissor_threshold)
				cutout.set_shader_parameter("surface_roughness", original.roughness)
				mesh.surface_set_material(surface, cutout)
				continue
			mesh.surface_set_material(surface,material)
		reused_meshes[key] = mesh
	node.multimesh.mesh = reused_meshes[key]

func _school_for_tree(tree_type: String) -> String:
	match tree_type:
		"GreenTree01": return "life"
		"GreenTree02": return "fire"
		"GreenTree02_1": return "ice"
		"GreenTree03": return "storm"
		"GreenTree04": return "myth"
		"GreenTree05": return "death"
	return ""

# GLBs use metre-sized trees; source trees were authored in larger map units.
# Use one uniform conversion per school (A reference), preserving placement matrices
# and A/B size differences. Root origin remains exactly at the original placement.
func _v4_parts(school: String, variant: String) -> Array:
	var key := school + "_" + variant
	if not tree_v4_parts.has(key):
		var scene := load(TREE_V4_ROOT + "Tree_" + key + "_BranchGrownV4.glb") as PackedScene
		if scene == null:
			push_error("Missing orchard V4 tree: " + key)
			return []
		var instance := scene.instantiate()
		var parts: Array = []
		_collect_meshes(instance, Transform3D.IDENTITY, parts)
		instance.free()
		for part in parts:
			part.mesh = _paint_tree_mesh(part.mesh, school)
		tree_v4_parts[key] = parts
	return tree_v4_parts[key]

func _paint_tree_mesh(source: Mesh, school: String) -> Mesh:
	var original := source.surface_get_material(0) as StandardMaterial3D
	if original == null:return source
	var foliage := original.resource_name.ends_with("SpeciesFoliage")
	var bark := original.resource_name == "Orchard_bark" or original.resource_name.ends_with("FruitingShoots")
	if not foliage and not bark:return source
	var mesh := source.duplicate() as Mesh
	for surface in mesh.get_surface_count():
		var material := (mesh.surface_get_material(surface) as StandardMaterial3D).duplicate() as StandardMaterial3D
		# The generated albedo supplies its own color; do not darken it twice.
		material.vertex_color_use_as_albedo = false
		material.albedo_color = Color.WHITE
		material.albedo_texture = _orchard_texture(TREE_PAINT_ROOT + ("leaves_imagegen.png" if foliage else "bark_imagegen.png"))
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.roughness = 0.82 if foliage else 0.94
		if bark:
			# Local-space triplanar mapping preserves the original un-UV'd branches.
			material.uv1_triplanar = true
			material.uv1_scale = Vector3(0.7, 0.35, 0.7)
			material.uv1_triplanar_sharpness = 4.0
			if school == "ice":material.albedo_color = Color(0.72, 0.88, 1.0)
			elif school == "death":material.albedo_color = Color(0.8, 0.74, 0.88)
		mesh.surface_set_material(surface, material)
	return mesh

func _v4_scale(path: String, school: String) -> float:
	if not tree_v4_scales.has(school):
		var old_top := 0.0
		var new_top := 0.0
		for part in prototypes[path]:
			var bounds: AABB = part.transform * part.mesh.get_aabb()
			old_top = maxf(old_top, bounds.end.y)
		for part in _v4_parts(school, "A"):
			var bounds: AABB = part.transform * part.mesh.get_aabb()
			new_top = maxf(new_top, bounds.end.y)
		tree_v4_scales[school] = old_top / maxf(new_top, 0.001)
	return float(tree_v4_scales[school])

func _build_v4_trees(source: MultiMeshInstance3D, group: Dictionary, default_school: String) -> void:
	var batches: Dictionary = {}
	for i in group.transforms.size():
		var placement_id := int(group.placement_ids[i])
		var school := default_school
		if school == "life" and placement_id % 2 != 0:
			school = "balance"
		# Divide by two for life/balance so both schools receive both variants.
		var seed_id := placement_id / 2 if default_school == "life" else placement_id
		var variant := "A" if int(seed_id) % 2 == 0 else "B"
		var unit_scale := _v4_scale(str(group.path), school)
		var conversion := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * unit_scale), Vector3.ZERO)
		for part in _v4_parts(school, variant):
			var mesh: Mesh = part.mesh
			var key := str(mesh.get_instance_id())
			if not batches.has(key):batches[key] = {"mesh": mesh, "transforms": [], "school": school, "variant": variant}
			batches[key].transforms.append(group.transforms[i] * conversion * part.transform)
	for batch in batches.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = batch.mesh
		mm.instance_count = batch.transforms.size()
		for i in batch.transforms.size():mm.set_instance_transform(i, batch.transforms[i])
		var visual := MultiMeshInstance3D.new()
		visual.name = "TreeV4_" + str(batch.school) + "_" + str(batch.variant)
		visual.multimesh = mm
		visual.visibility_range_end = source.visibility_range_end
		visual.visibility_range_end_margin = source.visibility_range_end_margin
		visual.set_meta("orchard_v4", true)
		add_child(visual)
