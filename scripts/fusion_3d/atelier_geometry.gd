extends Node3D
## Explicit mesh profiles, tapered splines and polygon ornaments shared by art assets.
func mat(c: Color, metal: float=0.0, glow: float=0.0) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.albedo_color=c
	m.metallic=metal
	m.roughness=0.38 if metal>0 else 0.82
	if glow>0:
		m.emission_enabled=true
		m.emission=c
		m.emission_energy_multiplier=glow
	return m
func mesh_node(mesh: Mesh, at: Vector3, c: Color, parent: Node3D=null, metal: float=0.0, glow: float=0.0) -> MeshInstance3D:
	var n:=MeshInstance3D.new()
	n.mesh=mesh
	n.position=at
	n.material_override=mat(c,metal,glow)
	(self if parent==null else parent).add_child(n)
	return n
func block(at: Vector3, size_v: Vector3, c: Color, parent: Node3D=null, metal: float=0.0) -> MeshInstance3D:
	var m:=BoxMesh.new()
	m.size=size_v
	return mesh_node(m,at,c,parent,metal)
func ellipsoid(at: Vector3, size_v: Vector3, c: Color, parent: Node3D=null, glow: float=0.0) -> MeshInstance3D:
	var m:=SphereMesh.new()
	m.radius=0.5
	m.height=1
	m.radial_segments=12
	m.rings=6
	var n:=mesh_node(m,at,c,parent,0,glow)
	n.scale=size_v
	return n
func profile(at: Vector3, rings: Array, c: Color, segments: int=12, parent: Node3D=null, metal: float=0.0) -> MeshInstance3D:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings.size()-1:
		for i in segments:
			var v:Array[Vector3]=[]
			for pair in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i,j+1),Vector2i(i+1,j+1)]:
				var r:Vector4=rings[pair.y]
				var a:=float(pair.x)*TAU/segments
				v.append(Vector3(r.x+sin(a)*r.z,r.y,cos(a)*r.w))
			for index in [0,1,2,1,3,2]:
				st.set_uv(Vector2(float(i)/segments,float(j)/rings.size()))
				st.add_vertex(v[index])
	st.generate_normals()
	var n:=mesh_node(st.commit(),at,c,parent,metal)
	n.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
	return n
func spline(points: Array[Vector3], radii: Array[float], c: Color, parent: Node3D=null, metal: float=0.0) -> MeshInstance3D:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in points.size()-1:
		var direction:Vector3=(points[j+1]-points[j]).normalized()
		var axis:=Vector3.UP if absf(direction.y)<0.9 else Vector3.RIGHT
		var u:=direction.cross(axis).normalized()
		var v:=direction.cross(u).normalized()
		for i in 8:
			var vertices:Array[Vector3]=[]
			for pair in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i,j+1),Vector2i(i+1,j+1)]:
				var a:float=pair.x*TAU/8.0
				vertices.append(points[pair.y]+(u*cos(a)+v*sin(a))*radii[pair.y])
			for idx in [0,2,1,1,2,3]: st.add_vertex(vertices[idx])
	st.generate_normals()
	return mesh_node(st.commit(),Vector3.ZERO,c,parent,metal)
func shard(at: Vector3, size_v: Vector3, c: Color, parent: Node3D=null, glow: float=0.0) -> MeshInstance3D:
	var n:=profile(at,[Vector4(0,-0.5,0.01,0.01),Vector4(0,-0.20,0.50,0.42),Vector4(0,0.16,0.36,0.30),Vector4(0.08,0.5,0.001,0.001)],c,5,parent)
	n.scale=size_v
	if glow>0: n.material_override=mat(c,0.15,glow)
	return n
func ring(at: Vector3, radius: float, thickness: float, c: Color, parent: Node3D=null) -> MeshInstance3D:
	var m:=TorusMesh.new()
	m.inner_radius=radius-thickness
	m.outer_radius=radius
	m.rings=40
	m.ring_segments=6
	return mesh_node(m,at,c,parent,0.6)
func plate(points: Array[Vector3], c: Color, parent: Node3D=null) -> MeshInstance3D:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,points.size()-1):
		for point in [points[0],points[i],points[i+1]]: st.add_vertex(point)
	st.generate_normals()
	var n:=mesh_node(st.commit(),Vector3.ZERO,c,parent)
	n.material_override.cull_mode=BaseMaterial3D.CULL_DISABLED
	return n
func particles(at: Vector3, color: Color, count: int, spread: Vector3, velocity: Vector3, parent: Node3D=null) -> GPUParticles3D:
	var p:=GPUParticles3D.new()
	p.position=at
	p.amount=count
	p.lifetime=2.8
	p.preprocess=2
	p.visibility_aabb=AABB(-spread-Vector3.ONE*4,spread*2+Vector3.ONE*8)
	var process:=ParticleProcessMaterial.new()
	process.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents=spread
	process.direction=velocity.normalized()
	process.spread=25
	process.initial_velocity_min=velocity.length()*0.4
	process.initial_velocity_max=velocity.length()
	process.gravity=Vector3.ZERO
	process.scale_min=0.025
	process.scale_max=0.075
	process.color=color
	var gradient:=Gradient.new()
	gradient.set_color(0,Color(color,0))
	gradient.add_point(0.18,color)
	gradient.set_color(1,Color(color,0))
	var tex:=GradientTexture1D.new()
	tex.gradient=gradient
	process.color_ramp=tex
	p.process_material=process
	var m:=SphereMesh.new()
	m.radius=0.5
	m.height=1
	m.radial_segments=6
	m.rings=3
	m.material=mat(color,0,1.2)
	m.material.vertex_color_use_as_albedo=true
	m.material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	p.draw_pass_1=m
	(self if parent==null else parent).add_child(p)
	return p
