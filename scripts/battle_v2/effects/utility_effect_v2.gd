class_name UtilityEffectV2
extends EffectHandlerV2


func execute(context: Dictionary) -> void:
	var effect := context.effect as Dictionary
	var type := StringName(str(effect.get("type", "")))
	var engine = context.engine
	var caster: BattleUnitStateV2 = context.caster
	var target: BattleUnitStateV2 = context.target
	var card: CardDefinitionV2 = context.card
	var school := StringName(str(effect.get("school", card.school_id)))
	match type:
		&"drain":
			var power := int(effect.get("power", 0)) + int(effect.get("power_per_pip", 0)) * int(context.get("payment_value", 0))
			var dealt: int = int(engine.resolve_damage(caster.id, target.id, school, power, float(context.get("outgoing_multiplier", 1.0)), &"drain"))
			var healing := roundi(dealt * float(effect.get("heal_ratio", 0.5)))
			engine.resolve_healing(caster.id, caster.id, healing, 1.0, &"drain")
		&"prism":
			var from_filter: Variant = effect.get("from_schools", effect.get("from_school", school))
			engine.add_status(target.id, &"prism", card.id, caster.id, from_filter, 0.0, 0, {"to_school":str(effect.get("to_school", school))})
		&"absorb":
			var capacity := int(effect.get("value", 0)) + int(effect.get("value_per_pip", 0)) * int(context.get("payment_value", 0))
			capacity+=roundi(target.max_hp*(float(effect.get("max_hp_ratio",0))+float(effect.get("max_hp_ratio_per_pip",0))*int(context.get("payment_value",0))))
			engine.add_status(target.id, &"absorb", card.id, caster.id, effect.get("school_filters", "*"), capacity, 0, {
				"origins":effect.get("origins", []), "exclude_origins":effect.get("exclude_origins", [])
			})
		&"stun":
			if not engine.consume_first_status(target.id, {"kinds":["stun_block"]}, &"stun_blocked"):
				engine.add_status(target.id, &"stun", card.id, caster.id, &"*", 0.0, int(effect.get("actions", 1)), {})
				engine.add_status(target.id, &"stun_block", card.id, caster.id, &"*", 0.0, int(effect.get("block_rounds", 0)), {})
		&"dispel":
			engine.add_status(target.id, &"dispel", card.id, caster.id, effect.get("school_filters", effect.get("school_filter", school)), 0.0, 0, {})
		&"apply_aura":
			engine.remove_statuses(target.id, {"kinds":["aura"]}, -1, &"aura_replaced")
			var aura_payload: Dictionary = (effect.get("payload", {}) as Dictionary).duplicate(true)
			aura_payload["modifiers"] = (effect.get("modifiers", {}) as Dictionary).duplicate(true)
			aura_payload["applied_round"] = engine.state.round_index
			engine.add_status(target.id, &"aura", card.id, caster.id, effect.get("school_filters", "*"), 0.0, int(effect.get("ticks", 4)), aura_payload)
		&"apply_global":
			engine.remove_global_statuses({"kinds":["global"]}, &"global_replaced")
			engine.add_global_status(&"global", card.id, caster.id, effect.get("school_filters", "*"), 0.0, int(effect.get("ticks", 0)), {
				"team":int(effect.get("team", -1)), "modifiers":(effect.get("modifiers", {}) as Dictionary).duplicate(true)
			})
		&"remove_status", &"cleanse", &"consume_status":
			engine.remove_statuses(target.id, _criteria(effect, type), int(effect.get("count", -1)), type)
		&"steal_status":
			engine.steal_statuses(target.id, caster.id, _criteria(effect, type), int(effect.get("count", 1)))
		&"detonate":
			engine.detonate_dots(target.id, int(effect.get("count", 1)), effect.get("school_filters", "*"))
		&"transfer_dot":
			engine.transfer_dot(caster.id,target.id)
		&"modify_dot":
			engine.modify_dot_duration(target.id, int(effect.get("ticks_delta", 0)), int(effect.get("count", 1)), effect.get("school_filters", "*"))
		&"resource":
			engine.modify_resources(target.id, effect)
		&"health_cost":
			var amount := int(effect.get("amount", 0))
			if effect.has("current_hp_ratio"):
				amount = ceili(caster.hp * float(effect.current_hp_ratio))
			elif effect.has("max_hp_ratio"):
				amount = ceili(caster.max_hp * float(effect.max_hp_ratio))
			var hp_before := caster.hp
			caster.hp = maxi(0, caster.hp - maxi(amount, 0))
			engine.event_stream.publish(&"HealthSpent", engine.state.round_index, {"unit_id":str(caster.id), "target_id":str(caster.id), "caster_id":str(caster.id), "school":str(school), "origin":"health_cost", "amount":hp_before - caster.hp, "hp_before":hp_before, "hp_after":caster.hp})
			if caster.hp <= 0:
				engine.death_resolver.kill(engine.state, caster)



func _criteria(effect: Dictionary, type: StringName) -> Dictionary:
	return preload("res://scripts/battle_v2/core/status_query_v2.gd").criteria_from(effect, "harmful" if type == &"cleanse" else "any")

