extends "res://scenes/battle_v2/battle_scene_shell.gd"
## Reuse production 2D HUD/hand/targeting/deck flow; project its hit proxies onto 3D actors.
const TrialArt=preload("res://scripts/tower_v01/trial_ui_art.gd")
var stage: Node3D
var fusion_mode := false
var fusion_first := -1
var charge_option: OptionButton
var ai_button: Button
var quick_test := false
var layout_viewport:=Vector2(-1,-1)
var layout_unit_count:=-1
var trial_warning: Label
var trial_info_panel: PanelContainer
var trial_info_label: Label
var planning_ui: Control
var layout_team := -1

func _l(zh: String,en: String) -> String:
	return en if Locale.locale == "en" else zh

func _on_battle_event(event: BattleEventV2) -> void:
	if is_instance_valid(stage) and is_instance_valid(stage.theatre):
		var unit := engine.state.unit_by_id(StringName(str(event.payload.get("unit_id", ""))))
		stage.theatre.audio.planning_feedback(event, unit != null and unit.team == 0)
	super._on_battle_event(event)

func _ready() -> void:
	music_context = &"combat_boss" if stage.battle_music_boss else stage.battle_music_context
	engine = preload("res://scripts/fusion_3d/fusion_engine.gd").new()
	if stage.trial_context != null:
		engine = preload("res://scripts/tower_v01/trial_engine.gd").new()
		engine.trial = stage.trial_context
	engine.party = stage.party.duplicate()
	engine.encounter_id = stage.encounter_id
	if stage.trial_context==null:engine.encounter_spec=stage.encounter_spec.duplicate(true)
	engine.campaign_level = stage.campaign_level
	ai = preload("res://scripts/fusion_3d/world_one_ai.gd").new()
	if stage.trial_context!=null:ai=preload("res://scripts/tower_v01/trial_ai.gd").new()
	super._ready()
	battle_music.bus = "AcademyMusic"
	circle.hide()
	caster_pointer.hide()
	top_bar.show()
	debug_toggle.hide()
	clean_view_button.hide()
	event_label.hide()
	cancel_button.text = _l("取消","Cancel")
	pass_button.text = _l("PASS / 蓄能","PASS / Charge")
	draw_button.text = _l("DRAW / 宝藏","DRAW / Treasure")
	deck_button.text = _l("DECK / 卡组","DECK / Cards")
	charge_option = OptionButton.new()
	for school in ["fire","ice","storm","myth","life","death","balance"]:
		charge_option.add_item(Locale.text("SCHOOL_"+school.to_upper()))
	charge_option.tooltip_text = _l("下轮充能学院；已转化的学院豆保持原属性","School charged next round; converted school pips keep their type")
	charge_option.item_selected.connect(func(index: int):
		if active_actor != null:
			engine.set_next_charge(active_actor.id,StringName(["fire","ice","storm","myth","life","death","balance"][index])))
	$TopBar/Bar.add_child(charge_option)
	var fusion := Button.new()
	fusion.text = _l("融合","Fuse")
	fusion.disabled = stage.trial_context != null
	fusion.toggle_mode = true
	fusion.toggled.connect(func(enabled: bool):
		fusion_mode = enabled
		fusion_first = -1
		_cancel_selection()
		prompt_label.text = _l("依次点击两张已习得普通卡；融合后手动 DRAW","Select two learned normal cards; draw manually after fusing") if enabled else _l("选择法术","Choose a spell"))
	$TopBar/Bar.add_child(fusion)
	ai_button = Button.new()
	ai_button.text = _l("AI 补全","AI fill")
	ai_button.pressed.connect(auto_plan_players)
	$TopBar/Bar.add_child(ai_button)
	if stage.trial_context != null:
		trial_warning=Label.new();trial_warning.position=Vector2(500,170)
		trial_warning.size=Vector2(550,115)
		trial_warning.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		trial_warning.add_theme_font_size_override("font_size",20)
		trial_warning.add_theme_color_override("font_shadow_color",Color("122b3b"))
		trial_warning.add_theme_constant_override("shadow_offset_x",2)
		trial_warning.add_theme_constant_override("shadow_offset_y",2)
		trial_warning.add_theme_color_override("font_color",Color("ffe0a0"))
		trial_warning.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(trial_warning)
		_build_trial_info()
		var trial_deck:=Button.new();trial_deck.text=_l("查看局内牌组","View battle deck");trial_deck.position=Vector2(500,338);add_child(trial_deck)
		TrialArt.apply_button(trial_deck,true)
		trial_deck.pressed.connect(_show_trial_deck)
		if stage.shared_session==null:
			var leave:=Button.new();leave.text=_l("放弃本局","Abandon run");leave.position=Vector2(740,338);add_child(leave)
			TrialArt.apply_button(leave,true)
			leave.pressed.connect(func():stage.get_parent().exploration_context.run_controller.request_abandon())
		var reorganize := Button.new()
		reorganize.text = _l("整备（每战一次 / 消耗行动）","Reorganize (once per battle / costs a turn)")
		TrialArt.apply_button(reorganize)
		reorganize.pressed.connect(func():
			if not stage.entering and engine.request_reorganize(active_actor):_begin_player_planning())
		$TopBar/Bar.add_child(reorganize)
	stage.bind_engine(engine)
	preload("res://scripts/fusion_3d/academy_ui.gd").apply(self)
	planning_ui=preload("res://scripts/fusion_3d/battle_planning_ui.gd").new()
	planning_ui.setup(self)
	if not get_window().size_changed.is_connected(_on_hud_window_resized):
		get_window().size_changed.connect(_on_hud_window_resized)
	_refresh_all()

