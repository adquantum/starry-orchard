extends RefCounted
## Shared, battle-local lessons: no account cards, equipment or rewards are changed.
const Fixed = preload("res://scripts/server/star_orchard_fixed_lessons.gd")
const IDS := ["SO1_T01", "SO1_T02", "SO1_T03", "SO1_T04", "SO1_T05"]
const POSITIONS := [[221.6,226.51,-402.0],[303.2,226.51,-398.6],[350.8,250.31,-470.0],[310.0,277.51,-575.4],[401.8,277.51,-572.0]]
const LABELS := ["逐风庭", "花信回廊", "风铃桥庭", "初霜花圃", "星仪露台"]
const TITLES := ["星豆与等待", "辉豆与学派", "刃、虚弱、盾与陷阱", "持续伤害与持续治疗", "并肩夺铃"]

static func is_tutorial(id: String) -> bool:return id in IDS
static func lesson(id: String) -> int:return IDS.find(id) + 1

static func metadata(id: String) -> Dictionary:
	var n := lesson(id)
	if n == 0:return {}
	if Fixed.active(id):return Fixed.metadata(n)
	return {}

static func _enemy(id: String, slot: int, model: String, hp: int) -> Dictionary:
	var names := {"liferat01":"星莓寻宝鼠","stormbeatle":"蜜金甲虫","stormbee":"蜜叶蜂","lifepangolin":"苔晶穿山甲","icewolf":"霜莓幼狼","stormmudmonster":"苔露泥灵","stormwindeagle01":"暮霞风鹰"}
	var variants := {"stormbee":"orchard_honey_bee","stormmudmonster":"orchard_moss_slime","liferat01":"orchard_berry_rat","stormbeatle":"orchard_honey_beetle","lifepangolin":"orchard_jade_pangolin","icewolf":"orchard_berry_wolf","stormwindeagle01":"orchard_sunset_eagle"}
	var schools := {"liferat01":"life","stormbeatle":"storm","stormbee":"storm","lifepangolin":"ice","icewolf":"ice","stormmudmonster":"myth","stormwindeagle01":"storm"}
	var bases := {"life":"grove_priest","storm":"storm_wraith","ice":"frost_golem","myth":"myth_scholar"}
	var school: String=("ice" if slot==0 else "myth") if lesson(id)==5 else schools[model]
	var cards := Fixed.enemy_cards(lesson(id),school)
	var result := {"id":id+"_e"+str(slot),"base":bases[school],"name":names[model],"school":school,"model":model,"hp":hp,"deck":Fixed.counts(cards),"opening":cards.slice(0,7),"ai_profile":"orchard_lesson_"+str(lesson(id)),"archmastery":0,"starting_resources":{"normal":0,"power":0},"stats":{"accuracy_floor":{"*":1.0}}}
	if variants.has(model):result.variant_id=variants[model]
	if lesson(id)==5:
		result.hp=800 if slot==0 else 650
		result.ai_profile="orchard_finale"
		result.name="晶壳守铃人" if slot==0 else "蜜叶咒术师"
	return result

static func enemies(id: String, _humans: int = 1) -> Array:
	var n := lesson(id)
	if n == 0:return []
	var models: Array = [["liferat01"],["stormbee"],["lifepangolin"],["icewolf"],["lifepangolin","stormbee"]][n-1]
	var result: Array = []
	for i in models.size():result.append(_enemy(id,i,models[i],[280,380,680,880,380][n-1]))
	return result

static func all_sites() -> Array:
	var result: Array = []
	for i in IDS.size():
		var at: Array = POSITIONS[i].duplicate()
		var approach := [at[0],at[1],at[2]+14.0]
		result.append({"id":IDS[i],"encounter":IDS[i],"campaign_id":"star_orchard_world1_v2","order":i+1,"label":LABELS[i],"name":TITLES[i],"center":at,"approach":approach,"radius":18.0,"outer_radius":21.0,"scale":1.4,"yaw":0.0,"material":"soil","fixed_roam_height":true,"roam_surface_y":at[1],"battle_height_offset":0.0,"cooldown_seconds":5.0,"pvp":false,"requires_explicit_entry":true,"requires_victories":[] if i==0 else [IDS[i-1]],"enemies":enemies(IDS[i]),"tutorial":metadata(IDS[i])})
	return result

static func opening(id: String, school: String) -> Array:
	return Fixed.opening(lesson(id),school) if is_tutorial(id) else []

static func deck_counts(id: String, school: String) -> Dictionary:
	return Fixed.counts(opening(id,school))

static func configure_unit(engine: BattleEngineV2, id: String, unit: BattleUnitStateV2) -> bool:
	return Fixed.configure_unit(engine,lesson(id),unit) if is_tutorial(id) else false

static func configure_engine(engine: BattleEngineV2, id: String) -> bool:
	if not is_tutorial(id):return true
	var resolver := preload("res://scripts/server/star_orchard_tutorial_resources.gd").new()
	resolver.lesson=lesson(id)
	resolver.event_stream=engine.event_stream
	resolver.rng=engine.resource_resolver.rng
	resolver.school_pip_enabled=false
	resolver.shadow_pip_enabled=false
	engine.resource_resolver=resolver
	if Fixed.active(id):Fixed.register_cards(engine.content)
	if lesson(id)==5:Fixed.Finale.ensure_partner(engine)
	for unit in engine.state.units:
		if (unit.team==0 or Fixed.active(id)) and not configure_unit(engine,id,unit):return false
	return true
