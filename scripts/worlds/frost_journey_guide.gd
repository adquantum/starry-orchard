extends CanvasLayer
## Read-only guidance; completion and first-clear rewards come from the account ledger.
var manager: Node
var sites: Array = []
var panel: PanelContainer
var heading: Label
var detail: Label
var navigation: Control
var target: Dictionary = {}
var tick := 0.0

func setup(encounter_manager: Node, definitions: Array) -> void:
	manager=encounter_manager;layer=21
	for definition in definitions:
		if not bool(definition.get("pvp",false)) and not definition.get("enemies",[]).is_empty():sites.append(definition)
	# Match the map destination list and the authored route, including every camp.
	sites.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		return int(a.get("challenge_order",a.order)) < int(b.get("challenge_order",b.order)))
	panel=PanelContainer.new()
	panel.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left=-322;panel.offset_right=-22;panel.offset_top=334;panel.offset_bottom=466
	panel.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var column:=VBoxContainer.new();column.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(column)
	heading=Label.new();heading.add_theme_font_size_override("font_size",19);heading.add_theme_color_override("font_color",Color("ffdd91"));heading.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(heading)
	detail=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.add_theme_font_size_override("font_size",19);detail.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(detail)
	for label in [heading,detail]:
		label.add_theme_color_override("font_shadow_color",Color.BLACK)
		label.add_theme_constant_override("shadow_outline_size",5)
	navigation=preload("res://scripts/fusion_3d/quest_indicator.gd").new()
	navigation.objective_provider=self;add_child(navigation);navigation.setup(manager.world)
	_refresh()

func _process(delta: float) -> void:
	if not is_instance_valid(manager) or panel==null:return
	panel.visible=not _battle_busy() and not is_open()
	if is_instance_valid(manager.atlas.player_minimap):
		var map_rect: Rect2=manager.atlas.player_minimap.get_global_rect()
		panel.position=Vector2(map_rect.position.x,map_rect.end.y+12)
		panel.size=Vector2(map_rect.size.x,132)
		panel.visible=panel.visible and manager.atlas.player_minimap.visible and not manager.atlas.player_minimap.expanded
	navigation.refresh()
	if not panel.visible:return
	tick+=delta
	if tick<0.2:return
	tick=0.0;_refresh()

func _refresh() -> void:
	var cleared: Array=Accounts.progression_snapshot.get("frost_cleared_sites",[])
	target={}
	var done:=0
	for candidate in sites:
		if str(candidate.id) in cleared:done+=1
		elif target.is_empty():target=candidate
	heading.text="寒冰岛挑战  %d / %d" % [done,sites.size()]
	if target.is_empty():
		detail.text="已完成全部营地挑战！\n可继续收集赋能、完善装备与卡组。"
		navigation.refresh();return
	var names: Array[String]=[]
	for enemy in target.enemies:
		var enemy_name:=str(enemy.name)
		if enemy_name not in names:names.append(enemy_name)
	detail.text="下一站：%s\n击败：%s\n首次击败：3 倍赋能\n右下角「队伍」可召唤 AI 队友" % [str(target.name),"、".join(names)]
	navigation.refresh()

func shown_objective() -> Dictionary:
	return {} if target.is_empty() else {"id":str(target.id),"kind":"battle","arrival_distance":7.0,"arrival_text":"已到达 · 走入战斗盘开始"}

func objective_point() -> Vector3:
	return Vector3.ZERO if target.is_empty() else manager.world.to_global(Vector3(float(target.center[0]),float(target.center[1]),float(target.center[2])))

func _objective_text(_objective: Dictionary) -> String:
	return "" if target.is_empty() else str(target.name)

func _battle_busy() -> bool:
	return not is_instance_valid(manager.world) or not manager.world.ready_world or manager.atlas.busy or manager.active or manager.session.active_local or manager.world.input_suspended

func is_open() -> bool:
	return is_instance_valid(manager.atlas.player_minimap) and manager.atlas.player_minimap.expanded
