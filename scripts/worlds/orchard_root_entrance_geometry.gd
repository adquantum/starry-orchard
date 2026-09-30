extends RefCounted
## Cut only the short left entrance passage from the runtime mother-tree mesh.
## The source GLB is untouched; interpolated UVs/normals retain its bark texture.
const OPENING := AABB(Vector3(1061.5,337.0,-737.9),Vector3(16,8.3,7.8))
var cut_triangles := 0
var removed_arches: Array[String] = []

func apply(root: Node3D) -> Dictionary:
	for node in root.find_children("*","MeshInstance3D",true,false):
		var bounds: AABB = node.global_transform*node.mesh.get_aabb()
		if not bounds.intersects(OPENING): continue
		if str(node.name).begins_with("C_INST_SanctuaryPortal_"):
			removed_arches.append(str(node.name))
			node.get_parent().remove_child(node)
			node.free()
		elif str(node.name) == "V_HERO_AncientCherry__SM_VEG_01_ElderCherry":
			node.mesh = _cut_mesh(node)
			node.set_meta("root_door_aperture",OPENING)
	return {"cut_triangles":cut_triangles,"removed_arches":removed_arches,"opening":OPENING}

func _cut_mesh(node: MeshInstance3D) -> ArrayMesh:
	var output := ArrayMesh.new()
	var lo := OPENING.position
	var hi := OPENING.end
	var planes := [Plane(Vector3.LEFT,-lo.x),Plane(Vector3.RIGHT,hi.x),Plane(Vector3.DOWN,-lo.y),Plane(Vector3.UP,hi.y),Plane(Vector3.FORWARD,-lo.z),Plane(Vector3.BACK,hi.z)]
	for surface_index in node.mesh.get_surface_count():
		var arrays := node.mesh.surface_get_arrays(surface_index)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in vertices.size(): indices.append(index)
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		builder.set_material(node.get_active_material(surface_index))
		for offset in range(0,indices.size(),3):
			var polygon: Array = []
			for corner in 3:
				var index := indices[offset+corner]
				polygon.append({"p":vertices[index],"w":node.global_transform*vertices[index],"n":normals[index],"uv":uv[index] if not uv.is_empty() else Vector2.ZERO})
			var triangle_bounds := AABB(polygon[0].w,Vector3.ZERO)
			triangle_bounds = triangle_bounds.expand(polygon[1].w).expand(polygon[2].w)
			if not triangle_bounds.intersects(OPENING):
				_emit(builder,polygon)
				continue
			for plane in planes:
				if polygon.is_empty(): break
				var split := _split(polygon,plane)
				_emit(builder,split[1])
				polygon = split[0]
			if not polygon.is_empty(): cut_triangles += 1
		builder.generate_tangents()
		builder.index()
		builder.commit(output)
	return output

func _split(polygon: Array,plane: Plane) -> Array:
	var inner: Array = []
	var outer: Array = []
	for i in polygon.size():
		var a: Dictionary = polygon[i]
		var b: Dictionary = polygon[(i+1)%polygon.size()]
		var da := plane.distance_to(a.w)
		var db := plane.distance_to(b.w)
		if da<=0: inner.append(a)
		else: outer.append(a)
		if (da<0 and db>0) or (da>0 and db<0):
			var t := da/(da-db)
			var vertex := {"p":a.p.lerp(b.p,t),"w":a.w.lerp(b.w,t),"n":a.n.lerp(b.n,t).normalized(),"uv":a.uv.lerp(b.uv,t)}
			inner.append(vertex)
			outer.append(vertex)
	return [inner,outer]

func _emit(builder: SurfaceTool,polygon: Array) -> void:
	for index in range(1,polygon.size()-1):
		for vertex in [polygon[0],polygon[index],polygon[index+1]]:
			builder.set_normal(vertex.n)
			builder.set_uv(vertex.uv)
			builder.add_vertex(vertex.p)
