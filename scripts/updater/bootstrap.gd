class_name ClientUpdateTree
extends SceneTree
## Stable program-shell entry. Never preload or type-reference gameplay/UI.
## A custom SceneTree is constructed before Godot snapshots its Autoload list.
signal update_status_changed(status: Dictionary)
const INSTALLATION_PATH := "res://scripts/updater/installation.json"
const CACHE := "user://client_update/cache/"
const SAFE_SCENE := "res://scripts/updater/startup_gate.tscn"
const BUSINESS_AUTOLOADS := ["Accounts","Wardrobe","Locale","WorldTransitionManager","DemoSession","GraphicsSettings"]
const STORE = preload("res://scripts/updater/activation_store.gd")
var activation = STORE.new()
var validator
var installation: Dictionary = {}
var state: Dictionary = {}
var update_status: Dictionary = {"phase":"disabled","code":"UPDATES_NOT_CONFIGURED","business_allowed":true,"restart_required":false}
var update_enabled := false
var mounted_any := false
var recovery_mode := false
var startup_hold := false
var base_identity: Dictionary = {}
var _exit_recorded := false
var _runtime_attached := false

func _init() -> void:
	var production_required := OS.has_feature("client_update_production_windows")
	if production_required:
		var trust_script = load("res://scripts/updater/installation_trust.gd")
		if trust_script == null:
			_block("INSTALLATION_METADATA_INVALID"); return
		var trusted: Dictionary = trust_script.new().read_verified()
		if not trusted.ok:
			_block(str(trusted.code)); return
		installation = trusted.installation
	else:
		if not FileAccess.file_exists(INSTALLATION_PATH): return
		var file = FileAccess.open(INSTALLATION_PATH,FileAccess.READ)
		if file == null or file.get_length() > 65536:
			_block("INSTALLATION_METADATA_INVALID"); return
		var data: Variant = JSON.parse_string(file.get_as_text()); file.close()
		if not data is Dictionary:
			_block("INSTALLATION_METADATA_INVALID"); return
		installation = data
	# The work-in-progress project has no installation metadata or update URL.
	# No cache, network client, or publisher key is consulted in this default path.
	if installation.get("updates_enabled",false) != true: return
	var fixture_signature: bool = OS.has_feature("client_update_fixture") and installation.get("test_signature_mode",false) == true
	if not production_required and not fixture_signature:
		update_status.code = "SIGNATURE_SCHEME_UNAVAILABLE"; return
	if not activation.hash_valid(installation.get("base_manifest_sha256")) or not activation.integer_valid(installation.get("base_release_seq",0)):
		_block("INSTALLATION_METADATA_INVALID"); return
	var validator_script = load("res://scripts/updater/manifest_validator.gd")
	if validator_script == null:
		_block("SIGNATURE_SCHEME_UNAVAILABLE"); return
	validator = validator_script.new(); validator.configure(installation)
	update_enabled = true
	base_identity = {"manifest_sha256":installation.base_manifest_sha256,"release_seq":installation.get("base_release_seq",0),"package_sha256_ordered":[]}
	var binding: Dictionary = {}
	for key in ["channel","base_id","base_sha256","platform","arch","export_profile_id","engine_version"]: binding[key] = installation.get(key)
	if not activation.binding_valid(binding):
		_block("INSTALLATION_METADATA_INVALID"); return
	var loaded: Dictionary = activation.read_state(base_identity,binding)
	if not loaded.ok:
		_block(str(loaded.code)); return
	state = loaded.state
	var plan: Dictionary = activation.start_plan(state)
	if not plan.ok:
		_block(str(plan.code)); return
	state = plan.state; recovery_mode = plan.mode == "recovery"; startup_hold = plan.hold
	var verified: Dictionary = _verify_identity(state.active,plan.mode != "candidate")
	if not verified.ok:
		_mark_failure(str(verified.code)); return
	# Persist the attempt before the first mount. A later crash is distinguishable
	# from normal exit; an unfinished recovery can never auto-restart in a loop.
	if plan.mode != "confirmed":
		activation.attempt(state,"mounting")
	if not _commit(): return
	for package_path in verified.packages:
		if not ProjectSettings.load_resource_pack(str(package_path),true):
			_mark_failure("MOUNT_FAILED"); return
		mounted_any = true
	if plan.mode != "confirmed":
		activation.attempt(state,"boot_check")
		if not _commit(): return
	if startup_hold:
		state.attempt = null
		if not _commit(): return
		_block("CANDIDATE_CLOSED_TWICE",false); return
	update_status = {"phase":"starting","code":"OK","business_allowed":true,"restart_required":false,"recovery":recovery_mode}

func _verify_identity(identity: Dictionary, local_restore: bool) -> Dictionary:
	if activation.same_identity(identity,base_identity): return {"ok":true,"packages":[],"identity":base_identity}
	if not activation.identity_valid(identity): return {"ok":false,"code":"ACTIVATION_STATE_INVALID"}
	var acceptance: Dictionary = {"highest_release_seq":int(state.highest_release_seq),"owned_item_required_catalog_revision":installation.get("catalog_revision",0)}
	if local_restore:
		acceptance.local_recovery_manifest_sha256 = identity.manifest_sha256
	else:
		acceptance.allow_same_release_manifest_sha256 = state.highest_manifest_sha256
		acceptance.rejected_manifest_sha256 = state.rejected_manifest_sha256
	var verified: Dictionary = validator.verify_ready(CACHE+"ready_"+str(identity.manifest_sha256)+".json",acceptance)
	if not verified.get("ok",false): return verified
	if not activation.same_identity(verified.identity,identity): return {"ok":false,"code":"ACTIVATION_IDENTITY_MISMATCH"}
	return verified

