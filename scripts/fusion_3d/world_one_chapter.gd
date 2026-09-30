extends "res://scripts/fusion_3d/chapter_one.gd"
const THRESHOLDS=[0,120,300,540,840,1200,1620,2100,2640,3240]
var world: Node3D
var progress: Dictionary={}
var beacons: Array[String]=[]
var selected_beacon := "beacon_fire"
var active_encounter_id := "garden_familiars"
var active_quest := ""
var journal: PanelContainer
var journal_text: RichTextLabel
var travel_buttons: VBoxContainer
var visited: Array[String]=["campus"]
var side_done: Array[String]=[]
var journal_clock:=0.0
var tracked_side := ""
var equipped_title := ""
var side_tasks := [
 {"id":"dorm","title":"宿舍失物","zone":"campus","min":2,"objects":["遗落的围巾","书包上的姓名牌"],"reward":"细心的新生"},
 {"id":"lamps","title":"桥头的夜灯","zone":"fire","min":3,"objects":["西桥灯芯","东桥灯芯","备用灯油"],"reward":"点灯人"},
 {"id":"lunch","title":"冻住的午餐","zone":"ice","min":7,"objects":["保温符文","结冰的餐盒"],"reward":"热心同窗"},
 {"id":"shelves","title":"归位的书页","zone":"myth","min":7,"objects":["目录页","散落的注释","借阅记录"],"reward":"档案守护者"},
 {"id":"pet","title":"迷路的小兽","zone":"forest","min":21,"objects":["小兽的足迹","食盆","安全窝巢"],"reward":"林间朋友"},
 {"id":"names","title":"无人遗忘","zone":"graveyard","min":27,"objects":["褪色的碑文","旧照片","花束"],"reward":"记忆守望者"},
 {"id":"tools","title":"矿工的工具","zone":"mine","min":25,"objects":["遗落的镐头","矿灯","工具箱"],"reward":"可靠的帮手"},
 {"id":"rematch","title":"同窗再切磋","zone":"balance","min":7,"objects":["同窗的挑战书"],"reward":"切磋之友"}
]
func configure(value: Node3D) -> void:
	super.configure(value)
	world=preload("res://scripts/fusion_3d/world_one_regions.gd").new()
	town.add_child(world)
	world.configure(town,self)
	_build_side_tasks()
	_build_journal()
	if not equipped_title.is_empty():equip_title(equipped_title)
	if step>=7:
		var zone: String=steps[mini(step,steps.size()-1)].get("zone","campus")
		if world.zone_names.has(zone):travel(zone,false)
	update_ui()
func level() -> int:
	var result:=1
	for i in THRESHOLDS.size():
		if xp>=THRESHOLDS[i]:result=i+1
	return result
func available_quests() -> Array:
	if step>=steps.size():return []
	if step>=14 and step<=20:
		var result: Array=[]
		for i in range(14,21):
			if not beacons.has(str(steps[i].id)):result.append(steps[i])
		return result
	return [steps[step]]
func current_quest() -> Dictionary:
	var choices:=available_quests()
	if choices.is_empty():return {}
	if step>=14 and step<=20:
		for q in choices:
			if q.id==selected_beacon:return q
	return choices[0]
func current_id() -> String:
	return str(current_quest().get("id","complete"))
func target() -> String:
	if not tracked_side.is_empty() and not side_done.has(tracked_side):
		for task in side_tasks:
			if task.id==tracked_side:
				for i in task.objects.size():
					var sid: String="side_"+task.id+"_"+str(i)
					if not progress.has(sid):return sid
	if step<7:return super.target()
	var q:=current_quest()
	if q.is_empty():return "keeper"
	for i in q.objects.size():
		var id: String=q.target+"_"+str(i)
		var expected: int=i+1 if q.kind=="puzzle" else 1
		if int(progress.get(id,0))!=expected:return id
	return q.target
func _process(delta: float) -> void:
	if world==null:return
	var at: Vector3=points.get(target(),Vector3.ZERO)
	marker.position=at+Vector3(0,4.3+sin(Time.get_ticks_msec()*0.002)*0.18,0)
	marker.visible=town.battle==null and not town.dialogue.visible and step<steps.size()
	if town.battle==null:
		var name_text: String=current_quest().get("text","第一世界完成 · 星仪已重启")
		var dist:=roundi(town.player.position.distance_to(at))
		town.quest_label.text="第一世界 · Lv."+str(level())+" · XP "+str(xp)+" / 3240\n"+name_text+" · "+str(dist)+" m · E 互动 / J 调查簿"
	journal_clock+=delta
	if journal_clock>0.5:world.refresh();journal_clock=0
