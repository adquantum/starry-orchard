extends Node
signal status_changed(message: String)
signal progression_changed(snapshot: Dictionary)
var progression_snapshot: Dictionary={}
signal identity_changed
var character_ready:=false
var session_generation:=0
var verified_username:=""
var game_transport: Node
var bootstrap_busy:=false
var economy_busy:=false
const DEFAULT_ACCOUNT_SERVER:="http://101.43.174.221:8787"
const FILES=["fusion_3d_story.json","academy_chapter_one.json","academy_wardrobe.json","academy_custom_decks.json"]
var server_url:=DEFAULT_ACCOUNT_SERVER
var token:=""
var account: Dictionary={}
var active_character: Dictionary={}
var cache_root:=""
var revision:=0
var synced_hash:=""
var sync_busy:=false
var local_write_failed:=false
var status:="尚未登录"
var conflict: Dictionary={}
var last_username:=""
var last_character_preview: Dictionary={}
var character_previews: Dictionary={}
var auto_sync_enabled:=true
var connection_save_enabled:=true
var cache_base:="user://account_cache"
func _ready() -> void:
	var config:=ConfigFile.new()
	if config.load("user://account_connection.cfg")==OK:
		last_username=str(config.get_value("connection","username",""))
		var saved: Variant=config.get_value("preview","character",{})
		if saved is Dictionary:last_character_preview=saved.duplicate(true)
	if "--weekend-local-services" in OS.get_cmdline_user_args():server_url="http://127.0.0.1:18787"
	var timer:=Timer.new()
	timer.wait_time=30
	timer.autostart=true
	timer.timeout.connect(func():
		if auto_sync_enabled and character_ready and not active_character.is_empty() and conflict.is_empty():sync_save())
	add_child(timer)
func message(text: String) -> void:
	status=text
	status_changed.emit(text)
func configure_server(url: String) -> bool:
	url=url.strip_edges().trim_suffix("/")
	if not url.begins_with("https://") and not url.begins_with("http://"):return false
	if url.contains("@") or url.contains("?") or url.contains("#"):return false
	if not account.is_empty() and url!=server_url:return false
	server_url=url
	return true
func connection_saved() -> void:
	if not connection_save_enabled:return
	var config:=ConfigFile.new()
	config.set_value("connection","server",server_url)
	config.set_value("connection","username",last_username)
	config.set_value("preview","character",last_character_preview)
	config.save("user://account_connection.cfg")
func remember_character_preview() -> void:
	if not character_ready or active_character.is_empty():return
	var appearance: Dictionary=progression_snapshot.get("appearance",{})
	if appearance.is_empty():return
	var value: Dictionary={"id":str(active_character.id),"school":str(active_character.school),"appearance":appearance.duplicate(true)}
	character_previews[character_cache(str(active_character.id))]=value.duplicate(true)
	if value==last_character_preview:return
	last_character_preview=value
	connection_saved()
func api(path: String, method: int=HTTPClient.METHOD_GET, data: Dictionary={}) -> Dictionary:
	var request_token:=token
	var request:=HTTPRequest.new()
	request.timeout=10
	request.body_size_limit=1048576
	add_child(request)
	var headers:=PackedStringArray(["Content-Type: application/json"])
	if not token.is_empty():headers.append("Authorization: Bearer "+token)
	var error:=request.request(server_url+path,headers,method,JSON.stringify(data) if method!=HTTPClient.METHOD_GET else "")
	if error!=OK:
		request.queue_free()
		return {"ok":false,"status":0,"error":"未连到服务器","code":"service_unavailable","snapshot":{}}
	var response: Array=await request.request_completed
	request.queue_free()
	var parser:=JSON.new()
	var body: Variant=parser.data if parser.parse((response[3] as PackedByteArray).get_string_from_utf8())==OK else null
	var result: Dictionary=body if body is Dictionary else {}
	result["status"]=int(response[1])
	result["ok"]=int(response[0])==HTTPRequest.RESULT_SUCCESS and int(response[1])>=200 and int(response[1])<300
	if not result.ok and not result.has("error"):result.error="暂时无法连接服务器，本地进度会保留。"
	if not result.has("code"):result.code="ok" if result.ok else "service_unavailable"
	if int(result.status)==401 and not request_token.is_empty() and token==request_token:
		token="";verified_username="";account.clear();leave_character()
		message("登录已过期，请重新登录。")
	return result

