extends Node

signal check_started
signal manifest_rejected(code: String)
signal download_progress(package_id: String, received: int, total: int)
signal download_failed(code: String, retryable: bool)
signal candidate_ready(descriptor_path: String)
signal up_to_date
signal shell_upgrade_required(url: String)
signal manifest_available(info: Dictionary)

const ValidatorScript = preload("res://scripts/updater/manifest_validator.gd")
const CacheScript = preload("res://scripts/updater/download_cache.gd")
const MAX_RETRIES := 3

var validator: RefCounted
var cache: RefCounted
var installation: Dictionary = {}
var acceptance: Dictionary = {}
var _busy := false
var last_error: Dictionary = {}

func configure(installed: Dictionary, accepted: Dictionary = {}) -> void:
	installation = installed.duplicate(true)
	acceptance = accepted.duplicate(true)
	validator = ValidatorScript.new()
	validator.configure(installation)
	cache = CacheScript.new()
	cache.configure(validator, installation)

func check(manifest_url: String, signature_url: String) -> Dictionary:
	if _busy:
		return _fail("HTTP_FAILURE")
	_busy = true
	check_started.emit()
	var result := await _check_inner(manifest_url, signature_url)
	_busy = false
	return result

func _check_inner(manifest_url: String, signature_url: String) -> Dictionary:
	if validator == null or not validator.trusted_url(manifest_url) or not validator.trusted_url(signature_url):
		_emit_rejected("HTTP_UNTRUSTED_ORIGIN", "source")
		return _fail("HTTP_UNTRUSTED_ORIGIN")
	var manifest_result := await _fetch_bytes(manifest_url, ValidatorScript.MAX_MANIFEST)
	if not manifest_result.ok:
		_emit_failed(manifest_result.code, true, "manifest_fetch")
		return manifest_result
	var signature_result := await _fetch_bytes(signature_url, ValidatorScript.MAX_SIGNATURE)
	if not signature_result.ok:
		_emit_failed(signature_result.code, true, "signature_fetch")
		return signature_result
	var network_acceptance := acceptance.duplicate()
	network_acceptance.erase("local_recovery_manifest_sha256")
	var verified: Dictionary = validator.verify_manifest(manifest_result.bytes, signature_result.bytes, network_acceptance)
	if not verified.ok:
		if verified.code == "SHELL_UPGRADE_REQUIRED":
			var shell_cache: Dictionary = cache.ensure_cache()
			if not shell_cache.ok:
				_emit_failed(shell_cache.code, false, "cache")
				return shell_cache
			var shell_saved: Dictionary = cache.write_verified_manifest(manifest_result.bytes, signature_result.bytes)
			if not shell_saved.ok:
				_emit_failed(shell_saved.code, false, "cache")
				return shell_saved
			var shell_manifest: Dictionary = verified.manifest
			manifest_available.emit({"manifest_sha256":verified.manifest_sha256,"release_seq":shell_manifest.release_seq,"notes":shell_manifest.notes,"required":shell_manifest.required,"missing_bytes":0,"content_version":shell_manifest.content_version,"shell_upgrade_required":true,"base_installer_url":verified.base_installer_url})
			_record_error(verified.code, "manifest_verify")
			shell_upgrade_required.emit(verified.get("base_installer_url", ""))
		else:
			_emit_rejected(verified.code, "manifest_verify")
		return verified
	var manifest: Dictionary = verified.manifest
	var local: Dictionary = cache.ensure_cache()
	if not local.ok:
		_emit_failed(local.code, false, "cache")
		return local
	var saved: Dictionary = cache.write_verified_manifest(manifest_result.bytes, signature_result.bytes)
	if not saved.ok:
		_emit_failed(saved.code, false, "cache")
		return saved
	var missing: Array = []
	var missing_bytes := 0
	for p in manifest.packages:
		if not cache.cached(p):
			missing.append(p)
			missing_bytes += p.size_bytes
	manifest_available.emit({"manifest_sha256":verified.manifest_sha256,"release_seq":manifest.release_seq,"notes":manifest.notes,"required":manifest.required,"missing_bytes":missing_bytes,"content_version":manifest.content_version})
	if missing.is_empty() and manifest.release_seq == acceptance.get("highest_release_seq", -1) and verified.manifest_sha256 == acceptance.get("current_manifest_sha256", ""):
		up_to_date.emit()
		return {"ok":true,"code":"UP_TO_DATE"}
	for package in missing:
		if not cache.enough_space(package.size_bytes):
			_emit_failed("INSUFFICIENT_SPACE", false, "space")
			return _fail("INSUFFICIENT_SPACE")
		var downloaded := false
		var last_code := "HTTP_FAILURE"
		for attempt in MAX_RETRIES:
			var outcome := await _download_package(package)
			if outcome.ok:
				downloaded = true
				break
			last_code = outcome.code
			if last_code == "INSUFFICIENT_SPACE" or last_code == "HTTP_UNTRUSTED_ORIGIN":
				break
		if not downloaded:
			var code := last_code if last_code == "INSUFFICIENT_SPACE" else "DOWNLOAD_RETRY_EXHAUSTED"
			_emit_failed(code, code != "INSUFFICIENT_SPACE", "package_download")
			return _fail(code)
	var ready: Dictionary = cache.write_ready(manifest_result.bytes, signature_result.bytes, manifest)
	if not ready.ok:
		_emit_failed(ready.code, false, "ready_commit")
		return ready
	var locally_verified: Dictionary = validator.verify_ready(ready.descriptor_path, {"highest_release_seq":-1})
	if not locally_verified.ok:
		_emit_failed(locally_verified.code, false, "ready_verify")
		return locally_verified
	candidate_ready.emit(ready.descriptor_path)
	return ready

