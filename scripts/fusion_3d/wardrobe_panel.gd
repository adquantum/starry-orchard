extends "res://scripts/fusion_3d/inventory_panel.gd"
## Compatibility for existing wardrobe callers. World routing uses game_menu's window.
func open_for(school: String) -> void:
	page.profile=str(get_node("/root/Wardrobe").progression().get("school",school))
	open_tab("equipment")
