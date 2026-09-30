class_name ApplyStatusEffectV2
extends EffectHandlerV2


func execute(context: Dictionary) -> void:
	var effect := context.effect as Dictionary
	context.engine.add_status(
		context.target.id, StringName(str(effect.get("status", ""))), context.card.id,
		context.caster.id, effect.get("school_filters", effect.get("school_filter", "*")),
		float(effect.get("value", 0.0))+float(effect.get("value_per_pip",0.0))*int(context.get("payment_value",0)), int(effect.get("ticks", 0)),
		(effect.get("payload", {}) as Dictionary).duplicate(true)
	)
