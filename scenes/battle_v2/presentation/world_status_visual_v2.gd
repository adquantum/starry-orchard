class_name WorldStatusVisualV2
extends Control

const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const LayoutProfile = preload("res://scripts/battle_v2/presentation/battle_layout_profile_v2.gd")

const UPPER_STATUS_SIZE := 72.0
const LOWER_STATUS_SIZE := 63.0
const FOOT_STATUS_SIZE := 210.0
const GROUND_VISUAL_OFFSETS := {
	&"dot":Vector2(12.0, 4.0),
}

enum LayerMode { ORBITS, FOOT }

const SCHOOL_COLORS := {
	"fire": Color("#f05b3d"), "ice": Color("#78c8f5"), "storm": Color("#a46cff"),
	"myth": Color("#e6b84b"), "life": Color("#63c96b"), "death": Color("#8d78a8"), "balance": Color("#d99b52"),
	"*": Color("#e7cf8a"), "": Color("#e7cf8a")
}

var layer_mode := LayerMode.ORBITS
var unit: BattleUnitStateV2
var presentation: Dictionary = {}
var pulse_time := 0.0
var event_flashes: Array[Dictionary] = []
var presentation_status_override: Array[StatusInstanceV2] = []
var use_presentation_status_override := false


func setup(p_unit: BattleUnitStateV2, p_presentation: Dictionary, p_layer_mode: LayerMode) -> void:
	unit = p_unit
	presentation = p_presentation.duplicate(true)
	layer_mode = p_layer_mode
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	set_process(true)
	queue_redraw()


func notify_status_event(kind: StringName) -> void:
	event_flashes.append({"kind":kind, "time":0.0})
	queue_redraw()


func set_presentation_statuses(statuses: Array[StatusInstanceV2]) -> void:
	presentation_status_override = statuses.duplicate()
	use_presentation_status_override = true
	queue_redraw()


func clear_presentation_statuses() -> void:
	presentation_status_override.clear()
	use_presentation_status_override = false
	queue_redraw()


func count_kind(kind: StringName) -> int:
	var count := 0
	for status: StatusInstanceV2 in _display_statuses():
		if status.kind == kind:
			count += 1
	return count


func _process(delta: float) -> void:
	pulse_time += delta
	for flash in event_flashes:
		flash["time"] = float(flash.get("time", 0.0)) + delta
	event_flashes = event_flashes.filter(func(flash: Dictionary): return float(flash.get("time", 0.0)) < 0.38)
	queue_redraw()


func _draw() -> void:
	if unit == null or not unit.alive:
		return
	var statuses := _visual_statuses()
	if layer_mode == LayerMode.ORBITS:
		_draw_orbit(statuses.filter(func(item: Dictionary): return item.kind in [&"blade", &"weakness"]), true)
		_draw_orbit(statuses.filter(func(item: Dictionary): return item.kind in [&"shield", &"trap"]), false)
	else:
		_draw_foot_rings(statuses.filter(func(item: Dictionary): return item.kind in [&"dot", &"hot", &"delay_damage"]))
	_draw_event_flashes()


func _display_statuses() -> Array[StatusInstanceV2]:
	return presentation_status_override if use_presentation_status_override else unit.statuses


func _visual_statuses() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for status: StatusInstanceV2 in _display_statuses():
		result.append({"kind":status.kind, "school":StringName(ArtRegistryScript.status_school_key(status)), "seed":status.instance_id})
	return result


func _draw_orbit(items: Array[Dictionary], upper: bool) -> void:
	var capacity := 8
	var visible_items: Array[Dictionary] = items.slice(0, mini(items.size(), capacity))
	if visible_items.is_empty():
		return
	var center := _vector("upper_status_anchor" if upper else "lower_status_anchor", Vector2(110, 38) if upper else Vector2(110, 105))
	var radius := _vector("upper_orbit_radius" if upper else "lower_orbit_radius", Vector2(53, 17) if upper else Vector2(59, 13))
	var orbit_scale := float(presentation.get("status_orbit_scale", 1.0))
	radius *= orbit_scale * 1.48
	for index in visible_items.size():
		var item: Dictionary = visible_items[index]
		var count := visible_items.size()
		var angle: float
		if upper and count <= 4:
			angle = lerpf(-PI * 0.82, -PI * 0.18, 0.5 if count == 1 else float(index) / float(count - 1))
		else:
			angle = -PI * 0.5 + TAU * float(index) / float(count)
		var local_radius := radius
		if not upper and item.kind == &"trap":
			local_radius *= 0.78
		var bob := sin(pulse_time * 1.8 + float(item.seed) * 0.71) * 1.5
		var position := center + Vector2(cos(angle) * local_radius.x, sin(angle) * local_radius.y + bob)
		var base_size := UPPER_STATUS_SIZE if upper else LOWER_STATUS_SIZE
		if count > 4:
			base_size *= 0.76
		_draw_world_object(item, position, base_size, angle)


