extends MeshInstance3D
## Hanbok-only pose correction. Native body, skeleton and animation stay read-only.
## A skirt envelope follows the posed legs while the upper garment keeps its authored skin.
var driver: Skeleton3D
var source_arrays: Array
var source_skin: Skin
var source_material: Material
var bind_bones: PackedInt32Array
var donor_points: Array[Vector3]=[]
var donor_bones: Array[PackedInt32Array]=[]
var donor_weights: Array[PackedFloat32Array]=[]
var pelvis_id: int
var output_mesh: ArrayMesh
var skirt_mask: PackedByteArray
var upper_surfaces: Array[Array]=[]
var upper_materials: Array[Material]=[]
func configure(rig: Skeleton3D, parts: Dictionary) -> void:
	driver=rig;source_arrays=mesh.surface_get_arrays(0);source_skin=skin;source_material=get_active_material(0)
	for surface in range(1,mesh.get_surface_count()):
		upper_surfaces.append(mesh.surface_get_arrays(surface))
		upper_materials.append(get_active_material(surface))
	for b in source_skin.get_bind_count():bind_bones.append(driver.find_bone(source_skin.get_bind_name(b)))
	var vv: PackedVector3Array=source_arrays[Mesh.ARRAY_VERTEX]
	var jj0: PackedInt32Array=source_arrays[Mesh.ARRAY_BONES]
	var ww0: PackedFloat32Array=source_arrays[Mesh.ARRAY_WEIGHTS]
	for i in vv.size():
		var skirt: bool=vv[i].y<2.12
		for k in 4:
			if ww0[i*4+k]>.001 and driver.get_bone_name(bind_bones[jj0[i*4+k]]) not in ["Bone_001","Bone_002","Bone_003"]:skirt=false
		skirt_mask.append(1 if skirt else 0)
	pelvis_id=driver.find_bone("Bone_001")
	for shape in [898,598]:
		if not parts.has(shape):continue
		var part: MeshInstance3D=parts[shape]
		var arrays: Array=part.mesh.surface_get_arrays(0)
		var pp: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var jj: PackedInt32Array=arrays[Mesh.ARRAY_BONES]
		var ww: PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		var donor_skin: Skin=part.skin
		for i in pp.size():
			if pp[i].y>2.18:continue
			var ids:=PackedInt32Array();var weights:=PackedFloat32Array()
			for k in 4:
				var bind: int=jj[i*4+k]
				var bone: int=driver.find_bone(donor_skin.get_bind_name(bind))
				if bone<0:bone=donor_skin.get_bind_bone(bind)
				ids.append(bone);weights.append(ww[i*4+k])
			donor_points.append(pp[i]);donor_bones.append(ids);donor_weights.append(weights)
	skeleton=get_path_to(driver)
	driver.skeleton_updated.connect(update_pose)
	update_pose()
func update_pose() -> void:
	if not is_instance_valid(driver) or not driver.is_inside_tree():return
	var transforms: Array[Transform3D]=[]
	for i in driver.get_bone_count():transforms.append(driver.get_bone_global_pose(i)*driver.get_bone_global_rest(i).affine_inverse())
	var pelvis: Transform3D=transforms[pelvis_id]
	var inverse: Transform3D=pelvis.affine_inverse()
	# Cross sections in the pelvis rest coordinate system; margin includes triangle interiors.
	var forward:=PackedFloat32Array();var backward:=PackedFloat32Array();forward.resize(24);backward.resize(24)
	for i in donor_points.size():
		var pos:=Vector3.ZERO
		for k in 4:
			if donor_weights[i][k]>.00001:pos+=(transforms[donor_bones[i][k]]*donor_points[i])*donor_weights[i][k]
		pos=inverse*pos
		for h in range(maxi(0,int((pos.y-.42)/.08)),mini(24,int((pos.y-.08)/.08)+1)):
			var y: float=.25+float(h)*.08
			if absf(pos.y-y)<.17:
				forward[h]=maxf(forward[h],pos.x+.14);backward[h]=maxf(backward[h],-pos.x+.14)
	# Cloth drapes below a raised knee instead of folding back through the shin.
	for h in range(22,-1,-1):
		forward[h]=maxf(forward[h],forward[h+1]-.035)
		backward[h]=maxf(backward[h],backward[h+1]-.035)
	for smoothing_pass in 4:
		var f: PackedFloat32Array=forward.duplicate();var b: PackedFloat32Array=backward.duplicate()
		for h in range(1,23):
			forward[h]=(f[h-1]+f[h]*2+f[h+1])*.25
			backward[h]=(b[h-1]+b[h]*2+b[h+1])*.25
	var vertices: PackedVector3Array=source_arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array=source_arrays[Mesh.ARRAY_NORMAL]
	# Keep native skeletal skinning on the GPU. Only the skirt rest coordinates change.
	var posed: PackedVector3Array=vertices.duplicate()
	var new_normals: PackedVector3Array=normals.duplicate()
	for i in vertices.size():
		if not skirt_mask[i]:continue
		var p: Vector3=vertices[i]
		var h: float=clampf((p.y-.25)/.08,0,22.99)
		var front: float=lerpf(forward[int(h)],forward[int(h)+1],fmod(h,1.0))
		var back: float=lerpf(backward[int(h)],backward[int(h)+1],fmod(h,1.0))
		var correction: float=clampf((2.12-p.y)/.30,0,1)
		var rest_depth: float=.35+.19*clampf((2.0-p.y)/1.6,0,1)
		var bulge: float=maxf(0.0,(front if p.x>=0 else back)-rest_depth)*correction
		p.x+=signf(p.x)*bulge*pow(clampf(absf(p.x)/rest_depth,0,1),.45)
		p.y+=bulge*.25*clampf((1.65-p.y)/1.25,0,1)
		posed[i]=p
		var n: Vector3=normals[i]
		n.x/=1.0+bulge/rest_depth
		new_normals[i]=n.normalized()

	var arrays: Array=source_arrays.duplicate();arrays[Mesh.ARRAY_VERTEX]=posed;arrays[Mesh.ARRAY_NORMAL]=new_normals;arrays[Mesh.ARRAY_TANGENT]=null
	output_mesh=ArrayMesh.new();output_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);output_mesh.surface_set_material(0,source_material)
	for surface in upper_surfaces.size():
		output_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,upper_surfaces[surface])
		output_mesh.surface_set_material(surface+1,upper_materials[surface])
	mesh=output_mesh
