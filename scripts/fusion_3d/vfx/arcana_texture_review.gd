extends Node3D
## Manual preview for the shared Arcana textures across all schools and Pip tiers.
const Stage = preload("res://scripts/fusion_3d/vfx/arcana_stage.gd")
const Arcana = preload("res://scripts/fusion_3d/vfx/arcana_spell_vfx.gd")
const SCHOOLS := ["fire", "ice", "storm", "myth", "life", "death", "balance"]
const SCHOOL_NAMES := ["火", "冰", "雷", "神话", "生命", "死亡", "平衡"]
var school_select: OptionButton
var tier_select: OptionButton
var effects: Node3D

func _ready() -> void:
	_build_world()
	_build_controls()
	_play_cast()

func _build_world() -> void:
	effects = Node3D.new()
	effects.name = "PreviewEffects"
	add_child(effects)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 4.0, 10.0)
	add_child(camera)
	camera.look_at(Vector3(0, 1.1, 0))
	camera.fov = 48.0
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -25, 0)
	light.light_energy = 1.1
	add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 7)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("1a2335")
	material.roughness = 0.9
	ground.material_override = material
	add_child(ground)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("0c1525")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("7d94b2")
	settings.ambient_light_energy = 0.55
	environment.environment = settings
	add_child(environment)

func _build_controls() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(280, 0)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "Arcana 贴图预览 · 七学院"
	column.add_child(title)
	school_select = OptionButton.new()
	for i in SCHOOLS.size():
		school_select.add_item(SCHOOL_NAMES[i])
	column.add_child(school_select)
	tier_select = OptionButton.new()
	for tier in [1, 2, 3]:
		tier_select.add_item("%d 豆粒子" % tier)
	column.add_child(tier_select)
	var cast_button := Button.new()
	cast_button.text = "播放施法（统一 3 级）"
	cast_button.pressed.connect(_play_cast)
	column.add_child(cast_button)
	var projectile_button := Button.new()
	projectile_button.text = "播放飞行与命中粒子"
	projectile_button.pressed.connect(_play_projectile)
	column.add_child(projectile_button)
	var hint := Label.new()
	hint.text = "选择学院和豆数后，点按钮重播。"
	column.add_child(hint)

func _clear_effects() -> void:
	for child in effects.get_children():
		child.queue_free()

func _school() -> String:
	return SCHOOLS[school_select.selected]

func _play_cast() -> void:
	_clear_effects()
	var cast := Stage.new()
	effects.add_child(cast)
	cast.scale = Vector3.ONE * 1.1
	cast.setup(_school(), 3, "cast", 2.4)

func _play_projectile() -> void:
	_clear_effects()
	var school := _school()
	var tier := tier_select.selected + 1
	var projectile := Arcana.new()
	effects.add_child(projectile)
	projectile.setup(school, tier, "missile", 1.0)
	projectile.arrived.connect(func():
		var impact := Arcana.new()
		effects.add_child(impact)
		impact.position = Vector3(2.6, 1.4, 0)
		impact.setup(school, tier, "end", 1.0))
	projectile.launch(Vector3(-2.6, 1.4, 0), Vector3(2.6, 1.4, 0), 1.4, school)
