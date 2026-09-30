class_name CardInstanceV2
extends RefCounted

var instance_id: int
var definition: CardDefinitionV2
var treasure_locked: bool = false
var temporary: bool = false
var inventory_token: String = ""
var equipment: bool = false


func _init(p_id: int = 0, p_definition: CardDefinitionV2 = null) -> void:
	instance_id = p_id
	definition = p_definition


func card_id() -> StringName:
	return definition.id if definition != null else &""
