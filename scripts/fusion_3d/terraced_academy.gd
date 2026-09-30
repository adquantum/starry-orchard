extends "res://scripts/fusion_3d/atelier_geometry.gd"
const ArtKit=preload("res://scripts/fusion_3d/world_one_art_kit.gd")
var town: Node3D
var layout: Dictionary
var orbits: Array[Node3D]=[]
var art: Node3D
var terrain: Node3D
func point(value: Array) -> Vector3: return Vector3(value[0],value[1],value[2])
func asset(id: String, at: Vector3, size_value: float=1.0) -> Node3D:
	if id in ["house_1","house_2","inn"]:return ArtKit.home(self,at,size_value*5.3,["house_1","house_2","inn"].find(id))
	var n:=load("res://assets/models/academy/"+id+".glb").instantiate() as Node3D
	add_child(n)
	n.position=at
	n.scale=Vector3.ONE*size_value
	if id in ["house_1","house_2","inn"]:
		var body:=StaticBody3D.new()
		var collision:=CollisionShape3D.new()
		var shape:=BoxShape3D.new()
		shape.size=Vector3(5.1,4.2,4.0)
		collision.shape=shape
		collision.position.y=2.1
		body.add_child(collision)
		n.add_child(body)
	return n
func build(value: Node3D) -> void:
	town=value
	layout=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/academy_world_layout.json"))
	terrain=asset("arcane_academy_terraces",Vector3.ZERO)
	art=preload("res://scripts/fusion_3d/town_art.gd").new()
	add_child(art)
	art.configure(town)
	setup_meshes(terrain)
	var rng:=RandomNumberGenerator.new()
	rng.seed=91245
	for area in layout.regions:
		var center:=point(area.center)
		var id:=str(area.id)
		var school:=int(area.school)
		if id in preload("res://scripts/fusion_3d/functional_town_layout.gd").REPLACED:continue
		if id=="astral":
			build_orrery(center+Vector3(0,0,-11))
			for at in [Vector3(-15,0,-15),Vector3(19,0,0)]:
				ArtKit.home(self,at,8.0,0 if at.x<0 else 2)
			for angle in [0.4,1.4,2.4,3.4,4.4,5.4]:
				art.lamp(Vector3(cos(angle)*22,0,sin(angle)*22))
			continue
		ArtKit.landmark(self,center+(Vector3(10,0,0) if id=="balance" else Vector3(0,0,-7)),id)
		town._sign(str(area.name),center+Vector3(0,9,-7),30)
		if id not in ["life","headmaster"]:
			for i in 4:
				var a:=PI+0.12+i*(PI-0.24)/3.0
				var at:=center+Vector3(cos(a),0,sin(a))*(float(area.radius)-3.5)
				if near_bridge(at,6):continue
				var home:=asset(["house_1","house_2","inn"][i%3],at,1.0+float(i%2)*0.25)
				home.look_at(Vector3(center.x,at.y,center.z))
		# Trees occupy planted outer arcs; preserve bridge mouths and the Life battle court.
		for i in 11:
			var angle:=PI-0.20+i*(PI+0.40)/10.0
			var offset:=Vector3(cos(angle),0,sin(angle))*(float(area.radius)-1.5)
			var at:=center+offset
			if near_bridge(at,6.0):continue
			var tree_id: String="pine" if id=="ice" else ("maple" if id in ["fire","death"] else ["oak","birch","pine"][i%3])
			asset(tree_id,at,0.65+rng.randf()*0.2)
			if i%3==0:asset("flower_bush",at+Vector3(1.4,0,1),0.8)
		for side in [-1,1]:
			art.lamp(center+Vector3(side*(float(area.radius)-3.0),0,2))

		if id=="ice":
			for i in 7:shard(center+Vector3((i-3)*2.0,1,-17),Vector3(1.2,2.5+float(i%3),1.2),Color("83c8ed"))
		elif id=="fire":
			particles(center+Vector3(0,4,-10),Color("ff9b45"),45,Vector3(5,2,3),Vector3(0,1.1,0))
		elif id=="death":
			particles(center+Vector3(0,1,6),Color("9d89d4"),25,Vector3(9,0.5,3),Vector3(0,0.3,0))
		elif id=="storm":
			var dome:=ring(center+Vector3(0,18,-10),3.5,0.10,Color("c9ab67"))
			dome.rotation.x=PI/3
			orbits.append(dome)
	var forest: Array[Node3D]=[]
	var functional=preload("res://scripts/fusion_3d/functional_town_layout.gd").new()
	functional.name="FunctionalDistricts"
	add_child(functional)
	functional.build(self)
	var dressing=preload("res://scripts/fusion_3d/campus_dressing.gd").new()
	add_child(dressing)
	dressing.build(self)
	for i in 850:
		var x:=rng.randf_range(-130,135)
		var z:=rng.randf_range(-157,105)
		if absf(x-40*sin(z*0.035))<26:continue
		var in_cliff:=false
		for area in layout.regions:
			var c:=point(area.center)
			if Vector2(c.x-x,c.z-z).length()<float(area.radius)+5:in_cliff=true
		if in_cliff:continue
		var y:float=-31+sin(x*0.065)*1.3+cos(z*0.047)*1.7
		forest.append(asset("pine" if i%3 else "oak",Vector3(x,y,z),1.0+rng.randf()*0.75))
	batch_forest(forest)
	batch_architecture()
	for id in ["sample_a","sample_b"]:
		var at:=point(layout.points[id])
		asset("flower_bush",at,1.25)
		particles(at+Vector3(0,0.8,0),Color("edaf6a") if id=="sample_a" else Color("8bc8ef"),14,Vector3(0.6,0.4,0.6),Vector3(0,0.35,0))
		town._sign("余烬叶 · E 检查" if id=="sample_a" else "结晶根 · E 检查",at+Vector3(0,2.4,0),24)
	var court:=point(layout.garden_arena)
	for i in 4:
		var creature:=preload("res://scripts/fusion_3d/garden_familiar.gd").new()
		creature.kind=["fire","ice","life","storm"][i]
		creature.position=court+Vector3(-5+i*3.3,-0.12,-5)
		creature.rotation.y=PI
		creature.add_to_group("garden_familiars")
		town.add_child(creature)
	town._sign("失控守护灵 · E 调查",point(layout.points.encounter)+Vector3(0,2.8,0),24).name="GardenEncounterSign"
	particles(court+Vector3(0,1,0),Color("d2dfa4"),45,Vector3(11,0.5,10),Vector3(0.1,0.35,0))
