extends RefCounted
const SCHOOLS = ["fire","ice","storm","myth","life","death","balance"]
const CHARACTERS = ["fire_student","ice_guardian","storm_duelist","myth_scholar","life_healer","death_reaper","balance_adept"]
const Allies = preload("res://scripts/worlds/island_ai_allies.gd")
var school := "life"
var ai_count := 0
var saved: Dictionary = {}
var content := ContentRegistryV2.new()
var equipment_rules := EquipmentRules.new()
var progression_snapshot: Dictionary = {}
var defaults: Dictionary = {}
var path := ""
var preset_path := ""
var presets: Dictionary = {"version":1,"presets":{}}

func setup(save_path: String, initial_school: String) -> void:
	path = save_path
	preset_path = path.get_base_dir().path_join("academy_deck_presets.json")
	content.load_default()
	equipment_rules.load_default()
	var showcase: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/showcase_decks.json"))
	for spec in showcase.cards:
		var card := CardDefinitionV2.from_dict(spec)
		content.cards[card.id] = card
	defaults = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/party_decks.json"))
	# Only fallback presets change; counts() still prefers the player's saved deck.
	var starter_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/frost_starter_decks.json"))
	if starter_data is Dictionary:
		for key in starter_data.get("deck_overrides", {}):
			var counts_value: Variant = starter_data.deck_overrides[key]
			if defaults.has(key) and valid_counts(counts_value):defaults[key].normal=counts_value.duplicate(true)
			else:push_error("Invalid Frost fallback deck: " + str(key))
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:saved = data
	if FileAccess.file_exists(preset_path):
		var preset_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(preset_path))
		if preset_data is Dictionary and preset_data.get("presets",{}) is Dictionary:presets = preset_data
	# The authenticated character school wins. The former local selector remains
	# readable for migration, but can no longer override a formal character.
	school = initial_school
	if school not in SCHOOLS:school = "life"
	ai_count = clampi(int(saved.get("__island_ai",0)),0,Allies.MAX_ALLIES)
	_bind_accounts_progression()

func _bind_accounts_progression() -> void:
	var tree:=Engine.get_main_loop() as SceneTree
	var accounts:=tree.root.get_node_or_null("Accounts") if tree else null
	if accounts==null:return
	var callback:=Callable(self,"_on_progression_changed")
	if accounts.has_signal("progression_changed") and not accounts.is_connected("progression_changed",callback):
		accounts.connect("progression_changed",callback)
	var current: Variant=accounts.get("progression_snapshot")
	if current is Dictionary and not (current as Dictionary).is_empty():set_progression_snapshot(current)

func _on_progression_changed(value: Dictionary) -> void:
	set_progression_snapshot(value)

func set_progression_snapshot(value: Variant) -> Dictionary:
	var checked:=equipment_rules.validate_snapshot(value)
	if not bool(checked.ok):
		progression_snapshot={}
		return checked
	progression_snapshot=(value as Dictionary).duplicate(true)
	school=str(progression_snapshot.school)
	return {"ok":true,"code":"ok"}

func character(value: String = "") -> String:
	if value.is_empty():value=school
	return CHARACTERS[SCHOOLS.find(value)] if value in SCHOOLS else "life_healer"

func counts(value: String = "") -> Dictionary:
	if value.is_empty():value=school
	var key:=character(value)
	if saved.has(key):
		var result: Variant = saved[key]
		if result is Dictionary:result = _without_retired_cards(result)
		if valid_counts(result):return result.duplicate(true)
	return defaults[key].normal.duplicate(true)

func valid_counts(value: Variant) -> bool:
	if not value is Dictionary or value.size()>40:return false
	var total := 0
	for id in value:
		if typeof(value[id]) not in [TYPE_INT,TYPE_FLOAT]:return false
		var count := int(value[id])
		var card := content.card(StringName(str(id)))
		if count<0 or count>40 or float(count)!=float(value[id]) or card==null:return false
		if not card.learned or card.treasure or card.enemy_only:return false
		total += count
	return total<=40

