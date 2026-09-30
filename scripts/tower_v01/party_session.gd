extends Node
## Private, two-human LAN trial. All run choices and combat resolve on the host.
const Trial=preload("res://scripts/tower_v01/trial_context.gd")
const Wire=preload("res://scripts/fusion_3d/battle_wire.gd")
const PORT=29731
var tower: Node3D
var net: Node
var controller: Node
var trials: Array=[]
var owners: Dictionary={}
var descriptor: Dictionary={}
var stage: Node3D
var active_local:=true
var battle_ready:=false
var run_id:=""
var guest:=0
var guest_school:=""
var sequence:=0
var received_sequence:=0
var packets: Array=[]
var consuming:=false
var ready_peers: Dictionary={}
var choices: Dictionary={}
var presented: Dictionary={}
var closed:=false
var connected_at:=0
var accepted_commands:=0
var rejected_commands:=0
var test_accelerated:=false
var menu_version:=0
var received_menu_version:=-1
var operation_serial:=0
var pending_operation:=""
var acknowledgements: Dictionary={}
var load_started:=0
var transition_node:=-1
var transition_ready: Dictionary={}
var transition_started:=0
var playback_speed:=1.0

func _ready() -> void:
	controller=tower.run_controller
	# A separate MultiplayerAPI prevents the trial from replacing world networking.
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(),get_path())
	net=preload("res://scripts/fusion_3d/town_network.gd").new()
	net.name="Transport";net.normalize_rpc_root=true;net.max_clients=1;net.dedicated=true
	add_child(net)
	net.request_received.connect(receive_request)
	net.battle_received.connect(receive)
	net.peer_left.connect(func(peer):
		if closed:return
		if not run_id.is_empty():abort("队友离线，本局结束；不发放正式奖励")
		elif peer==guest:guest=0;guest_school="";show_lobby("队友已离开，等待新队友加入"))
	net.state_changed.connect(func(_message):
		if net.connected and not authority():net.send_request({"op":"hello","school":chosen_school()})
		if run_id.is_empty() and not closed:show_lobby())
	net.set_process(false) # No world presence, account verification, or production traffic.

func _process(_delta: float) -> void:
	if net.connecting:
		if connected_at==0:connected_at=Time.get_ticks_msec()
		elif Time.get_ticks_msec()-connected_at>12000:
			net.disconnect_town();connected_at=0;show_lobby("连接超时，请检查房主地址和 UDP 29731")
	else:connected_at=0
	if load_started>0 and not battle_ready and Time.get_ticks_msec()-load_started>35000:abort("队伍战斗加载超时，本局结束")
	if transition_started>0 and Time.get_ticks_msec()-transition_started>20000:
		transition_started=0
		if authority():cancel_transition("楼层准备超时，仍保留原节点，可重试")
		else:net.send_request({"op":"moved","run":run_id,"node":trials[0].node_index,"target":transition_node,"ok":false})

func authority() -> bool:return net.multiplayer.is_server()
func mine(id: StringName) -> bool:return int(owners.get(str(id),0))==net.multiplayer.get_unique_id()
func local_slot() -> int:return 0 if authority() else 1
func planning_blocked() -> bool:return not battle_ready or closed
func configure_engine(_engine: BattleEngineV2) -> void:pass
func update_roster() -> void:pass
func settle_treasures(_events: Array) -> void:pass
func admit_pending() -> void:pass

func lobby() -> void:
	if controller.running:return
	closed=false;controller.running=true;controller.party_session=self
	show_lobby()

