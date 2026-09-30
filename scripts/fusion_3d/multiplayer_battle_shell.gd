extends "res://scripts/fusion_3d/battle_shell_bridge.gd"
const Wire=preload("res://scripts/fusion_3d/battle_wire.gd")
var resolving_network:=false
const PLANNING_SECONDS:=30.0
var planning_deadline:=0
var planning_round:=-1
var team_choices: Label
var countdown: Label
var flee_button: Button
var school_picker: Button
func planning_remaining() -> float:
	return maxf(0.0,float(planning_deadline-Time.get_ticks_msec())/1000.0)
func _process(delta: float) -> void:
	super._process(delta)
	top_bar.hide()
	_refresh_charge_control()
	if is_instance_valid(flee_button):
		flee_button.visible=session().active_local and not stage.entering
		flee_button.disabled=ui_state not in [UIState.PLANNING,UIState.CARD_SELECTED,UIState.TARGETING] or resolving_network
	if session().has_method("planning_blocked") and session().planning_blocked():
		if is_instance_valid(countdown):countdown.text="30"
		return
	if engine==null or stage.entering or resolving_network or engine.state.phase!=BattleStateV2.Phase.PLANNING or planning_round!=engine.state.round_index:return
	phase_label.text=("第 %d 回合 · " % ceili(engine.state.round_index/2.0)+("红方" if engine.state.active_team==0 else "蓝方")+"规划阶段" if engine.state.pvp else "规划阶段")+" · %d 秒 · 右键取消后可重选" % ceili(planning_remaining())
	if engine.state.pvp and not _can_plan():prompt_label.text="对方规划中 · 可以弃牌和抽取宝藏卡"
	if _local_player_downed():
		prompt_label.text="你已倒下 · 自动跳过行动 · 队友继续战斗"
		phase_label.text="你已倒下 · 本回合自动跳过"
	if is_instance_valid(countdown):
		countdown.visible=session().active_local and not _local_player_downed()
		countdown.text=str(ceili(planning_remaining()))
		countdown.modulate=Color("ff796e") if planning_remaining()<=10.0 else Color("ffe4a0")
	if session().authority() and planning_remaining()<=0.0:_expire_planning()
func _expire_planning() -> void:
	if session().has_method("planning_blocked") and session().planning_blocked():return
	if resolving_network or engine.state.phase!=BattleStateV2.Phase.PLANNING:return
	for unit in engine.state.living_units(engine.state.active_team if engine.state.pvp else 0):
		if engine.state.actions.has(unit.id):continue
		if int(session().owners.get(str(unit.id),0))==0:engine.queue_action(ai.choose_action(engine,unit))
		else:engine.queue_pass(unit.id)
	_plan_enemies_and_resolve()
func _input(event: InputEvent) -> void:
	# The production island menu owns the authenticated F10 LAN entry.
	if event is InputEventKey and event.keycode==KEY_F10:return
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and engine!=null and not stage.entering and not resolving_network and engine.state.phase==BattleStateV2.Phase.PLANNING:
		if active_actor!=null and engine.state.actions.has(active_actor.id):
			session().command("cancel");get_viewport().set_input_as_handled();return
	super._input(event)
func _show_team_choices() -> void:
	if not is_instance_valid(team_choices):return
	var lines: Array[String]=[]
	for unit in engine.state.team_units(_local_team()):
		var prefix: String=str(unit.slot+1)+"号 · "+_unit_title(unit)+(" [AI]" if int(session().owners.get(str(unit.id),0))==0 else "")
		var intent: ActionIntentV2=engine.state.actions.get(unit.id)
		var before := lines.size()
		if not unit.alive:lines.append(prefix+" · 已倒下")
		elif intent==null:lines.append(prefix+" · 选择中")
		elif intent.pass_action:lines.append(prefix+" · 跳过 / 蓄能")
		else:
			var card:=engine.card_in_hand(unit,intent.card_instance_id)
			var targets: Array[String]=[]
			for id in intent.target_ids:
				var target := engine.state.unit_by_id(id)
				if target!=null:targets.append(("敌" if target.team!=_local_team() else "友")+str(target.slot+1)+" · "+_unit_title(target))
			var definition:=card.definition if card!=null else content.card(intent.card_definition_id)
			lines.append(prefix+" · "+(Locale.text(str(definition.name_key)) if definition!=null else "法术")+" → "+" / ".join(targets))
		if unit_views.has(unit.id) and lines.size() > before:
			var plate = unit_views[unit.id].nameplate
			if unit.alive and intent == null: plate.show_choosing(Color("b6d8e8"))
			plate.set_meta("public_action_detail", "\n" + lines[-1])
			plate.tooltip_text = plate._display_name() + "\n" + lines[-1]
	team_choices.text="\n".join(lines)
	team_choices.hide()
