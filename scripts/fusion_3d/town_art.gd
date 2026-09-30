extends Node3D
## Scene dressing only: preserve roads, NPC destinations and the east encounter footprint.
var town: Node3D
const STONE := Color("343c50")
const TRIM := Color("8d7955")
const ROOF := Color("203855")
var paving: ShaderMaterial
var roof_tiles: ShaderMaterial
func configure(owner_town: Node3D) -> void:
	town = owner_town
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=wp.xz*1.45; p.x+=mod(floor(p.y),2.0)*0.5;
 vec2 cell=floor(p); vec2 q=fract(p);
 float edge=min(min(q.x,1.0-q.x),min(q.y,1.0-q.y));
 float hash=fract(sin(dot(cell,vec2(17.13,91.73)))*43758.5);
 vec3 stone=mix(vec3(0.045,0.060,0.092),vec3(0.085,0.105,0.145),hash);
 ALBEDO=mix(vec3(0.02,0.028,0.044),stone,smoothstep(0.025,0.065,edge));
 ROUGHNESS=0.94;
}
"""
	paving = ShaderMaterial.new()
	paving.shader = preload("res://assets/materials/campus_paving.gdshader")
	var roof_shader := Shader.new()
	roof_shader.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=vec2(wp.z*2.0,wp.y*3.0); p.x+=mod(floor(p.y),2.0)*0.5;
 vec2 q=fract(p); float edge=min(min(q.x,1.-q.x),min(q.y,1.-q.y));
 float n=fract(sin(dot(floor(p),vec2(23.17,48.2)))*18273.4);
 ALBEDO=mix(vec3(0.013,0.023,0.045),mix(vec3(0.025,0.045,0.082),vec3(0.05,0.075,0.13),n),smoothstep(0.025,0.065,edge));
 if(!FRONT_FACING){NORMAL=-NORMAL;}
 ROUGHNESS=0.85;
}
"""
	roof_tiles = ShaderMaterial.new()
	roof_tiles.shader = roof_shader
func box(at: Vector3, size_value: Vector3, color: Color, solid: bool = false) -> MeshInstance3D:
	return town._box(at,size_value,color,solid)
func cylinder(at: Vector3, radius: float, height: float, color: Color, pointed: bool = false) -> MeshInstance3D:
	return town._cylinder(at,radius,height,color,pointed)
func ring(at: Vector3, radius: float, width: float, color: Color) -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = radius-width
	torus.outer_radius = radius
	torus.rings = 64
	torus.ring_segments = 6
	var mesh := MeshInstance3D.new()
	mesh.mesh = torus
	mesh.position = at
	mesh.material_override = town._mat(color)
	town.add_child(mesh)
func roof(at: Vector3, width: float, depth: float, height: float) -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-width/2,0,-depth/2),Vector3(width/2,0,-depth/2),Vector3(0,height,-depth/2),Vector3(-width/2,0,depth/2),Vector3(width/2,0,depth/2),Vector3(0,height,depth/2)]
	for index in [0,2,1,3,4,5,0,3,5,0,5,2,2,5,4,2,4,1]:
		mesh.add_vertex(points[index])
	mesh.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = mesh.commit()
	node.position = at
	node.material_override = roof_tiles
	town.add_child(node)
	for side in [-1,1]:
		for i in 6:
			var x: float = side*(float(i)/6.0)*(width/2)
			box(at+Vector3(x,height*(1.0-float(i)/6.0)+0.025,0),Vector3(0.06,0.06,depth+0.10),Color("3c5270"))
	box(at+Vector3(0,height+0.035,0),Vector3(0.12,0.10,depth+0.2),TRIM)
func window(at: Vector3, width: float = 0.8, height: float = 1.3) -> void:
	box(at,Vector3(width+0.18,height+0.18,0.16),Color("151c29"))
	var pane := box(at+Vector3(0,0,0.10),Vector3(width,height,0.035),Color("e4af57"))
	pane.material_override = town._mat(Color("c49445"),true)
	box(at+Vector3(0,0,0.13),Vector3(0.065,height,0.05),TRIM)
	box(at+Vector3(0,-0.12,0.13),Vector3(width,0.055,0.05),TRIM)
	box(at+Vector3(0,-height/2-0.12,0.08),Vector3(width+0.27,0.15,0.24),STONE.lightened(0.15))
func building(at: Vector3, title: String, accent: Color) -> void:
	var index := absi(roundi(at.x/8.0))%3
	var model := load("res://assets/models/academy/"+["house_1","house_2","inn"][index]+".glb") as PackedScene
	var building_node := model.instantiate() as Node3D
	town.add_child(building_node)
	building_node.position=at
	building_node.rotation.y=PI
	var collider := box(at+Vector3(0,2.2,0),Vector3(5.6,4.4,4.5),STONE,true)
	collider.visible=false
	var decoration := preload("res://scripts/fusion_3d/academy_architecture.gd").new()
	town.add_child(decoration)
	decoration.position=at
	decoration.banner(Vector3(2.3,4.6,2.75),accent.darkened(0.20),0.85,2.0)
	town._sign(title,at+Vector3(0,5.4,2.9),24)
func tree(at: Vector3, purple: bool=false) -> void:
	var id: String = "maple" if purple else (["oak","birch","pine"][absi(roundi(at.x+at.z))%3])
	var model := load("res://assets/models/academy/"+id+".glb") as PackedScene
	var node := model.instantiate() as Node3D
	node.position=at
	node.rotation.y=fmod(absf(at.x*3.13+at.z),TAU)
	node.scale=Vector3.ONE*0.8
	town.add_child(node)
func lamp(at: Vector3) -> void:
	cylinder(at+Vector3(0,0.15,0),0.34,0.3,STONE)
	cylinder(at+Vector3(0,1.55,0),0.075,2.8,TRIM)
	cylinder(at+Vector3(0,3.03,0),0.29,0.16,TRIM)
	var lantern := box(at+Vector3(0,3.33,0),Vector3(0.33,0.50,0.33),Color("f1bf76"))
	lantern.material_override = town._mat(Color("e4af61"),true)
	for side in [-1,1]: box(at+Vector3(side*0.20,3.33,0),Vector3(0.045,0.6,0.43),TRIM)
	cylinder(at+Vector3(0,3.72,0),0.35,0.3,ROOF,true)
	var light := OmniLight3D.new()
	light.position = at+Vector3(0,3.3,0)
	light.light_color = Color("ffd09a")
	light.light_energy = 0.6
	light.omni_range = 6.0
	town.add_child(light)
func garden(at: Vector3, purple: bool) -> void:
	box(at+Vector3(0,0.15,0),Vector3(5,0.3,3.8),STONE)
	box(at+Vector3(0,0.32,0),Vector3(4.7,0.18,3.5),Color("263e35"))
	for x in [-2.0,2.0]:
		box(at+Vector3(x,0.65,0),Vector3(0.45,0.7,3.1),Color("315648"))
	tree(at,purple)
	for i in 5:
		cylinder(at+Vector3(-1.5+i*0.7,0.52,1.35),0.12,0.18,Color("897aa5") if purple else Color("a18c69"))
func fountain(at: Vector3) -> void:
	cylinder(at+Vector3(0,0.22,0),2.1,0.45,STONE)
	ring(at+Vector3(0,0.47,0),2.1,0.20,TRIM)
	cylinder(at+Vector3(0,0.46,0),1.88,0.03,Color("315e76"))
	cylinder(at+Vector3(0,1.0,0),0.4,1.0,STONE.lightened(0.1))
	cylinder(at+Vector3(0,1.54,0),0.32,1.05,Color("8f79be"),true)
	ring(at+Vector3(0,0.5,0),1.18,0.03,Color("6899ac"))
func build() -> void:
	box(Vector3(0,-0.6,0),Vector3(96,1,96),Color("162c2c"),true)
	for size_value in [Vector3(12,0.08,84),Vector3(84,0.08,12)]:
		box(Vector3(0,-0.05,0),size_value,Color.WHITE).material_override = paving
	for x in [-5.9,5.9]:
		box(Vector3(x,0.005,0),Vector3(0.09,0.03,84),TRIM)
		box(Vector3(0,0.01,x),Vector3(84,0.03,0.09),TRIM)
	for center in [Vector3.ZERO,Vector3(23,0,0)]:
		cylinder(center+Vector3(0,-0.005,0),10.6,0.07,STONE).material_override = paving
		for r in [9.8,10.2]: ring(center+Vector3(0,0.05,0),r,0.055,TRIM)
	for r in [2.3,2.6,5.2,5.35]: ring(Vector3(0,0.05,0),r,0.05,TRIM)
	for i in 8:
		var a := i*TAU/8
		var line := box(Vector3(sin(a)*1.35,0.065,cos(a)*1.35),Vector3(0.055,0.035,2.4),Color("7095a5"))
		line.rotation.y = a
	for i in 7: building(Vector3(-24+i*8,0,-24),Locale.text("SCHOOL_"+town.SCHOOL_IDS[i].to_upper())+"学院",town.TINTS[i])
	building(Vector3(-23,0,14),"河畔市场",town.TINTS[6])
	building(Vector3(0,0,29),"学生宿舍",town.TINTS[1])
	building(Vector3(15,0,25),"星辉图书馆",town.TINTS[3])
	for at in [Vector3(-12,0,-12),Vector3(12,0,-13),Vector3(-12,0,12),Vector3(11,0,16),Vector3(-26,0,-10),Vector3(-26,0,24)]:
		garden(at,int(at.x)%3 == 0)
	fountain(Vector3(-18,0,-12))
	fountain(Vector3(-14,0,22))
	for x in [-7.8,7.8]:
		for z in [-18,-8,8,18]: lamp(Vector3(x,0,z))
	for z in [-8.5,8.5]:
		for x in [16,30]: lamp(Vector3(x,0,z))
	# Secondary courts connect the gardens and buildings without obstructing the duel.
	for at in [Vector3(-20,0,-18),Vector3(20,0,-18),Vector3(-23,0,10),Vector3(15,0,20)]:
		box(at+Vector3(0,0.01,0),Vector3(7.1,0.06,4.5),STONE).material_override=paving
		for side in [-1,1]:
			box(at+Vector3(side*3.4,0.45,0),Vector3(0.22,0.9,4.5),STONE)
			box(at+Vector3(side*3.4,0.94,0),Vector3(0.3,0.1,4.6),TRIM)
	for i in 7:
		tree(Vector3(42,0,-28+i*9),i%3==0)
	for i in 12:
		tree(Vector3(-41+i*7,0,-34),i%3 == 0)
		tree(Vector3(-42,0,-27+i*5),i%4 == 0)
	for side in [-1,1]:
		var base := Vector3(35,0,side*8.4)
		box(base+Vector3(0,3.1,0),Vector3(3.1,6.2,3.1),STONE,true)
		cylinder(base+Vector3(0,7.1,0),2.25,2.8,ROOF,true)
		for y in [0.5,5.8]: box(base+Vector3(0,y,0),Vector3(3.3,0.18,3.3),TRIM)
	box(Vector3(35,6.2,0),Vector3(2.4,0.8,17),STONE)
	box(Vector3(35,6.7,0),Vector3(2.6,0.10,17.5),TRIM)
	# River and bridge keep the merchant approach open.
	box(Vector3(-35,-0.11,0),Vector3(7,0.04,74),Color("233f51"))
	box(Vector3(-35,0.05,0),Vector3(10,0.3,5),STONE,true).material_override = paving
	for z in [-2.7,2.7]: box(Vector3(-35,0.75,z),Vector3(10,0.2,0.18),TRIM)
	for x in [-8,8]:
		for z in [-8,8]:
			box(Vector3(x,0.55,z),Vector3(2,0.16,0.65),Color("57483d"),true)
			box(Vector3(x,0.93,z+0.25),Vector3(2,0.5,0.12),Color("57483d"))

