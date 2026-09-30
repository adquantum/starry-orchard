extends RefCounted
## Shared locations and protocol names; only the dedicated server grants access.
const TUTORIAL := "star_orchard_world1_v2"
const MAIN := "star_orchard_main"
const FROST := "frost"
const LESSONS := ["SO1_T01", "SO1_T02", "SO1_T03", "SO1_T04", "SO1_T05"]
const WEST_ENTRY := Vector3(221.6, 228.0, -343.0)
const CRYSTAL := Vector3(378.0, 281.0, -629.8)
const SHIP := Vector3(-445.45, 3.12, -658.91)
const MAIN_ENTRY := Vector3(1045.0, 242.1952, 146.7728)

static func completed(record: Dictionary) -> bool:
	for id in LESSONS:
		var receipt: Dictionary = record.get("victories", {}).get(id, {})
		if not bool(receipt.get("committed", false)) or int(receipt.get("winner", -1)) != 0:return false
	return true

static func admitted(record: Dictionary) -> bool:
	return completed(record) or bool(record.get("tutorial_skipped", false))

static func near(at: Vector3, target: Vector3, radius: float = 16.0) -> bool:
	return Vector2(at.x-target.x, at.z-target.z).length() <= radius and absf(at.y-target.y) <= 22.0
