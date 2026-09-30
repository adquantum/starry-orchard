extends Node3D
var town: Node3D
var art: Node3D
var orrery: Node3D
func build(value: Node3D, palette: Node3D) -> void:
	town=value
	art=palette
	# Eastern expansion joins the old east gate without changing its arena.
	var lawn: MeshInstance3D=town._box(Vector3(79,-0.6,0),Vector3(66,1,76),Color("243c36"),true)
	var grass_shader := Shader.new()
	grass_shader.code="""shader_type spatial;
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){vec2 p=floor(wp.xz*3.0);float n=fract(sin(dot(p,vec2(17.13,53.1)))*17832.3);float broad=sin(wp.x*0.31)*cos(wp.z*0.38)*0.5+0.5;ALBEDO=mix(vec3(0.025,0.064,0.041),vec3(0.063,0.12,0.068),n*0.35+broad*0.55);ROUGHNESS=1.0;}
"""
	var grass := ShaderMaterial.new()
	grass.shader=grass_shader
	lawn.material_override=grass
	town._box(Vector3(72,-0.045,0),Vector3(77,0.08,9),Color.WHITE).material_override=art.paving
	town._cylinder(Vector3(78,-0.02,0),12.2,0.09,Color.WHITE).material_override=art.paving
	for radius in [11.6,12.0]: art.ring(Vector3(78,0.045,0),radius,0.055,Color("8a926c"))
	# Water below a level stone bridge. Bank barriers stop walking into the river.
	var water: MeshInstance3D = town._box(Vector3(53,-0.055,0),Vector3(9,0.04,75),Color("365c70"))
	var mat := ShaderMaterial.new()
	mat.shader=load("res://scripts/worlds/haqi_water.gdshader")
	mat.set_shader_parameter("deep_color",Color("365c70"))
	mat.set_shader_parameter("shallow_color",Color("619aab"))
	mat.set_shader_parameter("reflection_color",Color("819dac"))
	mat.set_shader_parameter("foam_color",Color("c4dce0"))
	water.material_override=mat
	water.position.z=21
	water.scale.z=33.0/75.0
	var other := water.duplicate()
	other.position.z=-21
	town.add_child(other)
	town._box(Vector3(53,-0.17,0),Vector3(11,0.14,8),Color.WHITE,true).material_override=art.paving
	for z in [-21.0,21.0]:
		var blocker: MeshInstance3D = town._box(Vector3(53,0.6,z),Vector3(9,2,33),Color.BLACK,true)
		blocker.visible=false
	for side in [-1,1]:
		for i in 6:
			town._box(Vector3(48.0+i*2.0,0.65,side*4.15),Vector3(0.35,1.4,0.45),Color("6a727a"),true)
		town._box(Vector3(53,1.27,side*4.15),Vector3(10.5,0.18,0.46),Color("9b997c"),true)
		for z in [-20,-10,10,20]:
			art.tree(Vector3(46,0,z),false)
			town._box(Vector3(58.0,0.18,z),Vector3(0.5,0.55,8.7),Color("596b61"),true)
	for x in [47,59]:
		for z in [-5.8,5.8]: art.lamp(Vector3(x,0,z))
	# Garden paths and clusters frame the free combat area without adding obstacles.
	for x in [65,94]:
		town._box(Vector3(x,-0.04,0),Vector3(2.7,0.09,51),Color.WHITE).material_override=art.paving
		for side in [-1,1]:
			town._box(Vector3(x+side*1.48,0.03,0),Vector3(0.13,0.12,51),Color("8b9376"))
	for z in [-17.5,18.5]:
		town._box(Vector3(79,-0.04,z),Vector3(30,0.09,2.2),Color.WHITE).material_override=art.paving
	for at in [Vector3(69,0,20),Vector3(90,0,20),Vector3(68,0,-19),Vector3(91,0,-19),Vector3(101,0,-5),Vector3(101,0,16)]:
		town._box(at+Vector3(0,0.12,0),Vector3(3.6,0.28,1.7),Color("67735a"))
		for i in 9:
			var flower_at: Vector3=at+Vector3((i%3-1)*1.05,0.42,(i/3-1)*0.45)
			town._cylinder(flower_at,0.17,0.30,Color("a9af75") if i%2==0 else Color("b192a6"),true)
	for at in [Vector3(62,0,-9),Vector3(96,0,6)]:
		town._cylinder(at+Vector3(0,2.4,0),0.065,4.8,Color("ae9970"))
		town._box(at+Vector3(0.58,3.9,0),Vector3(1.15,1.6,0.045),Color("426b4c"))
		town._box(at+Vector3(0.58,4.78,0),Vector3(1.4,0.08,0.12),Color("b6a170"))
		town._sign("❧",at+Vector3(0.58,3.9,0.08),38)
	# Terraced planting around a deliberately empty battle court.
	for at in [Vector3(66,0,-21),Vector3(83,0,-21),Vector3(66,0,22),Vector3(84,0,23),Vector3(103,0,9),Vector3(103,0,-10)]:
		art.garden(at,false)
		art.lamp(at+Vector3(3.1,0,0))
	for i in 9:
		art.tree(Vector3(62+i*5.5,0,33),i%4==0)
		art.tree(Vector3(61+i*5.5,0,-34),i%4==0)
	for z in [-25,-15,-5,5,15,25]: art.tree(Vector3(109,0,z),false)
	art.building(Vector3(65,0,28),"生命学院 · 花园值守所",Color("79b883"))
	# A conservatory facade signals the next destination without pretending it is playable.
	conservatory(Vector3(98,0,-26))
	town._sign("废弃温室 · 后续调查区域",Vector3(98,3.8,-20),25)
	town._box(Vector3(98,1.1,-20),Vector3(8,2.2,0.3),Color("675f49"),true)
	town._sign("生命花园",Vector3(61,4.7,-6),34)
	town._sign("星仪中央城  ←     →  生命花园",Vector3(43,3.7,5.7),25)
	art.fountain(Vector3(93,0,24))
	for at in [Vector3(70,0,-15),Vector3(92,0,13)]:
		town._cylinder(at+Vector3(0,0.12,0),1.15,0.26,Color("4c6155"))
		for i in 5:
			var a := i*TAU/5
			var leaf: MeshInstance3D = town._cylinder(at+Vector3(sin(a)*0.4,0.85,cos(a)*0.4),0.22,1.25,Color("789359"),true)
			leaf.rotation.z=sin(a)*0.4
		town._cylinder(at+Vector3(0,1.2,0),0.21,0.65,Color("d79866") if at.x<80 else Color("96b8cf"),true)
	town._sign("余烬叶 · E 检查",Vector3(70,2.2,-15),23)
	town._sign("结晶根 · E 检查",Vector3(92,2.2,13),23)
	town._sign("失控守护灵 · E 调查",Vector3(78,2.8,9),24).name="GardenEncounterSign"
	for i in 4:
		var creature := preload("res://scripts/fusion_3d/garden_familiar.gd").new()
		creature.kind=["fire","ice","life","storm"][i]
		creature.position=Vector3(73+i*3.3,0,-3)
		creature.rotation.y=PI
		creature.add_to_group("garden_familiars")
		town.add_child(creature)
	# Floating astronomical instrument; root and exploration camera stay unchanged.
	orrery=Node3D.new()
	town.add_child(orrery)
	orrery.position=Vector3(0,4.0,-11)
	for i in 3:
		var torus := TorusMesh.new()
		torus.inner_radius=1.75+i*0.14
		torus.outer_radius=1.82+i*0.14
		var ring := MeshInstance3D.new()
		ring.mesh=torus
		ring.material_override=town._mat(Color("b89c65"))
		ring.rotation_degrees=Vector3(i*43,0,28+i*30)
		orrery.add_child(ring)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius=0.55
	sphere.height=1.1
	core.mesh=sphere
	core.material_override=town._mat(Color("649bba"),true)
	orrery.add_child(core)
	town._cylinder(Vector3(0,0.15,-11),2.5,0.35,Color("3b495e"))
	town._sign("World Orrery · E 观测",Vector3(0,6.8,-11),27)
	for i in 7:
		var angle := i*TAU/7
		town._cylinder(Vector3(sin(angle)*2.7,0.55,-11+cos(angle)*2.7),0.16,0.8,town.TINTS[i],true)
func conservatory(at: Vector3) -> void:
	town._box(at+Vector3(0,0.2,0),Vector3(12,0.4,9),Color("68766c"),true)
	var glass: MeshInstance3D = town._box(at+Vector3(0,2.8,0),Vector3(11.5,5.2,8.5),Color("46615e"),true)
	glass.material_override.roughness=0.28
	for x in [-5.8,-2.9,0.0,2.9,5.8]:
		town._box(at+Vector3(x,2.8,4.35),Vector3(0.14,5.4,0.15),Color("b8a876"))
		var beam: MeshInstance3D=town._box(at+Vector3(x,6.0,0),Vector3(0.16,0.16,9.4),Color("b8a876"))
		beam.rotation.x=0.0
	for y in [0.6,2.6,5.5]:
		town._box(at+Vector3(0,y,4.35),Vector3(11.8,0.14,0.14),Color("b8a876"))
	art.roof(at+Vector3(0,5.55,0),12.2,9.3,2.0)
func _process(delta: float) -> void:
	if orrery != null: orrery.rotation.y += delta*0.16
