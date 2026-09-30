extends Node3D
## Small, local atmosphere using Godot's built-in particle systems.
## Forest positions come from successfully planted trees. All effects are visual;
## no particle collision, lights, physics queries or scene-wide fog are created.
const FOUNTAIN_OWNER := "C_SO_INST_SO_01_Central_Plaza_0001_fountain"
const GPU_PARTICLE_LIMIT := 192
const CPU_PARTICLE_LIMIT := 96
const MAX_GROVES := 96
var _world: Node3D
var _landscape: Node3D
var _spec: Dictionary = {}
var _entries: Array[Dictionary] = []
var _meshes: Dictionary = {}
var _cpu := false
var _enabled := true
var _budget := GPU_PARTICLE_LIMIT
var _refresh_in := 0.0
var _counts := {"groves": 0, "petal_emitters": 0, "mote_emitters": 0, "fountain_emitters": 0}


func install(world: Node3D, landscape: Node3D) -> void:
	set_process(false)
	if world.has_meta("orchard_ambient_life"):
		return
	_world = world
	_landscape = landscape
	var config: Dictionary = landscape.settings
	_spec = config.get("ambient_life", {})
	_enabled = bool(_spec.get("enabled", true)) and config.has("sculpted_landform")
	if OS.get_cmdline_user_args().has("--orchard-no-ambient"):
		_enabled = false
	if not _enabled:
		world.set_meta("orchard_ambient_life", {"enabled": false, "active_particles": 0})
		return
	name = "OrchardAmbientLife"
	_cpu = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var hard_limit := CPU_PARTICLE_LIMIT if _cpu else GPU_PARTICLE_LIMIT
	_budget = clampi(int(_spec.get("active_particle_budget", hard_limit)), 24, hard_limit)
	_meshes["petals"] = _sprite(Vector2(0.40, 0.21), false)
	_meshes["motes"] = _sprite(Vector2(0.16, 0.16), true)
	_meshes["mist"] = _sprite(Vector2(0.52, 0.38), true)
	var dressing: Dictionary = world.get_meta("orchard_mountain_dressing", {})
	var anchors: Array = world.get_meta("orchard_local_ambient_anchors", []).duplicate()
	anchors.append_array(dressing.get("ambient_anchors", []))
	var grove_limit := MAX_GROVES if world.has_meta("orchard_local_ambient_anchors") else int(_spec.get("grove_limit",10))
	var chosen: Array[Vector3] = []
	for value in anchors:
		if chosen.size() >= clampi(grove_limit,0,MAX_GROVES):
			break
		var point := Vector3.ZERO
		if value is Vector3:
			point = value
		elif value is Array and value.size() >= 3:
			point = Vector3(float(value[0]), float(value[1]), float(value[2]))
		else:
			continue
		# Imported tree origins can sit below their visible roots. Anchor to
		# the actual terrain so petals remain around the lower canopy.
		point.y = landscape.height_at(Vector2(point.x, point.z)) + 6.0
		var crowded := false
		for previous in chosen:
			if Vector2(previous.x, previous.z).distance_to(Vector2(point.x, point.z)) < 28.0:
				crowded = true
		if crowded:
			continue
		chosen.append(point)
		_add_grove(point, chosen.size() - 1)
	if bool(_spec.get("fountain_mist", true)):
		var harbor := world.get_node_or_null("BlenderHarborCity")
		if harbor != null:
			_add_fountain(harbor)
	_publish_counts(0, 0)
	set_process(not _entries.is_empty())
	# The explorer creates its camera after install(). Until then every emitter
	# remains hidden, with emission and simulation stopped.


func set_effects_enabled(enabled: bool) -> void:
	_enabled = enabled
	_refresh_in = 0.0
	if not enabled:
		for entry in _entries:
			_set_active(entry, false)
		_publish_counts(0, 0)
	set_process(enabled and not _entries.is_empty())


