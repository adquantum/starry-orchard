extends Control
## One coordinate space for the 3D planning HUD. The 2D sandbox keeps its layout.
const PlanningSkin = preload("res://scenes/battle_v2/ui/compact_battle_skin.gd")
const Metrics = preload("res://scenes/battle_v2/ui/compact_hud_metrics.gd")
var shell: Control
var fade: Tween
var planning_visible := true
var clock_label: Label
var picker: Control
var flee: Button
var book: TextureRect
var mode_button: Button
var click_mode := false

func setup(host: Control) -> void:
	shell=host;name="PlanningUI";z_index=250;mouse_filter=Control.MOUSE_FILTER_IGNORE
	host.add_child(self)
	for control in [shell.hand_panel,shell.prompt_label,shell.pass_button,shell.draw_button,shell.cancel_button]:
		control.reparent(self,false)
	if shell.stage.shared_session==null:shell.deck_button.reparent(self,false)
	shell.hand.central_presentation=true
	shell.hand_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shell.prompt_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shell.prompt_label.add_theme_font_size_override("font_size",23)
	shell.prompt_label.add_theme_color_override("font_shadow_color",Color("10141e"))
	shell.prompt_label.add_theme_constant_override("shadow_outline_size",5)
	for button in [shell.pass_button,shell.draw_button,shell.cancel_button]:
		PlanningSkin.button(button);button.add_theme_font_size_override("font_size",24)
	book=TextureRect.new();book.name="DrawOrigin";book.mouse_filter=Control.MOUSE_FILTER_IGNORE
	book.texture=load("res://assets/art/ui/magic_card_box.png")
	book.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;book.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(book);shell.hand.draw_origin_control=book
	mode_button=Button.new();mode_button.name="OperationMode"
	mode_button.text="拖拽施法\n点击切换"
	mode_button.tooltip_text="切换为点击模式：点卡牌，再点高亮目标"
	PlanningSkin.button(mode_button);mode_button.add_theme_font_size_override("font_size",16)
	for state in ["normal","hover","pressed","disabled","focus"]:
		var cover:=StyleBoxFlat.new()
		cover.bg_color=Color(0.1,0.23,0.36,0.35 if state=="hover" else 0.15 if state=="pressed" else 0.0)
		cover.set_corner_radius_all(8)
		mode_button.add_theme_stylebox_override(state,cover)
	mode_button.add_theme_color_override("font_color",Color("f6dfaa"))
	add_child(mode_button)
	mode_button.pressed.connect(_toggle_mode)
	PlanningSkin.backing(shell.hand_panel)
	shell.hand.hand_layout_changed.connect(_align_book)
	shell.visibility_changed.connect(func():
		if shell.visible and planning_visible:
			if fade!=null and fade.is_valid():fade.kill()
			modulate.a=0.0
			fade=create_tween();fade.tween_property(self,"modulate:a",1.0,0.18))
	var action_preview=preload("res://scripts/fusion_3d/battle_action_hover.gd").new()
	action_preview.setup(shell)
	layout()

func attach_multiplayer(clock: Label, school: Control, escape: Button) -> void:
	clock_label=clock;picker=school;flee=escape
	for control in [clock_label,picker,flee]:control.reparent(self,false)
	PlanningSkin.button(flee)
	flee.add_theme_font_size_override("font_size",24)
	layout()

func place(control: Control, rect: Rect2) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.custom_minimum_size=Vector2.ZERO
	control.position=rect.position;control.size=rect.size

func layout() -> void:
	var viewport: Vector2=shell.size
	var factor:=minf(viewport.x/1920.0,viewport.y/1080.0)
	scale=Vector2.ONE*factor;size=Vector2(1100,500)
	position=Vector2(viewport.x*0.5,viewport.y*0.50)-Vector2(550,270)*factor
	place(shell.hand_panel,Rect2(50,162,1000,226))
	shell.hand.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	place(shell.prompt_label,Rect2(40,102,1020,44))
	place(shell.pass_button,Rect2(65,410,210,58))
	place(shell.draw_button,Rect2(445,410,210,58))
	place(shell.cancel_button,Rect2(445,475,210,46))
	_align_book()
	if shell.stage.shared_session==null:place(shell.deck_button,Rect2(book.position.x-16,410,170,48))
	if is_instance_valid(clock_label):place(clock_label,Rect2(490,-48,120,120))
	if is_instance_valid(flee):place(flee,Rect2(825,410,210,58))
	if is_instance_valid(picker):place(picker,Rect2(1158,228,84,84))
	# Only the visible card region blocks battlefield targeting; button hits are separate.
	shell.hand_safe_area=Rect2(position+Vector2(50,150)*factor,Vector2(1000,245)*factor)

