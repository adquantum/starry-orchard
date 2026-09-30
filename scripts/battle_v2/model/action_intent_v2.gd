class_name ActionIntentV2
extends RefCounted

var actor_id: StringName
var card_instance_id: int = -1
var card_definition_id: StringName = &""
var target_ids: Array[StringName] = []
var pass_action: bool = false
var cancelled: bool = false


static func cast(actor: StringName, card_id: int, targets: Array[StringName]) -> ActionIntentV2:
	var result := ActionIntentV2.new()
	result.actor_id = actor
	result.card_instance_id = card_id
	result.target_ids = targets.duplicate()
	return result


static func pass_turn(actor: StringName) -> ActionIntentV2:
	var result := ActionIntentV2.new()
	result.actor_id = actor
	result.pass_action = true
	return result
