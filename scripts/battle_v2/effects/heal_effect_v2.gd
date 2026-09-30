class_name HealEffectV2
extends EffectHandlerV2


func execute(context: Dictionary) -> void:
	var effect := context.effect as Dictionary
	var power := int(effect.get("power", 0)) + int(effect.get("power_per_pip", 0)) * int(context.get("payment_value", 0))
	context.engine.resolve_healing(context.caster.id, context.target.id, power, float(context.get("outgoing_multiplier",1.0)), &"spell", false)
