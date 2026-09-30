extends "res://scripts/worlds/haqi_explorer.gd"
func _setup_view() -> void:
	super._setup_view()
	for child in get_children():
		if child is WorldEnvironment:
			var sky := Sky.new()
			var panorama := PanoramaSkyMaterial.new()
			panorama.panorama=load("res://assets/worlds/haqi_town/painted_sky_v1/panorama.png")
			panorama.energy_multiplier=0.8
			sky.sky_material=panorama
			child.environment.background_mode=Environment.BG_SKY
			child.environment.sky=sky
