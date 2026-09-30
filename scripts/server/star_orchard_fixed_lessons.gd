extends RefCounted
## Battle-local definitions; borrowed low-cost artwork never changes account cards.
const Finale = preload("res://scripts/server/star_orchard_finale.gd")
const BASE := {"fire":"fir_001", "ice":"ice_001", "storm":"sto_002", "life":"lif_005", "death":"dea_009", "myth":"myt_005", "balance":"bal_005"}

const SUMMON := {"fire":"fir_013","ice":"ice_013","storm":"sto_017","life":"lif_017","death":"dea_013","myth":"myt_013","balance":"bal_013"}
const BLADE := {"fire":"fir_003","ice":"ice_003","storm":"sto_003","life":"lif_003","death":"dea_003","myth":"myt_002","balance":"bal_003"}
const TRAP := {"fire":"fir_004","ice":"ice_007","storm":"sto_004","life":"lif_008","death":"dea_002","myth":"myt_003","balance":"bal_006"}
const AOE := {"fire":"fir_011","ice":"ice_010","storm":"sto_009","life":"lif_013","death":"dea_014","myth":"myt_010","balance":"bal_009"}

static func source_card(role: String, school: String) -> String:
	match role:
		"heavy","summon","borrowed","single","burst","slam":return SUMMON[school]
		"blade":return BLADE[school]
		"trap":return TRAP[school]
		"aoe":return AOE[school]
		"weakness":return "bal_002"
		"shield":return "ice_006"
		"dot":return "fir_006"
		"hot":return "lif_004"
		"double":return "myt_013"
	return BASE[school]

static func active(id: String) -> bool:
	return id in ["SO1_T01", "SO1_T02", "SO1_T03", "SO1_T04", "SO1_T05"]

static func card_id(role: String, school: String) -> String:
	return "orchard_lesson_"+role+"_"+school

static func opening(n: int, school: String) -> Array:
	if n==5:return Finale.deck(school)
	var roles: Array = [[],["light","light","light","heavy"],["light","light","light","summon","borrowed","shield","shield"],["blade","weakness","shield","shield","trap","summon","light"],["shield","hot","dot","trap","offlight","blade","homehit"],["blade","shield","aoe","single","light","light"]][n]
	return roles.map(func(role):return card_id(role,school))

static func counts(cards: Array) -> Dictionary:
	var result: Dictionary = {}
	for id in cards:result[id]=int(result.get(id,0))+1
	return result

static func register_cards(content: ContentRegistryV2) -> void:
	Finale.register_cards(content)
	for school in BASE:
		for role in ["light","offlight","homehit","heavy","summon","borrowed","blade","weakness","shield","trap","burst","sting","double","slam","tail","dot","hot","aoe","single","bite","flurry"]:
			var foreign: String = "storm" if school != "storm" else "fire"
			var actual_school: String = "myth" if role == "double" else (foreign if role in ["borrowed","offlight"] else school)
			actual_school = {"shield":"ice", "weakness":"balance", "hot":"life"}.get(role, actual_school)
			var source := content.card(StringName(source_card(role,actual_school)))

			var costs := {"light":1,"offlight":2,"homehit":2,"heavy":3,"summon":4,"borrowed":4,"blade":0,"weakness":0,"shield":0,"trap":0,"burst":3,"sting":1,"double":1,"slam":2,"tail":2,"dot":2,"hot":1,"aoe":3,"single":3,"bite":1,"flurry":1}
			var powers := {"light":80,"offlight":100,"homehit":100,"heavy":300,"summon":400,"borrowed":550,"burst":600,"sting":200,"slam":600,"tail":100,"aoe":300,"single":500,"bite":180,"flurry":100}
			var data := {"id":card_id(role,school),"name_key":str(source.name_key),"school":actual_school,"target":"self" if role in ["blade","shield","hot"] else ("all_enemies" if role == "aoe" else "enemy"),"pip_cost":costs[role],"accuracy":1.0,"learned":true,"art_path":source.art_path,"presentation":source.presentation.duplicate(true)}
			if role == "dot":
				data.name_key="CARD_ORCHARD_DOT_"+school.to_upper()+"_NAME"
				data.effects=[{"type":"damage","power":260},{"type":"apply_dot","damage_per_tick":160,"ticks":3}]
				data.tags=["damage","dot"]
			elif role in ["shield", "weakness"]:
				# Keep the native spell's targeting, effects, school, artwork and presentation.
				data.target=str(source.target_type)
				data.pip_cost=source.pip_cost
				data.accuracy=source.accuracy
				data.effects=source.effects.duplicate(true)
				data.tags=source.tags.duplicate()
			elif role == "hot":
				data.effects=[{"type":"heal","power":100},{"type":"apply_hot","healing_per_tick":100,"ticks":3}]
				data.tags=["heal","hot"]
				data.presentation={"template":"target_buff","impact":"magic_life_aura","camera":"camera_target_focus"}
			elif role == "double":
				# One spell, two damage events: weakness covers both; a shield is consumed by the first.
				data.effects=[{"type":"damage","power":40},{"type":"damage","power":200}]
				data.tags=["damage"]
			elif powers.has(role):
				data.effects=[{"type":"damage","power":powers[role]}]
				data.tags=["damage"]
			else:
				var values := {"blade":35,"weakness":-25,"shield":-50,"trap":30}
				data.effects=[{"type":"apply_status","status":role,"school_filter":school if role in ["blade","trap"] else "*","value":values[role]}]
				data.tags=["charm" if role in ["blade","weakness"] else "ward"]
				data.presentation={"template":"target_buff","impact":"magic_"+actual_school+"_aura","camera":"camera_target_focus"}
			data.presentation["source_card_id"]=str(source.id)
			data.presentation["teaching_variant"]=true
			var card := CardDefinitionV2.from_dict(data)
			content.cards[card.id]=card

