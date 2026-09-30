extends Label3D
## Exploration-only name for another connected player.
var display_name:="冒险者"

func _ready() -> void:
	billboard=BaseMaterial3D.BILLBOARD_ENABLED
	font_size=38
	outline_size=8
	modulate=Color("fff1cf")
	outline_modulate=Color("18202b")
	pixel_size=0.006
	no_depth_test=false

func _process(_delta: float) -> void:
	var avatar: Node3D=get_parent()
	text=display_name
	visible=not avatar.battle_mode and not text.is_empty()
	position=avatar.to_local(avatar.anchor_global("HeadStatus"))+Vector3(0,0.25,0)
