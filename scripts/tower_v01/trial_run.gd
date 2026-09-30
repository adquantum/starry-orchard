extends RefCounted
const Rules = preload("res://scripts/tower_v01/trial_rules.gd")
const Store = preload("res://scripts/tower_v01/trial_store.gd")
const Relics = preload("res://scripts/tower_v01/relic_catalog.gd")
static var RELICS: Dictionary = Relics.descriptions()
const ALLOWED = Rules.ALLOWED
var run_id := ""
var seed_value := 0
var school := "fire"
var secondary := ""
var school_owner := ""
var node_index := 0
var state := "SAFE"
var deck: Array = []
var relics: Array = ["ready_seed"]
var hp: Array = []
var dew := 30
var offer: Array = []
var offer_reasons: Dictionary = {}
var relic_offer: Array = []
var shop_offer: Array = []
var ledger: Dictionary = {}
var sources: Dictionary = {}
var reward_rng := RandomNumberGenerator.new()
var shop_rng := RandomNumberGenerator.new()
var next_instance := 1
var seed_rules := Rules.VERSION
var teammate: RefCounted
var player_slot := 0
var party_size := 1
var routes: Dictionary = {}
var progress: Dictionary = {}
var revision := 0
var failure_reason := ""
var history: Array = []
var study_mode := ""
var new_study_instance := -1

func initialize(main_school: String, seed_number: int) -> bool:
	if main_school not in Rules.SCHOOLS:return false
	school=main_school;school_owner=main_school;seed_value=seed_number
	run_id="%s-%d-%d" % [school,seed_number,Time.get_ticks_usec()]
	reward_rng.seed=seed_number ^ 0x524557;shop_rng.seed=seed_number ^ 0x53484F
	deck=[];relics=["ready_seed"];hp=[];offer=[];relic_offer=[];shop_offer=[];offer_reasons={};ledger={};progress={};routes={};history=[]
	node_index=0;state="SAFE";dew=30;next_instance=1;revision=0;secondary="";study_mode="";failure_reason="";new_study_instance=-1
	var catalog: Variant=JSON.parse_string(FileAccess.get_file_as_string(ContentRegistryV2.SPELL_CATALOG_PATH))
	if not catalog is Dictionary:return false
	sources={}
	for card in catalog.cards:
		var id := str(card.id)
		if bool(catalog.get("_audit",{}).get("cards",{}).get(id,{}).get("hidden",false)) or id=="myt_015":continue
		if Rules.supported(card.effects):sources[id]=card.duplicate(true)
	for id in Rules.STARTERS[school]:
		if not sources.has(id):return false
		for count in int(Rules.STARTERS[school][id]):add_card(id)
	return deck.size()==12

func main_max_hp() -> int:
	return int({"fire":1710,"ice":2160,"storm":1332,"myth":1836,"life":2124,"death":1980,"balance":1944}.get(school,1800))

func current_hp() -> int:return int(hp[0]) if not hp.is_empty() else main_max_hp()
func recover(ratio: float) -> void:hp=[mini(main_max_hp(),current_hp()+roundi(main_max_hp()*ratio))]
func encounter() -> Dictionary:return preload("res://scripts/tower_v01/encounter_catalog.gd").get_encounter(node_index,str(routes.get(str(node_index),"normal"))=="elite",party_size)
func record_for(id: int) -> Dictionary:
	for record in deck:
		if int(record.instance_id)==id:return record
	return {}
func count_card(id: String) -> int:return deck.filter(func(record):return record.base_spell_id==id).size()
func add_card(id: String) -> void:
	deck.append({"instance_id":next_instance,"base_spell_id":id,"level":0,"upgrade_path":"","cost_down":0});next_instance+=1

func definition(instance: Dictionary, with_relics := true) -> CardDefinitionV2:
	var data: Dictionary=sources[instance.base_spell_id].duplicate(true)
	var path := str(instance.get("upgrade_path","power"))
	var bonus := float(instance.get("level",0))*0.1 if path in ["","power"] else 0.0
	for effect in data.effects:
		var type := str(effect.type)
		var field := "power" if type in ["damage","drain","heal"] else "damage_per_tick" if type=="apply_dot" else "healing_per_tick" if type=="apply_hot" else ""
		if not field.is_empty() and effect.has(field):
			var extra := 0.25 if with_relics and type=="apply_dot" and "ember_wick" in relics else 0.0
			effect[field]=roundi(float(effect[field])*(1.0+minf(0.6,bonus+extra)))
		if path=="ward" and str(data.id) in Rules.WARD_UPGRADES and effect.has("value"):
			effect.value=signf(float(effect.value))*minf(60.0,absf(float(effect.value))+5.0*int(instance.level))
	var accuracy := clampf(float(data.accuracy)+Rules.PLAYER_ACCURACY,0,1)
	if path=="focus" and accuracy<0.95:accuracy=minf(0.95,accuracy+float(instance.level)*0.08)
	data.accuracy=accuracy
	return CardDefinitionV2.from_dict(data)