func _draw_foot_rings(items: Array[Dictionary]) -> void:
	var visible_items: Array[Dictionary] = items.slice(0, mini(items.size(), 6))
	var center := foot_anchor()
	var base_scale := _vector("foot_status_scale", Vector2(1.0, 0.42))
	for index in visible_items.size():
		var item: Dictionary = visible_items[index]
		var expansion := 1.0 + index * 0.11
		var pulse := 1.0 + sin(pulse_time * 2.0 + index) * 0.025
		var texture := _status_texture(item)
		if texture == null:
			continue
		var accent := _accent(item.school)
		var visual_size := Vector2(FOOT_STATUS_SIZE, FOOT_STATUS_SIZE) * expansion
		draw_set_transform(center + ground_visual_offset(StringName(str(item.kind))), pulse_time * (0.018 if index % 2 == 0 else -0.014), Vector2(base_scale.x * pulse, base_scale.y * pulse))
		draw_texture_rect(texture, Rect2(-visual_size * 0.5, visual_size), false, Color(1, 1, 1, 0.94) if item.kind in [&"dot", &"hot"] else Color(accent.lightened(0.36), 0.76))
		if not item.kind in [&"dot", &"hot"]:
			_draw_school_rune(item.school, Vector2.ZERO, 27.0, 0.82)
		draw_set_transform(Vector2.ZERO)


func _draw_world_object(item: Dictionary, position: Vector2, visual_size: float, angle: float) -> void:
	var texture := _status_texture(item)
	if texture == null:
		return
	var accent := _accent(item.school)
	var rotation := 0.0
	if item.kind == &"trap":
		rotation = sin(pulse_time) * 0.06
	draw_circle(position, visual_size * 0.39, Color(accent, 0.09))
	draw_set_transform(position, rotation, Vector2.ONE)
	draw_texture_rect(texture, Rect2(Vector2.ONE * -visual_size * 0.5, Vector2.ONE * visual_size), false, Color.WHITE if item.kind in [&"shield", &"trap"] else Color(accent.lightened(0.38), 0.94))
	if not item.kind in [&"shield", &"trap"]:
		_draw_school_rune(item.school, Vector2.ZERO, 15.0, 0.92)
	draw_set_transform(Vector2.ZERO)


func foot_anchor() -> Vector2:
	# Ground statuses share the exact same local origin as the unit foot/selection ring.
	return LayoutProfile.UNIT_LOCAL_FOOT

static func ground_visual_offset(kind: StringName) -> Vector2:
	return GROUND_VISUAL_OFFSETS.get(kind, Vector2.ZERO)


func _draw_school_rune(school: StringName, position: Vector2, visual_size: float, alpha: float) -> void:
	if school in [&"", &"*"]:
		return
	var rune := ArtRegistryScript.texture(StringName("school_%s" % str(school)))
	if rune != null:
		draw_texture_rect(rune, Rect2(position - Vector2.ONE * visual_size * 0.5, Vector2.ONE * visual_size), false, Color(1, 1, 1, alpha))


func _draw_event_flashes() -> void:
	for flash in event_flashes:
		var progress := float(flash.get("time", 0.0)) / 0.38
		var kind := StringName(str(flash.get("kind", "")))
		var center := foot_anchor() + ground_visual_offset(kind)
		if kind in [&"blade", &"weakness"]:
			center = _vector("upper_status_anchor", Vector2(110, 38))
		elif kind in [&"shield", &"trap"]:
			center = _vector("lower_status_anchor", Vector2(110, 105))
		var spark := ArtRegistryScript.texture(&"world_status_spark")
		if spark != null:
			var size_value := 36.0 + progress * 42.0
			draw_texture_rect(spark, Rect2(center - Vector2.ONE * size_value * 0.5, Vector2.ONE * size_value), false, Color(1, 1, 1, 1.0 - progress))


func _vector(key: String, fallback: Vector2) -> Vector2:
	var value = presentation.get(key, [])
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback


func _accent(school: StringName) -> Color:
	return SCHOOL_COLORS.get(str(school), Color("#e7cf8a"))


func _status_texture(item: Dictionary) -> Texture2D:
	if item.kind in [&"shield", &"trap", &"dot", &"hot"]:
		var school := str(item.school)
		if school in ["", "*"]:
			school = "all"
		return ArtRegistryScript.texture(StringName("status_%s_%s" % [item.kind, school]))
	return ArtRegistryScript.texture(StringName("world_%s" % str(item.kind)))
