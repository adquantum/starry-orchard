extends Node
## Authoritative shared island. World traffic stays global; every battle owns an isolated room.
const Geo=preload("res://scripts/server/encounter_geometry.gd")
const Pvp=preload("res://scripts/server/pvp_encounter.gd")
const Room=preload("res://scripts/server/island_battle_room.gd")
var net: Node
var loadout=preload("res://scripts/worlds/island_loadout.gd").new()
var terrain=preload("res://scripts/server/terrain_heights.gd").new()
var ai=preload("res://scripts/fusion_3d/world_one_ai.gd").new()
var sites: Array=[]
var profiles: Dictionary={}
var cooldowns: Dictionary={}
var rooms: Dictionary={}
var peer_rooms: Dictionary={}
var observer_rooms: Dictionary={}
var observer_protocols: Dictionary={}
var observer_tick:=0.0
var load_log_tick:=0.0
var site_rooms: Dictionary={}
var next_encounter:=0
var max_rooms:=16
var pvp_lobby:=Pvp.new()
var request_limits: Dictionary={}
var chat_limits: Dictionary={}
var test_ai_counts: Dictionary={}
var scan_tick:=0.0
var clock_tick:=0.0
var port:=29710
var progression: Node
var authentication_pending: Dictionary={}
var connection_bindings: Dictionary={}
var economy_pending: Dictionary={}
var deferred_profiles: Dictionary={}
var orchard_authority: Node

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):port=int(arg.trim_prefix("--port="))
	loadout.content.validate_art_paths=false
	loadout.setup("res://server/no_saved_deck.json","life")
	if not loadout.content.errors.is_empty():push_error(str(loadout.content.errors));get_tree().quit(1);return
	sites=preload("res://scripts/server/frost_encounter_catalog.gd").all_sites()
	orchard_authority=preload("res://scripts/server/star_orchard_authority.gd").new()
	orchard_authority.name="StarOrchardAuthority";add_child(orchard_authority);orchard_authority.setup(self)
	terrain.load_world("res://assets/worlds/frostroarisland_teen/world.json")
	net=preload("res://scripts/server/star_orchard_transport.gd").new()
	net.coordinator=self
	net.name="Transport";net.normalize_rpc_root=true;net.dedicated=true
	net.max_clients=32;net.position_limit=10000.0;net.speed_limit=160.0
	add_child(net)
	net.request_received.connect(_request);net.peer_left.connect(_left)
	progression=preload("res://scripts/server/progression_bridge.gd").new()
	progression.name="ProgressionBridge";add_child(progression)
	progression.committed.connect(_progression_committed)
	var error: int=net.host(port,"0.0.0.0")
	if error!=OK:push_error("Listen failed: "+error_string(error));get_tree().quit(1);return
	var deadline:=Time.get_ticks_msec()+40000
	while not progression.available and not progression.stopped and Time.get_ticks_msec()<deadline:await get_tree().create_timer(.1).timeout
	if not progression.available:push_error("Island ledger recovery/identity readiness failed");get_tree().quit(1);return
	print("ISLAND_SERVER_READY UDP 0.0.0.0:",port," sites=",sites.size()," protocol=2 ledger=ready")

func now() -> float:return Time.get_ticks_msec()/1000.0
func begin_site_cooldown(index: int) -> void:
	cooldowns[index]=now()+maxf(20.0,float(sites[index].get("cooldown_seconds",20)))
func monster_position(site: int,index: int) -> Vector3:
	var at:=Geo.roam_position(sites[site],index,now())
	at.y=Geo.point(sites[site].center).y if bool(sites[site].get("fixed_roam_height",false)) else terrain.height(at)
	return at

func _process(delta: float) -> void:
	if net==null or not net.connected:return
	load_log_tick+=delta
	if load_log_tick>=30.0:
		load_log_tick=0.0
		print("ISLAND_LOAD connected=",net.multiplayer.get_peers().size()," authenticated=",profiles.size()," rooms=",rooms.size()," observers=",observer_rooms.size()," journal_pending=",progression.jobs.size()," process_ms=",snappedf(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,0.1))
	clock_tick+=delta
	if clock_tick>=2:
		clock_tick=0;net.publish({"op":"clock","seconds":now()})
	scan_tick+=delta
	if scan_tick>=0.1:
		scan_tick=0;_scan_contacts()
	if pvp_lobby.site_index>=0 and Time.get_ticks_msec()>=pvp_lobby.expires:_cancel_pvp_wait()
	observer_tick+=delta
	if observer_tick>=0.25:
		observer_tick=0.0;_refresh_observers()