func apply_progression(value: Dictionary) -> bool:
	if active_character.is_empty() or str(value.get("character_id",""))!=str(active_character.get("id","")) or str(value.get("account_id",""))!=str(account.get("id","")):return false
	if int(value.get("schema_version",0))!=1 or str(value.get("school",""))!=str(active_character.school):return false
	if not progression_snapshot.is_empty():
		if int(value.get("character_revision",0))<int(progression_snapshot.get("character_revision",0)) or int(value.get("account_revision",0))<int(progression_snapshot.get("account_revision",0)):return false
	if progression_snapshot==value:return true
	progression_snapshot=value.duplicate(true)
	remember_character_preview()
	progression_changed.emit(progression_snapshot.duplicate(true))
	return true

func _progression_api(action: String,data: Dictionary={},read_only: bool=false) -> Dictionary:
	if active_character.is_empty() or token.is_empty():return {"ok":false,"code":"unauthorized","snapshot":{}}
	if economy_busy or not is_instance_valid(game_transport) or not game_transport.connected or not game_transport.authenticated:return {"ok":false,"code":"service_unavailable","snapshot":{}}
	economy_busy=true
	var generation:=session_generation
	var request_token:=token
	var result:=await _game_request(game_transport,{"op":"economy","action":action,"payload":data},"economy_result",generation)
	if generation!=session_generation:return {"ok":false,"code":"cancelled","snapshot":{}}
	economy_busy=false
	if request_token!=token:return {"ok":false,"code":"cancelled","snapshot":{}}
	if str(result.get("code",""))=="unauthorized":_expire_session()
	if result.ok and result.get("snapshot") is Dictionary:apply_progression(result.snapshot)
	if not result.has("snapshot"):result.snapshot={}
	return result

func refresh_progression() -> Dictionary:return await _progression_api("progression",{},true)
func buy_shop_offer(offer_id: String,quantity: int,request_id: String) -> Dictionary:
	var catalog: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/weekend_shop_catalog.json"))
	if not catalog is Dictionary:return {"ok":false,"code":"service_unavailable","snapshot":{}}
	return await _progression_api("shop-buy",{"offer_id":offer_id,"quantity":quantity,"request_id":request_id,"catalog_version":str(catalog.get("catalog_version",""))})
func exchange_equipment(slot: String,tier: String,payment_cards: Dictionary,request_id: String) -> Dictionary:
	return await _progression_api("exchange",{"slot":slot,"tier":tier,"payment_cards":payment_cards,"request_id":request_id})
func equip_stat(slot: String,item_id: String,request_id: String) -> Dictionary:
	return await _progression_api("equip-stat",{"slot":slot,"item_id":item_id,"request_id":request_id})
func save_appearance(value: Dictionary,request_id: String) -> Dictionary:
	return await _progression_api("appearance",{"value":value,"request_id":request_id})
func equip_wing(wing_id: String,request_id: String) -> Dictionary:
	return await _progression_api("equip-wing",{"wing_id":wing_id,"request_id":request_id})
func island_ticket() -> Dictionary:return {"ok":false,"code":"client_upgrade_required","snapshot":{}}
func authenticate(username: String,password: String,register: bool=false) -> Dictionary:
	var health:=await api("/health")
	if not health.ok:return health
	if int(health.get("version",0))<1:return {"ok":false,"code":"server_upgrade_required","error":"登录服务协议不兼容。"}
	var result:=await api("/v1/register" if register else "/v1/login",HTTPClient.METHOD_POST,{"username":username,"password":password})
	if result.ok:
		leave_character()
		token=str(result.token)
		account=result.account
		verified_username=str(account.get("username","")).to_lower()
		identity_changed.emit()
		last_username=username
		connection_saved()
		message("已登录 · "+str(account.username))
	return result
func change_password(old: String,new_password: String) -> Dictionary:
	var result:=await api("/v1/password",HTTPClient.METHOD_POST,{"old_password":old,"new_password":new_password})
	if result.ok:token=str(result.token)
	return result
func list_characters() -> Dictionary:
	return await api("/v1/characters")
