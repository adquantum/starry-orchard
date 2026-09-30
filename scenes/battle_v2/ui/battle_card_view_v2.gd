class_name BattleCardViewV2
extends Control

signal selected(card: CardInstanceV2)
signal drag_started(card: CardInstanceV2, origin_global: Vector2)
signal drag_moved(card: CardInstanceV2, pointer_global: Vector2, origin_global: Vector2)
signal drag_ended(card: CardInstanceV2, pointer_global: Vector2)
signal discard_requested(card: CardInstanceV2)

const SCHOOL_COLORS := {
	"fire": Color("#f05b3d"), "ice": Color("#78c8f5"), "storm": Color("#a46cff"),
	"myth": Color("#e6b84b"), "life": Color("#63c96b"), "death": Color("#8d78a8"), "balance": Color("#d99b52")
}
const EffectRendererScript = preload("res://scenes/battle_v2/ui/card_effect_renderer_v2.gd")
const DragControllerScript = preload("res://scenes/battle_v2/ui/card_drag_controller_v2.gd")
const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const LayoutProfile = preload("res://scripts/battle_v2/presentation/battle_layout_profile_v2.gd")
const SkinScript = preload("res://scripts/battle_v2/presentation/card_skin_definition_v2.gd")
const SpellTitleFont = preload("res://assets/fonts/grenze/Grenze-Bold.ttf")
const SpellTomeTooltipScript = preload("res://scenes/battle_v2/ui/spell_tome_tooltip_v2.gd")

var card: CardInstanceV2
var is_selected := false
var dimmed := false
var action_confirmed := false
var affordable := true
var hover_amount := 0.0
var target_hover := 0.0
var pressed := false
var dragging := false
var press_global := Vector2.ZERO
var drag_offset := Vector2.ZERO
var art_texture: Texture2D
var school_texture: Texture2D
var skin: CardSkinDefinitionV2 = SkinScript.arcane_v2()
var locking := false
var effect_renderer: Control
var drag_controller: Node
var layout_position := Vector2.ZERO
var layout_rotation := 0.0
var layout_z_index := 0
var payment_debug: Dictionary = {}
var debug_cost_view := false
var interaction: Control
var requirement_badge: Control
var rules_pattern: TextureRect
var type_frame: Control
const Painted=preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd")
const Backplate=preload("res://scenes/battle_v2/ui/card_art_backplate_v3.gd")
const PhaseTokens=preload("res://scenes/battle_v2/ui/effect_tokens_v2.gd")
const TreasurePattern=preload("res://assets/ui/card_type_patterns_v2/treasure.png")
const EquipmentPattern=preload("res://assets/ui/card_type_patterns_v3/equipment.png")


func _ready() -> void:
	custom_minimum_size = LayoutProfile.HAND_CARD_SIZE
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): target_hover = 1.0)
	mouse_exited.connect(func(): target_hover = 0.0)
	gui_input.connect(_on_gui_input)
	type_frame=preload("res://scenes/battle_v2/ui/card_type_frame_v2.gd").new()
	type_frame.size=size
	type_frame.mouse_filter=Control.MOUSE_FILTER_IGNORE
	type_frame.show_behind_parent=true
	var frame_material:=ShaderMaterial.new()
	frame_material.shader=preload("res://assets/shaders/card_frame_palette_v2.gdshader")
	type_frame.material=frame_material
	add_child(type_frame)
	rules_pattern=TextureRect.new()
	rules_pattern.position=Vector2(10,143)
	rules_pattern.size=Vector2(size.x-20,size.y-155)
	rules_pattern.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	rules_pattern.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var pattern_material:=ShaderMaterial.new()
	pattern_material.shader=preload("res://assets/shaders/card_rules_pattern_v1.gdshader")
	rules_pattern.material=pattern_material
	add_child(rules_pattern)
	_update_rules_pattern()
	effect_renderer = EffectRendererScript.new()
	effect_renderer.position = LayoutProfile.CARD_EFFECT_RECT.position
	effect_renderer.size = LayoutProfile.CARD_EFFECT_RECT.size
	add_child(effect_renderer)
	interaction=preload("res://scenes/battle_v2/ui/card_interaction_v3.gd").new()
	add_child(interaction);interaction.setup(self)
	requirement_badge=preload("res://scenes/battle_v2/ui/card_requirement_badge_v3.gd").new()
	requirement_badge.position=Vector2(34,25);add_child(requirement_badge)
	var shade:=ShaderMaterial.new();shade.shader=preload("res://assets/shaders/card_unavailable_v3.gdshader");material=shade
	drag_controller = DragControllerScript.new()
	add_child(drag_controller)
	drag_controller.setup(self)
	var locale_node := _locale_node()
	if locale_node != null and not locale_node.language_changed.is_connected(_on_language_changed):
		locale_node.language_changed.connect(_on_language_changed)
	if card != null:
		effect_renderer.setup(card.definition)
		requirement_badge.setup(card.definition,affordable)
	set_process(true)


