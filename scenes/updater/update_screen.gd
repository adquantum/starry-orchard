extends Control

const CLIENT_SCRIPT := "res://scripts/updater/update_client.gd"
const GOLD := Color("f3d591")
const PALE := Color("d7e1e5")
const DIM := Color("aabdc8")

var client: Node
var context: Dictionary = {}
var known: Dictionary = {}
var latest: Dictionary = {}
var outcome: Dictionary = {}
var waiting := false
var checking := false
var installer_url := ""
var state_code := "CHECKING"
var title_label: Label
var detail_label: Label
var notes_label: Label
var size_label: Label
var progress_bar: ProgressBar
var retry_button: Button
var continue_button: Button
var install_button: Button
var close_button: Button
var _english := false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_english = TranslationServer.get_locale().begins_with("en")
	_build()
	_show("CHECKING", _tr("正在检查更新…", "Checking for updates…"))

func run_update_flow(start_context: Dictionary) -> Dictionary:
	context = start_context.duplicate(true)
	if not context.get("enabled", false):
		return {"allow_business":true,"code":"UPDATES_NOT_CONFIGURED"}
	if title_label == null:
		_build()
	await get_tree().process_frame
	if context.get("in_battle", false):
		_show("BATTLE_NOTICE_ONLY", _tr("有更新可用。战斗结束后重新打开游戏以检查。", "An update is available. Check again after the battle."))
		return {"allow_business":context.get("status", {}).get("business_allowed", true),"code":"BATTLE_NOTICE_ONLY"}
	var script := load(CLIENT_SCRIPT) as GDScript
	if script == null:
		_show("UPDATE_CLIENT_MISSING", _tr("更新组件不可用，请重试。", "Update service is unavailable. Please retry."))
		return {"allow_business":false,"code":"UPDATE_CLIENT_MISSING"}
	client = script.new()
	add_child(client)
	var active: Dictionary = context.get("current", {})
	var highest_hash := str(context.get("highest_manifest_sha256", ""))
	var acceptance := {
		"highest_release_seq":int(context.get("highest_release_seq", 0)),
		"allow_same_release_manifest_sha256":highest_hash,
		"current_manifest_sha256":str(active.get("manifest_sha256", "")),
		"rejected_manifest_sha256":context.get("rejected_manifest_sha256", null)
	}
	client.configure(context.get("installation", {}), acceptance)
	client.manifest_available.connect(_on_manifest)
	client.download_progress.connect(_on_progress)
	known = client.read_known_requirement()
	var status: Dictionary = context.get("status", {})
	if not status.get("business_allowed", true):
		_show("STARTUP_BLOCKED", _tr("当前版本未能安全启动。请重新打开游戏或重试更新。", "This version did not start safely. Reopen the game or retry the update."))
		return {"allow_business":false,"code":str(status.get("code", "STARTUP_BLOCKED"))}
	_apply_known()
	var installation: Dictionary = context.get("installation", {})
	var manifest_url := str(installation.get("manifest_url", ""))
	var signature_url := str(installation.get("signature_url", ""))
	if manifest_url.is_empty() or signature_url.is_empty():
		if _known_blocks():
			_show_known_block()
			retry_button.visible = false
			return {"allow_business":false,"code":state_code}
		_show("REMOTE_NOT_CONFIGURED", _tr("尚未配置在线更新。可继续使用当前版本；服务器当前要求未知。", "Online updates are not configured. You may use this version; current server requirements are unknown."))
		return {"allow_business":true,"code":"REMOTE_NOT_CONFIGURED"}
	while true:
		await _check_once(manifest_url, signature_url)
		if not outcome.is_empty():
			return outcome
		waiting = true
		while waiting:
			await get_tree().process_frame
		if not outcome.is_empty():
			return outcome
	return {"allow_business":false,"code":"FLOW_STOPPED"}