func _unit_title(unit: BattleUnitStateV2) -> String:
	return unit_views[unit.id].nameplate._display_name() if unit_views.has(unit.id) else str(unit.name_key)
func _sync_action_token(unit_id: StringName, view: Control) -> void:
	super._sync_action_token(unit_id, view)
	var unit := engine.state.unit_by_id(unit_id)
	if unit != null and unit.alive and unit.team == _local_team() and not action_token_cache.has(unit_id) and engine.state.phase == BattleStateV2.Phase.PLANNING:
		view.show_choosing_token()
func _rebuild_action_tokens() -> void:
	action_token_cache.clear()
	for unit in engine.state.team_units(_local_team()):
		var intent: ActionIntentV2=engine.state.actions.get(unit.id)
		if intent==null:continue
		var payload: Dictionary={"unit_id":str(unit.id),"pass":intent.pass_action,"targets":Array(intent.target_ids)}
		if not intent.pass_action:
			var card:=engine.card_in_hand(unit,intent.card_instance_id)
			if card!=null:payload.card_id=str(card.card_id())
			elif intent.card_definition_id!=&"":payload.card_id=str(intent.card_definition_id)
		_cache_action_token(payload)

func session() -> Node:return stage.shared_session
func _local_team() -> int:return session().local_team() if session().has_method("local_team") else 0
func _can_plan() -> bool:return not engine.state.pvp or _local_team()==engine.state.active_team
func _ready() -> void:
	super._ready()
	for connection in charge_option.item_selected.get_connections():charge_option.item_selected.disconnect(connection.callable)
	charge_option.item_selected.connect(func(index: int):session().command("charge",{"school":["fire","ice","storm","myth","life","death","balance"][index]}))
	team_choices=Label.new();team_choices.position=Vector2(620,74)
	team_choices.add_theme_font_size_override("font_size",18)
	team_choices.add_theme_color_override("font_shadow_color",Color.BLACK)
	team_choices.add_theme_constant_override("shadow_offset_x",2);team_choices.add_theme_constant_override("shadow_offset_y",2)
	team_choices.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(team_choices)
	countdown=Label.new();countdown.text="30";countdown.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	countdown.add_theme_font_size_override("font_size",82)
	countdown.add_theme_color_override("font_shadow_color",Color("102236"))
	countdown.add_theme_constant_override("shadow_offset_x",3);countdown.add_theme_constant_override("shadow_offset_y",3)
	countdown.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(countdown)
	countdown.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	countdown.offset_left=-205;countdown.offset_right=-45;countdown.offset_top=-245;countdown.offset_bottom=-130
	countdown.hide()
	deck_button.hide() # Configure the loadout before entering; no mid-battle deck rerolls.
	top_bar.hide()
	flee_button=Button.new();flee_button.text="FLEE · 逃跑";add_child(flee_button)
	TrialArt.apply_button(flee_button,true)
	flee_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	flee_button.offset_left=40;flee_button.offset_right=220;flee_button.offset_top=-305;flee_button.offset_bottom=-259
	flee_button.tooltip_text="规划阶段逃离战斗，返回安全位置；不获得胜利奖励。"
	flee_button.pressed.connect(func():session().request_flee())
	if stage.trial_context!=null:
		var reorganize:=Button.new();reorganize.text="整备（消耗本轮行动）";add_child(reorganize)
		TrialArt.apply_button(reorganize)
		reorganize.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		reorganize.offset_left=1060;reorganize.offset_right=1370;reorganize.offset_top=202;reorganize.offset_bottom=246
		flee_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		flee_button.offset_left=1060;flee_button.offset_right=1370;flee_button.offset_top=150;flee_button.offset_bottom=194
		reorganize.pressed.connect(func():session().command("reorganize"))
	var compact_skin = preload("res://scenes/battle_v2/ui/compact_battle_skin.gd")
	school_picker=preload("res://scenes/battle_v2/ui/compact_school_picker.gd").new()
	school_picker.source=charge_option
	add_child(school_picker)
	charge_option.hide()
	_refresh_charge_control()
	compact_skin.clock(countdown)
	planning_ui.attach_multiplayer(countdown,school_picker,flee_button)
	pass_button.text="PASS · 跳过"
	draw_button.text="DRAW · 抽牌"
	speed_option.disabled=true
	speed_option.tooltip_text="联机演出统一速度"
