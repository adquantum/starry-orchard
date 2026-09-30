extends Node3D
## Normalizes converted meshes without changing their source files.
static func place(parent: Node3D, id: String, at: Vector3, extent: float, by_height: bool=false, solid: bool=false, normalization: Dictionary={}) -> Node3D:
	var path := "res://assets/models/world_one/"+id+".glb"
	if not ResourceLoader.exists(path):path=preload("res://scripts/fusion_3d/character_library.gd").model_path(id)
	if path.is_empty() or not ResourceLoader.exists(path):return null
	var holder := Node3D.new()
	holder.set_meta("world_one_asset",id)
	parent.add_child(holder)
	holder.position=at
	var model: Node3D=load(path).instantiate()
	holder.add_child(model)
	var source: String=preload("res://scripts/fusion_3d/character_library.gd").entry(id).get("source","")
	if source.contains("/cc/02human/"):model.rotate_x(-PI/2)
	var bounds := AABB()
	var found := false
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var box: AABB=holder.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		bounds=box if not found else bounds.merge(box)
		found=true
	# Some skinned exports have a bind-pose AABB far outside their visible idle
	# pose. Use an audited pose box for those assets only, preserving the mesh.
	var pose_bounds: Dictionary=normalization.get("normalization_bounds",{})
	if pose_bounds.has("position") and pose_bounds.has("size"):
		var origin: Array=pose_bounds.position
		var dimensions: Array=pose_bounds.size
		if origin.size()==3 and dimensions.size()==3 and float(dimensions[0])>0 and float(dimensions[1])>0 and float(dimensions[2])>0:
			bounds=AABB(Vector3(float(origin[0]),float(origin[1]),float(origin[2])),Vector3(float(dimensions[0]),float(dimensions[1]),float(dimensions[2])))
			found=true
	if found:
		var dimension: float=bounds.size.y if by_height else maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
		var factor: float=extent/maxf(dimension,0.01)
		if by_height:factor=minf(factor,float(normalization.get("max_horizontal_span",3.5))/maxf(0.01,maxf(bounds.size.x,bounds.size.z)))
		holder.set_meta("normalized_size",bounds.size*factor)
		model.scale*=factor
		model.position-=Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)*factor
		if solid:
			var body:=StaticBody3D.new();holder.add_child(body)
			var shape:=BoxShape3D.new();shape.size=Vector3(maxf(0.6,bounds.size.x*factor*0.72),maxf(1,bounds.size.y*factor*0.8),maxf(0.6,bounds.size.z*factor*0.72))
			var collision:=CollisionShape3D.new();collision.shape=shape;collision.position.y=shape.size.y/2;body.add_child(collision)
	var painted_id: String=preload("res://scripts/fusion_3d/character_library.gd").entry(id).get("existing_painted","")
	preload("res://scripts/fusion_3d/world_one_lowpoly.gd").auto_apply(holder,painted_id if not painted_id.is_empty() else id)
	return holder
