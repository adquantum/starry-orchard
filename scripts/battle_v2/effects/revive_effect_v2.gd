class_name ReviveEffectV2
extends EffectHandlerV2


func execute(context: Dictionary) -> void:
	var effect := context.effect as Dictionary
	var amount := int(effect.get("power", 1))
	if effect.has("max_hp_ratio"):
		amount = roundi(context.target.max_hp * float(effect.max_hp_ratio))
	context.engine.revive_unit(context.target.id, maxi(amount, 1))