static func configure_unit(engine: BattleEngineV2, n: int, unit: BattleUnitStateV2) -> bool:
	if n==5:return Finale.configure(engine,unit)
	var school := str(unit.school_id)
	var cards := opening(n,school) if unit.team == 0 else enemy_cards(n,school)
	if not engine.configure_deck(unit.id,counts(cards)):return false
	var pool: Array = unit.deck.hand.duplicate()
	pool.append_array(unit.deck.draw_pile)
	unit.deck.draw_pile.clear()
	unit.deck.hand.clear()
	for id in cards:
		for card in pool:
			if str(card.card_id()) == id:
				card.temporary=true # No fusion / treasure-credit loophole.
				if unit.deck.hand.size() < DeckStateV2.HAND_LIMIT:unit.deck.hand.append(card)
				else:unit.deck.draw_pile.append(card)
				pool.erase(card);break
	unit.deck.treasure_pile.clear();unit.deck.removed_cards.clear()
	unit.resources.clear_on_death();unit.statuses.clear();unit.archmastery=0
	unit.stats={"accuracy_floor":{"*":1.0}}
	unit.max_hp=500 if unit.team == 0 else [0,280,380,680,880,380][n]
	unit.hp=unit.max_hp
	if unit.team == 1:unit.ai_profile_id=StringName("orchard_lesson_"+str(n))
	return true

static func enemy_cards(n: int, school: String) -> Array:
	if n==5:return Finale.deck(school,false,true)
	var roles: Array = [[],["burst"],["sting","sting","sting","sting","sting","sting","sting","sting"],["slam","double","tail"],["bite","bite","bite","bite","bite","bite","bite","bite"],["flurry","flurry","flurry","flurry","flurry","flurry","flurry","flurry"]][n]
	return roles.map(func(role):return card_id(role,school))

static func enemy_action(engine: BattleEngineV2, unit: BattleUnitStateV2) -> ActionIntentV2:
	if unit.ai_profile_id==&"orchard_finale":return Finale.choose(engine,unit)
	var n := int(str(unit.ai_profile_id).get_slice("_",2))
	var round_number := engine.state.round_index
	var role := ""
	if n == 1 and round_number >= 3:role="burst"
	if n == 2:role="sting"
	if n == 3:
		if round_number == 2:role="slam"
		if round_number == 3:role="double"
		if round_number == 5:role="tail"
	if n == 4:role="bite"
	if n == 5:role="flurry"
	for card in unit.deck.hand:
		if not role.is_empty() and str(card.card_id()) == card_id(role,str(unit.school_id)) and engine.cost_resolver.can_pay(unit,card.definition):
			return ActionIntentV2.cast(unit.id,card.instance_id,[&"P0"])
	return ActionIntentV2.pass_turn(unit.id)

