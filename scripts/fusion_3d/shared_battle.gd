extends Node
## One shared demo encounter per town. Only the host runs Battle Core.
const Wire=preload("res://scripts/fusion_3d/battle_wire.gd")
var town: Node3D
var net: Node
var stage: Node3D
var encounter:=0
var members: Array[int]=[]
var pending: Array[int]=[]
var owners: Dictionary={}
var descriptor: Dictionary={}
var latest: Dictionary={}
var latest_segment: Dictionary={}
var sequence:=0
var hello_sent:=false
var active_local:=false
var arrivals: Dictionary={}
var join_button: Button
var messages: Array[Dictionary]=[]
var consuming:=false
var last_request: Dictionary={}
func setup(world: Node3D) -> void:
	town=world
	net=town.network
	net.request_received.connect(_request)
	net.battle_received.connect(_receive)
	net.peer_left.connect(_left)
	join_button=Button.new()
	join_button.text="加入附近战斗"
	join_button.position=Vector2(24,220)
	join_button.size=Vector2(235,44)
	join_button.focus_mode=Control.FOCUS_NONE
	town.hud.add_child(join_button)
	join_button.pressed.connect(func():net.send_request({"op":"join","encounter":encounter}))
func authority() -> bool:return net.connected and multiplayer.is_server()
func mine(id: StringName) -> bool:return int(owners.get(str(id),0))==multiplayer.get_unique_id() and active_local
static func allocation(peers: Array[int]) -> Dictionary:
	var result: Dictionary={}
	if peers.is_empty():return result
	for slot in 4:result["P"+str(slot)]=peers[slot] if slot<peers.size() else 0
	return result
func _process(_delta: float) -> void:
	if net.connected and not hello_sent:
		hello_sent=true
		if not authority():net.send_request({"op":"hello"})
	if not net.connected:hello_sent=false
	join_button.visible=is_instance_valid(stage) and not active_local
	join_button.disabled=pending.has(multiplayer.get_unique_id()) or members.size()+pending.size()>=4
	if pending.has(multiplayer.get_unique_id()):join_button.text="已入阵 · 等待下一规划阶段"
	else:join_button.text="加入附近战斗"
	if is_instance_valid(stage) and not active_local:town.camera.current=true
func start() -> void:
	net.send_request({"op":"start","party":town.party,"origin":town.battle_origin,"encounter_id":"garden_familiars" if town.chapter!=null and town.chapter.encounter_active else ""})
func _request(peer: int,data: Dictionary) -> void:
	if not authority():return
	var op:=str(data.get("op",""))
	if op=="hello":
		if is_instance_valid(stage):
			net.publish({"op":"open","descriptor":descriptor,"owners":owners,"members":members,"pending":pending},peer)
			if not latest.is_empty():net.publish(latest,peer)
		return
	if op=="start":
		if is_instance_valid(stage):_request(peer,{"op":"join","encounter":encounter});return
		var chosen: Array[StringName]=[]
		for id in data.get("party",[]):
			if town.CHARACTER_IDS.has(StringName(id)) and not chosen.has(StringName(id)):chosen.append(StringName(id))
		if chosen.size()!=4:return
		encounter+=1
		members.assign([peer]);pending.clear();owners=allocation(members)
		var origin: Vector3=data.get("origin",town.battle_origin)
		if not origin.is_finite() or origin.length()>600:return
		descriptor={"id":encounter,"party":chosen,"origin":origin,"encounter_id":"garden_familiars" if data.get("encounter_id","")=="garden_familiars" else ""}
		net.publish({"op":"open","descriptor":descriptor,"owners":owners,"members":members,"pending":pending})
		_open()
		return
	if not is_instance_valid(stage) or int(data.get("encounter",-1))!=encounter:return
	if op=="join":
		if members.has(peer) or pending.has(peer) or members.size()+pending.size()>=4:return
		var position: Vector3=net.positions.get(peer,net.local_position if peer==1 else Vector3(9999,0,0))
		if position.distance_to(stage.global_position)>26:
			net.state_changed.emit("靠近战斗法阵后加入")
			return
		pending.append(peer)
		# Already planned actions remain immutable. Transfer only at a clean planning boundary.
		if not stage.entering and stage.shell.ui_state==0 and stage.engine.state.actions.is_empty():admit_pending()
		else:publish_roster()
		return
	if op=="command":
		var now:=Time.get_ticks_msec()
		if now-int(last_request.get(peer,0))<40:return
		last_request[peer]=now
		stage.shell.accept_command(peer,data)
func _open() -> void:
	if is_instance_valid(stage):return
	stage=load("res://scenes/fusion_3d/battle_stage.tscn").instantiate()
	stage.shared_session=self
	stage.embedded=true
	stage.party.assign(descriptor.party)
	stage.encounter_id=str(descriptor.encounter_id)
	stage.position=descriptor.origin
	stage.entry_origin=town.player.position-stage.position
	town.add_child(stage)
	stage.entrance_finished.connect(_entrance_ready)
	town.camera.current=true
	update_roster()
func _entrance_ready() -> void:
	update_roster()
	if authority():
		admit_pending()
		stage.shell.network_planning()
	elif not messages.is_empty():consume()
