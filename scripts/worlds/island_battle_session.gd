extends Node
signal presentations_finished
const Wire=preload("res://scripts/fusion_3d/battle_wire.gd")
var manager: Node
var net: Node
var stage: Node3D
var owners: Dictionary={}
var members: Array[int]=[]
var descriptor: Dictionary={}
var observer_state: Dictionary={}
var profiles: Dictionary={}
var test_ai_counts: Dictionary={}
var remotes: Dictionary={}
var remote_looks: Dictionary={}
var loaded: Dictionary={}
var arrived: Dictionary={}
var messages: Array[Dictionary]=[]
var sequence:=0
var encounter:=0
var active_local:=false
var encounter_busy:=false
var gathering:=false
var battle_ready:=false
var waiting_round:=-1
var presented: Dictionary={}
var presentation_grace_until:=0
var consuming:=false
var ready_deadline:=0
var announced:=false
var profile_sending:=false
var clock_offset:=0.0
var clock_tick:=0.0
var status_layer: CanvasLayer
var status_text: Label
var warm_stage: Node3D
var retiring_stages: Array[Node3D]=[]
var entering_stages: Array[Node3D]=[]
var prewarming:=false
var pending_join: Dictionary={}
var join_figures: Dictionary={}
var join_pauses_planning:=false
var join_tick:=0.0
const Pvp=preload("res://scripts/server/pvp_encounter.gd")
const PRESENTATION_LAG_GRACE_MS:=2000
const PLANNING_LAST_PEER_MS:=8000
var pvp_lobby:=Pvp.new()
var pvp_waiting:=false
var pvp_wait_deadline:=0
var pvp_wait_team:=0
var pvp_wait_positions: Dictionary={}
var pvp_wait_targets: Dictionary={}
var pvp_visual_origins: Dictionary={}
var pvp_wait_center:=Vector3.ZERO
var pvp_announced_count:=0

func planning_blocked() -> bool:return join_pauses_planning

func prewarm() -> void:
	if GraphicsSettings.is_low():return
	if manager.site_entries.is_empty():return
	prewarming=true
	descriptor={"loadouts":[manager.atlas.loadout.profile()]}
	warm_stage=load("res://scenes/fusion_3d/battle_stage.tscn").instantiate()
	warm_stage.shared_session=self;warm_stage.embedded=true;warm_stage.manual_entrance=true
	warm_stage.party.assign([StringName(manager.atlas.loadout.character())])
	warm_stage.encounter_id=str(manager.site_entries[0].config.encounter)
	warm_stage.encounter_spec={"enemies":manager.site_entries[0].config.enemies.duplicate(true)}
	warm_stage.position=manager.battle_origin(manager.site_entries[0].config);warm_stage.scale=Vector3.ONE*float(manager.site_entries[0].config.scale)
	manager.world.add_child(warm_stage)
	warm_stage.shell.set_music_paused(true)
	# Render the actual board/actors under the loading cover to compile their first-use pipelines.
	warm_stage.camera.current=true
	warm_stage.arena_surface.set_arrival_progress(0.4)
	for frame in 3:await get_tree().process_frame
	warm_stage.arena_surface.set_arrival_progress(1.0)
	for frame in 2:await get_tree().process_frame
	manager.world.camera.current=true;warm_stage.hide();warm_stage.set_process(false);warm_stage.shell.set_process(false)
	descriptor={}
	prewarming=false

func _ready() -> void:
	net=preload("res://scripts/fusion_3d/town_network.gd").new()
	net.cloud_required=true
	net.normalize_rpc_root=true
	net.name="Transport";net.position_limit=10000.0;net.speed_limit=160.0;net.max_clients=3
	add_child(net)
	net.request_received.connect(_request);net.battle_received.connect(_receive);net.peer_left.connect(_transport_left)
	var accounts:=get_node_or_null("/root/Accounts")
	if accounts!=null:accounts.game_transport=net;accounts.progression_changed.connect(_progression_updated)
	net.state_changed.connect(func(text: String):
		if is_instance_valid(manager.atlas.game_menu):
			manager.atlas.game_menu.message.text=text
			manager.atlas.game_menu.message.modulate=Color("f06c6c") if text=="未连到服务器" else Color.WHITE)
	status_layer=CanvasLayer.new();status_layer.layer=40;add_child(status_layer)
	status_text=Label.new();status_text.position=Vector2(450,100);status_text.add_theme_font_size_override("font_size",24);status_layer.add_child(status_text);status_layer.hide()

func authority() -> bool:
	if net.cloud_required and not (net.lan_debug and net.debug_allowed()):return false
	return (not net.connected and not net.connecting) or (net.connected and multiplayer.is_server())
func local_id() -> int:return multiplayer.get_unique_id() if net.connected else 1
func mine(id: StringName) -> bool:return active_local and int(owners.get(str(id),0))==local_id()
func world_seconds() -> float:return Time.get_ticks_msec()/1000.0+clock_offset
func player_positions() -> Dictionary:
	var result: Dictionary=net.positions.duplicate() if net.connected else {}
	if is_instance_valid(manager.world) and manager.world.ready_world:result[local_id()]=manager.world.player.position
	return result
func send_profile() -> void:
	if not is_instance_valid(manager.atlas.loadout):return
	if not net.connected and not authority():return
	var data: Dictionary={"op":"profile","profile":manager.atlas.loadout.profile()}
	if authority():_request(local_id(),data)
	else:
		if profile_sending:return
		profile_sending=true
		var accounts:=get_node_or_null("/root/Accounts")
		profile_sending=false
		if accounts==null or accounts.token.is_empty() or accounts.active_character.is_empty():return
		if not net.lan_debug:
			data.profile.erase("progression_snapshot");data.profile.erase("equipment")
		data.protocol_version=2;data.battle_wire_version=3;data.observer_protocol=1;data.token=accounts.token;data.character_id=str(accounts.active_character.id);net.send_request(data)

func _exit_tree() -> void:
	var accounts:=get_node_or_null("/root/Accounts")
	if accounts!=null and accounts.game_transport==net:accounts.game_transport=null
	# A scene can leave before an interrupted presentation returns. Release its
	# captured card/events and callbacks before the scene destroys the nodes.
	for old_stage in retiring_stages:
		if is_instance_valid(old_stage):_clear_stage_references(old_stage);old_stage.queue_free()
	retiring_stages.clear();entering_stages.clear();messages.clear();observer_state.clear()

func _progression_updated(_snapshot: Dictionary) -> void:
	if net!=null and net.connected and not authority() and not active_local and not profile_sending:send_profile()
func _send(data: Dictionary) -> void:
	if authority():_request(local_id(),data)
	else:net.send_request(data)