func _build_units() -> void:
	super._build_units()
	refresh_roster_skin()

func refresh_roster_skin() -> void:
	# New controls need styling and layout even when the roster count is unchanged.
	layout_viewport=Vector2(-1,-1);layout_unit_count=-1
	for view in unit_views.values():
		view.nameplate.set_meta("refined",true)
		view.nameplate.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
		view.nameplate.queue_redraw()

func _layout_units() -> void:
	if not is_node_ready():return
	# The 2D HUD geometry is static between resize/roster changes. Only project
	# the hit proxies every frame; rebuilding every nameplate caused entry hitches.
	var local_team: int=int(call("_local_team")) if has_method("_local_team") else 0
	if size!=layout_viewport or unit_views.size()!=layout_unit_count or local_team!=layout_team:
		super._layout_units()
		layout_viewport=size;layout_unit_count=unit_views.size()
		layout_team=local_team
		if is_instance_valid(planning_ui):planning_ui.layout()
	hand_tray_art.offset_top = 0
	hand_tray_art.offset_bottom = 0
	if stage == null or stage.actors.is_empty(): return
	circle.hide()
	caster_pointer.hide()
	for id in unit_views:
		var view: Control = unit_views[id]
		var point: Vector2 = stage.screen_floor(id)
		view.position = point-LayoutProfile.UNIT_LOCAL_FOOT*view.scale
		# Keep the transparent input proxy and detached HUD. 3D owns all world visuals.
		view.self_modulate.a = 0
		for child in view.get_children():
			if child is CanvasItem: child.hide()

func _layout_hud_columns(_viewport_size: Vector2) -> void:
	var local_team: int=int(call("_local_team")) if has_method("_local_team") else 0
	preload("res://scripts/fusion_3d/battle_planning_ui.gd").layout_roster(self,local_team)

func _on_hud_window_resized() -> void:
	layout_viewport=Vector2(-1,-1)
	_layout_units()

