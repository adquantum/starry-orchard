extends Node3D
const Layer=preload("res://scripts/fusion_3d/vfx/para_casting_layer.gd")
# Same outside radius as the original .97 + .012 torus in school_vfx.gd.
const OUTER_RADIUS_RATIO: float=.982
static var catalog: Dictionary={}
var school: String="fire"
var diameter: float=3.2
var layers: Array=[]
var opacity: float=1.0:
	set(value):
		opacity=clampf(value,0,1)
		for layer in layers:layer.opacity=opacity
func world_radius() -> float:
	return diameter*.5*OUTER_RADIUS_RATIO*maxf(global_basis.x.length(),global_basis.z.length())
func _ready() -> void:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/approved_casting/catalog.json"))
	var config: Dictionary=catalog[school]
	for path in config.layers:
		var layer=Layer.new()
		layer.bounds_owner=self
		layer.source_radius=float(config.source_radius)
		layer.scale=Vector3.ONE*(diameter*.5*.97/layer.source_radius)
		layer.orbit_particles=bool(config.orbit_particles)
		layer.particle_limit=12 if layer.orbit_particles else 42
		layer.particle_size_factor=float(config.particle_size)
		layer.particle_rate_factor=float(config.particle_rate)
		layer.opacity=opacity
		add_child(layer)
		layer.load_effect(str(path))
		layers.append(layer)