func show_lobby(message:="") -> void:
	controller.clear_menu("寒冰回响 · 双人真人组队\n局域网 UDP %d · 无 AI 补位 · 正式奖励关闭\n%s" % [PORT,message])
	if not net.connected and not net.connecting:
		controller.button("创建双人房间",func():
			var error: int=net.host(PORT)
			show_lobby("等待队友加入" if error==OK else "创建失败：%d" % error))
		var address:=LineEdit.new();address.placeholder_text="房主局域网 IP（同机测试填 127.0.0.1）"
		controller.column.add_child(address)
		controller.button("加入房间",func():
			var error: int=net.join(address.text,PORT)
			show_lobby("连接中…" if error==OK else "地址无效或连接失败"))
	elif authority():
		if guest>1:controller.button("两人已就绪 · 开始共同试炼",begin_run)
		else:controller.button("刷新队伍",func():show_lobby("等待队友加入"))
	else:controller.button("刷新队伍",func():show_lobby("已连接，等待房主开始"))
	controller.button("退出组队",func():abort("已退出组队"))

func begin_run(seed_override:=0) -> void:
	if not authority() or guest<=1 or not run_id.is_empty():return
	var seed_number:=seed_override if seed_override!=0 else int(Time.get_unix_time_from_system())
	trials.clear()
	for slot in 2:
		var trial=Trial.new()
		if not trial.initialize(chosen_school() if slot==0 else guest_school,seed_number+slot*71):return
		trial.player_slot=slot;trial.party_size=2;trials.append(trial)
	run_id=trials[0].run_id
	trials[1].run_id=run_id;trials[0].teammate=trials[1]
	owners={"P0":1,"P1":guest}
	publish_menu()

func contexts() -> Array:return trials.map(func(trial):return trial.snapshot())
func publish_menu() -> void:
	if closed:return
	menu_version+=1
	net.publish({"op":"menu","run":run_id,"version":menu_version,"contexts":contexts(),"owners":owners,"choices":choices,"acks":acknowledgements,"playback_speed":playback_speed})
	controller.busy=false
	show_menu()

func read_contexts(data: Array) -> bool:
	if data.size()!=2:return false
	var rebuilt: Array=[]
	for record in data:
		var trial=Trial.new()
		if not trial.import_snapshot(record,str(record.school)):return false
		# Mid-battle snapshots here are host-issued setup, not resumable disk saves.
		trial.state=str(record.state)
		rebuilt.append(trial)
	trials=rebuilt;trials[0].teammate=trials[1]
	return true

func show_menu() -> void:
	if trials.size()!=2 or closed:return
	controller.trial=trials[local_slot()]
	controller.render_run()

func show_removals() -> void:
	show_menu()

func choose(kind: String,arg: Variant={}) -> void:
	if trials.size()!=2 or not pending_operation.is_empty():return
	var args: Dictionary=normalize_args(kind,arg)
	operation_serial+=1
	pending_operation="%d:%d:%d" % [net.multiplayer.get_unique_id(),Time.get_ticks_usec(),operation_serial]
	controller.busy=true
	net.send_request({"op":"choice","run":run_id,"node":trials[0].node_index,"kind":kind,"args":args,"operation":pending_operation,"revision":trials[local_slot()].revision})

func receive_request(peer: int,data: Dictionary) -> void:
	if not authority() or closed:return
	var op:=str(data.get("op",""))
	if op=="hello" and run_id.is_empty() and peer>1 and guest in [0,peer]:
		var school:=str(data.get("school",""))
		if school not in ["fire","ice","storm","myth","life","death","balance"]:return
		guest=peer;guest_school=school;show_lobby("队友已加入："+school);return
	if str(data.get("run",""))!=run_id or run_id.is_empty() or peer not in [1,guest]:rejected_commands+=1;return
	if op=="leave":abort("队伍已解散");return
	if int(data.get("node",-1))!=trials[0].node_index:rejected_commands+=1;return
	if op=="moved":
		if transition_node<0 or int(data.get("target",-1))!=transition_node:return
		if not bool(data.get("ok",false)):cancel_transition("楼层准备失败，节点未推进，可重试");return
		transition_ready[peer]=true
		if transition_ready.size()==2:
			for member in trials:member.command("advance",{},"advance:%d" % member.node_index,member.revision)
			transition_node=-1;transition_started=0;transition_ready.clear();choices.clear();controller.busy=false;publish_menu()
		return
	if op=="loaded":
		if not is_instance_valid(stage) or not controller.in_battle:return
		ready_peers[peer]=true
		if ready_peers.size()==2:
			battle_ready=true;load_started=0
			net.publish({"op":"ready","run":run_id})
			stage.shell.network_planning()
	elif op=="command" and is_instance_valid(stage):
		if stage.shell.accept_command(peer,data):accepted_commands+=1
		else:rejected_commands+=1
	elif op=="presented":presented[peer]=int(data.get("round",-1))
	elif op=="choice":
		if str(data.get("operation","")).is_empty() or not data.get("args",{}) is Dictionary:rejected_commands+=1;return
		apply_choice(0 if peer==1 else 1,str(data.get("kind","")),data.get("args",{}),str(data.operation),int(data.get("revision",-1)))