func _refresh_observers() -> void:
	for peer in observer_rooms.keys():
		if not profiles.has(peer) or not net.positions.has(peer):_stop_observing(int(peer))
	for value in profiles:
		var peer:=int(value)
		if not net.positions.has(peer):continue
		if not bool(observer_protocols.get(peer,false)):
			_stop_observing(peer);continue
		if peer_rooms.has(peer) or pvp_lobby.teams.has(peer):
			_stop_observing(peer,int(peer_rooms.get(peer,-1)));continue
		var nearest: Node
		var best:=float(net.POSITION_INTEREST_METRES)*float(net.POSITION_INTEREST_METRES)
		for room in rooms.values():
			if not orchard_authority.same_world(peer,int(room.descriptor.get("site",-1))):continue
			if orchard_authority.is_tutorial_peer(peer):continue
			if room.engine==null or room.preparing or not room.gathering:continue
			var offset: Vector3=net.positions[peer]-Geo.point(sites[int(room.descriptor.site)].center)
			var distance:=Vector2(offset.x,offset.z).length_squared()
			if distance<best:
				best=distance;nearest=room
		var next_id:=int(nearest.encounter) if nearest!=null else -1
		if int(observer_rooms.get(peer,-1))==next_id:continue
		_stop_observing(peer)
		if nearest!=null:
			observer_rooms[peer]=next_id
			nearest.observe(peer)

func _stop_observing(peer: int,keep_stage_for: int=-1) -> void:
	if not observer_rooms.has(peer):return
	var previous:=int(observer_rooms[peer]);observer_rooms.erase(peer)
	if previous!=keep_stage_for:
		net.publish({"op":"close","encounter":previous,"winner":-1,"observer_only":true},peer)

func observing(peer: int,room: Node) -> bool:
	return profiles.has(peer) and bool(observer_protocols.get(peer,false)) and not peer_rooms.has(peer) and int(observer_rooms.get(peer,-1))==room.encounter

func observer_recipients(room: Node) -> Array[int]:
	var result: Array[int]=[]
	for peer in observer_rooms:
		if observing(int(peer),room):result.append(int(peer))
	return result

func _available(peer: Variant) -> bool:
	var id:=int(peer)
	return progression!=null and progression.available and profiles.has(id) and net.positions.has(id) and not peer_rooms.has(id) and not pvp_lobby.teams.has(id) and not authentication_pending.has(id)

func _scan_contacts() -> void:
	if rooms.size()>=max_rooms:return
	for index in sites.size():
		if orchard_authority.is_site(index):continue
		if site_rooms.has(index) or now()<float(cooldowns.get(index,0)):continue
		if bool(sites[index].get("pvp",false)):
			_scan_pvp(index);continue
		for peer in net.positions:
			if orchard_authority.is_peer(int(peer)):continue
			if not _available(peer):continue
			if Geo.in_arena(net.positions[peer],sites[index]):
				start_contact(index,int(peer));break
		if rooms.size()>=max_rooms:return

func _new_room(index: int, private_room: bool = false) -> Node:
	if rooms.size()>=max_rooms or (not private_room and site_rooms.has(index)):return null
	next_encounter+=1
	var room: Node=preload("res://scripts/server/star_orchard_battle_room.gd").new() if orchard_authority.is_site(index) else Room.new()
	room.name="BattleRoom_%d"%next_encounter
	room.configure(self,net,loadout,terrain,ai,sites,profiles,cooldowns,next_encounter)
	room.test_ai_counts=test_ai_counts
	room.closed.connect(_room_closed)
	rooms[next_encounter]=room
	if not private_room:site_rooms[index]=next_encounter
	add_child(room)
	return room

func start_contact(index: int,trigger: int) -> void:
	if orchard_authority.is_site(index) or orchard_authority.is_peer(trigger):return
	if index<0 or index>=sites.size() or not _available(trigger):return
	if not Geo.in_arena(net.positions[trigger],sites[index]):return
	var candidates: Array[int]=[]
	for peer in net.positions:
		if not orchard_authority.is_peer(int(peer)) and _available(peer) and Geo.in_arena(net.positions[peer],sites[index]):candidates.append(int(peer))
	candidates.sort()
	var room:=_new_room(index)
	if room==null:return
	if not await room.start_pve(index,trigger,candidates):
		_discard_room(room,index);return
	for peer in room.members:_reserve_peer(int(peer),room)

