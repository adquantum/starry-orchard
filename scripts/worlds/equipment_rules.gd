class_name EquipmentRules
extends RefCounted

const CATALOG_PATH := "res://resources/fusion_3d/weekend_equipment.json"
const ECONOMY_PATH := "res://resources/fusion_3d/weekend_treasure_economy.json"
const SCHOOLS := ["fire", "ice", "storm", "myth", "life", "death", "balance"]
const SLOTS := ["staff", "hat", "robe", "boots", "cape"]
const TIERS := ["t0", "t1", "t2", "t3", "t4", "t5"]
const BASE_META := &"weekend_equipment_base_spec"

var catalog: Dictionary = {}
var economy: Dictionary = {}
var items_by_id: Dictionary = {}
var errors: Array[String] = []


func load_default() -> Dictionary:
	errors.clear()
	catalog = _read_json(CATALOG_PATH)
	economy = _read_json(ECONOMY_PATH)
	items_by_id.clear()
	if catalog.is_empty() or economy.is_empty():
		return {"ok":false, "code":"catalog_unavailable", "errors":errors.duplicate()}
	if int(catalog.get("schema_version", 0)) != 1 or int(economy.get("schema_version", 0)) != 1:
		errors.append("unsupported weekend catalog schema")
	if str(catalog.get("catalog_version", "")) != str(economy.get("catalog_version", "")):
		errors.append("equipment/economy catalog_version mismatch")
	for value in catalog.get("items", []):
		if not value is Dictionary:
			errors.append("equipment item must be a Dictionary")
			continue
		var item := value as Dictionary
		var id := str(item.get("id", ""))
		if id.is_empty() or items_by_id.has(id):
			errors.append("invalid or duplicate equipment id: %s" % id)
			continue
		items_by_id[id] = item.duplicate(true)
	_validate_catalog()
	return {"ok":errors.is_empty(), "code":"ok" if errors.is_empty() else "invalid_catalog", "errors":errors.duplicate()}


func validate_snapshot(snapshot: Variant) -> Dictionary:
	if not snapshot is Dictionary:
		return _failure("invalid_progression_snapshot")
	var value := snapshot as Dictionary
	if int(value.get("schema_version", 0)) != 1:
		return _failure("invalid_progression_snapshot")
	var school := str(value.get("school", ""))
	if school not in SCHOOLS:
		return _failure("invalid_progression_snapshot")
	if not value.get("equipment_unlocks", null) is Array or not value.get("equipped_stats", null) is Dictionary:
		return _failure("invalid_progression_snapshot")
	var unlocks := value.equipment_unlocks as Array
	for unlock in unlocks:
		if not unlock is String and not unlock is StringName:
			return _failure("invalid_progression_snapshot")
	var equipped := value.equipped_stats as Dictionary
	for raw_slot in equipped:
		var slot := str(raw_slot)
		if slot not in SLOTS:
			return _failure("equipment_slot_mismatch", {"slot":slot})
		var id := str(equipped[raw_slot])
		if id.is_empty():
			continue
		var checked := _validate_item_for_snapshot(value, slot, id)
		if not bool(checked.ok):
			return checked
	return {"ok":true, "code":"ok", "school":school}


func available_equipment(snapshot: Variant) -> Dictionary:
	var checked := validate_snapshot(snapshot)
	if not bool(checked.ok):
		return checked
	var value := snapshot as Dictionary
	var school := str(value.school)
	var equipped := value.equipped_stats as Dictionary
	var result := {}
	for slot in SLOTS:
		result[slot] = []
	for item_value in items_by_id.values():
		var item := item_value as Dictionary
		if str(item.school) != school:
			continue
		var copy := item.duplicate(true)
		copy["unlocked"] = _is_unlocked(value, str(item.slot), str(item.tier))
		copy["equipped"] = str(equipped.get(str(item.slot), _default_item_id(school, str(item.slot)))) == str(item.id)
		(result[str(item.slot)] as Array).append(copy)
	for slot in SLOTS:
		(result[slot] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return TIERS.find(str(a.tier)) < TIERS.find(str(b.tier)))
	return {"ok":true, "code":"ok", "school":school, "slots":result, "catalog_version":str(catalog.get("catalog_version", ""))}


