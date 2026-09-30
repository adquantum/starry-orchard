extends "res://scripts/worlds/catalog_explorer.gd"

func _ready() -> void:
	super._ready()
	# The furnished Order Temple is authored far above the terrain.
	destinations.append(Vector3(1200.0, 10265.0, -60.0))
	destination_names.append("高空 · 秩序神殿")
