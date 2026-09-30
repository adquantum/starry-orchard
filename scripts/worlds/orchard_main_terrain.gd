extends RefCounted
## Baked deterministic noise terrain; rendering, floor queries and collisions share it.
const ROOT := "res://assets/worlds/star_orchard/procedural_main_v1/"
const REVISION := "main_noise_v1"
static var _textures: Dictionary={}

static func height_path(tile: Array) -> String:
	return ROOT+"height_%d_%d.bin"%[tile[0],tile[1]]

static func prepare_placements(world: Node3D) -> void:
	if world.has_meta("orchard_generated_terrain"):return
	world.set_meta("orchard_generated_terrain",REVISION)
	var offsets: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"placement_offsets.json"))
	for key in offsets:
		world.data.placements[int(key)].position[1]+=float(offsets[key])

static func texture(filename: String) -> Texture2D:
	return asset_texture("res://assets/worlds/star_orchard/cloud_repaint/"+filename)

static func asset_texture(path: String) -> Texture2D:
	if _textures.has(path):return _textures[path]
	var source: Texture2D
	if ResourceLoader.exists(path):source=load(path) as Texture2D
	var result: Texture2D=source
	var image := source.get_image() if source!=null else Image.load_from_file(path)
	if not image.has_mipmaps():
		if image.is_compressed():image.decompress()
		image.generate_mipmaps()
		result=ImageTexture.create_from_image(image)
	if result==null:result=ImageTexture.create_from_image(image)
	_textures[path]=result
	return result

static func finish(node: MeshInstance3D, tile: Vector2i, base: Texture2D, plaza: bool) -> void:
	var suffix := "%d_%d.bin"%[tile.x,tile.y]
	var preserve := FileAccess.get_file_as_bytes(ROOT+"preserve_"+suffix).to_float32_array()
	var raw_normals := FileAccess.get_file_as_bytes(ROOT+"normals_"+suffix).to_float32_array()
	var arrays := node.mesh.surface_get_arrays(0)
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	for i in preserve.size():
		colors.append(Color(preserve[i],0,0,1))
		normals.append(Vector3(raw_normals[i*3],raw_normals[i*3+1],raw_normals[i*3+2]))
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_NORMAL]=normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new()
	material.shader=preload("res://assets/worlds/star_orchard/procedural_main_v1/ground.gdshader")
	material.set_shader_parameter("base_texture",base)
	material.set_shader_parameter("grass",texture("orchard_meadow_generated.png"))
	material.set_shader_parameter("soil",texture("orchard_soil_generated.png"))
	material.set_shader_parameter("cliff_texture",asset_texture("res://assets/worlds/star_orchard/coastal_art_v2/cliff_imagegen.png"))
	material.set_shader_parameter("paving",load("res://assets/worlds/star_orchard/terrain_paint_layers_v1/material_paving.png"))
	material.set_shader_parameter("plaza_enabled",plaza)
	mesh.surface_set_material(0,material)
	node.mesh=mesh
	for body in node.get_children():
		if body is StaticBody3D:
			for shape in body.get_children():
				if shape is CollisionShape3D:shape.shape=mesh.create_trimesh_shape()
