extends Node3D
const Landform := preload("res://scripts/worlds/orchard_coastal_landform.gd")
const Terrain := preload("res://scripts/worlds/orchard_main_terrain.gd")
const STEP := 4.0
var world: Node3D
var islands: Array[Dictionary]=[]
var bridge_start := Vector3(586,221.5,-211)
var bridge_end := Vector3(510,223.2,-211)
var timber: StandardMaterial3D
var bridge_ready := false

func install(target: Node3D, plant: bool = true) -> void:
	world=target
	name="OrchardCoastalExpansion"
	for profile in preload("res://scripts/worlds/orchard_coastal_catalog.gd").profiles():
		_build_island(profile,plant)
	bridge_start.y=world._height(bridge_start)
	_build_bridge()
	bridge_ready=true
	for spec in islands:
		var landing: Vector2=spec.form.route[0]
		world.destinations.append(Vector3(landing.x,sample(spec,landing)+1,landing.y))
		world.destination_names.append(str(spec.profile.name)+" · 登陆点")
	set_meta("generation_seed",9262101)
	set_meta("generated_from_functions",true)

func _build_island(profile: Dictionary, plant: bool) -> void:
	var form := Landform.new(true,int(profile.id))
	var west := form.west
	var start: Vector2=profile.start
	var cells: Vector2i=profile.cells
	var width := cells.x+1
	var heights := PackedFloat32Array()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for z in range(cells.y+1):
		for x in range(width):
			var p := start+Vector2(x,z)*STEP
			var h := form.height(p)
			heights.append(h)
			vertices.append(Vector3(p.x,h,p.y))
			var dx := form.height(p+Vector2(STEP,0))-form.height(p-Vector2(STEP,0))
			var dz := form.height(p+Vector2(0,STEP))-form.height(p-Vector2(0,STEP))
			normals.append(Vector3(-dx,2*STEP,-dz).normalized())
			colors.append(Color(0,(1.0-smoothstep(4,11,form.path_distance(p)))*smoothstep(221,227,h),form.battle_weight(p),1))
			uv.append(p*0.01)
	for z in cells.y:
		for x in cells.x:
			var a := z*width+x
			# Stop in submerged slopes; avoid coplanar ocean-floor geometry.
			if maxf(maxf(heights[a],heights[a+1]),maxf(heights[a+width],heights[a+width+1]))<=199:continue
			indices.append_array(PackedInt32Array([a,a+1,a+width,a+1,a+width+1,a+width]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new()
	material.shader=load(Terrain.ROOT+"ground.gdshader")
	material.set_shader_parameter("grass",Terrain.asset_texture("res://assets/worlds/star_orchard/coastal_art_v2/ground_%s_imagegen.png"%str(profile.school)))
	material.set_shader_parameter("school_ground",true)
	material.set_shader_parameter("soil",Terrain.texture("orchard_soil_generated.png"))
	material.set_shader_parameter("cliff_texture",Terrain.asset_texture("res://assets/worlds/star_orchard/coastal_art_v2/cliff_imagegen.png"))
	material.set_shader_parameter("plaza_enabled",false)
	var node := MeshInstance3D.new()
	node.name="CoastalTerrain_%d"%int(profile.id)
	node.mesh=mesh
	node.material_override=material
	add_child(node)
	node.create_trimesh_collision()
	var spec := {"west":west,"profile":profile,"start":start,"cells":cells,"width":width,"heights":heights,"form":form,"node":node,"tree_sites":[]}
	islands.append(spec)
	for court in form.courts:
		var marker := Marker3D.new()
		marker.name=str(court.id)
		marker.position=Vector3(court.center.x,court.height,court.center.y)
		marker.set_meta("reserved_battle_site",court.duplicate(true))
		add_child(marker)
	if plant:_plant_groves(spec)

func sample(spec: Dictionary, at: Vector2) -> float:
	var grid: Vector2=(at-spec.start)/STEP
	var x := floori(grid.x)
	var z := floori(grid.y)
	if x<0 or z<0 or x>=spec.cells.x or z>=spec.cells.y:return -INF
	var a: int=z*spec.width+x
	var h: PackedFloat32Array=spec.heights
	if maxf(maxf(h[a],h[a+1]),maxf(h[a+spec.width],h[a+spec.width+1]))<=199:return -INF
	var u := grid.x-x
	var v := grid.y-z
	if u+v<=1:return h[a]+(h[a+1]-h[a])*u+(h[a+spec.width]-h[a])*v
	return h[a+spec.width+1]+(h[a+spec.width]-h[a+spec.width+1])*(1-u)+(h[a+1]-h[a+spec.width+1])*(1-v)

func surface_height(at: Vector3) -> float:
	var result := -INF
	var t := (at.x-bridge_start.x)/(bridge_end.x-bridge_start.x)
	if bridge_ready and t>=0 and t<=1 and absf(at.z-bridge_start.z)<=4.0:
		result=lerpf(bridge_start.y,bridge_end.y,t)
	for spec in islands:result=maxf(result,sample(spec,Vector2(at.x,at.z)))
	return result

func _plant_groves(spec: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed=9262151+int(spec.profile.id)
	var sites: Array[Vector2]=[]
	var batches: Dictionary={}
	var target := 58 if spec.west else 78
	for attempt in 1800:
		if sites.size()>=target:break
		var at: Vector2=spec.start+Vector2(rng.randf()*spec.cells.x,rng.randf()*spec.cells.y)*STEP
		var h := sample(spec,at)
		if not is_finite(h) or h<227 or spec.form.path_distance(at)<19:continue
		var near_arena := false
		for court in spec.form.courts:
			if at.distance_to(court.center)<float(court.clear_radius)+18.0:near_arena=true
		if near_arena:continue
		var dx := sample(spec,at+Vector2(STEP,0))-sample(spec,at-Vector2(STEP,0))
		var dz := sample(spec,at+Vector2(0,STEP))-sample(spec,at-Vector2(0,STEP))
		if not is_finite(dx+dz) or Vector2(dx,dz).length()/(2*STEP)>0.43:continue
		if spec.form.broad.get_noise_2d(at.x+610,at.y-201)<-0.19:continue
		var occupied := false
		for existing in sites:
			if existing.distance_to(at)<22:occupied=true;break
		if occupied:continue
		sites.append(at)
		var school := str(spec.profile.school)
		var variant := "A" if sites.size()%2==0 else "B"
		var key := school+variant
		if not batches.has(key):batches[key]={"parts":world._v4_parts(school,variant),"alternate":variant=="B","transforms":[]}
		var parts: Array=batches[key].parts
		var bounds := AABB()
		var first := true
		for part in parts:
			var box: AABB=part.transform*part.mesh.get_aabb()
			bounds=box if first else bounds.merge(box)
			first=false
		var tree_height := rng.randf_range(19,30)
		var factor := tree_height/maxf(bounds.size.y,0.01)
		var basis := Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3(1.08,1.0,1.08)*factor)
		batches[key].transforms.append(Transform3D(basis,Vector3(at.x,h-bounds.position.y*factor-0.05,at.y)))
		var body := StaticBody3D.new()
		body.position=Vector3(at.x,h,at.y)
		add_child(body)
		var shape := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius=0.75
		cylinder.height=tree_height*0.4
		shape.shape=cylinder
		shape.position.y=cylinder.height*0.5
		body.add_child(shape)
	for batch in batches.values():
		for part in batch.parts:
			var mm := MultiMesh.new()
			mm.transform_format=MultiMesh.TRANSFORM_3D
			mm.mesh=preload("res://scripts/worlds/orchard_coastal_tree_style.gd").variant_mesh(part.mesh,bool(batch.alternate))
			mm.instance_count=batch.transforms.size()
			for i in batch.transforms.size():mm.set_instance_transform(i,batch.transforms[i]*part.transform)
			var display := MultiMeshInstance3D.new()
			display.multimesh=mm
			display.set_meta("orchard_school",spec.profile.school)
			display.set_meta("foliage_variant","B" if batch.alternate else "A")
			add_child(display)
	spec["tree_count"]=sites.size()
	spec["tree_sites"]=sites

func _beam(a: Vector3,b: Vector3,width: float,thickness: float) -> void:
	var x := (b-a).normalized()
	var z := x.cross(Vector3.UP).normalized()
	var mesh := BoxMesh.new()
	mesh.size=Vector3(a.distance_to(b),thickness,width)
	var node := MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=timber
	node.transform=Transform3D(Basis(x,z.cross(x),z),(a+b)*0.5)
	add_child(node)
	node.create_trimesh_collision()

func _build_bridge() -> void:
	timber=StandardMaterial3D.new()
	timber.albedo_texture=load("res://assets/worlds/star_orchard/theme_v1/ZhanCheMuCai.png")
	timber.roughness=1.0
	timber.uv1_triplanar=true
	timber.uv1_scale=Vector3.ONE*0.15
	_beam(bridge_start-Vector3.UP*0.22,bridge_end-Vector3.UP*0.22,8.0,0.44)
	for side in [-1.0,1.0]:
		_beam(bridge_start+Vector3(0,1.25,side*4),bridge_end+Vector3(0,1.25,side*4),0.20,0.22)
	for i in 9:
		var at := bridge_start.lerp(bridge_end,float(i)/8.0)
		for side in [-1.0,1.0]:
			var mesh := BoxMesh.new()
			mesh.size=Vector3(0.5,at.y-190.0+1.4,0.5)
			var node := MeshInstance3D.new()
			node.mesh=mesh
			node.material_override=timber
			node.position=Vector3(at.x,190+mesh.size.y*0.5,at.z+side*3.85)
			add_child(node)
			node.create_trimesh_collision()
