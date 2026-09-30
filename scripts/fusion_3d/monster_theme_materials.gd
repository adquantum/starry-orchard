extends RefCounted
## Call after the base world_one model has applied its normal materials.
## Overrides belong to MeshInstance3D only; source meshes and global maps stay intact.
const CONFIG := "res://resources/fusion_3d/monster_theme_variants_v1.json"
const PAINTED_SHADER := preload("res://assets/materials/world_one_lowpoly/painted_uv.gdshader")
static var _specs: Dictionary = {}

static func data() -> Dictionary:
	if _specs.is_empty() and FileAccess.file_exists(CONFIG):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
		if parsed is Dictionary:
			_specs = parsed.get("variants", {})
	return _specs

static func specification(variant_id: String) -> Dictionary:
	return data().get(variant_id, {}).duplicate(true)

static func apply(root: Node3D, variant_id: String) -> bool:
	return bool(apply_report(root, variant_id).get("ok", false))

static func apply_report(root: Node3D, variant_id: String) -> Dictionary:
	var spec := specification(variant_id)
	var result := {"ok": false, "variant_id": variant_id, "applied": 0, "missing": []}
	if root == null or spec.is_empty() or spec.get("status", "") != "ready":
		return result
	var slots: Dictionary = spec.get("materials", {})
	var pending: Array[Dictionary] = []
	var found: Dictionary = {}
	var nodes: Array[Node] = []
	if root is MeshInstance3D:
		nodes.append(root)
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null or not slots.has(original.resource_name):
				continue
			var path: String = slots[original.resource_name]
			var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
			if texture == null:
				result.missing.append(path)
				continue
			# Blended/effect surfaces are deliberately not converted to cutout.
			if original.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR]:
				result.missing.append("unsupported transparency: " + original.resource_name)
				continue
			var material := ShaderMaterial.new()
			material.resource_name = variant_id + "/" + original.resource_name
			material.shader = PAINTED_SHADER
			material.set_shader_parameter("painted_map", texture)
			material.set_shader_parameter("source_map", original.albedo_texture)
			material.set_shader_parameter("use_cutout", original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
			material.set_shader_parameter("alpha_cutoff", original.alpha_scissor_threshold)
			material.set_shader_parameter("source_alpha", original.albedo_color.a)
			pending.append({"mesh": mesh, "surface": surface, "material": material})
			found[original.resource_name] = true
	for slot in slots:
		if not found.has(slot):
			result.missing.append(slot)
	# Apply atomically: absent wing/body slots never produce a half-reskinned actor.
	if not result.missing.is_empty() or pending.is_empty():
		return result
	for item in pending:
		var mesh: MeshInstance3D = item.mesh
		var surface: int = item.surface
		var key := "monster_theme_previous_" + str(surface)
		if not mesh.has_meta(key):
			mesh.set_meta(key, {"material": mesh.get_surface_override_material(surface)})
		mesh.set_surface_override_material(surface, item.material)
	root.set_meta("monster_theme_variant_id", variant_id)
	result.applied = pending.size()
	result.ok = true
	return result

static func clear(root: Node3D) -> void:
	if root == null:
		return
	var nodes: Array[Node] = []
	if root is MeshInstance3D:
		nodes.append(root)
	nodes.append_array(root.find_children("*", "MeshInstance3D", true, false))
	for node in nodes:
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var key := "monster_theme_previous_" + str(surface)
			if mesh.has_meta(key):
				mesh.set_surface_override_material(surface, mesh.get_meta(key).get("material"))
				mesh.remove_meta(key)
	root.remove_meta("monster_theme_variant_id")