func _check_once(manifest_url: String, signature_url: String) -> void:
	checking = true
	_show("CHECKING", _tr("正在检查更新…", "Checking for updates…"))
	retry_button.disabled = true
	continue_button.disabled = true
	var result: Dictionary = await client.check(manifest_url, signature_url)
	checking = false
	if result.get("ok", false):
		if result.get("code", "") == "UP_TO_DATE":
			outcome = {"allow_business":true,"code":"UP_TO_DATE"}
			return
		if result.has("descriptor_path"):
			var accepted: Dictionary = get_tree().accept_candidate_ready(str(result.descriptor_path))
			if not accepted.get("ok", false):
				_show("ACTIVATION_REJECTED", _tr("更新已下载，但无法安排下次启动。请重试。", "Downloaded update could not be prepared for the next launch. Please retry."))
				retry_button.visible = true
				retry_button.disabled = false
				if not _known_blocks():
					continue_button.visible = true
					continue_button.disabled = false
				return
			if accepted.get("restart_required", false):
				_show("READY_NEXT_LAUNCH", _tr("更新已准备好。关闭并重新打开游戏后生效。", "Update is ready. Close and reopen the game to apply it."))
				size_label.text = _tr("已下载：", "Downloaded: ") + _format_bytes(int(latest.get("missing_bytes", 0)))
				progress_bar.value = 100
				if _target_required():
					outcome = {"allow_business":false,"code":"READY_NEXT_LAUNCH"}
				else:
					continue_button.visible = true
					continue_button.disabled = false
				close_button.visible = true
				return
		outcome = {"allow_business":true,"code":"CURRENT"}
		return
	if result.get("code", "") == "SHELL_UPGRADE_REQUIRED":
		_show_known_block()
		return
	known = client.read_known_requirement()
	_apply_known()
	if _known_blocks():
		_show_known_block()
		detail_label.text += "\n" + _failure_text(str(result.get("code", "NETWORK_OFFLINE")))
		return
	var code := str(result.get("code", "NETWORK_OFFLINE"))
	var message := _failure_text(code)
	_show(code, message)
	retry_button.visible = true
	retry_button.disabled = false
	continue_button.visible = true
	continue_button.disabled = false

func _apply_known() -> void:
	if known.get("ok", false):
		latest = known.duplicate(true)
		_set_notes(str(known.get("notes", "")))
		installer_url = str(known.get("base_installer_url", "")) if known.get("shell_upgrade_required", false) else ""
		install_button.visible = not installer_url.is_empty()

func _known_blocks() -> bool:
	if not latest.get("ok", false): return false
	return _target_required()

func _target_required() -> bool:
	var target := latest
	if not target.get("required", false): return false
	var current: Dictionary = context.get("current", {})
	return str(target.get("manifest_sha256", "")) != str(current.get("manifest_sha256", ""))

func _show_known_block() -> void:
	if latest.get("shell_upgrade_required", false):
		_show("SHELL_UPGRADE_REQUIRED", _tr("需要安装新版游戏程序。", "A new game installation is required."))
	elif latest.get("failed_candidate", false):
		_show("CANDIDATE_PREVIOUSLY_FAILED", _tr("此必需更新此前启动失败。请等待新版或使用完整安装包。", "This required update failed to start before. Please wait for a new release or reinstall."))
	else:
		_show("REQUIRED_UPDATE_PENDING", _tr("必须先完成更新并重新打开游戏。", "Complete the required update and reopen the game."))
	retry_button.visible = true
	retry_button.disabled = false
	continue_button.visible = not _known_blocks()
	continue_button.disabled = _known_blocks()

func _on_manifest(info: Dictionary) -> void:
	latest = info.duplicate(true)
	latest["ok"] = true
	installer_url = ""
	install_button.visible = false
	_set_notes(str(info.get("notes", "")))
	var bytes := int(info.get("missing_bytes", 0))
	size_label.text = _tr("本次更新：", "This update: ") + _format_bytes(bytes)
	progress_bar.visible = bytes > 0
	progress_bar.value = 0
	if info.get("shell_upgrade_required", false):
		installer_url = str(info.get("base_installer_url", ""))
		install_button.visible = not installer_url.is_empty()
		_show("SHELL_UPGRADE_REQUIRED", _tr("需要安装新版游戏程序。", "A new game installation is required."))
	elif bytes > 0:
		_show("DOWNLOADING", _tr("正在下载已验证的更新清单所列内容…", "Downloading the verified update…"))
	else:
		_show("PREPARING", _tr("正在验证更新…", "Verifying update…"))

