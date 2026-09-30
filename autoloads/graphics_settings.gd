extends Node
## Local presentation preferences; never stored in a character/cloud save.
signal changed
const CONFIG_PATH := "user://graphics_settings.cfg"
const RESOLUTIONS := [Vector2i(1280,720), Vector2i(1600,900), Vector2i(1920,1080), Vector2i(2560,1440), Vector2i(3840,2160)]
var quality := "high"
var active_quality := "high"
var particles_enabled := true
var fullscreen := false
var window_size := Vector2i(1280,720)
var config_path := CONFIG_PATH
var tracked: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	# Compatibility launchers and driver fallback always start with the low
	# preset, including the first launch and an older saved high preference.
	if not OS.has_feature("mobile") and RenderingServer.get_current_rendering_method() == "gl_compatibility":
		quality = "low"
	active_quality = quality
	if is_low():Engine.max_fps = 30
	# Rendering backends are selected before scripts run. Relaunch once with the
	# saved backend; keep an attempt marker so driver fallback cannot loop.
	if FileAccess.file_exists(config_path) and not OS.has_feature("mobile") and DisplayServer.get_name() != "headless" and not "--script" in OS.get_cmdline_args() and not "-s" in OS.get_cmdline_args():
		if RenderingServer.get_current_rendering_method() != desired_renderer() and not "--graphics-renderer-attempt" in OS.get_cmdline_user_args():
			restart_game()
	get_tree().node_added.connect(_node_added)
	call_deferred("_start")

func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(config_path) != OK:return
	quality = "low" if config.get_value("graphics","quality","high") == "low" else "high"
	particles_enabled = bool(config.get_value("graphics","particles",true))
	fullscreen = bool(config.get_value("display","fullscreen",false))
	var saved: Variant = config.get_value("display","window_size",Vector2i(1280,720))
	if saved in RESOLUTIONS:window_size = saved

func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("graphics","quality",quality)
	config.set_value("graphics","particles",particles_enabled)
	config.set_value("display","fullscreen",fullscreen)
	config.set_value("display","window_size",window_size)
	return config.save(config_path)

func _start() -> void:
	_scan(get_tree().root)
	apply_display()

func _scan(node: Node) -> void:
	_register(node)
	for child in node.get_children():_scan(child)

func _node_added(node: Node) -> void:
	# Scene builders frequently configure properties after add_child().
	if node is Light3D or _is_particle(node) or node.has_method("set_pip_particles_enabled"):
		call_deferred("_register_id",node.get_instance_id())

func _register_id(id: int) -> void:
	var node = instance_from_id(id)
	if is_instance_valid(node):_register(node)

func _is_particle(node: Node) -> bool:
	return node is GPUParticles3D or node is CPUParticles3D or node is GPUParticles2D or node is CPUParticles2D

func _register(node: Node) -> void:
	if not is_instance_valid(node) or node.has_meta("graphics_registered"):return
	if not (node is Light3D or _is_particle(node) or node.has_method("set_pip_particles_enabled")):return
	node.set_meta("graphics_registered",true)
	tracked[node.get_instance_id()] = weakref(node)
	node.tree_exiting.connect(_forget.bind(node.get_instance_id()),CONNECT_ONE_SHOT)
	_apply_node(node)

func _forget(id: int) -> void:
	tracked.erase(id)
	var node = instance_from_id(id)
	if is_instance_valid(node):node.remove_meta("graphics_registered")

func _override(object: Object, property: String, low_value: Variant, enabled: bool) -> void:
	var key := "graphics_original_" + property
	if enabled:
		if not object.has_meta(key):object.set_meta(key,object.get(property))
		object.set(property,low_value)
	elif object.has_meta(key):
		object.set(property,object.get_meta(key))
		object.remove_meta(key)

func _apply_node(node: Node) -> void:
	var low := is_low()
	if node is Light3D:_override(node,"shadow_enabled",false,low)
	if node.has_method("set_pip_particles_enabled"):
		node.set_pip_particles_enabled(particles_enabled)
	if _is_particle(node):
		_override(node,"visible",false,not particles_enabled)
		_override(node,"emitting",false,not particles_enabled)

func apply_graphics() -> void:
	for ref in tracked.values():
		var node = ref.get_ref()
		if is_instance_valid(node):
			_apply_node(node)
	changed.emit()

func apply_display() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile"):return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var screen := DisplayServer.window_get_current_screen()
		var usable := DisplayServer.screen_get_usable_rect(screen)
		var actual := window_size.min((usable.size - Vector2i(32,64)).max(Vector2i(640,360)))
		DisplayServer.window_set_size(actual)
		DisplayServer.window_set_position(usable.position + (usable.size-actual)/2)

func open_panel(parent: Node) -> void:
	if parent.get_node_or_null("GraphicsSettingsPanel") != null:return
	var panel = load("res://scripts/fusion_3d/graphics_settings_panel.gd").new()
	panel.name = "GraphicsSettingsPanel"
	parent.add_child(panel)

func is_low() -> bool:
	return active_quality == "low"

func desired_renderer() -> String:
	return "gl_compatibility" if quality == "low" else "forward_plus"

func restart_required() -> bool:
	return active_quality != quality or (not OS.has_feature("mobile") and RenderingServer.get_current_rendering_method() != desired_renderer())

func restart_arguments() -> PackedStringArray:
	var result := PackedStringArray()
	var skip_next := false
	for argument in OS.get_cmdline_args():
		if skip_next:
			skip_next=false
			continue
		if argument == "--":break
		if argument in ["--rendering-method","--rendering-driver","--max-fps"]:
			skip_next=true
			continue
		if argument in ["--fullscreen","-f","--windowed","-w","--editor","-e"]:continue
		result.append(argument)
	if not OS.has_feature("standalone") and not "--path" in result:
		result.append_array(["--path",ProjectSettings.globalize_path("res://")])
	result.append_array(["--rendering-method",desired_renderer(),"--max-fps","30" if quality == "low" else "0"])
	result.append("--fullscreen" if fullscreen else "--windowed")
	result.append("--")
	for argument in OS.get_cmdline_user_args():
		if argument in ["--graphics-renderer-attempt","--frost-variants-off","--frost-environment-off","--frost-atmosphere-off"]:continue
		result.append(argument)
	result.append("--graphics-renderer-attempt")
	return result

func restart_game() -> void:
	OS.set_restart_on_exit(true,restart_arguments())
	if get_tree().has_method("record_graceful_exit"):get_tree().record_graceful_exit()
	get_tree().quit()
