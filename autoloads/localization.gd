extends Node

signal language_changed

var locale: String = "zh_CN"

var _zh: Dictionary = {
	"CARD_ORCHARD_DOT_FIRE_NAME": "炽焰回旋",
	"CARD_ORCHARD_DOT_ICE_NAME": "寒霜侵蚀",
	"CARD_ORCHARD_DOT_STORM_NAME": "雷霆余波",
	"CARD_ORCHARD_DOT_LIFE_NAME": "荆棘缠身",
	"CARD_ORCHARD_DOT_DEATH_NAME": "幽魂蚀骨",
	"CARD_ORCHARD_DOT_MYTH_NAME": "幻象回响",
	"CARD_ORCHARD_DOT_BALANCE_NAME": "星衡流沙",
	"GAME_TITLE": "星辉学院 · 4v4魔法对决",
	"ROUND": "第 %d 轮",
	"PHASE_PLANNING": "制定行动",
	"PHASE_RESOLVING": "蛇形结算中",
	"PHASE_FINISHED": "战斗结束",
	"CURRENT_WIZARD": "当前：%s",
	"NEXT_CHARGE": "下轮学院豆：",
	"SKIP": "跳过行动",
	"RESTART": "重新开始",
	"LANGUAGE": "EN",
	"HELP": "玩法",
	"DECK_BUILDER": "卡组",
	"DECK_TITLE": "卡组配置",
	"DECK_WIZARD": "巫师：",
	"DECK_SIZE_VALUE": "卡组 %d 张 · 单卡最多4张 · 至少7张",
	"DECK_RESET": "恢复默认",
	"DECK_APPLY": "应用并重开战斗",
	"FUSION_HINT": "Shift+左键选择两张普通卡融合",
	"FUSION_SELECTED": "融合材料：%s",
	"CARD_INPUT_HINT": "左键选牌并拉出目标箭头 · 右键换宝藏 · Shift+左键融合",
	"TARGET_SELECTED": "目标：%s",
	"TARGETING_HINT": "选择发光目标 · 右键/Esc取消",
	"VICTORY": "胜利！星辉法阵恢复了平静",
	"DEFEAT": "失败……重新调整卡组再试一次",
	"CLOSE": "关闭",
	"HELP_TEXT": "每轮为A1B2C3D4 / 1A2B3C4D蛇形行动。先为四名巫师依次选牌与目标。每轮补牌到7张并生成魔豆。\n\n左键卡牌：拉出箭头，再点击发光目标\n右键：弃掉普通牌并立即抽一张宝藏卡\nShift+左键：依次选择两张已习得普通牌进行融合\n右键空白处或Esc：取消目标选择\n\n融合配方：\n火花箭 + 余烬印记 = 炼狱环流\n寒冰碎片 + 霜甲 = 冰川坠落\n\n刀刃和盾可以选择队友，虚弱选择敌人。刀刃/虚弱作用于整个下一法术；护盾/陷阱只作用于下一跳伤害。相同来源一次只触发一个。",
	"SCHOOL_FIRE": "火焰", "SCHOOL_ICE": "寒冰", "SCHOOL_STORM": "风暴",
	"SCHOOL_LIFE": "生命", "SCHOOL_DEATH": "死亡", "SCHOOL_BALANCE": "平衡", "SCHOOL_MYTH": "神话",
	"UNIT_P0": "A · 赤焰学徒", "UNIT_P1": "B · 霜铃守卫", "UNIT_P2": "C · 苔光医师", "UNIT_P3": "D · 雷羽术士",
	"UNIT_E0": "1 · 灰烬骷髅", "UNIT_E1": "2 · 冻土魔像", "UNIT_E2": "3 · 荆棘女巫", "UNIT_E3": "4 · 暮雷幽灵",
	"HP": "生命 %d/%d", "PIPS": "豆 %s", "DECK_COUNT": "牌库 %d · 宝藏 %d",
	"STATUS_EMPTY": "无悬挂效果", "STATUS_BLADE": "刃", "STATUS_WEAKNESS": "弱",
	"STATUS_SHIELD": "盾", "STATUS_TRAP": "陷", "STATUS_DOT": "灼", "STATUS_HOT": "愈", "STATUS_DELAYED": "延",
	"CARD_FIRE_BOLT_NAME": "火花箭", "CARD_FIRE_BOLT_DESC": "对单个敌人造成135点伤害。",
	"CARD_EMBER_MARK_NAME": "余烬印记", "CARD_EMBER_MARK_DESC": "放置+30%陷阱，只强化下一跳。",
	"CARD_ICE_SHARD_NAME": "寒冰碎片", "CARD_ICE_SHARD_DESC": "高命中的120点寒冰伤害。",
	"CARD_FROST_WARD_NAME": "霜甲", "CARD_FROST_WARD_DESC": "放置-80%护盾，只保护下一跳。",
	"CARD_LIFE_BLOOM_NAME": "生命绽放", "CARD_LIFE_BLOOM_DESC": "为一名存活队友恢复270生命。",
	"CARD_BRIGHT_BLADE_NAME": "星辉刀刃", "CARD_BRIGHT_BLADE_DESC": "下一个伤害法术整体提高30%。",
	"CARD_SOFT_WEAKNESS_NAME": "衰弱咒", "CARD_SOFT_WEAKNESS_DESC": "目标的下一个伤害法术整体降低25%。",
	"CARD_PRISM_TRAP_NAME": "棱镜陷阱", "CARD_PRISM_TRAP_DESC": "下一跳受到的伤害提高25%。",
	"CARD_BURNING_ORBIT_NAME": "燃烧轨迹", "CARD_BURNING_ORBIT_DESC": "连续3轮，每轮造成92点火焰伤害。",
	"CARD_RENEWING_MIST_NAME": "复苏薄雾", "CARD_RENEWING_MIST_DESC": "连续3轮，每轮恢复82生命。",
	"CARD_TIME_BOMB_NAME": "时序雷核", "CARD_TIME_BOMB_DESC": "延迟2轮后造成430点伤害。",
	"CARD_PHOENIX_REVIVE_NAME": "凤凰回响", "CARD_PHOENIX_REVIVE_DESC": "消耗1枚生命学院豆，复活一名队友。",
	"CARD_STORM_LANCE_NAME": "风暴长枪", "CARD_STORM_LANCE_DESC": "低命中的245点风暴伤害。",
	"CARD_STORM_WEAKNESS_NAME": "静电枷锁", "CARD_STORM_WEAKNESS_DESC": "目标的下一个伤害法术降低20%。",
	"CARD_SHADOW_BURST_NAME": "暗影迸发", "CARD_SHADOW_BURST_DESC": "消耗1枚暗影豆，造成410点伤害。",
	"CARD_DEATH_DRAIN_NAME": "冥息汲取", "CARD_DEATH_DRAIN_DESC": "连续3轮，每轮恢复70生命。",
	"CARD_BALANCE_BLAST_NAME": "平衡震波", "CARD_BALANCE_BLAST_DESC": "造成205点平衡伤害。",
	"CARD_MYTH_MINOTAUR_NAME": "神话牛头人", "CARD_MYTH_MINOTAUR_DESC": "造成215点神话伤害。",
	"CARD_MYTH_GUARD_NAME": "传说守护", "CARD_MYTH_GUARD_DESC": "为一名队友放置-50%护盾。",
	"CARD_MYTH_ECHO_NAME": "迷宫回声", "CARD_MYTH_ECHO_DESC": "延迟1轮后造成300点神话伤害。",
	"CARD_FUSION_INFERNO_NAME": "炼狱环流", "CARD_FUSION_INFERNO_DESC": "融合卡。对全体敌人施加3轮燃烧。",
	"CARD_FUSION_GLACIER_NAME": "冰川坠落", "CARD_FUSION_GLACIER_DESC": "融合卡。延迟2轮造成520点伤害。",
	"CARD_TREASURE_METEOR_NAME": "流星雨", "CARD_TREASURE_METEOR_DESC": "一次性。对全体敌人造成205点伤害。",
	"CARD_TREASURE_ELIXIR_NAME": "翠绿药剂", "CARD_TREASURE_ELIXIR_DESC": "一次性。免费恢复230生命。",
	"CARD_TREASURE_BLADE_NAME": "王者刀刃", "CARD_TREASURE_BLADE_DESC": "一次性。下个伤害法术提高40%。",
	"CARD_WEEKEND_TC_FIRE_DRAKE_NAME": "熔爪炎龙", "CARD_WEEKEND_TC_FIRE_DRAKE_DESC": "一次性。对全体敌人造成415点火焰伤害，并施加3轮灼烧。",
	"CARD_WEEKEND_TC_FIRE_BLADE_NAME": "余烬锋刃", "CARD_WEEKEND_TC_FIRE_BLADE_DESC": "一次性。使下一次火焰伤害提高35%。",
	"CARD_WEEKEND_TC_ICE_BRUTE_NAME": "寒峰巨猿", "CARD_WEEKEND_TC_ICE_BRUTE_DESC": "一次性。对一名敌人造成460点寒冰伤害。",
	"CARD_WEEKEND_TC_ICE_BLADE_NAME": "寒霜锋刃", "CARD_WEEKEND_TC_ICE_BLADE_DESC": "一次性。使下一次寒冰伤害提高40%。",
	"CARD_WEEKEND_TC_STORM_YETI_NAME": "怒飙雪魔", "CARD_WEEKEND_TC_STORM_YETI_DESC": "一次性。对全体敌人造成600点风暴伤害。",
	"CARD_WEEKEND_TC_STORM_BLADE_NAME": "雷霆锋刃", "CARD_WEEKEND_TC_STORM_BLADE_DESC": "一次性。使下一次风暴伤害提高30%。",
	"CARD_WEEKEND_TC_MYTH_REAPER_NAME": "秘纹摄魂者", "CARD_WEEKEND_TC_MYTH_REAPER_DESC": "一次性。对一名敌人连续造成50点与550点神话伤害。",
	"CARD_WEEKEND_TC_MYTH_BLADE_NAME": "符文锋刃", "CARD_WEEKEND_TC_MYTH_BLADE_DESC": "一次性。使下一次神话伤害提高35%。",
	"CARD_WEEKEND_TC_LIFE_WARDEN_NAME": "荆棘妖卫", "CARD_WEEKEND_TC_LIFE_WARDEN_DESC": "一次性。对全体敌人造成400点生命伤害。",
	"CARD_WEEKEND_TC_LIFE_BLADE_NAME": "翠绿锋刃", "CARD_WEEKEND_TC_LIFE_BLADE_DESC": "一次性。使下一次生命伤害提高40%。",
	"CARD_WEEKEND_TC_DEATH_BRAND_NAME": "幽冥毒药", "CARD_WEEKEND_TC_DEATH_BRAND_DESC": "一次性。造成55点死亡伤害，并施加3轮幽冥侵蚀。",
	"CARD_WEEKEND_TC_DEATH_BLADE_NAME": "幽冥锋刃", "CARD_WEEKEND_TC_DEATH_BLADE_DESC": "一次性。使下一次死亡伤害提高40%。",
	"CARD_WEEKEND_TC_BALANCE_REAPER_NAME": "秤魂使者", "CARD_WEEKEND_TC_BALANCE_REAPER_DESC": "一次性。对全体敌人造成470点平衡伤害并放置陷阱。",
	"CARD_WEEKEND_TC_BALANCE_BLADE_NAME": "星衡锋刃", "CARD_WEEKEND_TC_BALANCE_BLADE_DESC": "一次性。使下一次任意学院伤害提高25%。",
	"CARD_WEEKEND_ITEM_FIRE_ROBE_T1_BLADE_NAME": "余烬锋刃", "CARD_WEEKEND_ITEM_FIRE_ROBE_T2_BLADE_NAME": "余烬锋刃",
	"CARD_WEEKEND_ITEM_ICE_ROBE_T1_BLADE_NAME": "寒霜锋刃", "CARD_WEEKEND_ITEM_ICE_ROBE_T2_BLADE_NAME": "寒霜锋刃",
	"CARD_WEEKEND_ITEM_STORM_ROBE_T1_BLADE_NAME": "雷霆锋刃", "CARD_WEEKEND_ITEM_STORM_ROBE_T2_BLADE_NAME": "雷霆锋刃",
	"CARD_WEEKEND_ITEM_MYTH_ROBE_T1_BLADE_NAME": "符文锋刃", "CARD_WEEKEND_ITEM_MYTH_ROBE_T2_BLADE_NAME": "符文锋刃",
	"CARD_WEEKEND_ITEM_LIFE_ROBE_T1_BLADE_NAME": "翠绿锋刃", "CARD_WEEKEND_ITEM_LIFE_ROBE_T2_BLADE_NAME": "翠绿锋刃",
	"CARD_WEEKEND_ITEM_DEATH_ROBE_T1_BLADE_NAME": "幽冥锋刃", "CARD_WEEKEND_ITEM_DEATH_ROBE_T2_BLADE_NAME": "幽冥锋刃",
	"CARD_WEEKEND_ITEM_BALANCE_ROBE_T1_BLADE_NAME": "星衡锋刃", "CARD_WEEKEND_ITEM_BALANCE_ROBE_T2_BLADE_NAME": "星衡锋刃",
	"CARD_WEEKEND_ITEM_FIRE_ROBE_T1_BLADE_DESC": "装备卡。下一次火焰伤害提高25%。", "CARD_WEEKEND_ITEM_FIRE_ROBE_T2_BLADE_DESC": "装备卡。下一次火焰伤害提高35%。",
	"CARD_WEEKEND_ITEM_ICE_ROBE_T1_BLADE_DESC": "装备卡。下一次寒冰伤害提高30%。", "CARD_WEEKEND_ITEM_ICE_ROBE_T2_BLADE_DESC": "装备卡。下一次寒冰伤害提高40%。",
	"CARD_WEEKEND_ITEM_STORM_ROBE_T1_BLADE_DESC": "装备卡。下一次风暴伤害提高20%。", "CARD_WEEKEND_ITEM_STORM_ROBE_T2_BLADE_DESC": "装备卡。下一次风暴伤害提高30%。",
	"CARD_WEEKEND_ITEM_MYTH_ROBE_T1_BLADE_DESC": "装备卡。下一次神话伤害提高25%。", "CARD_WEEKEND_ITEM_MYTH_ROBE_T2_BLADE_DESC": "装备卡。下一次神话伤害提高35%。",
	"CARD_WEEKEND_ITEM_LIFE_ROBE_T1_BLADE_DESC": "装备卡。下一次生命伤害提高30%。", "CARD_WEEKEND_ITEM_LIFE_ROBE_T2_BLADE_DESC": "装备卡。下一次生命伤害提高40%。",
	"CARD_WEEKEND_ITEM_DEATH_ROBE_T1_BLADE_DESC": "装备卡。下一次死亡伤害提高30%。", "CARD_WEEKEND_ITEM_DEATH_ROBE_T2_BLADE_DESC": "装备卡。下一次死亡伤害提高40%。",
	"CARD_WEEKEND_ITEM_BALANCE_ROBE_T1_BLADE_DESC": "装备卡。下一次任意学院伤害提高20%。", "CARD_WEEKEND_ITEM_BALANCE_ROBE_T2_BLADE_DESC": "装备卡。下一次任意学院伤害提高25%。",
	"CARD_FIR_012_NAME": "燃点引爆", "CARD_FIR_012_DESC": "立刻结算目标的一层火焰持续伤害。",
	"CARD_ICE_024_NAME": "冰封禁锢", "CARD_ICE_024_DESC": "造成400点寒冰伤害并使目标跳过下一次行动。",
	"CARD_STO_008_NAME": "雷霆转化", "CARD_STO_008_DESC": "将一枚普通魔豆转化为超级魔豆。",
	"CARD_LIF_020_NAME": "再生之春", "CARD_LIF_020_DESC": "以350点生命复活一名倒下的队友。",
	"CARD_DEA_001_NAME": "灵魂虹吸", "CARD_DEA_001_DESC": "造成80点死亡伤害，并治疗造成伤害的50%。",
	"CARD_MYT_015_NAME": "神话碎镜", "CARD_MYT_015_DESC": "移除目标最多两层护盾。",
	"CARD_BAL_007_NAME": "平衡赠豆", "CARD_BAL_007_DESC": "给予一名队友一枚普通魔豆。",
	"CARD_FIR_001_NAME": "余烬飞矢", "CARD_FIR_002_NAME": "闷燃烙印", "CARD_FIR_003_NAME": "烈焰锋刃", "CARD_FIR_004_NAME": "余烬圈套",
	"CARD_FIR_005_NAME": "炽热火球", "CARD_FIR_006_NAME": "燃烧螺旋", "CARD_FIR_007_NAME": "熔炉印记", "CARD_FIR_009_NAME": "熔岩长枪",
	"CARD_FIR_010_NAME": "火葬轨迹", "CARD_FIR_011_NAME": "灰烬雨", "CARD_FIR_014_NAME": "灼热余痕", "CARD_FIR_015_NAME": "野火之刃", "CARD_FIR_016_NAME": "无尽余烬",
	"CARD_ICE_001_NAME": "霜针", "CARD_ICE_002_NAME": "雪幕", "CARD_ICE_003_NAME": "霜华之刃", "CARD_ICE_004_NAME": "寒意疑云",
	"CARD_ICE_005_NAME": "寒冰彗星", "CARD_ICE_006_NAME": "水晶堡垒", "CARD_ICE_007_NAME": "霜冻圈套", "CARD_ICE_008_NAME": "深度冻结",
	"CARD_ICE_009_NAME": "冻伤诅咒", "CARD_ICE_010_NAME": "冰雹环流", "CARD_ICE_011_NAME": "冰川神盾", "CARD_ICE_012_NAME": "永冻之地",
	"CARD_ICE_014_NAME": "冬日协约", "CARD_ICE_015_NAME": "冰封裁决", "CARD_ICE_016_NAME": "净化之雪",
	"LOG_ROUND": "—— 第 %d 轮开始 ——", "LOG_PLANNED": "%s 选择了 %s。",
	"LOG_SKIPPED": "%s 选择蓄力。", "LOG_CAST": "%s 施放了 %s。",
	"LOG_MISSED": "%s 的 %s 未命中，魔豆和悬挂效果保留。", "LOG_DEFEATED": "%s 倒下，临时状态与资源已清空。",
	"LOG_CANNOT_CAST": "资源不足，无法施放这张卡。", "LOG_BAD_TARGET": "这张卡不能选择该目标。",
	"LOG_TARGET_GONE": "%s 的 %s 失去了有效目标。", "LOG_TREASURE_DRAW": "%s 弃牌并抽取了一张宝藏卡。",
	"LOG_CANNOT_DISCARD": "宝藏卡或本轮刚抽到的牌不能再次弃掉。", "LOG_FUSION_NORMAL_ONLY": "只有已习得的普通卡可以融合。",
	"LOG_NO_RECIPE": "这两张卡之间没有融合公式。", "LOG_FUSED": "融合成功：%s。",
	"FLOAT_MISS": "未命中",
}