func can_upgrade(record: Dictionary, path: String) -> bool:
	if record.is_empty() or int(record.level)>=2:return false
	if int(record.level)>0 and str(record.get("upgrade_path","power"))!=path:return false
	var data: Dictionary=sources[record.base_spell_id]
	match path:
		"power":return data.effects.any(func(e):return str(e.type) in ["damage","drain","heal","apply_dot","apply_hot"])
		"focus":return definition(record,false).accuracy<0.94999
		"ward":return str(data.id) in Rules.WARD_UPGRADES and data.effects.size()==1 and absf(float(data.effects[0].get("value",0)))+5*int(record.level)<60
	return false

func snapshot() -> Dictionary:
	return {"rules":seed_rules,"hash":FileAccess.get_sha256(ContentRegistryV2.SPELL_CATALOG_PATH),"config_hash":Rules.config_hash(),"run_id":run_id,"seed":seed_value,"school":school,"school_owner":school_owner,"secondary":secondary,"node":node_index,"state":state,"deck":deck.duplicate(true),"relics":relics.duplicate(),"hp":hp.duplicate(),"dew":dew,"offer":offer.duplicate(),"offer_reasons":offer_reasons.duplicate(),"relic_offer":relic_offer.duplicate(),"shop_offer":shop_offer.duplicate(),"ledger":ledger.duplicate(true),"rng":str(reward_rng.state),"shop_rng":str(shop_rng.state),"next_instance":next_instance,"routes":routes.duplicate(),"party_size":party_size,"player_slot":player_slot,"progress":progress.duplicate(true),"revision":revision,"study_mode":study_mode,"new_study_instance":new_study_instance,"failure_reason":failure_reason,"history":history.duplicate(true)}

func save(path: String) -> bool:return Store.write(path,snapshot())
func restore(path: String, expected_school: String) -> bool:
	if not FileAccess.file_exists(path):return false
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or str(data.get("school_owner",data.get("school","")))!=expected_school:return false
	if not import_snapshot(data,str(data.get("school",""))):return false
	if state=="ABANDONED":return false
	if state=="BATTLE":state="FAILED";failure_reason="战斗中断；本场未结算"
	return true

