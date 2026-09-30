class_name BattleSceneShellV2
extends Control

signal battle_finished(winner_team: int)

const SlotConfigScript = preload("res://scripts/battle_v2/presentation/battle_slot_config_v2.gd")
const UnitViewScript = preload("res://scenes/battle_v2/presentation/battle_unit_view_v2.gd")
const ArrowScript = preload("res://scenes/battle_v2/presentation/target_arrow_renderer_v2.gd")
const ActionTokenScript = preload("res://scenes/battle_v2/ui/action_token_v2.gd")
const ThemeScript = preload("res://scripts/battle_v2/presentation/school_theme_v2.gd")
const LayoutProfile = preload("res://scripts/battle_v2/presentation/battle_layout_profile_v2.gd")
const ArcaneThemeScript = preload("res://scripts/battle_v2/presentation/arcane_ui_theme_v2.gd")
const PixelMetrics = preload("res://scripts/battle_v2/presentation/pixel_ui_metrics_v2.gd")
const MusicLibrary = preload("res://scripts/battle_v2/presentation/music_library_v2.gd")

enum UIState { PLANNING, CARD_SELECTED, TARGETING, ACTION_LOCKED, RESOLVING, BATTLE_END }

const STATE_NAMES := ["PLANNING", "CARD SELECTED", "TARGETING", "ACTION LOCKED", "RESOLVING", "BATTLE END"]

var content := ContentRegistryV2.new()
var engine := BattleEngineV2.new()
var ai := BasicAIPolicyV2.new()
var slot_configs := SlotConfigScript.default_slots()
var unit_views: Dictionary = {}
var ui_state := UIState.PLANNING
var active_actor: BattleUnitStateV2
var selected_card: CardInstanceV2
var selected_target_id: StringName = &""
var valid_target_ids: Array[StringName] = []
var resolving_actor_id: StringName = &""
var debug_mode := false
var active_music_track: StringName = &""
var music_context: StringName = &"combat_main"
var music_start_paused := false
var last_event_text := ""
@export var show_enemy_planned_actions := true
var action_token_cache: Dictionary = {}
var resolved_action_ids: Array[StringName] = []
var drag_target_id: StringName = &""
var drag_arrow_start := Vector2.ZERO
var hand_safe_area := Rect2()
var custom_decks: Dictionary = {}
@export var debug_ui_visible := true
var embedded_world_mode := false
var world_arena_center := Vector2.ZERO
var battle_finish_emitted := false


const NAMEPLATE_HAND_GAP := LayoutProfile.PLAYER_HUD_HAND_GAP
const CUSTOM_DECK_PATH := "user://battle_v2_custom_decks.json"
const FIRE_TEST_DECK_REVISION := 2

@onready var circle: Control = $BattleCircle
@onready var caster_pointer: ResolutionCasterPointerV2 = $CasterPointer
@onready var unit_layer: Control = $UnitLayer
@onready var hud_layer: Control = $HUDLayer
@onready var presentation_director: SpellPresentationDirectorV2 = $PresentationLayer
@onready var target_arrow: Control = $TargetArrow
@onready var hand_panel: Control = $HandPanel
@onready var hand: Control = $HandPanel/Hand
@onready var phase_label: Label = $TopBar/Bar/Phase
@onready var prompt_label: Label = $TopBar/Bar/Prompt
@onready var event_label: Label = $TopBar/Bar/Event
@onready var pass_button: Button = $ActionStrip/Row/Pass
@onready var draw_button: Button = $ActionStrip/Row/Draw
@onready var deck_button: Button = $DeckDock/Deck
@onready var action_strip: Control = $ActionStrip
@onready var deck_dock: Control = $DeckDock
@onready var action_dock_art: TextureRect = $ActionStrip/FrameArt
@onready var deck_dock_art: TextureRect = $DeckDock/FrameArt
@onready var hand_tray_art: TextureRect = $HandPanel/FrameArt
@onready var deck_builder: Control = $DeckBuilder
@onready var cancel_button: Button = $TopBar/Bar/Cancel
@onready var debug_toggle: CheckButton = $TopBar/Bar/Debug
@onready var speed_option: OptionButton = $TopBar/Bar/Speed
@onready var top_bar: Control = $TopBar
@onready var clean_view_button: Button = $TopBar/Bar/CleanView
@onready var layout_debug_overlay: Control = $LayoutDebugOverlay
@onready var battle_music: AudioStreamPlayer = $BattleMusic


