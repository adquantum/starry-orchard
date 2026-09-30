extends RefCounted
## Implementation values from ROGUELIKE_V02_PLAN.md, not an auto-tuning system.
const VERSION = "tower-local-v02-plan-20260917"
const SCHOOLS = ["fire", "ice", "storm", "myth", "life", "death", "balance"]
const MIN_DECK = 10
const MAX_DECK = 18
const PLAYER_ACCURACY = 0.08
const DUO_HP = 1.8
const ELITE_HP = 1.3
const STARTERS = {
	"fire":{"fir_001":2,"fir_006":2,"fir_011":1,"fir_013":1,"fir_003":2,"fir_004":1,"fir_012":1,"ice_006":1,"lif_004":1},
	"ice":{"ice_001":2,"ice_012":2,"ice_010":1,"ice_013":1,"ice_003":2,"ice_006":2,"ice_004":1,"lif_004":1},
	"storm":{"sto_002":3,"sto_009":2,"sto_017":1,"sto_003":2,"sto_007":1,"ice_006":2,"lif_004":1},
	"myth":{"myt_005":2,"myt_006":2,"myt_010":1,"myt_013":1,"myt_002":2,"myt_004":1,"myt_020":2,"lif_004":1},
	"life":{"lif_005":3,"lif_013":1,"lif_017":1,"lif_003":2,"lif_004":2,"lif_020":1,"lif_011":1,"lif_012":1},
	"death":{"dea_009":2,"dea_005":3,"dea_013":1,"dea_003":2,"dea_004":1,"death_empower":1,"ice_006":1,"lif_004":1},
	"balance":{"bal_005":2,"bal_010":2,"bal_009":1,"bal_013":1,"bal_003":2,"bal_006":1,"bal_007":1,"bal_004":1,"lif_004":1}
}
const DIRECTIONS = {
	"fire":"余烬引爆 / 烙印爆发", "ice":"守势反攻 / 削弱蓄力", "storm":"疾雷抢攻 / 蓄势重击",
	"myth":"拆印突击 / 双击破阵", "life":"生长攻势 / 丰饶护生", "death":"汲取消耗 / 献祭转势", "balance":"刃阵调度 / 双系调和"
}
const POOL_IDS = [
	"fir_001","fir_003","fir_004","fir_006","fir_008","fir_011","fir_012","fir_013","fir_020","fir_021","fir_025","fir_029",
	"ice_001","ice_003","ice_004","ice_006","ice_007","ice_010","ice_012","ice_013","ice_014","ice_016","ice_017","ice_019","ice_021","ice_023","ice_031",
	"sto_002","sto_003","sto_004","sto_007","sto_009","sto_012","sto_017","sto_018","sto_021","sto_025","storm_lightning_strike",
	"myt_002","myt_003","myt_004","myt_005","myt_006","myt_010","myt_012","myt_013","myt_017","myt_018","myt_019","myt_020","myt_025",
	"lif_003","lif_004","lif_005","lif_006","lif_008","lif_011","lif_012","lif_013","lif_015","lif_017","lif_018","lif_020","lif_021","lif_023","lif_025","lif_031",
	"dea_002","dea_003","dea_004","dea_005","dea_006","dea_008","dea_009","dea_013","dea_014","dea_017","dea_019","dea_020","dea_021","dea_025","death_empower",
	"bal_002","bal_003","bal_004","bal_005","bal_006","bal_007","bal_009","bal_010","bal_011","bal_012","bal_013","bal_014","bal_015","bal_017","bal_020","bal_021","bal_024","bal_025","bal_028","bal_030","balance_elemental_blade","balance_spirit_blade"
]
const WARD_UPGRADES = ["fir_003","fir_004","ice_003","ice_006","ice_004","myt_002","myt_003","myt_020","lif_003","lif_008","dea_002","dea_003","dea_004","bal_002","bal_003","bal_004","bal_006"]
const SCHOOL_TAGS = {"fire":["apply_dot","detonate","blade","trap"],"ice":["shield","weakness","blade"],"storm":["damage","remove_enemy_buff","accuracy_blade"],"myth":["multihit","remove_enemy_buff","blade"],"life":["apply_hot","heal","cleanse"],"death":["drain","health_cost","weakness"],"balance":["blade","trap","resource"]}
const SCHOOL_RELICS = {"fire":["ember_wick","detonation_seed","charged_core"],"ice":["frost_thorn","steady_pips","charged_core"],"storm":["swift_flask","charged_core"],"myth":["seal_shard","swift_flask","charged_core"],"life":["abundance_pod","travel_supply","steady_pips"],"death":["shadow_ledger","charged_core"],"balance":["twin_scales","steady_pips","charged_core"]}
const ALLOWED = ["damage","heal","apply_dot","apply_hot","apply_status","drain","detonate","health_cost","resource","remove_status","steal_status","absorb","cleanse","prism"]

static func config_hash() -> String:
	var parts: Array[String] = []
	for path in ["res://scripts/tower_v01/trial_rules.gd","res://scripts/tower_v01/encounter_catalog.gd","res://scripts/tower_v01/relic_catalog.gd"]:
		parts.append(FileAccess.get_sha256(path))
	return "|".join(parts).sha256_text()

static func supported(effects: Array) -> bool:
	for effect in effects:
		if not effect is Dictionary or str(effect.get("type","")) not in ALLOWED:return false
		# No conditional/convert wrapper is admitted without its own semantic audit.
		for value in effect.values():
			if value is Array:
				for nested in value:
					if nested is Dictionary and nested.has("type") and not supported([nested]):return false
	return true

static func removes_enemy_buff(card: Dictionary) -> bool:
	if str(card.get("target","")) not in ["enemy","all_enemies"]:return false
	for effect in card.get("effects",[]):
		if str(effect.get("type","")) not in ["remove_status","steal_status"]:continue
		if str(effect.get("target", "")) in ["caster","self","ally","all_allies"]:continue
		if str(effect.get("polarity","")) == "helpful":return true
		for kind in effect.get("kinds",[]):
			if kind in ["blade","shield","absorb","healing_blade","accuracy_blade","stun_block"]:return true
	return false

static func tags(card: Dictionary) -> Array:
	var result: Array = []
	var hits := 0
	for effect in card.get("effects",[]):
		var type := str(effect.type)
		if type not in result:result.append(type)
		if type in ["damage","drain"]:hits += 1
		if effect.has("status") and effect.status not in result:result.append(effect.status)
	if hits > 0:result.append("attack")
	if hits > 1:result.append("multihit")
	if removes_enemy_buff(card):result.append("remove_enemy_buff")
	if str(card.get("target","")) == "all_enemies" and hits > 0:result.append("aoe")
	return result
