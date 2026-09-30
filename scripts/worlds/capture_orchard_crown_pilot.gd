extends SceneTree

const OUTPUT := "res://docs/star_orchard/crown_colors_20260926/"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1600, 900)
	var world: Node3D = load("res://scenes/worlds/star_orchard.tscn").instantiate()
	world.set("production_mode", true)
	root.add_child(world)
	var wait_frames := 0
	while world.get("ready_world") != true and wait_frames < 2400:
		await process_frame
		wait_frames += 1
	if world.get("ready_world") != true:
		push_error("World did not finish loading")
		quit(1)
		return
	world.set_physics_process(false)
	var colors: Dictionary = world.get_meta("orchard_crown_colors", {})
	var positions: Array = colors.get("sample_positions", [])
	if positions.size() != 10:
		push_error("Crown capture needs ten reference trees; found %d" % positions.size())
		quit(1)
		return
	var center: Vector3 = positions[0]
	var forest_center := Vector3.ZERO
	for position in positions:
		forest_center += position
		if position.x > center.x:
			center = position
	forest_center /= float(positions.size())
	var views := [
		{"id": "single_close", "eye": center + Vector3(30, 14, 22), "aim": center + Vector3.UP * 6},
		{"id": "forest_far", "eye": forest_center + Vector3(64, 64, 110), "aim": forest_center + Vector3.UP * 10}
	]
	var color_material: ShaderMaterial = null
	for node in world.get_node("MountainShoulderForest").get_children():
		if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).material_override is ShaderMaterial:
			color_material = (node as MultiMeshInstance3D).material_override
			break
	assert(color_material != null)
	var report := {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(), "resolution": [root.size.x, root.size.y], "green_trees": colors.get("green", 0), "red_trees": colors.get("red", 0), "sample_positions": positions.map(func(p: Vector3) -> Array: return [p.x, p.y, p.z]), "views": []}
	for view in views:
		world.player.global_position = forest_center + Vector3.UP * 2
		world.camera.global_position = view.eye
		world.camera.look_at(view.aim)
		for enabled in [false, true]:
			color_material.set_shader_parameter("color_strength", 1.0 if enabled else 0.0)
			for i in 80:
				await process_frame
			var times: Array[float] = []
			for i in 90:
				var tick := Time.get_ticks_usec()
				await process_frame
				times.append(float(Time.get_ticks_usec() - tick) / 1000.0)
			times.sort()
			await RenderingServer.frame_post_draw
			var suffix := "after" if enabled else "before"
			var path := OUTPUT + str(view.id) + "_" + suffix + ".png"
			var error := root.get_texture().get_image().save_png(path)
			if error != OK:
				push_error("Could not save " + path)
				report["capture_error"] = error
			report.views.append({"id": view.id, "variant": suffix, "eye": [view.eye.x, view.eye.y, view.eye.z], "aim": [view.aim.x, view.aim.y, view.aim.z], "median_frame_ms": times[45], "p95_frame_ms": times[85], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "image": path})
	FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	color_material.set_shader_parameter("color_strength", 1.0)
	print("ORCHARD_CROWN_COLORS_CAPTURE ", JSON.stringify(report))
	quit()
