extends RefCounted
static var specs: Dictionary={}
static var cache: Dictionary={}
static func data() -> Dictionary:
	if specs.is_empty():
		var path := "res://resources/fusion_3d/mobile_lite/painted_static_assets.json" if OS.has_feature("mobile_lite") else "res://resources/fusion_3d/painted_static_assets.json"
		specs=JSON.parse_string(FileAccess.get_file_as_string(path))
	return specs
static func apply(root: Node3D,id: String) -> bool:
	if not data().has(id):return false
	var spec: Dictionary=data()[id]
	var count:=0
	for node in root.find_children("*","MeshInstance3D",true,false):
		var mesh: MeshInstance3D=node
		for surface in mesh.mesh.get_surface_count():
			var original:=mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if original==null:continue
			if not spec.materials.has(original.resource_name):
				mesh.set_surface_override_material(surface,null)
				continue
			var path: String=spec.materials[original.resource_name]
			var key:=path+"/"+str(original.get_instance_id())
			if not cache.has(key) or (cache[key] is WeakRef and cache[key].get_ref() == null):
				var material:=ShaderMaterial.new()
				var blend: bool=original.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA,BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]
				material.shader=load("res://assets/materials/para_static_painted/blend_uv.gdshader" if blend else "res://assets/materials/para_static_painted/opaque_uv.gdshader")
				material.set_shader_parameter("painted_map",load(path))
				material.set_shader_parameter("source_map",original.albedo_texture)
				material.set_shader_parameter("source_tint",original.albedo_color)
				material.set_shader_parameter("use_cutout",original.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR,BaseMaterial3D.TRANSPARENCY_ALPHA_HASH])
				material.set_shader_parameter("alpha_cutoff",original.alpha_scissor_threshold)
				cache[key]=weakref(material) if GraphicsSettings.is_low() else material
				mesh.set_surface_override_material(surface,material)
			mesh.set_surface_override_material(surface,cache[key].get_ref() if cache[key] is WeakRef else cache[key])
			count+=1
		# Later school tint passes must retain both the repainted slots and original effects.
		mesh.set_meta("para_static_painted",true)
	root.set_meta("para_static_painted_count",count)
	return true
