class_name MagicTargetArrowV2
extends Control

enum State { HIDDEN, SEARCHING, VALID, INVALID, LOCKED }

var arrow_state := State.HIDDEN
var start_point := Vector2.ZERO
var end_point := Vector2.ZERO
var accent := Color("#ffb24a")
var pulse_time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func show_arrow(from_global: Vector2, to_global: Vector2, p_accent: Color) -> void:
	accent = p_accent
	arrow_state = State.SEARCHING
	update_arrow(from_global, to_global, State.SEARCHING)


func update_arrow(from_global: Vector2, to_global: Vector2, state: State) -> void:
	start_point = get_global_transform().affine_inverse() * from_global
	end_point = get_global_transform().affine_inverse() * to_global
	arrow_state = state
	queue_redraw()


func lock_arrow() -> void:
	arrow_state = State.LOCKED
	queue_redraw()


func hide_arrow() -> void:
	arrow_state = State.HIDDEN
	queue_redraw()


func _process(delta: float) -> void:
	pulse_time += delta
	if arrow_state != State.HIDDEN:
		queue_redraw()


func _draw() -> void:
	if arrow_state == State.HIDDEN:
		return
	var distance := start_point.distance_to(end_point)
	if distance < 8.0:
		return
	var direction_sign := -1.0 if end_point.x < start_point.x else 1.0
	var control_a := start_point + Vector2(direction_sign * clampf(distance * 0.20, 38, 120), -clampf(distance * 0.38, 80, 220))
	var control_b := end_point + Vector2(-direction_sign * clampf(distance * 0.16, 30, 95), clampf(distance * 0.10, 18, 55))
	var points := PackedVector2Array()
	for index in 41:
		var t := float(index) / 40.0
		var p := pow(1.0 - t, 3) * start_point + 3.0 * pow(1.0 - t, 2) * t * control_a + 3.0 * (1.0 - t) * t * t * control_b + t * t * t * end_point
		points.append(p.round())
	var color := accent
	if arrow_state == State.SEARCHING:
		color = accent.darkened(0.22)
	elif arrow_state == State.INVALID:
		color = Color("#8a5662")
	elif arrow_state == State.VALID:
		color = accent.lightened(0.20)
	elif arrow_state == State.LOCKED:
		color = Color("#fff1aa")
	var pulse := 0.5 + sin(pulse_time * 8.0) * 0.5
	draw_polyline(points, Color(0.01, 0.02, 0.06, 0.82), 10.0, true)
	draw_polyline(points, Color(color, 0.62 + pulse * 0.30), 4.0 if arrow_state != State.LOCKED else 7.0, true)
	for index in range(4, points.size() - 3, 5):
		var rune_alpha := 0.30 + 0.55 * (0.5 + sin(pulse_time * 6.0 + index) * 0.5)
		draw_rect(Rect2(points[index] - Vector2(2, 2), Vector2(4, 4)), Color(color, rune_alpha))
	var direction := (points[-1] - points[-4]).normalized()
	var normal := Vector2(-direction.y, direction.x)
	var head_size := 28.0 if arrow_state in [State.VALID, State.LOCKED] else 22.0
	draw_colored_polygon(PackedVector2Array([end_point, end_point - direction * head_size + normal * head_size * 0.50, end_point - direction * head_size * 0.72, end_point - direction * head_size - normal * head_size * 0.50]), color)
	draw_circle(end_point, 5.0 + pulse * 2.0, Color(color, 0.85))