func bind(p_card: CardInstanceV2, p_affordable: bool, p_payment_debug: Dictionary = {}) -> void:
	card = p_card
	affordable = p_affordable
	payment_debug = p_payment_debug.duplicate(true)
	_update_rules_pattern()
	art_texture = load(card.definition.art_path) as Texture2D if card != null and not card.definition.art_path.is_empty() and ResourceLoader.exists(card.definition.art_path) else null
	school_texture = Painted.ui_symbol(StringName("school_%s" % str(card.definition.school_id))) if card != null else null
	if card != null and card.definition.tags.has(&"universal_aura"):
		school_texture = ArtRegistryV2.texture(&"school_badge_all")
	if effect_renderer != null:
		effect_renderer.setup(card.definition)
	if requirement_badge!=null:requirement_badge.setup(card.definition,affordable)
	tooltip_text = _card_tooltip()
	queue_redraw()


func set_invalid_target(value: bool) -> void:
	if interaction!=null:interaction.invalid_target=value;interaction.sync()

func _update_rules_pattern() -> void:
	if rules_pattern==null:return
	rules_pattern.texture=null
	if card!=null and card.definition!=null:
		if card.equipment or card.definition.tags.has(&"equipment"):rules_pattern.texture=EquipmentPattern
		elif card.definition.treasure:rules_pattern.texture=TreasurePattern
	rules_pattern.visible=rules_pattern.texture!=null
	var equipment: bool=card!=null and (card.equipment or card.definition.tags.has(&"equipment"))
	var treasure: bool=card!=null and card.definition.treasure and not equipment
	type_frame.material.set_shader_parameter("palette",Vector3(0.68,1.10,1.46) if equipment else Vector3(1.45,0.91,0.40))
	type_frame.material.set_shader_parameter("strength",0.9 if equipment or treasure else 0.0)

func set_debug_cost_view(value: bool) -> void:
	debug_cost_view = value
	tooltip_text = _card_tooltip()


func set_state(p_selected: bool, p_dimmed: bool, p_confirmed: bool = false) -> void:
	is_selected = p_selected
	dimmed = p_dimmed
	action_confirmed = p_confirmed
	queue_redraw()


