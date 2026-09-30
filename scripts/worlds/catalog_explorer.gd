extends "res://scripts/worlds/haqi_explorer.gd"
## Source-authored entrances also work in indoor maps with elevated mesh floors.
var source_spawn := Vector3.ZERO
var source_attributes: Dictionary = {}

func _ready() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(world_root.path_join("world.json")))
	source_attributes = manifest.get("attributes",{})
	var offset: Array = manifest.origin
	source_spawn = Vector3(float(source_attributes.get("PlayerX",offset[0]))-float(offset[0]),float(source_attributes.get("PlayerY",5)),float(source_attributes.get("PlayerZ",offset[1]))-float(offset[1]))
	var overrides: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/world_entry_overrides.json"))
	var key := world_root.trim_suffix("/").get_file()
	if overrides.has(key):
		var entry: Array = overrides[key].position
		source_spawn = Vector3(entry[0],entry[1],entry[2])
	fall_reset_height = minf(-100.0,source_spawn.y-150.0)
	destinations = [source_spawn]
	destination_names = ["原场景入口"]
	yaw = -float(source_attributes.get("PlayerFacing",0))
	super._ready()

func _reset_player() -> void:
	# Elevated original interiors need a margin larger than float spacing at Y=20000.
	player.safe_margin = 0.01
	player.position = destinations[tour_index] + Vector3.UP * maxf(2.0,explorer_scale)
	player.velocity = Vector3.ZERO
	if ready_world:_refresh_collisions()

func _height(at: Vector3) -> float:
	var value := super._height(at)
	return source_spawn.y-1.0 if value < -900.0 else value

func _build_water() -> void:
	water_config = {"sea_level":-100000.0,"swim_depth":1.15,"swim_speed":4.2,"float_offset":0.85}
	if str(source_attributes.get("OceanEnabled","false")) != "true":return
	water_config.sea_level = float(source_attributes.get("OceanLevel",0))
	var plane := PlaneMesh.new()
	plane.size = Vector2(6000,6000)
	plane.subdivide_width = 180
	plane.subdivide_depth = 180
	var water := MeshInstance3D.new()
	water.name = "Ocean"
	water.mesh = plane
	water.position = Vector3(source_spawn.x,float(water_config.sea_level),source_spawn.z)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/worlds/haqi_water.gdshader")
	water.material_override = material
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	_configure_world_water(material)
