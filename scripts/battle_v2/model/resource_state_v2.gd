class_name ResourceStateV2
extends RefCounted

enum PipKind { NORMAL, POWER, SCHOOL }

const MAX_PIPS := 7
const MAX_SHADOW_PIPS := 2

var pips: Array[int] = []
var pip_schools: Array[StringName] = []
var shadow_pips: int = 0
var shadow_progress: int = 0
var archmastery_charge: int = 0
var charge_school: StringName = &"fire"
var next_charge_school: StringName = &"fire"


func clear_on_death() -> void:
	pips.clear()
	pip_schools.clear()
	shadow_pips = 0
	shadow_progress = 0
	archmastery_charge = 0


func append_pip(kind: PipKind, school_id: StringName = &"") -> bool:
	if pips.size() >= MAX_PIPS:
		return false
	pips.append(kind)
	pip_schools.append(school_id if kind == PipKind.SCHOOL else &"")
	sort_pips()
	return true


func sort_pips() -> void:
	# Paired stable sort: school at the inner/left end, normal at outer/right.
	for i in range(1, pips.size()):
		var j := i
		while j > 0 and pips[j] > pips[j - 1]:
			var kind := pips[j - 1]
			var school := pip_schools[j - 1]
			pips[j - 1] = pips[j]
			pip_schools[j - 1] = pip_schools[j]
			pips[j] = kind
			pip_schools[j] = school
			j -= 1


func snapshot() -> Dictionary:
	sort_pips()
	var kinds: Array[String] = []
	for kind in pips:
		kinds.append(["normal", "power", "school"][kind])
	return {
		"pips": kinds, "pip_schools": Array(pip_schools).map(func(value): return str(value)),
		"shadow_pips": shadow_pips, "shadow_progress": shadow_progress,
		"archmastery_charge": archmastery_charge,
		"charge_school": str(charge_school), "next_charge_school": str(next_charge_school)
	}