func apply_choice(slot: int,kind: String,arg: Variant,operation_id: String="",expected_revision: int=-1) -> void:
	if controller.in_battle or transition_node>=0:return
	var trial: RefCounted=trials[slot]
	var args:=normalize_args(kind,arg)
	var operation:=operation_id if not operation_id.is_empty() else "internal:%d:%d:%s" % [slot,trial.revision,kind]
	var accepted:=false
	if kind=="speed":
		accepted=slot==0 and choices.is_empty() and trial.state=="SAFE" and float(args.get("speed",0)) in [1.0,1.5,2.0]
		if accepted:playback_speed=float(args.speed)
	elif kind=="unready":
		accepted=choices.has(str(slot)) and trial.state=="SAFE"
		if accepted:choices.erase(str(slot))
	elif kind=="ready":
		accepted=trial.state=="SAFE" and (expected_revision<0 or expected_revision==trial.revision)
		if accepted:choices[str(slot)]="ready"
	elif kind=="complete":accepted=trial.state=="NODE_COMPLETE"
	elif not choices.has(str(slot)):
		if kind=="route":
			if slot==0 and choices.is_empty():
				var previous_revision: int=trial.revision
				accepted=trial.command(kind,args,operation,expected_revision)
				if accepted and trial.revision!=previous_revision:trials[1].routes[str(trial.node_index)]=str(args.route);trials[1].revision+=1
		else:accepted=trial.command(kind,args,operation,expected_revision)
	acknowledgements[str(slot)]={"operation":operation_id,"accepted":accepted}
	if not accepted:rejected_commands+=1
	controller.busy=false;pending_operation=""
	if choices.size()==2:
		choices.clear();begin_battle();return
	if trials.all(func(member):return member.state=="NODE_COMPLETE"):
		publish_menu();begin_transition();return
	publish_menu()

func begin_battle() -> void:
	ready_peers.clear();battle_ready=false;presented.clear();load_started=Time.get_ticks_msec()
	for trial in trials:
		if not trial.command("battle",{},"battle:%d" % trial.node_index,trial.revision):abort("开战状态校验失败");return
	net.publish({"op":"battle","run":run_id,"contexts":contexts()})
	build_battle()

func build_battle() -> void:
	controller.panel.hide()
	var floor_index: int=mini(2,int(trials[0].node_index/3))
	if tower.current_room!=floor_index and not await tower.move_to(floor_index):abort("楼层准备失败，本局中止");return
	controller.trial=trials[local_slot()]
	controller.trial.state="SAFE" # The controller validates the local launch transition.
	controller.busy=false
	controller.start_battle()
	if not controller.in_battle:abort("战斗场地未准备好");return
	for trial in trials:trial.state="BATTLE"
	stage.shell.presentation_director.playback_speed=playback_speed
	if test_accelerated:stage.entrance_scale=0.02;stage.shell.presentation_director.test_duration_scale=0.02
	await stage.entrance_finished
	net.send_request({"op":"loaded","run":run_id,"node":trials[0].node_index})

func command(op: String,args: Dictionary={}) -> void:
	if not is_instance_valid(stage) or stage.shell.active_actor==null:return
	var data:=args.duplicate(true)
	data.merge({"op":"command","command":op,"run":run_id,"node":trials[0].node_index,"round":stage.engine.state.round_index,"actor":str(stage.shell.active_actor.id)})
	net.send_request(data)