func _request(peer: int,data: Dictionary) -> void:
	var bucket: Dictionary=request_limits.get(peer,{"second":0,"count":0})
	var second:=Time.get_ticks_msec()/1000
	if int(bucket.second)!=second:bucket={"second":second,"count":0}
	bucket.count+=1;request_limits[peer]=bucket
	if int(bucket.count)>80:return
	var op:=str(data.get("op",""))
	if op=="bootstrap":
		if not authentication_pending.has(peer) and not profiles.has(peer):_bootstrap(peer,data)
		return
	if op=="economy":
		if profiles.has(peer) and not economy_pending.has(peer):_economy(peer,data)
		return
	if op=="profile":
		if peer_rooms.has(peer) or pvp_lobby.teams.has(peer) or authentication_pending.has(peer):return
		if economy_pending.has(peer):deferred_profiles[peer]=data.duplicate(true);return
		_authenticate_profile(peer,data)
		return
	if not profiles.has(peer):return
	if orchard_authority.handle(peer,data):return
	if op=="chat":
		var sent_at:=Time.get_ticks_msec()
		if sent_at-int(chat_limits.get(peer,0))<700:return
		chat_limits[peer]=sent_at
		var chat_text: String=net.clean_chat_text(data.get("text",""))
		if chat_text.is_empty():return
		var test_result: Dictionary=preload("res://scripts/worlds/island_ai_allies.gd").apply_test_command(test_ai_counts,peer,chat_text,peer_rooms.has(peer) or pvp_lobby.teams.has(peer),profiles.has(peer))
		if not test_result.is_empty():
			net.publish({"op":"chat","peer":0,"name":"系统","text":str(test_result.message)},peer);return
		var appearance: Dictionary=net.appearances.get(peer,{})
		orchard_authority.publish_chat(peer,{"op":"chat","peer":peer,"name":net.clean_player_name(appearance.get("name","冒险者")),"text":chat_text})
		return
	if op=="hello":
		net.publish({"op":"clock","seconds":now()},peer)
		if orchard_authority.is_peer(peer):orchard_authority.send_state(peer)
		var current:=room_for_peer(peer)
		if current!=null:current.observe(peer)
		else:_refresh_observers()
		return
	var encounter:=int(data.get("encounter",-1))
	var room: Node=rooms.get(encounter)
	if room==null or not room.accepts(peer):return
	room.request(peer,data)

func room_for_peer(peer: int) -> Node:
	var encounter:=int(peer_rooms.get(peer,-1))
	return rooms.get(encounter)

func peer_available(peer: int) -> bool:return not orchard_authority.is_peer(peer) and _available(peer)

func _reserve_peer(peer: int,room: Node) -> bool:
	if peer_rooms.has(peer) and int(peer_rooms[peer])!=room.encounter:return false
	_stop_observing(peer,room.encounter)
	peer_rooms[peer]=room.encounter;net.position_frozen[peer]=true
	return true

func _release_peer(peer: int,room: Node) -> void:
	if int(peer_rooms.get(peer,-1))==room.encounter:peer_rooms.erase(peer)
	net.position_frozen.erase(peer)

func _room_closed(room: Node,departed: Array,winner: int) -> void:
	for peer in observer_rooms.keys():
		if int(observer_rooms[peer])==room.encounter:observer_rooms.erase(peer)
	for peer in departed:_release_peer(int(peer),room)
	var site:=int(room.descriptor.get("site",-1))
	rooms.erase(room.encounter)
	if int(site_rooms.get(site,-1))==room.encounter:site_rooms.erase(site)
	print("ROOM_RELEASE id=",room.encounter," winner=",winner," active_rooms=",rooms.size())
	room.queue_free()

func _discard_room(room: Node,index: int) -> void:
	room.cancel_preparation()
	for peer in peer_rooms.keys():
		if int(peer_rooms[peer])==room.encounter:_release_peer(int(peer),room)
	rooms.erase(room.encounter)
	if int(site_rooms.get(index,-1))==room.encounter:site_rooms.erase(index)
	room.queue_free()