func preview_character(character: Dictionary) -> Dictionary:
	# Read the game ledger: identity-service saves may still hold the creation outfit.
	var generation:=session_generation
	var cid:=str(character.id)
	var key:=character_cache(cid)
	var result: Dictionary=await _bootstrap_progression(cid,generation)
	if generation!=session_generation:return {}
	var snapshot: Dictionary=result.get("snapshot",{})
	var appearance: Variant=snapshot.get("appearance",{})
	if result.get("ok",false) and str(snapshot.get("character_id",""))==cid and str(snapshot.get("account_id",""))==str(account.get("id","")) and str(snapshot.get("school",""))==str(character.school) and appearance is Dictionary and not appearance.is_empty():
		var value: Dictionary={"id":cid,"school":str(character.school),"appearance":appearance.duplicate(true)}
		character_previews[key]=value
		last_character_preview=value.duplicate(true)
		connection_saved()
		return appearance.duplicate(true)
	var cached: Dictionary=character_previews.get(key,{})
	if cached.is_empty() and str(last_character_preview.get("id",""))==cid:
		cached=last_character_preview
	return cached.get("appearance",{}).duplicate(true)
func legacy_snapshot() -> Dictionary:
	var result: Dictionary={}
	for filename in FILES:
		var path: String="user://"+filename
		if FileAccess.file_exists(path):
			var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:result[filename]=data
	return result
func create_character(name_value: String,school: String,gender: String,hair: String,import_legacy: bool=false,creation_appearance: Dictionary={}) -> Dictionary:
	var data: Dictionary={"name":name_value,"school":school,"gender":gender,"hairstyle":hair}
	if import_legacy:
		data.save=legacy_snapshot()
		var ids: Array=["fire_student","ice_guardian","storm_duelist","myth_scholar","life_healer","death_reaper","balance_adept"]
		var schools: Array=["fire","ice","storm","myth","life","death","balance"]
		var party: Array=data.save.get("fusion_3d_story.json",{}).get("party",[])
		if not party.is_empty() and ids.has(str(party[0])):data.school=schools[ids.find(str(party[0]))]
		var appearance: Dictionary=data.save.get("academy_wardrobe.json",{}).get("outfits",{}).get(str(data.school),{})
		data.gender=appearance.get("gender",gender)
		data.hairstyle=appearance.get("hairstyle",hair)
	else:
		# Existing save-import API accepts presentation; the ledger independently validates it.
		var schools: Array=["fire","ice","storm","myth","life","death","balance"]
		var ids: Array=["fire_student","ice_guardian","storm_duelist","myth_scholar","life_healer","death_reaper","balance_adept"]
		var lead: String=ids[schools.find(school)]
		var party: Array=[lead]
		for id in ["ice_guardian","life_healer","storm_duelist","fire_student"]:
			if id!=lead and party.size()<4:party.append(id)
		var outfit := creation_appearance.duplicate(true)
		if outfit.is_empty():
			for slot in ["body", "hat", "robe", "boots", "staff", "aura"]:outfit[slot] = school
			outfit.merge({"gender":gender,"hairstyle":hair,"model_style":"teen"})
		data.save={"fusion_3d_story.json":{"quest_step":0,"party":party,"starting_world":preload("res://scripts/worlds/orchard_character_start.gd").ORIGIN},"academy_chapter_one.json":{"version":1,"step":0,"xp":0,"samples":[],"rewards":[]},"academy_wardrobe.json":{"version":3,"outfits":{school:outfit}},"academy_custom_decks.json":{}}
	return await api("/v1/characters",HTTPClient.METHOD_POST,data)
func character_cache(id: String) -> String:
	return cache_base+"/"+server_url.sha256_text().left(16)+"/"+str(account.id)+"/"+id
func path_for(filename: String) -> String:
	assert(FILES.has(filename))
	return (cache_root+"/" if not cache_root.is_empty() else "user://")+filename
func write_json(path: String,data: Dictionary) -> bool:
	var ok:=_write_json(path,data)
	if not ok:
		local_write_failed=true
		message("本地存档写入失败，请检查磁盘空间。")
	return ok
func _write_json(path: String,data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error:=file.get_error()
	file.close()
	if error!=OK:return false
	if FileAccess.file_exists(path):
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(path+".bak"))!=OK:return false
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))==OK
func write_save(filename: String,data: Dictionary) -> bool:
	var ok:=write_json(path_for(filename),data)
	if not ok:message("本地存档写入失败，请检查磁盘空间。")
	return ok
func snapshot() -> Dictionary:
	var result: Dictionary={}
	for filename in FILES:
		var path:=path_for(filename)
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else {}
		result[filename]=data if data is Dictionary else {}
	return result
