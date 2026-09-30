extends RefCounted

const CACHE := "user://client_update/cache"
const SCHEME := "rsa-pkcs1-v1_5-sha256"
const MAX_MANIFEST := 262144
const MAX_SIGNATURE := 16384
const MAX_SAFE_INT := 9007199254740991

var installation: Dictionary = {}
var _source := ""
var _cursor := 0
var _parse_error := false
var _nodes := 0

func configure(value: Dictionary) -> void:
	installation = value.duplicate(true)

func verify_manifest(raw_manifest: PackedByteArray, raw_signature: PackedByteArray, acceptance: Dictionary = {}) -> Dictionary:
	var signature_result := verify_signature(raw_manifest, raw_signature)
	if not signature_result.ok:
		return signature_result
	var manifest = _strict_object(raw_manifest)
	if manifest.is_empty():
		return _fail("MANIFEST_MALFORMED")
	var bound_acceptance := acceptance.duplicate()
	bound_acceptance["_actual_manifest_sha256"] = _bytes_hash(raw_manifest).hex_encode()
	var checked := _check_manifest(manifest, bound_acceptance)
	if checked.code == "SHELL_UPGRADE_REQUIRED":
		checked["manifest"] = manifest
		checked["manifest_sha256"] = _bytes_hash(raw_manifest).hex_encode()
		return checked
	if not checked.ok:
		return checked
	checked["manifest"] = manifest
	checked["manifest_sha256"] = _bytes_hash(raw_manifest).hex_encode()
	return checked

func verify_signature(raw_manifest: PackedByteArray, raw_signature: PackedByteArray) -> Dictionary:
	if raw_manifest.is_empty() or raw_manifest.size() > MAX_MANIFEST or raw_signature.is_empty() or raw_signature.size() > MAX_SIGNATURE:
		return _fail("MANIFEST_MALFORMED")
	var sig = _strict_object(raw_signature)
	if sig.is_empty() or not _exact_keys(sig, ["algorithm", "key_id", "signature_b64"]):
		return _fail("MANIFEST_MALFORMED")
	if sig.get("algorithm") != SCHEME:
		return _fail("SIGNATURE_SCHEME_UNAVAILABLE")
	var keys: Dictionary = {}
	if OS.has_feature("client_update_production_windows"):
		# Only the protected program shell supplies production keys. Installation
		# JSON and manifest signature descriptors cannot introduce trust anchors.
		var trust = load("res://scripts/updater/installation_trust.gd")
		if trust == null or not trust.production_supported():
			return _fail("SIGNATURE_SCHEME_UNAVAILABLE")
		keys = trust.WINDOWS_PUBLIC_KEYS
	elif installation.get("test_signature_mode", false) and OS.has_feature("client_update_fixture"):
		keys = installation.get("test_public_keys", {})
	else:
		# Source projects and Android remain closed. Platform admission is separate.
		return _fail("SIGNATURE_SCHEME_UNAVAILABLE")
	if not keys.has(sig.get("key_id")):
		return _fail("KEY_UNKNOWN")
	if not sig.get("key_id") is String or not sig.get("signature_b64") is String:
		return _fail("MANIFEST_MALFORMED")
	var b64: String = sig["signature_b64"]
	if b64.is_empty() or Marshalls.raw_to_base64(Marshalls.base64_to_raw(b64)) != b64:
		return _fail("SIGNATURE_INVALID")
	var key := CryptoKey.new()
	if key.load_from_string(str(keys[sig["key_id"]]), true) != OK:
		return _fail("KEY_UNKNOWN")
	if not Crypto.new().verify(HashingContext.HASH_SHA256, _bytes_hash(raw_manifest), Marshalls.base64_to_raw(b64), key):
		return _fail("SIGNATURE_INVALID")
	return {"ok":true, "code":"OK"}