func _on_progress(_package_id: String, received: int, total: int) -> void:
	progress_bar.visible = true
	progress_bar.value = clampf(float(received) * 100.0 / maxf(float(total), 1.0), 0.0, 100.0)
	detail_label.text = _tr("正在下载：", "Downloading: ") + _format_bytes(received) + " / " + _format_bytes(total)

func _failure_text(code: String) -> String:
	match code:
		"INSUFFICIENT_SPACE": return _tr("存储空间不足。清理空间后重试。", "Not enough storage. Free space and retry.")
		"NETWORK_OFFLINE": return _tr("无法连接更新服务。请重试。", "Cannot reach updates. Please retry.")
		"DOWNLOAD_RETRY_EXHAUSTED": return _tr("下载多次失败。请检查网络后重试。", "Download failed repeatedly. Check your connection and retry.")
		"CANDIDATE_PREVIOUSLY_FAILED": return _tr("此更新此前启动失败。", "This update failed to start before.")
		_: return _tr("更新检查失败（%s）。可重试。", "Update check failed (%s). Retry.") % code

func _show(code: String, detail: String) -> void:
	state_code = code
	title_label.text = _tr("星界果园 · 更新", "STARRY ORCHARD · UPDATE")
	detail_label.text = detail
	retry_button.visible = false
	continue_button.visible = false
	close_button.visible = false

func _build() -> void:
	if title_label != null: return
	var backdrop := ColorRect.new()
	backdrop.color = Color("071423")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scroll.custom_minimum_size = Vector2(0, 0)
	center.add_child(scroll)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("112536")
	style.border_color = Color("a88c55")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	scroll.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 13)
	panel.add_child(stack)
	title_label = _label("", 31, GOLD)
	stack.add_child(title_label)
	detail_label = _label("", 21, PALE)
	stack.add_child(detail_label)
	size_label = _label("", 17, DIM)
	stack.add_child(size_label)
	progress_bar = ProgressBar.new()
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size.y = 12
	progress_bar.visible = false
	stack.add_child(progress_bar)
	notes_label = _label("", 17, DIM)
	stack.add_child(notes_label)
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 10)
	buttons.add_theme_constant_override("v_separation", 8)
	stack.add_child(buttons)
	retry_button = _button(_tr("重试", "Retry"), buttons, _on_retry)
	continue_button = _button(_tr("继续当前版本", "Continue current version"), buttons, _on_continue)
	install_button = _button(_tr("打开安装页面", "Open installation page"), buttons, _on_install)
	install_button.visible = false
	close_button = _button(_tr("关闭游戏", "Close game"), buttons, _on_close)
	close_button.visible = false
	resized.connect(_fit_panel.bind(scroll))
	_fit_panel(scroll)

func _fit_panel(scroll: ScrollContainer) -> void:
	scroll.custom_minimum_size.x = minf(maxf(size.x - 24.0, 100.0), 730.0)
	scroll.custom_minimum_size.y = minf(maxf(size.y - 24.0, 160.0), 560.0)
	(scroll.get_child(0) as Control).custom_minimum_size.x = scroll.custom_minimum_size.x - 8.0

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(value: String, parent: Control, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(155, 48)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _set_notes(value: String) -> void:
	notes_label.text = (_tr("更新公告：", "Release notes: ") + value) if not value.is_empty() else ""

func _format_bytes(value: int) -> String:
	if value >= 1000000: return "%.2f MB" % (float(value) / 1000000.0)
	if value >= 1000: return "%.1f KB" % (float(value) / 1000.0)
	return "%d B" % value

func _tr(zh: String, en: String) -> String:
	return en if _english else zh

func _on_retry() -> void:
	if checking: return
	waiting = false

func _on_continue() -> void:
	if _known_blocks(): return
	outcome = {"allow_business":true,"code":state_code}
	waiting = false

func _on_install() -> void:
	if not installer_url.is_empty():
		OS.shell_open(installer_url)

func _on_close() -> void:
	if get_tree().has_method("record_graceful_exit"):
		get_tree().record_graceful_exit()
	get_tree().quit()