func digest(data: Dictionary) -> String:
	return JSON.stringify(data,"",true).sha256_text()
func save_metadata() -> bool:
	return write_json(cache_root+"/sync.json",{"revision":revision,"synced_hash":synced_hash})
func use_remote(data: Dictionary) -> bool:
	for filename in FILES:
		if not write_json(path_for(filename),data.save.get(filename,{})):return false
	revision=int(data.revision)
	synced_hash=digest(snapshot())
	return save_metadata()
func activate_character(id: String) -> Dictionary:
	leave_character()
	var generation:=session_generation
	var remote:=await api("/v1/characters/"+id)
	if not remote.ok:return remote
	var progression_result:=await _bootstrap_progression(id,generation)
	if generation!=session_generation:return {"ok":false,"code":"unauthorized","error":"登录状态已改变，请重新选择角色。"}
	if not progression_result.ok:
		if str(progression_result.get("code",""))=="unauthorized":_expire_session()
		if not progression_result.has("error"):progression_result.error="游戏服务器权益暂不可用，请稍后重试。"
		return progression_result
	var candidate: Dictionary=progression_result.get("snapshot",{})
	if int(candidate.get("schema_version",0))!=1 or str(candidate.get("character_id",""))!=id or str(candidate.get("account_id",""))!=str(account.get("id","")) or str(candidate.get("school",""))!=str(remote.character.school):return {"ok":false,"code":"invalid_progression_snapshot","error":"服务器角色权益不完整，请重试。"}
	active_character=remote.character
	progression_snapshot={}
	apply_progression(candidate)
	cache_root=character_cache(id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_root))
	var meta: Variant=JSON.parse_string(FileAccess.get_file_as_string(cache_root+"/sync.json")) if FileAccess.file_exists(cache_root+"/sync.json") else {}
	if not meta is Dictionary:meta={}
	revision=int(meta.get("revision",0))
	synced_hash=str(meta.get("synced_hash",""))
	var pending: bool=revision>0 and digest(snapshot())!=synced_hash
	if pending and revision!=int(remote.revision):
		conflict=remote
		message("本地与云端都有新进度，请选择要保留的版本。")
		return {"ok":false,"code":"save_conflict","error":status}
	if pending:
		message("读取本地待同步进度")
	else:
		if not use_remote(remote):
			leave_character()
			return {"ok":false,"error":"无法写入本地角色存档。"}
	var store:=get_node("/root/Wardrobe")
	store.save_path=path_for("academy_wardrobe.json")
	store.save_enabled=true
	store.load_save()
	character_ready=true
	remember_character_preview()
	identity_changed.emit()
	return {"ok":true}
func resolve_conflict(keep_local: bool) -> Dictionary:
	if conflict.is_empty():return {"ok":false,"error":"没有待处理的存档冲突。"}
	# Preserve both snapshots before an explicit selection replaces either version.
	var folder:=cache_root+"/conflicts/"+str(int(Time.get_unix_time_from_system()))
	if not write_json(folder+"/local.json",snapshot()) or not write_json(folder+"/cloud.json",conflict.save):return {"ok":false,"error":"无法备份冲突存档。"}
	if keep_local:
		revision=int(conflict.revision)
		if not save_metadata():return {"ok":false,"error":"无法保存同步信息。"}
	else:
		if not use_remote(conflict):return {"ok":false,"error":"无法写入云端存档。"}
	conflict.clear()
	character_ready=true
	remember_character_preview()
	var result:=await sync_save()
	get_node("/root/Wardrobe").save_path=path_for("academy_wardrobe.json")
	get_node("/root/Wardrobe").load_save()
	return result
func sync_save() -> Dictionary:
	if active_character.is_empty() or not character_ready:return {"ok":true}
	while sync_busy:await get_tree().process_frame
	if active_character.is_empty() or not character_ready:return {"ok":true}
	var generation:=session_generation
	if not conflict.is_empty():return {"ok":false,"code":"save_conflict","error":"云存档有冲突，请返回角色管理处理。"}
	var data:=snapshot()
	var checksum:=digest(data)
	if checksum==synced_hash:
		message("已保存 · 云端已同步")
		return {"ok":true}
	sync_busy=true
	message("正在同步存档…")
	var result:=await api("/v1/characters/"+str(active_character.id)+"/save",HTTPClient.METHOD_PUT,{"revision":revision,"save":data})
	sync_busy=false
	if generation!=session_generation:return {"ok":false,"code":"unauthorized","error":"角色已切换。"}
	if result.ok:
		revision=int(result.revision)
		synced_hash=checksum
		if not save_metadata():
			message("云端已保存，但本地同步信息写入失败。")
			return {"ok":false,"error":status}
		message("已保存 · 云端已同步")
	else:
		message(str(result.error))
	return result
