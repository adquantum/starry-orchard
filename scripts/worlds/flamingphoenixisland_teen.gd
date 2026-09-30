extends "res://scripts/worlds/haqi_explorer.gd"

const POLISH_ROOT := "res://assets/worlds/flamingphoenixisland_teen/polish_pilot/"
var polish_enabled := true
var flame_count := 0
const RETEXTURE_ROOT := "res://assets/worlds/flamingphoenixisland_teen/retexture_v1/"
var retexture_enabled := true
var painted_models: Dictionary = {}
var painted_meshes: Dictionary = {}
var painted_counts: Dictionary = {}
var painted_terrain: Dictionary = {}
const ENVIRONMENT_ROOT := "res://assets/worlds/flamingphoenixisland_teen/environment_v2/"
var environment_repaint_enabled := true

func _ready() -> void:
	environment_repaint_enabled = not "--phoenix-environment-v2-off" in OS.get_cmdline_user_args()
	polish_enabled = not "--phoenix-polish-off" in OS.get_cmdline_user_args()
	retexture_enabled = not "--phoenix-retexture-off" in OS.get_cmdline_user_args()
	painted_models = JSON.parse_string(FileAccess.get_file_as_string(RETEXTURE_ROOT+"material_map.json"))
	if not "--phoenix-batch01-off" in OS.get_cmdline_user_args():
		var batch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/worlds/flamingphoenixisland_teen/retexture_batch01/material_map.json"))
		painted_models.merge(batch)
	if not "--phoenix-batch02-off" in OS.get_cmdline_user_args():
		var batch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/worlds/flamingphoenixisland_teen/retexture_batch02/material_map.json"))
		painted_models.merge(batch)
	world_root = "res://assets/worlds/flamingphoenixisland_teen/"
	if not "--phoenix-full-retexture-off" in OS.get_cmdline_user_args():
		painted_models.merge(JSON.parse_string(FileAccess.get_file_as_string(world_root+"retexture_full/material_map.json")))
		if retexture_enabled:
			painted_terrain = JSON.parse_string(FileAccess.get_file_as_string(world_root+"retexture_full/terrain_map.json"))
	if environment_repaint_enabled:
		painted_terrain.merge(JSON.parse_string(FileAccess.get_file_as_string(ENVIRONMENT_ROOT+"terrain_map.json")),true)
	world_title = "火鸟岛 · 少年版"
	capture_root = "res://docs/flamingphoenixisland_teen/"
	water_config_path = "res://resources/fusion_3d/flamingphoenixisland_teen_water.json"
	destinations = [Vector3(-189.1875, 3.59816, -382.785156), Vector3(-195, 30.381781, -150), Vector3(0, 73.097656, -90), Vector3(152, 64.039413, 220)]
	destination_names = ["原地图入口", "神坛道路", "神木高地", "北部祭坛"]
	distance = 14.0
	super._ready()

func _setup_view() -> void:
	super._setup_view()
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.background_color = Color("aa765a")
			child.environment.ambient_light_color = Color("e6d1b8")
		elif child is DirectionalLight3D:
			child.light_color = Color("ffe4c9")
			child.light_energy = 0.75
	if polish_enabled:
		for child in get_children():
			if child is WorldEnvironment:
				var env: Environment = child.environment
				var sky_material := ShaderMaterial.new()
				sky_material.shader = load(POLISH_ROOT + "sky.gdshader")
				if environment_repaint_enabled:
					sky_material.shader = load(ENVIRONMENT_ROOT+"sky.gdshader")
					sky_material.set_shader_parameter("painted_sky",load(ENVIRONMENT_ROOT+"sky_panorama.res"))
				env.sky = Sky.new()
				env.sky.sky_material = sky_material
				env.background_mode = Environment.BG_SKY
				env.ambient_light_color = Color("b7a4b9")
				env.ambient_light_energy = 0.62
				env.tonemap_exposure = 0.94
				env.fog_enabled = true
				env.fog_mode = Environment.FOG_MODE_DEPTH
				env.fog_depth_begin = 45.0
				env.fog_depth_end = 800.0
				env.fog_depth_curve = 1.35
				env.fog_density = 1.0
				env.fog_light_color = Color("c7946e")
				env.fog_light_energy = 1.0
				env.fog_sky_affect = 0.0
			elif child is DirectionalLight3D:
				child.light_color = Color("ffd4a5")
				child.light_energy = 0.82

