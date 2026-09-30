extends RefCounted
## Small, repeatable encounter using the production Battle V2 rules.
static func create(seed_value: int = 905) -> BattleSandboxControllerV2:
	var session := BattleSandboxControllerV2.new()
	session.engine = preload("res://scripts/duel_3d/duel_engine.gd").new()
	if not session.content.load_default():
		return null
	session.content.decks["duel_fire"] = {"fire_bolt":4, "fire_serpent":4, "bright_blade":3, "ember_trap":2, "burning_orbit":3, "life_bloom":2, "frost_ward":2}
	session.content.decks["duel_life"] = {"ice_shard":4, "life_bloom":4, "frost_ward":3, "bright_blade":3, "renewing_mist":2, "storm_lance":4}
	var scenario := {
		"teams": [["fire_student", "life_healer"], ["ember_skeleton", "frost_golem"]],
		"starting_resources": {"normal":2},
		"rules": {"school_pip_enabled":false, "shadow_pip_enabled":false,
			"deck_overrides":{"P0":"duel_fire", "P1":"duel_life", "E0":"duel_fire", "E1":"duel_life"}}
	}
	if not session.setup_scenario(scenario, seed_value):
		return null
	return session

