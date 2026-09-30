extends Node
## Host-authoritative LAN transport: presence, appearance and shared encounter messages.
# Six dyeable silhouettes, both genders and all seven profiles need about 13 KB.
# Keep the incoming appearance bounded while allowing all saved color records.
const MAX_APPEARANCE_BYTES:=16384
const POSITION_INTERVAL:=0.1
const POSITION_INTEREST_METRES:=120.0
signal request_received(peer_id: int, message: Dictionary)
signal battle_received(message: Dictionary)
signal peer_left(peer_id: int)
var dedicated := false
var cloud_required:=false
var lan_debug:=false
var authenticated:=false
var connection_generation:=0
var owned_peer: ENetMultiplayerPeer
var bootstrap_only:=false
func debug_allowed() -> bool:
	var accounts:=get_node_or_null("/root/Accounts")
	return accounts!=null and accounts.is_verified_admin()
var normalize_rpc_root := false
var position_frozen: Dictionary = {}
var position_limit:=500.0
var speed_limit:=14.0
var max_clients:=16
var appearances: Dictionary={}
var local_appearance: Dictionary={}
var hidden_checks: Dictionary={}
var hidden_pending: Dictionary={}
var local_yaw:=0.0
var rotations: Dictionary={}
var profile_hash:=0
var profile_timer:=0.0
var position_snapshot_hashes: Dictionary={}
var wing_ids: Dictionary={}
var verified_characters: Dictionary={}
signal state_changed(message: String)
var positions: Dictionary = {}
var accumulated := 0.0
var local_position := Vector3.ZERO
var position_updates_paused:=false
var last_position_sent_msec:=0
var last_sent_position:=Vector3.ZERO
var last_sent_yaw:=0.0
var received_snapshots := 0
var connected := false
var connecting := false
var connect_started_msec:=0
var connect_timeout_msec:=12000
var last_seen: Dictionary = {}
func _ready() -> void:
	if normalize_rpc_root:multiplayer.root_path=get_parent().get_path()
	var mount_values: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/wing_mounts.json"))
	if mount_values is Array:
		for mount in mount_values:wing_ids[str(mount.get("id",""))]=true
	multiplayer.peer_connected.connect(_peer_connected)
	multiplayer.peer_disconnected.connect(_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connecting=false; connected=true; connect_started_msec=0; state_changed.emit("已加入房间"))
	multiplayer.connection_failed.connect(func(): disconnect_town(); state_changed.emit("未连到服务器"))
	multiplayer.server_disconnected.connect(func(): disconnect_town(); state_changed.emit("城镇服务器断开"))
func host(port: int = 29710,bind_ip: String = "*") -> Error:
	if cloud_required and not dedicated and (not lan_debug or not debug_allowed()):return ERR_UNAUTHORIZED
	if connected or connecting: return ERR_ALREADY_IN_USE
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(bind_ip)
	if normalize_rpc_root:multiplayer.server_relay=false
	var error := peer.create_server(port,max_clients)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	owned_peer=peer
	connected = true
	state_changed.emit("城镇已开放 · UDP %d" % port)
	return OK
func join(address: String, port: int = 29710) -> Error:
	if cloud_required and lan_debug and not debug_allowed():return ERR_UNAUTHORIZED
	if cloud_required and not lan_debug:
		var allowed:=address=="101.43.174.221" and port==29710
		if "--weekend-local-services" in OS.get_cmdline_user_args() and address=="127.0.0.1:29760":allowed=true
		if not allowed:return ERR_UNAUTHORIZED
	if connected or connecting: return ERR_ALREADY_IN_USE
	address=address.strip_edges()
	if address.count(":")==1:
		var port_text:=address.get_slice(":",1)
		if not port_text.is_valid_int():return ERR_INVALID_PARAMETER
		port=int(port_text);address=address.get_slice(":",0)
	if address.is_empty() or port<1 or port>65535:return ERR_INVALID_PARAMETER
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address,port)
	if error != OK: return error
	multiplayer.multiplayer_peer = peer
	owned_peer=peer
	connecting = true
	connect_started_msec=Time.get_ticks_msec()
	state_changed.emit("连接中…")
	return OK
