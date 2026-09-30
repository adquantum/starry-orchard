class_name DotEffectV2
extends EffectHandlerV2


func execute(context: Dictionary) -> void:
	var effect := context.effect as Dictionary
	var base_tick := int(effect.get("damage_per_tick", 0)) + int(effect.get("damage_per_pip", 0)) * int(context.get("payment_value", 0))
	var locked_amount := base_tick
	context.engine.add_status(
		context.target.id, &"dot", context.card.id, context.caster.id,
		effect.get("school", context.card.school_id), 0.0, int(effect.get("ticks", 1)), {"amount": locked_amount,"outgoing_multiplier":float(context.outgoing_multiplier),"source_snapshot":context.engine.damage_resolver.snapshot_source(context.engine.state,context.caster.id,StringName(str(effect.get("school",context.card.school_id))))}
	)
