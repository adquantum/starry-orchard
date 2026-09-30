class_name BattleUnitViewV2
extends Control

signal clicked(unit_id: StringName)

const UnitNameplateScript = preload("res://scenes/battle_v2/ui/unit_nameplate_v2.gd")
const TargetSigilScript = preload("res://scenes/battle_v2/ui/target_sigil_v2.gd")
const WorldStatusScript = preload("res://scenes/battle_v2/presentation/world_status_visual_v2.gd")
const WorldPipArcScript = preload("res://scenes/battle_v2/presentation/world_pip_arc_v2.gd")
const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const LayoutProfile = preload("res://scripts/battle_v2/presentation/battle_layout_profile_v2.gd")
const SCHOOL_COLORS := {
	"fire": Color("#f05b3d"), "ice": Color("#78c8f5"), "storm": Color("#a46cff"),
	"myth": Color("#e6b84b"), "life": Color("#63c96b"), "death": Color("#8d78a8"), "balance": Color("#d99b52")
}

var unit: BattleUnitStateV2
var slot_config
var active := false
var valid_target := false
var selected_target := false
var resolving_actor := false
var debug_mode := false
var hud_hovered := false
var character_hovered := false
var pulse_time := 0.0
var nameplate: Control
var ground_sigil: Control
var action_token: Control
var foot_status_visual: Control
var orbit_status_visual: Control
var world_pip_arc: Control
var character_presentation: Dictionary = {}
var school_aura_texture: Texture2D
var character_texture: Texture2D
var character_facing: StringName = &"front_left"
var character_animation: StringName = &"idle"
var character_anim_time := 0.0


func _ready() -> void:
	size = Vector2(220, 230)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_character_mouse_entered)
	mouse_exited.connect(_on_character_mouse_exited)
	ground_sigil = TargetSigilScript.new()
	ground_sigil.position = Vector2(82, 106)
	ground_sigil.size = Vector2(72, 72)
	ground_sigil.scale = Vector2(1.0, 0.42)
	ground_sigil.z_index = -1
	ground_sigil.visible = false
	add_child(ground_sigil)
	foot_status_visual = WorldStatusScript.new()
	foot_status_visual.size = Vector2(220, 160)
	foot_status_visual.z_index = -1
	add_child(foot_status_visual)
	world_pip_arc = WorldPipArcScript.new()
	world_pip_arc.size = Vector2(220, 160)
	world_pip_arc.z_index = 1
	add_child(world_pip_arc)
	nameplate = UnitNameplateScript.new()
	nameplate.position = Vector2(8, 139)
	nameplate.size = preload("res://scenes/battle_v2/ui/compact_hud_metrics.gd").SIZE
	nameplate.clicked.connect(func(unit_id: StringName): clicked.emit(unit_id))
	nameplate.hover_changed.connect(_on_nameplate_hover_changed)
	add_child(nameplate)
	action_token = nameplate.action_badge
	orbit_status_visual = WorldStatusScript.new()
	orbit_status_visual.size = Vector2(220, 160)
	orbit_status_visual.z_index = 3
	add_child(orbit_status_visual)
	set_process(true)


func bind(p_unit: BattleUnitStateV2, config, character_definition: Dictionary = {}) -> void:
	unit = p_unit
	slot_config = config
	character_presentation = (character_definition.get("presentation", {}) as Dictionary).duplicate(true)
	school_aura_texture = ArtRegistryScript.texture(StringName("magic_%s_aura" % str(unit.school_id)))
	var source_direction := "back" if unit.team == 0 else "front"
	# Front and Back masters have opposite camera-facing source semantics.
	# Both branches are derived only from the slot's position relative to the arena center.
	var center_facing := ("left" if config.normalized_position.x < 0.5 else "right") if unit.team == 0 else ("right" if config.normalized_position.x < 0.5 else "left")
	character_facing = StringName("%s_%s" % [source_direction, center_facing])
	character_texture = ArtRegistryScript.texture(StringName("wizard_%s_%s" % [str(unit.school_id), source_direction]))
	z_index = config.z_order
	ground_sigil.setup(config.sigil_id, SCHOOL_COLORS.get(str(unit.school_id), Color.WHITE), 0.22)
	nameplate.bind(unit, config.sigil_id)
	foot_status_visual.setup(unit, character_presentation, WorldStatusScript.LayerMode.FOOT)
	orbit_status_visual.setup(unit, character_presentation, WorldStatusScript.LayerMode.ORBITS)
	world_pip_arc.setup(unit, character_presentation)
	queue_redraw()


func refresh() -> void:
	nameplate.refresh()
	world_pip_arc.refresh()
	queue_redraw()


func set_flags(p_active: bool, p_valid: bool, p_selected: bool, p_resolving: bool, p_debug: bool) -> void:
	active = p_active
	valid_target = p_valid
	selected_target = p_selected
	resolving_actor = p_resolving
	debug_mode = p_debug
	nameplate.set_flags(active, valid_target, selected_target, debug_mode)
	# The battle-board art is the single world-space source for position runes.
	# Keep this compatibility node hidden for targeting data and HUD rune lookup.
	ground_sigil.visible = false
	queue_redraw()