func _process(delta: float) -> void:
	if not is_instance_valid(manager.world) or not manager.world.ready_world:return
	net.local_position=manager.world.player.position
	net.local_yaw=manager.world.avatar.rotation.y
	net.position_updates_paused=active_local
	net.local_appearance={"school":manager.atlas.current_school,"name":str(get_node("/root/Accounts").active_character.get("name","冒险者")),"outfits":get_node("/root/Wardrobe").outfits.duplicate(true)}
	if "flight" in manager.world and is_instance_valid(manager.world.flight):
		net.local_appearance.merge({"wings":manager.world.flight.equipped_id,"flying":manager.world.flight.flying,"flapping":manager.world.flight.flap_time>0,"swimming":manager.world.swimming})
	if net.connected and not announced:
		announced=true;send_profile();_send({"op":"hello"})
	if not net.connected:announced=false
	clock_tick+=delta
	if authority() and clock_tick>2.0:
		clock_tick=0;net.publish({"op":"clock","seconds":world_seconds()})
	if authority() and waiting_round>=0 and (Time.get_ticks_msec()>ready_deadline or (presentation_grace_until>0 and Time.get_ticks_msec()>=presentation_grace_until)):
		waiting_round=-1;presentation_grace_until=0;presentations_finished.emit()
	elif authority() and encounter_busy and not battle_ready and Time.get_ticks_msec()>ready_deadline:
		finish(-1)
		manager.atlas.game_menu.message.text="队伍加载超时，本次集结已取消；请检查队友连接后重试。"
	if authority() and pvp_lobby.site_index>=0:_poll_pvp()
	if pvp_waiting:status_text.text=("红方" if pvp_wait_team==0 else "蓝方")+"已入阵 · 等待对手 %d 秒" % maxi(0,ceili((pvp_wait_deadline-Time.get_ticks_msec())/1000.0))
	_update_remotes(delta)
	_advance_pvp_wait(delta)
	join_tick+=delta
	if authority() and encounter_busy and battle_ready and join_tick>0.2:
		join_tick=0;_scan_late_players()
	if authority() and not pending_join.is_empty() and Time.get_ticks_msec()>int(pending_join.deadline):
		# Release a stalled admission without aborting the existing team's battle.
		net.publish({"op":"join_cancel","encounter":encounter});_cancel_join()

func _update_remotes(delta: float) -> void:
	for peer in remotes.keys():
		if not net.connected or not net.positions.has(peer):
			remotes[peer].queue_free();remotes.erase(peer);remote_looks.erase(peer)
	if not net.connected:return
	for peer in net.positions:
		if int(peer)==local_id():continue
		if not remotes.has(peer):
			var body: Node3D=load("res://scenes/characters/modular_wizard.tscn").instantiate()
			manager.world.add_child(body);body.scale=Vector3.ONE*manager.world.explorer_scale
			body.follow_local_wardrobe=false;body.position=net.positions[peer];remotes[peer]=body
			var nameplate:=Label3D.new()
			nameplate.name="ExplorationPlayerName"
			nameplate.set_script(preload("res://scripts/worlds/remote_world_name.gd"))
			body.add_child(nameplate)
		var avatar: Node3D=remotes[peer]
		avatar.visible=not (encounter_busy and (members.has(int(peer)) or int(pending_join.get("peer",-1))==int(peer)))
		var profile: Dictionary=net.appearances.get(peer,{"school":"life","outfits":{}})
		if int(remote_looks.get(peer,0))!=hash(profile):
			if avatar.school_id!=str(profile.school):avatar.configure(Color.WHITE,str(profile.school),false)
			var outfit: Dictionary=profile.get("outfits",{}).get(str(profile.school),get_node("/root/Wardrobe").default_outfit(str(profile.school)))
			if avatar.equipped!=outfit:avatar.apply_outfit(outfit)
			var wings=preload("res://scripts/worlds/replicated_wings.gd").attach(avatar,profile)
			wings.motion(bool(profile.get("flying",false)),bool(profile.get("flapping",false)),bool(profile.get("swimming",false)))
			var nameplate:=avatar.get_node_or_null("ExplorationPlayerName")
			if nameplate!=null:nameplate.display_name=net.clean_player_name(profile.get("name","冒险者"))
			remote_looks[peer]=hash(profile)
		if pvp_wait_targets.has(peer):continue
		var target: Vector3=net.positions[peer]
		var speed: float=avatar.position.distance_to(target)/maxf(delta,0.001)
		avatar.position=avatar.position.lerp(target,minf(1.0,delta*12.0))
		avatar.rotation.y=lerp_angle(avatar.rotation.y,float(net.rotations.get(peer,0.0)),minf(1.0,delta*12.0))
		avatar.set_locomotion(false,0,minf(speed,8.0))

func start_contact(index: int,trigger_peer: int) -> void:
	if not authority() or encounter_busy or index<0 or index>=manager.site_entries.size():return
	if not profiles.has(trigger_peer) or not preload("res://scripts/worlds/island_ai_allies.gd").valid_request(profiles[trigger_peer].get("ai",0)):return
	if pvp_lobby.site_index>=0 and pvp_lobby.site_index!=index:return
	var positions:=player_positions()
	if not positions.has(trigger_peer) or not manager.touches(index,positions[trigger_peer]):return
	var config: Dictionary=manager.site_entries[index].config
	if bool(config.get("pvp",false)):
		pvp_lobby.scan(index,config,positions,profiles,Time.get_ticks_msec());_poll_pvp();return
	var center: Vector3=manager.point(config.center)
	members.clear();owners.clear()
	# Triggering player goes first; every other player in this zone joins once.
	members.append(trigger_peer)
	for peer in positions:
		var offset: Vector3=positions[peer]-center
		if int(peer)!=trigger_peer and Vector2(offset.x,offset.z).length()<=float(config.radius) and absf(offset.y)<8:members.append(int(peer))
	if members.size()>4:members.resize(4)
	var party: Array[StringName]=[]
	var loadouts: Array[Dictionary]=[]
	var origins: Dictionary={}
	for peer in members:
		var profile: Dictionary=profiles.get(peer,{})
		if profile.is_empty():members.clear();return # Await the validated school/deck handshake.
		var id: String="P"+str(party.size())
		owners[id]=peer;origins[id]=positions[peer]
		party.append(StringName(manager.atlas.loadout.character(str(profile.school))));loadouts.append(profile.duplicate(true))
	var test_override := int(test_ai_counts.get(trigger_peer,0))
	var helpers: int=preload("res://scripts/worlds/island_ai_allies.gd").available_count(profiles[trigger_peer].get("ai",0),party.size(),test_override)
	for index_ai in helpers:
		var helper: Dictionary=preload("res://scripts/worlds/island_ai_allies.gd").test_profile(manager.atlas.loadout.content,loadouts[0],index_ai) if test_override>0 else preload("res://scripts/worlds/island_ai_allies.gd").profile(manager.atlas.loadout.content,loadouts[0],index_ai)
		var school: String=helper.school
		var id: String="P"+str(party.size());owners[id]=0;origins[id]=center+Vector3(0,0,10+index_ai)
		party.append(StringName(manager.atlas.loadout.character(school)))
		loadouts.append(helper)
	for i in config.enemies.size():origins["E"+str(i)]=manager.grounded_roam_position(manager.world,config,i,world_seconds())
	encounter+=1;sequence=0;loaded.clear();arrived.clear();gathering=false;battle_ready=false
	descriptor={"id":encounter,"site":index,"enemies":config.enemies.duplicate(true),"party":party,"loadouts":loadouts,"origins":origins,"appearances":net.appearances.duplicate(true)}
	descriptor.appearances[local_id()]=net.local_appearance.duplicate(true)
	net.publish({"op":"open","descriptor":descriptor,"owners":owners,"members":members})
	_open()

