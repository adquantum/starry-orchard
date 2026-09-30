extends BattleEngineV2
static var setup_data_cache: Dictionary={}
var party: Array[StringName] = [&"fire_student",&"ice_guardian",&"life_healer",&"storm_duelist"]
var party_decks: Dictionary = {}
var enemy_openings: Dictionary = {}
var encounter_id := ""
var encounter_spec: Dictionary = {}
var campaign_level := 0
var boss_phase := 1
var boss_healed := false
static func _setup_data(path: String) -> Dictionary:
	if not setup_data_cache.has(path):
		setup_data_cache[path]=JSON.parse_string(FileAccess.get_file_as_string(path))
	return setup_data_cache[path]

func setup(p_content: ContentRegistryV2, _scenario: Dictionary, seed_value: int = 20260816) -> bool:
	if preload("res://scripts/server/star_orchard_fixed_lessons.gd").active(encounter_id):
		preload("res://scripts/server/star_orchard_fixed_lessons.gd").register_cards(p_content)
	enemy_openings.clear()
	if encounter_id.is_empty():encounter_id="town_showcase"
	if encounter_id=="town_showcase":campaign_level=0
	party_decks = _setup_data("res://resources/fusion_3d/party_decks.json").duplicate(true)
	if encounter_id=="town_showcase" or encounter_id.begins_with("frost_progress_"):
		var showcase: Dictionary=_setup_data("res://resources/fusion_3d/showcase_decks.json")
		if encounter_id=="town_showcase":party_decks=showcase.party.duplicate(true)
		for spec in showcase.cards:
			var card=CardDefinitionV2.from_dict(spec)
			p_content.cards[card.id]=card
	if campaign_level>0:
		for character in party_decks:
			var normal: Dictionary=party_decks[character].normal
			for id in normal.keys():
				if p_content.card(StringName(id)).pip_cost>card_cost_cap():normal.erase(id)
			var total := 0
			for count in normal.values():total+=int(count)
			if total<7:
				var school := str(p_content.characters[character].get("school","fire"))
				for id in p_content.spell_catalog_ids:
					var fallback := p_content.card(id)
					if str(fallback.school_id)==school and fallback.pip_cost<=card_cost_cap() and fallback.target_type==&"enemy":
						normal[str(id)]=int(normal.get(str(id),0))+7-total
						break
	var scenario := p_content.scenario(&"basic_4v4").duplicate(true)
	scenario["teams"][0] = party.duplicate()
	var overrides: Dictionary = scenario.get("rules",{}).get("deck_overrides",{}).duplicate()
	for character in party_decks:
		var deck_id := "academy_"+str(character)
		p_content.decks[deck_id] = party_decks[character].normal.duplicate()
		overrides[character] = deck_id
	if not scenario.has("rules"): scenario.rules = {}
	if not encounter_id.is_empty():
		var selected: Dictionary=encounter_spec.duplicate(true)
		if selected.is_empty():selected=_setup_data("res://resources/fusion_3d/chapter_encounters.json").get(encounter_id,{}).duplicate(true)
		if not selected.is_empty():
			var enemies: Array = []
			for spec in selected.enemies:
				if str(spec.get("ai_profile", "")).begins_with("frost_") and not _valid_frost_enemy(p_content, spec):
					push_error("Invalid Frost enemy configuration: " + str(spec.get("id", "unknown")))
					return false
			for spec in selected.enemies:
				var data: Dictionary = p_content.characters[spec.base].duplicate(true)
				data.id=spec.id
				data.name_key=spec.name
				data.school=spec.school
				data.max_hp=spec.hp
				data.hp=spec.hp
				for field in ["stats", "archmastery", "ai_profile"]:
					if spec.has(field):data[field]=spec[field].duplicate(true) if spec[field] is Dictionary else spec[field]
				if spec.has("starting_resources"):
					if not scenario.has("unit_starting_resources"):scenario.unit_starting_resources={}
					scenario.unit_starting_resources[spec.id]=spec.starting_resources.duplicate(true)
				data.default_deck=spec.id
				data.charge_school=spec.school
				p_content.characters[spec.id]=data
				p_content.decks[spec.id]=spec.deck.duplicate()
				enemy_openings[str(spec.id)]=spec.get("opening",[])
				overrides[spec.id]=spec.id
				enemies.append(spec.id)
			scenario.teams[1]=enemies
	if encounter_id=="town_showcase":
		scenario.player_starting_resources={"normal":3}
		scenario.enemy_starting_resources={"normal":2}
	scenario.rules.deck_overrides = overrides
	return super.setup(p_content,scenario,seed_value)

func _create_unit(character_id: StringName, team: int, slot: int) -> BattleUnitStateV2:
	var unit := super._create_unit(character_id,team,slot)
	if unit != null and team == 0 and campaign_level>0:
		unit.max_hp+=45*(campaign_level-1)
		unit.hp=unit.max_hp
	if unit != null and team == 0 and party_decks.has(str(character_id)):
		unit.deck.treasure_pile.clear()
		for id in party_decks[str(character_id)].treasure:
			unit.deck.treasure_pile.append(_new_card(content.card(StringName(id))))
		_shuffle_cards(unit.deck.treasure_pile)
	if unit != null and team == 1 and (encounter_id.begins_with("frost_progress_") or encounter_id.begins_with("SO1_")):
		unit.deck.treasure_pile.clear()
	if unit!=null and (encounter_id=="town_showcase" or (team==1 and (encounter_id.begins_with("frost_progress_") or encounter_id.begins_with("SO1_")))):
		var opening: Array=party_decks[str(character_id)].opening if team==0 else enemy_openings.get(str(character_id),[])
		for card_id in opening:
			for card in unit.deck.draw_pile:
				if str(card.card_id())==str(card_id):
					unit.deck.draw_pile.erase(card)
					unit.deck.hand.append(card)
					break
	return unit

