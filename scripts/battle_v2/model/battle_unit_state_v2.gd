class_name BattleUnitStateV2
extends RefCounted

var id: StringName
var character_id: StringName
var name_key: StringName
var team: int
var slot: int
var school_id: StringName
var max_hp: int
var hp: int
var archmastery: int
var ai_profile_id: StringName
var alive: bool = true
var stats: Dictionary = {}
var resources := ResourceStateV2.new()
var deck := DeckStateV2.new()
var statuses: Array[StatusInstanceV2] = []
var planned_action: ActionIntentV2 = null
var action_slot_passed: bool = false


func setup(data: Dictionary, p_team: int, p_slot: int) -> void:
	id = StringName(str(data.get("battle_id", "%d_%d" % [p_team, p_slot])))
	character_id = StringName(str(data.get("character_id", id)))
	name_key = StringName(str(data.get("name_key", "UNIT_%s" % str(id).to_upper())))
	team = p_team
	slot = p_slot
	school_id = StringName(str(data.get("school", "fire")))
	max_hp = int(data.get("max_hp", 1000))
	hp = int(data.get("hp", max_hp))
	archmastery = int(data.get("archmastery", 50))
	ai_profile_id = StringName(str(data.get("ai_profile", "default")))
	stats = (data.get("stats", {}) as Dictionary).duplicate(true)
	alive = hp > 0
	resources.charge_school = StringName(str(data.get("charge_school", school_id)))
	resources.next_charge_school = resources.charge_school


func snapshot() -> Dictionary:
	return {
		"id": str(id), "team": team, "slot": slot, "school": str(school_id),
		"hp": hp, "max_hp": max_hp, "alive": alive,
		"stats": stats.duplicate(true),
		"resources": resources.snapshot(),
		"hand": deck.hand.map(func(card): return str((card as CardInstanceV2).card_id())),
		"draw_count": deck.draw_pile.size(), "treasure_count": deck.treasure_pile.size(),
		"statuses": statuses.map(func(status): return (status as StatusInstanceV2).to_dict())
	}


func school_stat(stat_id: StringName, school_id: StringName = &"*") -> float:
	var entry: Variant = stats.get(str(stat_id), stats.get(stat_id, 0.0))
	if entry is Dictionary:
		var values := entry as Dictionary
		return float(values.get("*", values.get(&"*", 0.0))) + float(values.get(str(school_id), values.get(school_id, 0.0)))
	return float(entry)


func set_school_stat(stat_id: StringName, school_id: StringName, value: float) -> void:
	var entry: Dictionary = (stats.get(str(stat_id), {}) as Dictionary).duplicate(true)
	entry[str(school_id)] = value
	stats[str(stat_id)] = entry