func _request(peer: int,data: Dictionary) -> void:
	if not authority():return
	match str(data.get("op","")):
		"flee":
			if not members.has(peer) or int(data.get("encounter",-1))!=encounter or not battle_ready or not is_instance_valid(stage) or stage.engine.state.phase!=BattleStateV2.Phase.PLANNING:return
			if peer==local_id():_return_from_flee()
			else:net.publish({"op":"fled","encounter":encounter},peer)
			net.position_frozen.erase(peer)
			net.positions[peer]=manager.point(manager.site.approach);net.last_seen[peer]=Time.get_ticks_msec()
			_left(peer)
		"profile":
			if (encounter_busy and members.has(peer)) or pvp_lobby.teams.has(peer):return
			var clean: Dictionary=manager.atlas.loadout.clean_profile(data.get("profile"))
			if not clean.is_empty():profiles[peer]=clean
		"hello":
			net.publish({"op":"clock","seconds":world_seconds()},peer)
			if encounter_busy:net.publish({"op":"busy","site":int(descriptor.site)},peer)
		"chat":
			var chat_text: String=net.clean_chat_text(data.get("text",""))
			if chat_text.is_empty():return
			var test_result: Dictionary=preload("res://scripts/worlds/island_ai_allies.gd").apply_test_command(test_ai_counts,peer,chat_text,(encounter_busy and members.has(peer)) or pvp_lobby.teams.has(peer),profiles.has(peer))
			if not test_result.is_empty():
				var reply := {"op":"chat","peer":0,"name":"系统","text":str(test_result.message)}
				if peer==local_id():_receive(reply)
				else:net.publish(reply,peer)
				return
			var appearance: Dictionary=net.appearances.get(peer,net.local_appearance if peer==local_id() else {})
			var packet:={"op":"chat","peer":peer,"name":net.clean_player_name(appearance.get("name","冒险者")),"text":chat_text}
			net.publish(packet)
			if peer==local_id():_receive(packet)
		"loaded", "arrived":
			if not encounter_busy or int(data.get("encounter",-1))!=encounter or not members.has(peer):return
			if data.op=="loaded":loaded[peer]=true
			elif gathering:arrived[peer]=true
			_check_ready()
		"command":
			if battle_ready and is_instance_valid(stage) and int(data.get("encounter",-1))==encounter and stage.shell.accept_command(peer,data):_shorten_planning_for_last_peer()
		"presented":
			if int(data.get("encounter",-1))!=encounter or int(data.get("round",-2))!=waiting_round or not members.has(peer):return
			presented[peer]=true;_check_presented()
		"join_loaded":
			if pending_join.is_empty() or int(data.get("encounter",-1))!=encounter or int(data.get("joining",-1))!=int(pending_join.peer):return
			if peer!=int(pending_join.peer) and not members.has(peer):return
			pending_join.ready[peer]=true
			_try_admit_join()

func wait_for_presentations(round_number: int) -> void:
	battle_ready=false;waiting_round=round_number;presented.clear()
	presentation_grace_until=0
	ready_deadline=Time.get_ticks_msec()+90000
	stage.shell.prompt_label.text="等待所有队友播放完本轮动画…"
	if active_local:presented[local_id()]=true
	broadcast_step("round_end",{"round":round_number})
	_check_presented.call_deferred()
	await presentations_finished
	if is_instance_valid(stage):battle_ready=true
func presentation_complete(round_number: int) -> void:
	if active_local and (authority() or net.lan_debug):_send({"op":"presented","encounter":encounter,"round":round_number})
func _check_presented() -> void:
	if waiting_round<0:return
	for peer in members:
		if not presented.has(peer):
			if presented.size()>=members.size()-1 and not presented.is_empty() and presentation_grace_until==0:
				presentation_grace_until=Time.get_ticks_msec()+PRESENTATION_LAG_GRACE_MS
			return
	waiting_round=-1;presentation_grace_until=0;presentations_finished.emit()

func _shorten_planning_for_last_peer() -> void:
	if not is_instance_valid(stage) or stage.shell.resolving_network:return
	var ready:=0
	var pending:=0
	for unit in stage.engine.state.living_units(stage.engine.state.active_team if stage.engine.state.pvp else 0):
		if int(owners.get(str(unit.id),0))<=0:continue
		if stage.engine.state.actions.has(unit.id):ready+=1
		else:pending+=1
	if ready>0 and pending==1:
		stage.shell.planning_deadline=mini(stage.shell.planning_deadline,Time.get_ticks_msec()+PLANNING_LAST_PEER_MS)
		stage.shell.network_planning()