func _apply_saved_decks() -> void:
	if session().has_method("configure_engine"):session().configure_engine(engine)
	elif session().authority():super._apply_saved_decks()
func _begin_player_planning() -> void:
	if stage.engine==null or stage.entering:return
	network_planning()
func _next_unplanned_player() -> BattleUnitStateV2:
	for unit in engine.state.team_units(_local_team()):
		if unit.alive and session().mine(unit.id):return unit
	return null
func _local_player_downed() -> bool:
	if not session().active_local or engine==null:return false
	var has_player:=false
	for unit in engine.state.team_units(_local_team()):
		if not session().mine(unit.id):continue
		has_player=true
		if unit.alive:return false
	return has_player
func network_planning() -> void:
	if stage.entering or resolving_network:return
	if session().has_method("configure_engine") and not session().battle_ready:return
	if planning_round!=engine.state.round_index:
		planning_round=engine.state.round_index
		if session().authority():planning_deadline=Time.get_ticks_msec()+int(PLANNING_SECONDS*1000)
	var previous_card := selected_card.instance_id if selected_card!=null else -1
	selected_card=null;selected_target_id=&"";valid_target_ids.clear()
	target_arrow.hide_arrow()
	hand.set_resolving(false)
	active_actor=_next_unplanned_player()
	_rebuild_action_tokens()
	_set_ui_state(UIState.PLANNING)
	session().update_roster()
	active_actor=_next_unplanned_player()
	if active_actor!=null:hand.show_hand(active_actor,engine)
	else:hand.clear_hand()
	hand.set_selected(-1,false)
	if active_actor!=null and engine.state.actions.has(active_actor.id):
		var chosen: ActionIntentV2=engine.state.actions[active_actor.id]
		if not chosen.pass_action:hand.set_selected(chosen.card_instance_id,false,true)
	_refresh_all()
	if active_actor==null:prompt_label.text="等待其他玩家确认行动" if session().active_local else "观战中 · 可在城镇界面加入"
	elif engine.state.actions.has(active_actor.id):prompt_label.text="已选好行动 · 等待队友 · 右键取消后可重选"
	var slots: Array=[]
	for id in session().owners:
		if session().mine(StringName(id)):slots.append(("蓝" if str(id).begins_with("E") else "红")+str(int(str(id).substr(1))+1))
	phase_label.text+=" · 控制 "+" / ".join(slots)
	_show_team_choices()
	if active_actor!=null and not engine.state.actions.has(active_actor.id) and previous_card>=0:
		var card := engine.card_in_hand(active_actor,previous_card)
		if card!=null:_on_card_selected(card)
	if session().authority():
		session().broadcast_step("planning",{"remaining":planning_remaining()})
		var complete:=true
		for unit in engine.state.living_units(engine.state.active_team if engine.state.pvp else 0):
			if int(session().owners.get(str(unit.id),0))>0 and not engine.state.actions.has(unit.id):complete=false
		if complete:_expire_planning()

