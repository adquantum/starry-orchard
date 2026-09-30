extends RefCounted
## Shared entrance, roster and initial battle rules for host and dedicated server.
const Geo=preload("res://scripts/server/encounter_geometry.gd")
var site_index: int=-1
var expires: int=0
var teams: Dictionary={}

static func team_at(position: Vector3,site: Dictionary) -> int:
	return 0 if (position-Geo.point(site.center)).dot(Geo.point(site.get("red_axis",[0,0,1])))>=0 else 1

static func free_slot(owners: Dictionary,team: int) -> int:
	for slot in 4:
		if not owners.has(("P" if team==0 else "E")+str(slot)):return slot
	return -1

func scan(index: int,site: Dictionary,positions: Dictionary,profiles: Dictionary,now_ms: int) -> void:
	if site_index>=0 and site_index!=index:return
	for peer in positions:
		if teams.has(peer) or not profiles.has(peer) or not Geo.in_arena(positions[peer],site):continue
		var team:=team_at(positions[peer],site)
		if teams.values().count(team)>=4:continue
		if site_index<0:site_index=index;expires=now_ms+30000
		teams[peer]=team

func ready() -> bool:return teams.values().has(0) and teams.values().has(1)
func clear() -> void:site_index=-1;expires=0;teams.clear()

func describe(loadout,profiles: Dictionary,positions: Dictionary,appearances: Dictionary) -> Dictionary:
	var result: Dictionary={"pvp":true,"first_team":randi_range(0,1),"site":site_index,"party":[],"loadouts":[],"combatants":[],"origins":{},"appearances":appearances.duplicate(true)}
	var slots: Array=[0,0]
	for peer in teams:
		var team:=int(teams[peer]);var slot:=int(slots[team]);slots[team]+=1
		var id:=("P" if team==0 else "E")+str(slot)
		var profile: Dictionary=profiles[peer].duplicate(true)
		result.combatants.append({"id":id,"team":team,"slot":slot,"peer":peer,"profile":profile})
		result.origins[id]=positions[peer]
		if team==0:result.party.append(StringName(loadout.character(str(profile.school))));result.loadouts.append(profile)
	return result

static func configure(engine: BattleEngineV2,descriptor: Dictionary,loadout) -> void:
	engine.state.units.clear();engine.state.actions.clear();engine.state.round_index=0
	engine.state.pvp=true;engine.state.first_team=int(descriptor.first_team)
	for member in descriptor.combatants:
		var profile: Dictionary=member.profile
		var unit:=engine._create_unit(StringName(loadout.character(str(profile.school))),int(member.team),int(member.slot))
		engine.state.units.append(unit)
		engine.configure_deck(unit.id,profile.counts);loadout.configure_extras(engine,unit.id,profile)
		unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
		if unit.team!=engine.state.first_team:unit.resources.append_pip(ResourceStateV2.PipKind.NORMAL)
