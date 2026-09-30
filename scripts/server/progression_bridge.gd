extends Node
## Server-only account transport. Secrets come only from the dedicated process environment.
signal committed(result: Dictionary)
var server_url:=""
var service_key:=""
var server_id:=""
var boot_id:=""
var journal_dir:=""
var available:=false
var busy:=false
var stopped:=false
var jobs: Array[Dictionary]=[]
var serial:=0
var retry_at:=0
var owns_process_lock:=false
var host_identity:=""
var last_journal_stamp:=0
var expected_boot_ids: Array=[]
static var supervised_lock_owner: int=0
var supervised_lock_held:=false

func _ready() -> void:
	server_url=OS.get_environment("GAME_PROGRESSION_URL").trim_suffix("/")
	service_key=OS.get_environment("ACADEMY_SERVICE_KEY")
	server_id=OS.get_environment("ISLAND_SERVER_ID")
	host_identity=OS.get_environment("COMPUTERNAME")
	if host_identity.is_empty():host_identity=OS.get_environment("HOSTNAME")
	if host_identity.is_empty():host_identity=OS.get_unique_id()
	journal_dir=OS.get_environment("ISLAND_PROGRESSION_DIR")
	if journal_dir.is_empty():journal_dir="user://island_progression"
	boot_id=Crypto.new().generate_random_bytes(24).hex_encode()
	if server_url.is_empty() or service_key.is_empty() or server_id.is_empty() or host_identity.is_empty():
		push_error("Island authority requires GAME_PROGRESSION_URL, ACADEMY_SERVICE_KEY and ISLAND_SERVER_ID")
		stopped=true;return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(journal_dir))!=OK:
		stopped=true;push_error("Cannot create progression journal");return
	if not _lock_process():stopped=true;return
	var directory:=DirAccess.open(journal_dir)
	if directory==null:stopped=true;return
	var files:=directory.get_files();files.sort()
	for filename in files:
		if not filename.ends_with(".json"):continue
		var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(journal_dir.path_join(filename)))
		if not value is Dictionary or not value.get("body") is Dictionary or str(value.get("action","")) not in ["consume","finish"]:
			stopped=true;push_error("Invalid durable progression journal; operator recovery required");return
		value.file=filename;jobs.append(value)
	_start()

func _lock_process() -> bool:
	supervised_lock_held=_has_supervisor_lock()
	if supervised_lock_held and supervised_lock_owner!=0 and supervised_lock_owner!=get_instance_id():
		push_error("Progression process lock: another bridge owns this supervisor");return false
	var lock_path:=ProjectSettings.globalize_path(journal_dir.path_join("process.lock"))
	var identity_path:=journal_dir.path_join("process.identity")
	if FileAccess.file_exists(identity_path):
		var previous: Variant=JSON.parse_string(FileAccess.get_file_as_string(identity_path))
		if not previous is Dictionary or str(previous.get("server_id",""))!=server_id or str(previous.get("host",""))!=host_identity or int(previous.get("pid",0))<=0:return false
		if not _previous_process_stopped(int(previous.pid)):
			push_error("Progression process lock: previous dedicated process is still running");return false
		expected_boot_ids.append(str(previous.boot_id))
	var account_boot_path:=journal_dir.path_join("account.boot")
	if FileAccess.file_exists(account_boot_path):
		var previous_account_boot:=FileAccess.get_file_as_string(account_boot_path).strip_edges()
		if not previous_account_boot.is_empty() and not expected_boot_ids.has(previous_account_boot):expected_boot_ids.append(previous_account_boot)
	if DirAccess.dir_exists_absolute(lock_path):
		var owner: Variant=JSON.parse_string(FileAccess.get_file_as_string(lock_path.path_join("owner.json")))
		if not owner is Dictionary or str(owner.get("server_id",""))!=server_id or str(owner.get("host",""))!=host_identity or int(owner.get("pid",0))<=0:
			push_error("Progression process lock identity cannot be verified; operator recovery required");return false
		if not _previous_process_stopped(int(owner.get("pid",0))):
			push_error("Progression process lock: previous dedicated process is still running");return false
		# No TTL: only a positively stopped local process permits takeover.
		if DirAccess.remove_absolute(lock_path.path_join("owner.json"))!=OK or DirAccess.remove_absolute(lock_path)!=OK:return false
	if DirAccess.make_dir_absolute(lock_path)!=OK:return false
	var file:=FileAccess.open(lock_path.path_join("owner.json"),FileAccess.WRITE)
	if file==null:return false
	var identity:=JSON.stringify({"pid":OS.get_process_id(),"server_id":server_id,"host":host_identity,"boot_id":boot_id})
	file.store_string(identity);file.flush()
	var error:=file.get_error();file.close()
	owns_process_lock=error==OK and _write_atomic(identity_path,identity)
	if owns_process_lock and supervised_lock_held:supervised_lock_owner=get_instance_id()
	return owns_process_lock

func _has_supervisor_lock() -> bool:
	if OS.get_name()!="Linux":return false
	var descriptor:=OS.get_environment("ISLAND_SUPERVISOR_LOCK_FD")
	if not descriptor.is_valid_int() or int(descriptor)<3:return false
	var outbox:=ProjectSettings.globalize_path(journal_dir).trim_suffix("/")
	if OS.get_environment("ISLAND_SUPERVISED_OUTBOX")!=outbox:return false
	var expected:=outbox.get_base_dir().path_join("supervisor.lock")
	if OS.get_environment("ISLAND_SUPERVISOR_LOCK_PATH")!=expected:return false
	# The launcher acquired flock before starting this stack and passes the open
	# descriptor to every child. Inspect our fd, not the readlink child's fd.
	var output: Array=[]
	if OS.execute("/usr/bin/readlink",PackedStringArray(["/proc/%d/fd/%d"%[OS.get_process_id(),int(descriptor)]]),output,true)!=0:return false
	return not output.is_empty() and str(output[0]).strip_edges()==expected