var _en: Dictionary = {
	"CARD_ORCHARD_DOT_FIRE_NAME": "Inferno Spiral",
	"CARD_ORCHARD_DOT_ICE_NAME": "Creeping Frost",
	"CARD_ORCHARD_DOT_STORM_NAME": "Thunder Aftershock",
	"CARD_ORCHARD_DOT_LIFE_NAME": "Entangling Thorns",
	"CARD_ORCHARD_DOT_DEATH_NAME": "Haunting Decay",
	"CARD_ORCHARD_DOT_MYTH_NAME": "Echoing Illusion",
	"CARD_ORCHARD_DOT_BALANCE_NAME": "Astral Quicksand",
	"GAME_TITLE": "STARLIGHT ACADEMY · 4v4 ARCANE DUEL",
	"ROUND": "ROUND %d", "PHASE_PLANNING": "PLAN ACTIONS", "PHASE_RESOLVING": "SNAKE RESOLUTION", "PHASE_FINISHED": "BATTLE OVER",
	"CURRENT_WIZARD": "ACTIVE: %s", "NEXT_CHARGE": "NEXT SCHOOL PIP: ", "SKIP": "PASS",
	"RESTART": "RESTART", "LANGUAGE": "中文", "HELP": "HOW TO PLAY", "CLOSE": "CLOSE",
	"DECK_BUILDER": "DECK", "DECK_TITLE": "DECK CONFIGURATION", "DECK_WIZARD": "WIZARD: ",
	"DECK_SIZE_VALUE": "%d CARDS · MAX 4 COPIES · MINIMUM 7", "DECK_RESET": "RESET DEFAULT", "DECK_APPLY": "APPLY & RESTART",
	"FUSION_HINT": "Shift+click two learned normal cards to fuse",
	"FUSION_SELECTED": "FUSION MATERIAL: %s", "CARD_INPUT_HINT": "Left: aim arrow · Right: treasure · Shift+Left: fuse",
	"TARGET_SELECTED": "TARGET: %s", "VICTORY": "VICTORY! The starlight circle is calm again",
	"TARGETING_HINT": "CHOOSE A GLOWING TARGET · RIGHT CLICK/ESC TO CANCEL",
	"DEFEAT": "DEFEAT... Rebuild the deck and try again",
	"HELP_TEXT": "Each round resolves A1B2C3D4 / 1A2B3C4D. Plan one card and target for each living wizard. Hands refill to 7 and pips generate each round.\n\nLeft click a card: aim the arrow, then click a glowing target\nRight click: discard a normal card and immediately draw treasure\nShift+Left click: select two learned normal cards to fuse\nRight click empty space or Esc: cancel targeting\n\nRecipes:\nSpark Bolt + Ember Mark = Inferno Orbit\nIce Shard + Frost Ward = Glacier Fall\n\nBlades and shields target allies; Weakness targets enemies. Blades/Weakness modify the whole next spell. Shields/Traps modify one damage tick. Identical sources trigger one at a time.",
	"SCHOOL_FIRE": "FIRE", "SCHOOL_ICE": "ICE", "SCHOOL_STORM": "STORM", "SCHOOL_LIFE": "LIFE", "SCHOOL_DEATH": "DEATH", "SCHOOL_BALANCE": "BALANCE", "SCHOOL_MYTH": "MYTH",
	"UNIT_P0": "A · EMBER APPRENTICE", "UNIT_P1": "B · FROST WARDEN", "UNIT_P2": "C · MOSS MEDIC", "UNIT_P3": "D · STORM SAGE",
	"UNIT_E0": "1 · ASH SKELETON", "UNIT_E1": "2 · TUNDRA GOLEM", "UNIT_E2": "3 · THORN WITCH", "UNIT_E3": "4 · DUSK WRAITH",
	"HP": "HP %d/%d", "PIPS": "PIPS %s", "DECK_COUNT": "DECK %d · TREASURE %d",
	"STATUS_EMPTY": "NO CHARMS/WARDS", "STATUS_BLADE": "BLD", "STATUS_WEAKNESS": "WEAK", "STATUS_SHIELD": "SHD", "STATUS_TRAP": "TRP", "STATUS_DOT": "DOT", "STATUS_HOT": "HOT", "STATUS_DELAYED": "DLY",
	"CARD_FIRE_BOLT_NAME": "SPARK BOLT", "CARD_FIRE_BOLT_DESC": "Deal 135 damage to one enemy.",
	"CARD_EMBER_MARK_NAME": "EMBER MARK", "CARD_EMBER_MARK_DESC": "Place a +30% trap for the next damage tick.",
	"CARD_ICE_SHARD_NAME": "ICE SHARD", "CARD_ICE_SHARD_DESC": "A reliable 120 ice damage attack.",
	"CARD_FROST_WARD_NAME": "FROST WARD", "CARD_FROST_WARD_DESC": "Place a -80% shield for the next damage tick.",
	"CARD_LIFE_BLOOM_NAME": "LIFE BLOOM", "CARD_LIFE_BLOOM_DESC": "Restore 270 health to a living ally.",
	"CARD_BRIGHT_BLADE_NAME": "STAR BLADE", "CARD_BRIGHT_BLADE_DESC": "The next damage spell deals 30% more overall.",
	"CARD_SOFT_WEAKNESS_NAME": "FEEBLE HEX", "CARD_SOFT_WEAKNESS_DESC": "Target's next damage spell deals 25% less overall.",
	"CARD_PRISM_TRAP_NAME": "PRISM TRAP", "CARD_PRISM_TRAP_DESC": "The next damage tick taken deals 25% more.",
	"CARD_BURNING_ORBIT_NAME": "BURNING ORBIT", "CARD_BURNING_ORBIT_DESC": "Deal 92 fire damage per round for 3 rounds.",
	"CARD_RENEWING_MIST_NAME": "RENEWING MIST", "CARD_RENEWING_MIST_DESC": "Restore 82 health per round for 3 rounds.",
	"CARD_TIME_BOMB_NAME": "CHRONO CORE", "CARD_TIME_BOMB_DESC": "Deal 430 damage after a 2-round delay.",
	"CARD_PHOENIX_REVIVE_NAME": "PHOENIX ECHO", "CARD_PHOENIX_REVIVE_DESC": "Spend one Life school pip to revive an ally.",
	"CARD_STORM_LANCE_NAME": "STORM LANCE", "CARD_STORM_LANCE_DESC": "An inaccurate attack for 245 storm damage.",
	"CARD_STORM_WEAKNESS_NAME": "STATIC SHACKLE", "CARD_STORM_WEAKNESS_DESC": "Reduce the target's next damage spell by 20%.",
	"CARD_SHADOW_BURST_NAME": "SHADOW BURST", "CARD_SHADOW_BURST_DESC": "Spend one shadow pip to deal 410 damage.",
	"CARD_DEATH_DRAIN_NAME": "GRAVE SIPHON", "CARD_DEATH_DRAIN_DESC": "Restore 70 health per round for 3 rounds.",
	"CARD_BALANCE_BLAST_NAME": "BALANCE BLAST", "CARD_BALANCE_BLAST_DESC": "Deal 205 Balance damage.",
	"CARD_MYTH_MINOTAUR_NAME": "MYTH MINOTAUR", "CARD_MYTH_MINOTAUR_DESC": "Deal 215 Myth damage.",
	"CARD_MYTH_GUARD_NAME": "LEGEND GUARD", "CARD_MYTH_GUARD_DESC": "Place a -50% shield on an ally.",
	"CARD_MYTH_ECHO_NAME": "LABYRINTH ECHO", "CARD_MYTH_ECHO_DESC": "Deal 300 Myth damage after 1 round.",
	"CARD_FUSION_INFERNO_NAME": "INFERNO ORBIT", "CARD_FUSION_INFERNO_DESC": "Fusion. Burn all enemies for 3 rounds.",
	"CARD_FUSION_GLACIER_NAME": "GLACIER FALL", "CARD_FUSION_GLACIER_DESC": "Fusion. Deal 520 damage after 2 rounds.",
	"CARD_TREASURE_METEOR_NAME": "METEOR", "CARD_TREASURE_METEOR_DESC": "One-use. Deal 205 damage to all enemies.",
	"CARD_TREASURE_ELIXIR_NAME": "JADE ELIXIR", "CARD_TREASURE_ELIXIR_DESC": "One-use. Restore 230 health for free.",
	"CARD_TREASURE_BLADE_NAME": "KING BLADE", "CARD_TREASURE_BLADE_DESC": "One-use. Next damage spell gains 40%.",
	"CARD_WEEKEND_TC_FIRE_DRAKE_NAME": "MOLTENTALON DRAKE", "CARD_WEEKEND_TC_FIRE_DRAKE_DESC": "One-use. Deal 415 Fire damage to all enemies and apply a three-round burn.",
	"CARD_WEEKEND_TC_FIRE_BLADE_NAME": "EMBER BLADE", "CARD_WEEKEND_TC_FIRE_BLADE_DESC": "One-use. The next Fire hit gains 35%.",
	"CARD_WEEKEND_TC_ICE_BRUTE_NAME": "FROSTPEAK BRUTE", "CARD_WEEKEND_TC_ICE_BRUTE_DESC": "One-use. Deal 460 Ice damage to one enemy.",
	"CARD_WEEKEND_TC_ICE_BLADE_NAME": "FROST BLADE", "CARD_WEEKEND_TC_ICE_BLADE_DESC": "One-use. The next Ice hit gains 40%.",
	"CARD_WEEKEND_TC_STORM_YETI_NAME": "GALEHOWL YETI", "CARD_WEEKEND_TC_STORM_YETI_DESC": "One-use. Deal 600 Storm damage to all enemies.",
	"CARD_WEEKEND_TC_STORM_BLADE_NAME": "THUNDER BLADE", "CARD_WEEKEND_TC_STORM_BLADE_DESC": "One-use. The next Storm hit gains 30%.",
	"CARD_WEEKEND_TC_MYTH_REAPER_NAME": "RUNEBOUND REAPER", "CARD_WEEKEND_TC_MYTH_REAPER_DESC": "One-use. Deal 50 and then 550 Myth damage to one enemy.",
	"CARD_WEEKEND_TC_MYTH_BLADE_NAME": "RUNIC BLADE", "CARD_WEEKEND_TC_MYTH_BLADE_DESC": "One-use. The next Myth hit gains 35%.",
	"CARD_WEEKEND_TC_LIFE_WARDEN_NAME": "BRIAR WARDEN", "CARD_WEEKEND_TC_LIFE_WARDEN_DESC": "One-use. Deal 400 Life damage to all enemies.",
	"CARD_WEEKEND_TC_LIFE_BLADE_NAME": "VERDANT BLADE", "CARD_WEEKEND_TC_LIFE_BLADE_DESC": "One-use. The next Life hit gains 40%.",
	"CARD_WEEKEND_TC_DEATH_BRAND_NAME": "GRAVE BRAND", "CARD_WEEKEND_TC_DEATH_BRAND_DESC": "One-use. Deal 55 Death damage and apply a three-round grave brand.",
	"CARD_WEEKEND_TC_DEATH_BLADE_NAME": "GRAVE BLADE", "CARD_WEEKEND_TC_DEATH_BLADE_DESC": "One-use. The next Death hit gains 40%.",
	"CARD_WEEKEND_TC_BALANCE_REAPER_NAME": "SOULSCALE REAPER", "CARD_WEEKEND_TC_BALANCE_REAPER_DESC": "One-use. Deal 470 Balance damage to all enemies and place a trap.",
	"CARD_WEEKEND_TC_BALANCE_BLADE_NAME": "ASTRAL BLADE", "CARD_WEEKEND_TC_BALANCE_BLADE_DESC": "One-use. The next hit from any school gains 25%.",
	"CARD_WEEKEND_ITEM_FIRE_ROBE_T1_BLADE_NAME": "EMBER BLADE", "CARD_WEEKEND_ITEM_FIRE_ROBE_T2_BLADE_NAME": "EMBER BLADE",
	"CARD_WEEKEND_ITEM_ICE_ROBE_T1_BLADE_NAME": "FROST BLADE", "CARD_WEEKEND_ITEM_ICE_ROBE_T2_BLADE_NAME": "FROST BLADE",
	"CARD_WEEKEND_ITEM_STORM_ROBE_T1_BLADE_NAME": "THUNDER BLADE", "CARD_WEEKEND_ITEM_STORM_ROBE_T2_BLADE_NAME": "THUNDER BLADE",
	"CARD_WEEKEND_ITEM_MYTH_ROBE_T1_BLADE_NAME": "RUNIC BLADE", "CARD_WEEKEND_ITEM_MYTH_ROBE_T2_BLADE_NAME": "RUNIC BLADE",
	"CARD_WEEKEND_ITEM_LIFE_ROBE_T1_BLADE_NAME": "VERDANT BLADE", "CARD_WEEKEND_ITEM_LIFE_ROBE_T2_BLADE_NAME": "VERDANT BLADE",
	"CARD_WEEKEND_ITEM_DEATH_ROBE_T1_BLADE_NAME": "GRAVE BLADE", "CARD_WEEKEND_ITEM_DEATH_ROBE_T2_BLADE_NAME": "GRAVE BLADE",
	"CARD_WEEKEND_ITEM_BALANCE_ROBE_T1_BLADE_NAME": "ASTRAL BLADE", "CARD_WEEKEND_ITEM_BALANCE_ROBE_T2_BLADE_NAME": "ASTRAL BLADE",
	"CARD_WEEKEND_ITEM_FIRE_ROBE_T1_BLADE_DESC": "Item card. The next Fire hit gains 25%.", "CARD_WEEKEND_ITEM_FIRE_ROBE_T2_BLADE_DESC": "Item card. The next Fire hit gains 35%.",
	"CARD_WEEKEND_ITEM_ICE_ROBE_T1_BLADE_DESC": "Item card. The next Ice hit gains 30%.", "CARD_WEEKEND_ITEM_ICE_ROBE_T2_BLADE_DESC": "Item card. The next Ice hit gains 40%.",
	"CARD_WEEKEND_ITEM_STORM_ROBE_T1_BLADE_DESC": "Item card. The next Storm hit gains 20%.", "CARD_WEEKEND_ITEM_STORM_ROBE_T2_BLADE_DESC": "Item card. The next Storm hit gains 30%.",
	"CARD_WEEKEND_ITEM_MYTH_ROBE_T1_BLADE_DESC": "Item card. The next Myth hit gains 25%.", "CARD_WEEKEND_ITEM_MYTH_ROBE_T2_BLADE_DESC": "Item card. The next Myth hit gains 35%.",
	"CARD_WEEKEND_ITEM_LIFE_ROBE_T1_BLADE_DESC": "Item card. The next Life hit gains 30%.", "CARD_WEEKEND_ITEM_LIFE_ROBE_T2_BLADE_DESC": "Item card. The next Life hit gains 40%.",
	"CARD_WEEKEND_ITEM_DEATH_ROBE_T1_BLADE_DESC": "Item card. The next Death hit gains 30%.", "CARD_WEEKEND_ITEM_DEATH_ROBE_T2_BLADE_DESC": "Item card. The next Death hit gains 40%.",
	"CARD_WEEKEND_ITEM_BALANCE_ROBE_T1_BLADE_DESC": "Item card. The next hit from any school gains 20%.", "CARD_WEEKEND_ITEM_BALANCE_ROBE_T2_BLADE_DESC": "Item card. The next hit from any school gains 25%.",
	"CARD_FIR_012_NAME": "FLASHPOINT", "CARD_FIR_012_DESC": "Immediately resolve one Fire damage-over-time effect.",
	"CARD_ICE_024_NAME": "GLACIAL LOCKDOWN", "CARD_ICE_024_DESC": "Deal 400 Ice damage and skip the target's next action.",
	"CARD_STO_008_NAME": "STORM TRANSMUTATION", "CARD_STO_008_DESC": "Convert one Normal Pip into a Power Pip.",
	"CARD_LIF_020_NAME": "SECOND SPRING", "CARD_LIF_020_DESC": "Revive a defeated ally with 350 health.",
	"CARD_DEA_001_NAME": "SOUL SIPHON", "CARD_DEA_001_DESC": "Deal 80 Death damage and heal for 50% of damage dealt.",
	"CARD_MYT_015_NAME": "MYTHIC SHATTERGLASS", "CARD_MYT_015_DESC": "Remove up to two Shields from the target.",
	"CARD_BAL_007_NAME": "BALANCE PIP GIFT", "CARD_BAL_007_DESC": "Give one Normal Pip to an ally.",
	"CARD_FIR_001_NAME": "CINDER DART", "CARD_FIR_002_NAME": "SMOLDERING BRAND", "CARD_FIR_003_NAME": "FLAME EDGE", "CARD_FIR_004_NAME": "EMBER SNARE",
	"CARD_FIR_005_NAME": "SEARING ORB", "CARD_FIR_006_NAME": "BURNING SPIRAL", "CARD_FIR_007_NAME": "FURNACE MARK", "CARD_FIR_009_NAME": "MAGMA LANCE",
	"CARD_FIR_010_NAME": "PYRE ORBIT", "CARD_FIR_011_NAME": "ASHFALL", "CARD_FIR_014_NAME": "SCORCHING AFTERMARK", "CARD_FIR_015_NAME": "WILDFIRE BLADE", "CARD_FIR_016_NAME": "ENDLESS CINDER",
	"CARD_ICE_001_NAME": "FROST NEEDLE", "CARD_ICE_002_NAME": "SNOW WARD", "CARD_ICE_003_NAME": "RIME BLADE", "CARD_ICE_004_NAME": "CHILLING DOUBT",
	"CARD_ICE_005_NAME": "ICE COMET", "CARD_ICE_006_NAME": "CRYSTAL BASTION", "CARD_ICE_007_NAME": "RIME SNARE", "CARD_ICE_008_NAME": "DEEP FREEZE",
	"CARD_ICE_009_NAME": "FROSTBITE HEX", "CARD_ICE_010_NAME": "HAIL RING", "CARD_ICE_011_NAME": "GLACIAL AEGIS", "CARD_ICE_012_NAME": "PERMAFROST",
	"CARD_ICE_014_NAME": "WINTER CONCORD", "CARD_ICE_015_NAME": "ICEBOUND SENTENCE", "CARD_ICE_016_NAME": "PURGING SNOW",
	"LOG_ROUND": "—— ROUND %d ——", "LOG_PLANNED": "%s selected %s.", "LOG_SKIPPED": "%s passed.", "LOG_CAST": "%s cast %s.",
	"LOG_MISSED": "%s missed %s; pips and hanging effects remain.", "LOG_DEFEATED": "%s fell; temporary state and resources cleared.",
	"LOG_CANNOT_CAST": "Not enough resources.", "LOG_BAD_TARGET": "That target is not valid.", "LOG_TARGET_GONE": "%s lost the target for %s.",
	"LOG_TREASURE_DRAW": "%s discarded and drew a treasure card.", "LOG_CANNOT_DISCARD": "Treasure and newly drawn treasure cannot be discarded this round.",
	"LOG_FUSION_NORMAL_ONLY": "Only learned normal cards can fuse.", "LOG_NO_RECIPE": "These cards have no fusion formula.", "LOG_FUSED": "FUSION: %s.",
	"FLOAT_MISS": "MISS",
}


