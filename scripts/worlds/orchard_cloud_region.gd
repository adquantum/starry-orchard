extends Node3D
## Imported cloud regions; the oasis pair additionally shares a joined runtime valley.
const TerrainMaterials = preload("res://scripts/worlds/orchard_cloud_terrain_materials.gd")
const PropStyle = preload("res://scripts/worlds/orchard_cloud_prop_style.gd")
const Oasis = preload("res://scripts/worlds/orchard_oasis_style.gd")
var world: Node3D
var source: Dictionary
var definition: Dictionary
var source_offset := Vector3.ZERO
var source_models: Array[Dictionary] = []
var terrain_nodes: Array[MeshInstance3D] = []
var terrain_data: Array[Dictionary] = []
var floor_cells: Dictionary = {}
var style: RefCounted
var presentation_meshes: Dictionary = {}
const CELL := 32.0

func install(target: Node3D, spec: Dictionary) -> void:
	world = target
	definition = spec
	name = str(spec.id)
	source_offset = _v(spec.source_offset)
	position = source_offset
	set_meta("source_world", spec.source_world)
	set_meta("source_offset", source_offset)
	set_meta("source_scale", Vector3.ONE)
	source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/worlds/"+str(spec.source_world)+"/world.json"))
	style = PropStyle.new()
	for tile in source.terrain:
		_build_tile(tile)
	_build_placements()
	if Oasis.is_oasis(definition):
		Oasis.plant_join_groves(self,world)
	set_meta("source_placement_count", source_models.size())
	set_meta("source_placement_indices", spec.source_placement_indices)

static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

func _inside_source(at: Vector3) -> bool:
	var b: Array = definition.source_bounds
	return at.x >= b[0] and at.z >= b[1] and at.x <= b[2] and at.z <= b[3]

func _build_tile(tile: Dictionary) -> void:
	var h := FileAccess.get_file_as_bytes(tile.height).to_float32_array()
	if h.size()!=16641:return
	# Legacy maps contain blank staging tiles; they are not authored land.
	var lo := h[0]
	var hi := lo
	for value in h:
		lo = minf(lo,value)
		hi = maxf(hi,value)
	if hi-lo < 0.001:return
	var size := float(source.tile_size)
	var step := size/128.0
	var start := Vector3(float(tile.tile[0])*size-float(source.origin[0]),0,float(tile.tile[1])*size-float(source.origin[1]))
	if Oasis.is_oasis(definition):
		for z in 129:
			for x in 129:
				var at := start+source_offset+Vector3(x*step,h[z*129+x],z*step)
				h[z*129+x]=Oasis.joined_height(at)-source_offset.y
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var selected_cells: Dictionary={}
	var use_selection := definition.has("source_terrain_cells")
	if use_selection:
		var tile_key := "%d,%d"%[tile.tile[0],tile.tile[1]]
		for cell in definition.source_terrain_cells.get(tile_key,[]):selected_cells[int(cell)]=true
	for z in 129:
		for x in 129:
			vertices.append(Vector3(x*step,h[z*129+x],z*step))
			normals.append(Vector3(h[z*129+maxi(x-1,0)]-h[z*129+mini(x+1,128)],2*step,h[maxi(z-1,0)*129+x]-h[mini(z+1,128)*129+x]).normalized())
			uv.append(Vector2(x,z)/128.0)
	for z in 128:
		for x in 128:
			var a := z*129+x
			var cell_world := start+source_offset+(vertices[a]+vertices[a+130])*0.5
			var join_fill := Oasis.is_oasis(definition) and absf(cell_world.x-Oasis.JOIN_X)<175.0 and absf(cell_world.z+130.0)<205.0
			if use_selection and not selected_cells.has(a) and not join_fill:continue
			if not _inside_source(start+vertices[a]) or not _inside_source(start+vertices[a+130]):continue
			if Oasis.is_oasis(definition) and not Oasis.keep_cell(definition,start+source_offset+(vertices[a]+vertices[a+130])*0.5):continue
			var staging_epsilon := 0.5 if str(definition.source_world).ends_with("_bearchieftain") else 0.001
			if maxf(maxf(absf(h[a]),absf(h[a+1])),maxf(absf(h[a+129]),absf(h[a+130]))) <= staging_epsilon:continue
			indices.append_array(PackedInt32Array([a,a+1,a+129,a+1,a+130,a+129]))
	if indices.is_empty():return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_TEX_UV]=uv
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node := MeshInstance3D.new()
	node.name="SourceTerrain_%d_%d" % [tile.tile[0],tile.tile[1]]
	node.mesh=mesh
	node.position=start
	node.material_override=TerrainMaterials.material_for(str(definition.source_world),str(tile.get("ground_texture",tile.get("texture",""))))
	if Oasis.is_oasis(definition):
		node.material_override=Oasis.ground_material()
	node.set_meta("source_height_path",tile.height)
	node.set_meta("source_tile",tile.tile)
	add_child(node)
	terrain_nodes.append(node)
	terrain_data.append({"start":start,"heights":h,"size":size})
	if str(definition.source_world).ends_with("_queensbattleship"):
		node.visible=false
		node.set_meta("source_presentation","hidden_staging_below_ship_deck")
		return
	node.create_trimesh_collision()
	_index_faces(mesh.get_faces(),Transform3D(Basis.IDENTITY,start))