func _ready() -> void:
	_apply_arcane_ui_theme()
	_start_battle_music()
	if not content.load_default():
		push_error("Battle V2 content failed: %s" % content.errors)
		return
	ai.profiles = content.ai_profiles
	var scenario := content.scenario(&"basic_4v4")
	var launch_data: Dictionary = {}
	if DemoSession.has_launch():
		launch_data = DemoSession.consume_launch()
		var encounter_id := StringName(str(launch_data.get("encounter_id", "")))
		scenario = content.encounter(encounter_id)
		scenario["teams"] = [
			launch_data.get("selected_team", []),
			scenario.get("enemy_units", []),
		]
	if not engine.setup(content, scenario, 20260816):
		push_error("Battle V2 shell setup failed")
		return
	_apply_launch_charge_schools(launch_data)
	_load_custom_decks()
	if launch_data.is_empty():
		_apply_saved_decks()
	engine.event_stream.subscribe(_on_battle_event)
	hand.card_selected.connect(_on_card_selected)
	hand.card_drag_started.connect(_on_card_drag_started)
	hand.card_drag_moved.connect(_on_card_drag_moved)
	hand.card_drag_ended.connect(_on_card_drag_ended)
	hand.card_discard_requested.connect(_on_card_discard_requested)
	pass_button.pressed.connect(_on_pass_pressed)
	draw_button.pressed.connect(_on_draw_pressed)
	deck_button.pressed.connect(_on_deck_pressed)
	deck_builder.apply_requested.connect(_on_deck_apply_requested)
	pass_button.icon = ArtRegistryV2.texture(&"ui_action_pass")
	draw_button.icon = ArtRegistryV2.texture(&"ui_action_draw")
	action_dock_art.texture = ArtRegistryV2.texture(&"ui_bottom_action_dock")
	deck_dock_art.texture = ArtRegistryV2.texture(&"ui_bottom_deck_dock")
	hand_tray_art.texture = ArtRegistryV2.texture(&"ui_bottom_hand_tray")
	pass_button.tooltip_text = "Lock a pass action for this wizard"
	draw_button.tooltip_text = "Spend a discard credit to draw one Treasure card"
	deck_button.tooltip_text = "Configure learned cards (0–40)"
	cancel_button.pressed.connect(_cancel_selection)
	debug_toggle.toggled.connect(_set_debug_mode)
	clean_view_button.pressed.connect(func(): set_debug_ui_visible(false))
	speed_option.add_item("1×", 0)
	speed_option.add_item("1.5×", 1)
	speed_option.add_item("2×", 2)
	speed_option.item_selected.connect(_on_presentation_speed_selected)
	resized.connect(_layout_units)
	_build_units()
	engine.start_battle()
	_begin_player_planning()
	_layout_units()

func set_world_overlay_mode(arena_center_screen: Vector2) -> void:
	embedded_world_mode = true
	world_arena_center = arena_center_screen
	if is_instance_valid(circle):
		circle.set_environment_visible(false)
	_layout_units()


func _battle_layout_offset(viewport_size: Vector2) -> Vector2:
	if not embedded_world_mode:
		return Vector2.ZERO
	return world_arena_center - LayoutProfile.battle_center(viewport_size)



func _start_battle_music() -> void:
	if music_start_paused:return
	active_music_track = MusicLibrary.play_random(battle_music, music_context)

func prepare_battle_music(context: StringName) -> void:
	battle_music.stop()
	battle_music.stream = null
	active_music_track = &""
	music_context = context
	music_start_paused = true

func set_music_paused(paused: bool) -> void:
	music_start_paused = paused
	if not paused and active_music_track == &"":
		_start_battle_music()
	elif not paused and not battle_music.playing and not battle_music.stream_paused:
		battle_music.play()
	battle_music.stream_paused = paused


func _apply_arcane_ui_theme() -> void:
	var shared_theme := Theme.new()
	shared_theme.set_stylebox("panel", "TooltipPanel", ArcaneThemeScript.style(ArcaneThemeScript.TOOLTIP, 18.0))
	shared_theme.set_color("font_color", "TooltipLabel", Color("#f3e7c7"))
	shared_theme.set_font_size("font_size", "TooltipLabel", 12)
	theme = shared_theme
	top_bar.add_theme_stylebox_override("panel", ArcaneThemeScript.style(ArcaneThemeScript.PANEL, 24.0))
	hand_panel.add_theme_stylebox_override("panel", ArcaneThemeScript.style(ArcaneThemeScript.PANEL, 24.0))
	action_strip.add_theme_stylebox_override("panel", ArcaneThemeScript.style(ArcaneThemeScript.PANEL_SMALL, 8.0))
	for button in [pass_button, draw_button, deck_button, cancel_button, clean_view_button]:
		ArcaneThemeScript.apply_button(button)
	ArcaneThemeScript.apply_button(speed_option)


func _build_units() -> void:
	for unit: BattleUnitStateV2 in engine.state.units:
		var view := UnitViewScript.new()
		view.clicked.connect(_on_unit_clicked)
		unit_layer.add_child(view)
		view.bind(unit, slot_configs[unit.id], content.characters.get(unit.character_id, {}) as Dictionary)
		view.detach_nameplate_to(hud_layer)
		unit_views[unit.id] = view