func derive_loadout(snapshot: Variant) -> Dictionary:
	var checked := validate_snapshot(snapshot)
	if not bool(checked.ok):
		return checked
	var value := snapshot as Dictionary
	var school := str(value.school)
	var equipped := value.equipped_stats as Dictionary
	var resolved := {}
	var selected: Array[Dictionary] = []
	var bonuses := _zero_bonuses()
	var item_cards: Array[String] = []
	for slot in SLOTS:
		var id := str(equipped.get(slot, ""))
		if id.is_empty():
			id = _default_item_id(school, slot)
		var item := (items_by_id.get(id, {}) as Dictionary).duplicate(true)
		if item.is_empty():
			return _failure("equipment_unknown", {"slot":slot, "item_id":id})
		resolved[slot] = id
		selected.append(item)
		var item_stats := item.get("stats", {}) as Dictionary
		for stat in bonuses:
			bonuses[stat] = float(bonuses[stat]) + float(item_stats.get(stat, 0.0))
		for card_id in item.get("item_cards", []):
			var normalized := str(card_id)
			if not normalized.is_empty() and normalized not in item_cards:
				item_cards.append(normalized)
	bonuses.max_hp = roundi(float(bonuses.max_hp))
	bonuses.accuracy_floor = clampf(float(bonuses.accuracy_floor), 0.0, 1.0)
	bonuses.extra_power_pip_chance = clampf(float(bonuses.extra_power_pip_chance), 0.0, 1.0)
	return {
		"ok":true, "code":"ok", "school":school, "equipped_stats":resolved,
		"items":selected, "bonuses":bonuses, "item_cards":item_cards,
		"catalog_version":str(catalog.get("catalog_version", ""))
	}


func build_battle_spec(base_spec: Dictionary, snapshot: Variant) -> Dictionary:
	var loadout := derive_loadout(snapshot)
	if not bool(loadout.ok):
		return loadout
	var result := base_spec.duplicate(true)
	var stats := (result.get("stats", {}) as Dictionary).duplicate(true)
	var bonuses := loadout.bonuses as Dictionary
	var school := str(loadout.school)
	result["max_hp"] = maxi(1, int(base_spec.get("max_hp", 1)) + int(bonuses.max_hp))
	result["hp"] = clampi(int(base_spec.get("hp", base_spec.get("max_hp", 1))) + int(bonuses.max_hp), 0, int(result.max_hp))
	stats["damage"] = _add_school_value(stats.get("damage", 0.0), school, float(bonuses.damage))
	stats["resistance"] = _add_global_value(stats.get("resistance", 0.0), float(bonuses.resistance))
	stats["accuracy_floor"] = _max_school_value(stats.get("accuracy_floor", {}), school, float(bonuses.accuracy_floor))
	stats["extra_power_pip_chance"] = _add_global_value(stats.get("extra_power_pip_chance", 0.0), float(bonuses.extra_power_pip_chance))
	result["stats"] = stats
	result["equipment"] = loadout
	result["ok"] = true
	result["code"] = "ok"
	return result


func apply_to_unit(unit: BattleUnitStateV2, snapshot: Variant) -> Dictionary:
	if unit == null:
		return _failure("unit_missing")
	var base_spec: Dictionary
	if unit.has_meta(BASE_META):
		base_spec = (unit.get_meta(BASE_META) as Dictionary).duplicate(true)
	else:
		base_spec = {"max_hp":unit.max_hp, "hp":unit.hp, "stats":unit.stats.duplicate(true)}
		unit.set_meta(BASE_META, base_spec.duplicate(true))
	var built := build_battle_spec(base_spec, snapshot)
	if not bool(built.ok):
		return built
	unit.max_hp = int(built.max_hp)
	unit.hp = int(built.hp)
	unit.stats = (built.stats as Dictionary).duplicate(true)
	return built.equipment as Dictionary


func display_summary(snapshot: Variant, overrides: Dictionary = {}) -> Dictionary:
	if not snapshot is Dictionary:
		return _failure("invalid_progression_snapshot")
	var preview := (snapshot as Dictionary).duplicate(true)
	var equipped := (preview.get("equipped_stats", {}) as Dictionary).duplicate(true)
	for slot in overrides:
		equipped[str(slot)] = str(overrides[slot])
	preview["equipped_stats"] = equipped
	var loadout := derive_loadout(preview)
	if not bool(loadout.ok):
		return loadout
	var bonuses := loadout.bonuses as Dictionary
	return {
		"ok":true, "code":"ok", "max_hp":int(bonuses.max_hp),
		"damage":float(bonuses.damage), "resistance":float(bonuses.resistance),
		"base_accuracy":float(bonuses.accuracy_floor) * 100.0,
		"extra_power_pip_chance":float(bonuses.extra_power_pip_chance) * 100.0,
		"item_cards":loadout.item_cards, "equipped_stats":loadout.equipped_stats
	}


