extends RefCounted
const StatusQuery = preload("res://scripts/battle_v2/core/status_query_v2.gd")

static func matches(actor: BattleUnitStateV2, target: BattleUnitStateV2, condition: Dictionary) -> bool:
	if condition.is_empty():
		return true
	if condition.has("all"):
		for child in condition["all"]:
			if not child is Dictionary or not matches(actor, target, child):
				return false
		return true
	if condition.has("any"):
		for child in condition["any"]:
			if child is Dictionary and matches(actor, target, child):
				return true
		return false
	if condition.has("not"):
		return condition["not"] is Dictionary and not matches(actor, target, condition["not"])
	var subject_name := str(condition.get("subject", "target"))
	if subject_name not in ["caster", "target"]:
		return false
	var subject := actor if subject_name == "caster" else target
	if subject == null:
		return false
	match str(condition.get("kind", "")):
		"has_status", "status_count":
			var count := StatusQuery.select(subject, StatusQuery.criteria_from(condition)).size()
			return count >= int(condition.get("count", 1)) and (not condition.has("max_count") or count <= int(condition.max_count))
		"hp_below":
			return float(subject.hp) / maxf(float(subject.max_hp), 1.0) <= float(condition.get("ratio", .5))
		"pip_at_least":
			return subject.resources.pips.size() >= int(condition.get("count", 1))
		"target_alive":
			return subject.alive
	return false
