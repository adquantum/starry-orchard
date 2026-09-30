extends Node3D
const ArtKit=preload("res://scripts/fusion_3d/world_one_art_kit.gd")
const Model=preload("res://scripts/fusion_3d/world_one_model.gd")
var town: Node3D
var chapter: Node
var zone_names := {"greenhouse":"废弃温室","channel":"地下水道","ruins":"旧城遗址","forest":"迷踪林道","camp":"无缚者营地","mine":"废弃矿道","graveyard":"记忆墓园","loom":"星仪织机"}
var centers: Dictionary={}
var nodes: Dictionary={}
var gates: Dictionary={}
var visuals: Dictionary={}
var restored_lights: Dictionary={}
func configure(value: Node3D, controller: Node) -> void:
	town=value;chapter=controller
	for region in town.world_layout.regions:centers[region.id]=town.layout_vector(region.center)
	centers.campus=Vector3.ZERO
	var index:=0
	for id in zone_names:
		centers[id]=Vector3(3000+index*1000,0,0)
		index+=1
		_build_zone(id)
	for q in chapter.steps:
		if not q.has("zone"):continue
		var center: Vector3=centers[q.zone]
		var offset:=Vector3(0,0,7)
		if q.zone=="campus":offset=Vector3(-8,0,10) if q.id=="archivist" else Vector3(8,0,5)
		elif q.zone=="loom":offset=Vector3(0,0,0) if q.id=="magister" else Vector3(0,0,8)
		# Multiple quests share a station; only the active station is interactive.
		chapter.points[q.target]=center+offset
		for i in q.objects.size():
			var at:=center+Vector3([-13,13,0][i%3],0,[-5,-5,-19][i%3])
			if str(q.id).begins_with("beacon_"):at=center+Vector3([-9,9,0][i%3],0,[13,13,-19][i%3])
			if q.id=="restore_core":at=town.world_point("orrery") if i==0 else Vector3(16,0,9)
			chapter.points[q.target+"_"+str(i)]=at
			var node:=ArtKit.task_prop(self,q,i,at)
			if node:visuals[q.target+"_"+str(i)]=node
		var label: Label3D=town._sign(q.title,center+offset+Vector3(0,3.7,0),24)
		visuals[q.target]=label
	town._citizen("world_archivist","塞琳 · 星仪档案员",3,chapter.points.w_archivist+Vector3(-2,0,0))
	town._citizen("world_camp","艾伦 · 无缚者领队",6,chapter.points.w_camp_parley+Vector3(-2,0,0))
	town._citizen("world_assistant","温室助手 · 等待接应",4,chapter.points.w_beacon_life_0)
	for i in 2:town._citizen("world_rescued_"+str(i),"获救的学徒",i,centers.forest+Vector3(-3+i*6,0,12))
	var encounter_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/chapter_encounters.json"))
	for q in chapter.steps:
		if not q.has("encounter") or str(q.encounter).is_empty():continue
		for i in 2:
			var model_id: String=encounter_data[q.encounter].enemies[i].model
			var actor: Node3D
			if model_id=="professor":actor=preload("res://scripts/fusion_3d/world_one_magister.gd").new()
			else:
				actor=preload("res://scripts/fusion_3d/world_one_monster.gd").new();actor.model_id=model_id
			add_child(actor);actor.position=chapter.points[q.target]+Vector3(-4+i*8,0,-2)
			if actor.has_method("face_center"):actor.face_center(chapter.points[q.target]+Vector3(0,0,10))
			visuals[q.target+"_guard_"+str(i)]=actor
	var gate_at: Vector3=town.world_point("gardener")+Vector3(5,0,3)
	gates["gate_greenhouse"]={"at":gate_at,"to":"greenhouse","min":7,"name":"温室入口"}
	gates["gate_campus"]={"at":Vector3(-8,0,15),"to":"campus","min":0,"name":"学院交通站 · 按 J 查阅路线"}
	for id in zone_names:
		var at: Vector3=centers[id]+Vector3(0,0,30)
		gates["return_"+id]={"at":at,"to":"campus","min":0,"name":"返回学院"}
	var routes:=[ ["greenhouse","channel",10],["channel","ruins",12],["campus","forest",21],["forest","camp",23],["camp","mine",25],["forest","graveyard",27],["ruins","loom",30] ]
	for route in routes:
		var at: Vector3=centers[route[0]]+Vector3(22,0,12)
		if route[0]=="campus":at=centers.fire+Vector3(9,0,7)
		gates["route_"+route[1]]={"at":at,"to":route[1],"min":route[2],"name":"前往"+str(zone_names[route[1]])}
	gates["next_world"]={"at":Vector3(32,12,-82),"to":"preview","min":33,"name":"星门 · 下一世界坐标"}
	for id in gates:
		var gate: Dictionary=gates[id]
		if gate.to=="preview":Model.place(self,"castledoor_citygate",gate.at,4.5)
		else:
			# A route is a signpost, not a second unrelated building inside an existing court.
			Model.place(self,"dengzhu",gate.at,2.8)
		town._sign(gate.name,gate.at+Vector3(0,4.8,0),25)