func _left(peer: int) -> void:
	test_ai_counts.erase(peer)
	orchard_authority.left(peer)
	observer_rooms.erase(peer)
	observer_protocols.erase(peer)
	if connection_bindings.has(peer):
		progression.call_account("disconnect",{"connection_id":connection_bindings[peer]})
		connection_bindings.erase(peer)
	economy_pending.erase(peer)
	deferred_profiles.erase(peer)
	authentication_pending.erase(peer)
	pvp_lobby.teams.erase(peer)
	if pvp_lobby.site_index>=0 and pvp_lobby.teams.is_empty():_cancel_pvp_wait()
	var current:=room_for_peer(peer)
	if current!=null:current.peer_left(peer)
	peer_rooms.erase(peer);profiles.erase(peer);request_limits.erase(peer);chat_limits.erase(peer)
	net.position_frozen.erase(peer)

func _scan_pvp(index: int) -> void:
	if site_rooms.has(index):return
	if pvp_lobby.site_index>=0 and Time.get_ticks_msec()>=pvp_lobby.expires:
		_cancel_pvp_wait();return
	var available_positions: Dictionary={}
	var available_profiles: Dictionary={}
	for peer in net.positions:
		if orchard_authority.is_peer(int(peer)):continue
		if peer_rooms.has(int(peer)) or not profiles.has(peer):continue
		available_positions[peer]=net.positions[peer];available_profiles[peer]=profiles[peer]
	var previous:=pvp_lobby.teams.size()
	pvp_lobby.scan(index,sites[index],available_positions,available_profiles,Time.get_ticks_msec())
	if pvp_lobby.teams.size()!=previous:
		for peer in pvp_lobby.teams:net.position_frozen[peer]=true
		_publish_to(pvp_lobby.teams.keys(),{"op":"pvp_wait","site":index,"teams":pvp_lobby.teams,"remaining":maxf(0,(pvp_lobby.expires-Time.get_ticks_msec())/1000.0)})
	if not pvp_lobby.ready():return
	var descriptor:=pvp_lobby.describe(loadout,profiles,net.positions,net.appearances)
	var room:=_new_room(index)
	if room==null:return
	if not await room.start_pvp(index,descriptor):
		_discard_room(room,index);_cancel_pvp_wait();return
	for peer in room.members:_reserve_peer(int(peer),room)
	pvp_lobby.clear()

func _authenticate_profile(peer: int,data: Dictionary) -> void:
	if int(data.get("protocol_version",0))!=2 or int(data.get("battle_wire_version",0))!=3:
		net.publish({"op":"server_error","code":"client_upgrade_required","message":"战斗协议已更新，请更新客户端后重新连接。"},peer);return
	var requested_profile: Variant=data.get("profile",{})
	if not requested_profile is Dictionary or not preload("res://scripts/worlds/island_ai_allies.gd").valid_request(requested_profile.get("ai",0)):
		net.publish({"op":"server_error","code":"invalid_ai_count","message":"AI 助战最多一位，请重新选择固定搭档。"},peer);return
	if not progression.available:
		net.publish({"op":"server_error","code":"service_unavailable","message":"账号服务正在恢复，请稍后重试入场。"},peer);return
	var authentication_id:=Crypto.new().generate_random_bytes(12).hex_encode()
	authentication_pending[peer]=authentication_id
	var binding: String=str(progression.boot_id)+":"+str(peer)+":"+authentication_id
	var result: Dictionary=await progression.call_account("authenticate",{"token":str(data.get("token","")),"character_id":str(data.get("character_id","")),"connection_id":binding})
	if bool(result.get("ok", false)):await orchard_authority.migrate_legacy_accounts()
	if str(authentication_pending.get(peer,""))!=authentication_id:
		progression.call_account("disconnect",{"connection_id":binding});return
	authentication_pending.erase(peer)
	if not result.ok:
		progression.call_account("disconnect",{"connection_id":binding})
		net.publish({"op":"server_error","code":result.code,"message":"账号入场验证失败："+str(result.code)},peer)
		if str(result.code)=="unauthorized":net._peer_disconnected(peer)
		return
	var snapshot: Dictionary=result.snapshot
	snapshot["orchard_journey"] = orchard_authority.state_for_identity(snapshot)
	var supplied: Variant=data.get("profile",{})
	if not supplied is Dictionary or str(supplied.get("school",""))!=str(snapshot.school) or not loadout.valid_counts(supplied.get("counts")) or typeof(supplied.get("ai",0)) not in [TYPE_INT,TYPE_FLOAT]:
		progression.call_account("disconnect",{"connection_id":binding})
		net.publish({"op":"server_error","code":"invalid_equipment","message":"角色学院或卡组无效。"},peer);return
	for other in profiles:
		if int(other)!=peer and str(profiles[other].progression_snapshot.character_id)==str(snapshot.character_id):
			progression.call_account("disconnect",{"connection_id":binding})
			net.publish({"op":"server_error","code":"in_battle","message":"该角色已在此专服连接。"},peer);return
	profiles[peer]={"school":str(snapshot.school),"counts":supplied.counts.duplicate(true),"ai":int(supplied.get("ai",0)),"treasures":loadout.clean_treasures(supplied.get("treasures",{})),"disabled_item_cards":loadout.clean_disabled_item_cards(supplied.get("disabled_item_cards",[])),"progression_snapshot":snapshot.duplicate(true)}
	# Old clients do not understand redacted observer snapshots; keep them unchanged.
	observer_protocols[peer]=int(data.get("observer_protocol",0))==1
	if connection_bindings.has(peer):progression.call_account("disconnect",{"connection_id":connection_bindings[peer]})
	connection_bindings[peer]=binding
	orchard_authority.bind_peer(peer,data)
	net.set_verified_character(peer,snapshot,str(result.get("name","冒险者")))
	net.publish({"op":"progression","snapshot":snapshot,"authenticated":true},peer)
	for room in rooms.values():
		if not orchard_authority.same_world(peer,int(room.descriptor.get("site",-1))):continue
		if room.try_rejoin(peer,str(snapshot.character_id)):
			print("ROOM_REJOIN id=",room.encounter," peer=",peer," character=",snapshot.character_id)
			break

