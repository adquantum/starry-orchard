extends RefCounted
## Local only. Never calls Accounts.path_for or adds a cloud save file.
static func path_for(accounts: Node, avatar_school: String) -> String:
	var identity := "local:" + avatar_school
	if accounts != null and not str(accounts.cache_root).is_empty():identity = str(accounts.cache_root)
	return "user://tower_runs/" + identity.sha256_text().left(24) + "/run_v02.json"

static func write(path: String, data: Dictionary) -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:return false
	file.store_string(JSON.stringify(data));file.flush()
	var error := file.get_error();file.close()
	if error != OK:return false
	return DirAccess.rename_absolute(path + ".tmp", path) == OK