func publish_roster() -> void:
	owners=allocation(members)
	update_roster()
	net.publish({"op":"roster","encounter":encounter,"owners":owners,"members":members,"pending":pending})
func admit_pending() -> void:
	for peer in pending:
		if members.size()<4:members.append(peer)
	pending.clear()
	publish_roster()
func update_roster() -> void:
	if not is_instance_valid(stage):return
	var should_join: bool=members.has(multiplayer.get_unique_id()) and not stage.entering and stage.shell.ui_state!=4
	if should_join and not active_local:
		active_local=true
		town.saved_position=town.player.position
		town.battle=stage
		town.player.hide();town.hud.hide()
		town.dialogue.hide();town.party_panel.hide();town.wardrobe_panel.hide()
		town.view_controller.set_capture(false)
		town.exploration_music.set_battle(true)
		stage.camera.current=true;stage.shell.show()
	for peer in arrivals.keys():
		if not pending.has(peer):arrivals[peer].queue_free();arrivals.erase(peer)
	for peer in pending:
		if arrivals.has(peer):continue
		var figure: Node3D=load("res://scenes/characters/modular_wizard.tscn").instantiate()
		town.add_child(figure)
		var profile: Dictionary=net.appearances.get(peer,{"school":"fire"})
		figure.configure(Color.WHITE,str(profile.school),true)
		figure.apply_outfit(profile.get("outfits",{}).get(str(profile.school),get_node("/root/Wardrobe").default_outfit(str(profile.school))))
		figure.position=net.positions.get(peer,town.player.position)
		var destination: Vector3=stage.position+Vector3(3.8+pending.find(peer)*1.5,0.1,6)
		figure.look_at(destination+Vector3(0,.01,0))
		create_tween().tween_property(figure,"position",destination,1.3)
		arrivals[peer]=figure
		if peer==multiplayer.get_unique_id():town.player.hide()
	apply_skins()
func apply_skins() -> void:
	if not is_instance_valid(stage) or stage.engine==null:return
	for unit in stage.engine.state.team_units(0):
		var peer:=int(owners.get(str(unit.id),0))
		var profile: Dictionary=net.local_appearance if peer==multiplayer.get_unique_id() else net.appearances.get(peer,{})
		var outfit: Dictionary=profile.get("outfits",{}).get(str(unit.school_id),get_node("/root/Wardrobe").default_outfit(str(unit.school_id)))
		var body: Node3D=stage.actors[unit.id].get_node("Body").external
		body.follow_local_wardrobe=false
		if body.equipped!=outfit:body.apply_outfit(outfit)
		body.set_battle_mode(true)
func broadcast_step(kind: String,extra: Dictionary={}) -> void:
	sequence+=1
	var compact:=kind in ["turn","action"]
	var packet: Dictionary={"op":"step","encounter":encounter,"seq":sequence,"kind":kind,"state":Wire.pack_view(stage.engine.state) if compact else Wire.pack(stage.engine.state)}
	if compact:packet.compact=true
	packet.merge(extra)
	latest=packet.duplicate(true)
	net.publish(packet)
func command(op: String,args: Dictionary={}) -> void:
	if not is_instance_valid(stage) or stage.shell.active_actor==null:return
	var data: Dictionary={"op":"command","encounter":encounter,"round":stage.engine.state.round_index,"actor":str(stage.shell.active_actor.id),"command":op}
	data.merge(args)
	net.send_request(data)
func _receive(data: Dictionary) -> void:
	if data.get("op","")=="open":
		if is_instance_valid(stage):return
		descriptor=data.descriptor;encounter=int(descriptor.id)
		owners=data.owners;members.assign(data.members);pending.assign(data.pending)
		_open();return
	if int(data.get("encounter",-1))!=encounter:return
	match str(data.get("op","")):
		"roster":
			owners=data.owners;members.assign(data.members);pending.assign(data.pending)
			update_roster()
			if not stage.entering and stage.shell.ui_state!=4:stage.shell.network_planning()
		"step":
			if int(data.seq)<=sequence:return
			sequence=int(data.seq)
			messages.append(data)
			if not stage.entering:consume()
		"close":close(int(data.get("winner",-1)))
func consume() -> void:
	if consuming:return
	consuming=true
	while not messages.is_empty() and is_instance_valid(stage):
		var packet: Dictionary=messages.pop_front()
		await stage.shell.play_packet(packet)
	consuming=false
func finish(winner: int) -> void:
	if authority():net.publish({"op":"close","encounter":encounter,"winner":winner})
	close(winner)
func close(winner: int=-1) -> void:
	messages.clear()
	for figure in arrivals.values():figure.queue_free()
	arrivals.clear()
	if is_instance_valid(stage):
		if active_local:town.finish_battle(winner)
		else:stage.queue_free()
	stage=null;active_local=false;owners.clear();members.clear();pending.clear();latest.clear();sequence=0
	town.player.show();town.camera.current=true
func _left(peer: int) -> void:
	if peer==0:close();return
	if not authority():return
	pending.erase(peer)
	members.erase(peer)
	if is_instance_valid(stage):
		if members.is_empty():finish(-1)
		else:
			publish_roster()
			if stage.shell.ui_state!=4:stage.shell.network_planning()