func _build_terrain(t: Dictionary) -> void:
	var painted_path := world_root.path_join("terrain_paint_layers_v1/ground_%d_%d.png"%[int(t.tile[0]),int(t.tile[1])])
	if not "--terrain-layer-repaint-off" in OS.get_cmdline_user_args() and ResourceLoader.exists(painted_path):
		super._build_terrain(t)
		return
	var first := get_child_count()
	var visual_tile := t.duplicate()
	var source_path: String = str(t.get("ground_texture",t.get("texture","")))
	if painted_terrain.has(source_path):
		visual_tile["ground_texture" if t.has("ground_texture") else "texture"] = painted_terrain[source_path]
	super._build_terrain(visual_tile)
	if environment_repaint_enabled:
		var painted_material := ShaderMaterial.new()
		painted_material.shader = load(ENVIRONMENT_ROOT+"terrain.gdshader")
		painted_material.set_shader_parameter("source_ground",load(visual_tile.ground_texture))
		for i in range(first,get_child_count()):
			var node := get_child(i)
			if node is MeshInstance3D:node.material_override = painted_material
	if not polish_enabled:return
	var tile := Vector2(float(t.tile[0])*terrain_size-origin.x,float(t.tile[1])*terrain_size-origin.y)
	var bounds := Rect2(tile,Vector2.ONE*terrain_size).grow(100.0)
	var intersects := false
	for center in [Vector2(-189.1875,-382.785156),Vector2(-195,-150),Vector2(45,-240)]:
		if bounds.has_point(center):intersects = true
	if not intersects:return
	var weights_path := POLISH_ROOT + "ground_weights_%d_%d.res" % [t.tile[0],t.tile[1]]
	var weights: Texture2D = load(weights_path)
	var material := ShaderMaterial.new()
	material.shader = load(POLISH_ROOT + "terrain.gdshader")
	if environment_repaint_enabled:material.shader = load(ENVIRONMENT_ROOT+"terrain.gdshader")
	material.set_shader_parameter("source_ground",load(visual_tile.ground_texture))
	material.set_shader_parameter("source_weights",weights)
	var heat := ShaderMaterial.new()
	heat.shader = load(POLISH_ROOT + "heat.gdshader")
	heat.set_shader_parameter("source_weights",weights)
	if not "--phoenix-heat-off" in OS.get_cmdline_user_args():material.next_pass = heat
	for i in range(first,get_child_count()):
		var node := get_child(i)
		if node is MeshInstance3D:node.material_override = material

func _load_world() -> void:
	await super._load_world()
	if not polish_enabled:return
	var transforms: Array[Transform3D] = []
	for p in data.placements:
		if not str(p.model).ends_with("021_BrazierFire.glb"):continue
		var m: Array = p.matrix
		var tr := Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[3],m[4],m[5]),Vector3(m[6],m[7],m[8])),Vector3(p.position[0]+m[9],p.position[1]+m[10],p.position[2]+m[11]))
		var at := Vector2(tr.origin.x,tr.origin.z)
		if minf(minf(at.distance_to(Vector2(-189.1875,-382.785156)),at.distance_to(Vector2(-195,-150))),at.distance_to(Vector2(45,-240)))>100.0:continue
		# Original bowl bounds: x +/-1.484, base y=0, rim y=1.176.
		tr.origin = tr * Vector3(0,1.85,0)
		transforms.append(tr)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.75,2.7)
	var flame := ShaderMaterial.new()
	flame.shader = load(POLISH_ROOT + "flame.gdshader")
	quad.material = flame
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i,transforms[i])
		mm.set_instance_custom_data(i,Color(fmod(float(i)*0.618034,1.0),0,0,1))
	var flames := MultiMeshInstance3D.new()
	flames.name = "OriginalBrazierFlames"
	flames.multimesh = mm
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)
	flame_count = transforms.size()
	print("PHOENIX_ORIGINAL_BRAZIERS_LIT ",flame_count)

func _build_water() -> void:
	super._build_water()

func _configure_visual_group(node: MultiMeshInstance3D, group: Dictionary, part: Dictionary) -> void:
	var model: String = str(group.path).get_file().get_basename()
	if not retexture_enabled or not painted_models.has(model):return
	var key: int = part.mesh.get_instance_id()
	if not painted_meshes.has(key):
		var visual_mesh: Mesh = part.mesh.duplicate()
		var slots: Dictionary = painted_models[model].materials
		for surface in visual_mesh.get_surface_count():
			var original := visual_mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null or not slots.has(original.resource_name):continue
			var entry: Dictionary = slots[original.resource_name]
			var texture_path := str(entry.texture)
			var texture: Texture2D = load(texture_path if texture_path.begins_with("res://") else RETEXTURE_ROOT+texture_path)
			if bool(entry.cutout):
				var leaf := ShaderMaterial.new()
				leaf.shader = load(RETEXTURE_ROOT+"foliage.gdshader")
				leaf.set_shader_parameter("painted_texture",texture)
				leaf.set_shader_parameter("original_texture",original.albedo_texture)
				visual_mesh.surface_set_material(surface,leaf)
			else:
				var bark := original.duplicate() as StandardMaterial3D
				bark.albedo_texture = texture
				if not bool(entry.get("preserve_original_material",false)):
					bark.roughness = 0.9
				visual_mesh.surface_set_material(surface,bark)
		painted_meshes[key] = visual_mesh
	node.multimesh.mesh = painted_meshes[key]
	painted_counts[model] = int(painted_counts.get(model,0))+group.transforms.size()