func verify_ready(descriptor_path: String, acceptance: Dictionary = {}) -> Dictionary:
	var prefix := ProjectSettings.globalize_path(CACHE).replace("\\", "/") + "/"
	var absolute := ProjectSettings.globalize_path(descriptor_path).replace("\\", "/")
	if not absolute.begins_with(prefix) or absolute.get_base_dir() + "/" != prefix:
		return _fail("PACKAGE_PATH_FORBIDDEN")
	var name := absolute.get_file()
	if not name.begins_with("ready_") or not name.ends_with(".json"):
		return _fail("PACKAGE_PATH_FORBIDDEN")
	var descriptor = _read_json_file(absolute, MAX_MANIFEST)
	if descriptor.is_empty() or not _exact_keys(descriptor, ["schema_version", "manifest_sha256", "manifest_path", "signature_path", "channel", "release_seq", "base_id", "platform", "arch", "export_profile_id", "packages", "created_at_utc"]):
		return _fail("MANIFEST_MALFORMED")
	var hash: Variant = descriptor.get("manifest_sha256", "")
	if not _hash(hash) or not descriptor.get("manifest_path") is String or not descriptor.get("signature_path") is String or name != "ready_%s.json" % hash or descriptor.get("manifest_path") != "manifest_%s.json" % hash or descriptor.get("signature_path") != "signature_%s.json" % hash:
		return _fail("PACKAGE_PATH_FORBIDDEN")
	var raw_manifest := _read_bytes(prefix + descriptor["manifest_path"], MAX_MANIFEST)
	var raw_signature := _read_bytes(prefix + descriptor["signature_path"], MAX_SIGNATURE)
	if _bytes_hash(raw_manifest).hex_encode() != hash:
		return _fail("MANIFEST_MALFORMED")
	var result := verify_manifest(raw_manifest, raw_signature, acceptance)
	if not result.ok:
		return result
	var manifest: Dictionary = result.manifest
	for field in ["channel", "release_seq", "base_id", "platform", "arch", "export_profile_id"]:
		if descriptor.get(field) != manifest.get(field):
			return _fail("MANIFEST_MALFORMED")
	if descriptor.get("schema_version") != 1 or not descriptor.get("packages") is Array or descriptor.packages.size() != manifest.packages.size():
		return _fail("PACKAGE_CHAIN_INVALID")
	if not descriptor.get("created_at_utc") is String or RegEx.create_from_string("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$").search(descriptor.created_at_utc) == null:
		return _fail("MANIFEST_MALFORMED")
	var paths: Array = []
	for i in manifest.packages.size():
		var package: Dictionary = manifest.packages[i]
		var expected := {"id":package.id, "sha256":package.sha256, "size_bytes":package.size_bytes, "cache_name":"package_%s.pck" % package.sha256}
		if descriptor.packages[i] != expected:
			return _fail("PACKAGE_CHAIN_INVALID")
		var path: String = prefix + expected.cache_name
		var integrity := verify_package(path, package)
		if not integrity.ok:
			return integrity
		paths.append(path)
	result["packages"] = paths
	result["descriptor"] = descriptor
	result["identity"] = {"manifest_sha256":hash, "release_seq":manifest.release_seq, "package_sha256_ordered":manifest.packages.map(func(p): return p.sha256)}
	return result

func verify_package(path: String, package: Dictionary) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return _fail("CACHE_IO_FAILURE")
	if f.get_length() != package.size_bytes:
		return _fail("PACKAGE_SIZE_MISMATCH")
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while not f.eof_reached():
		var chunk := f.get_buffer(65536)
		if chunk.is_empty():
			break
		context.update(chunk)
	if context.finish().hex_encode() != package.sha256:
		return _fail("PACKAGE_HASH_MISMATCH")
	return {"ok":true, "code":"OK"}

