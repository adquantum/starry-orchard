extends Node3D
## Authored functional districts. Asset instances remain editable under named roots.
const Model=preload("res://scripts/fusion_3d/world_one_model.gd")
const Kit=preload("res://scripts/fusion_3d/world_one_art_kit.gd")
const REPLACED=["astral","fire","ice","storm","myth","headmaster"]
var source: Node3D
var zones: Dictionary={}
func zone(id: String,at: Vector3) -> Node3D:
	var root:=Node3D.new()
	root.name=id
	add_child(root)
	root.position=at
	zones[id]=root
	return root
func item(root: Node3D,id: String,at: Vector3,size: float,solid: bool=false) -> Node3D:
	var n:=Model.place(root,id,at,size,false,solid)
	if n!=null:
		n.name=id+"_"+str(root.get_child_count())
		if id in ["castledoor_citygate","castledoor_blueflag"]:
			var bounds: Vector3=n.get_meta("normalized_size")
			if bounds.z>bounds.x:n.rotation.y=PI/2
	return n
func house(root: Node3D,at: Vector3,size: float,variant: int,focus: Vector3) -> void:
	var n:=Kit.home(root,at,size,variant)
	n.name="residence_"+str(root.get_child_count())
	var d:=focus-at
	n.rotation.y=atan2(d.x,d.z)
func path(root: Node3D,a: Vector3,b: Vector3,width: float) -> void:
	var n:=MeshInstance3D.new()
	n.name="pedestrian_path_"+str(root.get_child_count())
	var shape:=BoxMesh.new()
	shape.size=Vector3(width,0.055,a.distance_to(b))
	n.mesh=shape
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("687575")
	mat.roughness=1.0
	n.material_override=source.art.paving
	root.add_child(n)
	n.position=(a+b)*0.5+Vector3.UP*0.05
	n.rotation.y=atan2(b.x-a.x,b.z-a.z)
	n.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for side in [-1,1]:
		var edge:=MeshInstance3D.new()
		var border:=BoxMesh.new()
		border.size=Vector3(0.10,0.015,shape.size.z)
		edge.mesh=border
		var trim:=StandardMaterial3D.new()
		trim.albedo_color=Color("a09276")
		edge.material_override=trim
		n.add_child(edge)
		edge.position=Vector3(side*width*0.5,0.04,0)
		edge.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
func rest(root: Node3D,at: Vector3) -> void:
	item(root,"brownwoodbench",at,3,true)
	item(root,"curlyironstreetlamp01",at+Vector3(2,0,0),3.5,true)
	item(root,"thicketgrass_03",at+Vector3(-2,0,0),2)
