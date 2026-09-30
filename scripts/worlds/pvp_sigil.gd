extends Node3D
## Permanent board and entry labels: south/red=P, north/blue=E.
func setup(config: Dictionary) -> void:
	position=preload("res://scripts/server/encounter_geometry.gd").point(config.center)
	var radius:=float(config.radius)
	for team in 2:
		var title:=Label3D.new();title.text="红方 · 从此侧入阵" if team==0 else "蓝方 · 从此侧入阵"
		title.position=Vector3(0,2.5,radius*0.75*(1 if team==0 else -1))
		title.billboard=BaseMaterial3D.BILLBOARD_ENABLED;title.font_size=48;title.pixel_size=0.015
		title.modulate=Color("ff7770") if team==0 else Color("78b7ff");add_child(title)
	var board=preload("res://scripts/fusion_3d/battle_board.gd").new()
	add_child(board);board.setup(_slot_coords())
	board.name="IdleBoard";board.scale=Vector3.ONE*float(config.scale);board.transparency=0

func _slot_coords() -> Dictionary:
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/battle_board_layout.json"))
	var radius: float=float(layout.outer_radius)-float(layout.slot_radius)
	var slots: Dictionary={}
	for id in layout.slot_angles:
		var angle:=deg_to_rad(float(layout.slot_angles[id]))
		slots[StringName(id)]=Vector3(sin(angle)*radius,float(layout.foot_height),-cos(angle)*radius)
	return slots
