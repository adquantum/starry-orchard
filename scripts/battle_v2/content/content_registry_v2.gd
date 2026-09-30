class_name ContentRegistryV2
extends RefCounted

const ROOT := "res://resources/battle_v2"
const SPELL_CATALOG_PATH := "res://resources/battle_v2/cards/spell.json"
const SPELL_CATALOG_EXPECTED_COUNT := 147

var validate_art_paths := true
var schools: Dictionary = {}
var characters: Dictionary = {}
var cards: Dictionary = {}
var spell_catalog_ids: Array[StringName] = []
var statuses: Dictionary = {}
var decks: Dictionary = {}
var fusion_recipes: Dictionary = {}
var treasure_deck: Array[StringName] = []
var scenarios: Dictionary = {}
var encounters: Dictionary = {}
var ai_profiles: Dictionary = {}
var errors: Array[String] = []


func load_default() -> bool:
	errors.clear()
	cards.clear()
	spell_catalog_ids.clear()
	_load_indexed("%s/schools/schools.json" % ROOT, "schools", schools)
	_load_indexed("%s/characters/characters_demo.json" % ROOT, "characters", characters)
	_load_cards("%s/cards/treasure_cards.json" % ROOT)
	_load_cards("%s/cards/item_cards.json" % ROOT)
	_load_indexed("%s/statuses/statuses.json" % ROOT, "statuses", statuses)
	_load_spell_catalog(SPELL_CATALOG_PATH)
	_load_decks("%s/decks/decks_demo.json" % ROOT)
	_load_fusion("%s/fusion/fusion.json" % ROOT)
	_load_scenario("%s/scenarios/basic_4v4.json" % ROOT)
	_load_indexed("%s/encounters/encounters.json" % ROOT, "encounters", encounters)
	_load_indexed("%s/ai/ai_profiles.json" % ROOT, "profiles", ai_profiles)
	_validate_references()
	return errors.is_empty()


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Cannot open %s" % path)
		return null
	var source := file.get_as_text()
	if not source.is_empty() and source.unicode_at(0) == 0xfeff:
		source = source.substr(1)
	var parsed: Variant = JSON.parse_string(source)
	if parsed == null:
		errors.append("Invalid JSON: %s" % path)
	return parsed


func _load_indexed(path: String, key: String, output: Dictionary) -> void:
	output.clear()
	var parsed = _read_json(path)
	if not parsed is Dictionary:
		return
	for entry in (parsed as Dictionary).get(key, []):
		var definition := (entry as Dictionary).duplicate(true)
		output[StringName(str(definition.get("id", "")))] = definition


func _load_cards(path: String) -> void:
	var parsed = _read_json(path)
	if not parsed is Dictionary:
		return
	for entry in (parsed as Dictionary).get("cards", []):
		var definition := CardDefinitionV2.from_dict(entry)
		cards[definition.id] = definition



func _load_spell_catalog(path: String) -> void:
	var parsed = _read_json(path)
	if not parsed is Dictionary:
		return
	var entries := (parsed as Dictionary).get("cards", []) as Array
	if entries.size() != SPELL_CATALOG_EXPECTED_COUNT:
		errors.append("Spell catalog expected %d cards, found %d" % [SPELL_CATALOG_EXPECTED_COUNT, entries.size()])
	var seen := {}
	for entry_value in entries:
		var entry := entry_value as Dictionary
		var definition := CardDefinitionV2.from_dict(entry)
		if definition.id.is_empty() or definition.id == &"unknown":
			errors.append("Spell catalog contains a card without a valid id")
			continue
		if seen.has(definition.id):
			errors.append("Spell catalog contains duplicate card id: %s" % definition.id)
			continue
		seen[definition.id] = true
		spell_catalog_ids.append(definition.id)
		cards[definition.id] = definition
		if validate_art_paths and (definition.art_path.is_empty() or not ResourceLoader.exists(definition.art_path)):
			errors.append("Spell catalog card %s references missing art: %s" % [definition.id, definition.art_path])


func _load_decks(path: String) -> void:
	decks.clear()
	treasure_deck.clear()
	var parsed = _read_json(path)
	if not parsed is Dictionary:
		return
	decks = ((parsed as Dictionary).get("decks", {}) as Dictionary).duplicate(true)
	for id in (parsed as Dictionary).get("treasure_deck", []):
		treasure_deck.append(StringName(str(id)))


func _load_fusion(path: String) -> void:
	fusion_recipes.clear()
	var parsed = _read_json(path)
	if not parsed is Dictionary:
		return
	for recipe in (parsed as Dictionary).get("recipes", []):
		var inputs: Array[String] = []
		for id in (recipe as Dictionary).get("inputs", []):
			inputs.append(str(id))
		inputs.sort()
		fusion_recipes["+".join(inputs)] = StringName(str((recipe as Dictionary).get("result", "")))


func _load_scenario(path: String) -> void:
	var parsed = _read_json(path)
	if parsed is Dictionary:
		scenarios[StringName(str((parsed as Dictionary).get("id", "basic_4v4")))] = (parsed as Dictionary).duplicate(true)


func _validate_references() -> void:
	for character in characters.values():
		var deck_id := str((character as Dictionary).get("default_deck", ""))
		if not decks.has(deck_id):
			errors.append("Character references missing deck: %s" % deck_id)
	for deck_id in decks:
		for card_id in (decks[deck_id] as Dictionary):
			if not cards.has(StringName(str(card_id))):
				errors.append("Deck %s references missing card %s" % [deck_id, card_id])
	for result_id in fusion_recipes.values():
		if not cards.has(result_id):
			errors.append("Fusion references missing card %s" % result_id)


func card(id: StringName) -> CardDefinitionV2:
	return cards.get(id) as CardDefinitionV2


func scenario(id: StringName = &"basic_4v4") -> Dictionary:
	return (scenarios.get(id, {}) as Dictionary).duplicate(true)


func encounter(id: StringName) -> Dictionary:
	return (encounters.get(id, {}) as Dictionary).duplicate(true)
