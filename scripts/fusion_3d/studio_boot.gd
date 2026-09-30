extends Control

const CARD_SECONDS:=2.0
const FADE_SECONDS:=0.34
const NEXT_SCENE:="res://scenes/fusion_3d/account_menu.tscn"

var leaving:=false
var startup_check_complete:=false
var phase_index:=-1
var studio_card: VBoxContainer
var game_card: VBoxContainer
var mobile_status: Label

func _ready() -> void:
	if not await _run_update_gate():return
	startup_check_complete=true
	DisplayServer.window_set_title("Starry Orchard" if Locale.locale == "en" else "星界果园")
	if OS.has_feature("mobile") or OS.has_feature("mobile_lite") or "--mobile-preview" in OS.get_cmdline_user_args():
		await _mobile_boot()
		return
	_build_screen()
	await get_tree().process_frame
	await _show_card(studio_card,0)
	if leaving:return
	await _show_card(game_card,1)
	if not leaving:finish()

func _run_update_gate() -> bool:
	var startup=get_tree()
	if not startup.has_method("get_update_context"):return true
	var context: Dictionary=startup.get_update_context()
	if not context.get("enabled",false):return true
	var screen_scene=load("res://scenes/updater/update_screen.tscn") as PackedScene
	if screen_scene==null:
		startup.report_boot_failure("UPDATE_UI_MISSING")
		return false
	var screen=screen_scene.instantiate()
	if screen==null or not screen.has_method("run_update_flow"):
		if screen!=null:screen.queue_free()
		startup.report_boot_failure("UPDATE_UI_MISSING")
		return false
	add_child(screen)
	var outcome: Variant=await screen.run_update_flow(context)
	if not outcome is Dictionary or not outcome.get("allow_business",false):return false
	if not startup.get_update_status().get("business_allowed",false):return false
	screen.queue_free()
	return true

func _mobile_boot() -> void:
	# Android must present a real frame before loading the account UI and its 3D
	# preview dependencies. Keeping this first frame resource-free also leaves a
	# readable failure state instead of the platform's blank launch window.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=ColorRect.new()
	background.color=Color("071423")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack:=VBoxContainer.new()
	stack.custom_minimum_size=Vector2(620,180)
	stack.alignment=BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation",18)
	center.add_child(stack)
	var title:=_label("STARRY ORCHARD" if Locale.locale == "en" else "星 界 果 园",58,Color("f3d591"))
	stack.add_child(title)
	mobile_status=_label("Preparing sign-in…" if Locale.locale == "en" else "正在准备登录界面…",22,Color("b9cbd8"))
	stack.add_child(mobile_status)
	await get_tree().process_frame
	await get_tree().process_frame
	mobile_status.text="Opening sign-in…" if Locale.locale == "en" else "正在打开登录界面…"
	# Account scripts use autoload singletons and must compile on the main thread.
	# The resource-free frame above remains visible during this synchronous read.
	var next:=load(NEXT_SCENE) as PackedScene
	if next==null:
		if get_tree().has_method("report_boot_failure"):get_tree().report_boot_failure()
		mobile_status.text="Sign-in screen is unavailable" if Locale.locale == "en" else "登录界面资源无效"
		return
	leaving=true
	var error:=get_tree().change_scene_to_packed(next)
	if error!=OK and get_tree().has_method("report_boot_failure"):get_tree().report_boot_failure()

func _build_screen() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background:=TextureRect.new()
	background.texture=load("res://assets/ui/academy_frontend/login_background.png")
	background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	background.modulate=Color("3a4656")
	add_child(background)
	var shade:=ColorRect.new()
	shade.color=Color("030814e8")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var glow:=TextureRect.new()
	glow.texture=_radial_glow()
	glow.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stage:=Control.new()
	stage.custom_minimum_size=Vector2(760,620)
	center.add_child(stage)
	studio_card=_studio_card()
	game_card=_game_card()
	for card in [studio_card,game_card]:
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		card.alignment=BoxContainer.ALIGNMENT_CENTER
		card.modulate.a=0.0
		card.hide()
		stage.add_child(card)

