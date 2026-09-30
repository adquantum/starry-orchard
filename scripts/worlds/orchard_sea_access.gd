extends Node3D
## Short shore landings and explicit entrances into preserved isolated source interiors.
var world: Node3D
var satellites: Node3D
var config: Dictionary
var surfaces: Array[Dictionary] = []
var entrances: Array[Dictionary] = []
var interior_regions: Dictionary = {}
var interior_door_nodes: Dictionary = {}
var interior_extras: Dictionary = {}
var active_interior := ""
var cooldown := 0.0
var timber: StandardMaterial3D
var shore_material: StandardMaterial3D
var rock_style := preload("res://scripts/worlds/orchard_cloud_prop_style.gd").new()

static func point(a: Array) -> Vector3:
	return Vector3(float(a[0]),float(a[1]),float(a[2]))

func install(target: Node3D, host: Node3D) -> void:
	world=target
	satellites=host
	config=host.config
	name="OrchardSeaAccess"
	timber=StandardMaterial3D.new()
	timber.roughness=1.0
	timber.albedo_color=Color("b1a189")
	shore_material=StandardMaterial3D.new()
	shore_material.roughness=1.0
	shore_material.albedo_texture=load("res://assets/worlds/star_orchard/cloud_repaint/orchard_soil_generated.png")
	shore_material.uv1_triplanar=true
	shore_material.uv1_world_triplanar=true
	shore_material.uv1_scale=Vector3.ONE*0.035
	shore_material.vertex_color_use_as_albedo=true
	shore_material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var bridge := "res://assets/worlds/_shared_models/d5a9caa379378816_ELongChaoXue_muqiao.glb"
	for part in world.prototypes.get(bridge,[]):
		var source_material: Material=part.mesh.surface_get_material(0)
		if source_material is StandardMaterial3D and source_material.albedo_texture!=null:
			timber.albedo_texture=source_material.albedo_texture
			timber.albedo_color=Color.WHITE
			break
	_build_access(config.get("sea_main_access",{}),"main")
	for island in config.get("islands",[]):
		var mode := str(island.get("sea_access_mode","open"))
		if str(island.id)!="orchard_wind":
			_build_access(island.get("sea_access",{}),str(island.id),mode=="boarding")
		if mode=="cave":
			var extra_nodes: Array[Node3D]=[]
			for region in host.cloud_regions:
				if str(region.name)==str(island.id):
					interior_regions[str(island.id)]=region
					region.visible=false
			for child in host.get_children():
				if not child is Node3D:continue
				var belongs := str(child.get_meta("orchard_island_id",""))==str(island.id)
				if child is Label3D and str(island.name) in child.text and child.position.y>5000:belongs=true
				if belongs:
					extra_nodes.append(child)
					child.visible=false
			interior_extras[str(island.id)]=extra_nodes
		if mode not in ["cave","boarding"]:continue
		var path: Array=island.sea_access.path
		var outer := point(path[path.size()-1])
		var inside := point(island.inside_return)
		if mode=="cave":_reef_entrance(outer,str(island.id))
		entrances.append({"id":str(island.id),"from":outer,"to":point(island.inside_entry),"enter":true,"mode":mode})
		entrances.append({"id":str(island.id),"from":inside,"to":point(island.sea_entry)+Vector3(0,1.2,0),"enter":false,"mode":mode})
		# The rock opening itself is the entrance; avoid a freestanding box gate.
		_label(str(island.name)+( "\n走近登船" if mode=="boarding" else "\n走近进入洞穴"),outer+Vector3(0,7.5,0))
		var return_nodes := _door(inside,"返回近海码头\n走近离开",str(island.id)+"_return")
		if mode=="cave":
			interior_door_nodes[str(island.id)]=return_nodes
			for node in return_nodes:node.visible=false
	set_meta("sea_level",float(config.get("sea_level",220.0)))
	set_meta("source_geometry_preserved",true)
	_close_bear_shore()
	print("ORCHARD_SEA_ACCESS_READY landings=8 doors=",entrances.size())