func _check_manifest(m: Dictionary, a: Dictionary) -> Dictionary:
	if not _exact_keys(m, ["schema_version", "channel", "release_seq", "base_id", "base_sha256", "platform", "arch", "export_profile_id", "engine_version", "minimum_shell_version", "content_version", "protocol", "catalog", "required", "notes", "base_installer_url", "packages"]):
		return _fail("MANIFEST_MALFORMED")
	if m.schema_version != 1:
		return _fail("SCHEMA_UNSUPPORTED")
	if not _integer(m.release_seq):
		return _fail("MANIFEST_MALFORMED")
	for pair in [["channel", "CHANNEL_MISMATCH"], ["base_id", "BASE_MISMATCH"], ["base_sha256", "BASE_MISMATCH"], ["platform", "PLATFORM_MISMATCH"], ["arch", "PLATFORM_MISMATCH"], ["export_profile_id", "PROFILE_MISMATCH"], ["engine_version", "ENGINE_MISMATCH"]]:
		if m[pair[0]] != installation.get(pair[0]):
			return _fail(pair[1])
	var actual_hash := str(a.get("_actual_manifest_sha256", ""))
	if actual_hash == str(a.get("rejected_manifest_sha256", "")) and _hash(actual_hash):
		return _fail("CANDIDATE_PREVIOUSLY_FAILED")
	var local_hash := str(a.get("local_recovery_manifest_sha256", ""))
	var same_hash := str(a.get("allow_same_release_manifest_sha256", ""))
	var highest = a.get("highest_release_seq", -1)
	if typeof(highest) != TYPE_INT:
		return _fail("RELEASE_REPLAY")
	if not (_hash(local_hash) and local_hash == actual_hash) and not (m.release_seq == highest and _hash(same_hash) and same_hash == actual_hash) and m.release_seq <= highest:
		return _fail("RELEASE_REPLAY")
	if not _version(m.minimum_shell_version) or not _version(str(installation.get("shell_version", ""))):
		return _fail("MANIFEST_MALFORMED")
	var shell_upgrade := _compare_version(m.minimum_shell_version, installation.shell_version) > 0
	if shell_upgrade:
		if m.base_installer_url == null or not trusted_url(m.base_installer_url):
			return _fail("HTTP_UNTRUSTED_ORIGIN")
	if not m.protocol is Dictionary or not _exact_keys(m.protocol, ["family", "min_revision", "max_revision"]):
		return _fail("MANIFEST_MALFORMED")
	if m.protocol.family != installation.get("protocol_family") or not _integer(m.protocol.min_revision) or not _integer(m.protocol.max_revision) or m.protocol.min_revision > installation.get("protocol_revision", -1) or m.protocol.max_revision < installation.get("protocol_revision", -1):
		return _fail("PROTOCOL_INCOMPATIBLE")
	if not m.catalog is Dictionary or not _exact_keys(m.catalog, ["family", "revision", "min_supported_revision", "max_supported_revision"]):
		return _fail("MANIFEST_MALFORMED")
	if m.catalog.family != installation.get("catalog_family") or not _integer(m.catalog.revision) or not _integer(m.catalog.min_supported_revision) or not _integer(m.catalog.max_supported_revision) or m.catalog.revision < installation.get("server_catalog_min_revision", -1) or m.catalog.revision > installation.get("server_catalog_max_revision", -1) or installation.get("catalog_revision", -1) < m.catalog.min_supported_revision or installation.get("catalog_revision", -1) > m.catalog.max_supported_revision:
		return _fail("CATALOG_INCOMPATIBLE")
	if m.catalog.revision < a.get("owned_item_required_catalog_revision", 0):
		return _fail("ROLLBACK_INCOMPATIBLE")
	if not m.required is bool or not m.notes is String or not m.content_version is String or m.content_version.is_empty() or (m.base_installer_url != null and not trusted_url(m.base_installer_url)):
		return _fail("MANIFEST_MALFORMED")
	if not m.packages is Array:
		return _fail("PACKAGE_CHAIN_INVALID")
	var seen := {}
	for p in m.packages:
		if not p is Dictionary or not _exact_keys(p, ["id", "url", "size_bytes", "sha256", "depends_on"]):
			return _fail("PACKAGE_CHAIN_INVALID")
		if not p.id is String or RegEx.create_from_string("^[A-Za-z0-9._-]{1,80}$").search(p.id) == null or seen.has(p.id) or not p.sha256 is String or not _hash(p.sha256) or not _integer(p.size_bytes) or p.size_bytes < 1 or p.size_bytes > installation.get("max_package_bytes", 0) or not p.depends_on is Array:
			return _fail("PACKAGE_CHAIN_INVALID")
		if not trusted_url(p.url):
			return _fail("HTTP_UNTRUSTED_ORIGIN")
		var dependencies := {}
		for dep in p.depends_on:
			if not dep is String or not seen.has(dep) or dependencies.has(dep):
				return _fail("PACKAGE_CHAIN_INVALID")
			dependencies[dep] = true
		seen[p.id] = true
	if shell_upgrade:
		return {"ok":false,"code":"SHELL_UPGRADE_REQUIRED","base_installer_url":m.base_installer_url}
	return {"ok":true, "code":"OK"}

func trusted_url(url: Variant) -> bool:
	if not url is String or url.contains("\\") or url.contains("#") or url.contains("@") or url.contains(".."):
		return false
	var rx := RegEx.create_from_string("^(https?)://([A-Za-z0-9.-]+)(:[0-9]{1,5})?(/[^?#]*)?(\\?[^#]*)?$")
	var match := rx.search(url)
	if match == null:
		return false
	var origin := "%s://%s%s" % [match.get_string(1).to_lower(), match.get_string(2).to_lower(), match.get_string(3)]
	if installation.get("test_http_loopback", false) and OS.has_feature("client_update_fixture") and origin.begins_with("http://127.0.0.1:"):
		return true
	return origin.begins_with("https://") and origin in installation.get("trusted_origins", [])