func _layout_units() -> void:
	if not is_node_ready():
		return
	var viewport_size := size
	var layout_offset := _battle_layout_offset(viewport_size)
	circle.set_environment_visible(not embedded_world_mode)
	circle.set_arena_offset(layout_offset)
	hand_safe_area = LayoutProfile.hand_safe_area(viewport_size)
	var hand_rect := LayoutProfile.hand_dock_rect(viewport_size)
	hand_panel.position = hand_rect.position
	hand_panel.size = hand_rect.size
	var action_rect := LayoutProfile.bottom_action_dock_rect(viewport_size)
	action_strip.position = action_rect.position
	action_strip.size = action_rect.size
	var deck_rect := LayoutProfile.bottom_deck_dock_rect(viewport_size)
	deck_dock.position = deck_rect.position
	deck_dock.size = deck_rect.size
	var center := LayoutProfile.battle_center(viewport_size) + layout_offset
	var spell_stage_center := LayoutProfile.spell_stage_center(viewport_size) + layout_offset
	caster_pointer.set_battle_center(spell_stage_center)
	presentation_director.set_battle_center(spell_stage_center)
	for id in unit_views:
		var config = slot_configs[id]
		var view: Control = unit_views[id]
		var visual_scale := LayoutProfile.character_scale(id, viewport_size)
		var anchor := LayoutProfile.slot_anchor(id, viewport_size) + layout_offset
		config.normalized_position = anchor / viewport_size
		view.scale = Vector2.ONE * visual_scale
		view.position = anchor - LayoutProfile.UNIT_LOCAL_FOOT * visual_scale
		view.z_index = 20 + roundi(anchor.y)
		view.apply_layout_geometry(center)
	_layout_hud_columns(viewport_size)
	if is_instance_valid(layout_debug_overlay):
		layout_debug_overlay.queue_redraw()


func _layout_hud_columns(viewport_size: Vector2) -> void:
	var metrics = preload("res://scenes/battle_v2/ui/compact_hud_metrics.gd")
	# Respect the project's canvas stretch while keeping this HUD readable at 720p.
	var canvas_scale := maxf(0.01, get_viewport().get_stretch_transform().get_scale().x)
	var ui_scale: float = metrics.scale_for(viewport_size * canvas_scale) / canvas_scale
	if not get_window().size_changed.is_connected(_on_hud_window_resized):
		get_window().size_changed.connect(_on_hud_window_resized)
	var plate_size: Vector2 = metrics.SIZE * ui_scale
	var top: float = metrics.TOP * ui_scale
	var local_team := int(call("_local_team")) if has_method("_local_team") else 0
	hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_hud_column(engine.state.team_units(local_team), true, top, metrics.GAP * ui_scale, plate_size, ui_scale, viewport_size)
	_layout_hud_column(engine.state.team_units(1 - local_team), false, top, metrics.GAP * ui_scale, plate_size, ui_scale, viewport_size)


func _on_hud_window_resized() -> void:
	if is_node_ready():
		_layout_hud_columns(size)


func _hud_gap(_count: int, _top: float, _bottom: float, _plate_height: float, ui_scale: float) -> float:
	return preload("res://scenes/battle_v2/ui/compact_hud_metrics.gd").GAP * ui_scale


func _layout_hud_column(units: Array[BattleUnitStateV2], left_column: bool, top: float, gap: float, plate_size: Vector2, ui_scale: float, viewport_size: Vector2) -> void:
	var metrics = preload("res://scenes/battle_v2/ui/compact_hud_metrics.gd")
	var x: float = metrics.MARGIN * ui_scale if left_column else viewport_size.x - metrics.MARGIN * ui_scale - plate_size.x
	for unit in units:
		if not unit_views.has(unit.id): continue
		var plate: Control = (unit_views[unit.id] as Control).nameplate
		plate.size = metrics.SIZE
		plate.scale = Vector2.ONE * ui_scale
		plate.position = Vector2(x, top + unit.slot * (plate_size.y + gap))
		plate.set_orientation(UnitNameplateV2.Orientation.RIGHT if left_column else UnitNameplateV2.Orientation.LEFT)


func _begin_player_planning() -> void:
	if engine.state.phase == BattleStateV2.Phase.FINISHED:
		_set_ui_state(UIState.BATTLE_END)
		_schedule_battle_finished()
		return
	active_actor = _next_unplanned_player()
	if active_actor != null and unit_views.has(active_actor.id):
		caster_pointer.set_planning_target((unit_views[active_actor.id] as Control).get_target_anchor_global(), ThemeScript.get_theme(active_actor.school_id).primary)
	selected_card = null
	selected_target_id = &""
	valid_target_ids.clear()
	if active_actor == null:
		_plan_enemies_and_resolve()
		return
	_set_ui_state(UIState.PLANNING)
	hand.show_hand(active_actor, engine)
	_refresh_all()


func _next_unplanned_player() -> BattleUnitStateV2:
	for unit: BattleUnitStateV2 in engine.state.team_units(0):
		if unit.alive and not engine.state.actions.has(unit.id):
			return unit
	return null