func _reef_entrance(door: Vector3, id: String) -> void:
	var rock_path := "res://assets/worlds/_shared_models/3ce8a628d5ab450a_Stone01.glb"
	var parts: Array=world.prototypes.get(rock_path,[])
	var bounds := AABB()
	var first := true
	for part in parts:
		var box: AABB=part.transform*part.mesh.get_aabb()
		bounds=box if first else bounds.merge(box)
		first=false
	var top := float(config.get("sea_level",220.0))+0.25
	var bottom := float(config.get("sea_bed_level",190.0))
	var center := Vector3(door.x,top,door.z-6.0)
	# A low irregular shelf slopes below the water instead of a cylinder wall.
	var shelf := SurfaceTool.new()
	shelf.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sector in 48:
		var angle_a := TAU*float(sector)/48.0
		var angle_b := TAU*float(sector+1)/48.0
		var rings_a := _reef_profile(center,angle_a,top,bottom)
		var rings_b := _reef_profile(center,angle_b,top,bottom)
		for ring in range(rings_a.size()-1):
			for vertex in [rings_a[ring],rings_a[ring+1],rings_b[ring],rings_b[ring],rings_a[ring+1],rings_b[ring+1]]:
				shelf.set_color(Color("bab8a0"))
				shelf.add_vertex(vertex)
	shelf.generate_normals()
	_visual(shelf.commit(),shore_material,id+"_sea_reef",Vector3.ZERO,true)
	surfaces.append({"center":center,"radius":16.0})
	# Original stone models form the cave cheeks. Their inside edges leave >5.6m clear.
	if parts.is_empty():return
	for side in [-1.0,1.0]:
		for layer in 2:
			var height := 10.0+float(layer)*3.5
			var factor := height/maxf(bounds.size.y,0.01)
			factor=minf(factor,11.0/maxf(maxf(bounds.size.x,bounds.size.z),0.01))
			var x: float = float(side)*(3.25+bounds.size.x*factor*0.5)
			var at := Vector3(door.x+x,top,door.z-3.0-float(layer)*7.0)
			_reef_rock(parts,bounds,factor,at,id+"_cave_cheek")
	var crown_factor := 14.0/maxf(bounds.size.y,0.01)
	crown_factor=minf(crown_factor,16.0/maxf(maxf(bounds.size.x,bounds.size.z),0.01))
	# The rear face begins 4.5m behind the entrance; the 2.8m trigger is reached first.
	var back := Vector3(door.x,top,door.z-4.5-bounds.size.z*crown_factor*0.5)
	_reef_rock(parts,bounds,crown_factor,back,id+"_cave_back")
	# A broad overhead stone joins the cheeks into an actual cave silhouette.
	var cap_factor := 19.0/maxf(bounds.size.x,0.01)
	_reef_rock(parts,bounds,cap_factor,Vector3(door.x,top+8.0,door.z-6.0),id+"_cave_crown")

func _reef_profile(center: Vector3, angle: float, top: float, bottom: float) -> Array[Vector3]:
	var radial := Vector3(cos(angle),0,sin(angle))
	var irregular := 1.0+0.10*sin(angle*3.0)+0.055*cos(angle*7.0)
	return [center,Vector3(center.x,top,center.z)+radial*16.0,
		Vector3(center.x,top-1.8,center.z)+radial*24.0*irregular,
		Vector3(center.x,bottom-0.4,center.z)+radial*48.0*irregular]

func _reef_rock(parts: Array, bounds: AABB, factor: float, at: Vector3, title: String) -> void:
	var holder := Node3D.new()
	holder.name=title
	add_child(holder)
	holder.position=at-Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
	holder.scale=Vector3.ONE*factor
	for part in parts:
		var node := MeshInstance3D.new()
		node.mesh=rock_style.style_mesh("res://assets/worlds/_shared_models/3ce8a628d5ab450a_Stone01.glb",part.mesh)
		node.transform=part.transform
		holder.add_child(node)
		node.create_trimesh_collision()

func _close_bear_shore() -> void:
	# Close the imported heightfield's open border down to the common sea bed.
	# Its original top samples and authored object transforms remain unchanged.
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("b8c2ae")
	material.albedo_texture=load("res://assets/worlds/star_orchard/cloud_repaint/orchard_stone_generated.png")
	material.roughness=1.0
	material.uv1_triplanar=true
	material.uv1_scale=Vector3.ONE*0.08
	material.uv1_world_triplanar=true
	for region in satellites.cloud_regions:
		if str(region.name)!="orchard_start":continue
		for terrain in region.terrain_nodes:
			var arrays: Array=terrain.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var boundary: Dictionary={}
			for first in range(0,indices.size(),3):
				for edge in 3:
					var a := int(indices[first+edge])
					var b := int(indices[first+(edge+1)%3])
					var key := Vector2i(mini(a,b),maxi(a,b))
					if boundary.has(key):boundary.erase(key)
					else:boundary[key]=Vector2i(a,b)
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for pair: Vector2i in boundary.values():
				var a: Vector3=terrain.global_transform*vertices[pair.x]
				var b: Vector3=terrain.global_transform*vertices[pair.y]
				var lower_a := Vector3(a.x,float(config.get("sea_bed_level",190.0)),a.z)
				var lower_b := Vector3(b.x,lower_a.y,b.z)
				for vertex in [a,lower_a,b,b,lower_a,lower_b]:tool.add_vertex(vertex)
			tool.generate_normals()
			var wall := _visual(tool.commit(),material,"MielinOriginalShoreCliff",Vector3.ZERO,true)
			wall.set_meta("preserves_source_top",true)

