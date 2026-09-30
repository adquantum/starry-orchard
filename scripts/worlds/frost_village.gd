extends Node3D
## Additive village for the expanded copy only. Original GLBs stay untouched.
const ROOT := "res://assets/worlds/frostroarisland_expanded/village_v1/"
var materials: Dictionary = {}

func build(world: Node3D) -> void:
	name = "IcePlainVillage"
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT+"placements.json"))
	for kind in config.models:
		var definition: Dictionary = config.models[kind]
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(ROOT+str(definition.texture))
		material.roughness = 0.95
		material.metallic_specular = 0.15
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		materials[kind] = material
	for entry in config.houses:
		var definition: Dictionary = config.models[entry.kind]
		var house: Node3D = load(str(definition.model)).instantiate()
		house.name = str(entry.id)
		add_child(house)
		house.position = Vector3(float(entry.position[0]),float(entry.position[1]),float(entry.position[2]))
		house.rotation.y = float(entry.yaw)
		house.scale = Vector3(float(entry.scale[0]),float(entry.scale[1]),float(entry.scale[2]))
		_style(house, str(definition.slot), materials[entry.kind])
	print("FROST_VILLAGE_READY ",config.houses.size())

func _style(node: Node, slot: String, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var has_structure := false
		for i in mesh_node.mesh.get_surface_count():
			var original := mesh_node.mesh.surface_get_material(i)
			if original != null and original.resource_name == slot:
				mesh_node.set_surface_override_material(i,material)
				has_structure = true
		# Preserve original blend effects, but do not give glow planes collisions.
		if has_structure:mesh_node.create_trimesh_collision()
	for child in node.get_children():
		if not child is StaticBody3D:_style(child,slot,material)
