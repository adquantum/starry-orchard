class_name ActionTokenV2
extends Control

enum State { EMPTY, CHOOSING, LOCKED, ACTIVE, COMPLETED, PASSED }

const SigilScript = preload("res://scenes/battle_v2/ui/target_sigil_v2.gd")
const ThemeScript = preload("res://scripts/battle_v2/presentation/school_theme_v2.gd")
const CircleShader = preload("res://assets/shaders/circular_spell_icon.gdshader")
const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const Metrics = preload("res://scripts/battle_v2/presentation/pixel_ui_metrics_v2.gd")
const Compact = preload("res://scenes/battle_v2/ui/compact_hud_metrics.gd")

var compact_mode := false
var reference_layout := false

func set_reference_layout() -> void:
	reference_layout=true
	size=Compact.ACTION_SIZE
	var backing:=target_backing.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	backing.set_corner_radius_all(2)
	backing.bg_color=Color.TRANSPARENT
	backing.border_color=Color("dcb66e")
	target_backing.add_theme_stylebox_override("panel",backing)
	target_backing.self_modulate.a=0.0
	_layout_reference()

func _layout_reference() -> void:
	icon.position=Vector2(2,2);icon.size=Vector2(46,46)
	target_sigil.position=Vector2(30,30) if token_state!=State.PASSED else Vector2(4,2)
	target_sigil.scale=Vector2.ONE*((46.0 if token_state==State.PASSED else 24.0)/Metrics.ACTION_TARGET_SIZE)
	target_backing.position=Vector2(30,30);target_backing.size=Vector2(24,24)
var token_state := State.EMPTY
var action_data: Dictionary = {}
var icon: TextureRect
var target_sigil: Control
var target_backing: Panel
var pulse_time := 0.0
var stage_color := Color("#3c1e25")


func _ready() -> void:
	size = Metrics.ACTION_BADGE_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon = TextureRect.new()
	icon.position = Vector2(3, 3)
	icon.size = Vector2.ONE * Metrics.ACTION_SPELL_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = CircleShader
	icon.material = material
	add_child(icon)
	if compact_mode:
		target_backing = Panel.new()
		target_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		target_backing.position = Vector2(30, 30)
		target_backing.size = Vector2.ONE * Compact.ACTION_TARGET
		var backing := StyleBoxFlat.new()
		backing.bg_color = Color("0b1426")
		backing.border_color = Color("96aab9")
		backing.set_border_width_all(1)
		backing.set_corner_radius_all(12)
		target_backing.add_theme_stylebox_override("panel", backing)
		add_child(target_backing)
	target_sigil = SigilScript.new()
	target_sigil.position = Vector2(62, 30)
	target_sigil.size = Vector2.ONE * Metrics.ACTION_TARGET_SIZE
	target_sigil.set_glow_enabled(false)
	target_sigil.set_texture_radius_ratio(0.46)
	add_child(target_sigil)
	if compact_mode:
		size = Compact.ACTION_SIZE
		icon.position = Vector2(2, 2)
		icon.size = Vector2.ONE * Compact.SCHOOL
		target_sigil.position = Vector2(30, 30)
		target_sigil.scale = Vector2.ONE * (Compact.ACTION_TARGET / Metrics.ACTION_TARGET_SIZE)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target_sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)
	visible = false


func show_action(data: Dictionary, state: State) -> void:
	action_data = data.duplicate(true)
	token_state = state
	visible = state != State.EMPTY
	var school := StringName(str(action_data.get("school", "balance")))
	var theme := ThemeScript.get_theme(school)
	var accent: Color = theme.accent
	stage_color = theme.secondary
	var art_path := str(action_data.get("art_path", ""))
	icon.texture = load(art_path) as Texture2D if not art_path.is_empty() and ResourceLoader.exists(art_path) else null
	icon.visible = state != State.PASSED
	var material := icon.material as ShaderMaterial
	material.set_shader_parameter("border_color", accent)
	material.set_shader_parameter("dim_amount", 0.68 if state == State.COMPLETED else 0.0)
	var sigil := &"pass" if state == State.PASSED else StringName(str(action_data.get("target_sigil", "battle_circle")))
	target_sigil.setup(sigil, accent, 0.95 if state == State.ACTIVE else 0.72 if state in [State.LOCKED, State.PASSED] else 0.30)
	if compact_mode:
		target_sigil.visible = true
		target_backing.visible = state != State.PASSED
		target_sigil.position = Vector2(4, 2) if state == State.PASSED else Vector2(30, 30)
		target_sigil.scale = Vector2.ONE * ((Compact.SCHOOL if state == State.PASSED else Compact.ACTION_TARGET) / Metrics.ACTION_TARGET_SIZE)
		target_sigil.set_intensity(1.0 if state != State.COMPLETED else 0.6)
		if get_parent().has_method("_fit_texture"):
			target_sigil.sigil_texture = get_parent()._fit_texture(target_sigil.sigil_texture)
	if reference_layout:_layout_reference()
	queue_redraw()


