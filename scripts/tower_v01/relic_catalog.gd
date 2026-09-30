extends RefCounted
const DATA := {
	"ready_seed":{"name":"备战果核","text":"每场开局额外 1 普通豆。","icon":"bal_010"},
	"swift_flask":{"name":"迅捷雷瓶","text":"每回合首次实付 1–2 豆的单体直伤 +25%；同次施法的多段共享倍率。","icon":"sto_002"},
	"charged_core":{"name":"蓄能星核","text":"每场首次实付至少 4 豆的主动攻击，直伤分量 +20%。","icon":"myt_013"},
	"ember_wick":{"name":"余烬灯芯","text":"施加 DoT 时，每跳基础伤害 +25%；引爆不重复放大。","icon":"fir_006"},
	"detonation_seed":{"name":"引爆火种","text":"主动引爆实际消耗 DoT 后返 1 普通豆；每次施法至多一次、每场两次。","icon":"fir_012"},
	"frost_thorn":{"name":"冰晶棘环","text":"自己施加的盾真实抵挡并被消耗后，反击 35 冰伤；每回合一次、每场三次，不消耗刃或陷阱。","icon":"ice_006"},
	"abundance_pod":{"name":"丰饶种荚","text":"付费主动即时治疗的溢出 40% 转为吸收盾；每场两次，单个目标该来源盾不超过最大 HP 的 10%。","icon":"lif_004"},
	"shadow_ledger":{"name":"冥影账簿","text":"主动法术真实自损后，下一次主动吸血直伤 +20%；每场充能两次，不叠层。","icon":"death_empower"},
	"seal_shard":{"name":"破印碎片","text":"主动拆除或偷取敌方正面状态后，下一张主动直伤 +20%；每场充能两次。","icon":"myt_004"},
	"twin_scales":{"name":"双生天秤","text":"连续两次成功付费的不同学院牌后，下一张主动直伤或即时治疗 +15%。","icon":"bal_010"},
	"steady_pips":{"name":"稳息豆纹","text":"自身本局强力豆生成率从 40% 提高到 48%。","icon":"ice_003"},
	"travel_supply":{"name":"旅人补给","text":"胜利结算恢复持有者最大 HP 的 10%；同一场不能重复领取。","icon":"lif_004"}
}

static func descriptions() -> Dictionary:
	var result: Dictionary={}
	for id in DATA:result[id]=DATA[id].name+"："+DATA[id].text
	return result

static func eligible(id: String,trial: RefCounted) -> bool:
	var kinds: Dictionary={};var schools: Dictionary={};var cheap:=false;var large:=false;var shield:=false;var removes_enemy:=false
	for record in trial.deck:
		removes_enemy=removes_enemy or preload("res://scripts/tower_v01/trial_rules.gd").removes_enemy_buff(trial.sources[record.base_spell_id])
		var card: CardDefinitionV2=trial.definition(record,false)
		if card.pip_cost>0:schools[str(card.school_id)]=true
		for effect in card.effects:
			kinds[str(effect.type)]=true
			if str(effect.type) in ["damage","drain"]:
				cheap=cheap or (card.pip_cost in [1,2] and card.target_type==&"enemy")
				large=large or card.pip_cost>=4
			if str(effect.get("status",""))=="shield":shield=true
	match id:
		"swift_flask":return cheap
		"charged_core":return large
		"ember_wick":return kinds.has("apply_dot")
		"detonation_seed":return kinds.has("detonate") and kinds.has("apply_dot")
		"frost_thorn":return shield
		"abundance_pod":return kinds.has("heal")
		"shadow_ledger":return kinds.has("health_cost") and kinds.has("drain")
		"seal_shard":return removes_enemy and (kinds.has("damage") or kinds.has("drain"))
		"twin_scales":return schools.size()>=2
	return true
