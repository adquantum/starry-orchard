extends "res://scripts/fusion_3d/vfx/para_status_layer.gd"
# Approved life DOT: one-shot sigil pulse and rising orbiting leaves.
var leaves: Array=[]
func load_effect(path):
	super.load_effect(path)
	for i in 12:
		var node=MeshInstance3D.new()
		var quad=QuadMesh.new();quad.size=Vector2(.26,.26);node.mesh=quad
		var mat=make_material(load("res://assets/vfx/approved_status/textures/0ef85da1fa424898a494.png"),2)
		mat.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
		mat.uv1_scale=Vector3(.5,.5,1)
		mat.uv1_offset=Vector3(float(i%2)*.5,float((i/2)%2)*.5,0)
		node.material_override=mat;add_child(node);leaves.append(node)
func _process(delta):
	super._process(delta)
	var t=elapsed
	var envelope=clampf(t/.18,0,1)*clampf((1.95-t)/.45,0,1)
	rotation.y=t*1.7
	var pulse=(.85+.15*sin(t*9.0))*envelope
	skeleton.scale=Vector3(maxf(.01,pulse),1,maxf(.01,pulse))
	opacity*=envelope
	for i in leaves.size():
		var age=fmod(t*.65+float(i)/leaves.size(),1.0)
		var angle=TAU*float(i)/leaves.size()+t*.8
		var radius=.85+.18*sin(age*PI)
		leaves[i].position=Vector3(cos(angle)*radius,.15+age*1.6,sin(angle)*radius)
		leaves[i].scale=Vector3.ONE*(.7+.4*sin(age*PI))
		leaves[i].material_override.albedo_color=Color(1,1,1,opacity*sin(age*PI))
