extends Node
## Exploration progression only. No turn or effect rules are implemented here.
var town: Node3D
var steps: Array = []
var step := 0
var xp := 0
var samples: Array[String] = []
var rewards: Array[String] = []
var save_path := "user://academy_chapter_one.json"
var pending := ""
var encounter_active := false
var checkpoint := Vector3(0,0.12,7)
var marker: Node3D
var points := {
	"keeper":Vector3(-3,0,3), "prefect":Vector3(2,0,20),
	"orrery":Vector3(0,0,-11), "gardener":Vector3(65,0,12),
	"sample_a":Vector3(70,0,-15), "sample_b":Vector3(92,0,13),
	"encounter":Vector3(78,0,9)
}
func configure(value: Node3D) -> void:
	town = value
	save_path=Accounts.path_for("academy_chapter_one.json")
	for id in points: points[id]=town.world_point(id)
	steps = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/chapter_one.json")).steps
	load_progress()
	town._citizen("gardener","萝温 · 生命学院教授",4,points.gardener)
	marker = town._cylinder(Vector3.ZERO,0.20,0.60,Color("e4c479"),true)
	marker.material_override = town._mat(Color("d4bb78"),true)
	if step > 0: town.player.position = checkpoint
	update_ui()
func current_id() -> String:
	return str(steps[step].id) if step < steps.size() else "complete"
func target() -> String:
	if step >= steps.size(): return "gardener"
	if current_id()=="samples": return "sample_b" if samples.has("sample_a") else "sample_a"
	return str(steps[step].target)
func _process(_delta: float) -> void:
	if not is_instance_valid(town) or marker == null: return
	var at: Vector3 = points[target()]
	marker.position = at+Vector3(0,4.3+sin(Time.get_ticks_msec()*0.002)*0.18,0)
	marker.visible = town.battle == null and not town.dialogue.visible and step < steps.size()
	if town.battle == null:
		var distance := Vector2(town.player.position.x-at.x,town.player.position.z-at.z).length()
		var direction := "东 →" if at.x-town.player.position.x>5 else ("← 西" if at.x-town.player.position.x< -5 else ("北 ↑" if at.z<town.player.position.z else "南 ↓"))
		town.quest_label.text = "第一章 · "+("第一份调查已完成" if step>=steps.size() else str(steps[step].text))+"\n"+("见习徽章已领取 · 温室区域将在后续开放" if step>=steps.size() else direction+"  "+str(roundi(distance))+" m  · 靠近按 E")+"  · XP "+str(xp)
func interact() -> bool:
	var closest := ""
	var distance := 3.8
	for id in points:
		var gap: float = town.player.position.distance_to(points[id])
		if gap<distance:
			distance=gap
			closest=id
	if closest.is_empty(): return false
	open(closest)
	return true
func open(id: String) -> void:
	pending = id
	town.active_dialogue = "chapter"
	town.reply.text = "继续"
	var text := ""
	match id:
		"keeper":
			text = "Astra：欢迎来到 Arcane Academy。你只是今天报到的新生，不必急着证明什么。先去南边宿舍找 Elowen，和三位同学组成调查小队。"
			if step>0: text = "Astra：星仪的七个节点刚才同时停顿了。也许只是旧设施的毛病。你可以在星仪南侧观测台记录一次读数。"
		"prefect":
			text = "Elowen：四人互相照应。火系攻坚、冰系守护、生命援护、风暴爆发是一个起点，也可以选择其他学院。确认编组后，你将代表 P1 行动。"
			if current_id()=="party": town.reply.text="选择并确认四人小队"
		"orrery":
			text = "World Orrery\n七枚符文短暂失去光芒，随后恢复。生命节点旁留下了一丝橙红色残影。记录已记入调查簿：沿东南拱桥前往生命花园询问萝温教授。"
		"gardener":
			text = "萝温：欢迎来到生命花园。北边的植株发烫，东边的根系却在结晶。请分别取样，别碰圆庭里的守护灵。"
			if current_id()=="report": text="萝温：你做得很好。守护灵已经平静，但样本中同时有火系和风暴能量。温室的引流管可能出了问题。收下见习徽章，下一次我们去调查废弃温室。"
			elif current_id()=="complete": text="萝温：第一份调查已经归档。你可以继续游览或到东门练习决斗；废弃温室将在下一段开放。"
		"sample_a": text="异常植株\n叶缘带着不自然的余烬。取下少量样本，瓶壁微微发热。"
		"sample_b": text="结晶根系\n细小的电弧掠过树根。它不属于生命学院。两种能量都指向圆庭的失控守护灵。"
		"encounter":
			text="四只花园守护灵被裂隙能量干扰。先集中处理一个目标，用护盾和治疗保护队友。法阵将在这座圆庭原地展开。"
			if current_id()=="duel": town.reply.text="进入花园 4v4 决斗"
	if id != target() and not (current_id()=="samples" and id in ["sample_a","sample_b"]):
		text += "\n\n当前目标："+("调查已完成。" if step>=steps.size() else str(steps[step].text))
	town.dialogue_label.text=text
	town.dialogue.show()
func advance() -> void:
	town.dialogue.hide()
	if current_id()=="party" and pending=="prefect":
		town.party_panel.show()
		return
	if current_id()=="samples" and pending in ["sample_a","sample_b"]:
		if not samples.has(pending): samples.append(pending)
		if samples.size()==2: complete_step()
		save()
		return
	if pending != target(): return
	if current_id()=="duel":
		encounter_active=true
		checkpoint=points.gardener+Vector3(0,0.12,2)
		save()
		town.battle_origin=town.layout_vector(town.world_layout.garden_arena)
		town.begin_battle()
	elif current_id()!="complete":
		complete_step()
func party_confirmed() -> void:
	if current_id()=="party": complete_step()
func complete_step() -> void:
	if step>=steps.size(): return
	var id := current_id()
	if not rewards.has(id):
		rewards.append(id)
		xp += int(steps[step].xp)
	step += 1
	checkpoint = points.gardener+Vector3(0,0.12,2) if step>=4 else Vector3(0,0.12,7)
	save()
	update_ui()
func battle_finished(winner: int) -> void:
	if not encounter_active: return
	encounter_active=false
	town.player.position=checkpoint
	if winner==0 and current_id()=="duel":
		complete_step()
		town.hint.text="守护灵恢复平静。向萝温报告调查结果。"
	else:
		town.hint.text="已退回萝温身边，调查样本保留。调整卡组后可再次挑战。"
	save()
func update_ui() -> void:
	var sign_node := town.get_node_or_null("GardenEncounterSign")
	if sign_node != null and step>=6: sign_node.text="花园守护灵 · 已恢复平静"
	if town.quest_label != null: town.quest_label.text="第一章 · "+current_id()
func save() -> void:
	if not town.persist_progress: return
	var data: Dictionary=({"version":1,"step":step,"samples":samples,"rewards":rewards,"xp":xp})
	Accounts.write_json(save_path,data)
func load_progress() -> void:
	if not town.persist_progress or not FileAccess.file_exists(save_path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or int(data.get("version",0))!=1: return
	step=clampi(int(data.get("step",0)),0,steps.size())
	# Derive reward totals from completed steps; reject inflated or repeated rewards.
	for i in step:
		rewards.append(str(steps[i].id))
		xp+=int(steps[i].xp)
	for id in data.get("samples",[]):
		if str(id) in ["sample_a","sample_b"] and not samples.has(str(id)): samples.append(str(id))
	checkpoint=points.gardener+Vector3(0,0.12,2) if step>=4 else Vector3(0,0.12,7)

