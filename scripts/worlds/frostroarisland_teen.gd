extends "res://scripts/worlds/haqi_explorer.gd"

const RESTYLE_ROOT := "res://assets/worlds/frostroarisland_teen/restyle_v1/"
var variant_assignments: Dictionary = {}
var variant_model_names: Array = []
var variant_families: Dictionary = {}
var variant_materials: Dictionary = {}
var variants_enabled := false
var variant_instance_count := 0
var variant_group_count := 0
var environment_layers_enabled := true
var story_enabled := true
var story_props_enabled := false
var story_pilot: Node3D
var restyle_models: Dictionary = {}
var restyle_applied: Dictionary = {}

func _ready() -> void:
	var story_config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/frost_story_pilot.json"))
	story_enabled = bool(story_config.get("enabled",true)) and not "--frost-story-off" in OS.get_cmdline_user_args()
	story_props_enabled = story_enabled and bool(story_config.get("props_enabled",false))
	environment_layers_enabled = not GraphicsSettings.is_low() and not "--frost-environment-off" in OS.get_cmdline_user_args()
	var configuration := "res://resources/fusion_3d/frost_variants_pilot.json" if "--frost-pilot-only" in OS.get_cmdline_user_args() else "res://resources/fusion_3d/frost_variants_all.json"
	var pilot: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(configuration))
	variant_families = pilot.get("families",{})
	variants_enabled = bool(pilot.enabled) and not GraphicsSettings.is_low() and not "--frost-variants-off" in OS.get_cmdline_user_args()
	variant_model_names = pilot.models
	if variants_enabled:
		for assignment in pilot.assignments:
			variant_assignments[int(assignment.index)] = assignment
	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/worlds/frostroarisland_teen/restyle_all/material_map.json"))
	for entry in entries:
		restyle_models[str(entry.model)] = entry.materials
	world_root = "res://assets/worlds/frostroarisland_teen/"
	world_title = "冰霜岛"
	capture_root = "res://docs/frostroarisland_teen/"
	exploration_music_path = "res://assets/audio/music/area_frostroarisland.mp3"
	water_config_path = "res://resources/fusion_3d/frostroarisland_teen_water.json"
	destinations = [Vector3(-376.320312, 2.377283, -538.044922), Vector3(-90, 3, -320), Vector3(200, 45, 95), Vector3(-180, 4, 380)]
	destination_names = ["港口入口", "冰原聚落", "高地冰屋", "北岸营地"]
	yaw = 0.0
	distance = 14.0
	super._ready()
	if "--tower-v01-local" in OS.get_cmdline_user_args():
		_install_tower_test.call_deferred()

func _install_tower_test() -> void:
	while not ready_world:await get_tree().process_frame
	var tower := preload("res://scripts/tower_v01/tower_runtime.gd").new()
	tower.name = "TowerRuntimeRoot"
	tower.world = self
	add_child(tower)
	if "--tower-v01-cave" in OS.get_cmdline_user_args():
		player.position=Vector3(-153,_height(Vector3(-153,2,-145))+2,-145)
		player.velocity=Vector3.ZERO
		_refresh_collisions()

func _setup_view() -> void:
	super._setup_view()
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.background_mode = Environment.BG_SKY
			var frost_sky := Sky.new()
			var sky_material := ShaderMaterial.new()
			sky_material.shader = load("res://assets/worlds/frostroarisland_teen/environment_v2/sky.gdshader" if environment_layers_enabled else RESTYLE_ROOT + "sky.gdshader")
			frost_sky.sky_material = sky_material
			child.environment.sky = frost_sky
			child.environment.ambient_light_color = Color("b9d3e7") if environment_layers_enabled else Color("c4ddeb")
			if environment_layers_enabled:
				child.environment.ambient_light_energy = 0.62
				child.environment.tonemap_exposure = 0.95
				child.environment.fog_enabled = true
				child.environment.fog_mode = Environment.FOG_MODE_DEPTH
				child.environment.fog_depth_begin = 65.0
				child.environment.fog_depth_end = 650.0
				child.environment.fog_depth_curve = 1.2
				child.environment.fog_density = 0.62
				child.environment.fog_light_color = Color("a9c9de")
				child.environment.fog_light_energy = 0.75
				child.environment.fog_sky_affect = 0.0
		elif child is DirectionalLight3D:
			child.light_color = Color("fff0dc") if environment_layers_enabled else Color("eaf5ff")
			child.light_energy = 0.75

	if environment_layers_enabled and not "--frost-atmosphere-off" in OS.get_cmdline_user_args():
		_apply_atmosphere()

	# Painted panorama takes precedence over the earlier procedural sky versions.
	for child in get_children():
		if child is WorldEnvironment:
			var painted_sky := PanoramaSkyMaterial.new()
			painted_sky.panorama=load("res://assets/worlds/frostroarisland_teen/painted_sky_v1/panorama.png")
			painted_sky.energy_multiplier=0.8
			child.environment.sky.sky_material=painted_sky

