extends Control
## Standalone entry for the same library panel used by the game.
func _ready() -> void:
	var panel = preload("res://scripts/fusion_3d/character_library_view.gd").new()
	add_child(panel)
	panel.visibility_changed.connect(func() -> void:
		if not panel.visible:
			get_tree().quit())