func read_known_requirement() -> Dictionary:
	if validator == null:
		return _fail("MANIFEST_MALFORMED")
	var directory := DirAccess.open(ValidatorScript.CACHE)
	if directory == null:
		return _fail("NETWORK_OFFLINE")
	var best := {}
	directory.list_dir_begin()
	while true:
		var name := directory.get_next()
		if name.is_empty():
			break
		if not name.begins_with("manifest_") or not name.ends_with(".json"):
			continue
		var hash := name.trim_prefix("manifest_").trim_suffix(".json")
		if not validator._hash(hash):
			continue
		var raw_m: PackedByteArray = validator._read_bytes(ValidatorScript.CACHE + "/" + name, ValidatorScript.MAX_MANIFEST)
		if validator._bytes_hash(raw_m).hex_encode() != hash:
			continue
		var raw_s: PackedByteArray = validator._read_bytes(ValidatorScript.CACHE + "/signature_" + hash + ".json", ValidatorScript.MAX_SIGNATURE)
		var known_acceptance := acceptance.duplicate()
		known_acceptance.erase("local_recovery_manifest_sha256")
		known_acceptance.erase("rejected_manifest_sha256")
		var check: Dictionary = validator.verify_manifest(raw_m, raw_s, known_acceptance)
		if (check.ok or check.code == "SHELL_UPGRADE_REQUIRED") and (best.is_empty() or check.manifest.release_seq > best.release_seq):
			best = {"ok":true,"code":"OK","manifest_sha256":hash,"release_seq":check.manifest.release_seq,"required":check.manifest.required,"notes":check.manifest.notes,"content_version":check.manifest.content_version,"failed_candidate":hash == acceptance.get("rejected_manifest_sha256", ""),"shell_upgrade_required":check.code == "SHELL_UPGRADE_REQUIRED","base_installer_url":check.get("base_installer_url", "")}
	directory.list_dir_end()
	return best if not best.is_empty() else _fail("NETWORK_OFFLINE")

func _fetch_bytes(url: String, limit: int) -> Dictionary:
	var req := HTTPRequest.new()
	add_child(req)
	req.max_redirects = 0
	req.accept_gzip = false
	req.body_size_limit = limit
	req.timeout = 15.0
	var err := req.request(url)
	if err != OK:
		req.queue_free()
		return _fail("NETWORK_OFFLINE")
	var completed: Array = await req.request_completed
	req.queue_free()
	if completed[0] != HTTPRequest.RESULT_SUCCESS:
		return _fail("NETWORK_OFFLINE" if completed[0] in [HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE, HTTPRequest.RESULT_TIMEOUT] else "HTTP_FAILURE")
	if completed[1] != 200 or completed[3].size() > limit:
		return _fail("HTTP_FAILURE")
	return {"ok":true,"code":"OK","bytes":completed[3]}

func _download_package(package: Dictionary) -> Dictionary:
	if not validator.trusted_url(package.url):
		return _fail("HTTP_UNTRUSTED_ORIGIN")
	var part: String = cache.part_path(package.sha256)
	var absolute := ProjectSettings.globalize_path(part)
	if FileAccess.file_exists(part):
		DirAccess.remove_absolute(absolute)
	var req := HTTPRequest.new()
	add_child(req)
	req.max_redirects = 0
	req.accept_gzip = false
	req.body_size_limit = package.size_bytes
	req.download_file = part
	req.timeout = 60.0
	req.request_completed.connect(_request_finished.bind(req))
	var err := req.request(package.url, PackedStringArray(["Accept-Encoding: identity"]))
	if err != OK:
		req.queue_free()
		return _fail("NETWORK_OFFLINE")
	var finished := false
	var completed: Array = []
	while not finished:
		await get_tree().process_frame
		if req.get_downloaded_bytes() > package.size_bytes:
			req.cancel_request()
			break
		download_progress.emit(package.id, req.get_downloaded_bytes(), package.size_bytes)
		if req.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED and not req.is_queued_for_deletion():
			# Completion may arrive at the same frame; test signal below.
			pass
		if req.has_meta("completion"):
			completed = req.get_meta("completion")
			finished = true
	# _request_finished stores completion before this loop observes it.
	req.queue_free()
	if not finished or completed[0] != HTTPRequest.RESULT_SUCCESS or completed[1] != 200:
		return _fail("HTTP_FAILURE")
	return cache.finalize_package(package)

func _request_finished(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest) -> void:
	req.set_meta("completion", [result, response_code, headers, body])

func _fail(code: String) -> Dictionary:
	return {"ok":false,"code":code}

func _emit_rejected(code: String, stage: String) -> void:
	_record_error(code, stage)
	manifest_rejected.emit(code)

func _emit_failed(code: String, retryable: bool, stage: String) -> void:
	_record_error(code, stage)
	download_failed.emit(code, retryable)

func _record_error(code: String, stage: String) -> void:
	last_error = {"code":code,"stage":stage,"message":code.replace("_", " ").capitalize(),"diagnostic_id":"u04-%d" % Time.get_ticks_usec()}