func card_cost_cap() -> int:
	if campaign_level<=0:return 99
	return 2 if campaign_level<3 else (4 if campaign_level<5 else (6 if campaign_level<7 else (8 if campaign_level<9 else 99)))
func configure_deck(unit_id: StringName, card_counts: Dictionary) -> bool:
	for id in card_counts:
		var card:=content.card(StringName(id))
		if card==null or (int(card_counts[id])>0 and card.pip_cost>card_cost_cap()):return false
	return super.configure_deck(unit_id,card_counts)
func resolve_actor_action(actor: BattleUnitStateV2) -> Array[BattleEventV2]:
	var events:=super.resolve_actor_action(actor)
	update_boss_phase()
	return events
func begin_actor_turn(actor: BattleUnitStateV2) -> Array[BattleEventV2]:
	var events:=super.begin_actor_turn(actor)
	if encounter_id=="SO1_T05" and actor.alive and actor.ai_profile_id==&"orchard_finale" and state.phase!=BattleStateV2.Phase.FINISHED:
		var intent: ActionIntentV2=preload("res://scripts/server/star_orchard_finale.gd").choose(self,actor)
		state.actions[actor.id]=intent
		actor.planned_action=intent
	update_boss_phase()
	return events
func update_boss_phase() -> void:
	if encounter_id!="magister" or state.phase==BattleStateV2.Phase.FINISHED:return
	var boss:=state.unit_by_id(&"E0")
	if boss==null or not boss.alive:return
	var ratio:=float(boss.hp)/float(boss.max_hp)
	var next_phase:=3 if ratio<=0.3 else (2 if ratio<=0.6 else 1)
	if next_phase>boss_phase:
		boss_phase=next_phase
		event_stream.publish(&"WorldBossPhase",state.round_index,{"phase":boss_phase,"unit_id":"E0"})
func resolve_healing(source_id: StringName,target_id: StringName,amount: int,outgoing: float=1.0,origin: StringName=&"spell",apply_charms: bool=true) -> int:
	if encounter_id=="SO1_T05" and not state.unit_by_id(target_id).alive:return 0
	if encounter_id=="magister" and source_id==&"E0" and boss_healed:return 0
	var healed:=super.resolve_healing(source_id,target_id,amount,outgoing,origin,apply_charms)
	if encounter_id=="magister" and source_id==&"E0" and healed>0:boss_healed=true
	return healed


# Only opted-in Frost enemies use this schema; legacy encounters retain their data path.
func _valid_frost_enemy(registry: ContentRegistryV2, spec: Dictionary) -> bool:
	for key in ["id", "name", "school", "base", "ai_profile"]:
		if not spec.get(key) is String or str(spec[key]).is_empty():return false
	if not registry.characters.has(StringName(spec.base)) or not registry.schools.has(StringName(spec.school)):return false
	if not registry.ai_profiles.has(StringName(spec.ai_profile)):return false
	if not _whole_range(spec.get("hp"), 1, 50000) or not _whole_range(spec.get("archmastery"), 0, 200):return false
	if not spec.get("deck") is Dictionary or not spec.get("opening", []) is Array:return false
	var total := 0
	for id in spec.deck:
		if registry.card(StringName(str(id))) == null or not _whole_range(spec.deck[id], 1, 40):return false
		total += int(spec.deck[id])
	if total < 7 or total > 40 or spec.get("opening", []).size() > 7:return false
	var opening_counts: Dictionary = {}
	for id in spec.get("opening", []):
		if not id is String or not spec.deck.has(id):return false
		opening_counts[id]=int(opening_counts.get(id, 0))+1
		if int(opening_counts[id]) > int(spec.deck[id]):return false
	if not spec.get("starting_resources", {}) is Dictionary:return false
	var starting := 0
	for key in spec.get("starting_resources", {}):
		if key not in ["normal", "power"] or not _whole_range(spec.starting_resources[key], 0, 7):return false
		starting += int(spec.starting_resources[key])
	if starting > 7 or not spec.get("stats", {}) is Dictionary:return false
	for stat in spec.get("stats", {}):
		if stat not in ["damage", "resistance", "pierce", "accuracy_floor", "extra_power_pip_chance"]:return false
		var values: Variant = spec.stats[stat]
		if values is Dictionary:
			for school in values:
				if str(school) != "*" and not registry.schools.has(StringName(str(school))):return false
				if not _valid_stat(stat, values[school]):return false
		elif not _valid_stat(stat, values):return false
	return true

func _whole_range(value: Variant, low: int, high: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value)==float(int(value)) and int(value)>=low and int(value)<=high

func _valid_stat(key: String, value: Variant) -> bool:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):return false
	if key in ["accuracy_floor", "extra_power_pip_chance"]:return float(value)>=0.0 and float(value)<=1.0
	return float(value)>=-50.0 and float(value)<=100.0