static func metadata(n: int) -> Dictionary:
	if n==5:return {"lesson":5,"title":"夺回引路铃","rounds":[],"intent":"","temporary_deck":true,"solo":true,"companion":true,"no_guidance":true,"planning_seconds":90}
	var titles := ["", "寻宝鼠的赃物", "蜜叶蜂的把戏", "桥上的守卫", "花圃里的追逐", "露台上的搭档"]
	# Short story beats. Announce mechanics before decisions, without prescribing a card.
	var lessons: Array = [[],[
		["风铃传讯", "那只果鼠偷走了引路星莓！星豆会逐回合积攒，等待也能为强大的法术争取机会。", "果鼠正把熟果塞进弹弓；第三回合才会发射。", true],
		["弹弓渐渐拉满", "小法术也会花掉星豆，想想下一次出手需要多少魔力。", "果鼠还在蓄力。", false],
		["就是现在", "这次你先出手。击败对手，就能打断它尚未发动的攻击。", "果鼠的弹弓已经拉满！", true]
	],[
		["花廊的守门蜂", "蜜叶蜂挡住了去路。星豆每颗支付1费，积攒魔力时也别忘了看看手中的法术学派。", "蜜叶蜂准备突刺，之后每回合都会追击。", true],
		["你获得了一颗辉豆", "辉豆支付本系法术时算2颗，支付异系只算1颗；它不会把伤害翻倍。", "蜜叶蜂本回合先手，再次举起蜂针。", true],
		["同样的豆，不同的价值", "你先出手。普通、辉豆、普通，支付本系算4，异系只算3。伤害更高的牌，也得先付得起费用。", "蜜叶蜂仍在追击；别让它继续逼近。", true]
	],[
		["晶壳守住了桥", "穿山甲抱紧晶壳，桥面开始颤动。盾能挡下一段伤害的50%，虚弱能削弱整个伤害法术的25%。", "它正在蓄力，下一回合会先手砸下重击。", true],
		["晶壳砸下来了", "这次重击只有一下。它下一回合还会连击：盾只挡一段，虚弱影响整个法术。", "穿山甲先砸下晶壳，随后开始准备神话连击。", true],
		["苔晶穿山甲", "“嘿嘿，瞧瞧我新学会的神话魔法！”\n\n你先出手。若盾牌被试探的一击消耗，还能挡住后面的重击吗？看看手中的刃与陷阱，或许正是为反击积蓄力量的时候。", "穿山甲即将使出两段攻击。", true],
		["露出破绽", "刃强化自己的法术，陷阱增加敌人受到的伤害。学派相符时，两者可以配合。", "穿山甲本回合喘息，下一回合会甩尾追击。", true],
		["别让它站稳", "你先出手，留意身上的刃与敌人身上的陷阱。", "穿山甲抬起了尾巴。", false]
	],[
		["花圃里的幼狼", "霜莓幼狼把引路铃当成了玩具！它跑得太快，先想办法站稳脚跟。", "幼狼正扑过来，之后也会紧追不舍。", true],
		["稳住呼吸", "持续治疗会在你之后的行动前恢复生命。别等倒下了才想起治疗。", "幼狼这回合先扑咬。", true],
		["留下魔法的余波", "持续伤害会在敌人行动前跳动，不再占你的出手机会。刃也能强化这个法术的后续伤害。", "你先出手，幼狼随后扑咬。", true],
		["布下后手", "陷阱只强化一次符合学派的伤害，包括持续伤害。同系攻击会先消耗本系陷阱，异系攻击则会把它留给后续跳伤。", "幼狼先行动，随后轮到你。", true],
		["铃声就在眼前", "看看剩余魔豆。两张单体攻击都要2豆，但它们的学派会影响身上的刃、敌人身上的陷阱。", "你先出手；幼狼行动前还会结算持续伤害。", true],
		["余波未散", "先前施下的魔法还没有结束。", "幼狼身上的持续伤害先于扑咬结算。", false]
	],[
		["最后一道关口", "风鹰和蜜叶蜂抢占了露台。群体法术能同时击中它们，刃的加成也会覆盖各个目标。", "两个家伙准备一同攻来。", true],
		["左右夹击", "盾只挡一次伤害。面对两个敌人，要留意谁先出手。", "风鹰先攻，轮到你之后，蜜叶蜂才会出手。", true],
		["夺回引路铃", "这回合你先动。别忘了，击败一个敌人，另一个仍会攻击。", "它们再次摆开了夹击的架势。", true]
	]]
	var rounds: Array = []
	for i in lessons[n].size():
		var tip: Array = lessons[n][i]
		rounds.append({"round":i+1,"title":tip[0],"text":tip[1],"intent":tip[2],"auto_prompt":tip[3]})
	return {"lesson":n,"title":titles[n],"rounds":rounds,"intent":rounds[0].intent,"temporary_deck":true,"solo":true,"planning_seconds":90}
