extends RefCounted
## Local appearance profiles for actors placed in Star Orchard.
const PROFILES := "res://resources/fusion_3d/star_orchard_npc_styles.json"
const PAINT := preload("res://assets/materials/world_one_lowpoly/orchard_npc_painted.gdshader")
static var cached: Dictionary = {}

static func profiles() -> Dictionary:
	if cached.is_empty() and FileAccess.file_exists(PROFILES):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILES))
		if parsed is Dictionary:cached = parsed.get("actors", {})
	return cached

static func prepare_entry(entry: Dictionary) -> void:
	var id := str(entry.get("actor_id", entry.get("npc_id", "")))
	var profile: Dictionary = profiles().get(id, {})
	if profile.has("school"):
		entry["school"] = profile.school
		var original_name := str(preload("res://scripts/fusion_3d/character_library.gd").entry(id).get("name", id))
		if str(entry.get("name", "")) in [original_name, "", str(profile.display_name)]:
			entry["name"] = profile.display_name

static func apply_to(holder: Node3D, id: String) -> int:
	var profile: Dictionary = profiles().get(id, {})
	if profile.is_empty():return 0
	var slots: Dictionary = profile.get("materials", {})
	var applied := 0
	var texture_slots: Dictionary = {}
	for value in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh.mesh == null:continue
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null or not slots.has(original.resource_name):continue
			var path := str(slots[original.resource_name])
			if not ResourceLoader.exists(path):
				push_error("Star Orchard NPC texture missing: " + path)
				continue
			var material := ShaderMaterial.new()
			material.shader = PAINT
			material.set_shader_parameter("painted_map", load(path))
			material.set_shader_parameter("source_map", original.albedo_texture)
			material.set_shader_parameter("use_cutout", original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
			material.set_shader_parameter("alpha_cutoff", original.alpha_scissor_threshold)
			material.set_shader_parameter("source_alpha", original.albedo_color.a)
			if id == "npc_kapaishangren_ec91f121":
				material.set_shader_parameter("card_map", load("res://assets/textures/frost_npcs/npc_kapaishangren_ec91f121-frost-empower-v2.png"))
				material.set_shader_parameter("card_rect", Vector4(0.646812, 0.7313805, 0.7114543, 0.8342457))
			mesh.set_surface_override_material(surface, material)
			applied += 1
			texture_slots[str(mesh.get_path()) + ":" + str(surface)] = path
	holder.set_meta("orchard_painted_materials", applied)
	holder.set_meta("orchard_texture_slots", texture_slots)
	holder.set_meta("orchard_display_name", profile.get("display_name", id))
	holder.set_meta("orchard_school", profile.get("school", ""))
	return applied