func broadcast_step(kind: String,extra: Dictionary={}) -> void:
	sequence+=1
	var compact:=kind in ["turn","action"]
	var data: Dictionary={"op":"step","run":run_id,"seq":sequence,"kind":kind,"state":Wire.pack_view(stage.engine.state) if compact else Wire.pack(stage.engine.state),"compact":compact}
	data["telegraph"]=str(stage.engine.telegraph_text)
	data["trial_info"]=stage.engine.trial_info()
	data.merge(extra,true);net.publish(data)

func receive(data: Dictionary) -> void:
	if authority() or closed:return
	var op:=str(data.get("op",""))
	if op=="menu":
		if not run_id.is_empty() and str(data.get("run",""))!=run_id:return
		if int(data.get("version",0))<=received_menu_version:return
		received_menu_version=int(data.get("version",0))
		run_id=str(data.run);owners=data.owners;choices=data.choices
		playback_speed=float(data.get("playback_speed",1.0))
		var ack: Dictionary=data.get("acks",{}).get(str(local_slot()),{})
		if not pending_operation.is_empty() and str(ack.get("operation",""))==pending_operation:
			pending_operation="";controller.busy=false
			controller.last_message="" if bool(ack.get("accepted",false)) else "操作已过期或不可用，未消耗资源。"
		if read_contexts(data.contexts):
			if transition_node>=0 and trials[0].node_index==transition_node:
				transition_node=-1;transition_started=0;controller.busy=false
			show_menu()
		return
	if str(data.get("run",""))!=run_id:return
	if op=="transition":
		transition_node=int(data.get("target",-1));transition_started=Time.get_ticks_msec();prepare_transition();return
	if op=="transition_cancel":
		transition_node=-1;transition_started=0;controller.busy=true
		await tower.move_to(mini(2,int(trials[0].node_index/3)))
		controller.busy=false;controller.last_message=str(data.get("message","转场取消"));show_menu();return
	if op=="battle":
		pending_operation="";controller.busy=false;load_started=Time.get_ticks_msec()
		battle_ready=false
		if read_contexts(data.contexts):build_battle()
	elif op=="ready":battle_ready=true;load_started=0
	elif op=="step":
		if int(data.seq)<=received_sequence:return
		received_sequence=int(data.seq);packets.append(data);consume()
	elif op=="result":packets.append(data);consume()
	elif op=="abort":abort(str(data.get("message","队伍结束")))

func consume() -> void:
	if consuming:return
	consuming=true
	while not packets.is_empty() and not closed:
		var packet: Dictionary=packets.pop_front()
		if str(packet.op)=="result":
			await remove_stage()
			choices.clear();pending_operation="";controller.busy=false
			if read_contexts(packet.contexts):show_menu()
		elif is_instance_valid(stage):
			stage.engine.telegraph_text=str(packet.get("telegraph",""))
			stage.engine.network_trial_info=str(packet.get("trial_info",""))
			await stage.shell.play_packet(packet)
	consuming=false

func presentation_complete(round_index: int) -> void:
	net.send_request({"op":"presented","run":run_id,"node":trials[0].node_index,"round":round_index})

func wait_for_presentations(round_index: int) -> void:
	broadcast_step("round_end",{"round":round_index})
	var deadline:=Time.get_ticks_msec()+45000
	while not closed and int(presented.get(guest,-1))<round_index and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	if not closed and int(presented.get(guest,-1))<round_index:abort("队友演出同步超时，本局中止")

func finish(_winner: int) -> void:
	if not authority() or closed:return
	for trial in trials:
		if not trial.settle(stage.engine):abort("重复或无效结算已拒绝");return
	net.publish({"op":"result","run":run_id,"contexts":contexts()})
	await remove_stage()
	show_menu()