func _ready() -> void:
	_load_spell_catalog_names()
	var settings := ConfigFile.new()
	if settings.load("user://language.cfg") == OK:
		var saved := str(settings.get_value("display", "language", "zh_CN"))
		locale = saved if saved in ["zh_CN", "en"] else "zh_CN"
	else:
		locale = "zh_CN"
	TranslationServer.set_locale(locale)


func _load_spell_catalog_names() -> void:
	var file := FileAccess.open("res://resources/battle_v2/cards/spell.json", FileAccess.READ)
	if file == null:
		return
	var source := file.get_as_text()
	if not source.is_empty() and source.unicode_at(0) == 0xfeff:
		source = source.substr(1)
	var parsed: Variant = JSON.parse_string(source)
	if not parsed is Dictionary:
		return
	for entry_value in (parsed as Dictionary).get("cards", []):
		var entry := entry_value as Dictionary
		var key := str(entry.get("name_key", ""))
		if key.is_empty():
			continue
		_zh[key] = str(entry.get("name_zh", key))
		_en[key] = str(entry.get("name_en", key))


func text(key: String, args: Array = []) -> String:
	var table := _zh if locale == "zh_CN" else _en
	var result: String = table.get(key, key)
	if not args.is_empty():
		var translated: Array = []
		for arg in args:
			if arg is String and ((arg as String).begins_with("UNIT_") or (arg as String).begins_with("CARD_")):
				translated.append(table.get(arg, arg))
			else:
				translated.append(arg)
		result = result % translated
	return result


func toggle() -> void:
	set_language("en" if locale == "zh_CN" else "zh_CN")


func set_language(value: String) -> void:
	if value not in ["zh_CN", "en"] or locale == value:
		return
	locale = value
	TranslationServer.set_locale(locale)
	var settings := ConfigFile.new()
	settings.set_value("display", "language", locale)
	var error := settings.save("user://language.cfg")
	if error != OK:
		push_warning("Could not save language preference: %s" % error)
	language_changed.emit()