func compare_item(snapshot: Variant, slot: String, item_id: String) -> Dictionary:
	var checked := validate_snapshot(snapshot)
	if not bool(checked.ok):
		return checked
	if slot not in SLOTS or not items_by_id.has(item_id):
		return _failure("equipment_unknown", {"slot":slot, "item_id":item_id})
	var item := items_by_id[item_id] as Dictionary
	var value := snapshot as Dictionary
	if str(item.school) != str(value.school):
		return _failure("equipment_school_mismatch", {"slot":slot, "item_id":item_id})
	if str(item.slot) != slot:
		return _failure("equipment_slot_mismatch", {"slot":slot, "item_id":item_id})
	var current := display_summary(value)
	var preview := value.duplicate(true)
	var unlocks := (preview.equipment_unlocks as Array).duplicate()
	var unlock_key := "%s:%s" % [slot, str(item.tier)]
	if str(item.tier) != "t0" and unlock_key not in unlocks:
		unlocks.append(unlock_key)
	preview.equipment_unlocks = unlocks
	var candidate := display_summary(preview, {slot:item_id})
	if not bool(current.ok) or not bool(candidate.ok):
		return candidate if not bool(candidate.ok) else current
	var delta := {}
	for key in ["max_hp", "damage", "resistance", "base_accuracy", "extra_power_pip_chance"]:
		delta[key] = float(candidate[key]) - float(current[key])
	return {"ok":true, "code":"ok", "unlocked":_is_unlocked(value, slot, str(item.tier)), "current":current, "candidate":candidate, "delta":delta}


func legal_treasure_card_ids() -> Array[String]:
	var result: Array[String] = []
	for id in economy.get("playable_cards", []):
		result.append(str(id))
	return result


func _validate_item_for_snapshot(snapshot: Dictionary, slot: String, item_id: String) -> Dictionary:
	if not items_by_id.has(item_id):
		return _failure("equipment_unknown", {"slot":slot, "item_id":item_id})
	var item := items_by_id[item_id] as Dictionary
	if str(item.get("school", "")) != str(snapshot.school):
		return _failure("equipment_school_mismatch", {"slot":slot, "item_id":item_id})
	if str(item.get("slot", "")) != slot:
		return _failure("equipment_slot_mismatch", {"slot":slot, "item_id":item_id})
	if not _is_unlocked(snapshot, slot, str(item.get("tier", ""))):
		return _failure("equipment_not_unlocked", {"slot":slot, "item_id":item_id})
	return {"ok":true, "code":"ok"}


func _is_unlocked(snapshot: Dictionary, slot: String, tier: String) -> bool:
	return tier == "t0" or "%s:%s" % [slot, tier] in (snapshot.get("equipment_unlocks", []) as Array)


func _default_item_id(school: String, slot: String) -> String:
	return "eq_%s_%s_t0" % [school, slot]


func _zero_bonuses() -> Dictionary:
	return {"max_hp":0, "damage":0.0, "resistance":0.0, "accuracy_floor":0.0, "extra_power_pip_chance":0.0}


func _add_school_value(base: Variant, school: String, bonus: float) -> Variant:
	if base is Dictionary:
		var values := (base as Dictionary).duplicate(true)
		values[school] = float(values.get(school, 0.0)) + bonus
		return values
	return {"*":float(base), school:bonus}


func _max_school_value(base: Variant, school: String, floor_value: float) -> Dictionary:
	var values := (base as Dictionary).duplicate(true) if base is Dictionary else {"*":float(base)}
	var inherited := float(values.get("*", 0.0))
	values[school] = maxf(float(values.get(school, 0.0)), floor_value - inherited)
	return values


func _add_global_value(base: Variant, bonus: float) -> Variant:
	if base is Dictionary:
		var values := (base as Dictionary).duplicate(true)
		values["*"] = float(values.get("*", 0.0)) + bonus
		return values
	return float(base) + bonus


func _validate_catalog() -> void:
	if items_by_id.size() != SCHOOLS.size() * SLOTS.size() * TIERS.size():
		errors.append("equipment catalog must contain exactly %d items" % (SCHOOLS.size() * SLOTS.size() * TIERS.size()))
	for school in SCHOOLS:
		for slot in SLOTS:
			for tier in TIERS:
				var expected := "eq_%s_%s_%s" % [school, slot, tier]
				if not items_by_id.has(expected):
					errors.append("missing equipment item: %s" % expected)
					continue
				var item := items_by_id[expected] as Dictionary
				for field in ["id", "school", "slot", "tier", "stats", "item_cards", "cosmetic_id"]:
					if not item.has(field):
						errors.append("%s missing field %s" % [expected, field])
				if str(item.get("school", "")) != school or str(item.get("slot", "")) != slot or str(item.get("tier", "")) != tier:
					errors.append("%s tuple does not match id" % expected)
	var legal := legal_treasure_card_ids()
	if legal.size() != 15 or "tc_empower" not in legal:
		errors.append("economy must whitelist the legacy fourteen cards plus empower")
	for school in SCHOOLS:
		var pool := (economy.get("school_pools", {}) as Dictionary).get(school, {}) as Dictionary
		if (pool.get("attack", []) as Array).is_empty() or (pool.get("buff", []) as Array).is_empty():
			errors.append("%s treasure pool requires attack and buff" % school)
		for id in pool.get("all", []):
			if str(id) not in legal:
				errors.append("%s pool contains non-currency card %s" % [school, str(id)])


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		errors.append("invalid JSON %s" % path)
		return {}
	return parsed as Dictionary


func _failure(code: String, extra: Dictionary = {}) -> Dictionary:
	var result := {"ok":false, "code":code}
	result.merge(extra, true)
	return result
