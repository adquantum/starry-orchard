extends Node
const Trial = preload("res://scripts/tower_v01/trial_context.gd")
const Rules = preload("res://scripts/tower_v01/trial_rules.gd")
const Store = preload("res://scripts/tower_v01/trial_store.gd")
const Art = preload("res://scripts/tower_v01/trial_ui_art.gd")
var tower: Node3D
var trial: RefCounted
var stage: Node3D
var in_battle := false
var running := false
var preparing := false
var panel: PanelContainer
var column: VBoxContainer
var header: Label
var notice: Label
var footer: HBoxContainer
var scroll: ScrollContainer
var busy := false
var menu_generation := 0
var persistence_path_override := ""
var party_session: Node
var selected_school := ""
var last_message := ""
var save_pending := false
var deferred_advance := false

func save_path() -> String:
	return persistence_path_override if not persistence_path_override.is_empty() else Store.path_for(get_node_or_null("/root/Accounts"),str(tower.world.avatar.school_id))

func save_run() -> bool:
	if party_session!=null:return true
	if trial==null:return false
	var result: bool=trial.save(save_path())
	save_pending=not result
	if not result:last_message="保存失败，本局仍保留在当前界面。请重试保存。"
	return result

func _ready() -> void:
	panel=PanelContainer.new();tower.layer.add_child(panel)
	panel.add_theme_stylebox_override("panel",Art.panel_style());panel.add_theme_font_size_override("font_size",18)
	var layout:=VBoxContainer.new();layout.add_theme_constant_override("separation",10);panel.add_child(layout)
	header=Label.new();header.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;header.add_theme_font_size_override("font_size",24);header.add_theme_color_override("font_color",Color("fff0bd"));header.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;layout.add_child(header)
	notice=Label.new();notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.modulate=Color("ffdba4");layout.add_child(notice)
	scroll=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;layout.add_child(scroll)
	column=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",10);scroll.add_child(column)
	footer=HBoxContainer.new();footer.alignment=BoxContainer.ALIGNMENT_CENTER;footer.add_theme_constant_override("separation",10);layout.add_child(footer);panel.hide()

func _process(_delta: float) -> void:
	if not panel.visible:return
	var viewport:=get_viewport().get_visible_rect().size
	var width:=minf(840,viewport.x-260)
	header.custom_minimum_size.x=width;notice.custom_minimum_size.x=width
	# The generated frame keeps tall, undistorted nine-slice caps; reserve their
	# fixed space before sizing the scrollable center.
	scroll.custom_minimum_size=Vector2(width,clampf(column.get_combined_minimum_size().y,260,maxf(260,viewport.y-600)))
	panel.reset_size();panel.position=(viewport-panel.size)*0.5

func clear_menu(title: String) -> void:
	menu_generation+=1;tower.world.input_suspended=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	for parent in [column,footer]:
		for child in parent.get_children():parent.remove_child(child);child.queue_free()
	header.text=title;notice.text=last_message;notice.visible=not last_message.is_empty();panel.show();scroll.scroll_vertical=0

func label(text: String, parent: Node=column, minimum_width:=0.0) -> Label:
	var item:=Label.new();item.text=text;item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;item.custom_minimum_size.x=minimum_width;item.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(item);return item

func button(title: String, action: Callable, bottom := false, secondary: Variant=null) -> Button:
	var generation:=menu_generation
	var item: Button=tower._button(footer if bottom else column,title,func():
		if generation!=menu_generation or busy:return
		action.call())
	item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	item.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	Art.apply_button(item,bottom if secondary==null else bool(secondary))
	return item

func school_name(value: String) -> String:return Locale.text("SCHOOL_"+value.to_upper())
func menu_return() -> void:show_menu()

