class_name ResolutionCasterPointerV2
extends Control

var current_angle := -PI * 0.5
var target_angle := -PI * 0.5
var school_color := Color("#d3a64b")
var intensity := 0.58
var rotating := false
var rotation_elapsed := 0.0
var rotation_duration := 0.28
var start_angle := 0.0
var pulse_time := 0.0
var test_duration_scale := 1.0
var battle_center_local := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func set_planning_target(caster_global: Vector2, color: Color) -> void:
	target_angle = _angle_to(caster_global)
	current_angle = target_angle
	school_color = color
	intensity = 0.58
	rotating = false
	queue_redraw()


func rotate_to_caster(caster_global: Vector2, color: Color, duration: float = 0.28) -> void:
	start_angle = current_angle
	target_angle = _angle_to(caster_global)
	school_color = color
	intensity = 1.0
	rotation_duration = clampf(duration, 0.20, 0.35) * maxf(test_duration_scale, 0.01)
	rotation_elapsed = 0.0
	rotating = true
	while rotating and is_inside_tree():
		await get_tree().process_frame


func set_idle() -> void:
	intensity = 0.58
	rotating = false
	queue_redraw()


func set_battle_center(center_local: Vector2) -> void:
	battle_center_local = center_local
	queue_redraw()


func _process(delta: float) -> void:
	pulse_time += delta
	if rotating:
		rotation_elapsed += delta
		var t := clampf(rotation_elapsed / maxf(rotation_duration, 0.001), 0.0, 1.0)
		var eased := t * t * (3.0 - 2.0 * t)
		current_angle = lerp_angle(start_angle, target_angle, eased)
		if t >= 1.0:
			current_angle = target_angle
			rotating = false
	queue_redraw()


func _angle_to(caster_global: Vector2) -> float:
	var center_global := get_global_transform() * _center()
	return (caster_global - center_global).angle()


func _center() -> Vector2:
	return battle_center_local if battle_center_local != Vector2.ZERO else Vector2(size.x * 0.5, size.y * 0.475)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var center := _center()
	var pulse := 0.5 + sin(pulse_time * 6.0) * 0.5
	var alpha := intensity * (0.82 + pulse * 0.18)
	var arcane_violet := Color("#9a72c7")
	var pointer_accent := arcane_violet.lerp(school_color.lightened(0.18), 0.22)
	var antique_gold := Color("#d9b66f")
	# The medallion and the needle share this exact pivot. Keeping the forward
	# blade and rear counterweight balanced avoids the old off-centre silhouette.
	draw_set_transform(center, 0.0, Vector2(1.0, 0.48))
	draw_circle(Vector2.ZERO, 39.0, Color("#211534", 0.28))
	draw_arc(Vector2.ZERO, 38.0, 0, TAU, 48, Color(pointer_accent, alpha * 0.86), 3.0)
	draw_arc(Vector2.ZERO, 29.0, 0, TAU, 40, Color(antique_gold, alpha * 0.55), 1.5)
	for tick_index in 8:
		var tick_angle := TAU * float(tick_index) / 8.0
		var tick_direction := Vector2.from_angle(tick_angle)
		draw_line(tick_direction * 33.0, tick_direction * 37.0, Color(antique_gold, alpha * 0.72), 1.5)
	draw_set_transform(Vector2.ZERO)
	var direction := Vector2.from_angle(current_angle)
	var side := direction.orthogonal()
	var tip := center + direction * 52.0
	var rear_tip := center - direction * 23.0
	var points := PackedVector2Array([
		tip,
		center + direction * 8.0 + side * 11.0,
		rear_tip,
		center + direction * 8.0 - side * 11.0,
	])
	draw_colored_polygon(points, Color(pointer_accent.darkened(0.08), alpha * 0.88))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color(antique_gold, maxf(alpha, 0.70)), 2.0)
	draw_circle(center, 8.0, Color("#241638", 0.92))
	draw_circle(center, 4.5, pointer_accent.lightened(0.30))
	draw_arc(center, 8.0, 0, TAU, 24, Color(antique_gold, maxf(alpha, 0.76)), 2.0)
