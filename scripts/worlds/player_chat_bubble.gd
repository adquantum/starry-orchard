extends Node3D
## A texture-backed speech bubble above either the local or a replicated avatar.
var expires_at:=0.0
var background: Sprite3D
var caption: Label3D
var bubble_height := 0.8

func _ready() -> void:
	background=Sprite3D.new()
	background.texture=load("res://assets/ui/chat/world_chat_bubble.png")
	background.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	background.pixel_size=0.0032
	background.no_depth_test=true
	background.render_priority=8
	add_child(background)
	caption=Label3D.new()
	caption.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	caption.font_size=48
	caption.outline_size=4
	caption.modulate=Color("fff6dc")
	caption.outline_modulate=Color("15243b")
	caption.pixel_size=0.0045
	caption.width=480
	caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	caption.no_depth_test=true
	caption.render_priority=9
	caption.position=Vector3(0,0.04,-0.02)
	add_child(caption)
	hide()

func show_message(value: String) -> void:
	caption.text=value
	expires_at=Time.get_ticks_msec()/1000.0+3.0
	show()
	_fit_message.call_deferred()

func _fit_message() -> void:
	# Label geometry updates after text shaping; size the artwork to the actual lines.
	await get_tree().process_frame
	if not is_instance_valid(caption):return
	var text_size:=caption.get_aabb().size
	var width:=maxf(1.5,text_size.x+0.38)
	# The painted panel occupies only the middle 55% of the source image height.
	bubble_height=maxf(0.8,(text_size.y+0.18)/0.55)
	background.scale=Vector3(width/(background.texture.get_width()*background.pixel_size),bubble_height/(background.texture.get_height()*background.pixel_size),1)
	caption.position.y=bubble_height*0.045

func _process(_delta: float) -> void:
	var avatar: Node3D=get_parent()
	position=avatar.to_local(avatar.anchor_global("HeadStatus"))+Vector3(0,0.92+maxf(0.0,bubble_height-0.8)*0.5,0)
	visible=not avatar.battle_mode and Time.get_ticks_msec()/1000.0<expires_at