func _parts(path: String) -> Array:
	if not world.prototypes.has(path):
		var scene := load(path) as PackedScene
		if scene==null:return []
		var instance := scene.instantiate()
		var parts: Array=[]
		world._collect_meshes(instance,Transform3D.IDENTITY,parts)
		instance.free()
		world.prototypes[path]=parts
	return world.prototypes[path]

func _build_placements() -> void:
	var groups: Dictionary={}
	for index in definition.source_placement_indices:
		var p: Dictionary=source.placements[int(index)]
		var m: Array=p.matrix
		var tr:=Transform3D(Basis(Vector3(m[0],m[1],m[2]),Vector3(m[3],m[4],m[5]),Vector3(m[6],m[7],m[8])),_v(p.position)+Vector3(m[9],m[10],m[11]))
		var path := str(p.get("model",""))
		source_models.append({"index":int(index),"model":path,"transform":tr,"solid":p.get("solid",false)})
		if Oasis.is_oasis(definition):
			var at := tr.origin+source_offset
			if not Oasis.keep_cell(definition,at) or absf(at.x-Oasis.JOIN_X)<175.0:continue
			if Oasis.is_tree_replacement(path):
				Oasis.plant_tree(self,world,path,tr,int(index)+(1001 if str(definition.id)=="orchard_wind_extension" else 0))
				continue
		# Preserve unresolved/effect placements as documented markers, without inventing geometry.
		if path.is_empty() or not ResourceLoader.exists(path):
			var marker := Marker3D.new()
			marker.name="SourceMarker_%04d"%int(index)
			marker.transform=tr
			marker.set_meta("source_placement",p.duplicate(true))
			add_child(marker)
			continue
		if not groups.has(path):groups[path]=[]
		groups[path].append(tr)
		var parts := _parts(path)
		var collision_path := _collision_path(path,parts)
		if bool(p.get("solid",false)):
			world.collision_pool.append({"path":collision_path,"source_model_path":path,"transform":Transform3D(Basis.IDENTITY,source_offset)*tr,"orchard_cloud_id":definition.id,"source_index":int(index)})
		# Floor sampling includes source architecture, not foliage / small props.
		if _floor_model(path):
			for part in world.prototypes[collision_path]:_index_faces(part.mesh.get_faces(),tr*part.transform)
	for path in groups:
		for part in _parts(path):
			var presented := _presentation_mesh(path,part.mesh)
			if presented == null:continue
			var mm := MultiMesh.new()
			mm.transform_format=MultiMesh.TRANSFORM_3D
			mm.mesh=style.style_mesh(path,presented)
			mm.instance_count=groups[path].size()
			for i in groups[path].size():mm.set_instance_transform(i,groups[path][i]*part.transform)
			var node := MultiMeshInstance3D.new()
			node.name=path.get_file().get_basename()
			node.multimesh=mm
			node.set_meta("source_model",path)
			add_child(node)

