extends "res://scripts/worlds/haqi_explorer.gd"

const RESTYLE_ROOT := "res://assets/worlds/frostroarisland_teen/restyle_v1/"
const POLISH_ROOT := "res://assets/worlds/darkforestisland_teen/polish_v2/"
var polish_enabled := true
var polish_config: Dictionary = {}
var variant_assignments: Dictionary = {}
var variant_materials: Dictionary = {}
var variant_instance_count := 0
var restyle_models: Dictionary = {}
var restyle_applied: Dictionary = {}

func _ready() -> void:
	polish_enabled = not "--forest-polish-off" in OS.get_cmdline_user_args()
	polish_config = JSON.parse_string(FileAccess.get_file_as_string(POLISH_ROOT + "config.json"))
	polish_enabled = polish_enabled and bool(polish_config.enabled)
	for item in polish_config.assignments: variant_assignments[int(item.index)] = item
	var entries: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/worlds/darkforestisland_teen/restyle_v1/material_map.json"))
	for entry in entries:
		restyle_models[str(entry.model)] = entry.materials
	world_root = "res://assets/worlds/darkforestisland_teen/"
	world_title = "黑暗森林 · 少年版"
	capture_root = "res://docs/darkforestisland_teen/"
	exploration_music_path = "res://assets/audio/music/area_darkforest.mp3"
	water_config_path = "res://resources/fusion_3d/darkforestisland_teen_water.json"
	destinations = [Vector3(7.613281, 15.14959, 162.53125), Vector3(-110, 9.93, -280), Vector3(-500, 11.680051, -50), Vector3(250, 55.43, 0)]
	destination_names = ["原地图入口", "森林营地", "西部遗迹", "灯塔高地"]
	distance = 14.0
	super._ready()

func _setup_view() -> void:
	super._setup_view()
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.background_mode = Environment.BG_SKY
			var forest_sky := Sky.new()
			var sky_material := ShaderMaterial.new()
			sky_material.shader = load("res://assets/worlds/darkforestisland_teen/legion_sky_v1/oriented_sky.gdshader")
			sky_material.set_shader_parameter("panorama",load("res://assets/worlds/darkforestisland_teen/legion_sky_v1/panorama.png"))
			forest_sky.sky_material = sky_material
			child.environment.sky = forest_sky
			child.environment.ambient_light_energy = 0.40
			child.environment.ambient_light_color = Color("a6b8b5")
		elif child is DirectionalLight3D:
			child.light_color = Color("d5d9ef")
			child.light_energy = 0.48

func _build_water() -> void:
	super._build_water()
	if "--forest-water-before" in OS.get_cmdline_user_args():
		var material: ShaderMaterial = get_node("Ocean").material_override
		var legacy := Shader.new()
		legacy = load("res://assets/shaders/legacy/haqi_water_before.gdshader")
		material.shader = legacy
		material.set_shader_parameter("deep_color",Color("26332b"))
		material.set_shader_parameter("rim_color",Color("586559"))


# Explicit model and material-name mapping; pending textures retain original materials.
# Vertex arrays, original GLBs, UVs and collision generation remain unchanged.
func _collect_meshes(node: Node, tr: Transform3D, parts: Array) -> void:
	var source_path := node.scene_file_path
	if restyle_models.has(source_path) and not restyle_applied.has(source_path):
		_apply_restyle(node, restyle_models[source_path])
		restyle_applied[source_path] = true
		print("FOREST_RESTYLE_MODEL ", source_path)
	super._collect_meshes(node, tr, parts)

func _apply_restyle(node: Node, slots: Array) -> void:
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
			if slot.is_empty() or str(slot.replacement).is_empty() or not ResourceLoader.exists(str(slot.replacement)):
				continue
			var material: Material
			if str(slot.alpha_mode) == "BLEND":
				var translucent := ShaderMaterial.new()
				translucent.shader = load("res://assets/worlds/darkforestisland_teen/restyle_v1/blend.gdshader")
				translucent.set_shader_parameter("painted_albedo", load(str(slot.replacement)))
				translucent.set_shader_parameter("original_alpha", load(str(slot.original)))
				translucent.set_shader_parameter("shoulder", 0.72 if polish_enabled else 0.0)
				material = translucent
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
			if polish_enabled and str(slot.alpha_mode) != "BLEND" and not (source_material is StandardMaterial3D and source_material.emission_enabled):
				material = _polished_material(load(str(slot.replacement)), load(str(slot.original)), str(slot.alpha_mode) == "MASK")
			material.resource_name = source_material.resource_name
			mesh_copy.surface_set_material(surface, material)
			print("FOREST_RESTYLE_SURFACE ", slot.name, " -> ", slot.replacement)
		node.mesh = mesh_copy
	for child in node.get_children():
		_apply_restyle(child, slots)