func disconnect_town() -> void:
	connection_generation+=1
	authenticated=false
	connected = false
	connecting = false
	connect_started_msec=0
	positions.clear()
	position_frozen.clear()
	last_seen.clear()
	appearances.clear()
	verified_characters.clear()
	hidden_pending.clear()
	rotations.clear()
	position_snapshot_hashes.clear()
	profile_hash=0
	position_updates_paused=false;last_position_sent_msec=0
	peer_left.emit(0)
	if owned_peer!=null:
		owned_peer.close()
		if multiplayer.multiplayer_peer==owned_peer:multiplayer.multiplayer_peer=OfflineMultiplayerPeer.new()
		owned_peer=null
func _exit_tree() -> void:
	if owned_peer!=null:owned_peer.close();owned_peer=null
func _process(delta: float) -> void:
	if connecting:
		if connect_started_msec>0 and Time.get_ticks_msec()-connect_started_msec>=connect_timeout_msec:
			disconnect_town();state_changed.emit("未连到服务器")
		return
	if not connected: return
	if bootstrap_only:return
	profile_timer+=delta
	if profile_timer>0.5:
		profile_timer=0
		if multiplayer.is_server():
			if not dedicated:
				var local_copy:=local_appearance.duplicate(true)
				var wardrobe=get_node("/root/Wardrobe")
				for theme in local_copy.get("outfits",{}):local_copy.outfits[theme]=wardrobe.sanitize_restricted(local_copy.outfits[theme],wardrobe.can_use_hidden_character())
				local_copy.name=clean_player_name(local_copy.get("name","冒险者"))
				if appearances.get(1,{})!=local_copy:
					appearances[1]=local_copy
					_broadcast_appearance(1,local_copy)
		elif hash(local_appearance)!=profile_hash:
			profile_hash=hash(local_appearance)
			var payload=local_appearance.duplicate(true)
			var accounts=get_node_or_null("/root/Accounts")
			if not normalize_rpc_root and has_hidden_character(payload) and accounts!=null:payload["hidden_auth_token"]=str(accounts.token)
			submit_appearance.rpc_id(1,payload)
	accumulated += delta
	if accumulated < POSITION_INTERVAL:return
	accumulated = 0
	if multiplayer.is_server():
		if not dedicated:
			positions[1] = local_position
			rotations[1]=local_yaw
		for peer in _recipients():_publish_positions(peer)
	else:
		if position_updates_paused:return
		var sent_at:=Time.get_ticks_msec()
		if last_position_sent_msec>0 and sent_at-last_position_sent_msec<1000 and local_position.distance_squared_to(last_sent_position)<0.0001 and absf(angle_difference(local_yaw,last_sent_yaw))<0.001:return
		submit_position.rpc_id(1,local_position,local_yaw)
		last_sent_position=local_position;last_sent_yaw=local_yaw;last_position_sent_msec=sent_at
@rpc("any_peer", "call_remote", "unreliable_ordered", 0)
func submit_position(value: Vector3,yaw: float=0.0) -> void:
	if dedicated and not verified_characters.has(multiplayer.get_remote_sender_id()):return
	if not multiplayer.is_server() or not value.is_finite() or absf(value.x) > position_limit or absf(value.z) > position_limit or absf(value.y) > position_limit or not is_finite(yaw): return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1 or position_frozen.has(id): return
	var now := Time.get_ticks_msec()
	if positions.has(id):
		# Forced server teleports must reset last_seen to their timestamp. Erasing it
		# leaves the retry allowance at 0.6 m forever until a position is accepted.
		var allowed := speed_limit*float(now-int(last_seen.get(id,now)))/1000.0+0.6
		if (positions[id] as Vector3).distance_to(value) > allowed: return
	positions[id] = value
	last_seen[id] = now
	rotations[id]=yaw
