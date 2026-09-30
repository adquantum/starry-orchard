extends Node3D
## Shared articulated low-poly rig. Origin = soles, front = -Z, nominal height = 3.05m.
## Geometry is authored with ring profiles, not a skinned/imported skeleton.
@export var replacement_model: PackedScene
var arm: Node3D
var off_arm: Node3D
var cape: Node3D
var gem: MeshInstance3D
var rig: Node3D
var staff: Node3D
var sockets: Dictionary = {}
var legs: Array[Node3D] = []
var cast_amount := 0.0
var recoil := 0.0
var clock_value := 0.0
var dead := false
var accent := Color.WHITE
var school_id := "fire"
var movement := 0.0
var last_world_position := Vector3.ZERO
var initialized_position := false
var cast_tween: Tween
var life_tween: Tween
var palette: Dictionary
var external: Node3D

func material(color: Color, metal: float = 0.0, glow: float = 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metal
	result.roughness = 0.46 if metal > 0 else 0.91
	result.vertex_color_use_as_albedo = true
	if glow > 0:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = glow
	return result

func part(parent: Node3D, mesh: Mesh, at: Vector3, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material(color,metal)
	node.position = at
	parent.add_child(node)
	return node

func box(parent: Node3D, at: Vector3, size_value: Vector3, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size_value
	return part(parent,mesh,at,color,metal)

func cone(parent: Node3D, at: Vector3, bottom: float, top: float, height: float, color: Color, metal: float = 0.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 10
	return part(parent,mesh,at,color,metal)

func sphere(parent: Node3D, at: Vector3, size_value: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1
	mesh.radial_segments = 12
	mesh.rings = 6
	var node := part(parent,mesh,at,color)
	node.scale = size_value
	return node

func socket(parent: Node3D, title: String, at: Vector3) -> Marker3D:
	var node := Marker3D.new()
	node.name = title
	node.position = at
	parent.add_child(node)
	sockets[title] = node
	return node

func anchor_global(title: String) -> Vector3:
	if external != null and external.has_method("anchor_global"): return external.anchor_global(title)
	return sockets[title].global_position if sockets.has(title) else global_position

# Swept rings author the bent hat, folded robe, gauntlets and pointed boots.
# Each ring is Vector4(center_x, height, radius_x, radius_z), front faces -Z.
func profile(parent: Node3D, rings: Array[Vector4], color: Color, segments: int = 14, opening: float = 0.0, folds: float = 0.0, metal: float = 0.0) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in rings.size()-1:
		for i in segments:
			var vertices: Array[Vector3] = []
			for pair in [Vector2i(i,j),Vector2i(i+1,j),Vector2i(i,j+1),Vector2i(i+1,j+1)]:
				var ring := rings[pair.y]
				var angle := opening+(TAU-2*opening)*float(pair.x)/segments
				var fold := 1.0 + (folds if pair.x%2 == 0 else -folds)
				vertices.append(Vector3(ring.x+sin(angle)*ring.z*fold,ring.y,-cos(angle)*ring.w*fold))
			for index in [0,2,1,1,2,3]:
				var shade := 0.94 + float(i%3)*0.028 + (0.025 if index >= 2 else 0.0)
				surface.set_color(Color(shade,shade,shade))
				surface.set_uv(Vector2(float(i)/segments,float(j)/maxi(1,rings.size()-1)))
				surface.add_vertex(vertices[index])
	surface.generate_normals()
	var node := part(parent,surface.commit(),Vector3.ZERO,color,metal)
	(node.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	return node

func crystal(parent: Node3D, at: Vector3, size_value: Vector3, color: Color, glow: float = 0.0) -> MeshInstance3D:
	var node := profile(parent,[Vector4(0,-0.5,0.015,0.015),Vector4(0,-0.1,0.5,0.5),Vector4(0,0.18,0.37,0.37),Vector4(0,0.5,0.005,0.005)],color,5)
	node.position = at
	node.scale = size_value
	node.material_override = material(color,0.25,glow)
	return node

func configure(_color: Color, school: String, enemy: bool) -> void:
	if rig != null:
		remove_child(rig)
		rig.queue_free()
	if sockets.has("FootRing") and is_instance_valid(sockets.FootRing):
		remove_child(sockets.FootRing)
		sockets.FootRing.queue_free()
	external = null
	sockets.clear()
	legs.clear()
	school_id = school
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/wizard_schools.json"))
	palette = data.get(school,data.fire)
	accent = Color(palette.gem)
	rig = Node3D.new()
	rig.name = "VisualRig"
	add_child(rig)
	if replacement_model != null:
		external = replacement_model.instantiate()
		rig.add_child(external)
		if external.has_method("configure"): external.configure(_color,school,enemy)
		return
	var cloth := Color(palette.cloth)
	var inner := Color(palette.inner)
	var trim := Color(palette.trim)
	var leather := Color(palette.leather)
	var skin := Color("e6b991") if not enemy else Color("a8b6b5")
	for side in [-1,1]:
		var leg := Node3D.new()
		leg.position = Vector3(side*0.20,0.42,0)
		rig.add_child(leg)
		legs.append(leg)
		var boot := profile(leg,[Vector4(0,-0.40,0.16,0.28),Vector4(0,-0.30,0.16,0.29),Vector4(0,-0.18,0.115,0.16),Vector4(0,0.07,0.12,0.12)],leather,8)
		boot.position.z = -0.09
		box(leg,Vector3(0,-0.385,-0.10),Vector3(0.31,0.05,0.51),leather.darkened(0.4))
		box(leg,Vector3(0,-0.15,-0.225),Vector3(0.13,0.055,0.035),trim,0.65)
	profile(rig,[Vector4(0,0.26,0.44,0.36),Vector4(0,0.56,0.40,0.32),Vector4(0,1.14,0.27,0.24)],inner,16,0.0,0.05)
	profile(rig,[Vector4(0,0.30,0.52,0.43),Vector4(0,0.53,0.49,0.40),Vector4(0,1.13,0.30,0.28),Vector4(0,1.47,0.36,0.30),Vector4(0,1.64,0.29,0.25)],cloth,16,0.48,0.045)
	profile(rig,[Vector4(0,0.29,0.53,0.44),Vector4(0,0.345,0.526,0.435)],trim,16,0.48,0.045,0.45)
	# Wide readable lapels, not thin lines scattered across the robe.
	for side in [-1,1]:
		var lapel := box(rig,Vector3(side*0.13,1.42,-0.277),Vector3(0.105,0.43,0.06),inner)
		lapel.rotation.z = side*-0.35
		var edging := box(rig,Vector3(side*0.19,0.73,-0.38),Vector3(0.035,0.79,0.028),trim,0.25)
		edging.rotation.z = side*0.12
	cone(rig,Vector3(0,1.12,0),0.319,0.316,0.115,leather)
	box(rig,Vector3(0,1.12,-0.32),Vector3(0.18,0.135,0.065),trim,0.65)
	box(rig,Vector3(0,1.12,-0.358),Vector3(0.105,0.065,0.022),leather)
	# Book and one pouch: visible silhouettes at the belt.
	var book := box(rig,Vector3(0.35,0.94,-0.08),Vector3(0.20,0.34,0.26),leather)
	book.rotation.z = 0.15
	box(book,Vector3(0.015,0,0),Vector3(0.205,0.26,0.205),Color("c4b68f"))
	box(book,Vector3(0.035,0,-0.125),Vector3(0.22,0.075,0.027),trim,0.4)
	sphere(rig,Vector3(-0.35,0.94,0.08),Vector3(0.24,0.30,0.25),leather)
	cape = Node3D.new()
	cape.name = "CapePivot"
	cape.position.y = 1.6
	rig.add_child(cape)
	var mantle := profile(cape,[Vector4(0,-1.18,0.47,0.42),Vector4(0,-0.80,0.43,0.38),Vector4(0,0.0,0.34,0.25)],inner.darkened(0.16),12,1.75,0.05)
	mantle.position.z = 0.10
	# Face stays unobscured beneath a raised front brim.
	cone(rig,Vector3(0,1.72,0),0.115,0.115,0.18,skin)
	sphere(rig,Vector3(0,1.98,-0.035),Vector3(0.46,0.52,0.45),skin)
	sphere(rig,Vector3(0,2.08,0.105),Vector3(0.49,0.40,0.34),Color("302a31"))
	for side in [-1,1]:
		sphere(rig,Vector3(side*0.225,1.98,-0.02),Vector3(0.085,0.15,0.10),skin)
		box(rig,Vector3(side*0.086,2.013,-0.25),Vector3(0.092,0.05,0.023),Color("fff1d6"))
		box(rig,Vector3(side*0.080,2.013,-0.267),Vector3(0.034,0.043,0.012),Color("28343c"))
		var brow := box(rig,Vector3(side*0.083,2.072,-0.232),Vector3(0.12,0.025,0.029),Color("473032"))
		brow.rotation.z = side*-0.12
	sphere(rig,Vector3(0,1.963,-0.267),Vector3(0.083,0.105,0.11),skin.lightened(0.08))
	box(rig,Vector3(0,1.878,-0.231),Vector3(0.105,0.023,0.025),Color("955e52"))
	for side in [-1,1]:
		var collar := box(rig,Vector3(side*0.145,1.665,-0.12),Vector3(0.18,0.18,0.31),inner)
		collar.rotation.z = side*0.35
	# Thick brim and continuous swept/bent crown, five rings with deliberate silhouette.
	var brim := cone(rig,Vector3(0,2.25,0.02),0.64,0.61,0.10,cloth)
	brim.scale.z = 0.84
	var rim := cone(rig,Vector3(0,2.215,0.02),0.643,0.643,0.025,trim,0.45)
	rim.scale.z = 0.84
	profile(rig,[Vector4(0,2.29,0.33,0.29),Vector4(0.01,2.48,0.28,0.24),Vector4(0.07,2.70,0.18,0.155),Vector4(0.21,2.88,0.085,0.08),Vector4(0.38,2.94,0.004,0.006)],cloth,12)
	cone(rig,Vector3(0,2.35,0),0.331,0.31,0.105,leather)
	box(rig,Vector3(0,2.35,-0.307),Vector3(0.20,0.13,0.045),trim,0.6)
	crystal(rig,Vector3(0,2.35,-0.344),Vector3(0.105,0.15,0.05),accent,0.12)
	arm = Node3D.new()
	arm.name = "StaffArm"
	arm.position = Vector3(-0.39,1.49,0)
	rig.add_child(arm)
	off_arm = Node3D.new()
	off_arm.name = "FreeArm"
	off_arm.position = Vector3(0.39,1.49,0)
	rig.add_child(off_arm)
	for pivot in [arm,off_arm]:
		profile(pivot,[Vector4(0,-0.46,0.18,0.16),Vector4(0,-0.36,0.16,0.15),Vector4(0,-0.12,0.14,0.14),Vector4(0,0.0,0.16,0.15)],cloth,10,0,0.04)
		cone(pivot,Vector3(0,-0.46,0),0.181,0.181,0.065,trim,0.45)
		profile(pivot,[Vector4(0,-0.66,0.07,0.085),Vector4(0,-0.57,0.105,0.105),Vector4(0,-0.48,0.08,0.08)],leather,8)
		sphere(pivot,Vector3(0.072,-0.568,-0.066),Vector3(0.072,0.11,0.075),leather.lightened(0.12))
	socket(arm,"HandGrip",Vector3(0,-0.57,-0.085))
	socket(off_arm,"OffHandGrip",Vector3(0,-0.57,-0.085))
	staff = socket(arm,"StaffSocket",Vector3(0,-0.57,-0.085))
	staff.rotation.z = 0.55
	cone(staff,Vector3(0,0.39,0),0.039,0.032,1.78,leather.lightened(0.24))
	for y in [-0.39,0.18,0.86]: cone(staff,Vector3(0,y,0),0.048,0.048,0.075,trim,0.65)
	cone(staff,Vector3(0,0.0,0),0.052,0.052,0.24,leather)
	gem = crystal(staff,Vector3(0,1.43,0),Vector3(0.23,0.38,0.23),accent,0.42)
	socket(staff,"CastRelease",Vector3(0,1.60,0))
	socket(rig,"HitPoint",Vector3(0,1.28,0))
	socket(rig,"HeadStatus",Vector3(0,2.70,0))
	socket(self,"FootRing",Vector3(0,0.025,0))
	_school_details(school,cloth,inner,trim)
	arm.rotation.z = -0.30
	off_arm.rotation.z = 0.22

func _school_details(school: String, cloth: Color, inner: Color, trim: Color) -> void:
	# Fire standard: pointed flame forks and layered ember shoulder plates.
	if school == "fire":
		for side in [-1,1]:
			var flame := profile(staff,[Vector4(side*0.09,1.13,0.055,0.055),Vector4(side*0.17,1.37,0.07,0.055),Vector4(side*0.11,1.62,0.038,0.03),Vector4(side*0.23,1.75,0.002,0.002)],trim,5,0,0,0.6)
			flame.name = "FlameFork"
			var plate := crystal(rig,Vector3(side*0.37,1.61,0),Vector3(0.30,0.25,0.43),inner)
			plate.rotation.z = side*0.6
		crystal(rig,Vector3(0.31,2.75,0.0),Vector3(0.12,0.24,0.07),trim)

	elif school == "ice":
		for side in [-1,1]:
			sphere(rig,Vector3(side*0.29,1.65,0),Vector3(0.42,0.23,0.50),Color("c7d2d9"))
			for i in 3:
				var shard := crystal(rig,Vector3(side*(0.31+i*0.075),1.75-i*0.025,0.06),Vector3(0.13,0.30,0.18),Color("9dcddd"))
				shard.rotation.z = side*-0.45
			crystal(staff,Vector3(side*0.14,1.33,0),Vector3(0.14,0.43,0.16),accent,0.16).rotation.z = side*-0.25
		for i in 3: crystal(rig,Vector3((i-1)*0.15,2.46,-0.24),Vector3(0.11,0.30,0.08),trim)
	elif school == "storm":
		for side in [-1,1]:
			var spike := crystal(rig,Vector3(side*0.39,1.67,0.04),Vector3(0.32,0.35,0.29),inner)
			spike.rotation.z = side*-0.7
			bolt(rig,Vector3(side*0.34,2.43,-0.16),0.24,trim)
		bolt(staff,Vector3(0,1.48,0),0.65,trim)
		gem.scale *= 0.65
	elif school == "myth":
		for side in [-1,1]:
			box(rig,Vector3(side*0.35,1.62,0),Vector3(0.34,0.12,0.43),trim,0.55).rotation.z = side*0.2
			box(rig,Vector3(side*0.17,2.44,-0.24),Vector3(0.10,0.29,0.05),trim,0.5)
		var frame := Node3D.new()
		staff.add_child(frame)
		frame.position.y = 1.46
		frame.rotation.z = PI/4
		for side in [-1,1]:
			box(frame,Vector3(side*0.21,0,0),Vector3(0.06,0.48,0.09),trim,0.6)
			box(frame,Vector3(0,side*0.21,0),Vector3(0.48,0.06,0.09),trim,0.6)
		for y in [0.52,0.72,0.92]: box(rig,Vector3(0,y,-0.40),Vector3(0.13,0.06,0.03),trim)
	elif school == "life":
		for side in [-1,1]:
			for i in 2:
				leaf(rig,Vector3(side*(0.24+i*0.12),1.65-i*0.04,-0.07),Vector3(0.23,0.36,0.09),inner.lightened(0.12)).rotation.z = side*0.9
			leaf(rig,Vector3(side*0.17,2.43,-0.27),Vector3(0.15,0.33,0.07),inner.lightened(0.25)).rotation.z = side*0.5
			profile(staff,[Vector4(0,1.02,0.06,0.05),Vector4(side*0.19,1.29,0.065,0.04),Vector4(side*0.17,1.59,0.025,0.025)],Color(palette.leather),7)
			leaf(staff,Vector3(side*0.21,1.56,0),Vector3(0.27,0.40,0.075),inner.lightened(0.25)).rotation.z = side*-0.6
	elif school == "death":
		for side in [-1,1]:
			var bone := box(rig,Vector3(side*0.30,1.65,-0.09),Vector3(0.34,0.085,0.13),trim)
			bone.rotation.z = side*0.25
			sphere(rig,Vector3(side*0.42,1.67,-0.09),Vector3(0.13,0.12,0.14),trim)
		var skull := sphere(rig,Vector3(0,2.38,-0.35),Vector3(0.21,0.24,0.10),trim)
		for side in [-1,1]: sphere(skull,Vector3(side*0.18,0.05,-0.44),Vector3(0.19,0.18,0.16),cloth)
		for side in [-1,1]:
			box(staff,Vector3(side*0.16,1.43,0),Vector3(0.035,0.42,0.035),trim,0.6)
			box(staff,Vector3(0,1.43,side*0.16),Vector3(0.035,0.42,0.035),trim,0.6)
		cone(staff,Vector3(0,1.19,0),0.19,0.15,0.09,trim,0.6)
		cone(staff,Vector3(0,1.69,0),0.21,0.045,0.16,trim,0.6)
	elif school == "balance":
		for side in [-1,1]:
			var epaulet := box(rig,Vector3(side*0.34,1.61,0),Vector3(0.30,0.09,0.42),trim,0.5)
			epaulet.rotation.z = side*0.18
			crystal(rig,Vector3(side*0.22,2.38,-0.26),Vector3(0.11,0.22,0.045),trim)
		box(staff,Vector3(0,1.47,0),Vector3(0.65,0.055,0.06),trim,0.65)
		for side in [-1,1]:
			cone(staff,Vector3(side*0.29,1.30,0),0.014,0.014,0.30,trim,0.65)
			cone(staff,Vector3(side*0.29,1.12,0),0.025,0.12,0.10,trim,0.65)
		gem.scale *= 0.6
		cone(rig,Vector3(0,0.81,-0.39),0.025,0.10,0.13,trim)
		cone(rig,Vector3(0,0.68,-0.39),0.10,0.025,0.13,trim)
	# A single readable back emblem for near-side slots.
	if school == "storm": bolt(cape,Vector3(0,-0.45,0.47),0.43,trim)
	elif school == "life": leaf(cape,Vector3(0,-0.45,0.46),Vector3(0.29,0.43,0.04),trim)
	else: crystal(cape,Vector3(0,-0.45,0.46),Vector3(0.24,0.35,0.035),trim)

func leaf(parent: Node3D, at: Vector3, size_value: Vector3, color: Color) -> MeshInstance3D:
	return crystal(parent,at,size_value,color)

func bolt(parent: Node3D, at: Vector3, size_value: float, color: Color) -> MeshInstance3D:
	var polygon := PackedVector2Array([Vector2(0.07,0.6),Vector2(-0.30,0.0),Vector2(-0.04,0.04),Vector2(-0.18,-0.6),Vector2(0.35,0.10),Vector2(0.06,0.02)])
	var indices := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		var point := polygon[index]*size_value
		surface.add_vertex(Vector3(point.x,point.y,-0.035))
	surface.generate_normals()
	var node := part(parent,surface.commit(),at,color,0.55)
	(node.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	return node

func play_cast(duration: float) -> void:
	if external != null:
		if external.has_method("play_cast"): external.play_cast(duration)
		return
	if cast_tween != null and cast_tween.is_valid(): cast_tween.kill()
	cast_tween = create_tween()
	cast_tween.tween_property(self,"cast_amount",1.0,duration*0.35).set_trans(Tween.TRANS_SINE)
	cast_tween.tween_interval(duration*0.25)
	cast_tween.tween_property(self,"cast_amount",0.0,duration*0.40).set_trans(Tween.TRANS_SINE)

func hit() -> void:
	if external != null:
		if external.has_method("hit"): external.hit()
		return
	recoil = 0.22
	create_tween().tween_property(self,"recoil",0.0,0.45)

func _process(delta: float) -> void:
	clock_value += delta
	if initialized_position:
		var speed := (global_position-last_world_position).length()/maxf(delta,0.001)
		movement = lerpf(movement,clampf(speed/6.0,0,1),minf(delta*10,1))
	last_world_position = global_position
	initialized_position = true
	if external != null or arm == null or dead: return
	var stride := sin(clock_value*8.5)*movement
	rig.position.y = absf(stride)*0.085
	for i in legs.size(): legs[i].rotation.x = stride*0.48*(1 if i == 0 else -1)
	arm.rotation.x = -cast_amount*2.15+stride*0.30*(1-cast_amount)
	arm.rotation.z = -0.30-cast_amount*0.22
	off_arm.rotation.x = -cast_amount*1.3-stride*0.48*(1-cast_amount)
	off_arm.rotation.z = 0.22+cast_amount*0.50
	cape.rotation.x = sin(clock_value*1.8)*0.035+movement*0.12+cast_amount*0.16
	rig.rotation.x = recoil-cast_amount*0.18-movement*0.035
	gem.rotation.y += delta*0.3

func set_alive(alive: bool) -> void:
	if external != null:
		if external.has_method("set_alive"): external.set_alive(alive)
		return
	if dead == not alive: return
	dead = not alive
	if life_tween != null and life_tween.is_valid(): life_tween.kill()
	if dead:
		life_tween = create_tween().set_parallel(true)
		life_tween.tween_property(rig,"rotation:z",1.30,0.50).set_trans(Tween.TRANS_BOUNCE)
		life_tween.tween_property(rig,"scale",Vector3.ONE*0.65,0.50)
	else:
		rig.rotation = Vector3.ZERO
		rig.scale = Vector3.ONE



