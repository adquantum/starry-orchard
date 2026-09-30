extends Node3D
## Shared visual controller for the 21 Arcana recipes. No combat state lives here.
const Stage = preload("res://scripts/fusion_3d/vfx/arcana_stage.gd")
const PARTICLE_ROOT := "res://assets/vfx/arcana/particles/"
const WISP_TEXTURE := preload("res://assets/vfx/arcana/textures/arcane_wisp_v1.png")
static var particle_cache: Dictionary = {}
const SCHOOLS := ["fire", "ice", "storm", "myth", "life", "death", "balance"]
const COLORS := {
	"fire": Color("ff804a"), "ice": Color("7fd9ff"), "storm": Color("bb80ff"),
	"myth": Color("ffd574"), "life": Color("a4e97c"), "death": Color("bba4dc"),
	"balance": Color("edc084")
}
var school := "ice"
var level := 2
var phase := "missile"
var rate := 1.0
var elapsed := 0.0
var flight_seconds := 0.8
var flight_start := Vector3.ZERO
var flight_end := Vector3.ZERO
var arc_height := 0.0
var flying := false
var trail: GPUParticles3D
signal arrived

static func level_for(card: CardDefinitionV2) -> int:
	if str(card.school_id) not in SCHOOLS:
		return 0
	if _contains_attack(card.effects):
		return clampi(card.pip_cost, 1, 3)
	return 0

static func cast_level_for(card: CardDefinitionV2) -> int:
	if str(card.school_id) not in SCHOOLS:
		return 0
	return clampi(card.pip_cost, 1, 3)

static func _contains_attack(value: Variant) -> bool:
	if value is Dictionary:
		if str(value.get("type", "")) in ["damage", "drain", "apply_dot", "delay_damage", "detonate"]:
			return true
		for child in value.values():
			if _contains_attack(child):
				return true
	elif value is Array:
		for child in value:
			if _contains_attack(child):
				return true
	return false

static func flight_duration(distance: float, school_id: String) -> float:
	var speed_value: float = {"storm": 24.0, "ice": 20.0, "fire": 19.0, "balance": 20.0,
		"life": 17.0, "death": 17.0, "myth": 16.0}.get(school_id, 19.0)
	return clampf(distance / speed_value, 0.32, 0.95)

func setup(school_id: String, tier: int, visual_phase: String, playback_rate: float, ground_delta: float = -1.35) -> void:
	school = school_id
	level = tier
	phase = visual_phase
	rate = maxf(playback_rate, 0.001)
	name = "Arcana_%s_%d_%s" % [school, level, phase]
	if phase == "end":
		var stage: Node3D = Stage.new()
		add_child(stage)
		stage.setup(school, level, "impact", [1.05, 1.35, 1.65][level - 1] * rate, ground_delta)
		_make_particles("impact")
		_make_particles("mist")
		get_tree().create_timer(([1.05, 1.35, 1.65][level - 1] + 0.5) * rate).timeout.connect(queue_free)
	else:
		var stage: Node3D = Stage.new()
		add_child(stage)
		stage.setup(school, level, "projectile", 0.9 * rate)
		_make_particles("trail")

func launch(start: Vector3, destination: Vector3, seconds: float, school_id: String) -> void:
	flight_start = start
	flight_end = destination
	flight_seconds = maxf(seconds, 0.001)
	elapsed = 0.0
	flying = true
	arc_height = minf(start.distance_to(destination) * 0.055, 0.65) if school_id in ["life", "death", "myth", "fire"] else 0.0
	position = start
	_update_flight(0.0)
	if trail != null:
		trail.emitting = true

func _process(delta: float) -> void:
	if not flying:
		return
	elapsed += delta
	_update_flight(clampf(elapsed / (flight_seconds * rate), 0.0, 1.0))
	if elapsed >= flight_seconds * rate:
		flying = false
		if trail != null:
			trail.emitting = false
			trail.reparent(get_parent(), true)
			get_tree().create_timer(1.2 * rate).timeout.connect(trail.queue_free)
		arrived.emit()
		queue_free()

func _update_flight(t: float) -> void:
	position = flight_start.lerp(flight_end, t) + Vector3.UP * (4.0 * arc_height * t * (1.0 - t))
	var tangent := flight_end - flight_start + Vector3.UP * (4.0 * arc_height * (1.0 - 2.0 * t))
	if tangent.length_squared() > 0.00001:
		quaternion = Quaternion(Vector3.RIGHT, tangent.normalized())

func _make_particles(kind: String) -> void:
	var recipe := "%s_%d" % [school, level]
	if not particle_cache.has(recipe):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(PARTICLE_ROOT + recipe + ".particles.json"))
		particle_cache[recipe] = raw if raw is Dictionary else {}
	var cloud_kind := "burst" if kind == "impact" else kind
	var cloud_count := 0
	for cloud in particle_cache[recipe].get("clouds", []):
		if str(cloud.get("kind", "")) == cloud_kind:
			cloud_count = int(cloud.get("count", 0))
			break
	var particles := GPUParticles3D.new()
	particles.name = "Arcana_%s" % kind
	particles.amount = clampi(int(cloud_count * (0.26 if kind == "trail" else 0.32)), 16, 150)
	particles.lifetime = 0.7 if kind == "trail" else 1.2 if kind == "mist" else 0.9
	particles.one_shot = kind != "trail"
	particles.explosiveness = 0.0 if kind == "trail" else 0.65 if kind == "mist" else 0.95
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.16 if kind == "trail" else 0.75 if kind == "mist" else 0.6
	process.initial_velocity_min = 0.15 if kind == "trail" else 0.2 if kind == "mist" else 1.8
	process.initial_velocity_max = 0.5 if kind == "trail" else 0.85 if kind == "mist" else 3.5
	process.gravity = Vector3(0, 0.35, 0) if kind == "trail" else Vector3(0, 0.15, 0) if kind == "mist" else Vector3(0, -1.4, 0)
	process.scale_min = 0.08
	process.scale_max = 0.24 if kind == "trail" else 0.35
	process.color = COLORS.get(school, Color.WHITE).darkened(0.5) if kind == "mist" else COLORS.get(school, Color.WHITE)
	particles.process_material = process
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.5, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if kind == "mist" else BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_texture = WISP_TEXTURE
	material.albedo_color = COLORS.get(school, Color.WHITE).darkened(0.6) if kind == "mist" else COLORS.get(school, Color.WHITE)
	if kind == "mist":
		material.albedo_color.a = 0.35
	material.emission_enabled = true
	material.emission = material.albedo_color
	material.emission_energy_multiplier = 0.25 if kind == "mist" else 1.6
	mesh.material = material
	particles.draw_pass_1 = mesh
	add_child(particles)
	particles.emitting = kind != "trail"
	if kind == "trail":
		trail = particles
