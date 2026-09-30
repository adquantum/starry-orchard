extends RefCounted
## Battle-local allies: no account inventory, equipment ownership or consumables.
const Finale = preload("res://scripts/server/star_orchard_finale.gd")
const MAX_ALLIES := 1
const DECKS := {
	"life": {"lif_003":2,"lif_005":3,"lif_020":4,"lif_012":2,"lif_023":2,"lif_013":2,"lif_017":2,"lif_021":1,"lif_025":2},
	"ice": {"ice_001":2,"ice_003":2,"ice_004":2,"ice_006":3,"ice_010":3,"ice_014":2,"ice_013":2,"ice_017":2,"ice_021":2},
	"fire": {"fir_001":2,"fir_003":3,"fir_004":2,"fir_006":3,"fir_011":3,"fir_013":3,"fir_029":2,"fir_021":2,"fir_031":1},
	"storm": {"sto_002":3,"sto_016":3,"sto_017":2,"sto_009":3,"sto_003":3,"sto_004":2,"sto_012":2,"sto_021":2},
	"balance": {"bal_005":3,"bal_010":3,"bal_013":3,"bal_009":3,"bal_003":3,"bal_004":2,"bal_021":2}
}

static func partner(school: String) -> String:
	return str(Finale.data().get("pair",{}).get(school,""))

static func valid_request(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and value in [0,1]

static func available_count(requested: Variant, human_count: int, test_override: int = 0) -> int:
	if not valid_request(requested) or human_count < 1:return 0
	var amount := test_override if test_override in [1,2,3] else int(requested)
	return mini(amount,maxi(0,4-human_count))

## Session-only test command, intentionally discoverable by knowing its text.
## It is not an admin credential. Only the authority supplies this state map.
static func apply_test_command(overrides: Dictionary, peer: int, text: String, busy: bool, authenticated: bool) -> Dictionary:
	var words := text.strip_edges().replace("\t"," ").split(" ",false)
	if words.is_empty() or words[0] != "/testai":return {}
	if not authenticated:return {"ok":false,"message":"请先完成角色连接验证，再使用测试指令。"}
	if busy:return {"ok":false,"message":"战斗或候场中不能修改测试助战；当前设置未改变。"}
	if words.size()>2 or (words.size()==2 and words[1] not in ["0","1","2","3"]):
		return {"ok":false,"message":"用法：/testai 0|1|2|3；不带数字为 3，0 恢复普通助战选择。"}
	var count := 3 if words.size()==1 else int(words[1])
	if count == 0:
		overrides.erase(peer)
		return {"ok":true,"message":"测试助战已关闭，恢复队伍界面的普通助战选择。"}
	overrides[peer] = count
	return {"ok":true,"message":"本次连接启用 %d 位测试 AI：真人优先，总队伍最多四人；断线后自动取消。" % count}

static func test_profile(content: ContentRegistryV2, player: Dictionary, index: int) -> Dictionary:
	if index<0 or index>2:return {}
	var first := partner(str(player.get("school","")))
	if first.is_empty():return {}
	var schools := [first]
	for school in ["life","ice","fire","storm","balance"]:
		if school not in schools:schools.append(school)
	return _school_profile(content,player,str(schools[index]))

static func profile(content: ContentRegistryV2, player: Dictionary, index: int) -> Dictionary:
	if index != 0:return {}
	var school := partner(str(player.get("school","")))
	if not DECKS.has(school):return {}
	return _school_profile(content,player,school)

static func _school_profile(content: ContentRegistryV2, player: Dictionary, school: String) -> Dictionary:
	# The player's equipped deck is the current, validated spell progression.
	# Always retain cheap attacks/support; unlock finishers with its cost range.
	var cost_cap := 3
	for id in player.get("counts", {}):
		if int(player.counts[id]) <= 0:continue
		var card := content.card(StringName(str(id)))
		if card != null:cost_cap = maxi(cost_cap, mini(card.pip_cost, 7))
	var counts: Dictionary = {}
	for id in DECKS[school]:
		var card := content.card(StringName(str(id)))
		if card == null or not card.learned or card.treasure or card.enemy_only:continue
		if card.pip_cost > cost_cap or card.shadow_cost > 0 or not card.school_pip_requirements.is_empty():continue
		counts[id] = int(DECKS[school][id])
	return {"school":school,"counts":counts,"treasures":{},"ai_source":"P0"}

static func configure(engine: BattleEngineV2, ally_id: StringName, source_id: StringName = &"P0") -> bool:
	var ally := engine.state.unit_by_id(ally_id)
	var source := engine.state.unit_by_id(source_id)
	if ally == null or source == null or ally == source:return false
	ally.max_hp = source.max_hp
	ally.hp = source.hp
	ally.alive = source.alive
	ally.archmastery = source.archmastery
	ally.stats = source.stats.duplicate(true)
	# Only casting bonuses follow the support role's school. Defensive school
	# tables describe incoming damage and must remain identical to the player.
	if ally.school_id != source.school_id:
		for key in ["damage", "flat_damage", "pierce", "critical", "accuracy_floor"]:
			if not ally.stats.get(key) is Dictionary:continue
			var values: Dictionary = ally.stats[key]
			var source_key := str(source.school_id)
			var ally_key := str(ally.school_id)
			var source_value: Variant = values.get(source_key, null)
			var ally_value: Variant = values.get(ally_key, null)
			values.erase(source_key);values.erase(ally_key)
			if source_value != null:values[ally_key] = source_value
			if ally_value != null:values[source_key] = ally_value
	ally.ai_profile_id = &"island_ally"
	ally.deck.treasure_pile.clear()
	return true
