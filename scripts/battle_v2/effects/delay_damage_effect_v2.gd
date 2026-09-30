class_name DelayDamageEffectV2
extends EffectHandlerV2


func execute(context: Dictionary) -> void:
	var effect := context.effect as Dictionary
	var base_amount := int(effect.get("power", 0)) + int(effect.get("power_per_pip", 0)) * int(context.get("payment_value", 0))
	var locked_amount := base_amount
	var payload := {"amount": locked_amount,"outgoing_multiplier":float(context.outgoing_multiplier)}
	payload.source_snapshot = context.engine.damage_resolver.snapshot_source(context.engine.state,context.caster.id,StringName(str(effect.get("school",context.card.school_id))))
	if effect.has("heal_ratio"):
		payload["heal_ratio"] = float(effect.heal_ratio)
	context.engine.add_status(
		context.target.id, &"delay_damage", context.card.id, context.caster.id,
		effect.get("school", context.card.school_id), 0.0, int(effect.get("countdown", 1)), payload
	)
