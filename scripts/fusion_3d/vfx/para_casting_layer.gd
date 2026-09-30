extends Node3D
# Approved casting effect playback. Source assets are cached; each instance owns animation state.
static var data_cache: Dictionary={}
static var texture_cache: Dictionary={}
static var blend_shaders: Dictionary={}
var bounds_owner: Node3D
var orbit_particles: bool=false
var source_radius: float=3.52
var particle_limit: int=48
var particle_pool: Array=[]
var data: Dictionary
var skeleton: Skeleton3D
var mats: Array=[]
var rest_positions: Array=[]
var elapsed: float=0.0
var duration: float=3.0
var particle_states: Array=[]
var live: Array=[]
var rng=RandomNumberGenerator.new()
var opacity: float=1.0
var warnings: Array=[]
var particle_size_factor: float=1
var particle_rate_factor: float=1
func v3(a):return Vector3(float(a[0]),float(a[1]),float(a[2]))
func sample(track,time,default):
	if track.is_empty() or track.values.is_empty():return default
	var ts=track.times
	var values=track.values
	if ts.size()==1:return values[0]
	var t=time
	if int(track.seq)!=65535 and int(track.seq)!=4294967295 and float(ts[-1])>0:t=fmod(t,float(ts[-1]))
	var k=0
	while k<ts.size()-2 and float(ts[k+1])<t:k+=1
	if t<=float(ts[0]):return values[0]
	if t>=float(ts[-1]):return values[-1]
	if int(track.type)==0:return values[k]
	var f=clampf((t-float(ts[k]))/maxf(1,float(ts[k+1])-float(ts[k])),0,1)
	var out=[]
	if values[k].size()==4:
		var a=values[k];var b=values[k+1]
		var q=Quaternion(a[0],a[1],a[2],a[3]).normalized().slerp(Quaternion(b[0],b[1],b[2],b[3]).normalized(),f)
		return [q.x,q.y,q.z,q.w]
	for j in values[k].size():out.append(lerpf(float(values[k][j]),float(values[k+1][j]),f))
	return out
func texture_at(index):
	if index<0 or index>=data.textures.size() or data.textures[index]==null:return null
	var path=str(data.textures[index])
	if not texture_cache.has(path):texture_cache[path]=load(path)
	return texture_cache[path]
func make_material(tex,blend):
	var key=3 if int(blend) in [3,4] else 2
	if not blend_shaders.has(key):
		var shader=Shader.new()
		shader.code=FileAccess.get_file_as_string("res://scripts/fusion_3d/vfx/casting_surface.gdshader").replace("blend_mix","blend_add" if key==3 else "blend_mix")
		blend_shaders[key]=shader
	var mat=ShaderMaterial.new();mat.shader=blend_shaders[key]
	mat.set_shader_parameter("effect_texture",tex)
	return mat
func update_bounds(mat):
	if bounds_owner==null:return
	mat.set_shader_parameter("effect_center",bounds_owner.global_position)
	mat.set_shader_parameter("effect_radius",bounds_owner.world_radius())
	mat.set_shader_parameter("inner_clear_radius",bounds_owner.world_radius()*.62 if bounds_owner.school=="balance" else 0.0)
func load_effect(path):
	rng.seed=57291
	if not data_cache.has(path):data_cache[path]=JSON.parse_string(FileAccess.get_file_as_string(path))
	data=data_cache[path]
	warnings=data.warnings
	if not data.animations.is_empty():duration=maxf(.1,float(data.animations[0][2]-data.animations[0][1])/1000.0)
	skeleton=Skeleton3D.new();add_child(skeleton)
	for i in data.bones.size():skeleton.add_bone("bone_%03d"%i)
	var skin=Skin.new()
	for i in data.bones.size():
		var b=data.bones[i];var pivot=v3(b.pivot);var par=int(b.parent)
		var rest=pivot
		if par>=0 and par<data.bones.size():
			skeleton.set_bone_parent(i,par);rest-=v3(data.bones[par].pivot)
		rest_positions.append(rest)
		skeleton.set_bone_rest(i,Transform3D(Basis.IDENTITY,rest))
		skin.add_bind(i,Transform3D(Basis.IDENTITY,-pivot))
	if not data.vertices.is_empty():
		var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
		var positions=PackedVector3Array();var uv=PackedVector2Array();var bones=PackedInt32Array();var weights=PackedFloat32Array()
		for vertex in data.vertices:
			positions.append(v3(vertex));uv.append(Vector2(vertex[14],vertex[15]))
			var total=maxf(1,vertex[3]+vertex[4]+vertex[5]+vertex[6])
			for j in 4:
				bones.append(int(vertex[7+j]) if float(vertex[3+j])>0 else 0)
				weights.append(float(vertex[3+j])/total)
		arrays[Mesh.ARRAY_VERTEX]=positions;arrays[Mesh.ARRAY_TEX_UV]=uv
		if not data.bones.is_empty():arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights
		for p in data.passes:
			if int(p[1])==0:continue
			var indices=PackedInt32Array()
			for j in range(int(p[0]),int(p[0])+int(p[1])):indices.append(int(data.indices[j]))
			arrays[Mesh.ARRAY_INDEX]=indices
			var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			var instance=MeshInstance3D.new();instance.mesh=mesh;instance.skin=skin
			skeleton.add_child(instance);instance.skeleton=instance.get_path_to(skeleton)
			instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat=make_material(texture_at(int(p[4])),p[9]);instance.material_override=mat
			mats.append({'mat':mat,'pass':p})
	for p in data.particles:particle_states.append({'def':p,'acc':0.0})
	update_pose(0)