func _open(animate_arrival: bool=true) -> void:
	var entry_tick:=Time.get_ticks_usec()
	pvp_visual_origins.clear()
	if bool(descriptor.get("pvp",false)):
		for id in owners:
			var peer:=int(owners[id])
			if pvp_wait_positions.has(peer):pvp_visual_origins[id]=pvp_wait_positions[peer]
	_clear_pvp_walk()
	pvp_waiting=false
	encounter_busy=true;active_local=members.has(local_id());battle_ready=false;gathering=false
	ready_deadline=Time.get_ticks_msec()+90000
	var source_camera: Transform3D=manager.world.camera.global_transform.orthonormalized()
	var source_fov: float=manager.world.camera.fov
	manager.begin_local(int(descriptor.site),active_local)
	# Keep the explorer visible during peer loading; swap at the first arrival frame.
	if active_local and animate_arrival:manager.world.player.show()
	var config: Dictionary=manager.site_entries[int(descriptor.site)].config
	entry_tick=_entry_timing("begin_local",entry_tick)
	var reusable: bool=is_instance_valid(warm_stage)
	if reusable:
		stage=warm_stage;warm_stage=null
		stage.shell.prepare_battle_music(&"combat_frost")
		entry_tick=_entry_timing("prepare_music",entry_tick)
		var next_spec: Dictionary={} if bool(descriptor.get("pvp",false)) else {"enemies":descriptor.get("enemies",config.enemies).duplicate(true)}
		var changed_spec: bool=stage.encounter_spec!=next_spec
		stage.encounter_spec=next_spec
		stage.process_mode=Node.PROCESS_MODE_INHERIT
		stage.set_process(true);stage.shell.set_process(true)
		if changed_spec or stage.get_meta("has_entered",false) or stage.encounter_id!=str(config.encounter) or Array(stage.party)!=Array(descriptor.party):stage.reset_prepared_party(descriptor.party,str(config.encounter))
		else:configure_engine(stage.engine)
	else:stage=load("res://scenes/fusion_3d/battle_stage.tscn").instantiate()
	entry_tick=_entry_timing("reuse_reset" if reusable else "instantiate",entry_tick)
	stage.name="EncounterStage";stage.shared_session=self;stage.embedded=true;stage.manual_entrance=true
	stage.party.assign(descriptor.party);stage.encounter_id=str(config.encounter)
	stage.encounter_spec={} if bool(descriptor.get("pvp",false)) else {"enemies":descriptor.get("enemies",config.enemies).duplicate(true)}
	stage.battle_music_context = &"combat_frost"
	stage.battle_music_boss = bool(config.get("boss", false)) or str(config.get("encounter_role", "")) == "boss"
	stage.position=manager.battle_origin(config);stage.scale=Vector3.ONE*float(config.scale)
	if not reusable:manager.world.add_child(stage)
	entry_tick=_entry_timing("ready_tree",entry_tick)
	stage.shell.prepare_battle_music(&"combat_boss" if stage.battle_music_boss else stage.battle_music_context)
	stage.set_planning_camera()
	stage.entry_camera=source_camera;stage.entry_fov=source_fov
	stage.set_meta("has_entered",true)
	if is_instance_valid(warm_stage):warm_stage.queue_free();warm_stage=null
	stage.hide();stage.shell.hide();stage.shell.set_music_paused(true)
	entry_tick=_entry_timing("camera_music",entry_tick)
	update_roster()
	_entry_timing("roster_appearance",entry_tick)
	if active_local:
		status_layer.show();status_text.text="队伍集结中 · 等待所有玩家载入战斗…"
		_send({"op":"loaded","encounter":encounter})
	if authority():_check_ready()

func _entry_timing(phase: String, since: int) -> int:
	var now:=Time.get_ticks_usec()
	if "--battle-entry-profile" in OS.get_cmdline_user_args():print("BATTLE_ENTRY_CPU ",phase," ms=",(now-since)/1000.0)
	return now

func _check_ready() -> void:
	if not authority() or not is_instance_valid(stage) or members.is_empty() or waiting_round>=0:return
	for peer in members:
		if not loaded.has(peer):return
	if not gathering:
		net.publish({"op":"gather","encounter":encounter});_gather();return
	for peer in members:
		if not arrived.has(peer):return
	if stage.entering or battle_ready:return
	battle_ready=true;status_layer.hide();stage.shell.set_music_paused(not active_local)
	stage.shell.network_planning()

func _gather() -> void:
	if gathering or not is_instance_valid(stage):return
	var gathering_stage:=stage
	entering_stages.append(gathering_stage)
	gathering=true
	var origins: Dictionary=descriptor.origins.duplicate()
	for id in pvp_visual_origins:origins[id]=pvp_visual_origins[id]
	if active_local and is_instance_valid(manager.world.get("player")):
		for id in owners:
			if int(owners[id])==local_id():origins[id]=manager.world.player.global_position;break
		stage.entry_camera=manager.world.camera.global_transform.orthonormalized()
		stage.entry_fov=manager.world.camera.fov
	for unit in stage.engine.state.units:
		stage.actors[unit.id].global_position=origins.get(str(unit.id),stage.to_global(stage.SLOT_COORDS[unit.id]))
	stage.arena_surface.set_arrival_progress(0.0,bool(descriptor.get("pvp",false)))
	stage.center_pointer.hide();stage.show()
	var idle: Node=manager.site_entries[int(descriptor.site)].root.get_node_or_null("PvpSigil/IdleBoard")
	if idle!=null:idle.hide()
	if active_local:
		if is_instance_valid(manager.world.get("player")):manager.world.player.hide()
		status_text.text="正在归位…"
	# Start the camera at the captured pose before the first rendered battle frame.
	if active_local:
		stage.arrival_active=true
		stage.camera.global_transform=stage.entry_camera;stage.camera.fov=stage.entry_fov;stage.camera.current=true
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(gathering_stage) or stage!=gathering_stage:
		if is_instance_valid(gathering_stage):entering_stages.erase(gathering_stage);_release_retiring_stage(gathering_stage)
		return
	await preload("res://scripts/fusion_3d/battle_arrival.gd").play(stage,origins,active_local,bool(descriptor.get("pvp",false)))
	if not is_instance_valid(gathering_stage) or stage!=gathering_stage:
		if is_instance_valid(gathering_stage):entering_stages.erase(gathering_stage);_release_retiring_stage(gathering_stage)
		return
	entering_stages.erase(gathering_stage)
	stage.entering=false;stage.center_pointer.show();stage.entrance_finished.emit()
	if active_local:status_text.text="已归位 · 等待队友准备完成…";_send({"op":"arrived","encounter":encounter})
	if authority():_check_ready()
	if not messages.is_empty():consume()

func _arrival_motion(body: Node3D,moving: bool) -> void:
	if "external" in body and is_instance_valid(body.external):
		body.external.set_locomotion(false,0,5.0 if moving else 0.0)
	elif "animation" in body and body.animation!=null:
		if not moving:
			if not body.idle.is_empty():body.animation.play(body.idle,0.15)
			return
		for clip in body.animation.get_animation_list():
			if "anim_004_" in clip:
				body.animation.get_animation(clip).loop_mode=Animation.LOOP_LINEAR;body.animation.play(clip,0.15);break

func configure_engine(engine: BattleEngineV2) -> void:
	if int(descriptor.get("wire_version",0))>=3 and not observer_state.is_empty():
		Wire.apply(engine,observer_state);engine.presentation_only=true;return
	# Observers receive public combat state, never a participant's deck or inventory.
	# Apply it before actor construction so PvP and late-joined units have correct models.
	if bool(descriptor.get("observer_only",false)) and not observer_state.is_empty():
		Wire.apply(engine,observer_state);return
	if bool(descriptor.get("pvp",false)):
		Pvp.configure(engine,descriptor,manager.atlas.loadout);return
	for index in descriptor.loadouts.size():
		if not engine.configure_deck(StringName("P"+str(index)),descriptor.loadouts[index].counts):
			push_error("Invalid encounter loadout for slot "+str(index))
		if descriptor.loadouts[index].has("ai_source"):
			preload("res://scripts/worlds/island_ai_allies.gd").configure(engine,StringName("P"+str(index)),StringName(str(descriptor.loadouts[index].ai_source)))
		else:preload("res://scripts/worlds/island_loadout.gd").configure_extras(engine,StringName("P"+str(index)),descriptor.loadouts[index])
