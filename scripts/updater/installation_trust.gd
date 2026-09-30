extends RefCounted
## Build injects public keys into this protected shell source before export.
## Never read a key from installation.json, sidecars, the cache or the network.
const WINDOWS_PUBLIC_KEYS := {}
const MAX_INSTALLATION := 65536

static func production_supported() -> bool:
	return OS.has_feature("client_update_production_windows") and OS.get_name() == "Windows" and OS.has_feature("template") and not OS.has_feature("editor") and not OS.has_feature("client_update_fixture") and not WINDOWS_PUBLIC_KEYS.is_empty()

func read_verified() -> Dictionary:
	if not production_supported(): return _fail("SIGNATURE_SCHEME_UNAVAILABLE")
	# Godot consumes --main-pack before exposing OS.get_cmdline_args(). Read
	# this process's real Windows command line; failure must never fall back to
	# hashing an unrelated sibling pack. No user input is interpolated here.
	if not _windows_pack_selection_valid():
		return _fail("INSTALLATION_PACK_PATH_INVALID")
	# Godot 4.5.1 selects explicit main-pack, embedded executable, then the
	# executable's sibling <stem>.pck. Reject overrides and embedded packs so
	# the path hashed below is exactly that first eligible pack, independent of CWD.
	for argument in OS.get_cmdline_args():
		if argument in ["--main-pack", "--remote-fs"] or argument.begins_with("--main-pack=") or argument.begins_with("--remote-fs="):
			return _fail("INSTALLATION_PACK_PATH_INVALID")
	var executable := OS.get_executable_path().replace("\\", "/").simplify_path()
	var directory := executable.get_base_dir()
	if FileAccess.file_exists(directory.path_join("override.cfg")) or FileAccess.file_exists("res://override.cfg") or not str(ProjectSettings.get_setting("application/config/project_settings_override", "")).is_empty():
		return _fail("INSTALLATION_PACK_PATH_INVALID")
	var verifier = load("res://scripts/updater/manifest_validator.gd").new()
	var raw: PackedByteArray = verifier._read_bytes(directory.path_join("installation.json"), MAX_INSTALLATION)
	var signature: PackedByteArray = verifier._read_bytes(directory.path_join("installation.sig.json"), verifier.MAX_SIGNATURE)
	if raw.is_empty() or signature.is_empty(): return _fail("INSTALLATION_METADATA_MISSING")
	var signed: Dictionary = verifier.verify_signature(raw, signature)
	if not signed.ok: return signed
	var value: Dictionary = verifier._strict_object(raw)
	if value.get("schema_version") != 1 or value.get("updates_enabled") != true or value.get("platform") != "windows" or value.get("arch") != "x86_64" or not OS.has_feature("x86_64"):
		return _fail("INSTALLATION_METADATA_INVALID")
	if value.has("test_signature_mode") or value.has("test_public_keys") or value.has("test_http_loopback"):
		return _fail("INSTALLATION_METADATA_INVALID")
	for field in ["base_id", "export_profile_id", "protocol_family", "catalog_family"]:
		if not value.get(field) is String or value[field].is_empty(): return _fail("INSTALLATION_METADATA_INVALID")
	for field in ["base_release_seq", "protocol_revision", "catalog_revision", "server_catalog_min_revision", "server_catalog_max_revision", "max_package_bytes"]:
		if not verifier._integer(value.get(field)): return _fail("INSTALLATION_METADATA_INVALID")
	if value.max_package_bytes < 1 or value.server_catalog_min_revision > value.server_catalog_max_revision or not verifier._version(value.get("shell_version")) or not verifier._hash(value.get("base_manifest_sha256")) or value.get("channel") not in ["test", "production"]:
		return _fail("INSTALLATION_METADATA_INVALID")
	if not value.get("trusted_origins") is Array: return _fail("INSTALLATION_METADATA_INVALID")
	for origin in value.trusted_origins:
		if not origin is String or RegEx.create_from_string("^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?$").search(origin) == null:
			return _fail("INSTALLATION_METADATA_INVALID")
	verifier.configure(value)
	for field in ["manifest_url", "signature_url"]:
		if value.has(field) and not verifier.trusted_url(value[field]): return _fail("INSTALLATION_METADATA_INVALID")
	if value.get("executable_name") != executable.get_file() or value.get("base_pack_name") != executable.get_file().get_basename() + ".pck":
		return _fail("INSTALLATION_PACK_PATH_INVALID")
	if not verifier._hash(value.get("base_sha256")) or not verifier._hash(value.get("executable_sha256")):
		return _fail("INSTALLATION_METADATA_INVALID")
	var version := Engine.get_version_info()
	if value.get("engine_version") != "%s.%s.%s" % [version.major, version.minor, version.patch]:
		return _fail("ENGINE_MISMATCH")
	if not _external_pack_executable(executable): return _fail("INSTALLATION_PACK_PATH_INVALID")
	if _file_hash(executable) != value.executable_sha256: return _fail("INSTALLATION_EXECUTABLE_HASH_MISMATCH")
	var pack_path := directory.path_join(str(value.base_pack_name))
	var pack := FileAccess.open(pack_path, FileAccess.READ)
	if pack == null or pack.get_32() != 0x43504447: return _fail("INSTALLATION_PACK_PATH_INVALID")
	pack.close()
	if _file_hash(pack_path) != value.base_sha256: return _fail("INSTALLATION_BASE_HASH_MISMATCH")
	return {"ok":true, "code":"OK", "installation":value}