func _build_access(spec: Dictionary, id: String, dock: bool = false) -> void:
	var path: Array=spec.get("path",[])
	if path.size()<2:return
	var width := float(spec.get("width",7.0))
	if not dock:
		_build_shore_path(path,width,id)
		_label(str(spec.get("label","海岛登陆点")),point(path[1])+Vector3(0,6.5,0))
		return
	for i in range(path.size()-1):_ramp(point(path[i]),point(path[i+1]),width,id+"_shore_%02d"%i)
	var landing: Vector3=point(path[1])
	var deck := BoxMesh.new()
	deck.size=Vector3(width+3,0.45,width+4)
	_visual(deck,timber,id+"_landing",landing-Vector3.UP*0.225,true)
	surfaces.append({"center":landing,"size":Vector2(width+3,width+4)})
	_label(str(spec.get("label","海岛登陆点")),landing+Vector3(0,6.5,0))

func _build_shore_path(path: Array, width: float, id: String) -> void:
	# A continuous walkable ridge with broad shoulders down to the seabed.
	# Shared sections at bends avoid overlapping separate ramp meshes.
	var centers: Array[Vector3]=[]
	for segment in range(path.size()-1):
		var start := point(path[segment])
		var finish := point(path[segment+1])
		var count := maxi(1,ceili(start.distance_to(finish)/6.0))
		for sample in count:centers.append(start.lerp(finish,float(sample)/float(count)))
		surfaces.append({"start":start,"finish":finish,"width":width})
	centers.append(point(path.back()))
	var sections: Array=[]
	var bed := float(config.get("sea_bed_level",190.0))-0.25
	for index in centers.size():
		var at := centers[index]
		var before := centers[maxi(0,index-1)]
		var after := centers[mini(centers.size()-1,index+1)]
		var tangent := Vector3(after.x-before.x,0,after.z-before.z).normalized()
		var side := Vector3(-tangent.z,0,tangent.x)
		var shoulder := 8.0+maxf(at.y-220.0,0.0)*0.65
		var spread := shoulder*(1.0+0.12*sin(float(index)*0.63))
		sections.append([Vector3(at.x,bed,at.z)-side*(width*0.5+spread+14.0),
			at-side*(width*0.5+spread)-Vector3.UP*minf(8.0,(at.y-bed)*0.45),
			at-side*width*0.5,at+side*width*0.5,
			at+side*(width*0.5+spread)-Vector3.UP*minf(8.0,(at.y-bed)*0.45),
			Vector3(at.x,bed,at.z)+side*(width*0.5+spread+14.0)])
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var colors := [Color("939c89"),Color("a7b29a"),Color("d9ceb1"),Color("d9ceb1"),Color("a7b29a"),Color("939c89")]
	for index in range(sections.size()-1):
		for lane in 5:
			for corner in [Vector2i(index,lane),Vector2i(index+1,lane),Vector2i(index+1,lane+1),Vector2i(index,lane),Vector2i(index+1,lane+1),Vector2i(index,lane+1)]:
				tool.set_color(colors[corner.y])
				tool.add_vertex(sections[corner.x][corner.y])
	tool.generate_normals()
	_visual(tool.commit(),shore_material,id+"_natural_shore",Vector3.ZERO,true)

