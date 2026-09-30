extends Node3D
## Original level 1/2/3 library layers, with shared flight/impact playback.
static var catalog: Dictionary={}
var layers: Array=[]
var elapsed:=0.0
var lifetime:=1.0
var playback:=1.0

static func level_for(card: CardDefinitionV2) -> int:
	if card.school_id!=&"fire" or card.pip_cost<1 or card.pip_cost>3:return 0
	for entry in card.effects:
		if str(entry.get("type","")) in ["damage","drain","apply_dot","delay_damage","detonate"]:return card.pip_cost
	return 0

static func preset(level: int) -> Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string("res://assets/vfx/fire_projectiles_v13/catalog.json"))
	return catalog[str(level)]

func setup(level: int, phase: String, rate: float) -> void:
	var config=preset(level)
	name="FireLevel%d_%s"%[level,phase]
	scale=Vector3.ONE*float(config.missile_scale if phase=="missile" else config.impact_scale)
	playback=1.0/maxf(rate,.001)
	lifetime=float(config.flight_seconds if phase=="missile" else config.impact_seconds)
	for path in config[phase]:
		var part=preload("res://scripts/fusion_3d/vfx/para_status_layer.gd").new()
		add_child(part);part.load_effect(path);part.set_process(false)
		part.animation_loop=phase=="missile"
		var speed: float=maxf(1.0,part.duration/lifetime)
		part.emission_window=lifetime*.7*speed
		part.set_meta("time_scale",speed)
		part.set_meta("opacity_weight",.22 if str(path).contains("_yan.json") else 1.0)
		if level==3 and phase=="end":part.rotation.x=PI/2
		layers.append(part)
		# Prime emitters so the launch frame contains the original textured core.
		for i in 6:part._process(1.0/60.0)

func _process(delta: float) -> void:
	elapsed+=delta*playback
	for part in layers:
		part.opacity=clampf((lifetime-elapsed)/.2,0,1)*float(part.get_meta("opacity_weight"))
		part._process(delta*playback*float(part.get_meta("time_scale")))
	if elapsed>=lifetime:queue_free()
