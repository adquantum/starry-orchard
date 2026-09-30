extends RefCounted
static func panel(fill: Color = Color("111a29f2"), edge: Color = Color("665d4e")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = ThemeDB.fallback_font
	theme.default_font_size = 16
	for type in ["Button","OptionButton"]:
		theme.set_stylebox("normal",type,panel())
		theme.set_stylebox("hover",type,panel(Color("1f2c3d"),Color("a19470")))
		theme.set_stylebox("pressed",type,panel(Color("293849"),Color("b8a580")))
		theme.set_stylebox("disabled",type,panel(Color("101722c9"),Color("3b4046")))
		theme.set_stylebox("focus",type,panel(Color("00000000"),Color("b8a580")))
		theme.set_color("font_color",type,Color("d9d4c6"))
		theme.set_color("font_hover_color",type,Color("f2e7d0"))
		theme.set_color("font_disabled_color",type,Color("687280"))
	theme.set_stylebox("panel","PanelContainer",panel())
	theme.set_color("font_color","Label",Color("d8d4c9"))
	return theme
static func apply(shell: Control) -> void:
	shell.theme = make_theme()
	for kind in ["Button","OptionButton"]:
		for state in ["normal","hover","pressed","disabled"]:
			var box := preload("res://scripts/fusion_3d/combat_scroll_skin.gd").style(false).duplicate() as StyleBoxTexture
			box.modulate_color = Color("c4b798") if state == "pressed" else (Color("ffffff66") if state == "disabled" else (Color("fff0cc") if state == "hover" else Color.WHITE))
			shell.theme.set_stylebox(state,kind,box)
	shell.phase_label.add_theme_font_size_override("font_size",17)
	shell.prompt_label.add_theme_font_size_override("font_size",15)
	shell.top_bar.add_theme_stylebox_override("panel",preload("res://scripts/fusion_3d/combat_scroll_skin.gd").style(false))
	for art in [shell.action_dock_art,shell.deck_dock_art,shell.hand_tray_art]: art.hide()
	for button in [shell.pass_button,shell.draw_button,shell.deck_button,shell.cancel_button,shell.ai_button,shell.charge_option,shell.speed_option]:
		for state in ["normal","hover","pressed","disabled","focus"]: button.remove_theme_stylebox_override(state)
		button.add_theme_font_size_override("font_size",16)
		button.custom_minimum_size.y = 36
	shell.pass_button.text = "跳过 · PASS"
	shell.draw_button.text = "宝藏 · DRAW"
	shell.deck_button.text = "卡组 · DECK"
	shell.deck_button.icon = null
	shell.pass_button.icon = null
	shell.draw_button.icon = null
	for view in shell.unit_views.values():
		view.nameplate.set_meta("refined",true)
		view.nameplate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		view.nameplate.queue_redraw()
