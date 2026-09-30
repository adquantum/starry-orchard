class_name BattleDemoFlowV2
extends Control

const ArcaneTheme = preload("res://scripts/battle_v2/presentation/arcane_ui_theme_v2.gd")
const SchoolTheme = preload("res://scripts/battle_v2/presentation/school_theme_v2.gd")
const UIFont = preload("res://assets/fonts/pixelify_sans/PixelifySans-Bold.ttf")
const BATTLE_SCENE := "res://scenes/battle_v2/battle_scene_shell.tscn"
const SCHOOL_ORDER := [&"fire", &"ice", &"storm", &"myth", &"life", &"death", &"balance"]

var content := ContentRegistryV2.new()
var selected_encounter: Dictionary = {}
var selected_team: Array[StringName] = []
var charge_schools: Dictionary = {}

var title_label: Label
var subtitle_label: Label
var encounter_panel: Control
var team_panel: Control
var team_grid: GridContainer
var team_status: Label
var launch_button: Button


func _ready() -> void:
	if not content.load_default():
		_show_load_error()
		return
	_build_background()
	_build_interface()
	_show_encounter_select()


func _build_background() -> void:
	var backdrop := TextureRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.texture = ArtRegistryV2.texture(&"background_arcane_academy_duel_hall")
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.modulate = Color(0.42, 0.48, 0.62, 0.82)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.012, 0.025, 0.055, 0.70)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)


func _build_interface() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 52)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_right", 52)
	margin.add_theme_constant_override("margin_bottom", 38)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	title_label = Label.new()
	title_label.text = "ARCANE ACADEMY - FIVE DUEL TRIALS"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_override("font", UIFont)
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", Color("#ffe2a3"))
	root.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_override("font", UIFont)
	subtitle_label.add_theme_font_size_override("font_size", 16)
	subtitle_label.add_theme_color_override("font_color", Color("#c8d4e8"))
	root.add_child(subtitle_label)

	var body := PanelContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_stylebox_override("panel", ArcaneTheme.style(ArcaneTheme.PANEL, 22.0, Color(0.92, 0.96, 1.0, 0.97)))
	root.add_child(body)

	var body_margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		body_margin.add_theme_constant_override("margin_" + side, 22)
	body.add_child(body_margin)

	var stack := Control.new()
	body_margin.add_child(stack)

	encounter_panel = VBoxContainer.new()
	encounter_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	encounter_panel.add_theme_constant_override("separation", 18)
	stack.add_child(encounter_panel)

	team_panel = VBoxContainer.new()
	team_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	team_panel.add_theme_constant_override("separation", 14)
	stack.add_child(team_panel)


func _show_encounter_select() -> void:
	selected_encounter.clear()
	selected_team.clear()
	charge_schools.clear()
	team_panel.visible = false
	encounter_panel.visible = true
	subtitle_label.text = "Choose a trial. Each encounter unlocks only its featured systems."
	_clear_children(encounter_panel)

	var heading := _label("SELECT ENCOUNTER", 22, Color("#fff0c0"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	encounter_panel.add_child(heading)

	var cards := HBoxContainer.new()
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 14)
	encounter_panel.add_child(cards)

	var ordered := content.encounters.values()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for encounter_value in ordered:
		cards.add_child(_encounter_card((encounter_value as Dictionary).duplicate(true)))


func _encounter_card(encounter: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 520)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _flat_panel(Color("#09152aee"), Color("#b68b42"), 2, 12))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var order := int(encounter.get("order", 0))
	var badge := _label("TRIAL %d" % order, 18, Color("#ffd36a"))
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(badge)

	var name := _label(str(encounter.get("display_name", "Unknown Trial")), 22, Color("#fff2d0"))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name)

	var level := _label("Recommended Level  %d" % int(encounter.get("recommended_level", 1)), 15, Color("#9fc7e8"))
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(level)

	var duel := _label("%dv%d" % [int(encounter.get("player_team_size", 4)), int(encounter.get("enemy_team_size", 4))], 30, Color("#f4c86a"))
	duel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(duel)

	var divider := HSeparator.new()
	column.add_child(divider)

	var mechanisms := encounter.get("mechanisms", []) as Array
	var mechanics_text := "FEATURES\n- " + "\n- ".join(mechanisms.map(func(value): return str(value).replace("_", " ").capitalize()))
	var mechanics := _label(mechanics_text, 15, Color("#d2d9e5"))
	mechanics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mechanics.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(mechanics)

	var button := Button.new()
	button.text = "BUILD TEAM"
	button.custom_minimum_size = Vector2(0, 58)
	ArcaneTheme.apply_button(button)
	button.pressed.connect(_select_encounter.bind(encounter))
	column.add_child(button)
	return panel


func _select_encounter(encounter: Dictionary) -> void:
	selected_encounter = encounter.duplicate(true)
	selected_team.clear()
	for value in selected_encounter.get("recommended_team", []):
		selected_team.append(StringName(str(value)))
	charge_schools.clear()
	for character_id in selected_team:
		var character := content.characters.get(character_id, {}) as Dictionary
		charge_schools[str(character_id)] = str(character.get("charge_school", character.get("school", "fire")))
	_show_team_select()


func _show_team_select() -> void:
	encounter_panel.visible = false
	team_panel.visible = true
	subtitle_label.text = "%s - SELECT %d WIZARDS" % [str(selected_encounter.get("display_name", "")), int(selected_encounter.get("player_team_size", 4))]
	_rebuild_team_panel()