func import_snapshot(data: Dictionary, expected_school: String) -> bool:
	if data.get("rules")!=seed_rules or data.get("hash")!=FileAccess.get_sha256(ContentRegistryV2.SPELL_CATALOG_PATH) or data.get("config_hash")!=Rules.config_hash() or data.get("school")!=expected_school:return false
	for field in ["deck","relics","hp","offer","relic_offer","shop_offer","history"]:
		if not data.get(field) is Array:return false
	for field in ["ledger","routes","progress","offer_reasons"]:
		if not data.get(field) is Dictionary:return false
	for field in ["run_id","seed","dew","next_instance","rng","shop_rng"]:
		if not data.has(field):return false
	if not data.get("deck") is Array or int(data.get("node",-1)) not in range(9):return false
	if str(data.get("state","")) not in ["SAFE","BATTLE","REWARD","RELIC","STUDY","STUDY_CARD","STUDY_REMOVE","SHOP","REST","REPLACE","NODE_COMPLETE","SUCCESS","FAILED","ABANDONED"]:return false
	if not initialize(expected_school,int(data.get("seed",0))):return false
	var ids: Dictionary={};var counts: Dictionary={}
	for record in data.deck:
		if not record is Dictionary or not sources.has(str(record.get("base_spell_id",""))):return false
		var id := int(record.get("instance_id",0))
		if id<=0 or ids.has(id) or int(record.get("level",0)) not in range(3):return false
		if str(record.get("upgrade_path","")) not in ["","power","focus","ward"]:return false
		ids[id]=true;counts[record.base_spell_id]=int(counts.get(record.base_spell_id,0))+1
		if counts[record.base_spell_id]>4:return false
	if data.deck.size()<Rules.MIN_DECK or data.deck.size()>Rules.MAX_DECK:return false
	for id in data.get("relics",[]):
		if not Relics.DATA.has(id):return false
	for ids_value in [data.offer,data.shop_offer]:
		for id in ids_value:
			if not sources.has(str(id)) or str(id) not in Rules.POOL_IDS:return false
	for id in data.relic_offer:
		if not Relics.DATA.has(str(id)):return false
	if str(data.get("secondary","")) not in Rules.SCHOOLS+[""] or int(data.get("party_size",1)) not in [1,2] or int(data.get("player_slot",0)) not in [0,1]:return false
	run_id=str(data.run_id);node_index=int(data.node);state=str(data.state);school_owner=str(data.get("school_owner",school))
	deck=data.deck.duplicate(true);relics=data.relics.duplicate();hp=data.hp.duplicate();dew=int(data.dew)
	offer=data.offer.duplicate();offer_reasons=data.get("offer_reasons",{}).duplicate();ledger=data.ledger.duplicate(true)
	routes=data.get("routes",{}).duplicate();party_size=int(data.get("party_size",1));player_slot=int(data.get("player_slot",0))
	relic_offer=data.get("relic_offer",[]).duplicate();secondary=str(data.get("secondary",""));shop_offer=data.get("shop_offer",[]).duplicate()
	next_instance=int(data.next_instance);reward_rng.state=int(str(data.rng));shop_rng.state=int(str(data.shop_rng))
	progress=data.get("progress",{}).duplicate(true);revision=int(data.get("revision",0));study_mode=str(data.get("study_mode",""));new_study_instance=int(data.get("new_study_instance",-1))
	failure_reason=str(data.get("failure_reason",""));history=data.get("history",[]).duplicate(true)
	return true

func cost_cap() -> int:return 4 if node_index<=2 else 5 if node_index<=5 else 7
func candidates(only_school := "", cap := -1) -> Array:
	var result: Array=[]
	for id in Rules.POOL_IDS:
		if not sources.has(id):continue
		var card: Dictionary=sources[id]
		if str(card.pip_cost)=="X" or int(card.pip_cost)>(cost_cap() if cap<0 else cap):continue
		if str(card.school) not in ([only_school] if not only_school.is_empty() else [school,secondary]):continue
		if count_card(id)>=4:continue
		result.append(id)
	result.sort();return result

func build_tags() -> Dictionary:
	var result: Dictionary={}
	for record in deck:
		for tag in Rules.tags(sources[record.base_spell_id]):result[tag]=int(result.get(tag,0))+1
	return result

func _pick(candidates_value: Array, rng_value: RandomNumberGenerator) -> String:
	return "" if candidates_value.is_empty() else str(candidates_value[rng_value.randi_range(0,candidates_value.size()-1)])

func _generate_offer(only_school: String, rng_value: RandomNumberGenerator, cap := -1) -> Dictionary:
	var available := candidates(only_school,cap)
	var selected: Array=[];var reasons: Dictionary={};var existing := build_tags()
	for slot in 3:
		if available.is_empty():break
		var best: Array=[];var best_score := -1000
		for id in available:
			var card: Dictionary=sources[id];var tags := Rules.tags(card);var score := 0
			if slot==0:
				if card.school==school:score+=4
				for tag in Rules.SCHOOL_TAGS[school]:
					if tag in tags:score+=2
				if "detonate" in tags and int(existing.get("apply_dot",0))>0:score+=2
			elif slot==1:
				if int(existing.get("attack",0))<7 and "attack" in tags:score+=6
				if not existing.has("aoe") and "aoe" in tags:score+=4
				if not existing.has("shield") and "shield" in tags:score+=4
				if node_index>=3 and "remove_enemy_buff" in tags:score+=2
				if card.school==school:score+=1
			else:
				if not secondary.is_empty() and card.school==secondary:score+=4
				if count_card(id)==0:score+=2
			if state=="STUDY_CARD" and slot==0 and int(card.pip_cost) in [1,2,3]:score+=20
			if score>best_score:best_score=score;best=[id]
			elif score==best_score:best.append(id)
		var chosen := _pick(best,rng_value)
		selected.append(chosen);available.erase(chosen)
		reasons[chosen]=["主轴：本系特色与已有组件","补缺：增加攻击或当前缺少的工具","变化：另一方向或已研习副系"][slot]
	return {"cards":selected,"reasons":reasons}