func _build_zone(id: String) -> void:
	var at: Vector3=centers[id]
	var is_natural: bool=id in ["greenhouse","forest","camp"]
	var base:=Color("657256") if is_natural else Color("626461")
	var ground:=CylinderMesh.new();ground.top_radius=45;ground.bottom_radius=44;ground.height=1;ground.radial_segments=64
	var floor_mesh:=ArtKit.mesh(self,ground,at-Vector3(0,0.5,0),base)
	var body:=StaticBody3D.new();floor_mesh.add_child(body)
	var shape:=CylinderShape3D.new();shape.radius=45;shape.height=1
	var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	var shader:=Shader.new()
	shader.code="shader_type spatial; varying vec3 wp; uniform vec4 tint:source_color; void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){float f=sin(wp.x*0.6)*cos(wp.z*0.53)*0.045; ALBEDO=tint.rgb+vec3(f);ROUGHNESS=0.94;}"
	var material:=ShaderMaterial.new();material.shader=shader;material.set_shader_parameter("tint",base);floor_mesh.material_override=material
	# One continuous, understated route leads through every investigation court.
	var path: MeshInstance3D=town._box(at+Vector3(0,0.025,0),Vector3(8,0.08,65),Color("7b7c6c"))
	if not is_natural:path.material_override=town.terrain_world.art.paving
	_decorate(id,at)
	town._sign(zone_names[id],at+Vector3(0,4,28),32)
func refresh() -> void:
	_restore_lights()
	if town.citizens.has("world_assistant"):
		var stop:=0
		for i in 3:
			if chapter.progress.has("w_beacon_life_"+str(i)):stop=mini(i+1,2)
		town.citizens.world_assistant.position=chapter.points["w_beacon_life_"+str(stop)]
		for id in ["world_assistant","world_rescued_0","world_rescued_1"]:
			var active: bool=town.battle==null and (chapter.step>=14 if id=="world_assistant" else chapter.step>=23)
			town.citizens[id].visible=active;town.citizen_labels[id].visible=active
	for id in visuals:
		var visible_now: bool=false
		for q in chapter.available_quests():
			if id==q.target or id.begins_with(str(q.target)+"_"):visible_now=true
		visuals[id].visible=visible_now and town.battle==null
func region(at: Vector3) -> Dictionary:
	for id in zone_names:
		if at.distance_to(centers[id])<90:return {"id":id,"name":zone_names[id]}
	return {}