func _rebuild_team_panel() -> void:
	_clear_children(team_panel)

	var header := HBoxContainer.new()
	team_panel.add_child(header)
	var back := Button.new()
	back.text = "< BACK TO TRIALS"
	back.custom_minimum_size = Vector2(170, 48)
	ArcaneTheme.apply_button(back)
	back.pressed.connect(_show_encounter_select)
	header.add_child(back)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	team_status = _label("", 18, Color("#ffe0a0"))
	team_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(team_status)

	team_grid = GridContainer.new()
	team_grid.columns = 4
	team_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	team_grid.add_theme_constant_override("h_separation", 14)
	team_grid.add_theme_constant_override("v_separation", 14)
	team_panel.add_child(team_grid)

	for value in selected_encounter.get("available_player_characters", []):
		team_grid.add_child(_character_card(StringName(str(value))))

	launch_button = Button.new()
	launch_button.text = "ENTER BATTLE"
	launch_button.custom_minimum_size = Vector2(320, 64)
	launch_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ArcaneTheme.apply_button(launch_button)
	launch_button.pressed.connect(_launch_battle)
	team_panel.add_child(launch_button)
	_refresh_team_status()


func _character_card(character_id: StringName) -> Control:
	var character := content.characters.get(character_id, {}) as Dictionary
	var school := StringName(str(character.get("school", "fire")))
	var accent: Color = SchoolTheme.get_theme(school).primary
	var selected := selected_team.has(character_id)

	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = selected
	button.custom_minimum_size = Vector2(330, 240)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_stylebox_override("normal", _flat_panel(Color("#071326f2"), accent.darkened(0.35), 2, 10))
	button.add_theme_stylebox_override("hover", _flat_panel(Color("#10213af5"), accent, 3, 10))
	button.add_theme_stylebox_override("pressed", _flat_panel(Color("#142843fa"), Color("#ffd768"), 4, 10))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.pressed.connect(_toggle_character.bind(character_id))

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	button.add_child(column)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)

	var badge := TextureRect.new()
	badge.custom_minimum_size = Vector2(72, 72)
	badge.texture = ArtRegistryV2.texture(StringName("school_badge_%s" % school))
	badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(badge)

	var info := VBoxContainer.new()
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var name := _label(_character_name(character_id), 20, Color("#fff0cb"))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name)
	var stats := _label("%s SCHOOL  -  HP %d" % [str(school).to_upper(), int(character.get("max_hp", 0))], 14, accent.lightened(0.28))
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(stats)

	var art_row := HBoxContainer.new()
	art_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_row.alignment = BoxContainer.ALIGNMENT_CENTER
	art_row.add_theme_constant_override("separation", 10)
	column.add_child(art_row)
	for texture in _representative_spell_textures(character):
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon.texture = texture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art_row.add_child(icon)

	var charge := OptionButton.new()
	charge.name = "ChargeSchool"
	charge.mouse_filter = Control.MOUSE_FILTER_STOP
	charge.custom_minimum_size = Vector2(0, 38)
	ArcaneTheme.apply_button(charge)
	for school_id in SCHOOL_ORDER:
		charge.add_item("CHARGE - %s" % str(school_id).to_upper())
		charge.set_item_metadata(charge.item_count - 1, str(school_id))
	var current := str(charge_schools.get(str(character_id), school))
	for index in charge.item_count:
		if str(charge.get_item_metadata(index)) == current:
			charge.select(index)
			break
	charge.item_selected.connect(_set_charge_school.bind(character_id, charge))
	column.add_child(charge)
	return button


func _toggle_character(character_id: StringName) -> void:
	var required := int(selected_encounter.get("player_team_size", 4))
	if selected_team.has(character_id):
		selected_team.erase(character_id)
	else:
		if selected_team.size() >= required:
			return
		selected_team.append(character_id)
		var character := content.characters.get(character_id, {}) as Dictionary
		charge_schools[str(character_id)] = str(character.get("charge_school", character.get("school", "fire")))
	_rebuild_team_panel()


func _set_charge_school(index: int, character_id: StringName, option: OptionButton) -> void:
	charge_schools[str(character_id)] = str(option.get_item_metadata(index))


func _launch_battle() -> void:
	var required := int(selected_encounter.get("player_team_size", 4))
	if selected_team.size() != required:
		return
	DemoSession.configure(StringName(str(selected_encounter.get("id", ""))), selected_team, charge_schools)
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _refresh_team_status() -> void:
	var required := int(selected_encounter.get("player_team_size", 4))
	team_status.text = "SELECTED %d / %d" % [selected_team.size(), required]
	launch_button.disabled = selected_team.size() != required


func _representative_spell_textures(character: Dictionary) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	var deck_id := str(character.get("default_deck", ""))
	var deck := content.decks.get(deck_id, {}) as Dictionary
	for card_id in deck:
		var card := content.card(StringName(str(card_id)))
		if card == null or card.art_path.is_empty():
			continue
		var texture := load(card.art_path) as Texture2D
		if texture != null:
			result.append(texture)
		if result.size() >= 3:
			break
	return result


func _character_name(character_id: StringName) -> String:
	return str(character_id).replace("_", " ").capitalize()


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_override("font", UIFont)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _flat_panel(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_border_width(side, width)
		style.set_corner_radius(side, radius)
		style.set_content_margin(side, 14)
	return style


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()


func _show_load_error() -> void:
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = "Battle V2 content failed:\n%s" % "\n".join(content.errors)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(label)