func make_offer(only_school := "") -> void:
	if not offer.is_empty():return
	var generated := _generate_offer(only_school,reward_rng)
	offer=generated.cards;offer_reasons=generated.reasons

func prepare_shop() -> void:
	if progress.get("shop_generated",false):return
	shop_offer=_generate_offer("",shop_rng).cards;progress.shop_generated=true

func make_relic_offer() -> void:
	if not relic_offer.is_empty():return
	var available: Array=[]
	for id in Relics.DATA:
		if id not in relics and Relics.eligible(id,self):available.append(id)
	available.sort()
	var preferred: Array=available.filter(func(id):return id in Rules.SCHOOL_RELICS[school])
	var pick := _pick(preferred,reward_rng)
	if not pick.is_empty():relic_offer.append(pick);available.erase(pick)
	var common: Array=available.filter(func(id):return id in ["steady_pips","travel_supply","charged_core","swift_flask"])
	pick=_pick(common,reward_rng)
	if not pick.is_empty():relic_offer.append(pick);available.erase(pick)
	while not available.is_empty() and relic_offer.size()<3:
		pick=_pick(available,reward_rng);relic_offer.append(pick);available.erase(pick)

func _take_card(id: String, replace_id := -1) -> bool:
	if not sources.has(id):return false
	var removed := record_for(replace_id)
	if replace_id>=0 and removed.is_empty():return false
	if removed.is_empty() and deck.size()>=Rules.MAX_DECK:return false
	if count_card(id)-(1 if not removed.is_empty() and removed.base_spell_id==id else 0)>=4:return false
	if not removed.is_empty():deck.erase(removed)
	add_card(id);return true

func choose_card(id: String, replace_id := -1) -> bool:
	if state not in ["REWARD","STUDY_CARD","REPLACE"] or id not in offer:return false
	if state=="REPLACE" and replace_id<0:return false
	if not _take_card(id,replace_id):return false
	new_study_instance=next_instance-1
	_finish_cards();return true

func _finish_cards() -> void:
	offer.clear();offer_reasons.clear()
	if state=="STUDY_CARD":
		progress.study_done=true;state="STUDY_REMOVE" if study_mode=="primary" else "REST"
	elif state=="REPLACE":progress.rest_done=true;state="NODE_COMPLETE"
	elif node_index in [0,3,6]:state="RELIC";make_relic_offer()
	else:state="NODE_COMPLETE"

func choose_relic(id: String) -> bool:
	if state!="RELIC" or id not in relic_offer or id in relics:return false
	relics.append(id);relic_offer.clear();state="NODE_COMPLETE";return true

func study(value: String) -> bool:
	if state!="STUDY" or node_index!=2 or progress.get("study_done",false):return false
	if value!="primary" and value not in Rules.SCHOOLS:return false
	if value==school:return false
	study_mode=value
	if value!="primary":secondary=value
	state="STUDY_CARD";offer.clear();make_offer(school if value=="primary" else value);return true

func buy(kind: String, arg := "", replace_id := -1) -> bool:
	if state!="SHOP" or node_index!=5:return false
	var key := "shop:"+kind+":"+arg
	if ledger.has(key):return false
	var price := 25 if kind=="heal" else 35 if kind=="card" else 30 if kind=="remove" else 0
	if price==0 or dew<price:return false
	match kind:
		"heal":
			if current_hp()>=main_max_hp():return false
			recover(0.35)
		"card":
			if arg not in shop_offer or not _take_card(arg,replace_id):return false
		"remove":
			var record := record_for(int(arg))
			if record.is_empty() or deck.size()<=Rules.MIN_DECK or int(progress.get("shop_removes",0))>=2:return false
			deck.erase(record);progress.shop_removes=int(progress.get("shop_removes",0))+1
	dew-=price;ledger[key]=true;return true

func open_node() -> void:
	progress={};offer.clear();offer_reasons.clear();relic_offer.clear();shop_offer.clear()
	state="STUDY" if node_index==2 else "SHOP" if node_index==5 else "REST" if node_index==7 else "SAFE"
	if state=="SHOP":prepare_shop()

