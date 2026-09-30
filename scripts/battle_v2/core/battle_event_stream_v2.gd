class_name BattleEventStreamV2
extends RefCounted

var events: Array[BattleEventV2] = []
var subscribers: Array[Callable] = []
var _sequence: int = 0


func publish(type: StringName, round_index: int, payload: Dictionary = {}) -> BattleEventV2:
	_sequence += 1
	var event := BattleEventV2.new(type, _sequence, round_index, payload)
	events.append(event)
	for subscriber in subscribers:
		if subscriber.is_valid():
			subscriber.call(event)
	return event


func subscribe(callback: Callable) -> void:
	if not subscribers.has(callback):
		subscribers.append(callback)


func clear() -> void:
	events.clear()
	_sequence = 0


func as_dicts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in events:
		result.append(event.to_dict())
	return result