func _process(_delta: float) -> void:
	if is_instance_valid(trial_warning):trial_warning.text=str(engine.telegraph_text)
	if stage == null or stage.actors.is_empty(): return
	_layout_units()
	var selecting:=_click_mode() and selected_card!=null and ui_state in [UIState.CARD_SELECTED,UIState.TARGETING] and active_actor!=null and not engine.state.actions.has(active_actor.id)
	for card_view in hand.cards:
		card_view.dimmed=selecting and card_view.card!=selected_card
		card_view.set_meta("fusion_selection",fusion_mode)
		if not card_view.get_meta("refined",false):
			card_view.set_meta("refined",true)
			card_view.queue_redraw()
	for id in unit_views:
		var view: Control = unit_views[id]
		var suppress_details: bool=selecting or ui_state==UIState.RESOLVING or stage.entering
		view.nameplate.set_meta("suppress_hover_details",suppress_details)
		if suppress_details:view.nameplate.status_detail_panel.hide()
		var targeting: bool=ui_state==UIState.TARGETING
		var highlighted: bool=valid_target_ids.has(id) if targeting else (view.hud_hovered or view.character_hovered or view.active)
		stage.highlight(id,highlighted,targeting,targeting and selected_target_id==id)

func _nearest_drag_target(pointer_global: Vector2) -> StringName:
	# Exact HUD/model hits win; magnetism only extends the battlefield hit area.
	if is_instance_valid(planning_ui) and planning_ui.blocks_pointer(pointer_global):return &""
	var direct: StringName=super._nearest_drag_target(pointer_global)
	if direct!=&"":return direct
	if _pointer_over_any_unit(pointer_global):return &""
	var margin: float=36.0*clampf(size.y/900.0,0.75,1.5)
	var nearest: StringName=&""
	var best:=INF
	for id in valid_target_ids:
		var view: Control=unit_views[id]
		var rect: Rect2=view.get_target_hit_rect_global()
		var distance: float=pointer_global.distance_to(pointer_global.clamp(rect.position,rect.end))
		var allowance: float=margin+(12.0 if id==selected_target_id else 0.0)
		if distance>allowance:continue
		# A small retention bias prevents flicker between neighboring candidates.
		var score: float=distance-(8.0 if id==selected_target_id else 0.0)
		if score<best:
			nearest=id
			best=score
	return nearest

func _center_cast_target(pointer_global: Vector2) -> StringName:
	if is_instance_valid(planning_ui) and planning_ui.blocks_pointer(pointer_global):return &""
	return super._center_cast_target(pointer_global)

func _on_card_selected(card: CardInstanceV2) -> void:
	if stage.entering: return
	if fusion_mode:
		if active_actor == null or ui_state == UIState.RESOLVING: return
		if fusion_first < 0:
			fusion_first = card.instance_id
			hand.set_selected(fusion_first,true)
			prompt_label.text = _l("选择第二张融合材料","Choose the second card to fuse")
		else:
			var result := engine.fuse_cards(active_actor.id,fusion_first,card.instance_id)
			fusion_first = -1
			hand.show_hand(active_actor,engine)
			_refresh_all()
			prompt_label.text = _l("融合成功，空位可手动 DRAW","Fusion succeeded; draw into the open slot manually") if result != null else _l("不符合配方：火花箭＋余烬陷阱；冰片＋霜甲","No recipe: Spark Arrow + Ember Trap; Ice Shard + Frost Armor")
		return
	super._on_card_selected(card)
	if _click_mode() and selected_card==card and ui_state==UIState.TARGETING and not valid_target_ids.is_empty():
		if valid_target_ids.size()==1 or card.definition.target_type in [&"self",&"all_enemies",&"all_allies",&"global"]:
			_on_unit_clicked(valid_target_ids[0])

func _click_mode() -> bool:
	return is_instance_valid(planning_ui) and planning_ui.click_mode

func _uses_center_cast() -> bool:
	return selected_card!=null and (selected_card.definition.target_type in [&"self",&"all_allies",&"all_enemies",&"global"] or valid_target_ids.size()==1)

func _on_card_drag_moved(card: CardInstanceV2, pointer_global: Vector2, origin_global: Vector2) -> void:
	if _uses_center_cast() and not fusion_mode:
		target_arrow.hide_arrow()
		if ui_state==UIState.TARGETING and not valid_target_ids.is_empty():
			drag_target_id=valid_target_ids[0]
			selected_target_id=drag_target_id
			prompt_label.text="松手施放 · 右键取消"
			_refresh_all()
		return
	super._on_card_drag_moved(card,pointer_global,origin_global)