@rpc("authority", "call_remote", "unreliable_ordered", 0)
func receive_positions(value: Dictionary,angles: Dictionary={}) -> void:
	positions = value
	rotations=angles
	received_snapshots += 1

@rpc("any_peer","call_remote","reliable",1)
func submit_appearance(value: Dictionary) -> void:
	if not multiplayer.is_server() or var_to_bytes(value).size()>MAX_APPEARANCE_BYTES:return
	var sender:=multiplayer.get_remote_sender_id()
	if dedicated:
		accept_verified_appearance(sender,value)
		return
	if has_hidden_character(value):
		hidden_pending[sender]=value.duplicate(true)
		if hidden_checks.has(sender):return
		hidden_checks[sender]=true
		var token:=str(value.get("hidden_auth_token",""))
		var allowed:=await verify_hidden_account(token)
		hidden_checks.erase(sender)
		if not hidden_pending.has(sender):return
		var latest:Dictionary=hidden_pending[sender]
		hidden_pending.erase(sender)
		if not connected or not multiplayer.is_server() or sender not in multiplayer.get_peers():return
		accept_appearance(sender,latest,allowed and str(latest.get("hidden_auth_token",""))==token)
	else:
		hidden_pending.erase(sender)
		accept_appearance(sender,value,false)
func has_hidden_character(value:Dictionary) -> bool:
	var outfits:Variant=value.get("outfits",{})
	if not outfits is Dictionary:return false
	for outfit in outfits.values():
		if outfit is Dictionary and str(outfit.get("teen_clothes",""))=="hidden_anime_catgirl":return true
	return false
func verify_hidden_account(token:String) -> bool:
	if token.is_empty() or token.length()>512 or "\n" in token or "\r" in token:return false
	var request:=HTTPRequest.new();request.timeout=8;request.body_size_limit=8192;add_child(request)
	# Trusted server-side endpoint; never accept an account name or URL from the peer.
	var url:=OS.get_environment("ACCOUNT_SERVER_URL")
	if url.is_empty():url="http://101.43.174.221:8787"
	var error:=request.request(url.trim_suffix("/")+"/v1/me",PackedStringArray(["Authorization: Bearer "+token]))
	if error!=OK:request.queue_free();return false
	var response:Array=await request.request_completed
	request.queue_free()
	if int(response[0])!=HTTPRequest.RESULT_SUCCESS or int(response[1])!=200:return false
	var data:Variant=JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
	return data is Dictionary and data.get("account") is Dictionary and str(data.account.get("username","")).to_lower()=="admin"