func update_pose(time):
	for i in data.bones.size():
		var b=data.bones[i];var t=sample(b.t,time,[0,0,0]);var r=sample(b.r,time,[0,0,0,1]);var s=sample(b.s,time,[1,1,1])
		skeleton.set_bone_pose_position(i,rest_positions[i]+v3(t))
		skeleton.set_bone_pose_rotation(i,Quaternion(-r[0],-r[1],-r[2],r[3]).normalized())
		skeleton.set_bone_pose_scale(i,v3(s))
	skeleton.force_update_all_bone_transforms()
	for row in mats:
		var p=row.pass;var mat=row.mat;var alpha=opacity;var color=Color.WHITE
		if int(p[8])>=0 and int(p[8])<data.opacity.size():alpha*=float(sample(data.opacity[int(p[8])],time,[1])[0])
		if int(p[7])>=0 and int(p[7])<data.colors.size():
			var c=data.colors[int(p[7])];var rgb=sample(c.rgb,time,[1,1,1]);color=Color(rgb[0],rgb[1],rgb[2]);alpha*=float(sample(c.alpha,time,[1])[0])
		color.a=clampf(alpha,0,1);mat.set_shader_parameter("tint",color);update_bounds(mat)
		if int(p[6])>=0 and int(p[6])<data.texanims.size():
			var a=data.texanims[int(p[6])];mat.set_shader_parameter("uv_offset",v3(sample(a.t,time,[0,0,0])));mat.set_shader_parameter("uv_scale",v3(sample(a.s,time,[1,1,1])))
func particle_value(p,index,time,fallback):return float(sample(p.params[index],time,[fallback])[0])
func color_argb(n):
	var v=int(n);return Color(float((v>>16)&255)/255,float((v>>8)&255)/255,float(v&255)/255,float((v>>24)&255)/255)
func spawn_particle(p,time):
	var life=1.5 if orbit_particles else clampf(particle_value(p,5,time,1),.05,3)
	var speed=particle_value(p,0,time,0)*(1+rng.randf_range(-1,1)*particle_value(p,1,time,0))
	var pos=v3(p.pos);var basis=Basis.IDENTITY;var par=int(p.bone)
	var transform=Transform3D.IDENTITY
	if par>=0 and par<data.bones.size():
		transform=skeleton.get_bone_global_pose(par)*Transform3D(Basis.IDENTITY,-v3(data.bones[par].pivot));basis=transform.basis.orthonormalized()
	var w=particle_value(p,8,time,0)*.5;var h=particle_value(p,7,time,0)*.5
	pos+=Vector3(rng.randf_range(-w,w),0,rng.randf_range(-h,h));pos=transform*pos
	var direction=Vector3.DOWN
	if int(p.type)==2:direction=Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
	var node: MeshInstance3D
	if particle_pool.is_empty():
		node=MeshInstance3D.new();var quad=QuadMesh.new();quad.size=Vector2.ONE;node.mesh=quad;add_child(node)
	else:node=particle_pool.pop_back();node.show()
	var mat=make_material(texture_at(int(p.texture)),p.blend)
	if (int(p.flags)&4096)==0:mat.set_shader_parameter("billboard",true)
	else:node.rotation.x=-PI/2
	var cols=maxi(1,int(p.cols));var rows=maxi(1,int(p.rows));var tile=rng.randi_range(0,cols*rows-1)
	mat.set_shader_parameter("uv_scale",Vector3(1.0/cols,1.0/rows,1));mat.set_shader_parameter("uv_offset",Vector3(float(tile%cols)/cols,float(tile/cols)/rows,0))
	node.material_override=mat;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.position=pos
	live.append({'node':node,'mat':mat,'p':p,'age':0.0,'life':life,'speed':basis*direction*speed,'gravity':particle_value(p,4,time,0),'orbit_angle':rng.randf_range(0,TAU)})
func _process(delta):
	if data.is_empty() or not is_visible_in_tree():return
	elapsed+=delta
	var time=fmod(elapsed,duration)*1000.0
	update_pose(time)
	for state in particle_states:
		var p=state.def;var rate=clampf(particle_value(p,6,time,0)*particle_rate_factor,0,120)
		state.acc+=delta*rate
		while state.acc>=1 and live.size()<particle_limit:
			state.acc-=1;spawn_particle(p,time)
		state.acc=minf(state.acc,2)
	for i in range(live.size()-1,-1,-1):
		var x=live[i];x.age+=delta
		if x.age>=x.life:x.node.hide();particle_pool.append(x.node);live.remove_at(i);continue
		if orbit_particles:
			x.orbit_angle+=delta*1.8
			var theta=float(x.orbit_angle)
			x.node.position=Vector3(cos(theta)*source_radius*.70,source_radius*(.38+.07*sin(theta*2)),sin(theta)*source_radius*.70)
		else:
			x.speed+=Vector3.DOWN*x.gravity*delta;x.node.position+=x.speed*delta
		var t=x.age/x.life;var mid=clampf(float(x.p.mid),.01,.99);var a=0 if t<mid else 1;var f=t/mid if t<mid else (t-mid)/(1-mid)
		var c=color_argb(x.p.colors[a]).lerp(color_argb(x.p.colors[a+1]),f);c.a*=opacity;x.mat.set_shader_parameter("tint",c);update_bounds(x.mat)
		var size=maxf(.001,lerpf(float(x.p.sizes[a]),float(x.p.sizes[a+1]),f));x.node.scale=Vector3.ONE*minf(size*particle_size_factor,source_radius*.34)

