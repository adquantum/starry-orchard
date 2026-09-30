class_name HotEffectV2
extends EffectHandlerV2


func execute(context: Dictionary) -> void:
	var effect := context.effect as Dictionary
	var amount := int(effect.get("healing_per_tick", 0)) + int(effect.get("healing_per_pip", 0)) * int(context.get("payment_value", 0))
	amount=roundi(amount*float(context.get("outgoing_multiplier",1.0)))
	context.engine.add_status(
		context.target.id, &"hot", context.card.id, context.caster.id,
		&"*", 0.0, int(effect.get("ticks", 1)), {"amount":amount}
	)