func _on_card_drag_ended(card: CardInstanceV2, pointer_global: Vector2) -> void:
	if _uses_center_cast() and not fusion_mode:
		target_arrow.hide_arrow()
		if ui_state==UIState.TARGETING and not valid_target_ids.is_empty():
			selected_target_id=valid_target_ids[0]
			_lock_selected_action()
		else:_cancel_selection()
		drag_target_id=&""
		return
	super._on_card_drag_ended(card,pointer_global)

func _show_click_target_guide() -> void:
	if _uses_center_cast() and not _click_mode():
		target_arrow.hide_arrow()
		prompt_label.text="轻拖后松手施放 · 右键取消"
		return
	if _click_mode():
		target_arrow.hide_arrow()
		prompt_label.text="点击高亮目标 · 右键取消"
		return
	super._show_click_target_guide()

func _update_target_guide(pointer_global: Vector2) -> void:
	if _click_mode():
		target_arrow.hide_arrow()
		return
	super._update_target_guide(pointer_global)

func _input(event: InputEvent) -> void:
	if _click_mode() and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and ui_state in [UIState.CARD_SELECTED,UIState.TARGETING]:
		_cancel_selection()
		target_arrow.hide_arrow()
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _on_card_drag_started(card: CardInstanceV2, origin_global: Vector2) -> void:
	if fusion_mode:
		_on_card_selected(card)
		return
	super._on_card_drag_started(card,origin_global)

func _on_unit_clicked(id: StringName) -> void:
	if stage.entering: return
	# Drag mode commits only through drag release, never a target click.
	if not _click_mode() and ui_state in [UIState.CARD_SELECTED, UIState.TARGETING]:return
	if _click_mode() and ui_state==UIState.TARGETING and selected_card!=null and valid_target_ids.has(id):
		selected_target_id=id
		target_arrow.hide_arrow()
		_refresh_all()
		_lock_selected_action()
		return
	if ui_state == UIState.PLANNING:
		var unit := engine.state.unit_by_id(id)
		if unit != null and unit.team == 0 and unit.alive and not engine.state.actions.has(id):
			active_actor = unit
			hand.show_hand(unit,engine)
			_refresh_all()
			return
	super._on_unit_clicked(id)

func _refresh_all() -> void:
	super._refresh_all()
	if is_instance_valid(charge_option):
		charge_option.disabled = active_actor == null or ui_state == UIState.RESOLVING
		if active_actor != null:
			charge_option.select(["fire","ice","storm","myth","life","death","balance"].find(str(active_actor.resources.next_charge_school)))
	if is_instance_valid(ai_button): ai_button.disabled = ui_state in [UIState.RESOLVING,UIState.BATTLE_END]
	if active_actor != null and engine.party_decks.has(str(active_actor.character_id)):
		var preset: Dictionary = engine.party_decks[str(active_actor.character_id)]
		deck_button.tooltip_text = str(preset.name)+" · "+str(preset.role)+"\n"+str(preset.plan)
	if not debug_mode: event_label.text = ""

func auto_plan_players() -> void:
	if stage.entering: return
	if ui_state in [UIState.RESOLVING,UIState.BATTLE_END]: return
	_cancel_selection()
	for unit in engine.state.living_units(0):
		if not engine.state.actions.has(unit.id):
			if stage.trial_context != null and unit.deck.draw_pile.is_empty() and unit.deck.hand.is_empty() and engine.request_reorganize(unit):continue
			engine.queue_action(ai.choose_action(engine,unit))
	_begin_player_planning()

func _cancel_selection() -> void:
	if ui_state == UIState.BATTLE_END:
		_schedule_battle_finished(0.0)
		return
	var no_arrow:=_click_mode() or _uses_center_cast()
	super._cancel_selection()
	if no_arrow:target_arrow.hide_arrow()


