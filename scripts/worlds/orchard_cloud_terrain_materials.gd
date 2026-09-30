extends RefCounted
## Baked orchard replacements for the six Cloud Fortress terrain heightfields.
## Source height samples, tile UVs and terrain positions remain owned by the caller.

const ROOT := "res://assets/worlds/star_orchard/cloud_repaint/"

static func material_for(source_world: String, source_path: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.roughness = 0.96
	material.albedo_color = Color.WHITE
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var selected := source_path
	if not "--orchard-cloud-art-off" in OS.get_cmdline_user_args():
		var candidate := ROOT.path_join(source_world).path_join(source_path.get_file())
		if ResourceLoader.exists(candidate):
			selected = candidate
	if ResourceLoader.exists(selected):
		material.albedo_texture = load(selected) as Texture2D
	return material
