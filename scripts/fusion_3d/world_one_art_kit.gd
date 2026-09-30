extends Node3D
const Model=preload("res://scripts/fusion_3d/world_one_model.gd")
const TREES=["cedar_01","cedar_02","populus01","populus02"]
const BUSHES=["thicketgrass_01","thicketgrass_02","thicketgrass_03","thicketgrass_04","limegreenlowgrass1"]
const GRASSES=["limegreenlowgrass1","limegreenlowgrass3","thicketgrass_01","thicketgrass_02","thicketgrass_03","thicketgrass_04","limegreenlowgrass3"]
static func home(parent: Node3D, at: Vector3, extent: float, variant: int=0) -> Node3D:
	var root:=Node3D.new();parent.add_child(root);root.position=at
	var building:=Model.place(root,"castlehouse" if variant%3==0 else ("castlehouse01" if variant%3==1 else "castlehouse02"),Vector3.ZERO,extent,false,true)
	var size: Vector3=building.get_meta("normalized_size")
	var door:=Model.place(root,"castlehousedoor0"+str(variant%4+1),Vector3(0,0,size.z*0.5+0.03),minf(2.6,extent*0.3))
	var door_size: Vector3=door.get_meta("normalized_size")
	if door_size.x<door_size.z:door.rotation.y=PI/2
	# A small coherent service cluster; furniture stays beside the facade.
	Model.place(root,"castlehousefirewood",Vector3(size.x*0.3,0,size.z*0.53),extent*0.16)
	Model.place(root,"castlehousepot",Vector3(-size.x*0.32,0,size.z*0.56),extent*0.13)
	return root
static func landmark(parent: Node3D, at: Vector3, school: String) -> void:
	var district:=Node3D.new();district.name="SchoolLandmark_"+school;parent.add_child(district)
	if school=="life":
		Model.place(district,"magicschool_life",at+Vector3(0,0,-10),14,false,true)
		home(district,at+Vector3(11,0,-8),7,2)
	elif school=="headmaster":
		home(district,at+Vector3(0,0,-9),15)
		for side in [-1,1]:Model.place(district,"castledoor_maintower",at+Vector3(side*9,0,-13),16,false,true)
	else:
		if school in ["fire","ice","storm","myth","death"]:
			Model.place(district,"magicschool_"+school,at+Vector3(0,0,-10),14,false,true)
		else:
			home(district,at+Vector3(0,0,-10),12,0)
		if school=="fire":Model.place(district,"castlehousestove",at+Vector3(9,0,-12),6,false,true)
		elif school=="myth":Model.place(district,"castlehouseshelf02",at+Vector3(-9,0,-10),3)
		else:Model.place(district,"castledoor_sidetower",at+Vector3(9,0,-12),9,false,true)
	preload("res://scripts/fusion_3d/world_one_lowpoly.gd").apply(district,school if school!="headmaster" else "balance",true)
static func mesh(parent: Node3D, shape: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var node:=MeshInstance3D.new();node.mesh=shape;node.position=at
	var mat:=StandardMaterial3D.new();mat.albedo_color=color;mat.roughness=0.65;node.material_override=mat;parent.add_child(node);return node
static func valve(parent: Node3D, at: Vector3) -> Node3D:
	var root:=Node3D.new();parent.add_child(root);root.position=at
	var pipe:=CylinderMesh.new();pipe.top_radius=0.12;pipe.bottom_radius=0.12;pipe.height=1.3;mesh(root,pipe,Vector3(0,0.65,0),Color("5c7069"))
	var wheel:=TorusMesh.new();wheel.inner_radius=0.28;wheel.outer_radius=0.36
	var ring:=mesh(root,wheel,Vector3(0,1.2,0.12),Color("aa8952"));ring.rotation.x=PI/2
	for angle in [0.0,PI/2]:
		var spoke:=BoxMesh.new();spoke.size=Vector3(0.62,0.055,0.055);var node:=mesh(root,spoke,Vector3(0,1.2,0.12),Color("aa8952"));node.rotation.z=angle
	return root
static func task_prop(parent: Node3D, q: Dictionary, index: int, at: Vector3) -> Node3D:
	var id: String=q.id
	if id in ["greenhouse_valves","channel_trace","strange_pipe","mine_shutdown","beacon_fire"]:return valve(parent,at)
	if id=="beacon_ice":
		var root:=Node3D.new();parent.add_child(root);root.position=at
		Model.place(root,"castlehousewindow01",Vector3.ZERO,1.5)
		var mirror:=BoxMesh.new();mirror.size=Vector3(0.72,1.2,0.025)
		var face:=mesh(root,mirror,Vector3(0,0.8,0.12),Color("a1bac4"));face.material_override.metallic=0.85;face.material_override.roughness=0.12
		return root
	if id=="beacon_storm":return Model.place(parent,"fengmozhu_storm",at,2.2)
	if "grave" in id or id=="beacon_death":return Model.place(parent,"hurricanelamp",at,1.25)
	if id=="beacon_balance":return Model.place(parent,"fuwenstone0"+str(index+1),at,1.1)
	if id=="beacon_life" or "forest" in id:return Model.place(parent,BUSHES[index%5],at,0.9)
	if id=="restore_core":return Model.place(parent,"fengmozhu_life",at,1.4)
	return Model.place(parent,"bookstand",at,1.05)
static func side_prop(parent: Node3D, id: String, at: Vector3) -> Node3D:
	if id=="lamps" or id=="names":return Model.place(parent,"hurricanelamp",at,0.9)
	if id=="pet":return Model.place(parent,"thicketgrass_04",at,0.9)
	if id=="tools":return Model.place(parent,"castlehousefirewood",at,0.7)
	if id=="lunch":return Model.place(parent,"castlehousepot",at,0.6)
	return Model.place(parent,"bookstand",at,0.8)