func direction_cards(school: String, parent: Node=column, vertical:=false) -> void:
	var titles: PackedStringArray=str(Rules.DIRECTIONS[school]).split(" / ")
	var row: BoxContainer=VBoxContainer.new() if vertical else HBoxContainer.new();row.alignment=BoxContainer.ALIGNMENT_CENTER;row.add_theme_constant_override("separation",10);parent.add_child(row)
	for index in 2:
		var card:=PanelContainer.new();card.custom_minimum_size=Vector2(390 if vertical else 320,96);card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card.add_theme_stylebox_override("panel",Art.tooltip_style());row.add_child(card)
		var body:=HBoxContainer.new();body.add_theme_constant_override("separation",10);card.add_child(body)
		Art.icon(Art.trait_icon(school,"a" if index==0 else "b"),Vector2(60,60),body)
		var words:=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_child(words)
		var title:=Label.new();title.text="方向%s · %s" % ["A" if index==0 else "B",titles[index] if index<titles.size() else ""];title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.add_theme_color_override("font_color",Color("f5d993"));words.add_child(title)
		var hint:=Label.new();hint.text=str(Art.TRAIT_HINTS[school][index]);hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;hint.add_theme_font_size_override("font_size",14);hint.add_theme_color_override("font_color",Color("b9ceda"));words.add_child(hint)

func progress_row() -> void:
	var row:=HBoxContainer.new();row.alignment=BoxContainer.ALIGNMENT_CENTER;row.add_theme_constant_override("separation",4);column.add_child(row)
	for index in 9:
		var node:=PanelContainer.new();node.custom_minimum_size=Vector2(34,28);node.tooltip_text="节点 %d%s" % [index+1," · 当前" if index==trial.node_index else ""]
		node.add_theme_stylebox_override("panel",Art.flat_panel(Color("2c607f") if index==trial.node_index else Color("102638"),Color("efc86f") if index==trial.node_index else Color("496579"),14,4));row.add_child(node)
		var number:=Label.new();number.text=str(index+1);number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;number.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;number.add_theme_font_size_override("font_size",13);node.add_child(number)

func start() -> void:
	if running or busy or not tower.inside:return
	preparing=true
	if selected_school.is_empty():selected_school=str(tower.world.avatar.school_id)
	show_preparation()

func show_preparation() -> void:
	clear_menu("寒冰回响 v0.2 · 试炼准备")
	var summary:=label("九节点六场战斗 · 正式奖励关闭 · 战中中断会结束本局")
	summary.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;summary.add_theme_color_override("font_color",Color("b9ceda"))
	var body:=HBoxContainer.new();body.add_theme_constant_override("separation",18);column.add_child(body)
	var left:=VBoxContainer.new();left.custom_minimum_size.x=400;left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;left.add_theme_constant_override("separation",10);body.add_child(left)
	var right:=VBoxContainer.new();right.custom_minimum_size.x=400;right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.add_theme_constant_override("separation",8);body.add_child(right)
	var school_title:=label("本局学院",left);school_title.add_theme_color_override("font_color",Color("f5d993"));school_title.add_theme_font_size_override("font_size",20)
	var choose:=OptionButton.new();left.add_child(choose)
	Art.apply_button(choose,true);choose.custom_minimum_size.y=54
	for school in Rules.SCHOOLS:choose.add_item(school_name(school))
	choose.select(maxi(0,Rules.SCHOOLS.find(selected_school)))
	choose.item_selected.connect(func(index):selected_school=Rules.SCHOOLS[index];show_preparation())
	var preview=Trial.new()
	if not preview.initialize(selected_school,1):label("该学院初始牌组加载失败");return
	var sandbox_note:=label("仅影响本次沙盒，不修改正式角色学院。",left);sandbox_note.add_theme_font_size_override("font_size",14);sandbox_note.add_theme_color_override("font_color",Color("90a9b7"))
	direction_cards(selected_school,left,true)
	var deck_title:=label("12张起始牌组",right);deck_title.add_theme_color_override("font_color",Color("f5d993"));deck_title.add_theme_font_size_override("font_size",20)
	var starter_panel:=PanelContainer.new();starter_panel.add_theme_stylebox_override("panel",Art.flat_panel(Color("091a29b8"),Color("3e5f73"),8,12));right.add_child(starter_panel)
	var starter_grid:=GridContainer.new();starter_grid.columns=2;starter_grid.add_theme_constant_override("h_separation",18);starter_grid.add_theme_constant_override("v_separation",7);starter_panel.add_child(starter_grid)
	for id in Rules.STARTERS[selected_school]:
		var item:=Label.new();item.text="%s  ×%d" % [Locale.text(str(preview.sources[id].name_key)),Rules.STARTERS[selected_school][id]];item.custom_minimum_size.x=178;item.add_theme_font_size_override("font_size",16);starter_grid.add_child(item)
	var rule_note:=label("蓄豆 → 刃/陷阱准备 → 选择攻击时机\n普通牌弃置后下回合补抽；每场可整备一次。",right);rule_note.add_theme_font_size_override("font_size",15);rule_note.add_theme_color_override("font_color",Color("b9ceda"))
	button("开始单人",request_new_run,true,false)
	button("双人组队",func():preparing=false;tower.party_session.lobby(),true,false)
	if FileAccess.file_exists(save_path()):button("继续旧局",resume,true,true)
	button("关闭",func():preparing=false;panel.hide();tower.world.input_suspended=false,true,true)

