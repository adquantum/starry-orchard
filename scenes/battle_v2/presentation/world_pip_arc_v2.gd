class_name WorldPipArcV2
extends Control

const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")

var unit: BattleUnitStateV2
var presentation: Dictionary = {}
var pulse_time := 0.0


func setup(p_unit: BattleUnitStateV2, p_presentation: Dictionary) -> void:
	unit = p_unit
	presentation = p_presentation.duplicate(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(true)
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _process(delta: float) -> void:
	pulse_time += delta
	if unit != null and not unit.resources.pips.is_empty():
		queue_redraw()


func _draw() -> void:
	if unit == null or not unit.alive:
		return
	var center := _vector("foot_status_anchor", Vector2(110, 132)) + Vector2(0, -19)
	var radius := Vector2(74, 24)
	var count := ResourceStateV2.MAX_PIPS
	for index in count:
		var angle := lerpf(PI * 0.12, PI * 0.88, float(index) / float(count - 1))
		var position := center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)
		if index >= unit.resources.pips.size():
			var empty := ArtRegistryScript.texture(&"pip_v2_empty")
			if empty != null:
				draw_texture_rect(empty, Rect2(position - Vector2(8, 8), Vector2(16, 16)), false, Color(1, 1, 1, 0.14))
			continue
		var asset_id := _asset_id(index)
		var texture := ArtRegistryScript.texture(asset_id)
		if texture == null:
			continue
		var pulse := 1.0 + sin(pulse_time * 2.2 + index * 0.7) * 0.035
		var visual_size := Vector2.ONE * 22.0 * pulse
		draw_circle(position, 9.5, Color(0.22, 0.68, 1.0, 0.08))
		draw_texture_rect(texture, Rect2(position - visual_size * 0.5, visual_size), false)


func _asset_id(index: int) -> StringName:
	match unit.resources.pips[index]:
		ResourceStateV2.PipKind.NORMAL:
			return &"pip_v2_normal"
		ResourceStateV2.PipKind.POWER:
			return &"pip_v2_power"
		ResourceStateV2.PipKind.SCHOOL:
			return StringName("pip_v2_%s" % str(unit.resources.pip_schools[index]))
	return &"pip_v2_empty"


func _vector(key: String, fallback: Vector2) -> Vector2:
	var value = presentation.get(key, [])
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