func _process(delta: float) -> void:
	_refresh_in -= delta
	if _refresh_in > 0.0:
		return
	_refresh_in = 0.35
	var camera := get_viewport().get_camera_3d()
	if camera == null or not _enabled:
		for entry in _entries:
			_set_active(entry, false)
		_publish_counts(0, 0)
		return
	var candidates: Array[Dictionary] = []
	for entry in _entries:
		var emitter: Node3D = entry.node
		var distance := camera.global_position.distance_to(emitter.global_position)
		var limit: float = float(entry.distance) + (24.0 if bool(entry.active) else 0.0)
		if distance < limit:
			# Spend the limited particle budget on the grove in view before those
			# behind the camera; nearby offscreen emitters used to consume it all.
			var behind := camera.is_position_behind(emitter.global_position)
			candidates.append({"entry": entry, "distance": distance + (230.0 if behind else 0.0)})
		else:
			_set_active(entry, false)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.distance) < float(b.distance))
	var active_particles := 0
	var active_emitters := 0
	for candidate in candidates:
		var entry: Dictionary = candidate.entry
		var amount: int = entry.amount
		var active := active_particles + amount <= _budget
		_set_active(entry, active)
		if active:
			active_particles += amount
			active_emitters += 1
	_publish_counts(active_particles, active_emitters)


func _add_grove(point: Vector3, index: int) -> void:
	# Anchors already sit near half crown height. A short lifetime and shallow
	# downward drift keep the leaves in the trees, above the ground.
	var tint := Color(0.99, 0.79, 0.53, 0.72) if index % 3 else Color(1.0, 0.73, 0.76, 0.73)
	_add_emitter("ForestPetals%02d" % index, "petals", point + Vector3.UP * 1.2, {
		"amount": 16 if _cpu else 24, "lifetime": 8.0,
		"extents": Vector3(9.0, 1.5, 9.0), "direction": Vector3(0.7, -0.16, 0.4),
		"spread": 34.0, "velocity": Vector2(0.28, 0.70), "gravity": Vector3(0.015, -0.042, 0.007),
		"angular": Vector2(-42.0, 48.0), "size": Vector2(0.72, 1.32),
		"color": tint, "distance": 230.0,
		"bounds": AABB(Vector3(-15.0, -8.0, -15.0), Vector3(37.0, 13.0, 35.0))
	})
	_counts.petal_emitters += 1
	_add_emitter("ForestMotes%02d" % index, "motes", point - Vector3.UP * 1.7, {
		"amount": 8 if _cpu else 12, "lifetime": 6.0,
		"extents": Vector3(9.5, 1.1, 9.5), "direction": Vector3(0.4, 0.7, 0.25),
		"spread": 58.0, "velocity": Vector2(0.05, 0.18), "gravity": Vector3(0.0, 0.025, 0.0),
		"angular": Vector2(-8.0, 8.0), "size": Vector2(0.75, 1.65),
		"color": Color(0.88, 1.0, 0.69, 0.48), "distance": 145.0,
		"bounds": AABB(Vector3(-12.0, -3.0, -12.0), Vector3(25.0, 9.0, 25.0))
	})
	_counts.mote_emitters += 1
	_counts.groves += 1


func _add_fountain(root: Node) -> void:
	var water := _find_fountain_water(root)
	if water == null:
		return
	var bounds: AABB = water.mesh.get_aabb()
	if bounds.size.x <= 0.1 or bounds.size.z <= 0.1:
		return
	var center := bounds.get_center()
	# This named mesh contains the vertical water jets as well as the pool.
	# Its lower face is the pool surface; using end.y would put mist in the air.
	center.y = bounds.position.y + 0.38
	var radius := minf(bounds.size.x, bounds.size.z) * 0.30
	for i in 4:
		var angle := float(i) * TAU / 4.0 + 0.35
		var local_point := center + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var point := water.to_global(local_point)
		_add_emitter("FountainMist%d" % i, "mist", point, {
			"amount": 6 if _cpu else 9, "lifetime": 2.3,
			"extents": Vector3(0.80, 0.12, 0.80), "direction": Vector3.UP,
			"spread": 36.0, "velocity": Vector2(0.22, 0.64), "gravity": Vector3(0.02, -0.08, 0.01),
			"angular": Vector2(-12.0, 12.0), "size": Vector2(0.65, 1.15),
			"color": Color(0.72, 0.91, 1.0, 0.30), "distance": 175.0,
			"bounds": AABB(Vector3(-2.5, -1.0, -2.5), Vector3(5.5, 4.0, 5.5))
		})
		_counts.fountain_emitters += 1