func command(kind: String, args: Dictionary, operation_id: String, expected_revision := -1) -> bool:
	var key := "op:"+operation_id
	var signature := JSON.stringify({"kind":kind,"args":args})
	if operation_id.is_empty():return false
	if ledger.has(key):return str(ledger[key])==signature
	if expected_revision>=0 and expected_revision!=revision:return false
	if not _apply(kind,args):return false
	ledger[key]=signature;revision+=1
	history.append({"node":node_index,"revision":revision,"kind":kind,"args":args.duplicate(true),"hp":current_hp(),"dew":dew,"cards":deck.size()})
	return true

func _apply(kind: String, args: Dictionary) -> bool:
	match kind:
		"card":return choose_card(str(args.get("id","")),int(args.get("replace",-1)))
		"skip":
			if state not in ["REWARD","STUDY_CARD","RELIC","STUDY_REMOVE"]:return false
			if state=="RELIC":relic_offer.clear();state="NODE_COMPLETE"
			elif state=="STUDY_REMOVE":state="REST"
			else:_finish_cards()
			return true
		"relic":return choose_relic(str(args.get("id","")))
		"study":return study(str(args.get("school","")))
		"skip_study":
			if state!="STUDY":return false
			progress.study_done=true;state="REST";return true
		"study_remove":
			if state!="STUDY_REMOVE" or deck.size()<=Rules.MIN_DECK:return false
			var record := record_for(int(args.get("instance",-1)))
			if record.is_empty() or int(record.instance_id)==new_study_instance:return false
			deck.erase(record);state="REST";return true
		"buy":return buy(str(args.get("kind","")),str(args.get("id","")),int(args.get("replace",-1)))
		"shop_done":
			if state!="SHOP":return false
			progress.shop_done=true;state="REST";return true
		"heal":
			if state!="REST" or node_index not in [2,5,7]:return false
			recover(0.3);progress.rest_done=true;state="NODE_COMPLETE";return true
		"upgrade":
			if state!="REST" or node_index not in [2,5,7]:return false
			var record := record_for(int(args.get("instance",-1)));var path := str(args.get("path","power"))
			if not can_upgrade(record,path):return false
			record.upgrade_path=path;record.level=int(record.level)+1;progress.rest_done=true;state="NODE_COMPLETE";return true
		"replace_begin":
			if state!="REST" or node_index!=7:return false
			state="REPLACE";make_offer();return true
		"replace_cancel":
			if state!="REPLACE":return false
			state="REST";return true # frozen offer survives returning to the same choice
		"route":
			if state!="SAFE" or node_index not in [1,4] or args.get("route") not in ["normal","elite"]:return false
			routes[str(node_index)]=str(args.route);return true
		"advance":
			if state!="NODE_COMPLETE" or node_index>=8:return false
			node_index+=1;open_node();return true
		"battle":
			if state!="SAFE" or node_index not in [0,1,3,4,6,8] or ledger.has("%s:%d:result" % [run_id,node_index]):return false
			state="BATTLE";return true
		"abandon":
			if state in ["SUCCESS","FAILED","ABANDONED"]:return false
			state="ABANDONED";return true
	return false

func settle(engine: BattleEngineV2) -> bool:
	if engine.get("trial")!=self and (engine.get("trial")==null or engine.trial.teammate!=self):return false
	if engine.trial.run_id!=run_id or engine.trial.node_index!=node_index:return false
	if state!="BATTLE" or engine.state.phase!=BattleStateV2.Phase.FINISHED:return false
	var key := "%s:%d:result" % [run_id,node_index]
	if ledger.has(key):return false
	var won := engine.state.winner_team==0
	ledger[key]={"won":won,"rounds":engine.state.round_index,"formal_items":0}
	for unit in engine.state.team_units(0):
		if unit.slot!=player_slot:continue
		var value: int=unit.hp if unit.alive else roundi(unit.max_hp*0.2)
		if won and "travel_supply" in relics:value=mini(unit.max_hp,value+roundi(unit.max_hp*0.1))
		hp=[value]
	if not won:state="FAILED";failure_reason="未能突破" if engine.state.round_index>=50 else "队伍倒下"
	elif node_index==8:state="SUCCESS"
	else:dew+=int(encounter().dew);state="REWARD";make_offer()
	revision+=1
	history.append({"kind":"battle_result","node":node_index,"won":won,"rounds":engine.state.round_index,"hp":current_hp(),"dew":dew,"metrics":preload("res://scripts/tower_v01/trial_telemetry.gd").battle(engine)})
	return true