func update_roster() -> void:
	if not is_instance_valid(stage) or stage.engine==null:return
	stage.shell.visible=active_local and battle_ready and not stage.entering
	for unit in stage.engine.state.units:
		if not stage.engine.state.pvp and unit.team==1:continue
		var peer:=int(owners.get(str(unit.id),0))
		var profile: Dictionary=net.appearances.get(peer,{})
		if profile.get("outfits",{}).is_empty():profile=descriptor.get("appearances",{}).get(peer,{})
		if peer==local_id() and profile.get("outfits",{}).is_empty():profile=net.local_appearance
		if stage.shell.unit_views.has(unit.id):
			var plate: Control=stage.shell.unit_views[unit.id].nameplate
			var player_name: String=""
			if peer>0:
				player_name=str(get_node("/root/Accounts").active_character.get("name","冒险者")) if peer==local_id() else str(profile.get("name",net.appearances.get(peer,{}).get("name","冒险者")))
			plate.set_meta("player_display_name",player_name)
			plate.tooltip_text=plate._display_name()
			plate.queue_redraw()
		var outfit: Dictionary=profile.get("outfits",{}).get(str(unit.school_id),get_node("/root/Wardrobe").default_outfit(str(unit.school_id)))
		var body: Node3D=stage.actors[unit.id].get_node("Body").external
		body.follow_local_wardrobe=false
		if body.equipped!=outfit:body.apply_outfit(outfit)
		preload("res://scripts/worlds/replicated_wings.gd").attach(body,profile)
		body.set_battle_mode(true)
func _scan_late_players() -> void:
	if not pending_join.is_empty() or not is_instance_valid(stage) or stage.entering or stage.engine.state.phase==BattleStateV2.Phase.FINISHED:return
	var config: Dictionary=manager.site_entries[int(descriptor.site)].config
	var center: Vector3=manager.point(config.center)
	for peer in player_positions():
		if members.has(int(peer)) or not profiles.has(peer):continue
		var offset: Vector3=player_positions()[peer]-center
		if Vector2(offset.x,offset.z).length()>float(config.radius) or absf(offset.y)>8:continue
		var team:=Pvp.team_at(player_positions()[peer],config) if stage.engine.state.pvp else 0
		var slot:=Pvp.free_slot(owners,team)
		# A full formation stays capped at four combatants, including AI helpers.
		if slot<0:continue
		pending_join={"team":team,"peer":int(peer),"slot":slot,"profile":profiles[peer].duplicate(true),"appearance":net.appearances.get(peer,{}).duplicate(true),"origin":player_positions()[peer],"round":stage.engine.state.round_index+1,"ready":{},"deadline":Time.get_ticks_msec()+90000}
		join_pauses_planning=false
		var packet: Dictionary={"op":"join_prepare","encounter":encounter,"descriptor":descriptor,"owners":owners,"members":members,"pending":pending_join,"state":Wire.pack(stage.engine.state),"seq":sequence,"pause":false}
		net.publish(packet);_prepare_join(packet);return

func _prepare_join(data: Dictionary) -> void:
	pending_join=data.pending.duplicate(true);join_pauses_planning=bool(data.pause)
	var peer:=int(pending_join.peer)
	var newcomer:=local_id()==peer
	if not is_instance_valid(stage):
		descriptor=data.descriptor;encounter=int(data.encounter);owners=data.owners;members.assign(data.members)
		_open(false)
		Wire.apply(stage.engine,data.state);stage.sync_roster();sequence=int(data.seq)
		stage.entering=false;gathering=true;stage.show();battle_ready=true
		stage.arena_surface.set_arrival_progress(1.0,true);stage.center_pointer.show()
		_hide_idle_board()
	if newcomer:
		manager.begin_local(int(descriptor.site),true);active_local=true
		stage.show();stage.set_planning_camera();stage.camera.current=true;status_layer.show()
		status_text.text="正在入阵 · 就绪后加入本轮" if join_pauses_planning else "正在入阵 · 下一回合参战"
	if join_pauses_planning:
		stage.shell.prompt_label.text="等待新队友载入与归位…"
	var body: Node3D=load("res://scenes/characters/modular_wizard.tscn").instantiate()
	body.follow_local_wardrobe=false;stage.add_child(body)
	body.configure(Color.WHITE,str(pending_join.profile.school),false)
	var appearance: Dictionary=pending_join.appearance
	body.apply_outfit(appearance.get("outfits",{}).get(str(pending_join.profile.school),get_node("/root/Wardrobe").default_outfit(str(pending_join.profile.school))))
	preload("res://scripts/worlds/replicated_wings.gd").attach(body,appearance)
	body.position=stage.to_local(pending_join.origin);join_figures[peer]=body
	var destination: Vector3=stage.SLOT_COORDS[StringName(("P" if int(pending_join.get("team",0))==0 else "E")+str(pending_join.slot))]
	body.look_at(stage.to_global(Vector3(destination.x,body.position.y,destination.z)))
	body.set_locomotion(false,0,5)
	var move:=create_tween();move.tween_property(body,"position",destination,1.5)
	await move.finished
	if pending_join.is_empty() or not is_instance_valid(body):return
	body.set_locomotion(false,0,0);body.look_at(stage.to_global(Vector3(0,body.position.y,0)))
	_send({"op":"join_loaded","encounter":encounter,"joining":peer})

func _join_ready() -> bool:
	if pending_join.is_empty():return false
	for peer in members+[int(pending_join.peer)]:
		if not pending_join.ready.has(peer):return false
	return true
func _try_admit_join() -> void:
	if not authority() or not _join_ready() or not is_instance_valid(stage):return
	if stage.shell.resolving_network or stage.engine.state.phase!=BattleStateV2.Phase.PLANNING or int(pending_join.round)>stage.engine.state.round_index:return
	_admit_join()
func admit_pending() -> void:
	if pending_join.is_empty() or not _join_ready() or not is_instance_valid(stage):return
	_admit_join()
func _admit_join() -> void:
	var peer:=int(pending_join.peer)
	var slot:=int(pending_join.slot)
	var profile: Dictionary=pending_join.profile
	var unit: BattleUnitStateV2=stage.engine._create_unit(StringName(manager.atlas.loadout.character(str(profile.school))),int(pending_join.get("team",0)),slot)
	stage.engine.state.units.append(unit)
	if not stage.engine.configure_deck(unit.id,profile.counts):
		push_error("Invalid joining loadout for "+str(unit.id))
	preload("res://scripts/worlds/island_loadout.gd").configure_extras(stage.engine,unit.id,profile)
	unit.deck.draw_to_limit();unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
	owners[str(unit.id)]=peer;members.append(peer);loaded[peer]=true;arrived[peer]=true
	if unit.team==0:
		descriptor.party.append(StringName(manager.atlas.loadout.character(str(profile.school))));descriptor.loadouts.append(profile)
	if stage.engine.state.pvp:descriptor.combatants.append({"id":str(unit.id),"team":unit.team,"slot":slot,"peer":peer,"profile":profile})
	descriptor.origins[str(unit.id)]=pending_join.origin
	descriptor.appearances[peer]=pending_join.appearance
	var packet: Dictionary={"op":"join_admit","encounter":encounter,"descriptor":descriptor,"owners":owners,"members":members,"state":Wire.pack(stage.engine.state)}
	net.publish(packet);_apply_admission(packet)
	stage.shell.planning_deadline=Time.get_ticks_msec()+30000
	stage.shell.network_planning()