func _write_atomic(path: String,value: String) -> bool:
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(value);file.flush()
	var error:=file.get_error();file.close()
	return error==OK and DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))==OK

func _previous_process_stopped(pid: int) -> bool:
	# Under the inherited kernel lock, a previous supervised stack cannot still
	# own this outbox. Container PID reuse must not block crash/restart recovery.
	if supervised_lock_held:return true
	# Godot OS.is_process_running only accepts children created by this process.
	# An unrelated previous server therefore needs an OS-wide, fail-closed probe.
	if OS.get_name()=="Windows":
		var output: Array=[]
		var probe:="try { $p = [System.Diagnostics.Process]::GetProcessById(%d); if ($p.HasExited) { exit 3 }; exit 0 } catch [System.ArgumentException] { exit 3 } catch { exit 4 }"%pid
		return OS.execute("powershell.exe",PackedStringArray(["-NoProfile","-NonInteractive","-Command",probe]),output,true,false)==3
	if OS.get_name()=="Linux" and DirAccess.dir_exists_absolute("/proc/self"):
		return not DirAccess.dir_exists_absolute("/proc/%d"%pid)
	return false

func _exit_tree() -> void:
	if not owns_process_lock:return
	if supervised_lock_owner==get_instance_id():supervised_lock_owner=0
	var lock_path:=ProjectSettings.globalize_path(journal_dir.path_join("process.lock"))
	DirAccess.remove_absolute(lock_path.path_join("owner.json"))
	DirAccess.remove_absolute(lock_path)

func _start() -> void:
	busy=true
	var health:=await call_account("probe",{})
	if not health.ok:busy=false;retry_at=Time.get_ticks_msec()+5000;return
	var claim:=await call_account("claim",{"expected_boot_ids":expected_boot_ids})
	if not claim.ok:
		if str(claim.code)!="service_unavailable":stopped=true;push_error("Progression instance claim blocked: "+str(claim.code))
		busy=false;retry_at=Time.get_ticks_msec()+5000;return
	if not _write_atomic(journal_dir.path_join("account.boot"),boot_id):
		_journal_failure();busy=false;return
	while not jobs.is_empty():
		if not await _deliver_first():
			busy=false;retry_at=Time.get_ticks_msec()+5000;return
	var recovery:=await call_account("recover",{})
	busy=false
	if recovery.ok:available=true;print("ISLAND_PROGRESSION_READY")
	else:retry_at=Time.get_ticks_msec()+5000

func _process(_delta: float) -> void:
	if stopped or busy or Time.get_ticks_msec()<retry_at:return
	if not available:_start()
	elif not jobs.is_empty():_drain()

func call_account(action: String,body: Dictionary) -> Dictionary:
	if stopped:return {"ok":false,"code":"service_unavailable","snapshot":{}}
	var request:=HTTPRequest.new();request.timeout=15;request.body_size_limit=1048576;add_child(request)
	var payload:=body.duplicate(true);payload.server_id=server_id;payload.boot_id=boot_id
	var error:=request.request(server_url+"/v1/internal/"+action,PackedStringArray(["Content-Type: application/json","X-Academy-Service-Key: "+service_key]),HTTPClient.METHOD_POST,JSON.stringify(payload))
	if error!=OK:request.queue_free();return {"ok":false,"code":"service_unavailable","snapshot":{}}
	var response: Array=await request.request_completed
	request.queue_free()
	var parsed: Variant=JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	var result: Dictionary=parsed if parsed is Dictionary else {}
	result.ok=int(response[0])==HTTPRequest.RESULT_SUCCESS and int(response[1])==200
	if not result.has("code"):result.code="ok" if result.ok else "service_unavailable"
	return result

func enqueue(action: String,body: Dictionary) -> bool:
	if stopped:return false
	serial+=1
	last_journal_stamp=maxi(last_journal_stamp+1,int(Time.get_unix_time_from_system()*1000000))
	var filename:="%020d-%08d-%s.json"%[last_journal_stamp,serial,boot_id.left(8)]
	var record:={"action":action,"body":body.duplicate(true),"file":filename}
	var path:=journal_dir.path_join(filename)
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return _journal_failure()
	file.store_string(JSON.stringify(record));file.flush()
	var error:=file.get_error();file.close()
	if error!=OK or DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))!=OK:return _journal_failure()
	jobs.append(record)
	return true

func _journal_failure() -> bool:
	stopped=true;available=false;push_error("Progression journal failed; battle progression halted")
	return false

func _drain() -> void:
	busy=true
	while not jobs.is_empty():
		if not await _deliver_first():break
	busy=false;retry_at=Time.get_ticks_msec()+2000

func _deliver_first() -> bool:
	var record: Dictionary=jobs[0]
	var result:=await call_account(str(record.action),record.body)
	if not result.ok:
		if str(result.code) not in ["service_unavailable","error"]:
			stopped=true;available=false;push_error("Progression receipt blocked: "+str(result.code))
		return false
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(journal_dir.path_join(str(record.file))))!=OK:return _journal_failure()
	# Preserve the existing committed finish identity for client presentation only.
	if str(record.action)=="finish":result["battle_id"]=str(record.body.get("battle_id",""))
	jobs.pop_front();committed.emit(result)
	return true
