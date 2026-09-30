extends Node3D
## Shared school effects; approved assets replace only the explicitly selected casting stage.
var use_approved_casting: bool=false
var approved_casting: Node3D
var school:="fire"
var kind:="rune"
var diameter:=3.0
var subtle:=false
var opacity:=1.0:
	set(value):
		opacity=clampf(value,0,1)
		if approved_casting!=null:approved_casting.opacity=opacity
		if painted_sigil!=null:painted_sigil.modulate.a=opacity*(0.62 if subtle else 0.85)
		for material in materials:material.albedo_color.a=opacity*(0.58 if subtle else 0.9)
var materials: Array[StandardMaterial3D]=[]
var painted_sigil: Sprite3D

func add_painted_sigil(parent: Node3D) -> void:
	painted_sigil=Sprite3D.new()
	painted_sigil.name="PaintedSchoolSigil"
	painted_sigil.texture=ArtRegistryV2.texture(StringName("cast_symbol_"+school+"_hd"))
	painted_sigil.pixel_size=1.42/float(painted_sigil.texture.get_width())
	painted_sigil.rotation.x=-PI/2
	painted_sigil.position.y=0.026
	painted_sigil.shaded=false
	painted_sigil.no_depth_test=false
	painted_sigil.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	painted_sigil.modulate.a=opacity*(0.62 if subtle else 0.85)
	painted_sigil.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(painted_sigil)
var orbit: Node3D
var core: Node3D
var particles: GPUParticles3D
var clock_value:=0.0
var settings: Dictionary
static var presets: Dictionary={}
func material(color: Color) -> StandardMaterial3D:
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.albedo_color.a=opacity*(0.58 if subtle else 0.9)
	mat.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled=true
	mat.emission=color
	mat.emission_energy_multiplier=0.35 if subtle else 0.7
	materials.append(mat)
	return mat