func _on_card_selected(card: CardInstanceV2) -> void:
	if ui_state not in [UIState.PLANNING, UIState.CARD_SELECTED, UIState.TARGETING] or active_actor == null:
		return
	selected_card = card
	selected_target_id = &""
	valid_target_ids.clear()
	engine.event_stream.publish(&"CardSelected", engine.state.round_index, {"unit_id": str(active_actor.id), "card_id": str(card.card_id()), "instance_id": card.instance_id})
	_set_ui_state(UIState.CARD_SELECTED)
	for target: BattleUnitStateV2 in engine.valid_targets(active_actor.id, card.instance_id):
		valid_target_ids.append(target.id)
	if valid_target_ids.is_empty():
		prompt_label.text = "No legal target — choose another card"
		return
	_set_ui_state(UIState.TARGETING)
	hand.set_selected(card.instance_id, true)
	_refresh_all()
	_show_click_target_guide()


func _on_unit_clicked(unit_id: StringName) -> void:
	if ui_state != UIState.TARGETING or selected_card == null or not valid_target_ids.has(unit_id):
		return
	selected_target_id = unit_id
	_refresh_all()
	if _uses_center_cast():
		target_arrow.hide_arrow()
		_lock_selected_action()
		return
	var pointer := get_viewport().get_mouse_position()
	var anchor: Vector2 = (unit_views[unit_id] as Control).get_target_selection_anchor_global()
	target_arrow.track_pointer(_selected_card_arrow_anchor(), pointer, ArrowScript.State.VALID, anchor)
	target_arrow.lock_arrow()
	_lock_selected_action()


func _on_card_drag_started(card: CardInstanceV2, origin_global: Vector2) -> void:
	if ui_state not in [UIState.PLANNING, UIState.CARD_SELECTED, UIState.TARGETING]:
		return
	drag_arrow_start = origin_global
	drag_target_id = &""
	_on_card_selected(card)
	if _uses_center_cast():
		target_arrow.hide_arrow()
		prompt_label.text = "拖到战斗盘中央松手施放"
		return
	var theme := ThemeScript.get_theme(card.definition.school_id)
	target_arrow.show_arrow(origin_global, get_viewport().get_mouse_position(), theme.accent)


func _on_card_drag_moved(_card: CardInstanceV2, pointer_global: Vector2, origin_global: Vector2) -> void:
	if ui_state != UIState.TARGETING:
		return
	drag_arrow_start = origin_global
	if _uses_center_cast():
		drag_target_id = _center_cast_target(pointer_global)
		selected_target_id = drag_target_id
		target_arrow.hide_arrow()
		_refresh_all()
		prompt_label.text = "松手施放" if drag_target_id != &"" else "拖到战斗盘中央松手施放"
		return
	drag_target_id = _nearest_drag_target(pointer_global)
	var state := ArrowScript.State.SEARCHING
	var snap_anchor := Vector2.INF
	if drag_target_id != &"":
		state = ArrowScript.State.VALID
		snap_anchor = (unit_views[drag_target_id] as Control).get_target_selection_anchor_global()
	elif _pointer_over_any_unit(pointer_global):
		state = ArrowScript.State.INVALID
	for view in hand.cards:
		view.set_invalid_target(view.card==selected_card and state==ArrowScript.State.INVALID)
	target_arrow.track_pointer(drag_arrow_start, pointer_global, state, snap_anchor)
	selected_target_id = drag_target_id
	_refresh_all()


func _on_card_drag_ended(_card: CardInstanceV2, _pointer_global: Vector2) -> void:
	if ui_state != UIState.TARGETING:
		target_arrow.hide_arrow()
		return
	if _uses_center_cast():
		drag_target_id = _center_cast_target(_pointer_global)
	else:
		drag_target_id = _nearest_drag_target(_pointer_global)
	if drag_target_id != &"" and valid_target_ids.has(drag_target_id):
		selected_target_id = drag_target_id
		if _uses_center_cast():target_arrow.hide_arrow()
		else:target_arrow.lock_arrow()
		_lock_selected_action()
	else:
		_cancel_selection()
	drag_target_id = &""


func _nearest_drag_target(pointer_global: Vector2) -> StringName:
	var nearest: StringName = &""
	var nearest_distance := INF
	for id in valid_target_ids:
		var view: Control = unit_views[id]
		if not view.contains_target_point(pointer_global):
			continue
		var distance := pointer_global.distance_to(view.get_target_selection_anchor_global())
		if distance < nearest_distance:
			nearest = id
			nearest_distance = distance
	return nearest


func _pointer_over_any_unit(pointer_global: Vector2) -> bool:
	for view: Control in unit_views.values():
		if view.contains_target_point(pointer_global):
			return true
	return false


func _lock_selected_action() -> void:
	if active_actor == null or selected_card == null:
		return
	var targets: Array[StringName] = [selected_target_id]
	var intent := ActionIntentV2.cast(active_actor.id, selected_card.instance_id, targets)
	if not engine.queue_action(intent):
		prompt_label.text = "Action rejected by Battle Core"
		return
	hand.animate_lock(selected_card.instance_id)
	engine.event_stream.publish(&"ActionLocked", engine.state.round_index, {"unit_id": str(active_actor.id), "card_id": str(selected_card.card_id()), "targets": Array(targets).map(func(id): return str(id))})
	_set_ui_state(UIState.ACTION_LOCKED)
	_refresh_all()
	await get_tree().create_timer(0.14).timeout
	target_arrow.hide_arrow()
	await get_tree().create_timer(0.08).timeout
	_begin_player_planning()