# Atmosphere only: preserve terrain, prop materials, transforms and gameplay.
func _apply_atmosphere() -> void:
	for child in get_children():
		if child is WorldEnvironment:
			var env: Environment = child.environment
			var sky_material := ShaderMaterial.new()
			sky_material.shader = load("res://assets/worlds/frostroarisland_teen/atmosphere_v3/sky.gdshader")
			env.sky.sky_material = sky_material
			env.ambient_light_color = Color("b4c8db")
			env.ambient_light_energy = 0.55
			env.tonemap_exposure = 0.94
			env.fog_mode = Environment.FOG_MODE_DEPTH
			env.fog_depth_begin = 35.0
			env.fog_depth_end = 400.0
			env.fog_depth_curve = 0.9
			env.fog_density = 0.58
			env.fog_light_color = Color("b8cbd8")
			env.fog_light_energy = 0.75
			env.fog_sky_affect = 0.0
		elif child is DirectionalLight3D:
			child.light_color = Color("fff0de")
			child.light_energy = 0.80

	if not "--frost-atmosphere-tuning-off" in OS.get_cmdline_user_args():
		for child in get_children():
			if child is WorldEnvironment:
				child.environment.sky.sky_material.shader = load("res://assets/worlds/frostroarisland_teen/atmosphere_v4/sky.gdshader")
				# Preserve the near range; raise only the far-end attenuation.
				child.environment.fog_density = 0.63
				child.environment.fog_depth_curve = 1.05
			elif child is DirectionalLight3D:
				child.light_color = Color("ffeacf")

# Explicit model and material-name mapping; pending textures retain original materials.
# Vertex arrays, original GLBs, UVs and collision generation remain unchanged.
func _collect_meshes(node: Node, tr: Transform3D, parts: Array) -> void:
	var source_path := node.scene_file_path
	if restyle_models.has(source_path) and not restyle_applied.has(source_path):
		_apply_restyle(node, restyle_models[source_path], source_path.get_file().get_basename())
		restyle_applied[source_path] = true
		print("FROST_RESTYLE_MODEL ", source_path)
	super._collect_meshes(node, tr, parts)

