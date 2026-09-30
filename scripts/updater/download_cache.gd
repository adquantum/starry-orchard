extends RefCounted

const CACHE := "user://client_update/cache"
const CHUNK := 65536
var validator: RefCounted
var minimum_free_bytes := 8388608
var simulated_free_bytes := -1

func configure(manifest_validator: RefCounted, settings: Dictionary = {}) -> void:
	validator = manifest_validator
	minimum_free_bytes = int(settings.get("minimum_free_bytes", minimum_free_bytes))
	if OS.has_feature("client_update_fixture"):
		simulated_free_bytes = int(settings.get("simulated_free_bytes", -1))

func ensure_cache() -> Dictionary:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE)) != OK:
		return _fail("CACHE_IO_FAILURE")
	return {"ok":true, "code":"OK"}

func package_path(hash: String) -> String:
	return CACHE + "/package_%s.pck" % hash

func part_path(hash: String) -> String:
	return package_path(hash) + ".part"

func cached(package: Dictionary) -> bool:
	var path := package_path(package.sha256)
	if not FileAccess.file_exists(path):
		return false
	return validator.verify_package(path, package).ok

func enough_space(required: int) -> bool:
	if required < 0:
		return false
	if simulated_free_bytes >= 0:
		return simulated_free_bytes >= required + minimum_free_bytes
	var directory := DirAccess.open(CACHE)
	return directory != null and directory.get_space_left() >= required + minimum_free_bytes

func finalize_package(package: Dictionary) -> Dictionary:
	var part := part_path(package.sha256)
	var valid: Dictionary = validator.verify_package(part, package)
	if not valid.ok:
		return valid
	var target := package_path(package.sha256)
	if FileAccess.file_exists(target):
		if validator.verify_package(target, package).ok:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(part))
			return {"ok":true, "code":"OK"}
		var bad := target + ".invalid"
		if FileAccess.file_exists(bad):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(target), ProjectSettings.globalize_path(bad)) != OK:
			return _fail("CACHE_IO_FAILURE")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(part), ProjectSettings.globalize_path(target)) != OK:
		return _fail("CACHE_IO_FAILURE")
	return validator.verify_package(target, package)

func write_ready(raw_manifest: PackedByteArray, raw_signature: PackedByteArray, manifest: Dictionary) -> Dictionary:
	var hash: String = validator._bytes_hash(raw_manifest).hex_encode()
	var packages := []
	for p in manifest.packages:
		if not cached(p):
			return _fail("PACKAGE_HASH_MISMATCH")
		packages.append({"id":p.id,"sha256":p.sha256,"size_bytes":p.size_bytes,"cache_name":"package_%s.pck" % p.sha256})
	var descriptor := {"schema_version":1,"manifest_sha256":hash,"manifest_path":"manifest_%s.json" % hash,"signature_path":"signature_%s.json" % hash,"channel":manifest.channel,"release_seq":manifest.release_seq,"base_id":manifest.base_id,"platform":manifest.platform,"arch":manifest.arch,"export_profile_id":manifest.export_profile_id,"packages":packages,"created_at_utc":Time.get_datetime_string_from_system(true) + "Z"}
	var existing_path := CACHE + "/ready_%s.json" % hash
	if FileAccess.file_exists(existing_path):
		var existing = validator._read_json_file(existing_path, validator.MAX_MANIFEST)
		if existing is Dictionary and not existing.is_empty():
			var old: Dictionary = existing.duplicate()
			old.erase("created_at_utc")
			var expected := descriptor.duplicate()
			expected.erase("created_at_utc")
			if old == expected and existing.get("created_at_utc") is String and RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$").search(existing.created_at_utc) != null and FileAccess.file_exists(CACHE + "/" + descriptor.manifest_path) and FileAccess.file_exists(CACHE + "/" + descriptor.signature_path) and FileAccess.get_file_as_bytes(CACHE + "/" + descriptor.manifest_path) == raw_manifest and FileAccess.get_file_as_bytes(CACHE + "/" + descriptor.signature_path) == raw_signature:
				return {"ok":true,"code":"OK","descriptor_path":existing_path}
	var saved := write_verified_manifest(raw_manifest, raw_signature)
	if not saved.ok:
		return saved
	for item in [["ready_%s.json" % hash,JSON.stringify(descriptor).to_utf8_buffer()]]:
		var result := _write_immutable(CACHE + "/" + item[0], item[1])
		if not result.ok:
			return result
	return {"ok":true,"code":"OK","descriptor_path":CACHE + "/ready_%s.json" % hash}

func write_verified_manifest(raw_manifest: PackedByteArray, raw_signature: PackedByteArray) -> Dictionary:
	var hash: String = validator._bytes_hash(raw_manifest).hex_encode()
	for item in [["manifest_%s.json" % hash,raw_manifest],["signature_%s.json" % hash,raw_signature]]:
		var result := _write_immutable(CACHE + "/" + item[0], item[1])
		if not result.ok:
			return result
	return {"ok":true,"code":"OK"}

func _write_immutable(path: String, bytes: PackedByteArray) -> Dictionary:
	if FileAccess.file_exists(path):
		if FileAccess.get_file_as_bytes(path) == bytes:
			return {"ok":true,"code":"OK"}
		var bad := path + ".invalid"
		if FileAccess.file_exists(bad):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bad))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bad)) != OK:
			return _fail("CACHE_IO_FAILURE")
	var part := path + ".part"
	var f := FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		return _fail("CACHE_IO_FAILURE")
	f.store_buffer(bytes)
	f.flush()
	f.close()
	if FileAccess.get_file_as_bytes(part) != bytes:
		return _fail("CACHE_IO_FAILURE")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(part),ProjectSettings.globalize_path(path)) != OK:
		return _fail("CACHE_IO_FAILURE")
	return {"ok":true,"code":"OK"}

func _fail(code: String) -> Dictionary:
	return {"ok":false,"code":code}
