extends "res://scripts/worlds/haqi_explorer.gd"

func _ready() -> void:
	world_root = "res://assets/worlds/haqitown_lafeiercastle_pvp/"
	world_title = "拉斐尔城堡 · PVP 竞技场"
	capture_root = "res://docs/haqitown_lafeiercastle_pvp/"
	destinations = [Vector3(0.195313, 62.896114, -40.472656), Vector3(0, 64, 0), Vector3(0, 63, 42)]
	destination_names = ["南侧入口", "竞技场中央", "北侧入口"]
	yaw = PI
	distance = 12.0
	super._ready()

func _build_water() -> void:
	# The source world explicitly disables its ocean.
	water_config = {"sea_level": -10000.0, "swim_depth": 1.0, "swim_speed": 8.0, "float_offset": 0.5}

func _setup_view() -> void:
	super._setup_view()
	for child in get_children():
		if child is WorldEnvironment:
			child.environment.background_color = Color("d9af78")
			child.environment.ambient_light_color = Color("ecd7bd")
