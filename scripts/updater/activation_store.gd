extends RefCounted
## Owns activation state only. Package trust belongs to manifest_validator.gd.
const PATH := "user://client_update/activation/state.json"
const LIMIT := 262144
const MAX_INTEGER := 9007199254740991

func identity_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 3: return false
	if not value.has_all(["manifest_sha256", "release_seq", "package_sha256_ordered"]): return false
	if not hash_valid(value.manifest_sha256) or not integer_valid(value.release_seq): return false
	if not value.package_sha256_ordered is Array or value.package_sha256_ordered.size() > 512: return false
	for hash_value in value.package_sha256_ordered:
		if not hash_valid(hash_value): return false
	return true

func same_identity(left: Variant, right: Variant) -> bool:
	if not identity_valid(left) or not identity_valid(right): return false
	if left.manifest_sha256 != right.manifest_sha256 or int(left.release_seq) != int(right.release_seq): return false
	if left.package_sha256_ordered.size() != right.package_sha256_ordered.size(): return false
	for index in left.package_sha256_ordered.size():
		if left.package_sha256_ordered[index] != right.package_sha256_ordered[index]: return false
	return true

func hash_valid(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for c in value:
		if not c in "0123456789abcdef": return false
	return true

func integer_valid(value: Variant, maximum: int = MAX_INTEGER) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= 0 and value <= maximum

func initial_state(base: Dictionary, binding: Dictionary) -> Dictionary:
	return {"schema_version":1, "highest_release_seq":base.release_seq, "highest_manifest_sha256":base.manifest_sha256, "rejected_manifest_sha256":null, "installation_identity":binding.duplicate(true), "pending":null, "active":base.duplicate(true), "previous":null, "confirmed":base.duplicate(true), "attempt":null, "recovery_tries":0, "candidate_graceful_exits":0}

func validate(state: Variant) -> bool:
	if not state is Dictionary or state.size() != 12: return false
	if not state.has_all(["schema_version","highest_release_seq","highest_manifest_sha256","rejected_manifest_sha256","installation_identity","pending","active","previous","confirmed","attempt","recovery_tries","candidate_graceful_exits"]): return false
	if state.schema_version != 1 or not integer_valid(state.highest_release_seq): return false
	if not hash_valid(state.highest_manifest_sha256): return false
	if state.rejected_manifest_sha256 != null and not hash_valid(state.rejected_manifest_sha256): return false
	if not binding_valid(state.installation_identity): return false
	if not integer_valid(state.recovery_tries,1) or not integer_valid(state.candidate_graceful_exits,2): return false
	for slot in ["pending","active","previous","confirmed"]:
		if state[slot] != null and (not identity_valid(state[slot]) or state[slot].release_seq > state.highest_release_seq): return false
	if state.confirmed == null or state.active == null: return false
	if state.attempt != null:
		var attempt: Variant = state.attempt
		if not attempt is Dictionary or attempt.size() != 4 or not attempt.has_all(["status","manifest_sha256","started_at_utc","reason"]): return false
		if not attempt.status in ["mounting","boot_check","failed","graceful_exit"]: return false
		if attempt.manifest_sha256 != state.active.manifest_sha256 or not attempt.started_at_utc is String: return false
		if attempt.status == "failed":
			if not attempt.reason is String or attempt.reason.is_empty(): return false
		elif attempt.reason != null: return false
	return true

func binding_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 7: return false
	for key in ["channel","base_id","base_sha256","platform","arch","export_profile_id","engine_version"]:
		if not value.get(key) is String or value[key].is_empty(): return false
	return hash_valid(value.base_sha256)

func read_state(base: Dictionary, binding: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(PATH): return {"ok":true,"state":initial_state(base,binding),"fresh":true}
	var file = FileAccess.open(PATH,FileAccess.READ)
	if file == null or file.get_length() > LIMIT: return {"ok":false,"code":"CACHE_IO_FAILURE"}
	var raw: PackedByteArray = file.get_buffer(file.get_length()); file.close()
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not validate(parsed): return {"ok":false,"code":"ACTIVATION_STATE_INVALID"}
	if parsed.installation_identity != binding:
		var archive_path: String = PATH.get_base_dir()+"/archive_"+FileAccess.get_sha256(PATH)+".json"
		if FileAccess.file_exists(archive_path):
			if FileAccess.get_file_as_bytes(archive_path) != raw: return {"ok":false,"code":"CACHE_IO_FAILURE"}
		else:
			if not _durable_write(archive_path+".tmp",raw): return {"ok":false,"code":"CACHE_IO_FAILURE"}
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(archive_path+".tmp"),ProjectSettings.globalize_path(archive_path)) != OK: return {"ok":false,"code":"CACHE_IO_FAILURE"}
		var migrated: Dictionary = initial_state(base,binding)
		var same_scope: bool = true
		for key in ["channel","platform","export_profile_id"]:
			if parsed.installation_identity[key] != binding[key]: same_scope = false
		if same_scope:
			if parsed.highest_release_seq >= migrated.highest_release_seq:
				migrated.highest_release_seq = parsed.highest_release_seq
				migrated.highest_manifest_sha256 = parsed.highest_manifest_sha256
			migrated.rejected_manifest_sha256 = parsed.rejected_manifest_sha256
		return {"ok":true,"state":migrated,"fresh":true,"migrated":true,"archive_path":archive_path,"same_scope":same_scope}
	return {"ok":true,"state":parsed,"fresh":false}

func write_state(state: Dictionary) -> Dictionary:
	if not validate(state): return {"ok":false,"code":"ACTIVATION_STATE_INVALID"}
	var bytes: PackedByteArray = JSON.stringify(state).to_utf8_buffer()
	if bytes.size() > LIMIT: return {"ok":false,"code":"CACHE_IO_FAILURE"}
	var folder: String = ProjectSettings.globalize_path(PATH.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return {"ok":false,"code":"CACHE_IO_FAILURE"}
	if not _durable_write(PATH+".tmp",bytes): return {"ok":false,"code":"CACHE_IO_FAILURE"}
	# Retain the previous exact bytes for diagnosis. Never auto-restore them and
	# accidentally lower the accepted release sequence after corrupt state.
	if FileAccess.file_exists(PATH):
		var old: PackedByteArray = FileAccess.get_file_as_bytes(PATH)
		if not _durable_write(PATH+".previous.tmp",old): return {"ok":false,"code":"CACHE_IO_FAILURE"}
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH+".previous.tmp"),ProjectSettings.globalize_path(PATH+".previous")) != OK: return {"ok":false,"code":"CACHE_IO_FAILURE"}
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH+".tmp"),ProjectSettings.globalize_path(PATH)) != OK: return {"ok":false,"code":"CACHE_IO_FAILURE"}
	if FileAccess.get_file_as_bytes(PATH) != bytes: return {"ok":false,"code":"CACHE_IO_FAILURE"}
	return {"ok":true}