func _radial_glow() -> GradientTexture2D:
	var gradient:=Gradient.new()
	gradient.colors=PackedColorArray([Color("29445c72"),Color("08111d00")])
	gradient.offsets=PackedFloat32Array([0.0,1.0])
	var texture:=GradientTexture2D.new()
	texture.gradient=gradient
	texture.fill=GradientTexture2D.FILL_RADIAL
	texture.fill_from=Vector2(.5,.5)
	texture.fill_to=Vector2(.5,1.0)
	texture.width=960
	texture.height=540
	return texture

func _studio_card() -> VBoxContainer:
	var card:=VBoxContainer.new()
	card.add_theme_constant_override("separation",18)
	var mark:=TextureRect.new()
	mark.texture=load("res://assets/branding/studio_portrait.jpg")
	mark.material=_portrait_material()
	mark.custom_minimum_size=Vector2(210,210)
	mark.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.add_child(mark)
	card.add_child(_label("TINY LAZE",58,Color("f1d390")))
	card.add_child(_label("S  T  U  D  I  O",22,Color("b9c8ce")))
	var line:=HSeparator.new()
	line.custom_minimum_size=Vector2(390,1)
	line.modulate=Color("bea3658c")
	card.add_child(line)
	card.add_child(_label("P R E S E N T S",14,Color("8295a4")))
	return card

func _portrait_material() -> ShaderMaterial:
	var shader:=Shader.new()
	shader.code="""
shader_type canvas_item;
void fragment(){
	vec4 portrait=texture(TEXTURE,UV);
	float distance_from_center=distance(UV,vec2(0.5));
	float circle=1.0-smoothstep(0.475,0.5,distance_from_center);
	float rim=smoothstep(0.445,0.465,distance_from_center)*circle;
	portrait.rgb=mix(portrait.rgb,vec3(0.91,0.72,0.34),rim);
	COLOR=vec4(portrait.rgb,portrait.a*circle);
}
"""
	var material:=ShaderMaterial.new()
	material.shader=shader
	return material

func _game_card() -> VBoxContainer:
	var card:=VBoxContainer.new()
	card.add_theme_constant_override("separation",14)
	var icon:=TextureRect.new()
	icon.texture=load("res://assets/branding/game_icon.png")
	icon.custom_minimum_size=Vector2(270,270)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.add_child(icon)
	card.add_child(_label("STARRY ORCHARD" if Locale.locale == "en" else "星 界 果 园",66,Color("f3d591")))
	return card

func _label(value: String,font_size: int,color: Color) -> Label:
	var label:=Label.new()
	label.text=value
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	return label

func _show_card(card: Control,index: int) -> void:
	phase_index=index
	card.show()
	card.modulate.a=0.0
	card.scale=Vector2(.985,.985)
	card.pivot_offset=card.size*.5
	var entrance:=create_tween().set_parallel(true)
	entrance.tween_property(card,"modulate:a",1.0,FADE_SECONDS).set_trans(Tween.TRANS_SINE)
	entrance.tween_property(card,"scale",Vector2.ONE,FADE_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await entrance.finished
	await get_tree().create_timer(CARD_SECONDS-FADE_SECONDS*2.0).timeout
	if leaving:return
	var exit:=create_tween()
	exit.tween_property(card,"modulate:a",0.0,FADE_SECONDS).set_trans(Tween.TRANS_SINE)
	await exit.finished
	card.hide()

func _unhandled_input(event: InputEvent) -> void:
	if startup_check_complete and event.is_pressed() and (event is InputEventKey or event is InputEventMouseButton):finish()

func finish() -> void:
	if leaving or not startup_check_complete:return
	leaving=true
	var error:=get_tree().change_scene_to_file(NEXT_SCENE)
	if error!=OK and get_tree().has_method("report_boot_failure"):get_tree().report_boot_failure()