func _find_fountain_water(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.mesh != null:
		var label := str(node.name)
		if label.begins_with(FOUNTAIN_OWNER) and label.ends_with("__water_fps3_a006_01"):
			return node
	for child in node.get_children():
		var result := _find_fountain_water(child)
		if result != null:
			return result
	return null


func _add_emitter(label: String, mesh_key: String, point: Vector3, spec: Dictionary) -> void:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.16, 0.64, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color.WHITE, Color(1, 1, 1, 0.78), Color(1, 1, 1, 0)])
	var velocity: Vector2 = spec.velocity
	var angular: Vector2 = spec.angular
	var size: Vector2 = spec.size
	var emitter: GeometryInstance3D
	if _cpu:
		var particles := CPUParticles3D.new()
		particles.emitting = false
		particles.amount = int(spec.amount)
		particles.lifetime = float(spec.lifetime)
		particles.mesh = _meshes[mesh_key]
		particles.direction = spec.direction
		particles.spread = float(spec.spread)
		particles.gravity = spec.gravity
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = spec.extents
		particles.initial_velocity_min = velocity.x
		particles.initial_velocity_max = velocity.y
		particles.angular_velocity_min = angular.x
		particles.angular_velocity_max = angular.y
		particles.angle_min = -180.0
		particles.angle_max = 180.0
		particles.scale_amount_min = size.x
		particles.scale_amount_max = size.y
		particles.color = spec.color
		particles.color_ramp = fade
		particles.local_coords = true
		particles.fixed_fps = 24
		particles.preprocess = 0.0
		particles.speed_scale = 0.0
		particles.randomness = 0.78
		particles.visibility_aabb = spec.bounds
		particles.use_fixed_seed = true
		particles.seed = 9262026 + _entries.size() * 71
		emitter = particles
	else:
		var particles := GPUParticles3D.new()
		particles.emitting = false
		particles.amount = int(spec.amount)
		particles.lifetime = float(spec.lifetime)
		particles.draw_pass_1 = _meshes[mesh_key]
		particles.local_coords = true
		particles.fixed_fps = 30
		particles.preprocess = 0.0
		particles.speed_scale = 0.0
		particles.randomness = 0.78
		particles.visibility_aabb = spec.bounds
		particles.use_fixed_seed = true
		particles.seed = 9262026 + _entries.size() * 71
		var process := ParticleProcessMaterial.new()
		process.direction = spec.direction
		process.spread = float(spec.spread)
		process.gravity = spec.gravity
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		process.emission_box_extents = spec.extents
		process.initial_velocity_min = velocity.x
		process.initial_velocity_max = velocity.y
		process.angular_velocity_min = angular.x
		process.angular_velocity_max = angular.y
		process.angle_min = -180.0
		process.angle_max = 180.0
		process.scale_min = size.x
		process.scale_max = size.y
		process.color = spec.color
		var ramp := GradientTexture1D.new()
		ramp.gradient = fade
		process.color_ramp = ramp
		particles.process_material = process
		emitter = particles
	emitter.name = label
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	emitter.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	emitter.visible = false
	add_child(emitter)
	emitter.global_position = point
	_entries.append({"node": emitter, "amount": int(spec.amount), "distance": float(spec.distance), "active": false})


func _set_active(entry: Dictionary, active: bool) -> void:
	if bool(entry.active) == active:
		return
	var emitter: GeometryInstance3D = entry.node
	# Pausing simulation as well as drawing is essential: turning off emission
	# alone keeps old particles updating until their lifetimes have elapsed.
	emitter.set("emitting", active)
	emitter.set("speed_scale", 1.0 if active else 0.0)
	emitter.visible = active
	entry.active = active


func _sprite(dimensions: Vector2, soft: bool) -> QuadMesh:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.24, 0.67, 1.0]) if soft else PackedFloat32Array([0.0, 0.60, 0.82, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0.80 if soft else 1.0), Color(1, 1, 1, 0.18 if soft else 0.76), Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.width = 32
	texture.height = 32
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = texture
	material.roughness = 1.0
	material.no_depth_test = false
	var mesh := QuadMesh.new()
	mesh.size = dimensions
	mesh.material = material
	return mesh


func _publish_counts(active_particles: int, active_emitters: int) -> void:
	if _world == null:
		return
	var metadata := _counts.duplicate()
	metadata["enabled"] = _enabled
	metadata["backend"] = "CPU compatibility" if _cpu else "GPU"
	metadata["active_particle_budget"] = _budget
	metadata["active_particles"] = active_particles
	metadata["active_emitters"] = active_emitters
	metadata["dynamic_lights"] = 0
	metadata["decorative_colliders"] = 0
	_world.set_meta("orchard_ambient_life", metadata)