# Keep the base mesh, height samples and collision; override appearance only.
func _build_terrain(t: Dictionary) -> void:
	var first_new_child := get_child_count()
	super._build_terrain(t)
	var weights_path := "res://assets/worlds/darkforestisland_teen/restyle_v1/ground_weights_%d_%d.png" % [int(t.tile[0]),int(t.tile[1])]
	var painted_root := "res://assets/worlds/darkforestisland_teen/terrain_repaint_v1/"
	for i in range(first_new_child,get_child_count()):
		var surface := get_child(i) as MeshInstance3D
		if surface == null:continue
		var material := ShaderMaterial.new()
		material.shader=load(painted_root+"terrain.gdshader")
		material.set_shader_parameter("tile_size",terrain_size)
		for layer in ["grass","earth","rock","sand"]:
			material.set_shader_parameter(layer+"_texture",load(painted_root+layer+".png"))
		if ResourceLoader.exists(weights_path):
			material.set_shader_parameter("has_weights",true)
			material.set_shader_parameter("layer_weights",load(weights_path))
		var lava_root := "res://assets/worlds/darkforestisland_teen/lava_restore_v1/"
		var lava_path := lava_root+"ground_weights_%d_%d.png"%[int(t.tile[0]),int(t.tile[1])]
		if ResourceLoader.exists(lava_path):
			material.set_shader_parameter("has_lava",true)
			material.set_shader_parameter("lava_weights",load(lava_path))
			material.set_shader_parameter("lava_crust",load(lava_root+"huoshan.png"))
			material.set_shader_parameter("lava_molten",load(lava_root+"huoshan04.png"))
		surface.material_override=material

func _polished_material(painted: Texture2D, alpha: Texture2D, cutout: bool, family: int = -1) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(POLISH_ROOT + "props.gdshader")
	mat.set_shader_parameter("painted_albedo",painted)
	mat.set_shader_parameter("original_alpha",alpha)
	mat.set_shader_parameter("cutout",cutout)
	mat.set_shader_parameter("family",family)
	return mat

func _configure_visual_group(node: MultiMeshInstance3D, group: Dictionary, part: Dictionary) -> void:
	if not polish_enabled or not polish_config.models.has(str(group.path)): return
	var selected := false
	for index in group.placement_ids:
		if variant_assignments.has(index): selected=true;break
	if not selected: return
	var key := str(group.path)
	if not variant_materials.has(key):
		var spec: Dictionary=polish_config.models[key]
		variant_materials[key]=_polished_material(load(spec.painted),load(spec.alpha),true,int(spec.family))
	node.material_override=variant_materials[key]
	var mm := node.multimesh
	mm.instance_count=0;mm.use_custom_data=true;mm.instance_count=group.transforms.size()
	for i in group.transforms.size():
		var variant := 0
		if variant_assignments.has(group.placement_ids[i]):
			variant=int(variant_assignments[group.placement_ids[i]].variant)
			variant_instance_count+=1
		mm.set_instance_transform(i,group.transforms[i]*part.transform)
		mm.set_instance_custom_data(i,Color(float(variant),0,0,1))

func _load_world() -> void:
	await super._load_world()
	if polish_enabled:
		_polish_avatar()
		get_node("/root/Wardrobe").changed.connect(_on_forest_wardrobe_changed)
		print("FOREST_POLISH_VARIANTS ",variant_instance_count)

func _polish_avatar() -> void:
	# Materials are local to this world's avatar. Wardrobe textures/colors stay intact.
	for mesh in avatar.find_children("*","MeshInstance3D",true,false):
		for index in mesh.mesh.get_surface_count():
			var source: Material=mesh.get_active_material(index)
			if source is StandardMaterial3D and source.albedo_texture != null and not source.emission_enabled:
				var mat := _polished_material(source.albedo_texture,source.albedo_texture,source.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
				mesh.set_surface_override_material(index,mat)
			elif source is ShaderMaterial and (source.shader.resource_path.contains("teen_dye") or source.shader.resource_path.contains("teen_hair")):
				# Keep the same local material instance so later dye color updates still work.
				var code: String=source.shader.code
				var start:=code.find("void fragment()")
				if start<0:continue
				var brace:=code.find("{",start)
				var depth:=1
				var cursor:=brace+1
				while depth>0 and cursor<code.length():
					if code[cursor]=="{":depth+=1
					elif code[cursor]=="}":depth-=1
					cursor+=1
				var shader:=Shader.new()
				shader.code=code.insert(cursor-1,"\n ALBEDO /= 1.0 + max(ALBEDO.r,max(ALBEDO.g,ALBEDO.b))*0.72;\n")
				source.shader=shader

func _on_forest_wardrobe_changed(_school: String) -> void:
	# Avatar rebuilds synchronously on the same signal; apply after that completes.
	_polish_avatar.call_deferred()