func _set_ui_state(value: UIState) -> void:
	super._set_ui_state(value)
	_refresh_charge_control()
	deck_button.hide()
	if is_instance_valid(countdown):countdown.visible=value in [UIState.PLANNING,UIState.CARD_SELECTED,UIState.TARGETING] and session().active_local
func _on_deck_pressed() -> void:pass

func _on_unit_clicked(id: StringName) -> void:
	if ui_state==UIState.PLANNING:
		if not session().mine(id):return
		var unit:=engine.state.unit_by_id(id)
		if unit!=null and unit.alive:active_actor=unit;hand.show_hand(unit,engine);_refresh_all();return
	super._on_unit_clicked(id)
func _lock_selected_action() -> void:
	if not _can_plan():return
	if active_actor!=null and selected_card!=null:
		session().command("cast",{"card":selected_card.instance_id,"targets":[selected_target_id]})
func _on_pass_pressed() -> void:
	if _can_plan():session().command("pass")
func _on_draw_pressed() -> void:session().command("draw")
func _on_card_discard_requested(card: CardInstanceV2) -> void:
	if card==null or stage.entering or resolving_network:return
	if ui_state in [UIState.CARD_SELECTED,UIState.TARGETING] or hand.is_dragging_card():
		hand.cancel_drag()
		_cancel_selection()
		return
	if active_actor!=null and engine.state.actions.has(active_actor.id):
		session().command("cancel")
		return
	if ui_state==UIState.PLANNING:session().command("discard",{"card":card.instance_id})
func _on_deck_apply_requested(counts: Dictionary) -> void:
	session().command("deck",{"counts":counts})
	deck_builder.close()
func _on_card_selected(card: CardInstanceV2) -> void:
	if not _can_plan():return
	if active_actor!=null and engine.state.actions.has(active_actor.id):
		prompt_label.text="已选好行动 · 右键取消后可重新选择"
		return
	if fusion_mode:
		if active_actor==null or ui_state==UIState.RESOLVING:return
		if fusion_first<0:
			fusion_first=card.instance_id;hand.set_selected(fusion_first,true)
		else:
			session().command("fuse",{"first":fusion_first,"second":card.instance_id})
			fusion_first=-1
		return
	super._on_card_selected(card)
func auto_plan_players() -> void:
	if _can_plan():session().command("auto")
func _schedule_battle_finished(_delay: float=0.75) -> void:pass
func _cancel_selection() -> void:
	if ui_state==UIState.BATTLE_END:return
	super._cancel_selection()
func accept_command(peer: int,data: Dictionary) -> bool:
	if session().has_method("planning_blocked") and session().planning_blocked():return false
	if not session().authority() or stage.entering or resolving_network or engine.state.phase!=BattleStateV2.Phase.PLANNING:return false
	if int(data.get("round",-1))!=engine.state.round_index:return false
	var id:=StringName(str(data.get("actor","")))
	var unit:=engine.state.unit_by_id(id)
	if unit==null or not unit.alive or int(session().owners.get(str(id),0))!=peer or peer<=0:return false
	var command:=str(data.get("command",""))
	if engine.state.pvp and unit.team!=engine.state.active_team and command not in ["draw","discard","charge"]:return false
	if planning_round!=engine.state.round_index or planning_remaining()<=0.0:return false
	if command=="cancel":
		if not engine.state.actions.has(id):return false
		engine.state.actions.erase(id);unit.planned_action=null
		action_token_cache.clear();network_planning();return true
	if engine.state.actions.has(id):return false
	var accepted:=false
	match command:
		"pass":accepted=engine.queue_pass(id)
		"reorganize":
			if stage.trial_context!=null:accepted=engine.request_reorganize(unit)
		"cast":
			var targets: Array[StringName]=[]
			for target in data.get("targets",[]):targets.append(StringName(str(target)))
			accepted=engine.queue_action(ActionIntentV2.cast(id,int(data.get("card",-1)),targets))
		"draw":accepted=engine.draw_one_treasure(id)!=null
		"discard":accepted=engine.discard_for_treasure(id,int(data.get("card",-1)))
		"fuse":accepted=engine.fuse_cards(id,int(data.get("first",-1)),int(data.get("second",-1)))!=null
		"charge":
			var school:=str(data.get("school",""))
			if school in ["fire","ice","storm","myth","life","death","balance"]:
				engine.set_next_charge(id,StringName(school));accepted=true
		"deck":return false
		"auto":
			for player in engine.state.living_units(engine.state.active_team if engine.state.pvp else 0):
				if int(session().owners.get(str(player.id),0))==peer and not engine.state.actions.has(player.id):
					if stage.trial_context!=null and player.deck.hand.is_empty() and player.deck.draw_pile.is_empty() and engine.request_reorganize(player):continue
					engine.queue_action(ai.choose_action(engine,player))
			accepted=true
	if accepted:network_planning()
	return accepted