func _collision_path(path: String, parts: Array) -> String:
	if not path.ends_with("_HeNvWangFeiKongTingchuancang.glb") and not path.ends_with("_RongYanLianYu.glb"):return path
	var key := path+"::orchard_without_backdrop"
	if not world.prototypes.has(key):
		var filtered: Array=[]
		for part in parts:
			var mesh := _presentation_mesh(path,part.mesh)
			if mesh != null:filtered.append({"mesh":mesh,"transform":part.transform})
		world.prototypes[key]=filtered
	return key

func _presentation_mesh(path: String, mesh: Mesh) -> Mesh:
	# These two authored surfaces are source-world backdrop cards, not traversable land.
	var excluded: Array[String] = []
	if path.ends_with("_HeNvWangFeiKongTingchuancang.glb"):excluded=["4"]
	if path.ends_with("_RongYanLianYu.glb"):excluded=["RongYanLianYu01"]
	if excluded.is_empty():return mesh
	var key := path+":"+str(mesh.get_instance_id())
	if presentation_meshes.has(key):return presentation_meshes[key]
	var copy := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface)
		if material != null and material.resource_name in excluded:continue
		copy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.surface_get_arrays(surface))
		copy.surface_set_material(copy.get_surface_count()-1,material)
	if copy.get_surface_count()==0:
		# An empty backdrop part keeps its placement record but has no rendered surface.
		presentation_meshes[key]=null
		return null
	presentation_meshes[key]=copy
	return copy

func _floor_model(path: String) -> bool:
	for fragment in ["_ELongChaoXue.glb","_ELongChaoXuedashikuai","_ELongChaoXuexiaoshikuai","_ELongChaoXue_muqiao","_Xuanfudao02.glb","_RongYanLianYu.glb","_HeNvWangFeiKongTingchuancang.glb","_HeNvWangFeiKongTing0taizi.glb"]:
		if fragment in path:return true
	return false

func _index_faces(faces: PackedVector3Array, tr: Transform3D) -> void:
	for i in range(0,faces.size(),3):
		var a: Vector3=tr*faces[i]
		var b: Vector3=tr*faces[i+1]
		var c: Vector3=tr*faces[i+2]
		var cross: Vector3=(b-a).cross(c-a)
		# Godot clockwise winding: walkable top faces have a negative cross-product Y.
		if cross.y >= -0.0001:continue
		var first := Vector2i(floori(minf(a.x,minf(b.x,c.x))/CELL),floori(minf(a.z,minf(b.z,c.z))/CELL))
		var last := Vector2i(floori(maxf(a.x,maxf(b.x,c.x))/CELL),floori(maxf(a.z,maxf(b.z,c.z))/CELL))
		for z in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var cell := Vector2i(x,z)
				if not floor_cells.has(cell):floor_cells[cell]=[]
				floor_cells[cell].append([a,b,c])

func surface_height(at: Vector3) -> float:
	var local := at-source_offset
	var key := Vector2i(floori(local.x/CELL),floori(local.z/CELL))
	var result := -INF
	var upper := local.y+12.0
	for face in floor_cells.get(key,[]):
		var a: Vector3=face[0]
		var b: Vector3=face[1]
		var c: Vector3=face[2]
		var determinant := (b.z-c.z)*(a.x-c.x)+(c.x-b.x)*(a.z-c.z)
		var u := ((b.z-c.z)*(local.x-c.x)+(c.x-b.x)*(local.z-c.z))/determinant
		var v := ((c.z-a.z)*(local.x-c.x)+(a.x-c.x)*(local.z-c.z))/determinant
		if u < -0.0001 or v < -0.0001 or u+v > 1.0001:continue
		var y := u*a.y+v*b.y+(1.0-u-v)*c.y
		if y<=upper:result=maxf(result,y)
	return result+source_offset.y if is_finite(result) else -INF

func audit() -> Dictionary:
	return {"id":definition.id,"source_world":definition.source_world,"offset":source_offset,"placements":source_models.size(),"terrain_tiles":terrain_nodes.size(),"uniform_scale":1.0,"floor_cells":floor_cells.size()}