func _apply_admission(data: Dictionary) -> void:
	descriptor=data.descriptor;owners=data.owners;members.assign(data.members)
	if bool(descriptor.get("observer_only",false)):observer_state=data.state
	Wire.apply(stage.engine,data.state);stage.sync_roster()
	for body in join_figures.values():if is_instance_valid(body):body.queue_free()
	join_figures.clear();pending_join.clear();join_pauses_planning=false
	battle_ready=true;active_local=members.has(local_id());status_layer.hide();update_roster()
func _cancel_join() -> void:
	var was_joiner:=int(pending_join.get("peer",-1))==local_id()
	var was_pausing:=join_pauses_planning
	for body in join_figures.values():if is_instance_valid(body):body.queue_free()
	join_figures.clear();pending_join.clear();join_pauses_planning=false
	if was_joiner:
		active_local=false;manager.finish_local(-1);stage.shell.hide();status_layer.hide()
	if was_pausing and authority() and is_instance_valid(stage) and not stage.shell.resolving_network:
		stage.shell.planning_deadline=Time.get_ticks_msec()+30000;stage.shell.network_planning()
func broadcast_step(kind: String,extra: Dictionary={}) -> void:
	sequence+=1
	var compact:=kind in ["turn","action"]
	var packet: Dictionary={"op":"step","encounter":encounter,"seq":sequence,"kind":kind,"state":Wire.pack_view(stage.engine.state) if compact else Wire.pack(stage.engine.state),"remaining":stage.shell.planning_remaining()}
	if compact:packet.compact=true
	packet.merge(extra);net.publish(packet)
func request_flee() -> void:
	if not active_local or not is_instance_valid(stage) or stage.shell.ui_state==stage.shell.UIState.RESOLVING:return
	_send({"op":"flee","encounter":encounter})

func _return_from_flee() -> void:
	if not active_local:return
	active_local=false
	if is_instance_valid(stage):stage.shell.hide();stage.shell.set_music_paused(true)
	manager.finish_local(-1)
	manager.atlas.game_menu.message.text="已逃离战斗，返回安全位置。"

func command(op: String,args: Dictionary={}) -> void:
	if not battle_ready or not is_instance_valid(stage):return
	if stage.engine.state.pvp and local_team()!=stage.engine.state.active_team and op not in ["draw","discard","charge"]:return
	var actor: String=""
	for id in owners:
		if mine(StringName(id)):actor=str(id);break
	if stage.shell.active_actor!=null and mine(stage.shell.active_actor.id):actor=str(stage.shell.active_actor.id)
	if actor.is_empty():return
	var data: Dictionary={"op":"command","encounter":encounter,"round":stage.engine.state.round_index,"actor":actor,"command":op}
	data.merge(args);_send(data)

func send_chat(text: String) -> void:net.send_chat(text)

func _receive(data: Dictionary) -> void:
	if str(data.get("op", "")) in ["journey_redirect", "journey_result"]:
		manager.atlas.journey_packet(data);return
	# Expand a reliable round envelope into the existing ordered presentation queue.
	if str(data.get("op",""))=="round_batch":
		if not is_instance_valid(stage) or int(data.get("encounter",-1))!=encounter:return
		for step in Wire.expand_round(data):_receive(step)
		return
	match str(data.get("op","")):
		"progression":
			var accounts:=get_node_or_null("/root/Accounts")
			if accounts!=null and data.get("snapshot") is Dictionary:
				if accounts.apply_progression(data.snapshot) and data.get("authenticated",false):
					net.authenticated=true
				if data.get("reward",false):manager.atlas.game_menu.message.text="宝藏卡已到账 · 服务器已保存"
				# The receipt is independent of inventory refresh/revision ordering.
				# A newer snapshot may already be applied when this confirmation arrives.
				if data.get("reward_receipt") is Dictionary and "empower_reward_popup" in manager.atlas and is_instance_valid(manager.atlas.empower_reward_popup):
					manager.atlas.empower_reward_popup.confirm(data.reward_receipt,data.snapshot)
			return
		"pvp_wait":_show_pvp_wait(data);return
		"pvp_wait_end":_end_pvp_wait();return
		"chat":
			if is_instance_valid(manager.atlas.world_chat):manager.atlas.world_chat.receive_message(str(data.get("name","冒险者")),str(data.get("text","")))
			_show_chat_bubble(int(data.get("peer",0)),str(data.get("text","")))
			return
		"server_error":
			if not net.authenticated or str(data.get("code",""))=="unauthorized":manager.atlas.game_menu.authentication_failed(str(data.get("code","service_unavailable")))
			manager.atlas.game_menu.message.text=str(data.get("message","服务器拒绝请求"));return
		"observe":
			if active_local:return
			if is_instance_valid(stage):
				if encounter==int(data.descriptor.id) and not data.members.has(local_id()):return
				close(-1)
			descriptor=data.descriptor;encounter=int(descriptor.id);owners=data.owners;members.assign(data.members)
			descriptor["observer_only"]=bool(data.get("observer_only",descriptor.get("observer_only",false)))
			observer_state=data.state
			_open(false);Wire.apply(stage.engine,data.state);stage.sync_roster();stage.entering=false;gathering=true;stage.show();sequence=int(data.seq)
			if active_local:
				stage.set_planning_camera();stage.camera.current=true
				battle_ready=true;status_layer.hide();stage.shell.set_music_paused(false)
			stage.arena_surface.transparency=0.0;stage.center_pointer.show()
			update_roster()
			_hide_idle_board()
			stage.sync_world_state();return
		"clock":clock_offset=float(data.seconds)-Time.get_ticks_msec()/1000.0;return
		"busy":
			encounter_busy=true;manager.staged_site=int(data.site)
			if manager.staged_site<manager.site_entries.size():manager.site_entries[manager.staged_site].root.hide()
			return
		"open":
			if is_instance_valid(stage):
				if active_local or encounter==int(data.descriptor.id) or not data.members.has(local_id()):return
				close(-1)
			observer_state=data.get("state",{})
			descriptor=data.descriptor;encounter=int(descriptor.id);sequence=0;owners=data.owners;members.assign(data.members)
			_open();return
		"join_prepare":
			if not is_instance_valid(stage):observer_state=data.get("state",{})
			if is_instance_valid(stage) and int(data.encounter)!=encounter:
				if active_local or int(data.pending.peer)!=local_id():return
				close(-1)
			if int(data.pending.peer)==local_id():
				# Upgrade the existing public stage to its participant snapshot before entry.
				observer_state=data.get("state",{});descriptor=data.descriptor
				if is_instance_valid(stage):Wire.apply(stage.engine,data.state);stage.sync_roster()
			_prepare_join(data);return
		"join_admit":
			if not is_instance_valid(stage) or int(data.encounter)!=encounter:return
			_apply_admission(data);return
		"join_cancel":
			if not is_instance_valid(stage) or int(data.encounter)!=encounter:return
			_cancel_join();return
	if int(data.get("encounter",-1))!=encounter and is_instance_valid(stage):return
	match str(data.get("op","")):
		"fled":_return_from_flee()
		"gather":_gather()
		"roster":owners=data.owners;members.assign(data.members);update_roster()
		"step":
			if not is_instance_valid(stage) or int(data.seq)<=sequence:return
			settle_treasures(Wire.unpack(data.get("events",[]),manager.atlas.loadout.content))
			sequence=int(data.seq);messages.append(data)
			if not stage.entering:consume()
		"close":
			if bool(data.get("observer_only",false)) and (active_local or not is_instance_valid(stage) or int(data.get("encounter",-1))!=encounter):return
			var exit_positions: Dictionary=data.get("exit_positions",{})
			close(int(data.get("winner",-1)),exit_positions)