func build(terrain: Node3D) -> void:
	source=terrain
	grand_stair()
	var hub:=zone("hub_plaza",Vector3.ZERO)
	var old_children:=source.get_child_count()
	source.build_orrery(Vector3.ZERO)
	for child in source.get_children().slice(old_children):
		child.reparent(hub,true)
	# Main entry and two subordinate service spokes.
	path(hub,Vector3(0,0,25),Vector3(0,0,5),5.5)
	path(hub,Vector3(-5,0,0),Vector3(-21,0,-9),3)
	path(hub,Vector3(5,0,0),Vector3(23,0,-9),3)
	for side in [-1,1]:
		rest(hub,Vector3(side*17,0,12))
		item(hub,"castledoor_blueflag",Vector3(side*8,0,-13),4)
	item(hub,"bookstand",Vector3(-7,0,3),1.3)
	item(hub,"castlehousesignboard01",Vector3(10,0,2),2)
	var homes:=zone("residential_upper_left",Vector3(-65,8,-30))
	house(homes,Vector3(-11,0,-7),9,0,Vector3.ZERO)
	house(homes,Vector3(10,0,-9),9,1,Vector3.ZERO)
	house(homes,Vector3(-10,0,8),8,2,Vector3.ZERO)
	path(homes,Vector3(0,0,11),Vector3(0,0,-9),3)
	path(homes,Vector3(-8,0,0),Vector3(8,0,0),2)
	rest(homes,Vector3(6,0,6))
	item(homes,"populus01",Vector3(-17,0,-14),7)
	garden_bed(homes,Vector3(14,0,10))
	item(homes,"flowerpot_1",Vector3(-6,0,5),1.5)
	var hall:=zone("academy_main_hall",Vector3(0,20,-134))
	house(hall,Vector3(0,0,-11),18,0,Vector3(0,0,12))
	for side in [-1,1]:
		item(hall,"castledoor_maintower",Vector3(side*12,0,-11),15,true)
		item(hall,"shizhu01",Vector3(side*9,0,1),4,true)
		item(hall,"castledoor_blueflag",Vector3(side*7,0,8),5)
	path(hall,Vector3(0,0,15),Vector3(0,0,-2),6)
	var approach:=zone("academy_approach",Vector3(-38,14,-83))
	path(approach,Vector3(0,0,15),Vector3(0,0,-14),5)
	for side in [-1,1]:
		item(approach,"castledoor_sidetower",Vector3(side*12,0,-7),9,true)
		item(approach,"castledoor_blueflag",Vector3(side*8,0,8),4)
	var market:=zone("market_lower_right",Vector3(75,6,-32))
	var revision:=preload("res://scripts/fusion_3d/market_courtyard_revision.gd").new()
	revision.name="RiverMarketCourtyard"
	market.add_child(revision)
	revision.build(self,market)
	var gate:=zone("worldgate_upper_right",Vector3(32,12,-83))
	item(gate,"castledoor_citygate",Vector3(0,0,-11),14,true)
	item(gate,"chuansongjitan",Vector3(0,0,-4),5)
	for side in [-1,1]:
		item(gate,"fengmozhu_storm",Vector3(side*8,0,-7),5,true)
		item(gate,"castledoor_blueflag",Vector3(side*8,0,3),4)
	path(gate,Vector3(0,0,17),Vector3(0,0,-2),5)
	var garden:=zone("garden_lower_left",Vector3(-64,-6,30))
	rest(garden,Vector3(-17,0,5))
	item(garden,"populus02",Vector3(-19,0,-3),7)

func garden_bed(root: Node3D,at: Vector3) -> void:
	var base:=MeshInstance3D.new()
	var shape:=BoxMesh.new()
	shape.size=Vector3(7,0.16,5)
	base.mesh=shape
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=Color("405e4b")
	mat.roughness=1.0
	base.material_override=mat
	root.add_child(base)
	base.position=at+Vector3.UP*0.08
	base.name="planted_courtyard_edge"
	for x in [-2,0,2]:
		item(root,"thicketgrass_03",at+Vector3(x,0.15,0),1.6)
func grand_stair() -> void:
	var root:=zone("main_story_stair_axis",Vector3.ZERO)
	var a:=Vector3(0,0,-25)
	var b:=Vector3(0,20,-114)
	var n:=MeshInstance3D.new()
	var ramp:=BoxMesh.new()
	ramp.size=Vector3(5.5,0.4,a.distance_to(b))
	n.mesh=ramp
	n.material_override=source.art.paving
	root.add_child(n)
	n.position=(a+b)*0.5-Vector3.UP*0.2
	n.look_at(b-Vector3.UP*0.2)
	var body:=StaticBody3D.new()
	n.add_child(body)
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=ramp.size
	collision.shape=shape
	body.add_child(collision)
	for i in 100:
		var t:=float(i)/99.0
		var step:=MeshInstance3D.new()
		var slab:=BoxMesh.new()
		slab.size=Vector3(5.8,0.16,0.91)
		step.mesh=slab
		step.material_override=source.art.paving
		root.add_child(step)
		step.position=a.lerp(b,t)-Vector3.UP*0.08
		step.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
