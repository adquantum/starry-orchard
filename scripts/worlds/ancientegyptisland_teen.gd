extends "res://scripts/worlds/haqi_explorer.gd"

const RETEXTURE_ROOT := "res://assets/worlds/ancientegyptisland_teen/retexture_v1/"
var retexture_enabled := true
var painted_models: Dictionary = {}
var painted_meshes: Dictionary = {}
var painted_terrain: Dictionary = {}

func _ready() -> void:
	retexture_enabled = not "--desert-retexture-off" in OS.get_cmdline_user_args()
	if retexture_enabled:
		painted_models = JSON.parse_string(FileAccess.get_file_as_string(RETEXTURE_ROOT+"material_map.json"))
		painted_terrain = JSON.parse_string(FileAccess.get_file_as_string(RETEXTURE_ROOT+"terrain_map.json"))
	world_root = "res://assets/worlds/ancientegyptisland_teen/"
	world_title = "古埃及岛 · 少年版"
	capture_root = "res://docs/ancientegyptisland_teen/"
	water_config_path = "res://resources/fusion_3d/ancientegyptisland_teen_water.json"
	destinations = [Vector3(-246.634766, 3.75, -370.294922), Vector3(-304, 48.07468, -84), Vector3(-30, 15.062002, -61), Vector3(40, 56.512794, 220)]
	destination_names = ["原地图入口", "沙漠营地", "神庙遗迹", "高地石墙"]
	distance = 14.0
	super._ready()

func _setup_view() -> void:
	super._setup_view()
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.background_color = Color("d9b996")
			child.environment.ambient_light_color = Color("e8d8bb")
			if retexture_enabled:
				var sky_material := ShaderMaterial.new()
				sky_material.shader = load(RETEXTURE_ROOT+"sky.gdshader")
				sky_material.set_shader_parameter("painted_sky",load(RETEXTURE_ROOT+"sky_panorama.res"))
				child.environment.sky = Sky.new()
				child.environment.sky.sky_material = sky_material
				child.environment.background_mode = Environment.BG_SKY
		elif child is DirectionalLight3D:
			child.light_color = Color("fff0d7")
			child.light_energy = 0.75

func _build_water() -> void:
	super._build_water()

func _build_terrain(t: Dictionary) -> void:
	var first_new_child := get_child_count()
	super._build_terrain(t)
	if not retexture_enabled:return
	var root := "res://assets/worlds/ancientegyptisland_teen/terrain_repaint_v2/"
	var weights_path := root+"ground_weights_%d_%d.png"%[int(t.tile[0]),int(t.tile[1])]
	for i in range(first_new_child,get_child_count()):
		var surface := get_child(i) as MeshInstance3D
		if surface == null:continue
		var material := ShaderMaterial.new()
		material.shader=load(root+"terrain.gdshader")
		material.set_shader_parameter("tile_size",terrain_size)
		for layer in ["sand","earth","rock","grass"]:
			material.set_shader_parameter(layer+"_texture",load(root+layer+".png"))
		if ResourceLoader.exists(weights_path):
			material.set_shader_parameter("has_weights",true)
			material.set_shader_parameter("layer_weights",load(weights_path))
		surface.material_override=material

func _configure_visual_group(node: MultiMeshInstance3D, group: Dictionary, part: Dictionary) -> void:
	var model := str(group.path).get_file().get_basename()
	if not retexture_enabled or not painted_models.has(model):return
	var key: int = part.mesh.get_instance_id()
	if not painted_meshes.has(key):
		var visual_mesh: Mesh = part.mesh.duplicate()
		var slots: Dictionary = painted_models[model].materials
		for surface in visual_mesh.get_surface_count():
			var original := visual_mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null or not slots.has(original.resource_name):continue
			var material := original.duplicate() as StandardMaterial3D
			material.albedo_texture = load(str(slots[original.resource_name].texture))
			visual_mesh.surface_set_material(surface,material)
		painted_meshes[key] = visual_mesh
	node.multimesh.mesh = painted_meshes[key]
