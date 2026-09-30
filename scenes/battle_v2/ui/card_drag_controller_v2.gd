class_name CardDragControllerV2
extends Node

const DRAG_THRESHOLD := 8.0
const PICKUP_OFFSET := 20.0
const MAX_TILT := deg_to_rad(3.0)

var host: Control
var pressed := false
var dragging := false
var press_global := Vector2.ZERO
var pickup_origin := Vector2.ZERO
var pickup_rotation := 0.0
var desired_position := Vector2.ZERO
var desired_scale := Vector2.ONE
var desired_rotation := 0.0
var pointer_velocity_x := 0.0


func setup(p_host: Control) -> void:
	host = p_host
	set_process(true)


func handle_gui_input(event: InputEvent) -> void:
	if host == null or host.locking or (not host.affordable and not bool(host.get_meta("fusion_selection",false))):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			pressed = true
			press_global = event.global_position
			pickup_origin = host.position
			pickup_rotation = host.rotation
			desired_position = pickup_origin
			desired_scale = host.scale
			desired_rotation = pickup_rotation
		else:
			if dragging:
				host.drag_ended.emit(host.card, event.global_position)
				finish_drag()
			elif pressed and (not host.has_meta("click_selection") or bool(host.get_meta("click_selection")) or bool(host.get_meta("fusion_selection",false))):
				host.selected.emit(host.card)
			pressed = false
	elif event is InputEventMouseMotion and pressed and not bool(host.get_meta("click_selection",false)):
		var pointer_delta: Vector2 = event.global_position - press_global
		if not dragging and pointer_delta.length() >= DRAG_THRESHOLD:
			_start_drag(event.global_position)
		if dragging:
			pointer_velocity_x = lerpf(pointer_velocity_x, event.relative.x * 60.0, 0.36)
			desired_position = pickup_origin + Vector2(pointer_delta.x * 0.03, -PICKUP_OFFSET + pointer_delta.y * 0.02)
			if host.card.definition.target_type in [&"self", &"all_allies", &"all_enemies"] and not bool(host.get_meta("fusion_selection",false)):
				var parent_inverse: Transform2D = host.get_parent().get_global_transform_with_canvas().affine_inverse()
				desired_position = pickup_origin + (parent_inverse * event.global_position - parent_inverse * press_global) - Vector2(0,PICKUP_OFFSET)
			desired_rotation = pickup_rotation + clampf(pointer_delta.x * 0.00045 + pointer_velocity_x * 0.000018, -MAX_TILT, MAX_TILT)
			desired_scale = Vector2.ONE * 1.065
			host.drag_moved.emit(host.card, event.global_position, host.get_arrow_anchor_global())


func cancel_drag() -> void:
	pressed = false
	if dragging:
		finish_drag()


func finish_drag() -> void:
	dragging = false
	if host == null:
		return
	host.dragging = false
	pointer_velocity_x = 0.0
	host.restore_layout_pose()


func _start_drag(pointer_global: Vector2) -> void:
	if bool(host.get_meta("click_selection",false)):
		cancel_drag()
		return
	dragging = true
	host.dragging = true
	host.z_index = 500
	desired_position = pickup_origin - Vector2(0, PICKUP_OFFSET)
	desired_scale = Vector2.ONE * 1.065
	host.drag_started.emit(host.card, host.get_arrow_anchor_global())
	host.drag_moved.emit(host.card, pointer_global, host.get_arrow_anchor_global())


func _process(delta: float) -> void:
	if host == null or host.locking or not dragging:
		return
	var response := 1.0 - exp(-delta * 18.0)
	host.position = host.position.lerp(desired_position, response)
	host.scale = host.scale.lerp(desired_scale, response)
	host.rotation = lerp_angle(host.rotation, desired_rotation, response)
	pointer_velocity_x = lerpf(pointer_velocity_x, 0.0, 1.0 - exp(-delta * 12.0))
	desired_rotation = lerp_angle(desired_rotation, pickup_rotation, 1.0 - exp(-delta * 5.0))