func apply_layout_geometry(center_global: Vector2) -> void:
	if ground_sigil == null:
		return
	var local_center := get_global_transform().affine_inverse() * center_global
	var foot := LayoutProfile.UNIT_LOCAL_FOOT
	var toward_center := (local_center - foot).normalized()
	var rune_center := foot + toward_center * LayoutProfile.RUNE_FORWARD_DISTANCE
	ground_sigil.position = rune_center - ground_sigil.size * 0.5
	var source_direction := "back" if unit.team == 0 else "front"
	var is_left_of_center := foot.x < local_center.x
	var center_facing := ("left" if is_left_of_center else "right") if unit.team == 0 else ("right" if is_left_of_center else "left")
	character_facing = StringName("%s_%s" % [source_direction, center_facing])
	queue_redraw()


func detach_nameplate_to(hud_parent: Control) -> void:
	if nameplate.get_parent() != hud_parent:
		nameplate.reparent(hud_parent)
	nameplate.scale = Vector2.ONE
	nameplate.size = preload("res://scenes/battle_v2/ui/compact_hud_metrics.gd").SIZE
	action_token = nameplate.action_badge


func show_action_token(data: Dictionary, state: int) -> void:
	nameplate.show_action(data, state)


func show_choosing_token() -> void:
	nameplate.show_choosing(SCHOOL_COLORS.get(str(unit.school_id), Color.WHITE))


func clear_action_token() -> void:
	nameplate.clear_action()


func set_presentation_statuses(statuses: Array[StatusInstanceV2]) -> void:
	foot_status_visual.set_presentation_statuses(statuses)
	orbit_status_visual.set_presentation_statuses(statuses)
	nameplate.set_presentation_statuses(statuses)


func clear_presentation_statuses() -> void:
	foot_status_visual.clear_presentation_statuses()
	orbit_status_visual.clear_presentation_statuses()
	nameplate.clear_presentation_statuses()


func notify_status_event(kind: StringName) -> void:
	foot_status_visual.notify_status_event(kind)
	orbit_status_visual.notify_status_event(kind)


func play_character_animation(animation_id: StringName) -> void:
	character_animation = animation_id
	character_anim_time = 0.0
	queue_redraw()


func get_target_anchor_global() -> Vector2:
	return get_global_transform() * Vector2(110, 70)


func get_cast_floor_anchor_global() -> Vector2:
	return get_global_transform() * Vector2(110, 132)


func get_target_selection_anchor_global() -> Vector2:
	return get_target_anchor_global()


func get_target_hit_rect_global() -> Rect2:
	var local_rect := Rect2(48, 0, 124, 137).grow(12.0)
	var top_left := get_global_transform() * local_rect.position
	var bottom_right := get_global_transform() * local_rect.end
	return Rect2(top_left, bottom_right - top_left).abs()


func contains_target_point(pointer_global: Vector2) -> bool:
	return get_target_hit_rect_global().has_point(pointer_global) or nameplate.get_global_rect().has_point(pointer_global)


func _process(delta: float) -> void:
	pulse_time += delta
	character_anim_time += delta
	var animation_duration := float({&"cast_start":0.35, &"cast_release":0.28, &"hit":0.28, &"revive":0.55}.get(character_animation, -1.0))
	if animation_duration > 0.0 and character_anim_time >= animation_duration:
		character_animation = &"idle"
		character_anim_time = 0.0
	if valid_target or selected_target or resolving_actor:
		queue_redraw()


func _draw() -> void:
	if unit == null:
		return
	var accent: Color = SCHOOL_COLORS.get(str(unit.school_id), Color.WHITE)
	var pulse := 0.5 + sin(pulse_time * 5.0) * 0.5
	var foot := Vector2(110, 132)
	draw_set_transform(Vector2.ZERO)
	_draw_ellipse(foot, Vector2(43, 13), Color(0.01, 0.02, 0.04, 0.58), 2.0)
	if active or valid_target or selected_target or resolving_actor or hud_hovered:
		var ring_color := Color("#f6d36b") if active else accent
		if valid_target:
			ring_color = Color(0.35, 0.95, 0.72, 0.62 + pulse * 0.3)
		if selected_target:
			ring_color = Color("#fff1a8")
		if resolving_actor:
			ring_color = Color("#71dcff")
		if hud_hovered:
			ring_color = Color("#ffe28a")
		_draw_ellipse(foot, Vector2(47 + pulse * 3, 16 + pulse), ring_color, 3.0 if selected_target else 2.0)
	if school_aura_texture != null and (active or selected_target or resolving_actor):
		draw_texture_rect(school_aura_texture, Rect2(72, 62, 76, 76), false, Color(1, 1, 1, 0.30 + pulse * 0.12))
	_draw_character(foot, accent)
	if valid_target:
		draw_arc(Vector2(110, 72), 49 + pulse * 2, 0, TAU, 40, Color(0.35, 0.95, 0.72, 0.35 + pulse * 0.25), 2.0)
	if selected_target:
		draw_colored_polygon(PackedVector2Array([Vector2(110, 2), Vector2(119, 15), Vector2(101, 15)]), Color("#fff1a8"))
	if not unit.alive:
		draw_rect(Rect2(64, 26, 92, 108), Color(0.04, 0.05, 0.08, 0.68))
		draw_string(ThemeDB.fallback_font, Vector2(88, 82), "DOWN", HORIZONTAL_ALIGNMENT_CENTER, 44, 13, Color("#bd7983"))
	if debug_mode:
		_draw_debug(foot)


