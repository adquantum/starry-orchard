extends RefCounted
## Summarize actual resolved events; no simulated win-rate claims.
static func battle(engine: BattleEngineV2) -> Dictionary:
	var units: Dictionary={}
	for unit in engine.state.units:
		units[str(unit.id)]={"hp_start":engine.initial_hp.get(str(unit.id),unit.hp),"hp_end":unit.hp,"damage_taken":0,"healing":0,"overheal":0,"drain_healing":0,"health_spent":0,"misses":0,"passes":0,"reorganizes":0,"deaths":0,"casts":{},"relics":{}}
	var actions: Array=[]
	for event in engine.event_stream.events:
		var data: Dictionary=event.payload
		var id:=str(data.get("unit_id",data.get("caster_id",data.get("target_id",""))))
		match str(event.type):
			"DamageResolved":
				id=str(data.target_id)
				if units.has(id):units[id].damage_taken+=maxi(0,int(data.get("hp_before",0))-int(data.get("hp_after",0)))
			"HealingResolved":
				id=str(data.target_id)
				if units.has(id):
					units[id].healing+=int(data.final_amount);units[id].overheal+=int(data.get("overheal",0))
					if str(data.get("origin",""))=="drain":units[id].drain_healing+=int(data.final_amount)
			"HealthSpent":
				if units.has(id):units[id].health_spent+=int(data.amount)
			"SpellMissed":
				if units.has(id):units[id].misses+=1
			"UnitDied":
				if units.has(id):units[id].deaths+=1
			"ActionPassed":
				if units.has(id):
					units[id].passes+=1
					if str(data.get("origin",""))=="system_reorganize":units[id].reorganizes+=1
			"SpellResolved":
				if units.has(id) and bool(data.get("success",false)):
					var card:=str(data.card_id);units[id].casts[card]=int(units[id].casts.get(card,0))+1
			"RelicTriggered":
				id=str(data.get("owner_id",""))
				if units.has(id):
					var relic:=str(data.get("relic",""));units[id].relics[relic]=int(units[id].relics.get(relic,0))+1
		if event.type in [&"ActionPassed",&"ActionFizzled",&"SpellCastStarted",&"ResourceSpent",&"TrialOpening",&"TrialPassive"]:actions.append(event.to_dict())
	return {"units":units,"actions":actions,"elapsed_ms":Time.get_ticks_msec()-engine.started_msec}
