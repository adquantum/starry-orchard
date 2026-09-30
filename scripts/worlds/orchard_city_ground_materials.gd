extends RefCounted
## World projection for authored terrain/floors, with a contact map baked from
## the union of real paving triangles and adjacent grass at the same height.
const Textures = preload("res://scripts/worlds/orchard_main_terrain.gd")
const GROUND_SHADER = preload("res://assets/worlds/star_orchard/city_ground_v1/city_ground.gdshader")
const CONTACT_CONFIG := "res://resources/fusion_3d/orchard_city_ground_contacts_v2.json"
const KIND_MEADOW := 0
const KIND_PAVING := 1
const KIND_ROCK := 2
const KIND_SOIL := 3
const KIND_MASONRY := 4
const KIND_STAIRS := 5

var _materials: Dictionary = {}
var _city := "sky"
var _stats: Dictionary = {}
var _contact_data: Dictionary = {}
var _contact_texture: Texture2D

func apply_city(city_root: Node3D, city: String) -> Dictionary:
	_city = city
	_materials.clear()
	_stats = {"meshes": 0, "surfaces": 0, "meadow": 0, "paving": 0, "rock": 0,
		"soil": 0, "masonry": 0, "stairs": 0, "kept_painted_surfaces": 0, "missing_uv_repaired": 0,
		"ground_uv_unified": 0, "contact_map_enabled": false}
	_load_contacts()
	_visit(city_root)
	_stats["shared_materials"] = _materials.size()
	city_root.set_meta("city_ground_revision", 3)
	city_root.set_meta("city_ground_material_stats", _stats.duplicate())
	return _stats.duplicate()

func _load_contacts() -> void:
	_contact_data.clear()
	_contact_texture = null
	if not FileAccess.file_exists(CONTACT_CONFIG):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTACT_CONFIG))
	if not parsed is Dictionary:
		return
	var cities: Variant = parsed.get("cities", {})
	if not cities is Dictionary or not cities.has(_city):
		return
	var entry: Variant = cities[_city]
	if not entry is Dictionary:
		return
	var path := String(entry.get("texture", ""))
	var width := int(entry.get("width", 0))
	var height := int(entry.get("height", 0))
	if path.is_empty() or width <= 0 or height <= 0 or not FileAccess.file_exists(path):
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() != width * height * 4:
		return
	var image := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)
	_contact_texture = ImageTexture.create_from_image(image)
	_contact_data = entry.duplicate()
	_stats["contact_map_enabled"] = true

func _visit(node: Node) -> void:
	if node is MeshInstance3D:
		_paint_ground(node as MeshInstance3D)
	for child in node.get_children():
		if not child is StaticBody3D:
			_visit(child)

func _paint_ground(node: MeshInstance3D) -> void:
	if node.mesh == null or node.material_override != null:
		return
	var owner_name := String(node.name).get_slice("__", 0).to_upper()
	if owner_name.begins_with("C_") or owner_name.begins_with("V_"):
		owner_name = owner_name.substr(2)
	var changed := false
	for surface in range(node.mesh.get_surface_count()):
		var original := node.get_active_material(surface) as BaseMaterial3D
		if original == null or original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var kind := _surface_kind(owner_name, original.resource_name.to_upper())
		if kind < 0:
			continue
		if original.albedo_texture != null:
			var arrays := node.mesh.surface_get_arrays(surface)
			var uv: Variant = arrays[Mesh.ARRAY_TEX_UV] if arrays.size() > Mesh.ARRAY_TEX_UV else null
			if uv is PackedVector2Array and not uv.is_empty():
				if kind == KIND_ROCK:
					_stats["kept_painted_surfaces"] += 1
					continue
				# Grass beds and floor patches with local UVs still need the same
				# projection as adjoining ground, otherwise their rectangles show.
				_stats["ground_uv_unified"] += 1
			else:
				# Harbor's exported ground textures use texCoord:-1 and have no UV.
				_stats["missing_uv_repaired"] += 1
		# Mesh resources can be shared with architecture: override this instance
		# and surface only, without mutating mesh.surface_set_material().
		node.set_surface_override_material(surface, _material(kind, node))
		_stats["surfaces"] += 1
		_stats[["meadow", "paving", "rock", "soil", "masonry", "stairs"][kind]] += 1
		changed = true
	if changed:
		_stats["meshes"] += 1

