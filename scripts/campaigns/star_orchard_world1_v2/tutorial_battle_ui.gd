extends CanvasLayer
## Local reading UI only. The server remains the owner of turns and victories.
const RetryHelp = preload("res://scripts/campaigns/star_orchard_world1_v2/tutorial_retry_help.gd")
var session: Node
var panel: PanelContainer
var heading: Label
var body: Label
var companion_plan: Label
var reopen: Button
var battle_key := ""
var shown_round := -1
var dismissed_round := -1
var lesson: Dictionary = {}
var voice: Node
var retry_summary := false
var explicit_help := false

func _ready() -> void:
	layer = 75
	var container := Control.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	panel = preload("res://scripts/fusion_3d/npc_dialogue_panel.gd").new()
	container.add_child(panel)
	voice = preload("res://scripts/campaigns/star_orchard_world1_v2/west_island_voice.gd").new()
	panel.add_child(voice)
	heading = panel.heading
	body = panel.body
	panel.scroll.custom_minimum_size.y = 180
	panel.minimum_size_changed.connect(func(): panel.layout_dialogue.call_deferred())
	var footer := Label.new()
	footer.text = "本场借用教学卡组 · 提示不暂停联机回合"
	footer.add_theme_font_size_override("font_size", 16)
	footer.modulate = Color("b3c2ce")
	panel.content.add_child(footer)
	panel.content.move_child(footer, panel.content.get_child_count() - 2)
	panel.add_action("明白了，继续操作", func(): dismissed_round=shown_round; retry_summary=false; panel.hide())
	reopen = Button.new()
	reopen.position = Vector2(24,114)
	reopen.text = "教程提示"
	reopen.add_theme_font_size_override("font_size",20)
	reopen.pressed.connect(func(): dismissed_round=-1; _show_round(shown_round))
	container.add_child(reopen)
	companion_plan=Label.new()
	companion_plan.position=Vector2(24,114)
	companion_plan.add_theme_font_size_override("font_size",20)
	companion_plan.add_theme_color_override("font_shadow_color",Color.BLACK)
	companion_plan.add_theme_constant_override("shadow_offset_x",2)
	companion_plan.add_theme_constant_override("shadow_offset_y",2)
	container.add_child(companion_plan)
	companion_plan.hide()
	panel.hide()
	reopen.hide()

func _process(_delta: float) -> void:
	companion_plan.hide()
	if not is_instance_valid(session): hide(); return
	var stage: Node = session.stage
	var available: bool = session.active_local and session.battle_ready and is_instance_valid(stage) and not stage.entering
	if not available:
		if retry_summary:reopen.hide(); return
		panel.hide(); reopen.hide(); return
	var descriptor: Dictionary = session.descriptor
	var key := str(descriptor.get("battle_id",descriptor.get("id","")))
	if key != battle_key:
		retry_summary = false
		battle_key = key
		lesson = descriptor.get("tutorial",{}).duplicate(true)
		explicit_help = RetryHelp.loss_count(session.tutorial_character_key(),str(descriptor.get("encounter_id","")))>=2
		shown_round = -1
		dismissed_round = -1
		panel.hide()
	if retry_summary:reopen.hide(); return
	if lesson.is_empty(): panel.hide(); reopen.hide(); return
	var planning: bool = stage.engine != null and stage.engine.state.phase == BattleStateV2.Phase.PLANNING
	if bool(lesson.get("no_guidance",false)):
		panel.hide();reopen.hide()
		if planning:_update_companion(stage.engine)
		return
	reopen.visible = planning
	if not planning: panel.hide(); return
	var round_number: int = stage.engine.state.round_index
	if round_number != shown_round:
		shown_round = round_number
		dismissed_round = -1
		panel.hide()
		if explicit_help or bool(_round_tip(round_number).get("auto_prompt",false)):
			_show_round(round_number)

func _round_tip(round_number: int) -> Dictionary:
	var tip: Dictionary = {}
	for entry in lesson.get("rounds",[]):
		if int(entry.get("round",-1)) == round_number: tip = entry; break
	if tip.is_empty():
		tip = {"title":"独立练习", "text":"按刚才学到的方法完成战斗。豆数不足时可以等待；留意生命值、状态图标和卡牌费用。获胜后服务器会保存本课进度。"}
	return tip

func _show_round(round_number: int) -> void:
	var tip := _round_tip(round_number)
	if explicit_help and is_instance_valid(session.stage):
		var engine: BattleEngineV2=session.stage.engine
		var direct:=RetryHelp.recommendation(int(lesson.get("lesson",0)),round_number,engine.state.unit_by_id(&"P0"),engine.content)
		if not direct.is_empty():tip=direct
	heading.text = "第 %d 课 · 第 %d 回合  ·  %s" % [int(lesson.get("lesson",1)),round_number,str(tip.get("title",lesson.get("title","战斗练习")))]
	body.text = str(tip.get("text",""))
	var intent := "" if explicit_help else str(tip.get("intent",lesson.get("intent","")))
	if not intent.is_empty():body.text += "\n\n怪物动向："+intent
	panel.show()
	panel.layout_dialogue.call_deferred()
	# Retry guidance names the live hand, so it has no prerecorded voice clip.
	if explicit_help:voice.stop()
	else:voice.play_text(body.text)

func show_retry_help(id: String) -> void:
	var n:=RetryHelp.lesson_number(id)
	if n==0 or not is_instance_valid(session.stage):return
	var engine: BattleEngineV2=session.stage.engine
	var player:=engine.state.unit_by_id(&"P0")
	if player==null:return
	retry_summary=true
	heading.text="一起试试这样出牌"
	body.text="这场练习已经战败两次。再次挑战时，每回合会直接提示该选的牌和原因。\n\n"
	# Name the opening card without changing battle/account state.
	var opening:=RetryHelp.recommendation(n,1,player,engine.content)
	body.text+=str(opening.get("title",""))+"\n"+str(RetryHelp.REASONS.get(opening.get("role",""),""))
	panel.show()
	panel.layout_dialogue.call_deferred()
	voice.stop()

func _update_companion(engine: BattleEngineV2) -> void:
	var ally:=engine.state.unit_by_id(&"P1")
	if ally==null or not ally.alive:return
	var intent: ActionIntentV2=engine.state.actions.get(&"P1")
	var action: String="等待"
	if intent!=null and not intent.pass_action:
		var card:=engine.content.card(intent.card_definition_id)
		if card!=null:
			action=Locale.text(str(card.name_key))
			if card.target_type==&"all_allies":action+=" → 全体队友"
			elif card.target_type==&"all_enemies":action+=" → 全体敌人"
			elif not intent.target_ids.is_empty():
				var target:=engine.state.unit_by_id(intent.target_ids[0])
				if target!=null:action+=" → "+("你" if target.id==&"P0" else ("自己" if target.id==ally.id else Locale.text(str(target.name_key))))
	companion_plan.text="队友预计："+action
	companion_plan.show()