func mesh_node(parent: Node3D,mesh: Mesh,mat: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node
func ring(parent: Node3D,radius: float,width: float,mat: Material) -> MeshInstance3D:
	var torus:=TorusMesh.new()
	torus.inner_radius=radius-width
	torus.outer_radius=radius+width
	torus.rings=64
	torus.ring_segments=6
	return mesh_node(parent,torus,mat)
func line(surface: SurfaceTool,a: Vector2,b: Vector2,width: float=0.012) -> void:
	var normal: Vector2=(b-a).orthogonal().normalized()*width
	var corners: Array[Vector3]=[]
	for point in [a+normal,b+normal,b-normal,a-normal]:corners.append(Vector3(point.x,0.012,point.y))
	for index in [0,1,2,0,2,3]:
		surface.set_normal(Vector3.UP)
		surface.add_vertex(corners[index])
func path(surface: SurfaceTool,points: Array,width: float=0.012) -> void:
	for i in points.size()-1:line(surface,points[i],points[i+1],width)
func arc(surface: SurfaceTool,radius: float,start: float,finish: float,center:=Vector2.ZERO) -> void:
	for i in 36:
		var a:=lerpf(start,finish,float(i)/36)
		var b:=lerpf(start,finish,float(i+1)/36)
		line(surface,center+Vector2(cos(a),sin(a))*radius,center+Vector2(cos(b),sin(b))*radius)
func symbol(surface: SurfaceTool) -> void:
	match school:
		"fire":path(surface,[Vector2(0,-.53),Vector2(-.10,-.12),Vector2(-.32,-.28),Vector2(-.35,.16),Vector2(-.18,.40),Vector2(.1,.46),Vector2(.35,.20),Vector2(.29,-.07),Vector2(.12,.07),Vector2(0,-.53)],.021)
		"ice":
			for i in 6:
				var direction:=Vector2.from_angle(i*TAU/6)
				line(surface,Vector2.ZERO,direction*.55)
				for side in [-1,1]:line(surface,direction*.33,direction*.43+direction.orthogonal()*.13*side)
		"storm":path(surface,[Vector2(.22,-.52),Vector2(-.25,.02),Vector2(.04,.02),Vector2(-.18,.52),Vector2(.32,-.16),Vector2(.03,-.16),Vector2(.22,-.52)],.026)
		"myth":
			path(surface,[Vector2(0,-.49),Vector2(.45,.32),Vector2(-.45,.32),Vector2(0,-.49)],.017)
			arc(surface,.18,0,TAU,Vector2(0,.03))
			line(surface,Vector2(0,-.08),Vector2(0,.14),.022)
		"life":
			path(surface,[Vector2(-.28,.4),Vector2(-.39,.05),Vector2(-.21,-.3),Vector2(.28,-.49),Vector2(.4,-.1),Vector2(.18,.24),Vector2(-.28,.4)],.019)
			line(surface,Vector2(-.38,.52),Vector2(.22,-.33))
			line(surface,Vector2(-.02,.02),Vector2(-.26,-.1))
			line(surface,Vector2(-.12,.2),Vector2(.2,.12))
		"death":
			arc(surface,.46,PI*.23,PI*1.77)
			arc(surface,.37,PI*.34,PI*1.66,Vector2(.12,0))
			path(surface,[Vector2(.22,-.10),Vector2(.3,0),Vector2(.22,.1),Vector2(.14,0),Vector2(.22,-.10)])
		"balance":
			line(surface,Vector2(0,-.48),Vector2(0,.40),.018)
			line(surface,Vector2(-.4,-.25),Vector2(.4,-.25),.018)
			line(surface,Vector2(-.24,.42),Vector2(.24,.42),.018)
			for x in [-.32,.32]:
				path(surface,[Vector2(x,-.25),Vector2(x-.16,.13),Vector2(x+.16,.13),Vector2(x,-.25)])
func _ready() -> void:
	if presets.is_empty():presets=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/school_vfx.json"))
	settings=presets.get(school,presets.fire)
	var primary:=material(Color(settings.color))
	var accent:=material(Color(settings.accent))
	var content:=Node3D.new()
	content.name="Geometry"
	content.scale=Vector3.ONE*diameter*0.5
	add_child(content)
	orbit=Node3D.new()
	content.add_child(orbit)
	if use_approved_casting and kind=="rune":
		ring(content,.97,.012,primary).name="OriginalFootprint"
		if school=="balance":
			add_painted_sigil(content)
		approved_casting=preload("res://scripts/fusion_3d/vfx/approved_casting_aura.gd").new()
		approved_casting.school=school
		approved_casting.diameter=diameter
		approved_casting.opacity=opacity
		approved_casting.name="ApprovedCastingAura"
		add_child(approved_casting)
		return
	if kind in ["rune","aura","heal"]:
		ring(content,.97,.012,primary)
		ring(content,.78,.006,accent)
		add_painted_sigil(content)
		var marks:=SurfaceTool.new()
		marks.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in 12:
			var direction:=Vector2.from_angle(i*TAU/12)
			line(marks,direction*.84,direction*.91,.009)
			if i%3==0:
				line(marks,direction*.86-direction.orthogonal()*.04,direction*.86+direction.orthogonal()*.04,.009)
		mesh_node(orbit,marks.commit(),accent)
	elif kind=="projectile":
		preload("res://scripts/fusion_3d/vfx/magic_radiance.gd").create(content,Color(settings.color),0.75)
		var crystal:=SphereMesh.new()
		crystal.radius=.19
		crystal.height=.50 if school in ["ice","fire","life"] else .38
		crystal.radial_segments=6 if school=="ice" else 12
		crystal.rings=3 if school=="ice" else 6
		core=mesh_node(content,crystal,primary)
		core.rotation.x=PI/2
		var halo:=ring(orbit,.30,.015,accent)
		halo.rotation.x=PI/2
		if school in ["storm","balance","myth"]:ring(orbit,.38,.009,primary).rotation.z=PI/3
	else:
		for i in 3:
			var shock:=ring(orbit,.4+float(i)*.16,.018 if i==0 else .008,accent if i==0 else primary)
			shock.rotation=Vector3(PI/3*i,0,PI/4*i)
	particles=GPUParticles3D.new()
	particles.name="SchoolParticles"
	particles.amount=maxi(4,int(settings.particles)/3) if subtle else int(settings.particles)
	if school == "all" and kind == "rune":particles.amount=42
	particles.lifetime=1.6 if subtle else 0.75
	particles.preprocess=0.8 if subtle else 0.0
	particles.local_coords=kind!="projectile"
	particles.visibility_aabb=AABB(Vector3(-3,-3,-3),Vector3(6,6,6))
	particles.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var motion:=ParticleProcessMaterial.new()
	motion.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_RING
	motion.emission_ring_axis=Vector3.UP
	motion.emission_ring_radius=.91
	motion.emission_ring_inner_radius=.84
	motion.emission_ring_height=.025
	motion.direction=Vector3.UP
	motion.spread=12
	motion.gravity=Vector3.ZERO
	motion.initial_velocity_min=.16 if subtle else .5
	motion.initial_velocity_max=.4 if subtle else 1.2
	if kind=="projectile":
		motion.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		motion.emission_sphere_radius=.14
		motion.direction=Vector3.BACK
		motion.initial_velocity_min=.3
		motion.initial_velocity_max=.6
	elif kind=="impact":
		motion.emission_ring_radius=.25
		motion.emission_ring_inner_radius=.05
		motion.spread=170
		particles.explosiveness=.92
		particles.one_shot=true
	motion.scale_min=.4
	motion.scale_max=1.0
	var fade:=Gradient.new()
	fade.set_color(0,Color(1,1,1,0))
	fade.add_point(.12,Color.WHITE)
	fade.add_point(.5,Color(1,1,1,.7))
	fade.set_color(fade.get_point_count()-1,Color(1,1,1,0))
	var ramp:=GradientTexture1D.new()
	ramp.gradient=fade
	motion.color_ramp=ramp
	if school == "all":
		var school_gradient := Gradient.new()
		school_gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
		var colors = preload("res://scripts/fusion_3d/vfx/casting_wisps.gd").SCHOOL_COLORS
		school_gradient.colors = PackedColorArray(colors)
		var stops := PackedFloat32Array()
		for i in 7:stops.append(float(i)/7.0)
		school_gradient.offsets = stops
		var school_ramp := GradientTexture1D.new()
		school_ramp.gradient = school_gradient
		motion.color_initial_ramp = school_ramp
	particles.process_material=motion
	var spark:=PrismMesh.new()
	spark.size=Vector3(.018,.07,.012) if subtle else Vector3(.028,.12,.018)
	var spark_material:=material(Color(settings.accent))
	if school == "all":spark_material.albedo_color = Color.WHITE
	if kind=="heal":
		spark_material.emission_energy_multiplier=2.0
		spark_material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
	spark_material.vertex_color_use_as_albedo=true
	spark.material=spark_material
	particles.draw_pass_1=spark
	content.add_child(particles)
	visibility_changed.connect(func():particles.emitting=is_visible_in_tree())
func _process(delta: float) -> void:
	clock_value+=delta
	orbit.rotation.y+=delta*float(settings.spin)
	if kind in ["aura","heal"]:orbit.position.y=.12+sin(clock_value*2)*.08
	if kind=="projectile":orbit.rotation.z+=delta*1.6
	if kind=="impact":orbit.scale=Vector3.ONE*(.7+clock_value*1.3)