func _surface_kind(owner_name: String, material_name: String) -> int:
	# Both loaders retain the source object's semantic owner before '__'.
	# Do not classify materials by color: the same limestone is used on walls.
	var is_land := owner_name.begins_with("LAND_") or owner_name.begins_with("SO_LAND_")
	var is_rock := owner_name.begins_with("ROCK_POL_LAND_")
	var is_soil := owner_name.begins_with("SOIL_") or owner_name.begins_with("SO_GARDEN_BED_")
	var is_meadow := owner_name.begins_with("EXP_") and owner_name.ends_with("_MEADOW")
	if is_land or is_rock or is_soil or is_meadow:
		if material_name.contains("MEADOW") or material_name.contains("ORCHARD_GRASS"):
			# A garden's grass must not change to an entire rectangular dirt patch
			# merely because the Blender object happened to be called SOIL/BED.
			return KIND_MEADOW
		if material_name.contains("CLIFF_") or material_name.contains("WEATHEREDROCK") or material_name.contains("COASTAL_STONE"):
			return KIND_ROCK
		if is_land and material_name.contains("LIMESTONE"):
			return KIND_PAVING
	if not _is_paved_owner(owner_name):
		return -1
	# The imported limestone flights have no UVs. They need carved stone on
	# treads, risers and support wedges, not cobbles above a raw cliff texture.
	if (owner_name.contains("STAIR") or owner_name.contains("STEPS")) and material_name.contains("LIMESTONE"):
		return KIND_STAIRS
	if owner_name.begins_with("ABUTMENT_") or owner_name.begins_with("SUPPORT_") or owner_name.contains("STAIR_SUPPORT_"):
		return KIND_MASONRY if material_name.contains("LIMESTONE") else -1
	if owner_name.begins_with("BRIDGE_POL_") and material_name.contains("AGEDLIMESTONE"):
		return KIND_MASONRY
	for token in ["PLAZA_PAVERS", "COBBLESTONE", "LIMESTONE", "AGEDLIMESTONE"]:
		if material_name.contains(token):
			return KIND_PAVING
	return -1

func _is_paved_owner(owner_name: String) -> bool:
	for token in ["RAIL", "POSTS", "PARAPET", "FENCE", "WATER", "FOAM"]:
		if owner_name.contains(token):
			return false
	for prefix in ["PATH_", "PAVING_", "PLAZA_", "PLATFORM_", "TERRACE_", "LANDING_", "BRIDGE_POL_", "ABUTMENT_", "SO_PATH_", "SO_PLAZA_"]:
		if owner_name.begins_with(prefix):
			return true
	if owner_name.begins_with("ARRAY_"):
		return owner_name.contains("PAVING") or owner_name.contains("STAIR") or owner_name.contains("STEPS")
	if owner_name.begins_with("SUPPORT_"):
		return owner_name.contains("STAIR")
	if owner_name.begins_with("EXP_"):
		return owner_name.ends_with("_TERRACE") or owner_name.ends_with("_ROUNDPLAZA")
	if owner_name.begins_with("POL_"):
		return owner_name.contains("_APPROACH_") or owner_name.contains("_DOOR_")
	if owner_name == "SO_R2_HARBOR_UPPERLANDING":
		return true
	if owner_name.begins_with("SO_R3_") and not owner_name.contains("_INST_"):
		for token in ["_PATH_", "APRON", "_COURT_", "_REST_", "LANDING", "STAIR_FLIGHT_", "STAIR_SUPPORT_"]:
			if owner_name.contains(token):
				return true
	return false

func _material(kind: int, owner: MeshInstance3D) -> ShaderMaterial:
	var across := Vector2.RIGHT
	var cache_key := str(kind)
	if kind == KIND_STAIRS:
		var local_across := owner.global_basis.z if String(owner.name).contains("ARRAY_POL_") else owner.global_basis.x
		across = Vector2(local_across.x, local_across.z).normalized()
		cache_key += "_%d" % roundi(atan2(across.y, across.x) * 1000.0)
	if _materials.has(cache_key):
		return _materials[cache_key] as ShaderMaterial
	var material := ShaderMaterial.new()
	material.resource_name = "Orchard_%s_Ground_%d" % [_city, kind]
	material.shader = GROUND_SHADER
	material.set_shader_parameter("surface_kind", kind)
	material.set_shader_parameter("stair_across", across)
	material.set_shader_parameter("grass_texture", Textures.texture("orchard_meadow_generated.png"))
	material.set_shader_parameter("soil_texture", Textures.texture("orchard_soil_generated.png"))
	material.set_shader_parameter("paving_texture", Textures.texture("orchard_stone_generated.png"))
	material.set_shader_parameter("cliff_texture", Textures.asset_texture("res://assets/worlds/star_orchard/coastal_art_v2/cliff_imagegen.png"))
	# Slightly cooler limestone above, warm worn stone at the harbor.
	material.set_shader_parameter("stone_tint", Vector3(0.93, 0.96, 1.0) if _city == "sky" else Vector3(1.0, 0.97, 0.90))
	material.set_shader_parameter("cliff_tint", Vector3(0.94, 0.98, 1.0) if _city == "sky" else Vector3(1.0, 0.99, 0.95))
	material.set_shader_parameter("grass_tint", Vector3(0.91, 0.98, 0.88))
	if _contact_texture != null:
		var origin: Array = _contact_data.get("origin", [0.0, 0.0])
		var size: Array = _contact_data.get("size", [1.0, 1.0])
		material.set_shader_parameter("contact_map_enabled", true)
		material.set_shader_parameter("contact_map", _contact_texture)
		material.set_shader_parameter("contact_origin", Vector2(float(origin[0]), float(origin[1])))
		material.set_shader_parameter("contact_size", Vector2(float(size[0]), float(size[1])))
		material.set_shader_parameter("contact_height_min", float(_contact_data.get("height_min", 0.0)))
		material.set_shader_parameter("contact_height_span", float(_contact_data.get("height_span", 1.0)))
	_materials[cache_key] = material
	return material
