class_name DamageEffectV2
extends EffectHandlerV2


func execute(context: Dictionary) -> void:
	var effect := context.effect as Dictionary
	var power := int(effect.get("power", 0)) + int(effect.get("power_per_pip", 0)) * int(context.get("payment_value", 0))
	context.engine.resolve_damage(
		context.caster.id, context.target.id, StringName(str(effect.get("school", context.card.school_id))),
		power, float(context.outgoing_multiplier), &"spell"
	)
