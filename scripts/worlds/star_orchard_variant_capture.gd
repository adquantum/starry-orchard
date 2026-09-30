extends SceneTree
const VARIANTS = preload("res://scripts/worlds/star_orchard_variant_materials.gd")
var actors: Array[Node3D] = []
var report: Array = []

func _init() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1920, 1080)
	var scene := Node3D.new()
	root.add_child(scene)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("303848")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.7
	environment.environment = env
	scene.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.light_energy = 1.0
	scene.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.4
	scene.add_child(camera)
	camera.position = Vector3(7.6, -0.9, 30)
	camera.look_at(Vector3(7.6, -0.9, 0))
	var ids := VARIANTS.data().keys()
	for i in ids.size():
		var spec := VARIANTS.specification(ids[i])
		var actor: Node3D = load("res://scripts/fusion_3d/world_one_monster.gd").new()
		actor.model_id = spec.model_id
		scene.add_child(actor)
		actors.append(actor)
		actor.position = Vector3((i % 5) * 3.8, -(i / 5) * 4.4, 0)
		actor.face_center(actor.position + Vector3(0, 0, 10))
		var skeletons_before := actor.find_children("*", "Skeleton3D", true, false)
		var snapshot: Array = []
		for node in actor.find_children("*", "MeshInstance3D", true, false):
			snapshot.append([node, node.mesh, node.skin])
		var result := VARIANTS.apply_report(actor, ids[i])
		result["rig_unchanged"] = skeletons_before == actor.find_children("*", "Skeleton3D", true, false)
		for item in snapshot:
			result.rig_unchanged = result.rig_unchanged and item[0].mesh == item[1] and item[0].skin == item[2]
		result["animations"] = Array(actor.animation.get_animation_list()) if actor.animation else []
		for node in actor.find_children("*", "MeshInstance3D", true, false):
			for surface in node.mesh.get_surface_count():
				var original: Material = node.mesh.surface_get_material(surface)
				if spec.materials.has(original.resource_name):
					var applied: ShaderMaterial = node.get_surface_override_material(surface)
					assert(applied.get_shader_parameter("painted_map").resource_path == spec.materials[original.resource_name])
					assert(applied.get_shader_parameter("source_map") == original.albedo_texture)
		assert(result.ok and result.rig_unchanged)
		report.append(result)
		var label := Label3D.new()
		label.text = spec.display_name
		label.font_size = 30
		label.pixel_size = 0.004
		label.position = actor.position + Vector3(0, -0.25, 1)
		scene.add_child(label)
	for i in 12:
		await process_frame
	await capture("front")
	for actor in actors:
		if actor.animation:
			actor.animation.pause()
		VARIANTS.clear(actor)
	await capture("base")
	for i in actors.size():
		assert(VARIANTS.apply(actors[i], ids[i]))
	for actor in actors:
		actor.rotation.y += 0.65
	for i in 8:
		await process_frame
	await capture("side")
	for actor in actors:
		actor.play_cast(0.8)
	await create_timer(0.28).timeout
	await capture("cast")
	var file := FileAccess.open("res://assets/textures/star_orchard_variants/validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("ORCHARD_VARIANTS_CAPTURE_OK ", report.size())
	quit()

func capture(view: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://assets/textures/star_orchard_variants/preview-" + view + ".png")