func leave_character() -> void:
	remember_character_preview()
	session_generation+=1
	economy_busy=false
	character_ready=false
	active_character.clear()
	progression_snapshot.clear()
	progression_changed.emit({})
	cache_root=""
	revision=0
	synced_hash=""
	conflict.clear()
	get_node("/root/Wardrobe").save_path="user://academy_wardrobe.json"
	get_node("/root/Wardrobe").load_save()
	identity_changed.emit()
func _expire_session() -> void:
	token="";verified_username="";account.clear();leave_character();message("登录已过期，请重新登录。")

func _game_request(net: Node,payload: Dictionary,response_op: String,generation: int) -> Dictionary:
	var correlation:=Crypto.new().generate_random_bytes(12).hex_encode()
	payload.correlation=correlation
	var reply: Dictionary={}
	var callback:=func(data: Dictionary):
		if str(data.get("op",""))==response_op and str(data.get("correlation",""))==correlation:reply.merge(data,true)
	net.battle_received.connect(callback)
	net.send_request(payload)
	var deadline:=Time.get_ticks_msec()+25000
	while reply.is_empty() and is_instance_valid(net) and net.connected and generation==session_generation and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if is_instance_valid(net) and net.battle_received.is_connected(callback):net.battle_received.disconnect(callback)
	if generation!=session_generation:return {"ok":false,"code":"cancelled","snapshot":{}}
	if reply.is_empty():return {"ok":false,"code":"service_unavailable","snapshot":{}}
	return reply

func _bootstrap_progression(cid: String,generation: int) -> Dictionary:
	# Preview and enter-world requests share one temporary multiplayer root.
	while bootstrap_busy and generation==session_generation:await get_tree().process_frame
	if generation!=session_generation:return {"ok":false,"code":"cancelled","snapshot":{}}
	if is_instance_valid(game_transport):return {"ok":false,"code":"service_unavailable","snapshot":{}}
	var api_multiplayer:=multiplayer
	if api_multiplayer.multiplayer_peer!=null and not api_multiplayer.multiplayer_peer is OfflineMultiplayerPeer:return {"ok":false,"code":"service_unavailable","snapshot":{}}
	bootstrap_busy=true
	var old_root: NodePath=api_multiplayer.root_path
	var holder:=Node.new();holder.name="ProgressionBootstrap";add_child(holder)
	var net:=preload("res://scripts/fusion_3d/town_network.gd").new()
	net.name="Transport";net.normalize_rpc_root=true;net.bootstrap_only=true;net.cloud_required=true;holder.add_child(net)
	var address:="127.0.0.1:29760" if "--weekend-local-services" in OS.get_cmdline_user_args() else "101.43.174.221"
	var result: Dictionary={"ok":false,"code":"service_unavailable","snapshot":{}}
	if net.join(address)==OK:
		var deadline:=Time.get_ticks_msec()+14000
		while net.connecting and generation==session_generation and Time.get_ticks_msec()<deadline:await get_tree().process_frame
		if net.connected and generation==session_generation:
			result=await _game_request(net,{"op":"bootstrap","protocol_version":2,"token":token,"character_id":cid},"bootstrap_result",generation)
	net.disconnect_town()
	api_multiplayer.root_path=old_root
	holder.queue_free()
	bootstrap_busy=false
	return result
func is_verified_admin() -> bool:
	return not token.is_empty() and verified_username=="admin" and str(account.get("username","")).to_lower()==verified_username
func verify_admin_session() -> bool:
	if not is_verified_admin():return false
	var generation:=session_generation
	var result:=await api("/v1/me")
	return generation==session_generation and result.ok and str(result.get("account",{}).get("username","")).to_lower()=="admin" and is_verified_admin()
func logout() -> void:
	var pending_logout=not token.is_empty()
	verified_username=""
	leave_character()
	if pending_logout:await api("/v1/logout",HTTPClient.METHOD_POST)
	token=""
	account.clear()
	leave_character()
	message("已退出账号，本地待同步进度已保留。")

