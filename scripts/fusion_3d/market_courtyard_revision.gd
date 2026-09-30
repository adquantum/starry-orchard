extends Node3D
## River market pilot: one district, keeping existing bridge mouths and merchant location.
const Model=preload("res://scripts/fusion_3d/world_one_model.gd")
const Kit=preload("res://scripts/fusion_3d/world_one_art_kit.gd")
var layout: Node3D
var district: Node3D
func box(at: Vector3,size_value: Vector3,color: Color,solid: bool=true) -> MeshInstance3D:
	var n:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size_value;n.mesh=mesh;n.position=at
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=0.9;n.material_override=mat;district.add_child(n)
	if solid:
		var body:=StaticBody3D.new();var shape:=CollisionShape3D.new();var volume:=BoxShape3D.new();volume.size=size_value;shape.shape=volume;body.add_child(shape);n.add_child(body)
	return n
func prop(id: String,at: Vector3,extent: float,solid: bool=false) -> Node3D:
	return layout.item(district,id,at,extent,solid)
func wall(a: Vector3,b: Vector3) -> void:
	var n:=box((a+b)*0.5+Vector3.UP*0.65,Vector3(0.6,1.3,a.distance_to(b)),Color("73777c"));n.rotation.y=atan2(b.x-a.x,b.z-a.z)
	var cap:=box((a+b)*0.5+Vector3.UP*1.36,Vector3(0.76,0.16,a.distance_to(b)+0.1),Color("c1b596"));cap.rotation.y=n.rotation.y
	var segments:=maxi(1,int(a.distance_to(b)/2.0))
	for i in segments+1:box(a.lerp(b,float(i)/segments)+Vector3.UP*1.66,Vector3(0.9,0.52,0.75),Color("8d8f89"))
func build(p_layout: Node3D,root: Node3D) -> void:
	layout=p_layout;district=root
	# Broad central lane continues the existing west bridge into a small court.
	layout.path(root,Vector3(-20,0,4),Vector3(9,0,4),5.2)
	layout.path(root,Vector3(1,0,12),Vector3(1,0,-12),4)
	for side in [-1,1]:
		prop("castledoor_sidetower",Vector3(-15,0,4+side*5.3),7.2,true)
		prop("castledoor_blueflag",Vector3(-12.5,0,4+side*5.0),3.8)
		prop("curlyironstreetlamp01",Vector3(-9,0,4+side*3.5),3.8,true)
	wall(Vector3(-14,0,-2),Vector3(-14,0,-11))
	wall(Vector3(-14,0,-11),Vector3(-8,0,-16))
	wall(Vector3(8,0,-17),Vector3(16,0,-10))
	wall(Vector3(17,0,-9),Vector3(17,0,10))
	wall(Vector3(-13,0,10),Vector3(-8,0,17))
	wall(Vector3(-8,0,17),Vector3(6,0,17))
	# Raised shop terrace; a gentle ramp is the actual collision surface.
	box(Vector3(10.5,0.6,-5),Vector3(10,1.2,12),Color("77797d"))
	var terrace:=box(Vector3(10.5,1.22,-5),Vector3(10,0.12,12),Color.WHITE);terrace.material_override=layout.source.art.paving
	for i in 6:box(Vector3(8,0.1+i*0.2,3.7-i*0.55),Vector3(5,0.2,0.56),Color("aaa58f"),false)
	var ramp:=box(Vector3(8,0.55,2.2),Vector3(5,0.16,3.8),Color("929589"));ramp.rotation.x=deg_to_rad(18)
	layout.house(root,Vector3(11,1.3,-6),8.5,1,Vector3(1,1.3,4))
	prop("castlehousegemshop",Vector3(0,0,-13),9,true)
	layout.house(root,Vector3(-8,0,-8),7.5,2,Vector3(0,0,1))
	layout.house(root,Vector3(9,0,12),7.2,0,Vector3(-3,0,5))
	# Two opposing small awnings leave the main arrival lane and NPC free.
	for at in [Vector3(-7,0,10),Vector3(5,0,-5)]:
		prop("castlehouseshed01",at,3.8,true)
		prop("woodenbattenbox",at+Vector3(1.5,0,0.7),0.9,true)
		prop("contracttable",at+Vector3(0,0,1.6),1.5,true)
	# Shallow decorative fountain and ring bench court.
	var basin:=MeshInstance3D.new();var bowl:=CylinderMesh.new();bowl.top_radius=2.2;bowl.bottom_radius=2.4;bowl.height=0.5;basin.mesh=bowl;basin.position=Vector3(-4,0.25,0);root.add_child(basin)
	var stone:=StandardMaterial3D.new();stone.albedo_color=Color("9b9e9c");basin.material_override=stone
	var rim:=MeshInstance3D.new();var ring:=TorusMesh.new();ring.inner_radius=1.9;ring.outer_radius=2.3;rim.mesh=ring;rim.position=Vector3(-4,0.56,0);rim.material_override=stone;root.add_child(rim)
	var water:=MeshInstance3D.new();var disc:=CylinderMesh.new();disc.top_radius=1.96;disc.bottom_radius=1.96;disc.height=0.035;water.mesh=disc;water.position=Vector3(-4,0.5,0);var wm:=ShaderMaterial.new();wm.shader=load("res://scripts/worlds/haqi_water.gdshader");water.material_override=wm;root.add_child(water)
	prop("shizhu01",Vector3(-4,0.5,0),1.7)
	for at in [Vector3(-10,0,14),Vector3(13,1.3,-10),Vector3(-9,0,-14)]:
		prop("populus01",at,6)
		prop("thicketgrass_03",at,2.8)
		prop("flowerpot_1",at+Vector3(1.5,0,0),1.2)
	for at in [Vector3(-3,0,12),Vector3(4,1.3,-9)]:
		prop("brownwoodbench",at,2.7,true)
		prop("curlyironstreetlamp01",at+Vector3(2,0,0),3.8,true)
	prop("castlehousesignboard01",Vector3(-10,0,7),2.3)

	for at in [Vector3(-8,0,14),Vector3(13,0,6),Vector3(-9,0,-14)]:
		box(at+Vector3(0,0.14,0),Vector3(4.6,0.28,2.5),Color("636d68"))
		box(at+Vector3(0,0.29,0),Vector3(4.2,0.04,2.1),Color("354c38"),false)
		for x in [-1.4,0.0,1.4]:prop("thicketgrass_03",at+Vector3(x,0.32,0),1.5)
	for at in [Vector3(-10,2.6,0.5),Vector3(-10,2.6,7.5),Vector3(6,3.8,-9)]:
		var light:=OmniLight3D.new();light.position=at;light.light_color=Color("ffd293");light.light_energy=0.7;light.omni_range=5;district.add_child(light)
