extends RefCounted
## Instance-only UV restyling. Source meshes, transforms and collision shapes stay intact.
const MAP_PATH := "res://assets/textures/orchard_cloud_props/material_map.json"
const CUTOUT := preload("res://assets/worlds/star_orchard/theme_v1/cutout.gdshader")
const BLEND := preload("res://assets/worlds/star_orchard/theme_v1/blend.gdshader")
var _mapping: Dictionary = {}
var _meshes: Dictionary = {}
var _textures: Dictionary = {}

func _init() -> void:
	if FileAccess.file_exists(MAP_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
		if parsed is Dictionary:
			_mapping = parsed.get("models", {})

func style_mesh(source_model_path: String, source_mesh: Mesh) -> Mesh:
	if "--orchard-cloud-art-off" in OS.get_cmdline_user_args():
		return source_mesh
	if source_mesh == null or not _mapping.has(source_model_path):
		return source_mesh
	var key := source_model_path + ":" + str(source_mesh.get_instance_id())
	if _meshes.has(key):
		return _meshes[key]
	var result := source_mesh.duplicate() as Mesh
	var slots: Dictionary = _mapping[source_model_path].get("materials", {})
	for surface in result.get_surface_count():
		var original := source_mesh.surface_get_material(surface) as StandardMaterial3D
		if original == null or not slots.has(original.resource_name):
			continue
		var paint_path := str(slots[original.resource_name])
		var replacement := _texture(paint_path)
		if replacement == null:
			continue
		if original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and original.albedo_texture != null:
			# Painted RGB is independent of the original cutout/blend silhouette.
			var shader_material := ShaderMaterial.new()
			shader_material.shader = CUTOUT if original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else BLEND
			shader_material.set_shader_parameter("painted", replacement)
			shader_material.set_shader_parameter("original_alpha", original.albedo_texture)
			shader_material.set_shader_parameter("tint", original.albedo_color)
			shader_material.set_shader_parameter("cutoff", original.alpha_scissor_threshold)
			shader_material.set_shader_parameter("surface_roughness", 0.9)
			result.surface_set_material(surface, shader_material)
		else:
			var material := original.duplicate() as StandardMaterial3D
			material.albedo_texture = replacement
			if "orchard_cloud_props" in paint_path and not ("Tree" in paint_path or "Cedar" in paint_path):
				# Keep the pastel stone below the scene's bright sun shoulder.
				material.albedo_color = original.albedo_color * Color(0.74, 0.78, 0.84, 1.0)
			material.roughness = 0.9
			material.normal_enabled = false
			material.emission_enabled = false
			result.surface_set_material(surface, material)
	_meshes[key] = result
	return result

func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var texture: Texture2D
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path) and path.get_extension().to_lower() == "png":
		# Freshly generated PNGs are usable before an editor import pass.
		var source_image := Image.load_from_file(path)
		if source_image != null:
			source_image.generate_mipmaps()
			texture = ImageTexture.create_from_image(source_image)
	_textures[path] = texture
	return texture
