extends CostResolverV2
var secondaries: Dictionary = {}
func get_pip_payment_value(resources: ResourceStateV2, index: int, caster: BattleUnitStateV2 = null, spell: CardDefinitionV2 = null) -> int:
	if caster != null and spell != null and secondaries.has(str(caster.id)) and not str(secondaries[str(caster.id)]).is_empty() and str(spell.school_id)==str(secondaries[str(caster.id)]) and index>=0 and index<resources.pips.size() and resources.pips[index]==ResourceStateV2.PipKind.POWER:return 2
	return super.get_pip_payment_value(resources,index,caster,spell)