func _on_pass_pressed() -> void:
	if active_actor == null or ui_state not in [UIState.PLANNING, UIState.CARD_SELECTED, UIState.TARGETING]:
		return
	if engine.queue_pass(active_actor.id):
		engine.event_stream.publish(&"ActionLocked", engine.state.round_index, {"unit_id": str(active_actor.id), "pass": true})
		_set_ui_state(UIState.ACTION_LOCKED)
		await get_tree().create_timer(0.18).timeout
		_begin_player_planning()


func _on_draw_pressed() -> void:
	if active_actor == null or ui_state not in [UIState.PLANNING, UIState.CARD_SELECTED, UIState.TARGETING]:
		return
	if ui_state in [UIState.CARD_SELECTED, UIState.TARGETING]:
		_cancel_selection()
	var drawn := engine.draw_one_treasure(active_actor.id)
	if drawn == null:
		prompt_label.text = "Discard a normal card first to draw a Treasure"
		_refresh_all()
		return
	hand.show_hand(active_actor, engine)
	prompt_label.text = "Treasure drawn: %s" % str(drawn.card_id()).replace("_", " ").capitalize()
	_refresh_all()


func _on_card_discard_requested(card: CardInstanceV2) -> void:
	if active_actor == null or card == null or ui_state not in [UIState.PLANNING, UIState.CARD_SELECTED, UIState.TARGETING]:
		return
	if ui_state in [UIState.CARD_SELECTED, UIState.TARGETING]:
		_cancel_selection()
		return
	if not engine.discard_for_treasure(active_actor.id, card.instance_id):
		prompt_label.text = "This card cannot be discarded this round"
		return
	hand.show_hand(active_actor, engine)
	prompt_label.text = "Discarded — DRAW is ready for a Treasure"
	_refresh_all()


func _on_deck_pressed() -> void:
	if active_actor == null or ui_state not in [UIState.PLANNING, UIState.CARD_SELECTED, UIState.TARGETING]:
		return
	if ui_state in [UIState.CARD_SELECTED, UIState.TARGETING]:
		_cancel_selection()
	var character_key := str(active_actor.character_id)
	var counts := custom_decks.get(character_key, _default_deck_counts(active_actor)) as Dictionary
	var treasures: Array=[]
	for item in active_actor.deck.treasure_pile:treasures.append(str(item.definition.id))
	deck_builder.set_character_context(unit_views[active_actor.id].nameplate._display_name() if unit_views.has(active_actor.id) else str(active_actor.character_id),treasures)
	deck_builder.open(content, counts)


func _on_deck_apply_requested(card_counts: Dictionary) -> void:
	if active_actor == null:
		return
	if not engine.configure_deck(active_actor.id, card_counts):
		prompt_label.text = "Deck rejected — use 0–40 learned normal cards"
		return
	custom_decks[str(active_actor.character_id)] = card_counts.duplicate(true)
	_save_custom_decks()
	deck_builder.close()
	hand.show_hand(active_actor, engine)
	prompt_label.text = "Deck applied — opening hand redrawn"
	_refresh_all()


func _default_deck_counts(unit: BattleUnitStateV2) -> Dictionary:
	var character := content.characters.get(unit.character_id, {}) as Dictionary
	var deck_id := str(character.get("default_deck", ""))
	return (content.decks.get(deck_id, {}) as Dictionary).duplicate(true)