func request_new_run() -> void:
	if FileAccess.file_exists(save_path()):
		var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(save_path()))
		if data is Dictionary and str(data.get("state","")) not in ["SUCCESS","FAILED","ABANDONED"]:
			confirm("放弃旧局并新开？","已有未结束测试局。继续将保留旧档副本并开始新局。",begin_new_run);return
	begin_new_run()

func confirm(title: String, text: String, action: Callable) -> void:
	var dialog:=ConfirmationDialog.new();dialog.title=title;dialog.dialog_text=text;tower.layer.add_child(dialog)
	dialog.confirmed.connect(func():dialog.queue_free();action.call())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered()

func begin_new_run() -> void:
	if busy:return
	busy=true
	if tower.current_room!=0 and not await tower.move_to(0):busy=false;last_message="首层准备失败，可重试。";show_preparation();return
	if FileAccess.file_exists(save_path()):
		var old: Variant=JSON.parse_string(FileAccess.get_file_as_string(save_path()))
		if old is Dictionary and not Store.write(save_path()+".previous",old):busy=false;last_message="旧档备份失败，未覆盖。";show_preparation();return
	trial=Trial.new()
	if not trial.initialize(selected_school,int(Time.get_unix_time_from_system())):busy=false;last_message="初始牌组加载失败";show_preparation();return
	trial.school_owner=str(tower.world.avatar.school_id);running=true;preparing=false;last_message="";busy=false
	save_run();show_menu()

func resume() -> void:
	if running or busy or not tower.inside:return
	var restored=Trial.new()
	if not restored.restore(save_path(),str(tower.world.avatar.school_id)):
		last_message="存档不存在、已放弃或与当前规则/牌库不兼容。旧档保留，可新开局。";preparing=true;show_preparation();return
	busy=true
	var floor_index:=mini(2,int(restored.node_index/3))
	if tower.current_room!=floor_index and not await tower.move_to(floor_index):busy=false;last_message="存档楼层加载失败，存档未改动。";show_preparation();return
	trial=restored;running=true;preparing=false;busy=false;last_message="已恢复到原节点与选择阶段。"
	if trial.state=="FAILED":save_run()
	show_menu()

func show_menu() -> void:
	if not running:return
	if party_session!=null:party_session.show_menu();return
	render_run()

