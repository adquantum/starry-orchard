extends "res://scripts/worlds/catalog_explorer.gd"
## Full authored slope preview; preserves source geometry, colors and density.
var imported_mesh_count := 0
var solid_mesh_count := 0

func _setup_view() -> void:
	super._setup_view()
	camera.fov = 55.0
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.background_color = Color("dcebe3")
			child.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			child.environment.ambient_light_color = Color("e5efd7")
			child.environment.ambient_light_energy = 0.65
		if child is DirectionalLight3D:
			child.light_energy = 1.0
			child.directional_shadow_max_distance = 400.0

func _load_world() -> void:
	label.text = "星界果园 · 正在载入完整露芽山坡…"
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file("res://assets/worlds/dewsprout_orchard/Dewsprout_Orchard.glb", state)
	if error != OK:
		push_error("Dewsprout GLB load failed: %s" % error)
		return
	var orchard := document.generate_scene(state) as Node3D
	orchard.name = "DewsproutAuthoredMap"
	add_child(orchard)
	_prepare_meshes(orchard)
	destinations = [Vector3(-8, 2.2, 92), Vector3(3, 6.8, 31), Vector3(-51, 13.25, -5), Vector3(48, 13.25, -4), Vector3(-12, 28.15, -62)]
	destination_names = ["入口营地", "水渠石桥", "西侧果林", "东侧果林", "山顶守护树"]
	fall_reset_height = -15.0
	await super._load_world()
	distance = 11.0
	pitch = -0.25
	loading_progress = 100.0
	print("DEWSPROUT_READY meshes=", imported_mesh_count, " solid_meshes=", solid_mesh_count)

func _prepare_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		imported_mesh_count += 1
		var mesh_node := node as MeshInstance3D
		# Flowers and fruit remain visual detail; solid geometry uses source triangles.
		var part := str(node.name)
		if not part.begins_with("08_") and not part.contains("flower") and not part.contains("fruit") and not part.ends_with("__water") and not part.ends_with("__foam"):
			mesh_node.create_trimesh_collision()
			solid_mesh_count += 1
	for child in node.get_children():
		_prepare_meshes(child)
