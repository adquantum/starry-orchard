extends CanvasLayer

signal transition_finished

var pending_spawn_id: StringName = &"default"
var transitioning := false
var _requested: Dictionary = {}
var _veil: ColorRect
var _rune: Label

func _ready() -> void:
	layer = 900
	_veil = ColorRect.new()
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_veil.color = Color(0.025, 0.018, 0.075, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_veil)
	_rune = Label.new()
	_rune.set_anchors_preset(Control.PRESET_CENTER)
	_rune.position = Vector2(-70, -52)
	_rune.size = Vector2(140, 104)
	_rune.text = "?"
	_rune.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rune.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_rune.add_theme_font_size_override("font_size", 62)
	_rune.add_theme_color_override("font_color", Color(0.75, 0.56, 1.0, 0.0))
	_rune.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rune)

func preload_zone(scene_path: String) -> void:
	if scene_path.is_empty() or _requested.has(scene_path):
		return
	if ResourceLoader.load_threaded_request(scene_path) == OK:
		_requested[scene_path] = true

func travel_to(scene_path: String, spawn_id: StringName = &"default") -> void:
	if transitioning or scene_path.is_empty():
		return
	transitioning = true
	pending_spawn_id = spawn_id
	preload_zone(scene_path)
	var packed := await _await_zone(scene_path)
	if packed == null:
		push_error("World transition could not load %s" % scene_path)
		transitioning = false
		return
	_veil.mouse_filter = Control.MOUSE_FILTER_STOP
	var cover := create_tween().set_parallel(true)
	cover.tween_property(_veil, "color:a", 0.92, 0.22)
	cover.tween_property(_rune, "theme_override_colors/font_color:a", 1.0, 0.22)
	cover.tween_property(_rune, "rotation", TAU * 0.125, 0.22)
	await cover.finished
	get_tree().change_scene_to_packed(packed)
	await get_tree().process_frame
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(_veil, "color:a", 0.0, 0.28)
	reveal.tween_property(_rune, "theme_override_colors/font_color:a", 0.0, 0.2)
	reveal.tween_property(_rune, "rotation", TAU * 0.25, 0.28)
	await reveal.finished
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	transitioning = false
	transition_finished.emit()

func consume_spawn(default_id: StringName = &"default") -> StringName:
	var result := pending_spawn_id if pending_spawn_id != &"" else default_id
	pending_spawn_id = &""
	return result

func _await_zone(scene_path: String) -> PackedScene:
	for _frame in 600:
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(scene_path) as PackedScene
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			break
		await get_tree().process_frame
	return load(scene_path) as PackedScene