func interact() -> bool:
	if world==null:return super.interact()
	for id in world.gates:
		var gate: Dictionary=world.gates[id]
		if town.player.position.distance_to(gate.at)<3.8:
			if gate.to=="preview":
				if step<33:continue
				town.active_dialogue="chapter";pending="next_world";town.reply.text="返回探索"
				town.dialogue_label.text="星门巡检完成。坐标指向学院之外的一片陌生大陆。\n第一世界已经完成，你可以继续探索与收集称号。下一世界暂未开放。"
				town.dialogue.show();return true
			if step>=int(gate.min):travel(gate.to)
			else:town.hint.text="道路尚未开放，请先完成："+str(current_quest().get("title","当前调查"))
			return true
	for task in side_tasks:
		if step<int(task.min) or side_done.has(str(task.id)):continue
		for i in task.objects.size():
			var sid: String="side_"+task.id+"_"+str(i)
			if town.player.position.distance_to(points[sid])<3.2:
				open(sid);return true
	if step<7:return super.interact()
	var nearest:=""
	var distance:=3.8
	for q in available_quests():
		var ids: Array=[q.target]
		for i in q.objects.size():ids.append(q.target+"_"+str(i))
		for id in ids:
			var gap: float=town.player.position.distance_to(points[id])
			if gap<distance:nearest=id;distance=gap;selected_beacon=q.id
	if nearest.is_empty():return false
	open(nearest)
	return true
func open(id: String) -> void:
	if id.begins_with("side_"):
		pending=id;town.active_dialogue="chapter";town.reply.text="记录并帮助同学"
		for task in side_tasks:
			if id.begins_with("side_"+str(task.id)+"_"):
				town.dialogue_label.text=str(task.title)+"\n调查物品："+str(task.objects[int(id.get_slice("_",2))])+"\n完成全部调查将获得称号「"+str(task.reward)+"」。支线不影响主线经验。"
				if task.id=="rematch":town.reply.text="进入友谊切磋"
		town.dialogue.show();return
	if not id.begins_with("w_"):
		super.open(id)
		if id=="gardener" and step>=6:town.dialogue_label.text="萝温：调查记录已经归档。温室入口就在附近。循着引流管继续追查，我们会在学院接应你。"
		return
	pending=id
	town.active_dialogue="chapter"
	var q:=current_quest()
	var text: String=q.get("dialogue","")
	for i in q.get("objects",[]).size():
		if id==str(q.target)+"_"+str(i):
			text+="\n\n"+str(q.objects[i])+" · "+("当前刻度 "+str(progress.get(id,0))+"，目标 "+str(i+1) if q.kind=="puzzle" else ("已记录" if progress.has(id) else "尚未记录"))
	if id==q.get("target","") and target()!=id:text+="\n\n先完成所有现场调查点；金色标记指向下一个位置。"
	if q.get("kind","")=="choice":text+="\n\n点击继续交换记录；按 V 选择非致命切磋。"
	town.dialogue_label.text=text
	town.reply.text="旋转一格" if q.get("kind","")=="puzzle" and id!=q.target else "继续"
	town.dialogue.show()
func advance() -> void:
	if pending.begins_with("side_"):
		town.dialogue.hide()
		for task in side_tasks:
			if pending.begins_with("side_"+str(task.id)+"_") and not side_done.has(str(task.id)):
				if task.id=="rematch":
					start_encounter({"id":"side_rematch","encounter":"garden_familiars","target":pending});return
				progress[pending]=1
				var done:=true
				for i in task.objects.size():
					if not progress.has("side_"+str(task.id)+"_"+str(i)):done=false
				if done:side_done.append(str(task.id));tracked_side="";town.hint.text="获得称号："+str(task.reward)
				save();update_ui();return
		return
	if step<7:
		active_encounter_id="garden_familiars"
		active_quest=current_id()
		super.advance()
		return
	town.dialogue.hide()
	tracked_side=""
	var q:=current_quest()
	if q.is_empty():return
	for i in q.objects.size():
		var id: String=q.target+"_"+str(i)
		if pending==id:
			progress[id]=(int(progress.get(id,0))+1)%4 if q.kind=="puzzle" else 1
			save();update_ui()
			return
	if pending!=q.target or target()!=q.target:return
	if not str(q.encounter).is_empty() and q.kind!="choice":start_encounter(q)
	else:complete_step()