func _set_ui_state(next: UIState) -> void:
	var previous_state := ui_state
	super._set_ui_state(next)
	if is_instance_valid(planning_ui):planning_ui.set_planning(next!=UIState.RESOLVING)
	# The action controls now belong to PlanningUI; old docks must not eat input.
	action_strip.hide();deck_dock.hide()
	if next == UIState.BATTLE_END and is_instance_valid(stage):
		stage.cancel_camera_action()
	if next == UIState.PLANNING and previous_state == UIState.RESOLVING and is_instance_valid(stage):
		presentation_director.held_turn_actor = &""
		stage.restore_planning_camera()
	# Round-start generation/conversion has completed before planning opens.
	# Refresh resources only; status visuals still follow their presentation markers.
	if next == UIState.PLANNING and is_instance_valid(stage) and stage.engine != null:
		for unit: BattleUnitStateV2 in engine.state.units:
			if stage.actors.has(unit.id): stage.visuals.sync_pips(unit)
	phase_label.text = _l("第 %d 回合 · %s","Round %d · %s") % [engine.state.round_index,_l("结算中","Resolving") if next == UIState.RESOLVING else (_l("战斗结束","Battle over") if next == UIState.BATTLE_END else _l("规划行动","Planning"))]
	prompt_label.text = _l("选择卡牌与目标 · 未选牌时右键删卡 · 选牌后右键取消","Choose a card and target · Right-click: discard idle card / cancel selection") if next == UIState.PLANNING else (_l("选择高亮角色或 HUD · 右键取消","Choose a highlighted character or HUD · Right-click to cancel") if next == UIState.TARGETING else (_l("法术演出中","Casting spell") if next == UIState.RESOLVING else prompt_label.text))
	if engine.encounter_id=="magister":phase_label.text+=_l(" · 织星者阶段 "," · Star Weaver phase ")+str(engine.boss_phase)+" / 3"
	cancel_button.text = (_l("前往战后奖励","View rewards") if stage.trial_context!=null else _l("返回城镇","Return to town")) if next == UIState.BATTLE_END else _l("取消","Cancel")

func _on_pass_pressed() -> void:
	if stage.entering: return
	super._on_pass_pressed()
func _on_draw_pressed() -> void:
	if stage.entering: return
	super._on_draw_pressed()
func _on_deck_pressed() -> void:
	if stage.trial_context != null:
		_show_trial_deck()
		return
	if stage.entering or active_actor==null or ui_state not in [UIState.PLANNING,UIState.CARD_SELECTED,UIState.TARGETING]:return
	if ui_state in [UIState.CARD_SELECTED,UIState.TARGETING]:_cancel_selection()
	var counts: Dictionary=custom_decks.get(str(active_actor.character_id),_default_deck_counts(active_actor)).duplicate()
	for id in counts.keys():
		var card:=content.card(StringName(id))
		if card==null or card.pip_cost>engine.card_cost_cap():counts.erase(id)
	deck_builder.max_pip_cost=engine.card_cost_cap()
	var actor_title: String=str(active_actor.name_key)
	var locale:=get_node_or_null("/root/Locale")
	if locale:actor_title=locale.text(actor_title)
	if unit_views.has(active_actor.id):actor_title=unit_views[active_actor.id].nameplate._display_name()
	deck_builder.set_character_context(actor_title,engine.party_decks.get(str(active_actor.character_id),{}).get("treasure",[]))
	deck_builder.open(content,counts)
func _on_card_discard_requested(card: CardInstanceV2) -> void:
	if stage.entering: return
	super._on_card_discard_requested(card)

func _load_custom_decks() -> void:
	custom_decks.clear()
	if stage.trial_context != null:return
	if FileAccess.file_exists(custom_deck_path()):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(custom_deck_path()))
		if parsed is Dictionary: custom_decks = parsed
func _save_custom_decks() -> void:
	if stage.trial_context != null:return
	var file := FileAccess.open(custom_deck_path(),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(custom_decks,"  "))
func _default_deck_counts(unit: BattleUnitStateV2) -> Dictionary:
	if engine.party_decks.has(str(unit.character_id)):
		return engine.party_decks[str(unit.character_id)].normal.duplicate(true)
	return super._default_deck_counts(unit)

