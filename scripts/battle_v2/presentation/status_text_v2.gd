extends RefCounted

const NAMES := {"blade":"伤害刃", "weakness":"虚弱", "healing_blade":"治疗刃", "infection":"感染", "accuracy_blade":"命中提升", "accuracy_weakness":"命中降低", "shield":"护盾", "trap":"陷阱", "prism":"棱镜", "absorb":"吸收盾", "dot":"持续伤害", "hot":"持续治疗", "delay_damage":"炸弹", "aura":"光环", "global":"场地", "stun":"眩晕", "stun_block":"眩晕防护", "dispel":"驱散", "stat_modifier":"属性效果"}
const STATS := {"outgoing_damage":"造成伤害", "incoming_damage":"受到伤害", "outgoing_healing":"施放治疗", "incoming_healing":"受到治疗", "accuracy":"命中率", "extra_power_pip_chance":"强力魔豆概率", "pierce":"穿透", "resist":"抗性"}
const SCHOOLS := {"*":"全系", "":"全系", "all":"全系", "fire":"火焰", "ice":"冰霜", "storm":"风暴", "myth":"神话", "life":"生命", "death":"死亡", "balance":"平衡", "shadow":"暗影"}

static func kind_name(kind: String) -> String:
	return str(NAMES.get(kind, "特殊效果"))

static func school_text(data: Dictionary) -> String:
	var names: Array[String] = []
	for school in data.get("school_filters", [data.get("school_filter", "*")]):
		var label := str(SCHOOLS.get(str(school), "全系"))
		if label == "全系": return label
		if not names.has(label): names.append(label)
	return "全系" if names.is_empty() else "、".join(names)

static func value_text(data: Dictionary) -> String:
	var kind := str(data.get("kind", ""))
	var value := float(data.get("value", 0))
	var ticks := int(data.get("ticks", 0))
	var payload: Dictionary = data.get("payload", {})
	var periodic_amount:=float(payload.get("amount",value))
	if payload.has("source_snapshot"):
		var snapshot: Dictionary=payload.source_snapshot
		periodic_amount=(periodic_amount*maxf(0.0,1.0+float(snapshot.get("damage",0))/100.0)+float(snapshot.get("flat",0)))*float(snapshot.get("aura",1.0))*float(snapshot.get("global",1.0))*float(payload.get("outgoing_multiplier",1.0))
	match kind:
		"dot", "hot": return "%d / 回合  ·  ◷ %d回合" % [roundi(periodic_amount), ticks]
		"delay_damage": return "%d伤害  ·  ◷ %d回合后爆炸" % [roundi(periodic_amount), ticks]
		"aura", "global", "stat_modifier":
			var parts: Array[String] = []
			var modifiers: Dictionary = payload.get("modifiers", {})
			for stat in modifiers:
				var amount := float(modifiers[stat]) * (100.0 if str(stat) == "extra_power_pip_chance" else 1.0)
				parts.append("%s %+.0f%%" % [STATS.get(str(stat), "属性"), amount])
			return "、".join(parts) + ("  ·  ◷ %d回合" % ticks if ticks > 0 else "  ·  持续生效")
		"absorb": return "剩余吸收 %d" % roundi(value)
		"prism": return "%s → %s" % [school_text(data), SCHOOLS.get(str(payload.get("to_school", "*")), "全系")]
		"stun": return "跳过 %d 次行动" % ticks
		"stun_block", "dispel": return "◷ %d回合" % ticks if ticks > 0 else "触发后消耗"
	return "%+.0f%%" % value

static func source_name(data: Dictionary, content: ContentRegistryV2) -> String:
	if content != null:
		var card := content.card(StringName(str(data.get("source_id", ""))))
		if card != null:
			var translated := Locale.text(str(card.name_key))
			if translated != str(card.name_key): return translated
	return kind_name(str(data.get("kind", "")))
