extends Node3D
## Small tapered streaks travel into the casting symbol; no round bubble meshes.
static var spark_mesh: ArrayMesh
var origin := Vector3.ZERO
var destination := Vector3.ZERO
var color := Color.WHITE
var seven_schools := false
const SCHOOL_COLORS = [Color("ff7439"), Color("72caff"), Color("af83ff"), Color("74d88e"), Color("ac78dc"), Color("e9bd62"), Color("eed6a0")]
var seconds := 1.8
var elapsed := 0.0
var streams: Array[MeshInstance3D] = []
var orbit_motes: Array[MeshInstance3D] = []
var halos: Array[MeshInstance3D] = []

static func geometry() -> ArrayMesh:
	if spark_mesh != null: return spark_mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two crossed, feathered diamonds remain readable from any camera side.
	for plane in 2:
		var points := [Vector3(0,-0.5,0),Vector3(0.16,0,0),Vector3(0,0.5,0),Vector3(-0.16,0,0)]
		for edge in 4:
			for index in 3:
				var vertex: Vector3 = Vector3.ZERO if index == 0 else points[(edge + index - 1) % 4]
				surface.set_color(Color(1,1,1,0.95) if index == 0 else Color(1,1,1,0))
				surface.add_vertex(vertex.rotated(Vector3.UP, plane * PI * 0.5))
	spark_mesh = surface.commit()
	return spark_mesh

static func make_spark(parent: Node3D, tint: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = "TaperedMagicSpark"
	node.mesh = geometry()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = tint.lightened(0.25)
	node.material_override = material
	parent.add_child(node)
	return node

func _ready() -> void:
	name = "CastingWisps"
	for index in (28 * 4 if seven_schools else 7 * 3):
		streams.append(make_spark(self, SCHOOL_COLORS[(index / 4) % 7] if seven_schools else color))
	if seven_schools:
		for i in 42:orbit_motes.append(make_spark(self,SCHOOL_COLORS[i % 7]))
		for i in 3:
			var halo := MeshInstance3D.new()
			var ring := TorusMesh.new()
			ring.inner_radius = 0.96;ring.outer_radius = 0.972
			ring.rings = 64;ring.ring_segments = 8
			halo.mesh = ring
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			material.albedo_color = [Color("f6db91"),Color("92dcff"),Color("c2a2ff")][i]
			halo.material_override = material
			add_child(halo);halos.append(halo)
	update_streams()

func point(index: int, t: float) -> Vector3:
	var angle := float(index) * TAU / 7.0 + t * 1.1
	var radial := Vector3(cos(angle),0,sin(angle)) * 1.35 * (1.0 - t)
	return origin.lerp(destination,t) + radial + Vector3.UP * sin(t * PI) * 0.22

func update_streams() -> void:
	if seven_schools:
		update_universal_streams()
		return
	for index in 7:
		var progress := (elapsed / maxf(seconds,0.001) - index * 0.045) / 0.64
		for trail in 3:
			var node := streams[index * 3 + trail]
			var t := progress - trail * 0.035
			node.visible = t > 0 and t < 1
			if not node.visible: continue
			var eased := t * t * (3.0 - 2.0 * t)
			node.position = point(index,eased)
			var direction := (point(index,minf(1,eased+0.01)) - point(index,maxf(0,eased-0.01))).normalized()
			node.quaternion = Quaternion(Vector3.UP,direction)
			var fade := sin(t * PI)
			var size := (0.32 if trail == 0 else 0.22 - trail * 0.05) * fade
			node.scale = Vector3(size * 0.8,size,size * 0.8)

func universal_point(index: int, t: float) -> Vector3:
	var angle := float(index % 7) * TAU / 7.0 + (index / 7) * 0.35 + t * 2.8
	var radius := (2.05 + (index / 7) * 0.16) * pow(1.0-t, 0.8)
	return origin.lerp(destination,t) + Vector3(cos(angle)*radius,sin(t*PI)*0.45,sin(angle)*radius)

func update_universal_streams() -> void:
	var progress := clampf(elapsed / maxf(seconds,0.001),0,1)
	for index in 28:
		var lead := (progress - (index / 7)*0.085 - (index % 7)*0.008) / 0.68
		for tail in 4:
			var node := streams[index*4+tail]
			var t := lead-tail*0.024
			node.visible = t>0 and t<1
			if not node.visible:continue
			node.position = universal_point(index,t)
			var direction := (universal_point(index,minf(t+0.01,1))-universal_point(index,maxf(t-0.01,0))).normalized()
			node.quaternion = Quaternion(Vector3.UP,direction)
			var size := sin(t*PI)*(0.39-tail*0.065)
			node.scale = Vector3(size*0.7,size*1.55,size*0.7)
	for i in orbit_motes.size():
		var angle := i*TAU/42.0 + progress*5.0
		var radius := (1.18 + (i%3)*0.11)*(0.8+0.2*sin(progress*PI))
		var mote := orbit_motes[i]
		mote.position = destination + Vector3(cos(angle)*radius,sin(angle)*radius,sin(angle*2.0+progress*3.0)*0.32)
		mote.quaternion = Quaternion(Vector3.UP,Vector3(-sin(angle),cos(angle),0))
		var size := (0.065+(i%3)*0.025)*sin(progress*PI)
		mote.scale = Vector3(size,size*2.1,size)
	for i in halos.size():
		var halo := halos[i]
		halo.position = destination
		halo.rotation = Vector3(PI*0.5+sin(progress*TAU+i)*0.35,progress*(1.0+i*0.35),i*PI/3.0)
		halo.scale = Vector3.ONE*(1.2+i*0.18)*(0.75+progress*0.25)
		(halo.material_override as StandardMaterial3D).albedo_color.a = sin(progress*PI)*0.55

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= seconds:
		queue_free()
		return
	update_streams()