func _draw_character(foot: Vector2, accent: Color) -> void:
	if character_texture != null:
		var bob := sin(pulse_time * 2.4) * 1.2 if character_animation == &"idle" else 0.0
		var cast_lift := -4.0 * sin(clampf(character_anim_time / 0.35, 0.0, 1.0) * PI) if character_animation in [&"cast_start", &"cast_release"] else 0.0
		var tint := Color.WHITE
		if character_animation == &"hit":
			tint = Color(1.0, 0.55, 0.55)
		elif character_animation == &"revive":
			tint = Color(0.72, 1.0, 0.78)
		var rect := Rect2(46, 4 + bob + cast_lift, 128, 128)
		if character_facing in [&"front_left", &"back_left"]:
			draw_set_transform(Vector2(220, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect(character_texture, rect, false, tint)
		draw_set_transform(Vector2.ZERO)
		return
	var is_enemy := unit.team == 1
	var body := accent.darkened(0.15)
	var outline := Color("#101827")
	if is_enemy:
		draw_colored_polygon(PackedVector2Array([Vector2(110, 31), Vector2(145, 113), Vector2(75, 113)]), body.darkened(0.22))
		draw_circle(Vector2(110, 49), 22, body)
		draw_circle(Vector2(102, 47), 3, Color("#f4dc80"))
		draw_circle(Vector2(118, 47), 3, Color("#f4dc80"))
		draw_line(Vector2(80, 105), Vector2(63, 125), outline, 6)
		draw_line(Vector2(140, 105), Vector2(157, 125), outline, 6)
	else:
		draw_colored_polygon(PackedVector2Array([Vector2(82, 118), Vector2(96, 63), Vector2(124, 63), Vector2(139, 118)]), body)
		draw_circle(Vector2(110, 49), 19, Color("#d9b59b"))
		draw_colored_polygon(PackedVector2Array([Vector2(82, 48), Vector2(110, 12), Vector2(137, 48)]), body.darkened(0.26))
		draw_rect(Rect2(87, 44, 46, 8), body.darkened(0.26))
		draw_line(Vector2(91, 76), Vector2(69, 105), outline, 7)
		draw_line(Vector2(129, 76), Vector2(151, 105), outline, 7)
		draw_line(Vector2(151, 105), Vector2(151, 42), Color("#74542f"), 5)
		draw_circle(Vector2(151, 37), 9, accent.lightened(0.18))
	draw_line(Vector2(94, 118), foot + Vector2(-13, 0), outline, 8)
	draw_line(Vector2(126, 118), foot + Vector2(13, 0), outline, 8)


func _draw_debug(foot: Vector2) -> void:
	draw_rect(Rect2(60, 5, 100, 128), Color("#ff4f78"), false, 1)
	draw_line(foot - Vector2(8, 0), foot + Vector2(8, 0), Color.CYAN, 1)
	draw_line(foot - Vector2(0, 8), foot + Vector2(0, 8), Color.CYAN, 1)
	draw_circle(Vector2(110, 70), 3, Color("#ffb84f"))
	draw_circle(Vector2(110, 20), 3, Color("#fa6cff"))
	draw_circle(Vector2(110, 137), 3, Color("#62ff9e"))
	draw_string(ThemeDB.fallback_font, Vector2(5, 12), "%s  n=(%.3f, %.3f)  z=%d" % [str(unit.id), slot_config.normalized_position.x, slot_config.normalized_position.y, z_index], HORIZONTAL_ALIGNMENT_LEFT, 210, 9, Color.CYAN)
	draw_string(ThemeDB.fallback_font, Vector2(5, 132), "C: CHARACTER", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color.CYAN)
	draw_string(ThemeDB.fallback_font, Vector2(115, 68), "S: SPELL", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#ffb84f"))
	draw_string(ThemeDB.fallback_font, Vector2(115, 19), "F: FLOAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#fa6cff"))
	draw_string(ThemeDB.fallback_font, Vector2(115, 145), "N: NAMEPLATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color("#62ff9e"))


func _draw_ellipse(center: Vector2, radii: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in 41:
		var angle := TAU * float(index) / 40.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	draw_polyline(points, color, width, true)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(unit.id)


func _on_character_mouse_entered() -> void:
	character_hovered = true
	hud_hovered = true
	nameplate.set_linked_hover(true)
	queue_redraw()


func _on_character_mouse_exited() -> void:
	character_hovered = false
	if not nameplate.linked_hover:
		hud_hovered = false
	nameplate.set_linked_hover(false)
	queue_redraw()


func _on_nameplate_hover_changed(_unit_id: StringName, hovered: bool) -> void:
	hud_hovered = hovered or character_hovered
	ground_sigil.visible = false
	queue_redraw()