func _apply_restyle(node: Node, slots: Array, model_name: String = "") -> void:
	if node is MeshInstance3D and node.mesh != null:
		var mesh_copy: Mesh = node.mesh.duplicate()
		for surface in mesh_copy.get_surface_count():
			var source_material: Material = node.mesh.surface_get_material(surface)
			if source_material == null:
				continue
			var slot: Dictionary = {}
			for candidate in slots:
				if str(candidate.name) == source_material.resource_name:
					slot = candidate
					break
			if slot.is_empty() or not ResourceLoader.exists(str(slot.replacement)):
				continue
			var material: Material
			if str(slot.name) == "WoodenEntrancePanel_FieldPVP_Snow":
				var sign_material := ShaderMaterial.new()
				sign_material.shader = load("res://assets/materials/world_one_lowpoly/painted_uv.gdshader")
				sign_material.set_shader_parameter("painted_map",load(str(slot.replacement)))
				# Mirror only the sign face; preserve the separate snow and wood islands.
				sign_material.set_shader_parameter("mirror_uv_rect",Vector4(0.1398,0.368732,0.998215,0.960079))
				sign_material.set_shader_parameter("painted_roughness",0.92)
				sign_material.set_shader_parameter("painted_specular",0.18)
				material = sign_material
			elif str(slot.alpha_mode) == "MASK":
				var leaf := ShaderMaterial.new()
				leaf.shader = load(RESTYLE_ROOT + "foliage.gdshader")
				leaf.set_shader_parameter("painted_albedo", load(str(slot.replacement)))
				leaf.set_shader_parameter("original_alpha", load(str(slot.original)))
				material = leaf
			else:
				var opaque: StandardMaterial3D = source_material.duplicate() if source_material is StandardMaterial3D else StandardMaterial3D.new()
				opaque.albedo_texture = load(str(slot.replacement))
				opaque.albedo_color = Color.WHITE
				opaque.roughness = 0.92
				opaque.metallic_specular = 0.18
				opaque.cull_mode = BaseMaterial3D.CULL_DISABLED
				material = opaque
			if variants_enabled and model_name in variant_model_names:
				var variation := ShaderMaterial.new()
				var family: String = variant_families.get(model_name,"wood" if model_name.contains("WoodStake") else "tree")
				variation.shader = load("res://scripts/worlds/frost_prop_variants.gdshader" if family in ["tree","wood"] else "res://scripts/worlds/frost_small_prop_variants.gdshader")
				if family not in ["tree","wood"]:
					variation.set_shader_parameter("prop_kind",{"box":0,"mushroom":1,"grass":2,"shrub":3}[family])
					var bounds: AABB = node.mesh.get_aabb()
					variation.set_shader_parameter("bottom",bounds.position.y)
					variation.set_shader_parameter("height",bounds.size.y)
				variation.set_shader_parameter("painted_albedo",load(str(slot.replacement)))
				variation.set_shader_parameter("original_alpha",load(str(slot.original)))
				variation.set_shader_parameter("cutout",str(slot.alpha_mode)=="MASK")
				if family in ["tree","wood"]:
					variation.set_shader_parameter("wood",model_name.contains("WoodStake"))
					var tree_kind := 1 if model_name.contains("Cedar_01") else (2 if model_name.contains("Cedar_02") else 3)
					variation.set_shader_parameter("tree_kind",tree_kind)
				variation.set_shader_parameter("base_roughness",0.96 if str(slot.alpha_mode)=="MASK" else 0.92)
				variant_materials[model_name] = variation
			material.resource_name = source_material.resource_name
			mesh_copy.surface_set_material(surface, material)
			print("FROST_RESTYLE_SURFACE ", slot.name, " -> ", slot.replacement)
		node.mesh = mesh_copy
	for child in node.get_children():
		_apply_restyle(child, slots, model_name)

func _build_terrain(t: Dictionary) -> void:
	var first_new_child := get_child_count()
	super._build_terrain(t)
	var weights_path := RESTYLE_ROOT + "ground_weights_%d_%d.png" % [int(t.tile[0]), int(t.tile[1])]
	var painted_root := "res://assets/worlds/frostroarisland_teen/terrain_repaint_v1/"
	for i in range(first_new_child, get_child_count()):
		var surface := get_child(i) as MeshInstance3D
		if surface == null:continue
		var material := ShaderMaterial.new()
		material.shader = load(painted_root + "terrain.gdshader")
		material.set_shader_parameter("tile_size",terrain_size)
		for layer in ["snow","road","rock","ice"]:
			material.set_shader_parameter(layer+"_texture",load(painted_root+layer+".png"))
		if ResourceLoader.exists(weights_path):
			material.set_shader_parameter("has_weights",true)
			material.set_shader_parameter("layer_weights",load(weights_path))
		surface.material_override = material

func _configure_visual_group(node: MultiMeshInstance3D, group: Dictionary, part: Dictionary) -> void:
	if not variants_enabled:return
	var selected := false
	for index in group.placement_ids:
		if variant_assignments.has(index):selected=true;break
	if not selected:return
	# Selected Top10 props each have one original material slot; reuse the variant material.
	node.material_override = variant_materials[str(group.path).get_file().get_basename()]
	var mm := node.multimesh
	mm.instance_count = 0
	mm.use_custom_data = true
	mm.instance_count = group.transforms.size()
	variant_group_count += 1
	for i in group.transforms.size():
		var tr: Transform3D = group.transforms[i]
		var variant := 0
		if variant_assignments.has(group.placement_ids[i]):
			var assignment: Dictionary = variant_assignments[group.placement_ids[i]]
			variant = int(assignment.variant)
			variant_instance_count += 1
		mm.set_instance_transform(i,tr * part.transform)
		mm.set_instance_custom_data(i,Color(float(variant),0.0,0.0,1.0))

func _load_world() -> void:
	await super._load_world()
	if story_props_enabled:
		story_pilot = load("res://scripts/worlds/frost_story_pilot.gd").new()
		add_child(story_pilot)
		story_pilot.build(self)
