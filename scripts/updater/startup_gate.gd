extends Control
## Resource-free shell gate: no business or update-screen preload/typed use.
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var startup = get_tree()
	if not startup.has_method("get_update_status"):
		_show_error("STARTUP_GATE_UNAVAILABLE"); return
	startup.attach_runtime()
	var status: Dictionary = startup.get_update_status()
	if not status.get("business_allowed",false):
		_show_error(str(status.get("code","BOOT_CHECK_FAILED"))); return
	call_deferred("_open_business")

func _open_business() -> void:
	var startup = get_tree()
	if not startup.get_update_status().get("business_allowed",false): return
	# Dynamic load occurs only after the trusted shell allowed all business.
	var scene = load("res://scenes/fusion_3d/studio_boot.tscn") as PackedScene
	if scene == null:
		startup.report_boot_failure(); return
	var error: int = startup.change_scene_to_packed(scene)
	if error != OK: startup.report_boot_failure()

func _show_error(code: String) -> void:
	var background := ColorRect.new()
	background.color = Color("071423")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	var stack := VBoxContainer.new(); stack.custom_minimum_size = Vector2(560,0)
	stack.add_theme_constant_override("separation",18); center.add_child(stack)
	var title := Label.new(); title.text = "暂时无法启动"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; title.add_theme_font_size_override("font_size",30); stack.add_child(title)
	var detail := Label.new(); detail.text = "请关闭后重新打开游戏。更新恢复不会改变你的存档。"
	if code == "RECOVERY_FAILED": detail.text = "更新恢复未完成。请保留游戏数据，稍后重试或更新安装包。"
	if code == "CANDIDATE_CLOSED_TWICE": detail.text = "更新启动尚未确认。你可以在下次打开时使用上次可用版本。"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; stack.add_child(detail)
	var diagnostic := Label.new(); diagnostic.text = "诊断编号："+code
	diagnostic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; stack.add_child(diagnostic)
	if code == "CANDIDATE_CLOSED_TWICE":
		var previous := Button.new(); previous.text = "下次使用上次可用版本"
		previous.pressed.connect(func():
			var result: Dictionary = get_tree().allow_confirmed_on_next_launch()
			if result.ok: get_tree().quit())
		stack.add_child(previous)
	var close := Button.new(); close.text = "关闭游戏"
	close.pressed.connect(func(): get_tree().record_graceful_exit(); get_tree().quit())
	stack.add_child(close)