func render_run() -> void:
	if trial==null:return
	clear_menu("寒冰回响 · 节点 %d / 9 · %s%s\nHP %d / %d · 灵露 %d · 卡牌 %d · 遗物 %d" % [trial.node_index+1,school_name(trial.school)," / "+school_name(trial.secondary) if not trial.secondary.is_empty() else "",trial.current_hp(),trial.main_max_hp(),trial.dew,trial.deck.size(),trial.relics.size()])
	progress_row()
	if save_pending:
		label("上次保存未完成，暂停领取和推进。")
		button("重试保存",func():
			if save_run():last_message="保存成功"
			show_menu())
		return
	if trial.state in ["FAILED","SUCCESS","ABANDONED"]:
		label(("试炼通关" if trial.state=="SUCCESS" else "本局结束 · "+trial.failure_reason)+"\n正式物品 0 · 剩余灵露仅记入战绩")
		button("查看本局构筑",show_build);button("返回洞外",finish);return
	if party_session!=null and party_session.waiting_for_partner():
		label("你的操作已提交，等待队友。")
		if trial.state=="SAFE":button("撤销就绪",func():party_session.choose("unready",{}))
	else:
		match trial.state:
			"REWARD","STUDY_CARD","REPLACE":show_card_rewards()
			"RELIC":
				label("战后奖励 · 卡牌已完成 → 选择一件遗物")
				for id in trial.relic_offer:relic_choice(str(id),func():perform("relic",{"id":id}))
				button("跳过并继续",func():perform("skip"))
			"STUDY":show_study_choices()
			"STUDY_REMOVE":
				label("本系深造：可免费移除一张旧实例，至少保留10张。之后仍可休整。")
				for record in trial.deck:
					if int(record.instance_id)!=trial.new_study_instance:button(card_line(record),func():perform("study_remove",{"instance":record.instance_id})).disabled=trial.deck.size()<=Rules.MIN_DECK
				button("保留全部并休整",func():perform("skip"))
			"SHOP":show_shop_contents()
			"REST":
				label("休息 / 强化"+(" / 免费换牌：三选一" if trial.node_index==7 else "：二选一"))
				button("恢复自身30%并完成整备",func():perform("heal"))
				button("强化一张卡",show_upgrades)
				if trial.node_index==7:
					label(preload("res://scripts/tower_v01/encounter_catalog.gd").get_encounter(8,false,trial.party_size).mechanics)
					button("免费换牌一次（占用整备选择）",func():perform("replace_begin"))
			"NODE_COMPLETE":
				button("完成节点并前进",func():
					if party_session!=null:party_session.choose("complete",{})
					else:advance())
			"SAFE":
				var encounter: Dictionary=trial.encounter()
				label("%s · %s · 胜利%d灵露\n%s" % [encounter.title,encounter.risk,encounter.dew,encounter.mechanics])
				for enemy in encounter.enemies:label("%s · %s · HP %d" % [enemy.name,school_name(enemy.school),enemy.hp])
				if party_session!=null:
					label("共同演出速度：%s×" % party_session.playback_speed)
					if party_session.can_change_route():
						button("切换演出速度（1× / 1.5× / 2×）",func():perform("speed",{"speed":1.5 if party_session.playback_speed==1.0 else 2.0 if party_session.playback_speed==1.5 else 1.0}))
				if trial.node_index in [1,4] and (party_session==null or party_session.can_change_route()):
					button("选择普通路线" if encounter.risk=="精英" else "选择精英路线（45灵露）",func():perform("route",{"route":"normal" if encounter.risk=="精英" else "elite"}))
				button("双方确认进入战斗" if party_session!=null else "开始战斗",func():
					if party_session!=null:party_session.choose("ready",{})
					else:start_battle())
	button("查看构筑",show_build,true)
	if party_session==null:button("保存退出",suspend,true)
	button("放弃本局",request_abandon,true)
	if party_session!=null:label(party_session.partner_status())

