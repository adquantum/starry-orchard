extends RefCounted
const SHADER=preload("res://assets/materials/world_one_lowpoly/palette.gdshader")
static var palettes: Dictionary={}
static var materials: Dictionary={}
static func data() -> Dictionary:
	if palettes.is_empty():palettes=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/lowpoly_palette.json"))
	return palettes
static func apply(root: Node3D, school: String, architecture: bool=false) -> void:
	var colors: Array=data().schools.get(school,data().schools.balance)
	for node in root.find_children("*","MeshInstance3D",true,false):
		var mesh: MeshInstance3D=node
		if mesh.has_meta("para_static_painted"):continue
		for surface in mesh.mesh.get_surface_count():
			var original: Material=mesh.mesh.surface_get_material(surface)
			if not original is StandardMaterial3D:continue
			var key:=str(original.get_instance_id())+"/"+school+"/"+str(architecture)+("/"+str(mesh.mesh.get_instance_id()) if architecture else "")
			if not materials.has(key) or (materials[key] is WeakRef and materials[key].get_ref() == null):
				var material:=ShaderMaterial.new();material.shader=SHADER
				material.set_shader_parameter("has_map",original.albedo_texture!=null)
				material.set_shader_parameter("source_map",original.albedo_texture)
				material.set_shader_parameter("source_tint",original.albedo_color)
				material.set_shader_parameter("architecture",architecture)
				var bounds: AABB=mesh.get_aabb()
				material.set_shader_parameter("roof_start",bounds.position.y+bounds.size.y*0.48)
				material.set_shader_parameter("detail_lod",4.2 if architecture else 3.0)
				var names: Array=["shadow_color","body_color","light_color","accent_color","secondary_color","stone_color"]
				for i in names.size():material.set_shader_parameter(names[i],Color(colors[i]))
				materials[key]=weakref(material) if GraphicsSettings.is_low() else material
				mesh.set_surface_override_material(surface,material)
			mesh.set_surface_override_material(surface,materials[key].get_ref() if materials[key] is WeakRef else materials[key])
	root.set_meta("lowpoly_school",school)
	root.set_meta("lowpoly_architecture",architecture)
static var painted_specs: Dictionary={}
static func painted_data() -> Dictionary:
	if painted_specs.is_empty():
		var path := "res://resources/fusion_3d/mobile_lite/painted_monsters.json" if OS.has_feature("mobile_lite") else "res://resources/fusion_3d/painted_monsters.json"
		painted_specs=JSON.parse_string(FileAccess.get_file_as_string(path))
	return painted_specs
static func apply_painted(root: Node3D, id: String) -> bool:
	if not painted_data().has(id):return false
	var spec: Dictionary=painted_data()[id]
	var applied:=0
	for node in root.find_children("*","MeshInstance3D",true,false):
		var mesh: MeshInstance3D=node
		for surface in mesh.mesh.get_surface_count():
			var original: Material=mesh.mesh.surface_get_material(surface)
			if not original is StandardMaterial3D:continue
			var name: String=original.resource_name
			if name in spec.preserve_original:
				mesh.set_surface_override_material(surface,null)
				continue
			if not spec.materials.has(name):
				push_error("Unmapped painted material: "+id+"/"+name)
				continue
			var path: String=spec.materials[name]
			var key: String="painted/"+path+"/"+str(original.get_instance_id())
			if not materials.has(key) or (materials[key] is WeakRef and materials[key].get_ref() == null):
				var material:=ShaderMaterial.new()
				material.shader=preload("res://assets/materials/world_one_lowpoly/painted_uv.gdshader")
				material.set_shader_parameter("painted_map",load(path))
				material.set_shader_parameter("source_map",original.albedo_texture if not GraphicsSettings.is_low() or original.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else null)
				material.set_shader_parameter("use_cutout",original.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
				material.set_shader_parameter("alpha_cutoff",original.alpha_scissor_threshold)
				material.set_shader_parameter("source_alpha",original.albedo_color.a)
				materials[key]=weakref(material) if GraphicsSettings.is_low() else material
				mesh.set_surface_override_material(surface,material)
			mesh.set_surface_override_material(surface,materials[key].get_ref() if materials[key] is WeakRef else materials[key]);applied+=1
	root.set_meta("painted_material_count",applied)
	root.set_meta("painted_model",id)
	return applied>0

static func auto_apply(root: Node3D, id: String) -> void:
	if preload("res://scripts/fusion_3d/para_static_painted.gd").apply(root,id):return
	if apply_painted(root,id):return
	var monsters: Dictionary=data().monsters
	if monsters.has(id):apply(root,monsters[id],false)
	elif id.begins_with("castlehouse") or id.begins_with("castledoor"):apply(root,"balance",true)