func start_encounter(q: Dictionary) -> void:
	active_encounter_id=q.encounter
	active_quest=q.id
	encounter_active=true
	checkpoint=points[q.target]+Vector3(0,0.15,6)
	town.battle_origin=points[q.target]+Vector3(0,0.12,0)
	save()
	world.refresh()
	town.begin_battle()
func complete_step() -> void:
	if step>=steps.size():return
	var q:=current_quest()
	if not rewards.has(str(q.id)):
		rewards.append(str(q.id));xp+=int(q.xp)
	if str(q.id).begins_with("beacon_"):
		if not beacons.has(str(q.id)):beacons.append(str(q.id))
		step=21 if beacons.size()==7 else 14
	else:step+=1
	if step<=7:checkpoint=points.gardener+Vector3(0,0.12,2) if step>=4 else Vector3(0,0.12,7)
	else:checkpoint=town.player.position+Vector3(0,0.1,0)
	if step==steps.size():_graduation()
	save();update_ui()
	if world:town.hint.text="调查完成 · +"+str(q.xp)+" XP · Lv."+str(level())+"。按 J 查看下一段路线。"
func battle_finished(winner: int) -> void:
	if not encounter_active:return
	encounter_active=false
	town.player.position=checkpoint
	if active_quest=="side_rematch":
		if winner==0 and not side_done.has("rematch"):side_done.append("rematch");tracked_side=""
	elif winner==0 and active_quest==current_id():complete_step()
	else:town.hint.text="小队已撤回安全点。调查记录保留，可调整编组再次挑战。"
	active_quest=""
	save();update_ui()
func update_ui() -> void:
	super.update_ui()
	if world:world.refresh()
	if journal_text:refresh_journal()
func unlocked(zone: String) -> bool:
	return step>=int({"greenhouse":7,"channel":10,"ruins":12,"forest":21,"camp":23,"mine":25,"graveyard":27,"loom":30}.get(zone,0))
func travel(zone: String, persist: bool=true) -> void:
	if not unlocked(zone) or town.battle!=null:return
	var at: Vector3=world.centers.get(zone,Vector3.ZERO)
	checkpoint=at+Vector3(0,0.15,26) if world.zone_names.has(zone) else at+Vector3(0,0.15,7)
	town.player.position=checkpoint
	town.zone_label.text=world.zone_names.get(zone,"学院区域")
	town.player.velocity=Vector3.ZERO
	town.overview=false
	town.view_controller.set_capture(false)
	if not visited.has(zone):visited.append(zone)
	if journal:journal.hide()
	if persist:save()
func _build_journal() -> void:
	journal=PanelContainer.new()
	journal.position=Vector2(250,85)
	journal.size=Vector2(820,700)
	town.hud.add_child(journal)
	var row:=HBoxContainer.new();journal.add_child(row)
	journal_text=RichTextLabel.new();journal_text.custom_minimum_size=Vector2(510,650);journal_text.bbcode_enabled=true;row.add_child(journal_text)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(280,650);row.add_child(scroll)
	travel_buttons=VBoxContainer.new();scroll.add_child(travel_buttons)
	journal.hide()
	# The journal is reached from the task icon or the existing J shortcut.
func toggle_journal() -> void:
	if town.icon_menu!=null:town.icon_menu.close()
	if town.battle!=null or town.dialogue.visible:return
	journal.visible=not journal.visible
	town.view_controller.set_capture(false)
	if journal.visible:refresh_journal()
func refresh_journal() -> void:
	var text:="[font_size=26]第一世界 · 调查记录[/font_size]\n等级 "+str(level())+"　经验 "+str(xp)+" / 3240\n已恢复信标 "+str(beacons.size())+" / 7\n\n"
	for q in steps:
		text+=("[color=#b8d1aa]✓ " if rewards.has(str(q.id)) else "[color=#ddd2bd]○ ")+str(q.title)+"[/color]\n"
	text+="\n[color=#dfbd76]当前线索[/color]\n"+str(current_quest().get("dialogue","星仪恢复运转。星门显示下一世界的坐标，目前可返回各区域继续探索。"))
	text+="\n\n成长：每级增加 45 点小队成员生命上限；3、5、7、9 级扩充可用法术。\n"
	text+="\n支线称号\n"
	for task in side_tasks:text+=("✓ "+str(task.reward) if side_done.has(str(task.id)) else "○ "+str(task.title))+"\n"
	journal_text.text=text
	for child in travel_buttons.get_children():travel_buttons.remove_child(child);child.queue_free()
	_add_button("关闭调查簿 [J]",toggle_journal)
	if step>=14 and step<=20:
		for q in available_quests():
			var qid: String=q.id
			_add_button("追踪 · "+str(q.title),func():tracked_side="";selected_beacon=qid;update_ui();journal.hide())
	for task in side_tasks:
		if side_done.has(str(task.id)):
			var earned: String=task.reward
			_add_button("佩戴 · "+earned,func():equip_title(earned))
		if step>=int(task.min) and not side_done.has(str(task.id)):
			var sid: String=task.id
			_add_button("支线 · "+str(task.title),func():tracked_side=sid;journal.hide())
	for zone in world.centers:
		if zone=="astral" or zone=="headmaster" or not unlocked(zone):continue
		var zid: String=zone
		var label: String=world.zone_names.get(zone,{"campus":"星仪广场","fire":"烈焰学院","ice":"冰霜学院","storm":"风暴学院","myth":"神话学院","life":"生命学院","death":"死亡学院","balance":"平衡学院"}.get(zone,zone))
		_add_button("前往 · "+label,func():travel(zid))