func show_card_rewards() -> void:
	label("研习选牌 → 休整" if trial.state=="STUDY_CARD" else "最终整备 · 换牌后不能再休息/强化" if trial.state=="REPLACE" else "战后奖励 · 选牌 → 遗物（适用节点）")
	var row:=HBoxContainer.new();column.add_child(row)
	for id in trial.offer:
		var stack:=VBoxContainer.new();stack.custom_minimum_size.x=164;row.add_child(stack)
		var slot:=Control.new();slot.custom_minimum_size=Vector2(164,238);stack.add_child(slot)
		var view:=BattleCardViewV2.new();slot.add_child(view)
		var definition: CardDefinitionV2=trial.definition({"base_spell_id":id,"level":0,"upgrade_path":""})
		view.bind(CardInstanceV2.new(-1,definition),true)
		view.selected.connect(func(_card):pick_card(str(id)))
		var details:=Label.new();details.text="已有%d张\n%s" % [trial.count_card(id),trial.offer_reasons.get(id,"")];details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;details.custom_minimum_size.x=160;stack.add_child(details)
		button("%s · %s" % ["替换为" if trial.state=="REPLACE" or trial.deck.size()>=18 else "领取",Locale.text(definition.name_key)],func():pick_card(str(id)))
		if trial.state!="REPLACE" and trial.deck.size()<18:button("用此牌替换旧牌："+Locale.text(definition.name_key),func():show_replacements(str(id),false))
	if trial.state=="REPLACE":button("返回整备（保留本次候选）",func():perform("replace_cancel"))
	else:button("跳过卡牌并继续",func():perform("skip"))

func pick_card(id: String) -> void:
	if trial.state=="REPLACE" or trial.deck.size()>=Rules.MAX_DECK:show_replacements(id,false)
	else:perform("card",{"id":id})

func show_replacements(id: String, purchase: bool) -> void:
	clear_menu("选择要替换的实例 · "+Locale.text(str(trial.sources[id].name_key)))
	label("替换后牌数不变，新卡从0级开始；同源最多4张。")
	for record in trial.deck:
		button(card_line(record),func():perform("buy" if purchase else "card",{"id":id,"replace":record.instance_id,"kind":"card"})).disabled=trial.count_card(id)-(1 if record.base_spell_id==id else 0)>=4
	button("返回",show_menu)

func show_study_choices() -> void:
	label("研习仅一次；研习完成后仍可休息或强化。")
	button("本系深造：本系三选一＋可删一张旧牌",func():perform("study",{"school":"primary"}))
	for school in Rules.SCHOOLS:
		if school==trial.school:continue
		var ids: Array=trial.candidates(school,3)
		var names: Array[String]=[]
		for id in ids.slice(0,3):names.append(Locale.text(str(trial.sources[id].name_key)))
		button("研习%s · POWER按2点支付\n入门组件示例：%s" % [school_name(school)," / ".join(names)],func():perform("study",{"school":school}))
	button("跳过研习并休整",func():perform("skip_study"))

func show_upgrades() -> void:
	clear_menu("选择卡牌改造 · 同实例最多两次，方向锁定")
	for record in trial.deck:
		for path in ["power","focus","ward"]:
			if not trial.can_upgrade(record,path):continue
			var preview: Dictionary=record.duplicate(true);preview.upgrade_path=path;preview.level=int(record.level)+1
			var before: CardDefinitionV2=trial.definition(record);var after: CardDefinitionV2=trial.definition(preview)
			button("%s · %s\n%s → %s" % [card_line(record),{"power":"威力","focus":"稳式","ward":"护印"}[path],definition_line(before),definition_line(after)],func():perform("upgrade",{"instance":record.instance_id,"path":path}))
	button("返回",show_menu)

func definition_line(value: CardDefinitionV2) -> String:
	var parts: Array[String]=["%d豆 命中%d%%" % [value.pip_cost,roundi(value.accuracy*100)]]
	for effect in value.effects:
		for field in ["power","damage_per_tick","healing_per_tick","value"]:
			if effect.has(field):parts.append("%s %s" % [str(effect.get("status",effect.type)),str(effect[field])])
	return " · ".join(parts)

func card_line(record: Dictionary) -> String:
	return "%s ×实例%d · %s%d" % [Locale.text(trial.definition(record).name_key),record.instance_id,{"":"未改造","power":"威力","focus":"稳式","ward":"护印"}.get(str(record.get("upgrade_path","")),""),record.level]

