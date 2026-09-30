extends RefCounted
## Shared nine-slice surfaces, matching the compact unit HUD.
const Art = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")

static func roundel(canvas: CanvasItem, center: Vector2, radius: float, accent := Color("9bb5c8")) -> void:
	canvas.draw_circle(center + Vector2(0, 1), radius + 1, Color("08121dde"))
	canvas.draw_circle(center, radius, Color("111f30"))
	canvas.draw_arc(center,radius-1,0,TAU,48,Color("b7bbc0"),1.4,true)
	canvas.draw_arc(center,radius-3,0,TAU,48,Color(accent,0.65),1,true)
	canvas.draw_arc(center,radius-1,PI*1.12,PI*1.85,20,Color("edf4ee"),1.5,true)
	for angle in [0.0, PI/2, PI, PI*1.5]:
		var point := center + Vector2.from_angle(angle) * (radius-1)
		canvas.draw_circle(point,1.5,Color("d6c7a3"))

static func backing(host: Control) -> void:
	if host.has_node("CompactBacking"):return
	var frame := Panel.new()
	frame.name = "CompactBacking"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel",panel(true,Color(0.8,0.9,1,0.94)))
	host.add_child(frame)
	host.move_child(frame,0)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left=-12; frame.offset_right=12
	frame.offset_top=-8; frame.offset_bottom=8
	var hand := host.get_node_or_null("Hand") as Control
	if hand != null:
		frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var fit_cards := func():
			var count: int=hand.cards.size()
			frame.visible=count>0
			var step := minf(142.0,maxf(78.0,(hand.size.x-162.0)/maxf(1,count-1)))
			var width := 138.0+step*maxi(0,count-1)
			frame.position=hand.position+Vector2((hand.size.x-width)*0.5-8.0,-4.0)
			frame.size=Vector2(width+16.0,226.0)
		hand.item_rect_changed.connect(fit_cards)
		hand.hand_layout_changed.connect(fit_cards)
		fit_cards.call()

static func outline(host: Control) -> void:
	var frame := Panel.new()
	frame.name="CompactOutline"
	frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style := panel(true)
	style.draw_center=false
	frame.add_theme_stylebox_override("panel",style)
	host.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

static func panel(card := false, tint := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = Art.texture(&"compact_card" if card else &"compact_button")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 16)
		style.set_content_margin(side, 12)
	style.modulate_color = tint
	return style

static func button(control: BaseButton) -> void:
	control.add_theme_stylebox_override("normal", panel(false, Color(1,1,1,0.88)))
	control.add_theme_stylebox_override("hover", panel(false, Color(1.12,1.2,1.25,1)))
	control.add_theme_stylebox_override("pressed", panel(false, Color(0.72,0.86,0.94,1)))
	control.add_theme_stylebox_override("disabled", panel(false, Color(0.65,0.7,0.75,0.7)))
	control.add_theme_stylebox_override("focus", panel(false, Color(1,1,1,0.2)))
	control.add_theme_color_override("font_color", Color("e4edf3"))
	control.add_theme_color_override("font_hover_color", Color.WHITE)
	control.add_theme_font_size_override("font_size", 18)
	control.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

static func dock(shell: Control, controls: Array) -> Control:
	var root := Control.new()
	root.name = "CompactActionDock"
	root.z_index = 250
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	root.offset_left = 32; root.offset_right = 272
	root.offset_top = -306; root.offset_bottom = -26
	var book := TextureRect.new()
	book.name = "MagicCardBox"
	book.texture = load("res://assets/art/ui/magic_card_box.png")
	book.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	book.stretch_mode = TextureRect.STRETCH_SCALE
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(book)
	book.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in range(1, controls.size()):
		var control: Control = controls[i]
		control.reparent(root, false)
		control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		control.custom_minimum_size = Vector2.ZERO
		control.position = Vector2(38, 70 + (i-1)*48)
		control.size = Vector2(168,46)
		button(control)
		control.add_theme_font_size_override("font_size",20)
		control.add_theme_color_override("font_disabled_color",Color("a0adba"))
		for state in ["normal", "disabled"]:
			control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		control.add_theme_color_override("font_shadow_color",Color("081322"))
		control.add_theme_constant_override("shadow_outline_size",4)
	var picker: Control = controls[0]
	picker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	picker.offset_left=-202;picker.offset_right=-118
	picker.offset_top=-202;picker.offset_bottom=-118
	picker.z_index=260
	var hand = shell.get("hand")
	if hand != null:hand.draw_origin_control=root
	return root

static func clock(label: Label) -> void:
	label.z_index = 250
	label.add_theme_font_size_override("font_size", 48)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.offset_left = -60; label.offset_right = 60
	label.offset_top = 20; label.offset_bottom = 140
	var frame := TextureRect.new()
	frame.name = "ClockBezel"
	frame.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	frame.texture = preload("res://scenes/battle_v2/presentation/target_arrow_renderer_v2.gd")._trimmed_texture("res://assets/art/ui/countdown_clock_painted_v2.png")
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = -1
	label.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