func near_bridge(at: Vector3, margin: float) -> bool:
	for link in layout.links:
		var a:=Vector3.ZERO
		var b:=Vector3.ZERO
		for region in layout.regions:
			if region.id==link[0]:a=point(region.center)
			if region.id==link[1]:b=point(region.center)
		var p:=Geometry2D.get_closest_point_to_segment(Vector2(at.x,at.z),Vector2(a.x,a.z),Vector2(b.x,b.z))
		if p.distance_to(Vector2(at.x,at.z))<margin:return true
	return false
func setup_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		var id:=str(node.name)
		if id.begins_with("Walk_") or id.begins_with("Rail_"):
			node.create_trimesh_collision()
		if id.begins_with("Promenade") or id.begins_with("Radial") or id.begins_with("Inner court") or id.begins_with("Star court") or id.begins_with("Walk_Bridge"):
			node.material_override=art.paving
		elif id.begins_with("Rail_") or id in ["Walk_astral","Walk_balance","Walk_headmaster"]:
			node.material_override=town._mat(Color("99917b"))
		elif id.begins_with("Walk_") and id not in ["Walk_astral","Walk_balance","Walk_headmaster"] or id.begins_with("Valley woodland"):
			var shader_ground:=Shader.new()
			shader_ground.code="""shader_type spatial;
uniform vec4 ground_tint : source_color = vec4(0.2,0.35,0.24,1);
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 q=floor(wp.xz*1.5);
 float fine=fract(sin(dot(q,vec2(12.7,43.1)))*14378.2);
 float broad=sin(wp.x*0.15)*cos(wp.z*0.19)*0.5+0.5;
 ALBEDO=ground_tint.rgb*(0.78+0.16*broad+0.06*fine);ROUGHNESS=1.0;
}"""
			var g:=ShaderMaterial.new()
			g.shader=shader_ground
			var tints: Dictionary={"Walk_fire":"51443b","Walk_ice":"b1c8d4","Walk_storm":"475469","Walk_myth":"6b7155","Walk_life":"446749","Walk_death":"343846"}
			g.set_shader_parameter("ground_tint",Color(tints.get(id,"36593e")))
			node.material_override=g
		if id.begins_with("Water"):
			var waterfall:=id.begins_with("Waterfall")
			var shader:=Shader.new()
			shader.code="""shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float waves=sin(world.x*0.10+world.z*0.07+TIME*0.5)*0.55+sin(world.z*0.17-TIME*0.4)*0.30;
 ALBEDO=mix(vec3(0.025,0.12,0.16),vec3(0.07,0.24,0.29),waves*0.5+0.5);
 ROUGHNESS=0.25;METALLIC=0.15;
}"""
			if waterfall:
				shader.code="""shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
void vertex(){world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 float streak=sin(world.x*16.0+world.z*13.0+sin(world.y*0.32+TIME*2.3));
 float foam=smoothstep(0.45,0.98,sin(world.y*1.2+TIME*5.0+world.x));
 ALBEDO=mix(vec3(0.12,0.40,0.48),vec3(0.72,0.87,0.9),streak*0.23+0.32+foam*0.25);
 ROUGHNESS=0.32;EMISSION=ALBEDO*0.12;
}"""
				var bounds: AABB=node.get_aabb()
				var base: Vector3=node.to_global(bounds.position+Vector3(bounds.size.x/2,0,bounds.size.z/2))
				particles(base,Color("c2dae0"),24,Vector3(2,0.2,2),Vector3(0,1.0,0))
			if not waterfall:
				shader=load("res://scripts/worlds/haqi_water.gdshader")
			var mat_value:=ShaderMaterial.new()
			mat_value.shader=shader
			node.material_override=mat_value
		if id.begins_with("Walk_") or id.begins_with("Promenade") or id.begins_with("Radial") or id.begins_with("Inner court") or id.begins_with("Star court"):
			node.material_override=art.paving
	for child in node.get_children():setup_meshes(child)