func show_build() -> void:
	clear_menu("本局构筑 · "+school_name(trial.school))
	var tags: Dictionary=trial.build_tags()
	label("卡牌%d张 · 攻击%d张 · 防护%d张 · 建议成型12–15张\n%s\n每战仅一次整备，删牌也会减少总施法容量。" % [trial.deck.size(),int(tags.get("attack",0)),int(tags.get("shield",0))+int(tags.get("absorb",0)),Rules.DIRECTIONS[trial.school]])
	direction_cards(trial.school)
	for record in trial.deck:label(card_line(record)+"\n"+definition_line(trial.definition(record)))
	for id in trial.relics:relic_display(str(id))
	button("返回",show_menu,true)

func show_shop() -> void:show_menu()
func show_shop_contents() -> void:
	label("冰原商店 · 购物后仍可休息或强化；库存固定，不刷新。")
	button("25灵露 · 回复35%（一次）",func():perform("buy",{"kind":"heal"})).disabled=trial.dew<25 or trial.current_hp()>=trial.main_max_hp() or trial.ledger.has("shop:heal:")
	for id in trial.shop_offer:
		button("35灵露 · "+Locale.text(str(trial.sources[id].name_key)),func():
			if trial.deck.size()>=18:show_replacements(str(id),true)
			else:perform("buy",{"kind":"card","id":id})).disabled=trial.dew<35 or trial.ledger.has("shop:card:"+str(id)) or trial.count_card(id)>=4
	for record in trial.deck:
		button("30灵露 · 删除 "+card_line(record),func():perform("buy",{"kind":"remove","id":str(record.instance_id)})).disabled=trial.dew<30 or trial.deck.size()<=10 or int(trial.progress.get("shop_removes",0))>=2
	label("删除最多两次，至少10张。删除前可查看构筑，留足攻击与关键工具。")
	button("结束购物并休整",func():perform("shop_done"))

func perform(kind: String, args: Dictionary={}) -> bool:
	if busy or trial==null or save_pending:return false
	if party_session!=null:party_session.choose(kind,args);return true
	var before: Dictionary=trial.snapshot()
	if not trial.command(kind,args,"local:%d:%s" % [trial.revision,kind],trial.revision):last_message="当前操作不可用，未消耗资源。";show_menu();return false
	if not save_run():
		trial.import_snapshot(before,str(before.school));save_pending=false
		last_message="保存失败，刚才的操作已撤回，未消耗资源。";show_menu();return false
	last_message=""
	if trial.state=="NODE_COMPLETE":advance()
	else:show_menu()
	return true

func advance() -> void:
	if busy or trial.state!="NODE_COMPLETE":return
	busy=true
	var previous_room: int=tower.current_room
	var next_floor:=mini(2,int((trial.node_index+1)/3))
	if previous_room!=next_floor and not await tower.move_to(next_floor):busy=false;last_message="转场失败，仍在原节点，可重试。";show_menu();return
	var before: Dictionary=trial.snapshot()
	if not trial.command("advance",{},"advance:%d" % trial.node_index,trial.revision) or not save_run():
		trial.import_snapshot(before,str(before.school));save_pending=false
		if tower.current_room!=previous_room:await tower.move_to(previous_room)
		last_message="推进未保存，节点未改变，可重试。"
	busy=false;show_menu()

func suspend() -> void:
	if in_battle or busy:return
	if not save_run():show_menu();return
	running=false;preparing=false;panel.hide();await tower.leave()

func find_battle_spot() -> Vector3:
	var room: Node3D=tower.rooms[tower.current_room]
	return room.to_global(room.arena_local) if room.arena_local.is_finite() else Vector3.INF