func _without_retired_cards(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for id in ["sto_020", "fir_008", "dea_007"]:result.erase(id)
	return result

func preset(slot: int,value: String="") -> Dictionary:
	if slot<1 or slot>3:return {}
	if value.is_empty():value=school
	var by_character: Variant=presets.get("presets",{}).get(character(value),{})
	if not by_character is Dictionary:return {}
	var entry: Variant=by_character.get(str(slot),{})
	if entry is Dictionary and entry.get("counts") is Dictionary:
		entry = entry.duplicate(true)
		entry.counts = _without_retired_cards(entry.counts)
	if not entry is Dictionary or not valid_counts(entry.get("counts",null)):return {}
	var result: Dictionary=entry.duplicate(true)
	result.counts=_normalize_counts(result.counts)
	result.card_total=_count_cards(result.counts)
	return result

func save_preset(slot: int,value: Dictionary) -> bool:
	if slot<1 or slot>3 or not valid_counts(value):return false
	var all_presets: Dictionary=presets.get("presets",{})
	var key:=character()
	var by_character: Dictionary=all_presets.get(key,{})
	by_character[str(slot)]={
		"slot":slot,
		"school":school,
		"character":key,
		"counts":value.duplicate(true),
		"card_total":_count_cards(value),
		"saved_at":int(Time.get_unix_time_from_system())
	}
	all_presets[key]=by_character
	presets={"version":1,"presets":all_presets}
	return _write_presets()

func load_preset(slot: int) -> Dictionary:
	var entry:=preset(slot)
	return entry.get("counts",{}).duplicate(true) if not entry.is_empty() else {}

func export_preset(slot: int,export_dir: String="user://deck_exports") -> String:
	var entry:=preset(slot)
	if entry.is_empty():return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(export_dir))
	var filename:="astral-garden-deck-%s-preset-%d-%d.json"%[school,slot,int(Time.get_unix_time_from_system())]
	var export_path:=export_dir.path_join(filename)
	var payload:={"format":"astral-garden-deck","version":1,"preset":entry}
	var file:=FileAccess.open(export_path,FileAccess.WRITE)
	if file==null:return ""
	file.store_string(JSON.stringify(payload,"  "))
	file.flush()
	var error:=file.get_error();file.close()
	return export_path if error==OK else ""

func _write_presets() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(preset_path.get_base_dir()))
	var file:=FileAccess.open(preset_path,FileAccess.WRITE)
	if file==null:return false
	file.store_string(JSON.stringify(presets,"  "))
	file.flush()
	var error:=file.get_error();file.close()
	return error==OK

func _count_cards(value: Dictionary) -> int:
	var total:=0
	for count in value.values():total+=int(count)
	return total

func _normalize_counts(value: Dictionary) -> Dictionary:
	var result: Dictionary={}
	for id in value:
		var count:=int(value[id])
		if count>0:result[str(id)]=count
	return result

func profile() -> Dictionary:
	return {
		"school":school,"counts":counts(),"ai":clampi(ai_count,0,Allies.MAX_ALLIES),"treasures":treasure_counts(),
		"equipment":equipment_cards(),"disabled_item_cards":disabled_item_cards(),"progression_snapshot":progression_snapshot.duplicate(true)
	}

func clean_profile(value: Variant) -> Dictionary:
	if not value is Dictionary:return {}
	if str(value.get("school","")) not in SCHOOLS or not valid_counts(value.get("counts")):return {}
	if not Allies.valid_request(value.get("ai",0)):return {}
	var result: Dictionary={"school":str(value.school),"counts":value.counts.duplicate(true),"ai":int(value.get("ai",0))}
	result.treasures=clean_treasures(value.get("treasures",{}))
	# Client equipment fields never prove ownership. Task 01 attaches the
	# authenticated progression snapshot after this deck-only cleaning step.
	result.equipment=[]
	result.disabled_item_cards=clean_disabled_item_cards(value.get("disabled_item_cards",[]))
	return result

