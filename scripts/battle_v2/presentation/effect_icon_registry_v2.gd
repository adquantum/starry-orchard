class_name EffectIconRegistryV2
extends RefCounted

const ICONS := {
	"healing_blade":{"label":"增疗", "tooltip":"增疗；强化持有者下一次施放的治疗，随后消耗，不限系别。"},
	"infection":{"label":"减疗", "tooltip":"减疗；削弱持有者下一次施放的治疗，随后消耗，不限系别。"},
	"summon":{"label":"Summon", "tooltip":"Summons the specified creature."},
	"damage":{"label":"Damage", "tooltip":"Deals direct damage."},
	"heal":{"label":"Healing", "tooltip":"Restores health."},
	"blade":{"label":"Blade", "tooltip":"Modifies the next matching spell cast by this unit."},
	"weakness":{"label":"Weakness", "tooltip":"Reduces the next matching spell cast by this unit."},
	"shield":{"label":"Shield", "tooltip":"Reduces the next matching damage event received."},
	"trap":{"label":"Trap", "tooltip":"Increases the next matching damage event received."},
	"dot":{"label":"Damage Over Time", "tooltip":"Deals damage once per tick."},
	"hot":{"label":"Healing Over Time", "tooltip":"Restores health once per tick."},
	"delay_damage":{"label":"Delayed Damage", "tooltip":"Deals its damage after the countdown ends."},
	"revive":{"label":"Revive", "tooltip":"Returns a defeated ally to battle."},
	"drain":{"label":"Health Drain", "tooltip":"Deals damage and heals the caster from damage actually dealt."},
	"prism":{"label":"Prism", "tooltip":"Converts the next matching damage event to another school."},
	"absorb":{"label":"Absorb", "tooltip":"Consumes a fixed amount of incoming damage."},
	"stun":{"label":"Stun", "tooltip":"Skips the target's next action."},
	"dispel":{"label":"Dispel", "tooltip":"Cancels the target's next matching school spell."},
	"aura":{"label":"Aura", "tooltip":"Temporarily modifies the unit's combat statistics."},
	"global":{"label":"Global", "tooltip":"Modifies combat while the battlefield effect remains active."},
	"steal_status":{"label":"Steal", "tooltip":"Transfers a matching status from the target to the caster."},
	"detonate":{"label":"Detonate", "tooltip":"Resolves the remaining damage of a DOT immediately."},
	"resource":{"label":"Pip Manipulation", "tooltip":"Adds, removes, or converts combat resources."},
	"conditional":{"label":"Conditional", "tooltip":"Selects an effect branch from the current battle state."},
	"pip":{"label":"Main Pip", "tooltip":"One slot in the shared seven Main Pip row."},
	"power_pip":{"label":"Power Pip", "tooltip":"A Main Pip with increased payment value."},
	"school_pip":{"label":"School Pip", "tooltip":"A Main Pip aligned to a specific school."},
	"shadow_pip":{"label":"Shadow Pip", "tooltip":"An independent Shadow resource."},
	"target_self":{"label":"Self", "tooltip":"This spell targets its caster."},
	"target_ally":{"label":"Ally", "tooltip":"This spell targets one living ally."},
	"target_enemy":{"label":"Enemy", "tooltip":"This spell targets one living enemy."},
	"target_dead_ally":{"label":"Defeated Ally", "tooltip":"This spell targets one defeated ally."},
	"target_all_allies":{"label":"All Allies", "tooltip":"This spell affects all allies."},
	"target_all_enemies":{"label":"All Enemies", "tooltip":"This spell affects all enemies."},
	"target_global":{"label":"Battle Circle", "tooltip":"This spell affects the entire battle circle."},
	"draw":{"label":"Draw", "tooltip":"Draws one or more cards."},
	"discard":{"label":"Discard", "tooltip":"Moves a card out of the hand."},
	"cleanse":{"label":"Cleanse", "tooltip":"Removes a negative effect."},
	"remove":{"label":"Remove", "tooltip":"Removes the specified object or effect."},
	"copy":{"label":"Copy", "tooltip":"Creates a copy of the specified object."},
	"convert":{"label":"Convert", "tooltip":"Changes one type into another."},
	"duration":{"label":"Duration", "tooltip":"Number of rounds or ticks remaining."},
	"trigger":{"label":"Trigger", "tooltip":"Activates when its condition is met."},
	"category_charm":{"label":"Charm", "tooltip":"Filters charm statuses; polarity selects helpful or harmful charms."},
	"category_ward":{"label":"Ward", "tooltip":"Filters ward statuses; polarity selects helpful or harmful wards."},
}

const SCHOOLS := [&"fire", &"ice", &"storm", &"myth", &"life", &"death", &"balance", &"universal"]
const KEYWORDS := [&"detonate", &"echo", &"consume", &"convert", &"pierce", &"cleanse", &"empower", &"delay", &"repeat"]


static func entry(icon_id: StringName) -> Dictionary:
	var key := str(icon_id)
	if key.begins_with("school_"):
		var school := key.trim_prefix("school_")
		return {"label":"%s School" % school.capitalize(), "tooltip":"This effect uses the %s school." % school.capitalize()}
	if key.begins_with("keyword_"):
		var keyword := key.trim_prefix("keyword_")
		return {"label":keyword.capitalize(), "tooltip":"Keyword: %s. Full rule text is supplied by the content definition." % keyword.capitalize()}
	return (ICONS.get(key, {"label":key.capitalize(), "tooltip":"Effect glyph."}) as Dictionary).duplicate()


static func effect_icon(effect: Dictionary) -> StringName:
	var type := StringName(str(effect.get("type", "")))
	if type == &"apply_status":
		return StringName(str(effect.get("status", "status")))
	return {
		&"apply_dot":&"dot", &"apply_hot":&"hot", &"delay_damage":&"delay_damage",
		&"absorb":&"shield",
		&"apply_aura":&"aura", &"apply_global":&"global", &"remove_status":&"remove",
		&"consume_status":&"remove", &"modify_dot":&"duration", &"convert_status":&"convert", &"transfer_dot":&"convert"
	}.get(type, type)


static func target_icon(target_type: StringName) -> StringName:
	var normalized := StringName(str({
		&"caster":&"self", &"selected":&"enemy", &"primary":&"enemy",
		&"selected_enemy":&"enemy", &"selected_ally":&"ally",
		&"random_enemy":&"enemy", &"random_ally":&"ally"
	}.get(target_type, target_type)))
	return StringName("target_%s" % str(normalized))

