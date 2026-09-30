extends Node3D

var camera: Camera3D
var layout_size := Vector2.ZERO
var base_positions: Dictionary = {}
var world_scale := Vector3.ONE

static func display_text(value: String) -> String:
	# Only the overhead presentation is unsigned; combat values stay unchanged.
	for sign in ["+", "-", "−", "＋", "－", "﹢", "﹣", "±"]:
		value = value.replace(sign, "")
	return value

func configure_layout(size_in_world: Vector2) -> void:
	layout_size = size_in_world
	base_positions.clear()
	for child in get_children():
		if child is Node3D: base_positions[child] = child.position
	face_camera()

func _ready() -> void:
	world_scale = global_basis.get_scale()
	face_camera()

func _process(_delta: float) -> void:
	face_camera()

func face_camera() -> void:
	if not is_instance_valid(camera): return
	var camera_basis := camera.global_basis.orthonormalized()
	global_basis = camera_basis.scaled(world_scale)
	if base_positions.is_empty() or camera.is_position_behind(global_position): return
	var screen := camera.unproject_position(global_position)
	var pixels_x := absf(camera.unproject_position(global_position + camera_basis.x).x - screen.x)
	var pixels_y := absf(camera.unproject_position(global_position + camera_basis.y).y - screen.y)
	if pixels_x < 0.01 or pixels_y < 0.01: return
	var viewport := camera.get_viewport().get_visible_rect().size
	var half_width := layout_size.x * world_scale.x * pixels_x * 0.5
	var half_height := layout_size.y * world_scale.y * pixels_y * 0.5
	var margin := 24.0
	var left := half_width + margin
	var right := viewport.x - half_width - margin
	var safe_top := maxf(80.0, viewport.y * 0.17)
	var bottom := viewport.y - half_height - margin
	var desired_x := clampf(screen.x,left,right) if left <= right else viewport.x * 0.5
	var desired_y := clampf(screen.y,safe_top + half_height,bottom) if safe_top + half_height <= bottom else viewport.y * 0.5
	var shift := Vector3((desired_x-screen.x)/(pixels_x * world_scale.x),-(desired_y-screen.y)/(pixels_y * world_scale.y),0)
	for child in base_positions:
		if is_instance_valid(child): child.position = base_positions[child] + shift
