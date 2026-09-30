extends RefCounted
## A/B silhouettes keep their original school UV slots and fruit materials.
static var meshes: Dictionary={}
static func variant_mesh(source: Mesh, alternate: bool) -> Mesh:
	if not alternate:return source
	var key := source.get_instance_id()
	if meshes.has(key):return meshes[key]
	var result := source.duplicate() as Mesh
	for i in result.get_surface_count():
		var original := source.surface_get_material(i) as StandardMaterial3D
		if original==null or not original.resource_name.ends_with("SpeciesFoliage"):continue
		var material := original.duplicate() as StandardMaterial3D
		material.albedo_texture=preload("res://scripts/worlds/orchard_main_terrain.gd").asset_texture("res://assets/worlds/star_orchard/coastal_art_v2/leaves_variant_imagegen.png")
		result.surface_set_material(i,material)
	meshes[key]=result
	return result
