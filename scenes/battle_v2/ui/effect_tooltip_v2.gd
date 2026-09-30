extends PanelContainer
const SCHOOLS={"fire":"火焰","ice":"冰霜","storm":"风暴","life":"生命","death":"死亡","balance":"平衡","myth":"神话","all":"全系"}
const TARGETS={"self":"自身","ally":"一名友方","all_allies":"全部友方","enemy":"一名敌方","all_enemies":"全部敌方","dead_ally":"一名倒下的友方","global":"整个战场"}
const EFFECTS={"damage":"直接伤害","heal":"即时治疗","dot":"持续伤害；每回合触发一次伤害","hot":"持续治疗；每回合恢复一次生命","blade":"增伤；提高下一次对应系别法术造成的伤害，触发后消耗","weakness":"虚弱；降低下一次对应系别法术造成的伤害，触发后消耗","shield":"护盾；降低下一次对应系别的伤害，触发后消耗","trap":"陷阱；提高下一次受到的对应系别伤害，触发后消耗","infection":"感染；削弱施法者下一次施放的治疗，随后消耗","dispel":"驱散；使下一个对应系别的法术失效","cleanse":"净化；移除负面状态","remove":"移除匹配状态","revive":"复活倒下的友方并恢复生命","summon":"召唤指定生物","stun":"眩晕；跳过行动","delay_damage":"倒计时结束后造成伤害","drain":"吸血；按实际伤害恢复施法者生命","resource":"调整能量资源","health_cost":"支付生命值","detonate":"立即结算剩余持续伤害","steal_status":"将匹配状态转移给施法者"}
static func panel(text: String) -> Control:
	var box=load("res://scenes/battle_v2/ui/effect_tooltip_v2.gd").new()
	var label:=Label.new()
	label.text=preload("res://scenes/battle_v2/ui/hover_text_v2.gd").clean(text);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size=Vector2(310,0)
	label.add_theme_font_size_override("font_size",15)
	box.add_child(label)
	return box
static func icon_text(id: StringName) -> String:
	var key:=str(id)
	var extra := {"accuracy_blade":"命中提升；提高下一次对应系别法术的命中率，触发后消耗", "accuracy_weakness":"命中降低；降低下一次对应系别法术的命中率，触发后消耗", "healing_blade":"治疗刃；提高下一次施放的治疗效果，触发后消耗", "prism":"棱镜；将下一次对应系别的伤害转换为指定系别，触发后消耗", "absorb":"吸收盾；吸收伤害，直到剩余容量耗尽", "aura":"光环；在持续回合内提供属性加成", "global":"场地；对整个战场提供持续效果", "stun_block":"眩晕防护；抵挡下一次眩晕，触发后消耗"}
	if extra.has(key):return str(extra[key])
	if key.begins_with("school_"):
		var school:=key.trim_prefix("school_")
		return str(SCHOOLS.get(school,school))+"系：此行伤害或效果的系别归属；状态图标表示适用系别。"
	if key.begins_with("target_"):
		var target:=key.trim_prefix("target_")
		return str(TARGETS.get(target,target))+"：此行效果作用的目标。"
	return str(EFFECTS.get(key,EffectIconRegistryV2.entry(id).tooltip))
static func duration_text(row: Dictionary) -> String:
	if str(row.source.type) == "apply_aura":return "光环持续%d回合；同一目标只能存在一个光环，新光环会覆盖旧光环。" % int(row.duration)
	if int(row.duration)>0:
		if str(row.source.type)=="delay_damage":return "倒计时 "+str(row.duration)+" 回合后触发伤害。"
		return "持续 "+str(row.duration)+" 次回合触发；数值为每次触发的量，不是总量。"
	if int(row.repeat_count)>1:return "独立重复此效果 "+str(row.repeat_count)+" 次。"
	if str(row.source.type)=="drain":return "按实际造成伤害的 "+str(row.qualifier)+" 恢复施法者生命。"
	return "数量或转换规则："+str(row.qualifier)