func _strict_object(raw: PackedByteArray) -> Dictionary:
	if raw.is_empty() or raw[0] == 239 or raw.get_string_from_utf8().to_utf8_buffer() != raw:
		return {}
	_source = raw.get_string_from_utf8()
	_cursor = 0
	_parse_error = false
	_nodes = 0
	var value = _scan_value(0)
	_skip_ws()
	if _parse_error or _cursor != _source.length() or not value is Dictionary:
		return {}
	return value

func _scan_value(depth: int) -> Variant:
	_nodes += 1
	if depth > 32 or _nodes > 4096:
		_parse_error = true
		return null
	_skip_ws()
	if _cursor >= _source.length():
		_parse_error = true
		return null
	var c := _source[_cursor]
	if c == "{" or c == "[":
		var object := c == "{"
		_cursor += 1
		var result = {} if object else []
		_skip_ws()
		if _take("}" if object else "]"):
			return result
		while not _parse_error:
			if object:
				var key = _scan_string()
				_skip_ws()
				if key == null or result.has(key) or not _take(":"):
					_parse_error = true
					break
				result[key] = _scan_value(depth + 1)
			else:
				result.append(_scan_value(depth + 1))
			_skip_ws()
			if _take("}" if object else "]"):
				return result
			if not _take(","):
				_parse_error = true
				break
		return null
	if c == "\"":
		return _scan_string()
	for literal in ["true", "false", "null"]:
		if _source.substr(_cursor, literal.length()) == literal:
			_cursor += literal.length()
			return true if literal == "true" else (false if literal == "false" else null)
	var start := _cursor
	if c == "-":
		_cursor += 1
	while _cursor < _source.length() and _source[_cursor] >= "0" and _source[_cursor] <= "9":
		_cursor += 1
	var token := _source.substr(start, _cursor - start)
	if token.is_empty() or token == "-" or token == "-0" or (token.begins_with("0") and token.length() > 1) or (token.begins_with("-0") and token.length() > 2) or token.length() > 16:
		_parse_error = true
		return null
	var n := token.to_int()
	if abs(n) > MAX_SAFE_INT:
		_parse_error = true
		return null
	return n

func _scan_string() -> Variant:
	_skip_ws()
	if not _take("\""):
		_parse_error = true
		return null
	var start := _cursor - 1
	var escaped := false
	while _cursor < _source.length():
		var c := _source[_cursor]
		_cursor += 1
		if c == "\"" and not escaped:
			var token := _source.substr(start, _cursor - start)
			var parsed: Variant = JSON.parse_string(token)
			if not parsed is String:
				_parse_error = true
			return parsed
		if c.unicode_at(0) < 32:
			_parse_error = true
			return null
		if c == "\\" and not escaped:
			escaped = true
		else:
			escaped = false
	_parse_error = true
	return null

func _skip_ws() -> void:
	while _cursor < _source.length() and _source[_cursor] in [" ", "\t", "\r", "\n"]:
		_cursor += 1

func _take(c: String) -> bool:
	if _cursor < _source.length() and _source[_cursor] == c:
		_cursor += 1
		return true
	return false

func _read_bytes(path: String, limit: int) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > limit:
		return PackedByteArray()
	return f.get_buffer(f.get_length())

func _read_json_file(path: String, limit: int) -> Dictionary:
	return _strict_object(_read_bytes(path, limit))

func _exact_keys(value: Dictionary, keys: Array) -> bool:
	if value.size() != keys.size():
		return false
	for key in keys:
		if not value.has(key):
			return false
	return true

func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= MAX_SAFE_INT

func _hash(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-f]{64}$").search(value) != null

func _version(value: Variant) -> bool:
	if not value is String or RegEx.create_from_string("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$").search(value) == null:
		return false
	for part in value.split("."):
		if part.length() > 16 or (part.length() == 16 and part > str(MAX_SAFE_INT)):
			return false
	return true

func _compare_version(a: String, b: String) -> int:
	var av := a.split(".")
	var bv := b.split(".")
	for i in 3:
		if int(av[i]) != int(bv[i]):
			return 1 if int(av[i]) > int(bv[i]) else -1
	return 0

func _fail(code: String) -> Dictionary:
	return {"ok":false, "code":code}

func _bytes_hash(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()