func _add_button(text: String, action: Callable) -> void:
	var button:=Button.new();button.text=text;button.pressed.connect(action);travel_buttons.add_child(button)
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_J:toggle_journal();get_viewport().set_input_as_handled()
		elif event.keycode==KEY_ESCAPE and journal and journal.visible:journal.hide();get_viewport().set_input_as_handled()
		elif event.keycode==KEY_V and town.dialogue.visible and current_id()=="camp_parley" and pending=="w_camp_parley":
			town.dialogue.hide();start_encounter(current_quest());get_viewport().set_input_as_handled()
func _graduation() -> void:
	if town.player_figure.get_node_or_null("GraduateMantle"):return
	var cape:=MeshInstance3D.new();cape.name="GraduateMantle"
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 8:
		for col in 8:
			for uv in [Vector2(col,row),Vector2(col+1,row+1),Vector2(col,row+1),Vector2(col,row),Vector2(col+1,row),Vector2(col+1,row+1)]:
				var u: float=uv.x/8.0;var v: float=uv.y/8.0
				surface.set_uv(Vector2(u,v));surface.add_vertex(Vector3((u-0.5)*(0.62+v*0.3),0.5-v*1.12,0.04+0.12*sin(u*PI)+0.08*v))
	surface.generate_normals();cape.mesh=surface.commit()
	cape.material_override=town._mat(Color("8563a8"))
	cape.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
	cape.position=Vector3(0,1,0.28)
	town.player_figure.add_child(cape)
func save() -> void:
	if not town.persist_progress:return
	Accounts.write_json(save_path,{"version":1,"step":step,"samples":samples,"rewards":rewards,"xp":xp,"progress":progress,"beacons":beacons,"visited":visited,"side_done":side_done,"equipped_title":equipped_title})
func load_progress() -> void:
	super.load_progress()
	if not town.persist_progress or not FileAccess.file_exists(save_path):return
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or int(data.get("version",0))!=1:return
	for id in data.get("side_done",[]):
		for task in side_tasks:
			if str(id)==str(task.id) and not side_done.has(str(id)):side_done.append(str(id))
	for task in side_tasks:
		if side_done.has(str(task.id)) and data.get("equipped_title","")==task.reward:equipped_title=task.reward
	progress=data.get("progress",{}) if data.get("progress",{}) is Dictionary else {}
	for id in data.get("beacons",[]):
		for i in range(14,mini(21,steps.size())):
			if str(id)==str(steps[i].id) and not beacons.has(str(id)):beacons.append(str(id))
	if step>=21:
		beacons.clear()
		for i in range(14,21):beacons.append(str(steps[i].id))
	elif step>=14:
		step=14
		for id in beacons:
			if not rewards.has(id):rewards.append(id);xp+=100
	if step==steps.size():_graduation()


func _build_side_tasks() -> void:
	for task in side_tasks:
		for i in task.objects.size():
			var sid: String="side_"+task.id+"_"+str(i)
			var at: Vector3=world.centers[task.zone]+Vector3(-16+i*15,0,16)
			points[sid]=at
			preload("res://scripts/fusion_3d/world_one_art_kit.gd").side_prop(world,task.id,at)
			town._sign(str(task.objects[i])+" · 支线",at+Vector3(0,2.2,0),19)

func equip_title(title: String) -> void:
	equipped_title=title
	var label: Label3D=town.player.get_node_or_null("EarnedTitle")
	if label==null:
		label=Label3D.new();label.name="EarnedTitle";label.font_size=25;label.pixel_size=0.004;label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.position=Vector3(0,3,0);town.player.add_child(label)
	label.text=title;label.modulate=Color("e8ca8b")
	save()