func _bootstrap(peer: int,data: Dictionary) -> void:
	var correlation:=str(data.get("correlation",""))
	if correlation.is_empty() or correlation.length()>80:return
	if int(data.get("protocol_version",0))!=2 or not progression.available:
		net.publish({"op":"bootstrap_result","correlation":correlation,"ok":false,"code":"client_upgrade_required" if int(data.get("protocol_version",0))!=2 else "service_unavailable"},peer);return
	var generation:=Crypto.new().generate_random_bytes(12).hex_encode()
	authentication_pending[peer]=generation
	var result: Dictionary=await progression.call_account("bootstrap",{"token":str(data.get("token","")),"character_id":str(data.get("character_id",""))})
	if bool(result.get("ok", false)):await orchard_authority.migrate_legacy_accounts()
	if str(authentication_pending.get(peer,""))!=generation:return
	authentication_pending.erase(peer)
	if bool(result.get("ok", false)) and result.get("snapshot") is Dictionary:
		result.snapshot["orchard_journey"] = orchard_authority.state_for_identity(result.snapshot)
	result.op="bootstrap_result";result.correlation=correlation;net.publish(result,peer)

func _economy(peer: int,data: Dictionary) -> void:
	var correlation:=str(data.get("correlation",""))
	var action:=str(data.get("action",""))
	if correlation.is_empty() or correlation.length()>80 or action not in ["progression","exchange","shop-buy","equip-stat","appearance","equip-wing"] or not data.get("payload",{}) is Dictionary:return
	economy_pending[peer]=correlation
	# A profile refresh rotates the binding. Finish it before starting an economic
	# request; subsequent refreshes are deferred until this reply has been sent.
	while authentication_pending.has(peer) and profiles.has(peer):await get_tree().create_timer(.02).timeout
	if not profiles.has(peer) or str(economy_pending.get(peer,""))!=correlation:return
	var binding:=str(connection_bindings.get(peer,""))
	if binding.is_empty():economy_pending.erase(peer);return
	var result: Dictionary=await progression.call_account("player",{"connection_id":binding,"action":action,"payload":data.get("payload",{})})
	if str(connection_bindings.get(peer,""))!=binding or str(economy_pending.get(peer,""))!=correlation:return
	economy_pending.erase(peer)
	result.op="economy_result";result.correlation=correlation;net.publish(result,peer)
	if result.ok:_refresh_account(str(profiles[peer].progression_snapshot.account_id))
	elif str(result.code)=="unauthorized":net._peer_disconnected(peer)
	if deferred_profiles.has(peer) and profiles.has(peer):
		var deferred: Dictionary=deferred_profiles[peer];deferred_profiles.erase(peer)
		_authenticate_profile(peer,deferred)