func _load_custom_decks() -> void:
	custom_decks.clear()
	if not FileAccess.file_exists(CUSTOM_DECK_PATH):
		custom_decks["__fire_test_deck_revision"] = FIRE_TEST_DECK_REVISION
		_save_custom_decks()
		return
	var file := FileAccess.open(CUSTOM_DECK_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		custom_decks = (parsed as Dictionary).duplicate(true)
	if int(custom_decks.get("__fire_test_deck_revision", 0)) < FIRE_TEST_DECK_REVISION:
		custom_decks.erase("fire_student")
		custom_decks["__fire_test_deck_revision"] = FIRE_TEST_DECK_REVISION
		_save_custom_decks()


func _save_custom_decks() -> void:
	var file := FileAccess.open(CUSTOM_DECK_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(custom_decks, "  "))


func _apply_saved_decks() -> void:
	var removed_retired_cards := false
	for unit: BattleUnitStateV2 in engine.state.team_units(0):
		var saved := custom_decks.get(str(unit.character_id), {}) as Dictionary
		if saved.is_empty():
			continue
		var valid := saved.duplicate(true)
		for card_id in valid.keys():
			if content.card(StringName(str(card_id))) == null:
				valid.erase(card_id)
				removed_retired_cards = true
		if not valid.is_empty():
			engine.configure_deck(unit.id, valid)
		custom_decks[str(unit.character_id)] = valid
	if removed_retired_cards:
		_save_custom_decks()


func _cancel_selection() -> void:
	for view in hand.cards:view.set_invalid_target(false)
	if ui_state == UIState.BATTLE_END:
		if embedded_world_mode:
			_schedule_battle_finished(0.0)
			return
		DemoSession.clear()
		get_tree().change_scene_to_file("res://scenes/battle_v2/demo_flow_v2.tscn")
		return
	if ui_state not in [UIState.CARD_SELECTED, UIState.TARGETING]:
		return
	target_arrow.cancel_arrow()
	hand.cancel_drag()
	selected_card = null
	selected_target_id = &""
	valid_target_ids.clear()
	_set_ui_state(UIState.PLANNING)
	hand.set_selected(-1, false)
	_refresh_all()


func _show_click_target_guide() -> void:
	if _uses_center_cast():
		target_arrow.hide_arrow()
		prompt_label.text = "拖到战斗盘中央松手施放，或点击中央"
		return
	if selected_card == null:
		return
	var start := _selected_card_arrow_anchor()
	var pointer := get_viewport().get_mouse_position()
	var theme := ThemeScript.get_theme(selected_card.definition.school_id)
	target_arrow.show_arrow(start, pointer, theme.accent)
	_update_target_guide(pointer)


func _selected_card_arrow_anchor() -> Vector2:
	if selected_card == null:
		return Vector2(size.x * 0.5, hand_safe_area.position.y)
	return hand.get_card_arrow_anchor_global(selected_card.instance_id)


func _update_target_guide(pointer_global: Vector2) -> void:
	if _uses_center_cast():
		target_arrow.hide_arrow()
		return
	if ui_state != UIState.TARGETING or selected_card == null:
		return
	var target_id := _nearest_drag_target(pointer_global)
	var state := ArrowScript.State.SEARCHING
	var snap_anchor := Vector2.INF
	if target_id != &"":
		state = ArrowScript.State.VALID
		snap_anchor = (unit_views[target_id] as Control).get_target_selection_anchor_global()
	elif _pointer_over_any_unit(pointer_global):
		state = ArrowScript.State.INVALID
	selected_target_id = target_id
	target_arrow.track_pointer(_selected_card_arrow_anchor(), pointer_global, state, snap_anchor)
	_refresh_all()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and ui_state == UIState.TARGETING and _uses_center_cast() and not hand.is_dragging_card():
		var automatic_target := _center_cast_target(event.global_position)
		if automatic_target != &"":
			selected_target_id = automatic_target
			_lock_selected_action()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseMotion and ui_state == UIState.TARGETING and not hand.is_dragging_card():
		_update_target_guide(event.global_position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if ui_state in [UIState.CARD_SELECTED, UIState.TARGETING] or hand.is_dragging_card():
			hand.cancel_drag()
			_cancel_selection()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if ui_state in [UIState.CARD_SELECTED, UIState.TARGETING]:
			_cancel_selection()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_F10:
		set_debug_ui_visible(not debug_ui_visible)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and is_node_ready():
		if ui_state in [UIState.CARD_SELECTED, UIState.TARGETING]:
			_cancel_selection()


func _plan_enemies_and_resolve() -> void:
	for unit: BattleUnitStateV2 in engine.state.team_units(1):
		if unit.alive and not engine.state.actions.has(unit.id):
			engine.queue_action(ai.choose_action(engine, unit))
	_set_ui_state(UIState.RESOLVING)
	active_actor = null
	valid_target_ids.clear()
	selected_target_id = &""
	hand.set_resolving(true)
	_refresh_all()
	await get_tree().create_timer(0.42).timeout
	engine.begin_resolution()
	for actor: BattleUnitStateV2 in engine.turn_manager.resolution_order(engine.state):
		if not actor.alive or not engine.state.actions.has(actor.id):
			continue
		resolving_actor_id = actor.id
		_refresh_all()
		var actor_view: Control = unit_views[actor.id]
		await caster_pointer.rotate_to_caster(actor_view.get_target_anchor_global(), ThemeScript.get_theme(actor.school_id).primary, 0.28)

		# Temporal effects resolve FIFO immediately before this unit's action.
		var frozen_turn_status_views: Array[Control] = []
		for view_value in unit_views.values():
			var frozen_turn_view: Control = view_value
			frozen_turn_view.set_presentation_statuses(frozen_turn_view.unit.statuses.duplicate())
			frozen_turn_status_views.append(frozen_turn_view)
		var turn_start_events := engine.begin_actor_turn(actor)
		await presentation_director.play_turn_start_events(turn_start_events, unit_views, frozen_turn_status_views)
		if engine.state.phase == BattleStateV2.Phase.FINISHED or not actor.alive:
			resolved_action_ids.append(actor.id)
			_refresh_all()
			if engine.state.phase == BattleStateV2.Phase.FINISHED:
				break
			continue

		var intent: ActionIntentV2 = engine.state.actions.get(actor.id)
		var card: CardDefinitionV2
		var target_views: Array[Control] = []
		var hp_before: Dictionary = {}
		if intent != null and not intent.pass_action:
			var instance := engine.card_in_hand(actor, intent.card_instance_id)
			if instance != null:
				card = instance.definition
				for target: BattleUnitStateV2 in engine.target_resolver.resolve_selected(engine.state, actor, card, intent.target_ids):
					var target_view: Control = unit_views.get(target.id)
					if target_view != null:
						target_views.append(target_view)
						hp_before[target.id] = target.hp
						target_view.nameplate.hold_presentation_hp(target.hp)

		# Freeze the pre-cast status picture. Core may add/consume statuses now,
		# but the visual change is released only at the presentation IMPACT marker.
		var frozen_status_views: Array[Control] = []
		for view_value in unit_views.values():
			var frozen_view: Control = view_value
			frozen_view.set_presentation_statuses(frozen_view.unit.statuses.duplicate())
			frozen_status_views.append(frozen_view)
		var action_events := engine.resolve_actor_action(actor)
		if card != null:
			await presentation_director.play_action(actor_view, target_views, card, action_events, hp_before, frozen_status_views)
		else:
			for frozen_view in frozen_status_views:
				frozen_view.clear_presentation_statuses()
			await get_tree().create_timer(0.22 / presentation_director.playback_speed).timeout
		resolved_action_ids.append(actor.id)
		_refresh_all()
		if engine.state.phase == BattleStateV2.Phase.FINISHED:
			break
	engine.end_resolution()
	caster_pointer.set_idle()
	resolving_actor_id = &""
	_refresh_all()
	await get_tree().create_timer(0.35).timeout
	if engine.state.phase == BattleStateV2.Phase.FINISHED:
		_set_ui_state(UIState.BATTLE_END)
		hand.clear_hand()
		_refresh_all()
		_schedule_battle_finished()
		return
	engine.start_next_round()
	action_token_cache.clear()
	resolved_action_ids.clear()
	hand.set_resolving(false)
	_begin_player_planning()



func _schedule_battle_finished(delay: float = 0.75) -> void:
	if battle_finish_emitted:
		return
	battle_finish_emitted = true
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if is_inside_tree():
		battle_finished.emit(engine.state.winner_team)


func _on_presentation_speed_selected(index: int) -> void:
	var speeds := [1.0, 1.5, 2.0]
	presentation_director.set_playback_speed(speeds[clampi(index, 0, speeds.size() - 1)])


func _set_ui_state(next: UIState) -> void:
	ui_state = next
	phase_label.text = "ROUND %d  ·  %s" % [engine.state.round_index, STATE_NAMES[ui_state]]
	match ui_state:
		UIState.PLANNING:
			prompt_label.text = "Choose a spell for %s" % _actor_name()
		UIState.CARD_SELECTED:
			prompt_label.text = "Card selected"
		UIState.TARGETING:
			prompt_label.text = "Choose a highlighted character or nameplate"
		UIState.ACTION_LOCKED:
			prompt_label.text = "Action locked"
		UIState.RESOLVING:
			prompt_label.text = "Spells are resolving — the stage is clear"
		UIState.BATTLE_END:
			prompt_label.text = "Victory" if engine.state.winner_team == 0 else "Defeat"
	pass_button.visible = ui_state in [UIState.PLANNING, UIState.CARD_SELECTED, UIState.TARGETING]
	draw_button.visible = pass_button.visible
	deck_button.visible = pass_button.visible
	action_strip.visible = pass_button.visible
	deck_dock.visible = pass_button.visible
	cancel_button.visible = ui_state in [UIState.CARD_SELECTED, UIState.TARGETING, UIState.BATTLE_END]
	cancel_button.text = "BACK TO TRIALS" if ui_state == UIState.BATTLE_END else "CANCEL"


func _refresh_all() -> void:
	if is_instance_valid(draw_button):
		draw_button.disabled = active_actor == null or active_actor.deck.hand.size() >= DeckStateV2.HAND_LIMIT or active_actor.deck.treasure_pile.is_empty() or active_actor.deck.treasure_draw_count_this_round >= active_actor.deck.discard_count_this_round + active_actor.deck.fusion_draw_credits or ui_state not in [UIState.PLANNING, UIState.CARD_SELECTED, UIState.TARGETING]
		draw_button.modulate = Color(1, 1, 1, 0.42) if draw_button.disabled else Color.WHITE
		deck_button.modulate = Color(1, 1, 1, 0.42) if deck_button.disabled else Color.WHITE
	for id in unit_views:
		var view: Control = unit_views[id]
		view.nameplate.status_detail_panel.content = content
		view.nameplate.status_detail_panel.global_status_provider = func(): return engine.state.global_statuses
		view.refresh()
		view.set_flags(
			active_actor != null and id == active_actor.id,
			valid_target_ids.has(id),
			selected_target_id == id,
			resolving_actor_id == id and ui_state == UIState.RESOLVING,
			debug_mode
		)
		_sync_action_token(id, view)
	event_label.text = last_event_text


func _on_battle_event(event: BattleEventV2) -> void:
	last_event_text = "#%03d  %s" % [event.sequence, str(event.type)]
	_route_status_presentation_event(event)
	match event.type:
		&"ActionQueued": _cache_action_token(event.payload)
		&"ActionTurnStarted": resolving_actor_id = StringName(str(event.payload.get("unit_id", "")))
		&"BattleEnded": ui_state = UIState.BATTLE_END
	_refresh_all()


func _set_debug_mode(value: bool) -> void:
	debug_mode = value
	hand.set_debug_cost_view(value)
	circle.set_debug_mode(value)
	layout_debug_overlay.visible = value
	layout_debug_overlay.queue_redraw()
	_refresh_all()


func set_debug_ui_visible(value: bool) -> void:
	debug_ui_visible = value
	top_bar.visible = value


func _apply_launch_charge_schools(launch_data: Dictionary) -> void:
	var charge_map := launch_data.get("charge_schools", {}) as Dictionary
	for unit: BattleUnitStateV2 in engine.state.team_units(0):
		var school := StringName(str(charge_map.get(str(unit.character_id), unit.resources.charge_school)))
		unit.resources.charge_school = school
		unit.resources.next_charge_school = school


func _route_status_presentation_event(event: BattleEventV2) -> void:
	var unit_id := StringName(str(event.payload.get("unit_id", event.payload.get("target_id", ""))))
	if unit_id == &"" or not unit_views.has(unit_id):
		return
	var kind := &""
	match event.type:
		&"StatusApplied":
			var status_data := event.payload.get("status", {}) as Dictionary
			kind = StringName(str(status_data.get("kind", "")))
		&"StatusConsumed": kind = StringName(str(event.payload.get("kind", event.payload.get("status_id", ""))))
		&"DotTicked": kind = &"dot"
		&"HotTicked": kind = &"hot"
		&"StatusExpired": kind = StringName(str(event.payload.get("kind", "delay_damage")))
	if kind != &"":
		(unit_views[unit_id] as Control).notify_status_event(kind)


func _actor_name() -> String:
	return str(active_actor.character_id).replace("_", " ").capitalize() if active_actor != null else "—"


func _cache_action_token(payload: Dictionary) -> void:
	var unit_id := StringName(str(payload.get("unit_id", "")))
	var unit := engine.state.unit_by_id(unit_id)
	if unit == null or unit.team == 1 and not show_enemy_planned_actions:
		return
	if bool(payload.get("pass", false)):
		action_token_cache[unit_id] = {"pass":true, "school":str(unit.school_id), "target_sigil":"pass"}
		return
	var card_id := StringName(str(payload.get("card_id", "")))
	var definition := content.card(card_id)
	if definition == null:
		return
	action_token_cache[unit_id] = {
		"card_id":str(card_id), "school":str(definition.school_id), "art_path":definition.art_path,
		"target_sigil":str(_target_sigil_for(definition, payload.get("targets", []) as Array))
	}


func _target_sigil_for(definition: CardDefinitionV2, targets: Array) -> StringName:
	match definition.target_type:
		&"all_enemies": return &"enemy_arc"
		&"all_allies": return &"ally_arc"
		&"global": return &"battle_circle"
	if not targets.is_empty():
		var target_id := StringName(str(targets[0]))
		if slot_configs.has(target_id):
			return slot_configs[target_id].sigil_id
	return &"battle_circle"


func _sync_action_token(unit_id: StringName, view: Control) -> void:
	var unit := engine.state.unit_by_id(unit_id)
	if unit == null or not unit.alive:
		view.clear_action_token()
		return
	if action_token_cache.has(unit_id):
		var data := action_token_cache[unit_id] as Dictionary
		var state := ActionTokenScript.State.PASSED if bool(data.get("pass", false)) else ActionTokenScript.State.LOCKED
		if resolving_actor_id == unit_id and ui_state == UIState.RESOLVING:
			state = ActionTokenScript.State.ACTIVE
		elif resolved_action_ids.has(unit_id):
			state = ActionTokenScript.State.COMPLETED
		view.show_action_token(data, state)
	else:
		view.clear_action_token()


func _uses_center_cast() -> bool:
	return selected_card != null and selected_card.definition.target_type in [&"self", &"all_allies", &"all_enemies"]

func _center_cast_target(pointer_global: Vector2) -> StringName:
	if not _uses_center_cast() or active_actor == null or valid_target_ids.is_empty():return &""
	var local_pointer := get_global_transform_with_canvas().affine_inverse() * pointer_global
	var drop_zone := Rect2(size * Vector2(0.28,0.18), size * Vector2(0.44,0.54))
	if not drop_zone.has_point(local_pointer):return &""
	return active_actor.id if selected_card.definition.target_type == &"self" else valid_target_ids[0]