func _commit() -> bool:
	var result: Dictionary = activation.write_state(state)
	if not result.ok:
		_block(str(result.code)); return false
	return true

func _mark_failure(code: String) -> void:
	if not state.is_empty():
		state.rejected_manifest_sha256 = state.active.manifest_sha256
		activation.attempt(state,"failed",code)
		var written: Dictionary = activation.write_state(state)
		if not written.ok: code = str(written.code)
	_block(code)

func _block(code: String, restart_required: bool = true) -> void:
	update_status = {"phase":"blocked","code":code,"business_allowed":false,"restart_required":restart_required,"recovery":recovery_mode}
	# This runs before main.cpp copies the Autoload list, unlike first-Autoload
	# quit(), which only requests deferred exit and still loads later scripts.
	for singleton_name in BUSINESS_AUTOLOADS:
		ProjectSettings.set_setting("autoload/"+singleton_name,null)

func get_update_status() -> Dictionary:
	return update_status.duplicate(true)

func attach_runtime() -> void:
	if _runtime_attached: return
	_runtime_attached = true
	scene_changed.connect(_on_scene_changed)
	root.close_requested.connect(record_graceful_exit)
	if root.has_signal("go_back_requested"): root.connect("go_back_requested",record_graceful_exit)

func _on_scene_changed() -> void:
	if current_scene != null and current_scene.scene_file_path == "res://scenes/fusion_3d/account_menu.tscn":
		confirm_startup()

func confirm_startup() -> Dictionary:
	if not update_enabled: return {"ok":true,"disabled":true}
	if not update_status.business_allowed: return {"ok":false,"code":update_status.code}
	for singleton_name in BUSINESS_AUTOLOADS:
		var singleton = root.get_node_or_null(str(singleton_name))
		if singleton == null or not singleton.is_node_ready(): return {"ok":false,"code":"BOOT_CHECK_FAILED"}
	state.confirmed = state.active.duplicate(true)
	if state.pending != null and state.pending.manifest_sha256 == state.active.manifest_sha256: state.pending = null
	state.attempt = null; state.candidate_graceful_exits = 0
	if not _commit(): return {"ok":false,"code":update_status.code}
	update_status.phase = "confirmed"; update_status_changed.emit(get_update_status())
	return {"ok":true}

func get_update_context() -> Dictionary:
	return {"enabled":update_enabled,"installation":installation.duplicate(true),"current":state.get("active",{}),"confirmed":state.get("confirmed",{}),"pending":state.get("pending"),"highest_release_seq":int(state.get("highest_release_seq",0)),"highest_manifest_sha256":state.get("highest_manifest_sha256",""),"rejected_manifest_sha256":state.get("rejected_manifest_sha256"),"status":get_update_status()}.duplicate(true)

func accept_candidate_ready(descriptor_path: String) -> Dictionary:
	if not update_enabled: return {"ok":false,"code":"SIGNATURE_SCHEME_UNAVAILABLE"}
	if not update_status.business_allowed or (state.attempt != null and state.attempt.status != "boot_check"): return {"ok":false,"code":"BOOT_NOT_CONFIRMED"}
	var verified: Dictionary = validator.verify_ready(descriptor_path,{"highest_release_seq":int(state.highest_release_seq),"allow_same_release_manifest_sha256":state.highest_manifest_sha256,"rejected_manifest_sha256":state.rejected_manifest_sha256,"owned_item_required_catalog_revision":installation.get("catalog_revision",0)})
	if not verified.get("ok",false): return verified
	if state.pending != null and activation.same_identity(verified.identity,state.pending):
		return {"ok":true,"identity":verified.identity,"restart_required":not activation.same_identity(verified.identity,state.active),"idempotent":true}
	if activation.same_identity(verified.identity,state.active):
		return {"ok":true,"identity":verified.identity,"restart_required":false,"already_current":true}
	state.pending = verified.identity.duplicate(true)
	state.highest_release_seq = verified.identity.release_seq
	state.highest_manifest_sha256 = verified.identity.manifest_sha256
	state.recovery_tries = 0; state.candidate_graceful_exits = 0
	if not _commit(): return {"ok":false,"code":update_status.code}
	update_status.phase = "ready_next_launch"; update_status.restart_required = true
	update_status_changed.emit(get_update_status())
	return {"ok":true,"identity":verified.identity,"restart_required":true}

func allow_confirmed_on_next_launch() -> Dictionary:
	if not update_enabled or state.is_empty() or int(state.candidate_graceful_exits) < 2: return {"ok":false,"code":"NO_USER_ACTION_PENDING"}
	state.pending = null; state.active = state.confirmed.duplicate(true)
	state.attempt = null; state.candidate_graceful_exits = 0
	if not _commit(): return {"ok":false,"code":update_status.code}
	update_status.restart_required = true
	return {"ok":true,"restart_required":true}

func record_graceful_exit() -> void:
	if _exit_recorded or not update_enabled or state.is_empty(): return
	_exit_recorded = true
	if activation.graceful_exit(state): _commit()

func report_boot_failure(code: String = "BOOT_CHECK_FAILED") -> void:
	if update_enabled and not state.is_empty(): _mark_failure(code)
	else: _block(code)
	# If scene startup itself failed after Autoloads, freeze their processing and
	# show only the shell error UI. No attempt is made to unload mounted packs.
	paused = true
	call_deferred("change_scene_to_file",SAFE_SCENE)