static func describe(row: Dictionary) -> String:
	var e: Dictionary=row.source
	var t:=str(TARGETS.get(str(row.target_icon).trim_prefix("target_"),"目标"))
	var s:=str(SCHOOLS.get(str(row.school_icon).trim_prefix("school_"),""))
	var v:=str(row.value)
	var result: String
	match str(e.type):
		"apply_aura":
			var stat := str(e.get("display_stat", "outgoing_damage"))
			var label := "魔豆生成概率" if stat == "extra_power_pip_chance" else ("受到的伤害" if stat == "incoming_damage" else s+"造成的伤害")
			result = "%s的%s%s，持续%d回合。\n光环：攻击后不消耗；新的光环会替换旧光环。" % [t,label,v,row.duration]
		"apply_global":result="全场双方造成的%s伤害提高%s。\n场地：对双方生效，攻击后不消耗，直到战斗结束或被新场地替换。" % [s,v]
		"damage":result="对%s造成%s点%s伤害。" % [t,v,s]
		"heal":result="为%s恢复%s点生命。" % [t,v]
		"apply_hot":result="为%s施加持续治疗，每回合恢复%s点生命，持续%d回合。" % [t,v,row.duration]
		"apply_dot":result="对%s施加持续伤害，每回合造成%s点%s伤害，持续%d回合。" % [t,v,s,row.duration]
		"delay_damage":result="对%s施加倒计时，%d回合后造成%s点%s伤害。" % [t,row.duration,v,s]
		"apply_status":
			var kind := str(e.get("status", ""))
			var rules := {
				"blade":["刀刃", "下一次造成的", "伤害", "提高持有者下一次对应系别法术的伤害，触发后消耗。"],
				"weakness":["虚弱", "下一次造成的", "伤害", "降低持有者下一次对应系别法术的伤害，触发后消耗。"],
				"shield":["盾牌", "下一次受到的", "伤害", "降低持有者下一次受到的对应系别伤害，触发后消耗。"],
				"trap":["陷阱", "下一次受到的", "伤害", "提高持有者下一次受到的对应系别伤害，触发后消耗。"],
				"healing_blade":["治疗刃", "下一次施放的", "治疗", "提高持有者下一次施放的治疗效果，触发后消耗。"],
				"infection":["感染", "下一次施放的", "治疗", "降低持有者下一次施放的治疗效果，触发后消耗。"],
				"accuracy_blade":["命中提升", "下一次施放的", "法术命中率", "提高持有者下一次对应系别法术的命中率，触发后消耗。"],
				"accuracy_weakness":["命中降低", "下一次施放的", "法术命中率", "降低持有者下一次对应系别法术的命中率，触发后消耗。"]
			}
			if rules.has(kind):
				var rule: Array = rules[kind]
				var filters: Variant = e.get("school_filters", e.get("school_filter", "*"))
				var scope := preload("res://scripts/battle_v2/presentation/status_text_v2.gd").school_text({"school_filters":filters if filters is Array else [filters]})
				if kind in ["healing_blade", "infection"]: scope = "全系"
				result = "%s：【%s】【%s】%s%s" % [rule[0],rule[1],scope,rule[2],v]
				result += "\n%s：%s" % [rule[0],rule[3]]
			else:
				var keyword := icon_text(row.effect_icon).split("；")
				result="为%s施加%s（%s，适用于%s）。" % [t,keyword[0],v,s]
				if keyword.size()>1:result+="\n%s：%s。" % [keyword[0],keyword[1].trim_suffix("。")]
		"dispel":result="使%s下一个%s系法术失效。" % [t,s]
		"revive":result="复活%s，并恢复%s点生命。" % [t,v]
		"summon":result="在%s召唤%s个指定生物（%s）。" % [t,v,str(e.get("creature_id","由法术指定"))]
		"drain":result="对%s造成%s点%s伤害，并按实际伤害的%s恢复施法者生命。" % [t,v,s,row.qualifier]
		"stun":result="使%s跳过%s次行动，并在未被阻挡时赋予眩晕防护。" % [t,v]
		"health_cost":
			result="施法者支付当前生命的%s（向上取整）。" % v.trim_prefix("-") if e.has("current_hp_ratio") else "施法者支付%s点生命。" % v.trim_prefix("-")
		"cleanse","remove_status","steal_status":
			var kinds: Array=e.get("kinds",[])
			var labels: Array[String]=[]
			for kind in kinds:labels.append(preload("res://scripts/battle_v2/presentation/status_text_v2.gd").kind_name(str(kind)))
			var filter_text: String="、".join(labels) if not labels.is_empty() else ("负面状态" if e.type=="cleanse" else "匹配状态")
			result=("%s%s的%s%s。" % ["转移至施法者：" if e.type=="steal_status" else "移除",t,"全部" if v=="∞" else v+"个",filter_text])
		"absorb":
			var capacity:=v
			if e.has("max_hp_ratio"):capacity="目标最大生命的%d%%" % roundi(float(e.max_hp_ratio)*100)
			if e.has("max_hp_ratio_per_pip"):capacity="目标最大生命的%d%% × 本次消耗的魔豆点数" % roundi(float(e.max_hp_ratio_per_pip)*100)
			result="为%s提供数值吸收盾，容量为%s。" % [t,capacity]
			if "drain" in e.get("exclude_origins",[]):result+="\n吸收盾：不吸收吸血类伤害。"
		"transfer_dot":result="将自身的1个持续伤害转移给%s，保留伤害、来源及剩余触发次数。" % t
		"modify_dot":result="%s身上的所有持续伤害各减少1次剩余触发，不提前造成伤害。" % t
		"detonate":result="立即结算%s身上%s个匹配持续伤害的剩余伤害。" % [t,v]
		"resource":
			var operation: String={"add_power":"增加强力能量","add_normal":"增加普通能量","normal_to_power":"将普通能量转换为强力能量","remove":"移除能量"}.get(str(e.get("operation","")),"调整能量")
			result="为%s%s，数量%s。" % [t,operation,v]
		_:result=icon_text(row.effect_icon)+"；目标："+t+"；数值："+v
	if str(e.type)=="health_cost" and e.has("max_hp_ratio"):result="施法者支付最大生命的%d%%。" % roundi(float(e.max_hp_ratio)*100)
	if e.has("value_per_pip"):result+="\n每消耗1点魔豆，增幅增加%d%%；只放置1枚陷阱。" % int(e.value_per_pip)
	if int(row.repeat_count)>1:result+="\n独立重复%d次。" % int(row.repeat_count)
	return preload("res://scenes/battle_v2/ui/hover_text_v2.gd").clean(result)


# Keep all executable effect text ahead of the shared keyword glossary.
static func description_parts(row: Dictionary) -> Dictionary:
	var lines := describe(row).split("\n")
	var effects: Array[String] = [lines[0]]
	var notes: Array[String] = []
	for i in range(1, lines.size()):
		if "：" in lines[i]: notes.append(lines[i])
		else: effects.append(lines[i])
	return {"effect":"\n".join(effects), "notes":notes}
