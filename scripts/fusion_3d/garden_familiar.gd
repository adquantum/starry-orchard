extends Node3D
## Shared feet origin / -Z front / presentation sockets, independent of battle state.
var kind := "life"
var visual: Node3D
var t := 0.0
var casting := 0.0
var recoil := 0.0
var dead := false
var sockets := {"CastRelease":Vector3(0,1.9,-0.7),"HitPoint":Vector3(0,1.3,0),"HeadStatus":Vector3(0,2.6,0),"FootRing":Vector3.ZERO}
var wings: Array[Node3D]=[]
func _ready() -> void:
	visual=load("res://assets/models/academy/"+kind+"_guardian.glb").instantiate()
	visual.rotation.y=PI
	add_child(visual)
	for wing_name in ["WingLeft","WingRight"]:
		var wing:=visual.find_child(wing_name,true,false) as Node3D
		if wing: wings.append(wing)
	var fx:=preload("res://scripts/fusion_3d/atelier_geometry.gd").new()
	add_child(fx)
	var colors: Dictionary={"fire":Color("ff963b"),"ice":Color("80d4ff"),"life":Color("c7d780"),"storm":Color("86bcff")}
	fx.particles(Vector3(0,1.7,0),colors[kind],16,Vector3(0.4,0.5,0.3),Vector3(0,0.45,0))
func anchor_global(id: String) -> Vector3:
	return to_global(sockets.get(id,Vector3.UP))
func play_cast(duration: float) -> void:
	casting=1
	create_tween().tween_property(self,"casting",0.0,duration)
func hit() -> void:
	recoil=0.25
func set_alive(alive: bool) -> void:
	dead=not alive
	visual.scale=Vector3.ONE if alive else Vector3(1,0.2,1)
func _process(delta: float) -> void:
	t+=delta
	if visual==null or dead: return
	recoil=move_toward(recoil,0,delta)
	visual.position.y=sin(t*2.4)*0.06+casting*0.25
	visual.rotation.x=-casting*0.25+recoil
	if kind=="storm":
		visual.position.y+=0.25+sin(t*3.0)*0.1
		for i in wings.size():
			wings[i].rotation.z=sin(t*4.0)*(0.10+casting*0.18)*(1 if i==0 else -1)
