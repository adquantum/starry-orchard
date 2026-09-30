extends Node3D
## Original level 1/2/3 library layers, with shared flight/impact playback.
static var catalog: Dictionary={}
var layers: Array=[]
var elapsed:=0.0
var lifetime:=1.0
var playback:=1.0
var flying := false
var flight_start := Vector3.ZERO
var flight_end := Vector3.ZERO
var arc_height := 0.0
signal arrived

static func flight_duration(distance: float, school: String) -> float:
	var speed: float = {"storm":24.0,"ice":20.0,"fire":19.0,"balance":20.0,"life":17.0,"death":17.0,"myth":16.0}.get(school,19.0)
	return clampf(distance / speed,0.32,0.95)

func launch(start: Vector3, destination: Vector3, seconds: float, school: String) -> void:
	flight_start=start
	flight_end=destination
	lifetime=maxf(seconds,0.001)
	elapsed=0.0
	flying=true
	arc_height=minf(start.distance_to(destination)*0.055,0.65) if school in ["life","death","myth","fire"] else 0.0
	position=start
	_update_flight(0.0)
	for part in layers:
		part.emission_window=99.0

func _update_flight(t: float) -> void:
	position=flight_start.lerp(flight_end,t)+Vector3.UP*(4.0*arc_height*t*(1.0-t))
	var tangent:=flight_end-flight_start+Vector3.UP*(4.0*arc_height*(1.0-2.0*t))
	if tangent.length_squared()>0.00001:
		quaternion=Quaternion(Vector3.RIGHT,tangent.normalized())

static func level_for(card: CardDefinitionV2) -> int:
	if str(card.school_id) not in ["fire","ice","storm","life","death","myth","balance"] or card.pip_cost<1 or card.pip_cost>3:return 0
	for entry in card.effects:
		if str(entry.get("type","")) in ["damage","drain","apply_dot","delay_damage","detonate"]:return card.pip_cost
	return 0

static func preset(school: String, level: int) -> Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/school_projectiles_v14/catalog.json"))
	return catalog[school][str(level)]

func setup(school: String, level: int, phase: String, rate: float) -> void:
	var config=preset(school,level)
	name="%sLevel%d_%s"%[school,level,phase]
	scale=Vector3.ONE*float(config.missile_scale if phase=="missile" else config.impact_scale)
	if phase=="missile":
		var colors: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/school_vfx.json"))
		var glow=preload("res://scripts/fusion_3d/vfx/magic_radiance.gd").create(self,Color(colors[school].color),(0.65+level*0.1)/maxf(scale.x,0.001))
		glow.name="ProjectileHeadGlow"
	playback=1.0/maxf(rate,.001)
	lifetime=float(config.flight_seconds if phase=="missile" else config.impact_seconds)
	for path in config[phase]:
		var part=preload("res://scripts/fusion_3d/vfx/para_status_layer.gd").new()
		add_child(part);part.load_effect(path);part.set_process(false)
		# Legacy layers stack independent high-rate emitters. Keep the authored
		# mesh/core, but budget secondary particles across the whole effect.
		var smoke:=str(path).get_file().contains("_yan")
		var layer_count: int=config[phase].size()
		part.particle_rate_factor=clampf(1.8/float(maxi(layer_count,1)),0.3,0.65)
		part.particle_size_factor=0.75 if smoke else 0.82
		if smoke:part.particle_rate_factor*=0.5
		part.animation_loop=phase=="missile"
		var speed: float=maxf(1.0,part.duration/lifetime)
		part.emission_window=lifetime*.7*speed
		part.set_meta("time_scale",speed)
		part.set_meta("opacity_weight",.22 if str(path).contains("_yan.json") else 1.0)
		if smoke:part.set_meta("opacity_weight",0.14)
		elif layer_count>=4:part.set_meta("opacity_weight",0.78)
		part.opacity=float(part.get_meta("opacity_weight"))
		if school=="fire" and level==3 and phase=="end":part.rotation.x=PI/2
		layers.append(part)
		# Prime emitters so the launch frame contains the original textured core.
		for i in 6:part._process(1.0/60.0)

func _process(delta: float) -> void:
	elapsed+=delta*playback
	if flying:_update_flight(clampf(elapsed/lifetime,0.0,1.0))
	for part in layers:
		part.opacity=(1.0 if flying else clampf((lifetime-elapsed)/.2,0,1))*float(part.get_meta("opacity_weight"))
		part._process(delta*playback*float(part.get_meta("time_scale")))
	if elapsed>=lifetime:
		if flying:
			flying=false
			arrived.emit()
		queue_free()
