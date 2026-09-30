extends "res://scripts/fusion_3d/atelier_geometry.gd"
var town: Node3D
var star_rings:Array[MeshInstance3D]=[]
func asset(id: String, at: Vector3, scale_value: float=1.0) -> Node3D:
	var packed := load("res://assets/models/academy/"+id+".glb") as PackedScene
	var n:=packed.instantiate() as Node3D
	n.position=at
	n.scale=Vector3.ONE*scale_value
	add_child(n)
	return n
func build(value: Node3D) -> void:
	town=value
	# Decorative terrain continues beneath the skyline; never leaves floating trees.
	block(Vector3(30,-1.2,-45),Vector3(260,2.0,220),Color("273f35"))
	for side in [-1,1]:
		for i in 11:
			var ridge:=asset("rock",Vector3(side*(68+i*4),-3,-66-i*4),5.0+float(i%4)*1.5)
			ridge.scale.y*=2.1
	# Broad terraces and stone edging make the academic skyline a connected campus.
	block(Vector3(0,-0.05,-47),Vector3(76,0.12,27),Color("727c7f"))
	for x in [-36.0,36.0]:
		block(Vector3(x,0.65,-45),Vector3(0.6,1.3,27),Color("a1a99e"))
	for i in 9:
		block(Vector3((i-4)*8,0.35,-32),Vector3(6.8,0.7,0.7),Color("a1a99e"))
	# A monumental skyline behind the playable streets, not a replacement backdrop.
	var hall:=preload("res://scripts/fusion_3d/academy_architecture.gd").new()
	add_child(hall)
	hall.position=Vector3(0,0,-49)
	hall.cathedral()
	for side in [-1,1]:
		asset("bell_tower",Vector3(side*24,0,-43),1.25)
		for i in 3:
			var wing:=preload("res://scripts/fusion_3d/academy_architecture.gd").new()
			add_child(wing)
			wing.position=Vector3(side*(12+i*6),0,-42)
			wing.arch(Vector3.ZERO,4.6,6.4,0.55,Color("b1b8af"),false)
			wing.block(Vector3(0,6.5,0),Vector3(6,0.4,1.5),Color("afb2a5"))
	for i in 7:
		var tower:=preload("res://scripts/fusion_3d/academy_architecture.gd").new()
		add_child(tower)
		tower.position=Vector3(-31+i*10,0,-31)
		tower.tower(Vector3.ZERO,9.0+float(i%3)*2.0,0.90,town.TINTS[i].darkened(0.57))
	# Planted banks, clipped beds, loose stones and tall forest create three depth layers.
	var rng:=RandomNumberGenerator.new()
	rng.seed=681234
	for i in 70:
		var x:=rng.randf_range(-42,109)
		var z:=rng.randf_range(-75,-39)
		asset(["oak","pine","birch"][i%3],Vector3(x,-0.1,z),rng.randf_range(0.8,1.5))
	for side in [-1,1]:
		for i in 15:
			var x:float=49.0+side*7.0
			var z:float=-34+i*4.8
			if absf(z)<7:continue
			asset("rock",Vector3(x,-0.6,z),rng.randf_range(0.45,0.8))
	for at in [Vector3(66,0,-21),Vector3(83,0,-21),Vector3(66,0,22),Vector3(84,0,23),Vector3(103,0,9)]:
		for i in 5:
			asset("flower_bush",at+Vector3((i-2)*0.8,0.2,1.3),0.65)
			asset("flowers",at+Vector3((i-2)*0.8,0.3,-1.2),1.0)
	for i in 50:
		var at:=Vector3(rng.randf_range(60,106),0.02,rng.randf_range(-31,31))
		if Vector2(at.x-78,at.z).length()<14 or absf(at.z)<6:continue
		asset("grass",at,rng.randf_range(0.8,1.4))
	particles(Vector3(78,1.6,0),Color("b5d49f"),90,Vector3(16,1,20),Vector3(0.1,0.4,0.08))
	particles(Vector3(0,3,-11),Color("8cc7ee"),70,Vector3(2,1,2),Vector3(0,0.6,0))
	for i in 2:
		var n:=ring(Vector3(0,4,-11),2.45+i*0.32,0.045,Color("d5b974"))
		n.rotation=Vector3(0.6+i,0,0.4+i)
		star_rings.append(n)
	var glow:=OmniLight3D.new()
	glow.position=Vector3(0,4,-11)
	glow.light_color=Color("7daedd")
	glow.light_energy=2
	glow.omni_range=9
	add_child(glow)
func _process(delta: float) -> void:
	for i in star_rings.size():
		star_rings[i].rotation.y+=delta*(0.20+i*0.12)
		star_rings[i].rotation.z+=delta*0.10