func show_choosing(accent: Color) -> void:
	action_data = {"school":"balance", "target_sigil":"battle_circle"}
	token_state = State.CHOOSING
	visible = true
	icon.visible = false
	target_sigil.setup(&"battle_circle", accent, 0.42)
	if compact_mode:
		target_sigil.hide()
		target_backing.hide()
	queue_redraw()


func clear() -> void:
	token_state = State.EMPTY
	visible = false


func _process(delta: float) -> void:
	pulse_time += delta
	if token_state in [State.CHOOSING, State.ACTIVE]:
		queue_redraw()


func _draw() -> void:
	if token_state == State.EMPTY:
		return
	if compact_mode:
		_draw_compact()
		return
	var alpha := 0.34 if token_state == State.COMPLETED else 0.92
	var glow := 0.5 + sin(pulse_time * 7.0) * 0.5
	var border := Color("#ffe7a0") if token_state == State.ACTIVE else Color("#755d36")
	if token_state == State.CHOOSING:
		border = Color(0.55, 0.80, 0.95, 0.45 + glow * 0.4)
	var spell_center := Vector2(42, 42)
	var frame := ArtRegistryScript.texture(&"ui_v2_rune_glow")
	if frame != null:
		draw_texture_rect(frame, Rect2(spell_center - Vector2.ONE * 43.0, Vector2.ONE * 86.0), false, Color(border, alpha))
	draw_circle(spell_center, 37.0, Color(stage_color, alpha))
	draw_arc(spell_center, 36.0, 0, TAU, 32, Color(border, 0.85), 3.0)
	if token_state == State.CHOOSING:
		draw_string(ThemeDB.fallback_font, Vector2(20, 47), "…", HORIZONTAL_ALIGNMENT_CENTER, 44, 26, Color("#c9eaff"))
	elif icon.texture == null and token_state != State.PASSED:
		draw_circle(spell_center, 27.0, Color("#39263a"))
		draw_string(ThemeDB.fallback_font, Vector2(25, 47), "✦", HORIZONTAL_ALIGNMENT_CENTER, 34, 21, Color("#ffd77c"))
	if token_state == State.ACTIVE:
		draw_arc(spell_center, 36.0 + glow * 3.0, 0, TAU, 32, Color("#fff1a8", 0.45 + glow * 0.45), 3.0)


func _panel(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.corner_radius_top_left = 18
	box.corner_radius_bottom_left = 18
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_right = 8
	return box


func _draw_compact() -> void:
	var label: String = {State.CHOOSING:"选择中", State.LOCKED:"准备", State.ACTIVE:"施放", State.COMPLETED:"完成", State.PASSED:"跳过"}.get(token_state, "")
	var color := Color("f4dfa3") if token_state == State.ACTIVE else Color("dfeaf0")
	if token_state == State.PASSED:
		draw_circle(Vector2(27, 25), 23, Color(0.02, 0.04, 0.07, 0.22))
	elif token_state != State.CHOOSING:
		# Card art stays circular; the target overlaps its lower-right corner.
		if not reference_layout:draw_circle(Vector2(25,25),23,Color("152136"),true,-1,true)
		draw_arc(Vector2(25, 25), 24, 0, TAU, 32, Color(color, 0.5), 1, true)
		if reference_layout:
			draw_arc(Vector2(25,25),25,0,TAU,64,Color("cda862"),2,true)
			draw_arc(Vector2(25,25),23,PI*1.05,PI*1.85,32,Color("fff0c2"),1,true)
			var diamond:=PackedVector2Array([Vector2(42,26),Vector2(58,42),Vector2(42,58),Vector2(26,42),Vector2(42,26)])
			draw_polyline(diamond,Color("cda862"),2,true)
	if token_state == State.CHOOSING:
		draw_string(ThemeDB.fallback_font, Vector2(0, 30), "…", HORIZONTAL_ALIGNMENT_CENTER, Compact.ACTION_SIZE.x, 18, color)
	draw_string_outline(ThemeDB.fallback_font, Vector2(0, Compact.ACTION_LABEL_Y), label, HORIZONTAL_ALIGNMENT_CENTER, Compact.ACTION_SIZE.x, 12, 3, Color("17202b"))
	draw_string(ThemeDB.fallback_font, Vector2(0, Compact.ACTION_LABEL_Y), label, HORIZONTAL_ALIGNMENT_CENTER, Compact.ACTION_SIZE.x, 12, color)