func _plan_enemies_and_resolve() -> void:
	if not session().authority() or resolving_network:return
	resolving_network=true
	if not engine.state.pvp:
		for enemy in engine.state.living_units(1):engine.queue_action(ai.choose_action(engine,enemy))
	engine.begin_resolution()
	for actor in engine.turn_manager.resolution_order(engine.state):
		if not actor.alive or not engine.state.actions.has(actor.id):continue
		var before: Dictionary=Wire.pack_view(engine.state)
		var turn_events:=engine.begin_actor_turn(actor)
		var turn: Dictionary={"before":before,"events":Wire.pack(turn_events),"actor":str(actor.id)}
		session().broadcast_step("turn",turn)
		turn.merge({"kind":"turn","state":Wire.pack_view(engine.state),"compact":true})
		await play_packet(turn)
		if engine.state.phase==BattleStateV2.Phase.FINISHED:break
		if not actor.alive:continue
		var intent: ActionIntentV2=engine.state.actions.get(actor.id)
		var spell: CardDefinitionV2
		var target_ids: Array[StringName]=[]
		if intent!=null and not intent.pass_action:
			var card:=engine.card_in_hand(actor,intent.card_instance_id)
			if card!=null:
				spell=card.definition
				for target in engine.target_resolver.resolve_selected(engine.state,actor,spell,intent.target_ids):target_ids.append(target.id)
		before=Wire.pack_view(engine.state)
		var events:=engine.resolve_actor_action(actor)
		var action: Dictionary={"before":before,"events":Wire.pack(events),"actor":str(actor.id),"card":str(spell.id) if spell!=null else "","targets":target_ids}
		session().broadcast_step("action",action)
		action.merge({"kind":"action","state":Wire.pack_view(engine.state),"compact":true})
		await play_packet(action)
		if engine.state.phase==BattleStateV2.Phase.FINISHED:break
	engine.end_resolution()
	if session().has_method("wait_for_presentations"):
		await session().wait_for_presentations(engine.state.round_index)
		if not is_instance_valid(stage) or not is_instance_valid(session().stage):return
	if engine.state.phase==BattleStateV2.Phase.FINISHED:
		session().broadcast_step("finished")
		await get_tree().create_timer(1.5).timeout
		session().finish(engine.state.winner_team)
		return
	engine.start_next_round()
	resolving_network=false
	action_token_cache.clear();resolved_action_ids.clear()
	await session().admit_pending()
	network_planning()

func sync_roster_views() -> void:
	for unit in engine.state.units:
		if unit_views.has(unit.id):continue
		var view:=UnitViewScript.new()
		view.clicked.connect(_on_unit_clicked);unit_layer.add_child(view)
		view.bind(unit,slot_configs[unit.id],content.characters.get(unit.character_id,{}))
		view.detach_nameplate_to(hud_layer);unit_views[unit.id]=view
	refresh_roster_skin()