func _align_book() -> void:
	if not is_instance_valid(book):return
	var first_x:=62.0
	if not shell.hand.cards.is_empty():first_x=shell.hand_panel.position.x+shell.hand.cards[0].layout_position.x
	place(book,Rect2(first_x-194,166,176,208))
	if is_instance_valid(mode_button):place(mode_button,Rect2(book.position+Vector2(33,74),Vector2(110,60)))
	if is_instance_valid(mode_button):mode_button.position=book.position+(book.size-mode_button.size)*0.5
	for card in shell.hand.cards:card.set_meta("click_selection",click_mode)

func _toggle_mode() -> void:
	shell.hand.cancel_drag()
	shell._cancel_selection()
	click_mode=not click_mode
	mode_button.text="点击施法\n点击切换" if click_mode else "拖拽施法\n点击切换"
	mode_button.tooltip_text="切换为拖拽模式" if click_mode else "切换为点击模式：点卡牌，再点高亮目标"
	_align_book()
	for card in shell.hand.cards:card.set_meta("click_selection",click_mode)

func blocks_pointer(global_point: Vector2) -> bool:
	if not planning_visible or not is_visible_in_tree():return false
	for control in [shell.pass_button,shell.draw_button,shell.cancel_button,shell.deck_button,picker,mode_button]:
		if is_instance_valid(control) and control.is_visible_in_tree() and control.get_global_rect().has_point(global_point):return true
	if is_instance_valid(flee) and flee.is_visible_in_tree() and flee.get_global_rect().has_point(global_point):return true
	if is_instance_valid(picker) and picker.expanded and picker.choices.get_global_rect().has_point(global_point):return true
	if shell.hand.cards.is_empty():return false
	var frame: Control=shell.hand_panel.get_node("CompactBacking")
	return frame.get_global_rect().grow(12.0*scale.x).has_point(global_point)

func set_planning(value: bool) -> void:
	if planning_visible==value:return
	planning_visible=value
	if fade!=null and fade.is_valid():fade.kill()
	if not value:
		shell.hand.cancel_drag()
		if is_instance_valid(picker):picker._reset_expansion()
	# Disable descendants as soon as resolution starts, rather than after the fade.
	process_mode=Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	for control in find_children("*","Control",true,false):
		if not value:
			control.set_meta("planning_mouse_filter",control.mouse_filter)
			control.mouse_filter=Control.MOUSE_FILTER_IGNORE
		elif control.has_meta("planning_mouse_filter"):
			control.mouse_filter=int(control.get_meta("planning_mouse_filter"))
			control.remove_meta("planning_mouse_filter")
	show()
	fade=create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(self,"modulate:a",1.0 if value else 0.0,0.18)
	if not value:fade.tween_callback(hide)

static func layout_roster(host: Control, local_team: int) -> void:
	var viewport: Vector2=host.size
	# Four fixed lanes per edge. Narrow windows shrink within a lane, never wrap.
	var canvas_scale:=maxf(0.01,host.get_viewport().get_stretch_transform().get_scale().x)
	var preferred: float=Metrics.scale_for(viewport*canvas_scale)/canvas_scale
	var lane_width:=viewport.x/4.0
	var margin:=24.0*minf(viewport.x/1920.0,viewport.y/1080.0)
	var roster_size:=Vector2(360,106)
	var factor:=minf(preferred,(lane_width-margin*2.0)/roster_size.x)
	var plate_size: Vector2=roster_size*factor
	for team in [local_team,1-local_team]:
		var units: Array=host.engine.state.team_units(team)
		units.sort_custom(func(a,b):return a.slot<b.slot)
		for index in units.size():
			var unit=units[index]
			if not host.unit_views.has(unit.id):continue
			var plate: Control=host.unit_views[unit.id].nameplate
			plate.set_reference_layout()
			plate.custom_minimum_size=roster_size;plate.size=roster_size;plate.scale=Vector2.ONE*factor
			var lane: int=3-unit.slot if team==local_team else unit.slot
			plate.position=Vector2((lane+0.5)*lane_width-plate_size.x*0.5,viewport.y-margin-plate_size.y if team==local_team else margin)
			plate.set_meta("hud_friendly",team==local_team)
			plate.set_orientation(UnitNameplateV2.Orientation.LEFT if team==local_team else UnitNameplateV2.Orientation.RIGHT)
			# Action preview occupies the reserved right side of the original plate.
			plate.action_badge.position=Vector2(298,30)

