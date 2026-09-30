extends StatusResolverV2

func consume_multiplier(unit: BattleUnitStateV2,kinds: Array[StringName],school: StringName,round_index: int,origin: StringName=&"spell") -> float:
	if origin==&"relic_secondary":
		var filtered: Array[StringName]=[]
		for kind in kinds:
			if kind not in [&"blade",&"trap"]:filtered.append(kind)
		return super.consume_multiplier(unit,filtered,school,round_index,origin)
	return super.consume_multiplier(unit,kinds,school,round_index,origin)
