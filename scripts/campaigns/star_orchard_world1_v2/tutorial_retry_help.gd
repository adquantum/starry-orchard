extends RefCounted
## Local teaching preferences only; never grants progress or changes battle state.
const Fixed = preload("res://scripts/server/star_orchard_fixed_lessons.gd")
const SAVE_PATH := "user://orchard_retry_help.cfg"
const PLANS := [[], ["wait","wait","heavy"], ["shield","shield","summon"],
	["shield","weakness","blade","trap","summon"], ["shield","hot","dot","trap","offlight","wait"]]
const REASONS := {
	"wait":"先选择 PASS / 蓄能，把魔力留给关键法术；现在消耗魔力会错过反击时机。",
	"heavy":"敌人已经蓄力完毕，用这张强力攻击先击败它，就能阻止它出手。",
	"summon":"用本系的召唤攻击完成反击。辉豆更适合支付本系法术，别被异系卡牌的威力吸引。",
	"shield":"先给自己加盾，挡住即将到来的第一下攻击，为后续行动争取机会。",
	"weakness":"对敌人施放虚弱。它即将连击，虚弱会削弱整套攻击，比再放一面只能挡一下的盾更合适。",
	"blade":"给自己加刃，强化稍后的本系反击；现在还不是消耗魔力攻击的时候。",
	"trap":"给敌人放上本系陷阱，为后续伤害做好准备。",
	"hot":"现在给自己持续治疗，让接下来的回合继续恢复，才能顶住敌人的追击。",
	"dot":"对敌人施放持续伤害，让它在后续行动前继续受伤，腾出你的出手机会。",
	"offlight":"用这张异系攻击补上伤害，同时把本系陷阱留给持续伤害。"
}

static func lesson_number(id: String) -> int:
	return ["SO1_T01","SO1_T02","SO1_T03","SO1_T04"].find(id)+1

static func loss_count(character_id: String, id: String, path: String = SAVE_PATH) -> int:
	if character_id.is_empty() or lesson_number(id)==0:return 0
	var config:=ConfigFile.new()
	if config.load(path)!=OK:return 0
	return int(config.get_value(character_id,id,0))

static func record_loss(character_id: String, id: String, battle_id: String, path: String = SAVE_PATH) -> int:
	if character_id.is_empty() or lesson_number(id)==0 or battle_id.is_empty():return 0
	var config:=ConfigFile.new()
	config.load(path)
	var count:=int(config.get_value(character_id,id,0))
	if str(config.get_value(character_id,id+"_last_battle",""))==battle_id:return count
	count+=1
	config.set_value(character_id,id,count)
	config.set_value(character_id,id+"_last_battle",battle_id)
	var error:=config.save(path)
	if error!=OK:push_warning("Tutorial retry hint preference could not be saved: "+error_string(error))
	return count

static func recommendation(n: int, round_number: int, player: BattleUnitStateV2, content: ContentRegistryV2) -> Dictionary:
	if n<1 or n>4 or round_number<1 or round_number>PLANS[n].size() or player==null:return {}
	var role: String=PLANS[n][round_number-1]
	if role=="wait":return {"title":"这回合选择 PASS / 蓄能", "text":"选择 PASS / 蓄能，让先前施下的持续伤害在敌人行动前完成追击。" if n==4 else REASONS[role], "role":role, "card_id":""}
	var id:=Fixed.card_id(role,str(player.school_id))
	var definition:=content.card(StringName(id))
	if definition==null:return {}
	var title:=Locale.text(str(definition.name_key))
	var position:=-1
	for i in player.deck.hand.size():
		if str(player.deck.hand[i].card_id())==id:position=i+1;break
	var target:="自己" if definition.target_type in [&"self",&"ally",&"all_allies"] else "敌人"
	var instruction:="选择从左往右第 %d 张《%s》，对%s使用。" % [position,title,target] if position>0 else "建议保留《%s》，在这一回合对%s使用。当前手牌已与提示路线不同，可以重试时按提示操作。" % [title,target]
	var reason: String=REASONS[role]
	if n==3 and role=="summon":reason="刃与陷阱已经准备好，现在用本系召唤攻击完成反击，赶在敌人再次出手之前击败它。"
	return {"title":"这回合选择《"+title+"》", "text":instruction+"\n\n"+reason, "role":role, "card_id":id}
