class_name EffectRegistryV2
extends RefCounted

const UtilityEffectScript := preload("res://scripts/battle_v2/effects/utility_effect_v2.gd")

var handlers: Dictionary = {}


func _init() -> void:
	register(&"damage", DamageEffectV2.new())
	register(&"heal", HealEffectV2.new())
	register(&"apply_status", ApplyStatusEffectV2.new())
	register(&"apply_dot", DotEffectV2.new())
	register(&"apply_hot", HotEffectV2.new())
	register(&"delay_damage", DelayDamageEffectV2.new())
	register(&"revive", ReviveEffectV2.new())
	var utility: EffectHandlerV2 = UtilityEffectScript.new()
	for type in [&"drain", &"prism", &"absorb", &"stun", &"dispel", &"apply_aura", &"apply_global", &"remove_status", &"cleanse", &"consume_status", &"steal_status", &"detonate", &"modify_dot", &"transfer_dot", &"resource", &"health_cost"]:
		register(type, utility)


func register(type: StringName, handler: EffectHandlerV2) -> void:
	handlers[type] = handler


func has(type: StringName) -> bool:
	return handlers.has(type)


func execute(type: StringName, context: Dictionary) -> bool:
	var handler := handlers.get(type) as EffectHandlerV2
	if handler == null:
		return false
	handler.execute(context)
	return true