func _decorate(id: String, at: Vector3) -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=hash(id)
	var natural: bool=id in ["greenhouse","forest","camp"]
	# Irregular boundary clusters leave paths and battle footprints clear.
	for cluster in 12:
		var angle: float=TAU*float(cluster)/12.0+rng.randf_range(-0.12,0.12)
		var anchor:=at+Vector3(cos(angle)*37,0,sin(angle)*37)
		for i in (5 if id=="forest" else 2):
			var offset:=Vector3(rng.randf_range(-3,3),0,rng.randf_range(-3,3))
			var asset_id: String=ArtKit.TREES[(cluster+i)%ArtKit.TREES.size()] if natural else "deathisland_stones0"+str((cluster+i)%4+1)
			if id=="graveyard":asset_id=["deathforestwilttree01","deathforestwilttree02","deathforestwitheredtree"][i%3]
			var placed:=Model.place(self,asset_id,anchor+offset,rng.randf_range(7,11) if natural else rng.randf_range(5,8))
			placed.rotation.y=rng.randf_range(-PI,PI)
		if natural:
			for i in 7:
				var pos:=anchor+Vector3(rng.randf_range(-5,5),0,rng.randf_range(-5,5))
				Model.place(self,ArtKit.BUSHES[(cluster+i)%5] if i%3==0 else ArtKit.GRASSES[(cluster+i)%7],pos,rng.randf_range(0.8,2.0))
	for side in [-1,1]:
		for z in [-19,5,25]:Model.place(self,"dengzhu",at+Vector3(side*10,0,z),3.4)
	if id=="greenhouse":
		for side in [-1,1]:
			ArtKit.home(self,at+Vector3(side*25,0,-23),9,1 if side<0 else 2)
			for z in [-16,0,16]:
				town._box(at+Vector3(side*19,0.3,z),Vector3(6,0.6,9),Color("615847"),true)
				for row in 4:
					for column in [-1,0,1]:
						Model.place(self,ArtKit.BUSHES[(row+abs(side))%5],at+Vector3(side*19+column*1.5,0.6,z-3+row*2),1.2)
			for z in [-24,-12,0,12,24]:town._box(at+Vector3(side*24,4.5,z),Vector3(0.22,9,0.22),Color("5d695e"),true)
		for z in [-24,-12,0,12,24]:
			for side in [-1,1]:
				var rafter: MeshInstance3D=town._box(at+Vector3(side*12,11,z),Vector3(24.33,0.24,0.24),Color("625e4b"));rafter.rotation.z=-side*atan2(4.0,24.0)
		for side in [-1,1]:
			var roof: MeshInstance3D=town._box(at+Vector3(side*12,11.1,0),Vector3(24.33,0.06,48),Color(0.6,0.75,0.68,0.1));roof.rotation.z=-side*atan2(4.0,24.0);roof.visible=false;roof.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;roof.set_meta("camera_clear_glass",true)
			town._box(at+Vector3(side*24,0.4,0),Vector3(0.6,0.8,49),Color("777665"),true)
			town._box(at+Vector3(side*24,9,0),Vector3(0.3,0.3,49),Color("625e4b"))
			for z in [-18,-6,6,18]:
				var pane: MeshInstance3D=town._box(at+Vector3(side*24,4.6,z),Vector3(0.04,7.6,11.7),Color(0.52,0.7,0.63,0.09));pane.visible=false;pane.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;pane.set_meta("camera_clear_glass",true)
		town._box(at+Vector3(0,13,0),Vector3(0.26,0.26,49),Color("625e4b"))
		Model.place(self,"castlehouseshelf",at+Vector3(-27,0,12),4)
		Model.place(self,"castlehouseshelf02",at+Vector3(-27,0,18),3.5)
	elif id=="forest":
		for i in 12:Model.place(self,ArtKit.TREES[i%ArtKit.TREES.size()],at+Vector3((-1 if i%2==0 else 1)*(23+i%3),0,-26+(i/2)*10),9+float(i%3))
	elif id=="camp":
		for side in [-1,1]:
			for z in [-17,4]:Model.place(self,"zhangpeng",at+Vector3(side*24,0,z),10,false,true)
		Model.place(self,"castlehousestove",at+Vector3(-22,0,23),4)
		Model.place(self,"castlehousefirewood",at+Vector3(-18,0,24),2)
		Model.place(self,"castlehouseshelf",at+Vector3(22,0,22),3.5)
		Model.place(self,"castlehousepot",at+Vector3(-20,0,21),0.8)
	else:
		for side in [-1,1]:
			for z in [-27,-13,1,15,29]:
				var wall:=Model.place(self,"castledoor_citywalls",at+Vector3(side*33,0,z),14)
				wall.rotation.y=PI/2
				town._box(at+Vector3(side*34,2.5,z),Vector3(1,5,14),Color("676955"),true)
		if id=="channel":
			for side in [-1,1]:
				town._box(at+Vector3(side*23,0.055,0),Vector3(8,0.08,64),Color("34575b"))
				for z in [-24,0,24]:Model.place(self,"castledoor_sidetower",at+Vector3(side*29,0,z),8)
		elif id=="mine":
			for side in [-1,1]:
				town._box(at+Vector3(side*3,0.12,0),Vector3(0.12,0.12,60),Color("696d6b"))
				for z in [-24,-12,0,12,24]:town._box(at+Vector3(side*25,3.5,z),Vector3(0.5,7,0.5),Color("64543e"),true)
			for z in [-24,-12,0,12,24]:town._box(at+Vector3(0,7,z),Vector3(50,0.5,0.5),Color("64543e"))
			for i in 10:Model.place(self,"fuwenstone0"+str(i%5+1),at+Vector3((-1 if i%2==0 else 1)*24,0,-23+(i/2)*11),2.7)
		elif id=="graveyard":
			for side in [-1,1]:
				for i in 5:Model.place(self,"deathisland_sarcophagus0"+str(i%4+1),at+Vector3(side*24,0,-23+i*11),3.5)
		elif id=="ruins":
			for side in [-1,1]:
				for i in 3:Model.place(self,"shizhu0"+str(i+1),at+Vector3(side*24,0,-22+i*22),8)
		elif id=="loom":
			var schools: Array=["fire","ice","storm","life","death","life","storm"]
			for i in 7:
				var angle:=TAU*float(i)/7
				Model.place(self,"fengmozhu_"+str(schools[i]),at+Vector3(cos(angle)*23,0,sin(angle)*23),5.5)
			Model.place(self,"castledoor_citygate",at+Vector3(0,0,-31),9)

func _restore_lights() -> void:
	for beacon in chapter.beacons:
		if restored_lights.has(beacon):continue
		var school: String=beacon.trim_prefix("beacon_")
		var sphere:=MeshInstance3D.new();var mesh:=SphereMesh.new();mesh.radius=0.65;mesh.height=1.3;sphere.mesh=mesh
		sphere.material_override=town._mat(Color("a9d5ca"),true)
		add_child(sphere);sphere.position=centers[school]+Vector3(0,5.5,7);restored_lights[beacon]=sphere
		var light:=OmniLight3D.new();light.omni_range=12;light.light_color=Color("a9d5ca");light.light_energy=1.6;sphere.add_child(light)
	if chapter.step==33 and not restored_lights.has("core"):
		var column: MeshInstance3D=town._cylinder(town.world_point("orrery")+Vector3(0,5,0),0.22,10,Color("a9d6ed"),true)
		restored_lights.core=column
		town._sign("世界星仪 · 已恢复运转",town.world_point("orrery")+Vector3(0,8,0),30)