func _refresh_account(account_id: String) -> void:
	for peer in profiles.keys():
		if not profiles.has(peer) or str(profiles[peer].progression_snapshot.account_id)!=account_id:continue
		var cid:=str(profiles[peer].progression_snapshot.character_id)
		var binding:=str(connection_bindings.get(peer,""))
		var result: Dictionary=await progression.call_account("snapshot",{"character_id":cid})
		if not result.ok or not profiles.has(peer) or str(connection_bindings.get(peer,""))!=binding:continue
		profiles[peer].progression_snapshot=result.snapshot
		net.set_verified_character(int(peer),result.snapshot)
		net.publish({"op":"progression","snapshot":result.snapshot},int(peer))

func prepare_profile(peer: int,battle_id: String,site: Dictionary) -> Dictionary:
	if not profiles.has(peer):return {"ok":false,"code":"unauthorized"}
	var original: Dictionary=profiles[peer].duplicate(true)
	var body:={"battle_id":battle_id,"character_id":str(original.progression_snapshot.character_id),"site_id":str(site.id),"pvp":bool(site.get("pvp",false)),"boss":bool(site.get("boss",false)),"cards":original.treasures,"connection_id":str(connection_bindings.get(peer,""))}
	var result: Dictionary=await progression.call_account("reserve",body)
	# An uncertain reserve must resolve using the same key, never release by timeout.
	while not result.ok and str(result.code)=="service_unavailable" and not progression.stopped:
		net.publish({"op":"server_error","code":"service_unavailable","message":"账号服务暂不可用，入场正在安全重试。"},peer)
		await get_tree().create_timer(3).timeout
		result=await progression.call_account("reserve",body)
	if not result.ok:
		if str(result.code)=="unauthorized" and str(connection_bindings.get(peer,""))==str(body.connection_id):
			net.publish({"op":"server_error","code":"unauthorized","message":"登录已过期，请重新登录。"},peer)
			net._peer_disconnected(peer)
		return result
	var profile: Dictionary={"school":str(result.snapshot.school),"counts":original.counts,"ai":original.ai,"treasures":result.treasures,"treasure_tokens":result.treasure_tokens,"disabled_item_cards":loadout.clean_disabled_item_cards(original.get("disabled_item_cards",[])),"progression_snapshot":result.snapshot}
	if profiles.has(peer) and str(connection_bindings.get(peer,""))==str(body.connection_id):
		profiles[peer].progression_snapshot=result.snapshot
		net.set_verified_character(peer,result.snapshot)
		net.publish({"op":"progression","snapshot":result.snapshot},peer)
	return {"ok":true,"profile":profile,"reward_version":result.reward_version}

func _progression_committed(result: Dictionary) -> void:
	var changed_accounts: Dictionary={}
	var snapshots: Dictionary=result.get("snapshots",{})
	if result.get("snapshot") is Dictionary:snapshots[str(result.snapshot.character_id)]=result.snapshot
	for peer in profiles:
		var cid:=str(profiles[peer].progression_snapshot.character_id)
		if not snapshots.has(cid):continue
		profiles[peer].progression_snapshot=snapshots[cid].duplicate(true)
		changed_accounts[str(snapshots[cid].account_id)]=true
		net.set_verified_character(peer,snapshots[cid])
		var message:Dictionary={"op":"progression","snapshot":snapshots[cid],"reward":result.get("rewards",{}).has(cid)}
		var rewards:Dictionary=result.get("rewards",{})
		if not str(result.get("battle_id","")).is_empty() and rewards.get(cid) is Dictionary:
			message["reward_receipt"]={"battle_id":str(result.battle_id),"character_id":cid,"rewards":rewards[cid].duplicate(true)}
		net.publish(message,int(peer))
	for account_id in changed_accounts:_refresh_account(str(account_id))

func _publish_to(peers: Array,data: Dictionary) -> void:
	for peer in peers:net.publish(data,int(peer))

func _cancel_pvp_wait() -> void:
	if pvp_lobby.site_index<0:return
	var index:=pvp_lobby.site_index
	var waiting: Array=pvp_lobby.teams.keys()
	for peer in waiting:
		net.position_frozen.erase(peer)
		if net.positions.has(peer):net.positions[peer]=Geo.point(sites[index].approach);net.last_seen[peer]=Time.get_ticks_msec()
	begin_site_cooldown(index)
	_publish_to(waiting,{"op":"pvp_wait_end","site":index})
	pvp_lobby.clear()
