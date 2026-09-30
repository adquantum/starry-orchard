extends Node3D
## Authored map variants assembled from existing tower props, never replacing the island.
const TITLES: Array[String]=["霜牙前庭","熔霜回廊","寒核祭坛"]
const ICE_A="res://assets/worlds/_shared_models/b6d91567ba5f5975_IceTeeth01.glb"
const ICE_B="res://assets/worlds/_shared_models/3ea67c45d013de5e_IceTeeth02.glb"
const TREE="res://assets/worlds/_shared_models/11cec96176ac3069_DeadTree01.glb"
const BLUE_FIRE="res://assets/worlds/_shared_models/c48f479305b133ec_BrazierFire_Blue.glb"
const FIRE="res://assets/worlds/_shared_models/59648f93ace08c88_BrazierFire.glb"
const STATION="res://assets/worlds/_shared_models/39a98b292906f578_FireStation.glb"
var room: Node3D
var floor_index:=0
var arena:=Vector3.ZERO
var environment: Environment
var prop_count:=0

func build(owner_room: Node3D,index: int,spot: Vector3) -> void:
	room=owner_room;floor_index=index;arena=spot
	name="TrialDressing_%d" % (index+1)
	environment=Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=[Color("193448"),Color("292437"),Color("101a38")][index]
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=[Color("bbd8e9"),Color("b7b8cc"),Color("adbfe0")][index]
	environment.ambient_light_energy=[0.8,0.65,0.65][index]
	environment.fog_enabled=true
	environment.fog_density=[0.006,0.005,0.007][index]
	environment.fog_light_color=[Color("476d87"),Color("665669"),Color("34446e")][index]
	if index==0:
		for i in 7:
			var angle:=PI+float(i)*PI/6.0
			prop(ICE_A if i%2==0 else ICE_B,Vector3(cos(angle)*30,0,sin(angle)*30),8+float(i%3)*2,angle)
		for x in [-22.0,22.0]:
			prop(BLUE_FIRE,Vector3(x,0,12),3.5,0)
			light(Vector3(x,4,12),Color("60c6ff"),3.5,17)
	elif index==1:
		for x in [-24.0,24.0]:
			for z in [-20.0,0.0,20.0]:
				prop(FIRE,Vector3(x,0,z),4.5,0)
				light(Vector3(x,5,z),Color("ff9857"),4.5,22)
			prop(TREE,Vector3(x*1.4,0,-14),11,0)
		prop(STATION,Vector3(0,0,-31),9,PI)
		prop(ICE_B,Vector3(-19,0,-30),8,PI/2)
		prop(ICE_A,Vector3(19,0,-30),8,-PI/2)
	else:
		for i in 9:
			var angle:=PI+float(i)*PI/8.0
			var offset:=Vector3(cos(angle)*29,0,sin(angle)*29-2)
			prop(ICE_A if i%2==0 else ICE_B,offset,10+float(i%3)*2,angle)
			if i%2==0:light(offset+Vector3.UP*5,Color("9389ff"),5,19)
		for x in [-22.0,22.0]:
			prop(BLUE_FIRE,Vector3(x,0,16),4.5,0)
			light(Vector3(x,5,16),Color("50e3ff"),4.5,22)
		ring(18.8,Color("5bbded"));ring(20.2,Color("b29bed"))
	weather(index)
	room._configure_branch(self)

func prop(path: String,offset: Vector3,height: float,angle: float) -> void:
	var packed: PackedScene=load(path)
	if packed==null:return
	var instance:=packed.instantiate()
	var parts: Array=[];room._collect_meshes(instance,Transform3D.IDENTITY,parts);instance.free()
	var bounds:=AABB();var first:=true
	for part in parts:
		var box: AABB=part.transform*part.mesh.get_aabb()
		bounds=box if first else bounds.merge(box);first=false
	if first or bounds.size.y<0.01:return
	var factor:=height/bounds.size.y
	var root:=Node3D.new();add_child(root)
	root.set_meta("source_asset",path)
	var point:=arena+offset
	point.y=room.ground_at(room.to_global(point))-room.global_position.y
	root.position=point;root.rotation.y=angle;root.scale=Vector3.ONE*factor
	var pivot:=Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	for part in parts:
		var mesh:=MeshInstance3D.new();mesh.mesh=part.mesh;mesh.transform=part.transform
		mesh.position-=pivot;root.add_child(mesh)
		var body:=StaticBody3D.new();body.collision_layer=0;body.collision_mask=0
		var shape:=CollisionShape3D.new();shape.shape=part.mesh.create_trimesh_shape()
		body.add_child(shape);mesh.add_child(body)
		var box: AABB=root.transform*mesh.transform*mesh.get_aabb()
		room.local_bounds=room.local_bounds.merge(box)
	prop_count+=1

func light(offset: Vector3,color: Color,energy: float,radius: float) -> void:
	var node:=OmniLight3D.new();node.position=arena+offset
	node.light_color=color;node.light_energy=energy;node.omni_range=radius
	node.light_cull_mask=1<<19;node.shadow_enabled=false;add_child(node)

func ring(radius: float,color: Color) -> void:
	var node:=MeshInstance3D.new();var mesh:=TorusMesh.new()
	mesh.inner_radius=radius-0.055;mesh.outer_radius=radius+0.055
	mesh.rings=80;mesh.ring_segments=6
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=color;material.emission_enabled=true;material.emission=color;material.emission_energy_multiplier=1.5
	mesh.material=material;node.mesh=mesh;node.position=arena+Vector3(0,0.08,0);add_child(node)

func weather(index: int) -> void:
	var particles:=CPUParticles3D.new();add_child(particles)
	particles.position=arena+Vector3.UP*8;particles.amount=[160,75,120][index]
	particles.lifetime=8;particles.preprocess=8
	particles.emission_shape=CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents=Vector3(34,5,30)
	particles.direction=Vector3(-0.3,-1,0.15) if index!=1 else Vector3(0.1,1,0)
	particles.gravity=Vector3(0,-0.03,0) if index!=1 else Vector3(0,0.04,0)
	particles.initial_velocity_min=0.5;particles.initial_velocity_max=1.2
	var mesh:=SphereMesh.new();mesh.radius=0.045;mesh.height=0.09;mesh.radial_segments=6;mesh.rings=3
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color=[Color("cae9f1"),Color("ffb867"),Color("b3b7ff")][index]
	mesh.material=material;particles.mesh=mesh;particles.emitting=true
