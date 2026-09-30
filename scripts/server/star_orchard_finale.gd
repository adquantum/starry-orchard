extends RefCounted
const DATA_PATH = "res://resources/fusion_3d/orchard_finale.json"
static var cached: Dictionary = {}
static func data() -> Dictionary:
	if cached.is_empty():cached=JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return cached
static func partner(school: String) -> String:return data().pair[school]
static func deck(school: String, companion: bool=false, enemy: bool=false) -> Array:
	return data()["enemy" if enemy else ("ally" if companion else "player")][school].duplicate()
static func register_cards(content: ContentRegistryV2) -> void:
	for id in data().cards:
		var spec: Dictionary=data().cards[id].duplicate(true)
		var source:=content.card(StringName(spec.source))
		spec.id=id;spec.name_key=str(source.name_key);spec.art_path=source.art_path
		spec.accuracy=1.0;spec.learned=true
		spec.presentation=source.presentation.duplicate(true)
		spec.presentation.source_card_id=str(source.id);spec.presentation.teaching_variant=true
		if spec.role in ["blade","shield","weak","trap","heal","hot"]:
			spec.presentation.template="target_buff"
			spec.presentation.impact="magic_"+str(spec.school)+"_aura"
		content.cards[StringName(id)]=CardDefinitionV2.from_dict(spec)
static func ensure_partner(engine: BattleEngineV2) -> void:
	if engine.state.unit_by_id(&"P1")!=null:return
	var school:=partner(str(engine.state.unit_by_id(&"P0").school_id))
	var loadout=preload("res://scripts/worlds/island_loadout.gd")
	engine.state.units.append(engine._create_unit(StringName(loadout.CHARACTERS[loadout.SCHOOLS.find(school)]),0,1))
static func configure(engine: BattleEngineV2, unit: BattleUnitStateV2) -> bool:
	var cards:=deck(str(unit.school_id),unit.id==&"P1",unit.team==1)
	var counts: Dictionary={}
	for id in cards:counts[id]=int(counts.get(id,0))+1
	if not engine.configure_deck(unit.id,counts):return false
	var pool: Array=unit.deck.hand.duplicate();pool.append_array(unit.deck.draw_pile)
	unit.deck.hand.clear();unit.deck.draw_pile.clear();unit.deck.treasure_pile.clear();unit.deck.removed_cards.clear()
	for id in cards:
		for card in pool:
			if str(card.card_id())!=str(id):continue
			card.temporary=true
			if unit.deck.hand.size()<7:unit.deck.hand.append(card)
			else:unit.deck.draw_pile.append(card)
			pool.erase(card);break
	unit.resources.clear_on_death();unit.statuses.clear();unit.archmastery=0
	unit.stats={"accuracy_floor":{"*":1.0}}
	unit.max_hp=(800 if unit.id==&"P0" else 650) if unit.team==0 else (800 if unit.slot==0 else 650)
	unit.hp=unit.max_hp
	if unit.id!=&"P0":unit.ai_profile_id=&"orchard_finale"
	return true
static func has_status(unit: BattleUnitStateV2, kind: StringName) -> bool:
	for status in unit.statuses:
		if status.kind==kind:return true
	return false
static func choose(engine: BattleEngineV2, unit: BattleUnitStateV2) -> ActionIntentV2:
	var round_number:=engine.state.round_index
	var foes:=engine.state.living_units(1-unit.team)
	if foes.is_empty():return ActionIntentV2.pass_turn(unit.id)
	var target: BattleUnitStateV2=foes[0]
	var wanted: String=""
	var cards:=deck(str(unit.school_id),unit.team==0,unit.team==1)
	if unit.team==1:
		if unit.slot==0:wanted=cards[0]
		elif round_number==1:wanted=cards[0];target=unit
		elif round_number==3:
			wanted=cards[1]
			if engine.state.unit_by_id(&"P1").alive:target=engine.state.unit_by_id(&"P1")
		elif round_number==6:wanted=cards[2]
		elif round_number>=8 and round_number%2==0:wanted=cards[3]
	elif unit.school_id==&"life":
		var allies:=engine.state.living_units(0)
		allies.sort_custom(func(a,b):return float(a.hp)/a.max_hp<float(b.hp)/b.max_hp)
		var low: BattleUnitStateV2=allies[0]
		for card in unit.deck.hand:
			var spec: Dictionary=data().cards[str(card.card_id())]
			if spec.role=="heal" and float(low.hp)/low.max_hp<0.6 and engine.cost_resolver.can_pay(unit,card.definition):return ActionIntentV2.cast(unit.id,card.instance_id,[low.id])
		var player:=engine.state.unit_by_id(&"P0")
		for card in unit.deck.hand:
			var spec: Dictionary=data().cards[str(card.card_id())]
			if not engine.cost_resolver.can_pay(unit,card.definition):continue
			if spec.role=="shield" and player.alive and not has_status(player,&"shield"):return ActionIntentV2.cast(unit.id,card.instance_id,[player.id])
			if spec.role=="hot" and not has_status(low,&"hot"):return ActionIntentV2.cast(unit.id,card.instance_id,[low.id])
		for card in unit.deck.hand:
			if data().cards[str(card.card_id())].role=="attack" and engine.cost_resolver.can_pay(unit,card.definition):return ActionIntentV2.cast(unit.id,card.instance_id,[target.id])
	else:
		if round_number<=cards.size():wanted=cards[round_number-1]
		if not wanted.is_empty():
			var role: String=data().cards[wanted].role
			if role in ["shield","heal","hot"]:
				target=engine.state.unit_by_id(&"P0") if round_number<=4 or role=="heal" else unit
				if not target.alive:target=unit
			if role=="blade":
				target=engine.state.unit_by_id(&"P0") if unit.school_id==&"balance" and round_number==2 else unit
				if not target.alive:return ActionIntentV2.pass_turn(unit.id)
	for card in unit.deck.hand:
		if str(card.card_id())==wanted and engine.cost_resolver.can_pay(unit,card.definition):return ActionIntentV2.cast(unit.id,card.instance_id,[target.id])
	return ActionIntentV2.pass_turn(unit.id)