func _on_deck_apply_requested(card_counts: Dictionary) -> void:
	for id in card_counts:
		var card:=content.card(StringName(id))
		if card!=null and int(card_counts[id])>0 and card.pip_cost>engine.card_cost_cap():
			prompt_label.text=_l("该法术尚未解锁：当前 Lv.","Spell not unlocked: current Lv.")+str(engine.campaign_level)+_l("，请调整卡组。",". Please adjust your deck.")
			return
	super._on_deck_apply_requested(card_counts)

func custom_deck_path() -> String:
	return "user://academy_showcase_decks_20260909.json" if stage.encounter_id=="town_showcase" else Accounts.path_for("academy_custom_decks.json")

func _build_trial_info() -> void:
	var toggle:=Button.new();toggle.text=_l("机制 / 遗物","Rules / Relics");toggle.position=Vector2(500,292)
	toggle.custom_minimum_size=Vector2(235,40);add_child(toggle)
	TrialArt.apply_button(toggle,true)
	trial_info_panel=PanelContainer.new();trial_info_panel.position=Vector2(500,220)
	trial_info_panel.add_theme_stylebox_override("panel",TrialArt.tooltip_style())
	add_child(trial_info_panel)
	var column:=VBoxContainer.new();trial_info_panel.add_child(column)
	var title:=Label.new();title.text=_l("机制与局内遗物 · 双人计时继续","Rules and relics · Co-op timer continues") if stage.shared_session!=null else _l("机制与局内遗物 · 单人无倒计时","Rules and relics · No solo timer");column.add_child(title)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(730,500);column.add_child(scroll)
	trial_info_label=Label.new();trial_info_label.custom_minimum_size.x=700
	trial_info_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;trial_info_label.add_theme_font_size_override("font_size",21)
	scroll.add_child(trial_info_label)
	var close:=Button.new();close.text=_l("返回战斗","Return to battle");column.add_child(close)
	TrialArt.apply_button(close,true)
	close.pressed.connect(trial_info_panel.hide)
	toggle.pressed.connect(func():trial_info_label.text=engine.trial_info();trial_info_panel.show();trial_info_panel.move_to_front())
	trial_info_panel.hide()
	if stage.trial_context.node_index==0:
		trial_info_label.text="蓄豆 → 刃 / 陷阱准备 → 选择攻击时机。\n每回合只有一次行动，PASS可保留魔豆。弃置普通手牌后，下回合补抽。\n强力豆：本系及研习副系按2点，其他系按1点支付。\n留意敌人预告；抽牌堆用尽且有弃牌时可整备，每战一次并消耗行动。\n可随时通过“机制与遗物”重新查看说明。"
		trial_info_panel.show()

func _show_trial_deck() -> void:
	if active_actor==null:return
	var dialog:=AcceptDialog.new();dialog.title="局内牌组 · 只读（未知抽牌顺序隐藏）";add_child(dialog)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(680,440);dialog.add_child(scroll)
	var text:=Label.new();text.custom_minimum_size.x=650;text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;scroll.add_child(text)
	var lines: Array[String]=[]
	for pair in [["手牌",active_actor.deck.hand],["抽牌堆（仅显示组成）",active_actor.deck.draw_pile],["弃牌堆",active_actor.deck.discard_pile],["本战移除",active_actor.deck.removed_cards]]:
		lines.append("\n%s · %d张" % [pair[0],pair[1].size()])
		var sorted_cards: Array=pair[1].duplicate()
		sorted_cards.sort_custom(func(a,b):return a.instance_id<b.instance_id)
		for card in sorted_cards:lines.append("#%d %s · %d豆 · 命中%d%%" % [card.instance_id,Locale.text(card.definition.name_key),card.definition.pip_cost,roundi(card.definition.accuracy*100)])
	lines.append("\n整备：抽牌堆为空且存在可回收弃牌时可用；占一次行动，每战一次。")
	text.text="\n".join(lines)
	dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free);dialog.popup_centered(Vector2i(720,520))