func ensure_inventory() -> void:
	if not progression_snapshot.is_empty():return
	if saved.has("__treasure_inventory"):return
	# Migrate the current character's former preset exactly once, never on reopening.
	var stock: Dictionary={}
	for id in defaults[character()].treasure:stock[str(id)]=int(stock.get(str(id),0))+1
	saved.__treasure_inventory=stock
	saved.__treasure_decks={character():stock.duplicate(true)}
	save()

func inventory() -> Dictionary:
	if not progression_snapshot.is_empty():
		return (progression_snapshot.get("treasure_inventory",{}) as Dictionary).duplicate(true)
	ensure_inventory()
	return saved.__treasure_inventory.duplicate(true)

func clean_treasures(value: Variant) -> Dictionary:
	var result: Dictionary={}
	if not value is Dictionary:return result
	var legal:=equipment_rules.legal_treasure_card_ids()
	var total:=0
	for id in value:
		var card:=content.card(StringName(str(id)))
		if str(id) not in legal or card==null or not card.treasure or card.enemy_only or typeof(value[id]) not in [TYPE_INT,TYPE_FLOAT]:continue
		var n:=clampi(int(value[id]),0,mini(9,40-total))
		if n>0:result[str(id)]=n;total+=n
	return result

func treasure_counts() -> Dictionary:
	var stock:=inventory()
	var result:=clean_treasures(saved.get("__treasure_decks",{}).get(character(),{}))
	var reserved: Dictionary=progression_snapshot.get("treasure_reserved",{}) if not progression_snapshot.is_empty() else {}
	for id in result.keys():
		result[id]=mini(int(result[id]),maxi(0,int(stock.get(id,0))-int(reserved.get(id,0))))
		if result[id]<=0:result.erase(id)
	return result

func save_treasures(value: Dictionary) -> void:
	ensure_inventory()
	if not saved.get("__treasure_decks",null) is Dictionary:saved.__treasure_decks={}
	saved.__treasure_decks[character()]=clean_treasures(value)
	saved.__treasure_decks[character()]=treasure_counts()
	save()

func grant_treasure(id: String, amount: int) -> void:
	if not progression_snapshot.is_empty():return
	var card:=content.card(StringName(id))
	if card==null or not card.treasure or amount<=0:return
	ensure_inventory()
	saved.__treasure_inventory[id]=int(saved.__treasure_inventory.get(id,0))+amount
	save()

func consume_treasure(id: String, token: String) -> bool:
	if not progression_snapshot.is_empty():return false
	if token.is_empty():return false
	ensure_inventory()
	var receipts: Dictionary=saved.get("__treasure_receipts",{})
	if receipts.has(token):return false
	receipts[token]=true
	saved.__treasure_receipts=receipts
	saved.__treasure_inventory[id]=maxi(0,int(saved.__treasure_inventory.get(id,0))-1)
	save()
	return true

func equipment_cards() -> Array:
	if progression_snapshot.is_empty():return []
	var loadout:=equipment_rules.derive_loadout(progression_snapshot)
	if not bool(loadout.ok):return []
	var result: Array=[]
	for id in loadout.item_cards:
		result.append({"card":str(id),"key":str(id),"source":"equipped_stats","enabled":not bool(saved.get("__equipment_disabled",{}).get(str(id),false))})
	return result

static func clean_disabled_item_cards(value: Variant) -> Array[String]:
	var result: Array[String]=[]
	if not value is Array:return result
	for id in value:
		if id is String and id.length()<=128 and id not in result:result.append(id)
		if result.size()>=64:break
	return result

func disabled_item_cards() -> Array[String]:
	var result: Array[String]=[]
	for item in equipment_cards():
		if not bool(item.enabled) and str(item.card) not in result:result.append(str(item.card))
	return result

func toggle_equipment(key: String) -> void:
	var disabled: Dictionary=saved.get("__equipment_disabled",{})
	disabled[key]=not disabled.get(key,false)
	saved.__equipment_disabled=disabled
	save()

