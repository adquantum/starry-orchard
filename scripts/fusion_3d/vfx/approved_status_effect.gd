extends Node3D
static var catalog: Dictionary={}
var elapsed: float=0.0
var lifetime: float=2.4
var playback_rate: float=1.0
var candidate_id: String=""
var layers: Array=[]
func setup(id: String, ratio: float, rate: float) -> void:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/approved_status/catalog.json"))
	candidate_id=id
	name="ApprovedStatus_"+id
	# Turn-start damage ticks should finish before the next result or cast.
	if id in ["17","18","19","23","24","25","26"]:lifetime=1.45
	playback_rate=1.0/maxf(rate,0.05)
	var c: Dictionary=catalog[id]
	scale=Vector3.ONE*float(c.scale)*ratio
	position.y=float(c.y)*ratio
	rotation.y=float(c.rotation)
	for path in c.layers:
		var fx=preload("res://scripts/fusion_3d/vfx/life_dot_animated.gd").new() if id=="24" else preload("res://scripts/fusion_3d/vfx/para_status_layer.gd").new()
		add_child(fx)
		fx.load_effect(path)
		fx.particle_size_factor=float(c.particle_size)
		fx.particle_rate_factor=float(c.particle_rate)
		fx.emission_window=minf(float(c.emission_window),lifetime-0.35)
		fx.animation_loop=false
		fx.set_process(false)
		layers.append(fx)
func _process(delta: float) -> void:
	elapsed+=delta*playback_rate
	for fx in layers:
		fx.opacity=clampf((lifetime-elapsed)/0.45,0,1)
		fx._process(delta*playback_rate)
	if elapsed>=lifetime:queue_free()