func _durable_write(path: String, bytes: PackedByteArray) -> bool:
	var file = FileAccess.open(path,FileAccess.WRITE)
	if file == null: return false
	file.store_buffer(bytes); file.flush()
	var error: int = file.get_error(); file.close()
	return error == OK and FileAccess.get_file_as_bytes(path) == bytes

func start_plan(original: Dictionary) -> Dictionary:
	if not validate(original): return {"ok":false,"code":"ACTIVATION_STATE_INVALID"}
	var state: Dictionary = original.duplicate(true)
	var mode := "confirmed"
	var hold := false
	if state.attempt != null and state.attempt.status in ["mounting","boot_check","failed"]:
		if int(state.recovery_tries) >= 1 or state.previous == null: return {"ok":false,"code":"RECOVERY_FAILED"}
		mode = "recovery"; state.recovery_tries = 1
		state.rejected_manifest_sha256 = state.active.manifest_sha256
		state.active = state.previous; state.pending = null
	elif state.pending != null and int(state.candidate_graceful_exits) >= 2:
		if state.previous == null: return {"ok":false,"code":"RECOVERY_FAILED"}
		mode = "recovery"; hold = true; state.recovery_tries = 1
		state.active = state.previous; state.pending = null
	elif state.pending != null:
		mode = "candidate"
		if state.attempt == null: state.previous = state.confirmed
		state.active = state.pending
	else:
		state.active = state.confirmed
		hold = int(state.candidate_graceful_exits) >= 2
	state.attempt = null
	return {"ok":true,"state":state,"mode":mode,"hold":hold,"identity":state.active}

func attempt(state: Dictionary, status: String, reason: Variant = null) -> void:
	state.attempt = {"status":status,"manifest_sha256":state.active.manifest_sha256,"started_at_utc":Time.get_datetime_string_from_system(true)+"Z","reason":reason}

func graceful_exit(state: Dictionary) -> bool:
	if state.attempt == null or state.attempt.status != "boot_check": return false
	if state.pending == null:
		state.attempt = null
	else:
		state.candidate_graceful_exits = mini(2,int(state.candidate_graceful_exits)+1)
		attempt(state,"graceful_exit")
	return true