static func configure_extras(engine: BattleEngineV2, unit_id: StringName, value: Dictionary) -> Dictionary:
	var unit:=engine.state.unit_by_id(unit_id)
	if unit==null:return {"ok":false,"code":"unit_missing"}
	var rules:=EquipmentRules.new()
	var loaded:=rules.load_default()
	if not bool(loaded.ok):return loaded
	var snapshot: Variant=value.get("progression_snapshot",null)
	var loadout:=rules.derive_loadout(snapshot)
	if not bool(loadout.ok):return loadout
	var treasures: Variant=value.get("treasures",{})
	var tokens: Variant=value.get("treasure_tokens",{})
	if not treasures is Dictionary or not tokens is Dictionary:
		return {"ok":false,"code":"invalid_treasure_reservation"}
	var legal:=rules.legal_treasure_card_ids()
	var prepared_treasures: Array[Dictionary]=[]
	var seen_tokens: Dictionary={}
	for raw_id in treasures:
		var id:=str(raw_id)
		if id not in legal or typeof((treasures as Dictionary)[raw_id]) not in [TYPE_INT,TYPE_FLOAT]:
			return {"ok":false,"code":"invalid_treasure_card","card_id":id}
		var count:=int((treasures as Dictionary)[raw_id])
		var card_tokens: Variant=(tokens as Dictionary).get(id,null)
		if count<0 or not card_tokens is Array or (card_tokens as Array).size()!=count:
			return {"ok":false,"code":"invalid_treasure_reservation","card_id":id}
		var definition:=engine.content.card(StringName(id))
		if definition==null or not definition.treasure or definition.learned:
			return {"ok":false,"code":"invalid_treasure_card","card_id":id}
		for raw_token in card_tokens:
			var token:=str(raw_token)
			if token.is_empty() or seen_tokens.has(token):
				return {"ok":false,"code":"invalid_treasure_reservation","card_id":id}
			seen_tokens[token]=true
			prepared_treasures.append({"definition":definition,"token":token})
	var prepared_items: Array[CardDefinitionV2]=[]
	# Preferences may only remove cards granted by authenticated equipment.
	var excluded:=clean_disabled_item_cards(value.get("disabled_item_cards",[]))
	for raw_id in loadout.item_cards:
		if str(raw_id) in excluded:continue
		var definition:=engine.content.card(StringName(str(raw_id)))
		if definition==null or definition.learned or definition.treasure or &"item" not in definition.tags:
			return {"ok":false,"code":"invalid_item_card","card_id":str(raw_id)}
		prepared_items.append(definition)
	var applied:=rules.apply_to_unit(unit,snapshot)
	if not bool(applied.ok):return applied
	unit.deck.treasure_pile.clear()
	for card in unit.deck.draw_pile.duplicate():
		if (card as CardInstanceV2).equipment:unit.deck.draw_pile.erase(card)
	for card in unit.deck.hand.duplicate():
		if (card as CardInstanceV2).equipment:unit.deck.hand.erase(card)
	for reserved in prepared_treasures:
		var card:=engine._new_card(reserved.definition)
		card.inventory_token=str(reserved.token)
		unit.deck.treasure_pile.append(card)
	for definition in prepared_items:
		var card:=engine._new_card(definition)
		card.equipment=true
		unit.deck.draw_pile.append(card)
	# Include equipment in the initial hand lottery, rather than always burying it below the hand.
	unit.deck.draw_pile.append_array(unit.deck.hand);unit.deck.hand.clear()
	engine._shuffle_cards(unit.deck.draw_pile)
	engine._shuffle_cards(unit.deck.treasure_pile)
	unit.deck.draw_to_limit()
	return {"ok":true,"code":"ok","loadout":loadout,"treasure_count":prepared_treasures.size()}

func save() -> bool:
	saved.__island_school = school
	ai_count = clampi(ai_count,0,Allies.MAX_ALLIES)
	saved.__island_ai = ai_count
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:return false
	file.store_string(JSON.stringify(saved,"  "))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK
