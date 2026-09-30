extends "res://scripts/fusion_3d/atelier_geometry.gd"
const STONE=Color("b4b7af")
const PALE=Color("d4d0bb")
const GOLD=Color("af9057")
const BLUE=Color("24395d")
var flags:Array[MeshInstance3D]=[]
func arch(at: Vector3, width: float, height: float, depth: float, color: Color, inset: bool=true) -> void:
	var radius:=width*0.5
	var spring:=height-radius
	if inset:
		var poly:Array[Vector3]=[at+Vector3(-radius,0,-0.06),at+Vector3(radius,0,-0.06)]
		for i in 13:
			var a:=i*PI/12
			poly.append(at+Vector3(cos(a)*radius,spring+sin(a)*radius,-0.06))
		plate(poly,Color("324758"))
	for side in [-1,1]:
		block(at+Vector3(side*(radius+0.12),spring*0.5,0),Vector3(0.24,spring,depth),color)
	for i in 13:
		var a:=i*PI/12
		var voussoir:=block(at+Vector3(cos(a)*(radius+0.12),spring+sin(a)*(radius+0.12),0),Vector3(0.30,0.27,depth),color)
		voussoir.rotation.z=a
	block(at+Vector3(0,-0.10,0),Vector3(width+0.6,0.18,depth+0.15),color)
func window(at: Vector3, width: float=0.7, height: float=1.8) -> void:
	arch(at,width,height,0.18,PALE)
	block(at+Vector3(0,height*0.43,0.025),Vector3(width*0.77,height*0.72,0.02),Color("749aaa")).material_override=mat(Color("89a5a9"),0.2,0.16)
	block(at+Vector3(0,height*0.48,0.08),Vector3(0.055,height*0.9,0.06),GOLD)
	block(at+Vector3(0,height*0.35,0.08),Vector3(width,0.06,0.06),GOLD)
func tower(at: Vector3, height: float, radius: float, accent: Color) -> void:
	profile(at,[Vector4(0,0,radius*1.16,radius*1.16),Vector4(0,0.45,radius,radius),Vector4(0,height*0.80,radius*0.85,radius*0.85),Vector4(0,height*0.82,radius*1.1,radius*1.1),Vector4(0,height*0.87,radius*1.1,radius*1.1)],STONE,10)
	for y in [0.5,height*0.46,height*0.80]: ring(at+Vector3(0,y,0),radius*1.04,0.09,GOLD)
	profile(at,[Vector4(0,height*0.86,radius*1.30,radius*1.30),Vector4(0,height*0.90,radius*1.20,radius*1.20),Vector4(0.12,height*1.10,radius*0.55,radius*0.55),Vector4(0.32,height*1.25,0.015,0.015)],accent,10)
	shard(at+Vector3(0.32,height*1.27,0),Vector3(0.18,0.6,0.18),GOLD)
	for i in 5:
		var a:=i*TAU/5
		var buttress:=block(at+Vector3(sin(a)*radius,1.8,cos(a)*radius),Vector3(0.22,3.6,0.40),PALE)
		buttress.rotation.y=a
	window(at+Vector3(0,height*0.52,radius*0.89),radius*0.70,height*0.20)
func house(title: String, accent: Color) -> void:
	block(Vector3(0,2.65,0),Vector3(6,5.3,5),STONE)
	for y in [0.25,2.8,5.15]: block(Vector3(0,y,0),Vector3(6.4,0.18,5.35),PALE)
	for x in [-2.75,2.75]:
		block(Vector3(x,2.6,2.60),Vector3(0.28,5.2,0.42),PALE)
	for x in [-1.85,1.85]:
		window(Vector3(x,0.85,2.58),0.75,1.6)
		window(Vector3(x,3.30,2.58),0.72,1.45)
	arch(Vector3(0,0.05,2.63),1.35,2.55,0.32,PALE)
	# Tall swept roof with repeated slate bands and a front gable.
	profile(Vector3.ZERO,[Vector4(0,5.3,4.0,3.4),Vector4(0,5.5,3.5,3.0),Vector4(0,6.8,1.8,1.55),Vector4(0.2,8.0,0.04,0.04)],BLUE,4)
	for i in 5:
		var h:=5.4+i*0.43
		var r:=3.4-i*0.56
		profile(Vector3.ZERO,[Vector4(0,h,r,r*0.84),Vector4(0,h+0.065,r,r*0.84)],Color("53657b"),4)
	tower(Vector3(-2.55,0,-1.8),7.8,0.75,BLUE)
	var gable:=plate([Vector3(-1.2,5.05,2.85),Vector3(1.2,5.05,2.85),Vector3(0,7.0,2.85)],STONE)
	window(Vector3(0,5.1,2.88),0.65,1.35)
	banner(Vector3(2.6,4.95,2.97),accent,0.72,1.65)
func banner(at: Vector3, color: Color, width: float=1.0, height: float=2.8) -> void:
	block(at+Vector3(0,0.06,0),Vector3(width+0.3,0.08,0.10),GOLD)
	var m:=PlaneMesh.new()
	m.size=Vector2(width,height)
	m.subdivide_width=5
	m.subdivide_depth=12
	var n:=mesh_node(m,at+Vector3(0,-height*0.5,0),color)
	n.rotation.x=PI/2
	var shader:=Shader.new()
	shader.code="""shader_type spatial;
render_mode cull_disabled;
uniform vec4 cloth:source_color;
void vertex(){float free_edge=UV.y;VERTEX.y+=sin(VERTEX.x*4.+TIME*1.7+UV.y*3.)*0.08*free_edge;}
void fragment(){float edge=min(UV.x,1.-UV.x);float border=1.-smoothstep(0.025,0.045,edge);float star=step(abs(UV.x-.5),.018)*step(abs(UV.y-.43),.20)+step(abs(UV.y-.43),.012)*step(abs(UV.x-.5),.22);ALBEDO=mix(cloth.rgb,vec3(.58,.40,.16),clamp(border+star,0.,1.));ROUGHNESS=.85;}
"""
	var sm:=ShaderMaterial.new()
	sm.shader=shader
	sm.set_shader_parameter("cloth",color)
	n.material_override=sm
func cathedral() -> void:
	block(Vector3(0,5.5,0),Vector3(17,11,9),STONE)
	for x in [-9.5,9.5]: tower(Vector3(x,0,0),19,1.8,BLUE)
	for x in [-6,-3,0,3,6]:
		window(Vector3(x,4.5,4.6),1.3,4.0)
		block(Vector3(x,2.0,4.6),Vector3(0.35,4,0.65),PALE)
	arch(Vector3(0,0.05,4.8),3.5,4.3,0.6,PALE)
	profile(Vector3.ZERO,[Vector4(0,10.7,12,6.8),Vector4(0,11.1,11,6.2),Vector4(0,16.8,0.05,0.05)],BLUE,4)
	tower(Vector3(0,0,-1),24,1.65,BLUE)
	var rose:=ring(Vector3(0,10.0,4.72),1.55,0.13,GOLD)
	rose.rotation.x=PI/2
	for i in 8:
		var a:=i*TAU/8
		spline([Vector3(0,10,4.75),Vector3(sin(a)*1.4,10+cos(a)*1.4,4.75)],[0.035,0.035],GOLD)
	for x in [-6,6]: banner(Vector3(x,10.0,4.85),BLUE,1.25,4.7)