func _process(delta: float) -> void:
	if interaction!=null:
		interaction.sync()
		(material as ShaderMaterial).set_shader_parameter("unavailable",1.0 if dimmed or not affordable else 0.0)
		(rules_pattern.material as ShaderMaterial).set_shader_parameter("unavailable",1.0 if dimmed or not affordable else 0.0)
		(type_frame.material as ShaderMaterial).set_shader_parameter("unavailable",1.0 if dimmed or not affordable else 0.0)
		modulate=Color(0.18,0.18,0.18,modulate.a) if action_confirmed else Color(1,1,1,modulate.a)
	if dragging or locking or drag_controller == null:
		return
	var hovered_control:=get_viewport().gui_get_hovered_control()
	var pointer_hover:=hovered_control!=null and (hovered_control==self or is_ancestor_of(hovered_control)) and not dimmed and not action_confirmed
	var desired := 1.0 if pointer_hover or is_selected else 0.0
	var next := move_toward(hover_amount, desired, delta * 7.0)
	var previous_hover:=hover_amount
	hover_amount = next
	var click_selected:=bool(get_meta("click_selection",false)) and is_selected and not action_confirmed
	var target_scale:=1.30 if pointer_hover else (1.08 if click_selected else 1.0)
	var target_position := layout_position - Vector2(size.x*(target_scale-1.0)*0.5, 38.0 if pointer_hover else 22.0 if click_selected else hover_amount * 6.0)
	var response := 1.0 - exp(-delta * 16.0)
	position = position.lerp(target_position, response)
	scale = scale.lerp(Vector2.ONE * target_scale, response)
	rotation = lerp_angle(rotation, layout_rotation * (1.0 - hover_amount * 0.35), response)
	z_index = 300 if hover_amount > 0.02 else layout_z_index
	if not is_equal_approx(next, previous_hover):
		queue_redraw()


func set_layout_pose(p_position: Vector2, p_rotation: float, p_z_index: int, immediate := false) -> void:
	layout_position = p_position
	layout_rotation = p_rotation
	layout_z_index = p_z_index
	if immediate:
		position = layout_position
		rotation = layout_rotation
		z_index = layout_z_index


func restore_layout_pose() -> void:
	if locking:
		return
	z_index = layout_z_index


func get_arrow_anchor_global() -> Vector2:
	return get_global_transform() * Vector2(size.x * 0.5, 3.0)


func _draw() -> void:
	if card == null or card.definition == null:
		return
	var definition := card.definition
	var accent: Color = SCHOOL_COLORS.get(str(definition.school_id), Color.WHITE)
	var alpha := 1.0
	var equipment: bool=card.equipment or definition.tags.has(&"equipment")
	var trim: Color=Color("b5ddf4") if equipment else Color("edc779")
	var art_rect := LayoutProfile.CARD_ART_RECT
	Backplate.draw_backplate(self,art_rect.grow(-3),str(definition.school_id),hover_amount)
	draw_line(Vector2(14,137),Vector2(size.x-14,137),Color(accent,0.35),1)
	var title_rect := LayoutProfile.CARD_TITLE_RECT
	var title := _name().to_upper()
	var title_size := _fitted_title_size(title, title_rect.size.x - 6.0)
	var title_baseline := title_rect.position + Vector2(3, 17)
	draw_string(SpellTitleFont, title_baseline + Vector2(1, 1), title, HORIZONTAL_ALIGNMENT_CENTER, title_rect.size.x - 6, title_size, Color(0.08, 0.035, 0.025, 0.90 * alpha))
	draw_string(SpellTitleFont, title_baseline, title, HORIZONTAL_ALIGNMENT_CENTER, title_rect.size.x - 6, title_size, Color(trim if equipment or definition.treasure else accent.lerp(Color("#fff0c4"), 0.82), alpha))
	draw_line(Vector2(29,29),Vector2(109,29),Color(PhaseTokens.accent(str(definition.school_id)),.25+hover_amount*.15),1)
	if art_texture != null:
		var spell_rect := _contain_rect(art_texture.get_size(), art_rect.grow(-3))
		draw_texture_rect(art_texture, spell_rect, false, Color(1, 1, 1, alpha))
	else:
		draw_arc(art_rect.get_center(), 25, 0, TAU, 28, Color(accent, alpha), 4)
		var symbol := _effect_symbol()
		draw_string(ThemeDB.fallback_font, art_rect.get_center() + Vector2(-20, 7), symbol, HORIZONTAL_ALIGNMENT_CENTER, 40, 20, Color(1, 1, 1, alpha))
	var cost_center := LayoutProfile.CARD_COST_CENTER
	var school_center := LayoutProfile.CARD_SCHOOL_CENTER
	preload("res://scenes/battle_v2/ui/compact_battle_skin.gd").roundel(self,cost_center,15,trim if equipment or definition.treasure else Color("bda86e"))
	draw_string(ThemeDB.fallback_font, cost_center + Vector2(-13, 5), definition.cost_label(), HORIZONTAL_ALIGNMENT_CENTER, 26, 14, Color(1, 0.91, 0.62, alpha))
	preload("res://scenes/battle_v2/ui/compact_battle_skin.gd").roundel(self,school_center,15,accent)
	if school_texture != null:
		draw_texture_rect(school_texture, Rect2(school_center - Vector2.ONE * 11.0, Vector2.ONE * 22.0), false, Color(1, 1, 1, alpha))
	else:
		draw_string(ThemeDB.fallback_font, school_center + Vector2(-4, 4), str(definition.school_id).left(1).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 9, 11, Color(1, 0.94, 0.75, alpha))


