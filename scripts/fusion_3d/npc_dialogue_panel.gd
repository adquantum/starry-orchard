extends PanelContainer
## Shared bottom dialogue. Artwork is nine-sliced; text and buttons remain native UI.
var heading: Label
var body: Label
var actions: HBoxContainer
var content: VBoxContainer
var scroll: ScrollContainer
var portrait: TextureRect
var portrait_view: SubViewport
var skin: StyleBoxTexture
var actor_id := ""

func _ready() -> void:
	theme = preload("res://scripts/fusion_3d/academy_ui.gd").make_theme()
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 202
	empty.content_margin_right = 36
	empty.content_margin_top = 24
	empty.content_margin_bottom = 26
	add_theme_stylebox_override("panel", empty)
	var tex := AtlasTexture.new()
	tex.atlas = load("res://assets/ui/npc_dialogue_v1/panel.png")
	tex.region = Rect2(14, 32, 2144, 630)
	skin = StyleBoxTexture.new()
	skin.texture = tex
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		skin.set_texture_margin(side, 220)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	add_child(content)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", Color("ead29b"))
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(heading)
	var line := HSeparator.new()
	line.modulate = Color("8b9aa8")
	content.add_child(line)
	scroll = ScrollContainer.new()
	scroll.custom_minimum_size.y = 106
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", 23)
	body.add_theme_color_override("font_color", Color("e6e7df"))
	scroll.add_child(body)
	actions = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 14)
	content.add_child(actions)
	portrait = TextureRect.new()
	portrait.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	portrait.texture = load("res://assets/art/ui/magic_card_box.png")
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	# A non-Control host keeps PanelContainer from resizing the portrait as content.
	var portrait_host := Node2D.new()
	add_child(portrait_host)
	portrait_host.add_child(portrait)
	get_viewport().size_changed.connect(layout_dialogue)
	resized.connect(_portrait_layout)
	visibility_changed.connect(func():
		if visible: scroll.scroll_vertical = 0
		if is_instance_valid(portrait_view): portrait_view.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED)
	layout_dialogue()

func add_action(text: String, callback: Callable) -> Button:
	var button := Button.new()
	preload("res://scenes/battle_v2/ui/compact_battle_skin.gd").button(button)
	button.text = text
	button.custom_minimum_size = Vector2(170, 44)
	button.add_theme_font_size_override("font_size", 21)
	button.pressed.connect(callback)
	actions.add_child(button)
	return button

func layout_dialogue() -> void:
	if not is_instance_valid(content): return
	var area := get_viewport_rect().size
	var factor := clampf(area.x / 1600.0, 0.65, 1.0)
	scale = Vector2.ONE * factor
	size = Vector2(minf(1320, (area.x - 48) / factor), 294)
	position = Vector2((area.x - size.x * factor) * 0.5, area.y - size.y * factor - 24)
	_portrait_layout()

func _portrait_layout() -> void:
	if not is_instance_valid(portrait): return
	portrait.position = Vector2(8, (size.y - 178) * 0.5)
	portrait.size = Vector2(178, 178)
	queue_redraw()

func _draw() -> void:
	if skin == null: return
	# Draw the high-resolution source at 1/5 scale so its fixed corners stay 44 px.
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * 0.2)
	draw_style_box(skin, Rect2(Vector2.ZERO, size * 5))
	draw_set_transform(Vector2.ZERO)
	var center := Vector2(97, size.y * 0.5)
	draw_circle(center, 96, Color("0a1727"))
	draw_arc(center, 96, 0, TAU, 96, Color("b79a5e"), 5, true)
	draw_arc(center, 89, 0, TAU, 96, Color("cbd4db"), 2, true)

func set_actor(id: String) -> void:
	if id == actor_id: return
	actor_id = id
	if is_instance_valid(portrait_view):
		portrait_view.queue_free()
		portrait_view = null
	portrait.material = null
	portrait.texture = load("res://assets/art/ui/magic_card_box.png")
	var path := "res://assets/models/character_library/npc/" + id + ".glb"
	if id.is_empty() or not ResourceLoader.exists(path): return
	var packed := load(path) as PackedScene
	if packed == null: return
	portrait_view = SubViewport.new()
	portrait_view.size = Vector2i(384, 384)
	portrait_view.own_world_3d = true
	portrait_view.transparent_bg = true
	portrait_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(portrait_view)
	var model := packed.instantiate() as Node3D
	portrait_view.add_child(model)
	model.rotation.y = -PI * 0.5
	var bounds := AABB()
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if bounds.size == Vector3.ZERO else bounds.merge(box)
	var height := maxf(bounds.size.y, 0.1)
	var focus := bounds.get_center()
	focus.y = bounds.position.y + height * 0.82
	var camera := Camera3D.new()
	portrait_view.add_child(camera)
	camera.position = focus + Vector3(0, height * 0.015, height * 0.66)
	camera.look_at(focus)
	camera.fov = 36
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -25, 0)
	light.light_energy = 1.6
	portrait_view.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("bccbdc")
	environment.environment.ambient_light_energy = 0.7
	portrait_view.add_child(environment)
	portrait.texture = portrait_view.get_texture()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){vec4 c=texture(TEXTURE,UV); c.a*=1.0-smoothstep(0.47,0.49,length(UV-vec2(0.5))); COLOR=c;}"
	var material := ShaderMaterial.new()
	material.shader = shader
	portrait.material = material