func start_battle() -> void:
	if busy or in_battle or not running or trial.state!="SAFE":return
	var spot:=find_battle_spot()
	if not spot.is_finite():last_message="战场准备失败，可重试。";show_menu();return
	busy=true
	if party_session==null:
		var before: Dictionary=trial.snapshot()
		if not trial.command("battle",{},"battle:%d" % trial.node_index,trial.revision) or not save_run():
			trial.import_snapshot(before,str(before.school));save_pending=false;busy=false;last_message="开战状态未保存，尚未开战。";show_menu();return
	else:trial.state="BATTLE"
	in_battle=true;panel.hide();tower.world.input_suspended=true;tower.world.player.hide()
	stage=load("res://scenes/fusion_3d/battle_stage.tscn").instantiate();stage.embedded=true
	stage.trial_context=party_session.trials[0] if party_session!=null else trial
	if party_session!=null:stage.shared_session=party_session;party_session.stage=stage
	stage.encounter_id="garden_familiars";stage.position=spot;tower.world.add_child(stage)
	stage.shell.embedded_world_mode=true;_tag_branch(stage);stage.camera.environment=tower.world.camera.environment;stage.camera.cull_mask=tower.ROOM_LAYER;stage.camera.current=true
	if party_session==null:stage.encounter_finished.connect(battle_finished)
	busy=false

func _tag_branch(node: Node) -> void:
	if node is GeometryInstance3D:node.layers=tower.ROOM_LAYER
	if not node.child_entered_tree.is_connected(_tag_branch):node.child_entered_tree.connect(_tag_branch)
	for child in node.get_children():_tag_branch(child)

func battle_finished(_winner: int) -> void:
	if busy or not in_battle:return
	busy=true
	if not trial.settle(stage.engine):last_message="拒绝重复或无效战斗结算。"
	stage.queue_free();stage=null;await get_tree().process_frame
	tower.world.player.show();tower.world.camera.current=true;tower.reset_to_safe();in_battle=false;busy=false
	save_run();show_menu()

func request_abandon() -> void:
	if party_session!=null:party_session.request_flee();return
	confirm("放弃本局？","本局将结束。战斗中无法保存续打，不发本场奖励。",abandon)

func abandon() -> void:
	if trial==null or busy:return
	var before: Dictionary=trial.snapshot()
	if trial.state not in ["SUCCESS","FAILED","ABANDONED"]:trial.command("abandon",{},"abandon:%d" % trial.revision)
	if not save_run():
		trial.import_snapshot(before,str(before.school));save_pending=false
		if in_battle:
			var error_dialog:=AcceptDialog.new();error_dialog.title="未能保存结束状态";error_dialog.dialog_text=last_message;tower.layer.add_child(error_dialog)
			error_dialog.confirmed.connect(error_dialog.queue_free);error_dialog.canceled.connect(error_dialog.queue_free);error_dialog.popup_centered()
		else:show_menu()
		return
	if is_instance_valid(stage):stage.queue_free();stage=null;await get_tree().process_frame
	in_battle=false;tower.world.player.show();tower.world.camera.current=true
	finish()

func finish() -> void:
	if busy:return
	if party_session!=null:party_session.abort("试炼已结束");return
	if trial!=null and trial.state not in ["SUCCESS","FAILED","ABANDONED"]:request_abandon();return
	if trial!=null and not save_run():show_menu();return
	running=false;preparing=false;panel.hide();await tower.leave()

func show_relics() -> void:show_menu()
func show_secondary() -> void:show_menu()
func relic_choice(id: String, action: Callable) -> void:
	var data: Dictionary=preload("res://scripts/tower_v01/relic_catalog.gd").DATA[id]
	var choice:=button(str(data.name)+"\n"+str(data.text),action)
	choice.icon=Art.framed_relic(id);choice.expand_icon=true;choice.custom_minimum_size.y=88

func relic_display(id: String) -> void:
	var data: Dictionary=preload("res://scripts/tower_v01/relic_catalog.gd").DATA.get(id,{"name":id,"text":""})
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);column.add_child(row)
	Art.icon(Art.framed_relic(id),Vector2(70,70),row)
	var text:=Label.new();text.text=str(data.name)+"\n"+str(data.text);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;text.custom_minimum_size.x=480;row.add_child(text)