func _ramp(start: Vector3, finish: Vector3, width: float, title: String) -> void:
	var direction := Vector2(finish.x-start.x,finish.z-start.z)
	if direction.length()<0.1:return
	var side := Vector3(-direction.y,0,direction.x).normalized()*width*0.5
	var a := start-side
	var b := start+side
	var c := finish+side
	var d := finish-side
	# Clockwise winding seen from above, independent of shoreline direction.
	var vertices := [a,b,c,a,c,d]
	if (b-a).cross(c-a).y>0:vertices=[a,c,b,a,d,c]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex: Vector3 in vertices:
		tool.set_uv(Vector2(vertex.x,vertex.z)*0.15)
		tool.add_vertex(vertex)
	tool.generate_normals()
	_visual(tool.commit(),timber,title,Vector3.ZERO,true)
	surfaces.append({"start":start,"finish":finish,"width":width})
	var count := maxi(1,ceili(direction.length()/22.0))
	for i in range(count+1):
		var at := start.lerp(finish,float(i)/count)
		if at.y<220.0:continue
		var length := maxf(2.0,at.y-float(config.get("sea_bed_level",190.0)))
		for sign_value in [-1.0,1.0]:
			var post := BoxMesh.new()
			post.size=Vector3(0.65,length,0.65)
			_visual(post,timber,title+"_timber",at+side*sign_value*0.78-Vector3.UP*(length*0.5+0.2),true)

func _visual(mesh: Mesh, material: Material, title: String, at: Vector3, solid: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name=title
	node.mesh=mesh
	node.material_override=material
	node.position=at
	add_child(node)
	if solid:node.create_trimesh_collision()
	return node

func _door(at: Vector3, title: String, id: String) -> Array[Node3D]:
	var first := get_child_count()
	var stone := StandardMaterial3D.new()
	stone.albedo_color=Color("857c69")
	stone.roughness=1.0
	for sign_value in [-1.0,1.0]:
		var post := BoxMesh.new()
		post.size=Vector3(0.9,5.2,1.1)
		_visual(post,stone,id+"_post",at+Vector3(sign_value*3.35,2.6,0),true)
	var lintel := BoxMesh.new()
	lintel.size=Vector3(7.6,0.8,1.1)
	_visual(lintel,stone,id+"_lintel",at+Vector3(0,5.3,0),true)
	_label(title,at+Vector3(0,7.5,0))
	var result: Array[Node3D]=[]
	for index in range(first,get_child_count()):result.append(get_child(index) as Node3D)
	return result

func _label(title: String, at: Vector3) -> void:
	var node := Label3D.new()
	node.text=title
	node.position=at
	node.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	node.font_size=28
	node.pixel_size=0.016
	node.modulate=Color("fff0cc")
	node.outline_size=7
	node.visibility_range_end=190
	add_child(node)

func surface_height(at: Vector3) -> float:
	var result := -INF
	for surface in surfaces:
		if surface.has("center"):
			var center: Vector3=surface.center
			if absf(at.y-center.y)>30.0 or center.y>at.y+4.0:continue
			if surface.has("radius"):
				if Vector2(at.x-center.x,at.z-center.z).length()<=float(surface.radius):result=maxf(result,center.y)
				continue
			var size: Vector2=surface.size
			if absf(at.x-center.x)<=size.x*0.5 and absf(at.z-center.z)<=size.y*0.5:result=maxf(result,center.y)
			continue
		var start: Vector3=surface.start
		var finish: Vector3=surface.finish
		var axis := Vector2(finish.x-start.x,finish.z-start.z)
		var delta := Vector2(at.x-start.x,at.z-start.z)
		var progress := delta.dot(axis)/axis.length_squared()
		if progress<0 or progress>1:continue
		if (delta-axis*progress).length()>float(surface.width)*0.5:continue
		var height := lerpf(start.y,finish.y,progress)
		if absf(at.y-height)>30.0 or height>at.y+4.0:continue
		result=maxf(result,height)
	return result

func _physics_process(delta: float) -> void:
	if not is_instance_valid(world) or not world.ready_world or world.input_suspended or not is_instance_valid(world.player):return
	cooldown=maxf(0,cooldown-delta)
	var at: Vector3=world.player.global_position
	var current := ""
	for island in config.get("islands",[]):
		if str(island.get("sea_access_mode",""))!="cave":continue
		var inside := point(island.inside_entry)
		if absf(at.y-inside.y)<650 and Vector2(at.x-inside.x,at.z-inside.z).length()<1600:current=str(island.id)
	active_interior=current
	world.set_meta("orchard_sea_interior",active_interior)
	for id in interior_regions:interior_regions[id].visible=(id==active_interior)
	for id in interior_door_nodes:
		for node in interior_door_nodes[id]:node.visible=(id==active_interior)
	for id in interior_extras:
		for node in interior_extras[id]:node.visible=(id==active_interior)
	# Interior return doors must be shown only in the corresponding content space.
	if cooldown>0:return
	for door in entrances:
		if absf(at.y-door.from.y)>5.0 or Vector2(at.x-door.from.x,at.z-door.from.z).length()>2.8:continue
		world._travel_gate(door.to)
		cooldown=2.5
		return
