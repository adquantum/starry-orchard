class_name CardEffectGrammarV2
extends RefCounted
## Presentation adapter only. Never changes executable spell data.
const Icons = preload("res://scripts/battle_v2/presentation/effect_icon_registry_v2.gd")
const ALIASES = {"round":"duration", "delay":"delay_damage", "summon":"summon", "stun":"stun"}

static func adapt(card: CardDefinitionV2) -> Array[Dictionary]:
	var rows: Array[Dictionary]=[]
	var previous: Dictionary={}
	for effect in card.effects:
		if str(effect.get("type", "")) == "apply_aura":
			var modifiers: Dictionary = effect.get("modifiers", {})
			for stat in modifiers:
				var aura_row := effect_row(effect, card)
				var amount := float(modifiers[stat])
				if str(stat) == "extra_power_pip_chance":
					amount *= 100.0
					aura_row.school_icon = &"school_all"
					aura_row.effect_icon = &"resource"
				else:
					aura_row.effect_icon = &"shield" if str(stat) == "incoming_damage" and amount < 0 else (&"trap" if str(stat) == "incoming_damage" else (&"blade" if amount >= 0 else &"weakness"))
				aura_row.value = "%+.0f%%" % amount
				aura_row.source["display_stat"] = str(stat)
				rows.append(aura_row)
			previous = effect
			continue
		# Only adjacent, identical effects can share a repeat marker.
		if effect==previous and not rows.is_empty():
			rows[-1].repeat_count+=1
		else:
			rows.append(effect_row(effect,card))
		previous=effect
	return rows

static func effect_row(effect: Dictionary, card: CardDefinitionV2) -> Dictionary:
	var kind:=str(effect.get("type",""))
	var school: Variant=effect.get("school_filters",effect.get("school",card.school_id))
	if school is Array:school=school[0] if school.size()==1 else "*"
	if str(school) in ["*","universal","all"]:school="all"
	var target:=str(effect.get("target",card.target_type))
	if kind=="apply_global":target="global"
	if target in ["selected","primary"]:target=str(card.target_type)
	var icon:=Icons.effect_icon(effect)
	var row: Dictionary={"value":"", "school_icon":StringName("school_"+str(school)),
		"effect_icon":icon, "target_icon":Icons.target_icon(StringName(target)),
		"duration":0, "duration_icon":&"duration", "repeat_count":1, "qualifier":"",
		"source":effect.duplicate(true), "supported":true}
	match kind:
		"damage","heal","revive","drain","delay_damage":
			row.value=str(int(effect.get("power",0)))
			if effect.has("power_per_pip"):row.value=str(int(effect.power_per_pip))+"/P"
			if kind=="delay_damage":row.duration=int(effect.get("countdown",0))
			if kind=="drain":row.qualifier="%d%%" % roundi(float(effect.get("heal_ratio",0.5))*100)
		"apply_dot":
			row.value=str(int(effect.get("damage_per_tick",0)));row.duration=int(effect.get("ticks",0))
		"apply_hot":
			row.value=str(int(effect.get("healing_per_tick",0)));row.duration=int(effect.get("ticks",0))
		"apply_status":
			row.value="%+.0f%%" % float(effect.get("value",0))
			if effect.has("value_per_pip"):row.value="%+.0f%%" % float(effect.value_per_pip);row.qualifier="/P"
		"health_cost":
			row.value="-%d%%" % roundi(float(effect.current_hp_ratio)*100) if effect.has("current_hp_ratio") else "-%d" % int(effect.get("amount",0))
			if effect.has("max_hp_ratio"):row.value="-%d%%" % roundi(float(effect.max_hp_ratio)*100);row.qualifier="HP"
		"resource":
			var op:=str(effect.get("operation",""))
			row.value=("%+d" % int(effect.get("count",1))) if op.begins_with("add") else str(int(effect.get("count",1)))
			row.qualifier="→" if op.contains("_to_") else ""
		"stun":
			row.value=str(int(effect.get("actions",1)))
		"cleanse","remove_status","steal_status","transfer_dot","detonate","dispel","summon":
			var count:=int(effect.get("count",1))
			row.value="∞" if count<0 else str(count)
		"absorb":
			row.value=str(int(effect.get("value",0)))
			if effect.has("value_per_pip"):row.value=str(int(effect.value_per_pip))+"/P"
			if effect.has("max_hp_ratio"):row.value="%d%%" % roundi(float(effect.max_hp_ratio)*100);row.qualifier="HP"
			if effect.has("max_hp_ratio_per_pip"):row.value="%d%%" % roundi(float(effect.max_hp_ratio_per_pip)*100);row.qualifier="HP/P"
		"modify_dot":
			row.value="%+d" % int(effect.get("ticks_delta",0));row.qualifier="DoT"
		"apply_aura","apply_global":
			row.value="%+.0f%%" % float(effect.get("value",0))
			row.duration=int(effect.get("ticks",0))
		_:
			row.value="?";row.supported=false
	# Preserve complete mechanics in the existing hover detail, including filters and operations.
	row.tooltip=JSON.stringify(effect,"  ")
	return row