func accept_appearance(sender:int,value:Dictionary,hidden_allowed:bool) -> void:
	var store:=get_node("/root/Wardrobe")
	var school:=str(value.get("school","fire"))
	if not store.valid_theme(school):return
	var clean: Dictionary={"school":school,"outfits":{},"name":clean_player_name(value.get("name","冒险者"))}
	var wing_id:=str(value.get("wings",""))
	clean.wings=""
	if wing_ids.has(wing_id):clean.wings=wing_id
	clean.flying=value.get("flying",false)==true
	clean.flapping=value.get("flapping",false)==true
	clean.swimming=value.get("swimming",false)==true
	for theme in store.catalog.themes:
		var outfit: Dictionary=store.default_outfit(str(theme.id))
		var supplied: Variant=value.get("outfits",{}).get(str(theme.id),{})
		if supplied is Dictionary:
			for slot in outfit:
				if slot in ["teen_dyes","teen_hair_color"]:continue
				var choice:=str(supplied.get(slot,outfit[slot]))
				if slot=="model_style":
					if choice in ["modular","teen"] or (choice=="custom" and store.catalog.get("custom_models",{}).has(str(theme.id))):outfit[slot]=choice
				elif not store.option(slot,choice).is_empty():outfit[slot]=choice
			outfit.teen_dyes=store.clean_dyes(supplied.get("teen_dyes",{}))
			outfit.teen_hair_color=store.clean_hair_color(supplied.get("teen_hair_color",""))
			# Retain one-time fit migrations so remote manual silhouettes do not reset.
			for key in ["teen_clothing_fit_revision","teen_equipment_fit_revision","teen_special_fit_revision","teen_costume_fit_revision","teen_recovered_fit_revision","teen_alpha_fit_revision","teen_high_school_fit_revision","teen_requested_fit_revision","teen_boot_review_fit_revision","teen_attachment_fit_revision","teen_level40_fit_revision"]:
				var revision: Variant=supplied.get(key,0)
				var supported: Array=[0,1,2] if key=="teen_level40_fit_revision" else [0,1]
				outfit[key]=int(revision) if typeof(revision) in [TYPE_INT,TYPE_FLOAT] and revision in supported else 0
			if outfit.model_style=="teen":outfit=store.clean_teen(outfit)
		clean.outfits[str(theme.id)]=store.sanitize_restricted(outfit,hidden_allowed)
	if appearances.get(sender,{})==clean:return
	appearances[sender]=clean
	_broadcast_appearance(sender,clean)

func set_verified_character(peer: int,snapshot: Dictionary,player_name: String="") -> void:
	var first_login:=not verified_characters.has(peer)
	var previous: Dictionary=verified_characters.get(peer,{})
	verified_characters[peer]={"snapshot":snapshot.duplicate(true),"name":player_name if not player_name.is_empty() else str(previous.get("name","冒险者"))}
	accept_verified_appearance(peer,appearances.get(peer,{}))
	if first_login and connected and multiplayer.is_server() and peer in multiplayer.get_peers():
		receive_appearances.rpc_id(peer,appearances)

func accept_verified_appearance(peer: int,value: Dictionary) -> void:
	if not verified_characters.has(peer):return
	var identity: Dictionary=verified_characters[peer]
	var snapshot: Dictionary=identity.snapshot
	var school:=str(snapshot.school)
	var wing:=str(snapshot.get("equipped_wing",""))
	if wing not in snapshot.get("wing_unlocks",[]) or not wing_ids.has(wing):wing=""
	var clean: Dictionary={"school":school,"name":clean_player_name(identity.name),"outfits":{school:snapshot.appearance.duplicate(true)},"wings":wing,"flying":not wing.is_empty() and value.get("flying",false)==true,"flapping":not wing.is_empty() and value.get("flapping",false)==true,"swimming":value.get("swimming",false)==true}
	if appearances.get(peer,{})==clean:return
	appearances[peer]=clean;_broadcast_appearance(peer,clean)
@rpc("authority","call_remote","reliable",1)
func receive_appearances(value: Dictionary) -> void:appearances=value
@rpc("authority","call_remote","reliable",1)
func receive_appearance_update(peer: int,value: Dictionary) -> void:
	if value.is_empty():appearances.erase(peer)
	else:appearances[peer]=value
func send_request(value: Dictionary) -> void:
	if not connected:return
	if multiplayer.is_server():request_received.emit(1,value)
	else:submit_request.rpc_id(1,value)
func send_chat(text: String) -> void:
	if not connected:return
	if multiplayer.is_server():request_received.emit(1,{"op":"chat","text":text})
	else:submit_chat.rpc_id(1,text)
@rpc("any_peer","call_remote","reliable",0)
func submit_chat(text: String) -> void:
	if multiplayer.is_server() and text.length()<=160:
		request_received.emit(multiplayer.get_remote_sender_id(),{"op":"chat","text":text})
