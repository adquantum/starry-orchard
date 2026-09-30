extends ActionResolverV2

func _execute_effect(engine,actor: BattleUnitStateV2,card: CardDefinitionV2,effect: Dictionary,targets: Array[BattleUnitStateV2],payment: Dictionary,plans: Dictionary) -> void:
	engine.relic_runtime.effect_index+=1
	super._execute_effect(engine,actor,card,effect,targets,payment,plans)