func remove_stage() -> void:
	battle_ready=false;load_started=0
	if is_instance_valid(stage):stage.queue_free()
	stage=null;controller.stage=null;controller.in_battle=false;controller.busy=false
	await get_tree().process_frame
	tower.world.player.show();tower.world.camera.current=true;tower.reset_to_safe()

func request_flee() -> void:
	if controller.in_battle:
		var dialog:=ConfirmationDialog.new()
		dialog.title="放弃双人试炼？"
		dialog.dialog_text="离开会结束两人的本局。不会发放正式物品。"
		tower.layer.add_child(dialog)
		dialog.confirmed.connect(func():send_leave();dialog.queue_free())
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered()
	else:send_leave()

func send_leave() -> void:
	net.send_request({"op":"leave","run":run_id,"node":trials[0].node_index if not trials.is_empty() else -1})

func abort(message: String) -> void:
	if closed:return
	closed=true
	if net.connected and authority():net.publish({"op":"abort","run":run_id,"message":message})
	for trial in trials:
		if trial.state not in ["SUCCESS","FAILED"]:trial.state="ABANDONED"
	await remove_stage()
	net.disconnect_town()
	controller.running=false;controller.party_session=null;controller.panel.hide()
	trials.clear();owners.clear();run_id="";guest=0;choices.clear();packets.clear()
	sequence=0;received_sequence=0;received_menu_version=-1;menu_version=0
	load_started=0;transition_started=0;transition_node=-1;pending_operation="";acknowledgements.clear()
	controller.preparing=false;controller.busy=false
	await tower.leave()
	controller.last_message=message
	controller.clear_menu("双人试炼结束")
	controller.label(message)
	controller.button("关闭",func():controller.panel.hide();tower.world.input_suspended=false)
	print("TOWER_PARTY_END ",message)

func chosen_school() -> String:
	return controller.selected_school if not controller.selected_school.is_empty() else str(tower.world.avatar.school_id)

func normalize_args(kind: String, arg: Variant) -> Dictionary:
	if arg is Dictionary:return arg
	if kind=="study":return {"school":str(arg)}
	if kind=="route":return {"route":str(arg)}
	if kind=="upgrade":return {"instance":int(arg),"path":"power"}
	return {"id":str(arg)}

func waiting_for_partner() -> bool:
	return choices.has(str(local_slot())) or (trials[local_slot()].state=="NODE_COMPLETE" and not trials.all(func(member):return member.state=="NODE_COMPLETE"))

func can_change_route() -> bool:return authority() and choices.is_empty()

func partner_status() -> String:
	var other: RefCounted=trials[1-local_slot()]
	return "队友：%s · HP %d/%d · %s" % [other.school,other.current_hp(),other.main_max_hp(),{"SAFE":"等待战斗确认","REWARD":"选择卡牌","RELIC":"选择遗物","STUDY":"选择研习","STUDY_CARD":"研习选牌","STUDY_REMOVE":"整理牌组","SHOP":"购物中","REST":"休整中","NODE_COMPLETE":"已完成"}.get(other.state,other.state)]

func begin_transition() -> void:
	if not authority() or transition_node>=0 or not trials.all(func(member):return member.state=="NODE_COMPLETE"):return
	transition_node=int(trials[0].node_index)+1;transition_ready.clear();transition_started=Time.get_ticks_msec()
	net.publish({"op":"transition","run":run_id,"target":transition_node})
	prepare_transition()

func prepare_transition() -> void:
	controller.busy=true
	var target:=transition_node
	var floor_index:=mini(2,int(target/3))
	var ok: bool=tower.current_room==floor_index or await tower.move_to(floor_index)
	if closed or target!=transition_node:return
	net.send_request({"op":"moved","run":run_id,"node":trials[0].node_index,"target":target,"ok":ok})

func cancel_transition(message: String) -> void:
	if transition_node<0:return
	transition_node=-1;transition_started=0;transition_ready.clear()
	if authority():net.publish({"op":"transition_cancel","run":run_id,"message":message})
	await tower.move_to(mini(2,int(trials[0].node_index/3)))
	controller.busy=false;controller.last_message=message;show_menu()