func settle_treasures(events: Array) -> void:
	# Online consumption is committed by the dedicated server; animation packets grant no rights.
	if net.connected and not authority():return
	var accounts:=get_node_or_null("/root/Accounts")
	if accounts!=null and not accounts.active_character.is_empty():return
	var changed:=false
	for event in events:
		if event.type==&"TreasureConsumed" and int(owners.get(str(event.payload.unit_id),0))==local_id():
			changed=manager.atlas.loadout.consume_treasure(str(event.payload.card_id),str(event.payload.token)) or changed
	if changed:manager.atlas.game_menu._queue_sync()

func _show_chat_bubble(peer: int,text: String) -> void:
	var avatar: Node3D
	if peer==local_id():avatar=manager.world.avatar
	elif remotes.has(peer):avatar=remotes[peer]
	if not is_instance_valid(avatar):return
	var bubble:=avatar.get_node_or_null("WorldChatBubble")
	if bubble==null:
		bubble=Node3D.new();bubble.name="WorldChatBubble"
		bubble.set_script(preload("res://scripts/worlds/player_chat_bubble.gd"))
		avatar.add_child(bubble)
	bubble.show_message(text)
func consume() -> void:
	if consuming:return
	var consuming_stage:=stage
	consuming=true
	while not messages.is_empty() and is_instance_valid(stage):
		var packet: Dictionary=messages.pop_front()
		if packet.kind=="planning":battle_ready=true;status_layer.hide();stage.shell.set_music_paused(not active_local)
		await stage.shell.play_packet(packet)
		if not is_instance_valid(consuming_stage) or stage!=consuming_stage:
			if is_instance_valid(consuming_stage):_release_retiring_stage(consuming_stage)
			return
		if active_local and not net.lan_debug and packet.kind in ["round_end","finished"]:
			_send({"op":"step_presented","encounter":encounter,"seq":int(packet.get("seq",0))})
	consuming=false

func _retire_stage(old_stage: Node3D) -> void:
	# Keep the in-flight await stack alive until this one packet returns. It no
	# longer receives packets, input, presentation acknowledgements or visible UI.
	retiring_stages.append(old_stage)
	old_stage.arrival_token+=1;old_stage.arrival_active=false
	old_stage.hide();old_stage.shell.hide()
	old_stage.set_process(false);old_stage.shell.set_process(false)
	old_stage.shell.set_process_input(false);old_stage.shell.set_process_unhandled_input(false)
	old_stage.shell.set_music_paused(true)
	var audio: Node=old_stage.theatre.audio
	audio.stop_all()
	for key in ["cast_volume_db","impact_volume_db","ui_volume_db"]:audio.config[key]=-80.0
	for player in old_stage.find_children("*","AudioStreamPlayer",true,false):player.volume_db=-80.0

func _clear_stage_references(old_stage: Node3D) -> void:
	if is_instance_valid(old_stage.theatre):old_stage.theatre.cost_presentation=Callable()
	if is_instance_valid(old_stage.shell):old_stage.shell.presentation_director.current_context.clear()
	old_stage.pending_cast_consumptions.clear()
	if old_stage.engine!=null:old_stage.engine.event_stream.subscribers.clear()

func _release_retiring_stage(old_stage: Node3D) -> void:
	if not is_instance_valid(old_stage):return
	if not retiring_stages.has(old_stage):return
	retiring_stages.erase(old_stage)
	_clear_stage_references(old_stage)
	old_stage.queue_free()

func prepare_world_exit(timeout_ms: int=30000) -> bool:
	if is_instance_valid(stage):close(-1)
	var deadline:=Time.get_ticks_msec()+timeout_ms
	while not retiring_stages.is_empty() or prewarming:
		if Time.get_ticks_msec()>=deadline:return false
		await get_tree().process_frame
	# Let deferred node deletion finish before the enclosing world is destroyed.
	await get_tree().process_frame
	return true
func finish(winner: int) -> void:
	var exit_positions: Dictionary={}
	if authority() and not descriptor.is_empty():
		exit_positions=preload("res://scripts/server/encounter_geometry.gd").scattered_exits(manager.site_entries[int(descriptor.site)].config,members)
		for peer in members:
			if net.positions.has(peer):net.positions[peer]=exit_positions[peer];net.last_seen[peer]=Time.get_ticks_msec()
		net.publish({"op":"close","encounter":encounter,"winner":winner,"exit_positions":exit_positions})
	close(winner,exit_positions)
func close(winner: int=-1,exit_positions: Dictionary={}) -> void:
	for body in join_figures.values():if is_instance_valid(body):body.queue_free()
	pending_join.clear();join_figures.clear();join_pauses_planning=false
	messages.clear();battle_ready=false
	if is_instance_valid(stage):
		# A completed/idle stage has no in-flight presentation coroutine; retain its
		# expensive static board/HUD for the next encounter. Interrupted animations
		# are discarded instead, so they cannot resume into a different battle.
		if not GraphicsSettings.is_low() and not consuming and not stage.entering and (not stage.shell.resolving_network or stage.engine.state.phase==BattleStateV2.Phase.FINISHED):
			if is_instance_valid(warm_stage):warm_stage.queue_free()
			warm_stage=stage;warm_stage.hide();warm_stage.shell.hide();warm_stage.theatre.clear()
			warm_stage.shell.prepare_battle_music(warm_stage.battle_music_context)
			warm_stage.process_mode=Node.PROCESS_MODE_DISABLED
		elif consuming or entering_stages.has(stage):_retire_stage(stage)
		else:stage.queue_free()
	# An interrupted old shell may never resume its await; new stages must still consume.
	consuming=false;observer_state.clear()
	var result_team:=local_team()
	stage=null;status_layer.hide();manager.finish_local((0 if winner==result_team else 1) if bool(descriptor.get("pvp",false)) and winner>=0 else winner,exit_positions.get(local_id()))
	if waiting_round>=0:waiting_round=-1;presentations_finished.emit()
	active_local=false;encounter_busy=false;gathering=false;owners.clear();members.clear();loaded.clear();arrived.clear()
	send_profile()