func _windows_pack_selection_valid() -> bool:
	var system_root := OS.get_environment("SystemRoot").replace("\\", "/")
	if not system_root.is_absolute_path(): return false
	var powershell := system_root.path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	if not FileAccess.file_exists(powershell): return false
	var folder := ProjectSettings.globalize_path("user://client_update/trust_probes")
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return false
	var verdict_path := folder.path_join("launch_%d_%d.txt" % [OS.get_process_id(), Time.get_ticks_usec()])
	# Persist only an OK verdict, never the potentially sensitive command line.
	# WMI's built-in type avoids module discovery and polluted PSModulePath.
	var query := "try { $line=([wmi]'Win32_Process.Handle=\"%d\"').CommandLine; if ([string]::IsNullOrEmpty($line)) { exit 2 }; $line=$line.Replace([string][char]34,''); if ($line.Contains('--main-pack') -or $line.Contains('--remote-fs')) { exit 2 }; [System.IO.File]::WriteAllText('%s','OK') } catch { exit 3 }" % [OS.get_process_id(), verdict_path.replace("'", "''")]
	var child := OS.create_process(powershell, ["-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", query], false)
	if child < 0: return false
	var deadline := Time.get_ticks_msec() + 8000
	while OS.is_process_running(child) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(10)
	var completed := not OS.is_process_running(child)
	if not completed: OS.kill(child)
	var valid := completed and FileAccess.get_file_as_string(verdict_path) == "OK" if FileAccess.file_exists(verdict_path) else false
	if FileAccess.file_exists(verdict_path): DirAccess.remove_absolute(verdict_path)
	return valid

func _external_pack_executable(path: String) -> bool:
	# Godot's Windows embedded pack source searches the PE `pck` section,
	# and the generic PCK reader also accepts a trailing GDPC footer.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() < 128 or file.get_16() != 0x5a4d: return false
	file.seek(0x3c)
	var pe_offset := file.get_32()
	if pe_offset + 24 > file.get_length(): return false
	file.seek(pe_offset)
	if file.get_32() != 0x00004550: return false
	file.get_16()
	var section_count := file.get_16()
	file.seek(pe_offset + 20)
	var optional_size := file.get_16()
	var section_start := pe_offset + 24 + optional_size
	if section_count > 96 or section_start + section_count * 40 > file.get_length(): return false
	for index in section_count:
		file.seek(section_start + index * 40)
		var section_name := file.get_buffer(8).get_string_from_ascii()
		if section_name == "pck":
			# Official external-pack templates still contain a dummy pck section.
			# Match the engine's eight-byte alignment search, not its name alone.
			file.seek(section_start + index * 40 + 20)
			var pack_offset := file.get_32()
			if pack_offset > 0:
				for alignment in 8:
					if pack_offset + alignment + 4 > file.get_length(): return false
					file.seek(pack_offset + alignment)
					if file.get_32() == 0x43504447: return false
	file.seek(file.get_length() - 4)
	return file.get_32() != 0x43504447

func _file_hash(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK: return ""
	var remaining := file.get_length()
	while remaining > 0:
		var chunk := file.get_buffer(mini(1048576, remaining))
		if chunk.is_empty() or context.update(chunk) != OK: return ""
		remaining -= chunk.size()
	file.close()
	return context.finish().hex_encode()

func _fail(code: String) -> Dictionary:
	return {"ok":false, "code":code}