func _draw_skin_piece(asset_id: StringName, rect: Rect2, tint: Color = Color.WHITE) -> void:
	if get_meta("refined",false):
		if asset_id == skin.card_bg:
			draw_style_box(preload("res://scripts/fusion_3d/combat_scroll_skin.gd").style(true),rect.grow(4))
		elif asset_id == skin.card_outer_frame:
			pass
		elif asset_id in [skin.card_header,skin.card_art_frame,skin.card_effect_panel,skin.cost_holder,skin.school_holder]:
			var component_ids := {skin.card_header: &"card_component_title",skin.card_art_frame: &"card_component_art",skin.card_effect_panel: &"card_component_description",skin.cost_holder: &"card_component_cost",skin.school_holder: &"card_component_school"}
			var component := ArtRegistryScript.texture(component_ids[asset_id])
			if component != null:
				if asset_id == skin.card_effect_panel: _draw_description_frame(component,rect,tint.a)
				elif asset_id in [skin.cost_holder,skin.school_holder]: draw_texture_rect(component,_contain_rect(component.get_size(),rect),false,Color(1,1,1,tint.a))
				else: draw_style_box(preload("res://scripts/fusion_3d/combat_scroll_skin.gd").sliced(component),rect)
		elif asset_id == skin.disabled_overlay:
			draw_rect(rect,Color(0.03,0.045,0.075,0.38))
		elif asset_id == skin.selected_overlay or asset_id == skin.hover_overlay:
			draw_rect(rect.grow(-7),Color("c2b58a"),false,1.5)
		return
	var texture := ArtRegistryScript.texture(asset_id)
	if texture != null:
		draw_texture_rect(texture, rect, false, tint)


func _draw_description_frame(texture: Texture2D, rect: Rect2, alpha: float) -> void:
	# Independently scale the painted border to three pixels, keeping the content rectangle intact.
	var source_size := texture.get_size()
	var source_x := [0.0,source_size.x*0.05,source_size.x*0.95,source_size.x]
	var source_y := [0.0,source_size.y*0.16,source_size.y*0.88,source_size.y]
	var target_x := [rect.position.x,rect.position.x+3.0,rect.end.x-3.0,rect.end.x]
	var target_y := [rect.position.y,rect.position.y+3.0,rect.end.y-3.0,rect.end.y]
	for y in 3:
		for x in 3:
			var source := Rect2(source_x[x],source_y[y],source_x[x+1]-source_x[x],source_y[y+1]-source_y[y])
			var target := Rect2(target_x[x],target_y[y],target_x[x+1]-target_x[x],target_y[y+1]-target_y[y])
			draw_texture_rect_region(texture,target,source,Color(1,1,1,alpha))


