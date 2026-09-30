extends RefCounted
## Native snapshots preserve GLTFDocument's scene exactly while avoiding repeated
## GLB decoding. Regenerate with tools/worlds/pack_orchard_scene_cache.gd.
const MANIFEST := "res://assets/worlds/star_orchard/runtime_cache/manifest.json"
static var _manifest: Dictionary = {}
static var _validated: Dictionary = {}

static func instantiate(source_path: String) -> Node3D:
	if not "--orchard-raw-gltf" in OS.get_cmdline_user_args():
		if _manifest.is_empty() and FileAccess.file_exists(MANIFEST):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
			if parsed is Dictionary: _manifest = parsed
		var entry: Dictionary = _manifest.get(source_path, {})
		if not entry.is_empty() and ResourceLoader.exists(str(entry.get("scene", ""))):
			if not _validated.has(source_path):
				# Exported GLBs are replaced by imported resources. Their raw bytes
				# cannot be hashed at runtime; the release build checks the cache's
				# source hash, and the signed PCK protects the shipped snapshot.
				if FileAccess.file_exists(source_path):
					_validated[source_path] = FileAccess.get_sha256(source_path) == str(entry.get("sha256", ""))
				else:
					_validated[source_path] = OS.has_feature("template") and ResourceLoader.exists(source_path)
			if bool(_validated[source_path]):
				var packed := load(str(entry.scene)) as PackedScene
				if packed != null: return packed.instantiate() as Node3D
	# Godot exports GLBs as imported PackedScenes, without the raw container.
	if not FileAccess.file_exists(source_path) and ResourceLoader.exists(source_path):
		var imported := load(source_path) as PackedScene
		if imported != null: return imported.instantiate() as Node3D
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(source_path, state)
	if error != OK:
		push_error("Orchard scene could not be read: %s (%s)" % [source_path, error])
		return null
	return document.generate_scene(state) as Node3D
