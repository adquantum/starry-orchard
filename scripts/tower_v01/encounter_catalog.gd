extends RefCounted
const Rules=preload("res://scripts/tower_v01/trial_rules.gd")
## Bound source IDs only. Stats do not scale with the player's chosen relics.
static func enemy(title: String, school: String, model: String, hp: int, damage: int, cards: Dictionary) -> Dictionary:
	return {"name":title,"school":school,"model":model,"hp":hp,"damage":damage,"resistance":5,"pierce":3,"cards":cards}

static func get_encounter(node: int, risk := false, party_size := 1) -> Dictionary:
	var result := {"title":"冰原巡卫","risk":"普通","dew":25,"enemies":[]}
	match node:
		0:
			result.enemies=[enemy("冰径守卫","ice","icewolf",850,25,{"ice_001":4,"ice_012":4,"ice_006":2,"ice_003":2}),enemy("烬火斥候","fire","firelizard",550,20,{"fir_001":4,"fir_006":4,"fir_003":2,"fir_011":2})]
		1:
			result.title="霜壳精英" if risk else "风雪巡逻"
			result.enemies=[enemy("霜壳卫长","ice","icebear",950,30,{"ice_012":4,"ice_013":4,"ice_006":2,"ice_003":2}),enemy("苔纹医师","life","lifetree",600,20,{"lif_005":4,"lif_013":4,"lif_020":2,"lif_003":2})]
		3:
			result.title="余烬与霜痕"
			result.enemies=[enemy("余烬术士","fire","firecrab01",1050,35,{"fir_006":4,"fir_011":4,"fir_001":2,"fir_003":2}),enemy("霜痕侍卫","ice","iceshrimpwarrior",700,30,{"ice_012":4,"ice_013":4,"ice_006":2,"ice_004":2})]
		4:
			result.title="裂冰先锋" if risk else "雷鸣哨兵"
			result.enemies=[enemy("裂冰先锋","myth","stormsmashbull",1100,35,{"myt_005":4,"myt_006":4,"myt_013":2,"myt_002":2}),enemy("雷鸣猎手","storm","stormbee",650,30,{"sto_002":4,"sto_009":6,"sto_003":2})]
		6:
			result.title="寒核门卫"
			result.enemies=[enemy("寒核门卫","ice","icebear",1250,40,{"ice_012":4,"ice_013":4,"ice_017":2,"ice_006":2}),enemy("镜纹祭司","life","lifepangolin",750,25,{"lif_005":4,"lif_017":4,"lif_020":2,"lif_003":2})]
		8:
			result.title="寒核守望者"
			result.risk="首领"
			result.enemies=[enemy("寒核守望者","ice","icebear",3000,55,{"ice_012":4,"ice_013":4,"ice_017":2,"ice_006":2}),enemy("镜纹祭司","life","lifepangolin",700,30,{"lif_005":4,"lif_017":4,"lif_020":2,"lif_003":2})]
	risk=risk and node in [1,4]
	if risk:result.risk="精英";result.dew=45
	for spec in result.enemies:
		var solo_hp := roundi(float(spec.hp)*0.42*(Rules.ELITE_HP if risk else 1.0))
		spec.hp=roundi(solo_hp*(Rules.DUO_HP if party_size==2 else 1.0))
		spec.damage=int(spec.damage)-30
	result["mechanics"]="普通守卫：留意刃、盾与治疗支援。"
	if node==1 and risk:result.mechanics="霜壳精英：定期获得吸收盾；击破/拆除后两次主动直伤施法 +20%，最迟下回合结束失效。"
	if node==4 and risk:result.mechanics="裂冰精英：两次攻击后获得 +25% 刃；可以拆除。"
	if node==6:result.mechanics="门卫：定期获得霜壳；祭司存活时主怪减伤 15%。"
	if node==8:result.mechanics="首领：祭司共鸣减伤 15%；第 3/6/9…回合寒潮。半血后下一回合进入狂怒。"
	result.mechanics+="\n敌方纯治疗、纯防御各最多成功两次；法术需要抽到并实际支付。"
	return result