func _fitted_title_size(title: String, safe_width: float) -> int:
	for font_size in range(14, 6, -1):
		if SpellTitleFont.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= safe_width:
			return font_size
	return 6


func _name() -> String:
	if get_meta("refined",false) and card != null:
		var names := {"fire_serpent":"火蛇","school_flare":"烈焰闪击","dragon_meteor":"陨星龙","thunder_lance":"雷电长枪","tempest_crown":"风暴王冠","phoenix_revive":"凤凰复苏","verdant_rebirth":"青枝重生","crystal_aegis":"晶体屏障"}
		if names.has(str(card.card_id())): return names[str(card.card_id())]
	if card != null and card.definition != null:
		var locale_node := _locale_node()
		if locale_node != null:
			var key := str(card.definition.name_key)
			var localized := str(locale_node.call("text", key))
			if not localized.is_empty() and localized != key:
				return localized
		var literal := str(card.definition.name_key)
		if not literal.is_empty() and not literal.begins_with("CARD_"):return literal
	return str(card.card_id()).replace("_", " ").capitalize()


func _locale_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Locale")


func _on_language_changed() -> void:
	tooltip_text = _card_tooltip()
	queue_redraw()


func _effect_symbol() -> String:
	var effect: Dictionary = card.definition.effects[0] if not card.definition.effects.is_empty() else {}
	return {"damage":"✦", "heal":"+", "apply_status":"◇", "apply_dot":"D", "apply_hot":"H", "delay_damage":"Δ", "revive":"R"}.get(str(effect.get("type", "")), "?")


func _effect_text() -> String:
	var effect: Dictionary = card.definition.effects[0] if not card.definition.effects.is_empty() else {}
	var type := str(effect.get("type", ""))
	match type:
		"damage": return "%d DMG" % int(effect.get("power", 0))
		"heal": return "+%d HP" % int(effect.get("power", 0))
		"apply_status": return "%+.0f%% %s" % [float(effect.get("value", 0)), str(effect.get("status", ""))]
		"apply_dot": return "%d × %d DOT" % [int(effect.get("damage_per_tick", 0)), int(effect.get("ticks", 0))]
		"apply_hot": return "%d × %d HOT" % [int(effect.get("healing_per_tick", 0)), int(effect.get("ticks", 0))]
		"delay_damage": return "%d DELAY" % int(effect.get("power", 0))
		"revive": return "+%d REVIVE" % int(effect.get("power", 0))
	return type.to_upper()


func _target_symbol() -> String:
	return {"enemy":"TARGET: ENEMY", "ally":"TARGET: ALLY", "dead_ally":"TARGET: DOWN ALLY", "all_enemies":"ALL ENEMIES", "all_allies":"ALL ALLIES"}.get(str(card.definition.target_type), str(card.definition.target_type).to_upper())


func _card_tooltip() -> String:
	if card == null:
		return ""
	return "%s · %s · %s Pip" % [_name(), str(card.definition.school_id).capitalize(), card.definition.cost_label()]


func _make_custom_tooltip(_for_text: String) -> Object:
	var tooltip := SpellTomeTooltipScript.new()
	tooltip.setup(card.definition, payment_debug, debug_cost_view)
	tooltip.art_texture=art_texture
	tooltip.display_title=_name()
	return tooltip


func _panel(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.corner_radius_top_left = 9
	box.corner_radius_top_right = 9
	box.corner_radius_bottom_left = 9
	box.corner_radius_bottom_right = 9
	return box


func _contain_rect(source_size: Vector2, bounds: Rect2) -> Rect2:
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return bounds
	var scale := minf(bounds.size.x / source_size.x, bounds.size.y / source_size.y)
	var fitted := source_size * scale
	return Rect2(bounds.get_center() - fitted * 0.5, fitted)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		discard_requested.emit(card)
		accept_event()
		return
	if drag_controller != null:
		drag_controller.handle_gui_input(event)