func _transport_left(peer: int) -> void:
	if peer==0:test_ai_counts.clear()
	else:test_ai_counts.erase(peer)
	_left(peer)

func _left(peer: int) -> void:
	if peer==0:
		_end_pvp_wait();pvp_lobby.clear();close();manager.restore_roaming();profiles.clear();send_profile();return
	pvp_lobby.teams.erase(peer)
	profiles.erase(peer)
	if not pending_join.is_empty():
		if int(pending_join.peer)==peer:
			net.publish({"op":"join_cancel","encounter":encounter});_cancel_join()
	if not authority() or not encounter_busy:return
	members.erase(peer);loaded.erase(peer);arrived.erase(peer)
	for id in owners:
		if int(owners[id])==peer:
			owners[id]=0
			if is_instance_valid(stage) and stage.engine.state.pvp:
				var unit: BattleUnitStateV2=stage.engine.state.unit_by_id(StringName(id))
				unit.alive=false;unit.hp=0;stage.engine.state.actions.erase(unit.id)
	if members.is_empty():finish(-1);return
	if is_instance_valid(stage) and stage.engine.state.pvp and stage.engine.check_battle_end():finish(stage.engine.state.winner_team);return
	net.publish({"op":"roster","encounter":encounter,"owners":owners,"members":members})
	_check_ready()
	_check_presented()
	if battle_ready and is_instance_valid(stage) and stage.engine.state.phase==BattleStateV2.Phase.PLANNING:stage.shell.network_planning()

func local_team() -> int:
	if int(pending_join.get("peer",-1))==local_id():return int(pending_join.get("team",0))
	for id in owners:
		if int(owners[id])==local_id():return 1 if str(id).begins_with("E") else 0
	return 0

func _poll_pvp() -> void:
	var index:=pvp_lobby.site_index
	if index<0:return
	if Time.get_ticks_msec()>=pvp_lobby.expires or pvp_lobby.teams.is_empty():
		net.publish({"op":"pvp_wait_end","site":index})
		for peer in pvp_lobby.teams:
			net.position_frozen.erase(peer)
			net.positions[peer]=manager.point(manager.site_entries[index].config.approach);net.last_seen[peer]=Time.get_ticks_msec()
		manager.cooldowns[index]=world_seconds()+20
		pvp_lobby.clear();pvp_announced_count=0;_end_pvp_wait();return
	pvp_lobby.scan(index,manager.site_entries[index].config,player_positions(),profiles,Time.get_ticks_msec())
	var packet:={"op":"pvp_wait","site":index,"teams":pvp_lobby.teams.duplicate(),"remaining":(pvp_lobby.expires-Time.get_ticks_msec())/1000.0}
	for peer in pvp_lobby.teams:net.position_frozen[peer]=true
	if pvp_announced_count!=pvp_lobby.teams.size():
		pvp_announced_count=pvp_lobby.teams.size();_show_pvp_wait(packet);net.publish(packet)
	if not pvp_lobby.ready():return
	var appearances: Dictionary=net.appearances.duplicate(true);appearances[local_id()]=net.local_appearance.duplicate(true)
	descriptor=pvp_lobby.describe(manager.atlas.loadout,profiles,player_positions(),appearances)
	members.assign(pvp_lobby.teams.keys());owners.clear()
	for member in descriptor.combatants:owners[member.id]=int(member.peer)
	encounter+=1;descriptor.id=encounter;sequence=0;loaded.clear();arrived.clear()
	pvp_lobby.clear();pvp_announced_count=0;net.publish({"op":"open","descriptor":descriptor,"owners":owners,"members":members});_open()

func _show_pvp_wait(data: Dictionary) -> void:
	_prepare_pvp_walk(data)
	if not data.teams.has(local_id()):return
	if not pvp_waiting:
		manager.begin_local(int(data.site),true)
		manager.world.player.show()
	pvp_waiting=true;pvp_wait_team=int(data.teams[local_id()])
	pvp_wait_deadline=Time.get_ticks_msec()+int(float(data.remaining)*1000)
	status_layer.show()

func _end_pvp_wait() -> void:
	_clear_pvp_walk()
	if not pvp_waiting:return
	pvp_waiting=false;status_layer.hide();manager.finish_local(-1)
	manager.atlas.game_menu.message.text="30 秒内没有对手入阵，已返回阵外。"

func _hide_idle_board() -> void:
	var idle: Node=manager.site_entries[int(descriptor.site)].root.get_node_or_null("PvpSigil/IdleBoard")
	if idle!=null:idle.hide()

func _prepare_pvp_walk(data: Dictionary) -> void:
	var config: Dictionary=manager.site_entries[int(data.site)].config
	pvp_wait_center=manager.point(config.center)
	var slots: Dictionary=preload("res://scripts/fusion_3d/battle_stage.gd").build_slot_coords()
	var counts: Array=[0,0]
	for peer in data.teams:
		var team:=int(data.teams[peer]);var slot:=int(counts[team]);counts[team]+=1
		if pvp_wait_targets.has(peer):continue
		var id:=StringName(("P" if team==0 else "E")+str(slot))
		pvp_wait_targets[peer]=pvp_wait_center+slots[id]*float(config.scale)
		pvp_wait_positions[peer]=manager.world.player.position if int(peer)==local_id() else (remotes[peer].position if remotes.has(peer) else net.positions.get(peer,pvp_wait_targets[peer]))

func _advance_pvp_wait(delta: float) -> void:
	for peer in pvp_wait_targets:
		var destination: Vector3=pvp_wait_targets[peer]
		var previous: Vector3=pvp_wait_positions[peer]
		var next:=previous.move_toward(destination,5.0*delta)
		pvp_wait_positions[peer]=next
		var avatar: Node3D
		if int(peer)==local_id():
			manager.world.player.position=next;avatar=manager.world.avatar
		elif remotes.has(peer):
			avatar=remotes[peer];avatar.position=next
		if not is_instance_valid(avatar):continue
		var moving:=next.distance_to(destination)>0.01
		var facing:=destination if moving else pvp_wait_center
		if Vector2(facing.x-next.x,facing.z-next.z).length()>0.01:
			avatar.look_at(Vector3(facing.x,avatar.global_position.y,facing.z))
		avatar.set_locomotion(false,0,5.0 if moving else 0.0)

func _clear_pvp_walk() -> void:
	if pvp_wait_targets.has(local_id()) and is_instance_valid(manager.world):manager.world.avatar.set_locomotion(false,0,0)
	for peer in pvp_wait_targets:
		if remotes.has(peer):remotes[peer].set_locomotion(false,0,0)
	pvp_wait_positions.clear();pvp_wait_targets.clear()