func build_orrery(at: Vector3) -> void:
	var root:=Node3D.new()
	add_child(root)
	root.position=at+Vector3(0,4.2,0)
	root.scale=Vector3.ONE*0.5
	ellipsoid(Vector3.ZERO,Vector3(2.8,2.8,2.8),Color("72c9f4"),root,0.4)
	for i in 3:
		var hoop:=ring(Vector3.ZERO,5.0+i*0.4,0.12,Color("bd9147"),root)
		hoop.rotation=Vector3(0.5+i*0.43,i*0.31,0.2+i*0.5)
		orbits.append(hoop)
	for r in [3.5]:
		ring(at+Vector3(0,0.14,0),r,0.09,Color("bba162"))
	particles(at+Vector3(0,4,0),Color("8cceff"),16,Vector3(1,1,1),Vector3(0,0.3,0))
	var light:=OmniLight3D.new()
	light.position=at+Vector3(0,5,0)
	light.light_color=Color("86c7fa")
	light.light_energy=3
	light.omni_range=15
	add_child(light)
	for side in [-1,1]:
		var pillar:=preload("res://scripts/fusion_3d/academy_architecture.gd").new()
		add_child(pillar)
		pillar.position=at+Vector3(side*8.5,0,0)
		pillar.banner(Vector3(0,7,0),Color("183957"),1.5,4)
		pillar.block(Vector3(0,4,0),Vector3(0.35,8,0.35),Color("bd9c58"))
func build_conservatory(at: Vector3) -> void:
	block(at+Vector3(0,0.3,0),Vector3(13,0.6,9),Color("a3b7a2"))
	var dome:=SphereMesh.new()
	dome.radius=5.2
	dome.height=10.4
	var glass:=mesh_node(dome,at+Vector3(0,2,0),Color("548b86"))
	glass.scale=Vector3(1.1,0.75,0.85)
	for i in 6:
		var hoop:=ring(at+Vector3(0,2,0),5.25,0.075,Color("d0b473"))
		hoop.rotation=Vector3(PI/2,i*PI/6,0)
		hoop.scale=Vector3(1.1,0.85,0.75)
	for side in [-1,1]:
		var wing:=asset("house_1",at+Vector3(side*8,0,1),0.9)
		wing.rotation.y=PI
func _process(delta: float) -> void:
	for i in orbits.size():orbits[i].rotation.y+=delta*(0.12+i*0.03)

func batch_forest(roots: Array[Node3D]) -> void:
	var batches: Dictionary={}
	for root in roots:
		var pending: Array[Node]=[root]
		while not pending.is_empty():
			var child: Node=pending.pop_back()
			for next in child.get_children():pending.append(next)
			if child is MeshInstance3D and child.mesh!=null:
				var key:=str(child.mesh.get_instance_id())
				if not batches.has(key):batches[key]={"mesh":child.mesh,"transforms":[]}
				batches[key].transforms.append(child.global_transform)
		root.queue_free()
	for batch in batches.values():
		var multimesh:=MultiMesh.new()
		multimesh.transform_format=MultiMesh.TRANSFORM_3D
		multimesh.mesh=batch.mesh
		multimesh.instance_count=batch.transforms.size()
		for i in batch.transforms.size():multimesh.set_instance_transform(i,batch.transforms[i])
		var node:=MultiMeshInstance3D.new()
		node.multimesh=multimesh
		add_child(node)
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func batch_architecture() -> void:
	var batches: Dictionary={}
	for branch in get_children():
		if branch.get_script()!=preload("res://scripts/fusion_3d/academy_architecture.gd"):continue
		var pending: Array[Node]=[branch]
		while not pending.is_empty():
			var child: Node=pending.pop_back()
			for next in child.get_children():pending.append(next)
			if not child is MeshInstance3D:continue
			var material:=child.material_override as StandardMaterial3D
			if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:continue
			var key:=str(material.albedo_color)+str(material.metallic)+str(material.roughness)+str(material.emission_enabled)+str(material.emission)+str(material.cull_mode)
			if not batches.has(key):
				var st:=SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(material)
				batches[key]=st
			for i in child.mesh.get_surface_count():
				batches[key].append_from(child.mesh,i,child.global_transform)
			child.hide()
	for st in batches.values():
		var node:=MeshInstance3D.new()
		node.mesh=st.commit()
		add_child(node)