func play_packet(packet: Dictionary) -> void:
	var kind:=str(packet.kind)
	if kind=="round_end":
		Wire.apply(engine,packet.state)
		prompt_label.text="本轮动画播放完毕 · 等待队友"
		if is_instance_valid(countdown):countdown.hide()
		session().presentation_complete(int(packet.round))
		return
	if kind=="planning":
		if bool(packet.get("planning_delta",false)):
			if not Wire.apply_planning_delta(engine,packet.state):return
		else:Wire.apply(engine,packet.state)
		planning_deadline=Time.get_ticks_msec()+int(clampf(float(packet.get("remaining",PLANNING_SECONDS)),0,PLANNING_SECONDS)*1000)
		stage.sync_world_state()
		network_planning()
		return
	if kind=="finished":
		Wire.apply(engine,packet.state)
		_set_ui_state(UIState.BATTLE_END);hand.clear_hand();_refresh_all()
		if engine.state.pvp:prompt_label.text="胜利" if engine.state.winner_team==_local_team() else "失败"
		return
	# Reconstruct the pre-impact visual state, including on a newly connected spectator.
	var compact:=bool(packet.get("compact",false))
	if compact:Wire.apply_view(engine,packet.before)
	else:Wire.apply(engine,packet.before)
	var frozen: Array[Control]=[]
	var hp_before: Dictionary={}
	for view in unit_views.values():
		view.set_presentation_statuses(view.unit.statuses.duplicate())
		view.nameplate.hold_presentation_hp(view.unit.hp)
		view.nameplate.hold_presentation_resources()
		hp_before[view.unit.id]=view.unit.hp
		frozen.append(view)
	if compact:Wire.apply_view(engine,packet.state)
	else:Wire.apply(engine,packet.state)
	var events: Array[BattleEventV2]=[]
	events.assign(Wire.unpack(packet.events,content))
	session().settle_treasures(events)
	active_actor=null
	_set_ui_state(UIState.RESOLVING);hand.set_resolving(true)
	resolving_actor_id=StringName(packet.actor)
	_refresh_all()
	if kind=="turn":await presentation_director.play_turn_start_events(events,unit_views,frozen)
	else:
		var card:=content.card(StringName(packet.card)) if not str(packet.card).is_empty() else null
		var targets: Array[Control]=[]
		for id in packet.targets:
			if unit_views.has(StringName(id)):targets.append(unit_views[StringName(id)])
		if card!=null:await presentation_director.play_action(unit_views[StringName(packet.actor)],targets,card,events,hp_before,frozen)
		else:
			for view in frozen:view.clear_presentation_statuses()
			await get_tree().create_timer(0.22).timeout
		resolved_action_ids.append(StringName(packet.actor))
	for view in unit_views.values():
		view.nameplate.release_presentation_hp()
		view.nameplate.release_presentation_resources()
	stage.sync_world_state()
	_refresh_all()


func _refresh_all() -> void:
	super._refresh_all()
	# Disabled book actions remain readable; theme color conveys availability.
	draw_button.modulate=Color.WHITE
	_refresh_charge_control()
	_refresh_hand_availability()
	if engine!=null and engine.state.pvp:
		pass_button.disabled=not _can_plan()
		if is_instance_valid(ai_button):ai_button.disabled=not _can_plan() or ui_state in [UIState.RESOLVING,UIState.BATTLE_END]

func _refresh_charge_control() -> void:
	if not is_instance_valid(charge_option):return
	var can_show: bool = session().active_local and not stage.entering
	charge_option.hide()
	charge_option.disabled=active_actor==null or not can_show or resolving_network or ui_state not in [UIState.PLANNING,UIState.CARD_SELECTED,UIState.TARGETING]
	charge_option.get_popup().hide()
	if is_instance_valid(school_picker):
		school_picker.visible=can_show
		school_picker.sync()

func _refresh_hand_availability() -> void:
	if engine==null or not is_instance_valid(hand):return
	# Visual hint only: the hand must retain hover and right-click discard input.
	hand.modulate=Color(0.76,0.78,0.82,hand.modulate.a) if engine.state.pvp and not _can_plan() else Color(1,1,1,hand.modulate.a)

func _cache_action_token(payload: Dictionary) -> void:
	if not engine.state.pvp:
		super._cache_action_token(payload);return
	var unit:=engine.state.unit_by_id(StringName(str(payload.get("unit_id",""))))
	if unit==null or unit.team!=_local_team():return
	var previous:=show_enemy_planned_actions
	show_enemy_planned_actions=true
	super._cache_action_token(payload)
	show_enemy_planned_actions=previous

