class_name TargetArrowRendererV2
extends Control

enum State { HIDDEN, SEARCHING, VALID, INVALID, LOCKED, CANCEL }

var arrow_state := State.HIDDEN
var start_point := Vector2.ZERO
var pointer_point := Vector2.ZERO
var snap_point := Vector2.ZERO
var displayed_end := Vector2.ZERO
var desired_end := Vector2.ZERO
var accent := Color("#ffb24a")
var pulse_time := 0.0
var opacity := 1.0
var arrow_head_texture: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	arrow_head_texture = _trimmed_texture("res://assets/art/ui/target_arrow_simple_gold_v3.png")
	(arrow_head_texture as AtlasTexture).region=Rect2(80,132,1094,978)
	set_process(true)


func show_arrow(from_global: Vector2, pointer_global: Vector2, p_accent: Color) -> void:
	accent = p_accent
	opacity = 1.0
	arrow_state = State.SEARCHING
	start_point = _to_local(from_global)
	pointer_point = _to_local(pointer_global)
	desired_end = _head_offset(start_point, pointer_point)
	displayed_end = desired_end
	queue_redraw()


func track_pointer(from_global: Vector2, pointer_global: Vector2, state: State, snap_global := Vector2.INF) -> void:
	start_point = _to_local(from_global)
	pointer_point = _to_local(pointer_global)
	arrow_state = state
	var raw_end := pointer_point
	if state == State.VALID and snap_global != Vector2.INF:
		snap_point = _to_local(snap_global)
		raw_end = pointer_point.lerp(snap_point, 0.76)
	desired_end = _head_offset(start_point, raw_end)
	queue_redraw()


func update_arrow(from_global: Vector2, to_global: Vector2, state: State) -> void:
	track_pointer(from_global, to_global, state, to_global if state == State.VALID else Vector2.INF)


func lock_arrow() -> void:
	arrow_state = State.LOCKED
	desired_end = _head_offset(start_point, snap_point if snap_point != Vector2.ZERO else pointer_point)
	queue_redraw()


func cancel_arrow() -> void:
	arrow_state = State.CANCEL
	queue_redraw()


func hide_arrow() -> void:
	arrow_state = State.HIDDEN
	opacity = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	pulse_time += delta
	if arrow_state == State.HIDDEN:
		return
	var follow_speed := 25.0 if arrow_state == State.SEARCHING else 15.0
	displayed_end = displayed_end.lerp(desired_end, 1.0 - exp(-delta * follow_speed))
	if arrow_state == State.CANCEL:
		opacity = move_toward(opacity, 0.0, delta * 9.0)
		if opacity <= 0.01:
			hide_arrow()
	queue_redraw()


func _draw() -> void:
	if arrow_state == State.HIDDEN:
		return
	var distance := start_point.distance_to(displayed_end)
	if distance < 8.0:
		return
	var direction_sign := -1.0 if displayed_end.x < start_point.x else 1.0
	var arch := clampf(distance * 0.34, 62.0, 210.0)
	var control_a := start_point + Vector2(direction_sign * clampf(distance * 0.18, 34.0, 112.0), -arch)
	var control_b := displayed_end + Vector2(-direction_sign * clampf(distance * 0.14, 26.0, 88.0), clampf(distance * 0.08, 12.0, 46.0))
	var points := PackedVector2Array()
	for index in 97:
		var t := float(index) / 96.0
		points.append(_bezier(start_point, control_a, control_b, displayed_end, t))
	var color := _state_color()
	var shadow := PackedVector2Array()
	var bevel_light := PackedVector2Array()
	var bevel_shade := PackedVector2Array()
	var specular := PackedVector2Array()
	var light_direction := Vector2(-0.8,-0.6)
	for index in points.size():
		var point := points[index]
		var tangent := points[maxi(0,index-1)].direction_to(points[mini(points.size()-1,index+1)])
		var normal := Vector2(-tangent.y,tangent.x)
		# Project a fixed upper-left light across the curve's rounded cross-section.
		var lit_side := normal*normal.dot(light_direction)
		shadow.append(point+Vector2(2.0,3.0))
		bevel_light.append(point+lit_side*1.1)
		bevel_shade.append(point-lit_side*2.0)
		specular.append(point+lit_side*2.2)
	# Blue-grey rim, shaded gold side, warm raised face and narrow ivory reflection.
	draw_polyline(shadow,Color(0.025,0.045,0.065,0.12*opacity),16.0,true)
	draw_polyline(shadow,Color(0.025,0.045,0.065,0.26*opacity),11.0,true)
	draw_polyline(points,Color("344759",opacity),11.0,true)
	draw_polyline(points,Color(color.darkened(0.36),opacity),8.8,true)
	draw_polyline(bevel_shade,Color(color.darkened(0.18),opacity),4.0,true)
	draw_polyline(points,Color(color,opacity),6.7,true)
	draw_polyline(bevel_light,Color(color.lightened(0.30),opacity),4.0,true)
	draw_polyline(specular,Color(color.lightened(0.76),0.94*opacity),1.5,true)
	var direction := (points[-1] - points[-5]).normalized()
	var head_size := 42.0 if arrow_state in [State.VALID,State.LOCKED] else 38.0
	var tint := Color.WHITE
	if arrow_state == State.INVALID:tint=Color("8f9baa")
	tint.a=opacity
	draw_set_transform(displayed_end,direction.angle()+PI/2)
	draw_texture_rect(arrow_head_texture,Rect2(-head_size*0.56,-head_size*0.75,head_size*1.12,head_size),false,tint)
	draw_set_transform(Vector2.ZERO)


static func _trimmed_texture(path: String) -> Texture2D:
	var source: Texture2D=load(path)
	var atlas := AtlasTexture.new()
	atlas.atlas=source
	atlas.region=source.get_image().get_used_rect()
	return atlas



func _state_color() -> Color:
	if arrow_state == State.INVALID:return Color("81858b")
	if arrow_state == State.LOCKED:return Color("f2dfab")
	return Color("d4be86")


func _head_offset(from_point: Vector2, raw_end: Vector2) -> Vector2:
	var direction := from_point.direction_to(raw_end)
	return raw_end - direction * 10.0


func _to_local(global_point: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global_point


func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var inverse := 1.0 - t
	return inverse * inverse * inverse * a + 3.0 * inverse * inverse * t * b + 3.0 * inverse * t * t * c + t * t * t * d