@rpc("any_peer","call_remote","reliable",2)
func submit_request(value: Dictionary) -> void:
	if multiplayer.is_server() and var_to_bytes(value).size()<16000:
		request_received.emit(multiplayer.get_remote_sender_id(),value)
func publish(value: Dictionary,peer: int=0) -> void:
	if not connected or not multiplayer.is_server():return
	var is_chat:=str(value.get("op",""))=="chat"
	if peer>1:
		# SceneMultiplayer can retain an ID while ENet is already closing it.
		if peer in multiplayer.get_peers():
			var remote := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(peer)
			if remote!=null and remote.get_state()==ENetPacketPeer.STATE_CONNECTED:
				if is_chat:receive_chat.rpc_id(peer,value)
				else:receive_battle.rpc_id(peer,value)
	else:
		for recipient in _recipients():
			if is_chat:receive_chat.rpc_id(recipient,value)
			else:receive_battle.rpc_id(recipient,value)
@rpc("authority","call_remote","reliable",0)
func receive_chat(value: Dictionary) -> void:battle_received.emit(value)
@rpc("authority","call_remote","reliable",2)
func receive_battle(value: Dictionary) -> void:battle_received.emit(value)

func clean_player_name(value: Variant) -> String:
	var source:=str(value).strip_edges()
	var result:=""
	for index in source.length():
		var code:=source.unicode_at(index)
		if code>=32 and code!=127:result+=source.substr(index,1)
		if result.length()>=20:break
	return result if not result.is_empty() else "冒险者"

func clean_chat_text(value: Variant) -> String:
	var source:=str(value).replace("\r"," ").replace("\n"," ").replace("\t"," ").strip_edges()
	var result:=""
	var previous_space:=false
	for index in source.length():
		var code:=source.unicode_at(index)
		if code<32 or code==127:continue
		var character:=source.substr(index,1)
		if character==" ":
			if previous_space:continue
			previous_space=true
		else:previous_space=false
		result+=character
		if result.length()>=160:break
	return result.strip_edges()


func _recipients() -> Array[int]:
	var result: Array[int]=[]
	if not connected or not multiplayer.is_server():return result
	for id in multiplayer.get_peers():
		if dedicated and not verified_characters.has(id):continue
		var peer := (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id)
		if peer!=null and peer.get_state()==ENetPacketPeer.STATE_CONNECTED:result.append(id)
	return result

func _peer_connected(id: int) -> void:
	if multiplayer.is_server() and not dedicated:receive_appearances.rpc_id(id,appearances)

func _peer_disconnected(id: int) -> void:
	verified_characters.erase(id)
	hidden_pending.erase(id)
	positions.erase(id);last_seen.erase(id);rotations.erase(id);position_frozen.erase(id)
	position_snapshot_hashes.erase(id)
	var removed:=appearances.has(id)
	appearances.erase(id)
	if removed and multiplayer.is_server():_broadcast_appearance(id,{})
	peer_left.emit(id)

func _broadcast_appearance(peer_id: int,value: Dictionary) -> void:
	if not connected or not multiplayer.is_server():return
	for recipient in _recipients():receive_appearance_update.rpc_id(recipient,peer_id,value)

func _publish_positions(recipient: int) -> void:
	if not positions.has(recipient):return
	var center: Vector3=positions[recipient]
	var nearby_positions: Dictionary={}
	var nearby_rotations: Dictionary={}
	for peer in positions:
		var offset: Vector3=positions[peer]-center
		if Vector2(offset.x,offset.z).length()>POSITION_INTEREST_METRES:continue
		nearby_positions[peer]=positions[peer]
		nearby_rotations[peer]=rotations.get(peer,0.0)
	var snapshot_hash:=hash([nearby_positions,nearby_rotations])
	if int(position_snapshot_hashes.get(recipient,0))==snapshot_hash:return
	position_snapshot_hashes[recipient]=snapshot_hash
	receive_positions.rpc_id(recipient,nearby_positions,nearby_rotations)
