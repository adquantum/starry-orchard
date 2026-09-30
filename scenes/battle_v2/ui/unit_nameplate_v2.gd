class_name UnitNameplateV2
extends Control

signal clicked(unit_id: StringName)
signal hover_changed(unit_id: StringName, hovered: bool)

enum Orientation { LEFT, RIGHT }

const Compact = preload("res://scenes/battle_v2/ui/compact_hud_metrics.gd")
const ColoredSchoolArt = preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd")
const StatusIconScript = preload("res://scenes/battle_v2/ui/status_icon_v2.gd")
const StatusDetailScript = preload("res://scenes/battle_v2/ui/status_detail_panel_v2.gd")
const ActionBadgeScript = preload("res://scenes/battle_v2/ui/action_token_v2.gd")
const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const RuneRegistryScript = preload("res://scripts/battle_v2/presentation/position_rune_registry_v2.gd")
const Metrics = preload("res://scripts/battle_v2/presentation/pixel_ui_metrics_v2.gd")
const SkinScript = preload("res://scripts/battle_v2/presentation/unit_hud_skin_definition_v2.gd")
const CharacterNameFont = preload("res://assets/fonts/pixelify_sans/PixelifySans-Bold.ttf")

const SCHOOL_COLORS := {
	"fire": Color("#f05b3d"), "ice": Color("#78c8f5"), "storm": Color("#a46cff"),
	"myth": Color("#e6b84b"), "life": Color("#63c96b"), "death": Color("#8d78a8"), "balance": Color("#d99b52")
}
const RUNE_VISUAL_OFFSETS := {
	&"crown": Vector2(4.5, 6.5), &"chalice": Vector2(1.5, 4.5), &"river": Vector2(1.5, 2.5), &"mountain": Vector2(0, 4.5),
	&"dagger": Vector2(-2.5, 0), &"eye": Vector2(1, -0.5), &"moon": Vector2(1.5, 0.5), &"tower": Vector2(4.5, 0)
}
const PIP_VISUAL_SIZE := Metrics.PIP_SIZE

var unit: BattleUnitStateV2
var rune_id: StringName = &"crown"
var hud_orientation: int = Orientation.RIGHT
var active := false
var valid_target := false
var selected_target := false
var debug_mode := false
var linked_hover := false
var displayed_hp := 0.0
var presentation_hp_override := -1.0
var _status_container: HBoxContainer
var _pip_textures: Dictionary = {}
var status_detail_panel: Control
var action_badge: Control
var rune_texture: Texture2D
var school_badge_texture: Texture2D
var skin: UnitHUDSkinDefinitionV2 = SkinScript.arcane_v5()
var presentation_status_override: Array[StatusInstanceV2] = []
var use_presentation_status_override := false
static var _fitted_textures: Dictionary = {}
var _panel_style: StyleBoxTexture
var _health_style: StyleBoxTexture
var _health_clip: Control
var _health_fill: NinePatchRect
var _aura_texture: Texture2D
var reference_layout := false

func set_reference_layout() -> void:
	if reference_layout:return
	reference_layout=true
	action_badge.set_reference_layout()
	queue_redraw()


func _ready() -> void:
	custom_minimum_size = Compact.SIZE
	size = Compact.SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel_style = _painted_style(&"hud_painted_panel", 110, 24)
	_panel_style.draw_center = false
	_health_style = _painted_style(&"hud_painted_hp_frame", 48, 4)
	_aura_texture = ArtRegistryScript.texture(&"hud_painted_aura")
	_health_clip = Control.new()
	_health_clip.clip_contents = true
	_health_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_health_clip)
	_health_fill = NinePatchRect.new()
	_health_fill.texture = ArtRegistryScript.texture(&"hud_painted_hp_fill")
	_health_fill.patch_margin_left = 60
	_health_fill.patch_margin_right = 60
	_health_fill.patch_margin_top = 50
	_health_fill.patch_margin_bottom = 50
	# Draw at the final bar size; clipping reveals HP without squeezing the endcaps.
	_health_fill.scale = Vector2(0.07, 0.07)
	_health_fill.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var fill_material := ShaderMaterial.new()
	fill_material.shader = preload("res://assets/game/nameplate_painted_v1/health_fill.gdshader")
	_health_fill.material = fill_material
	_health_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_clip.add_child(_health_fill)
	_status_container = HBoxContainer.new()
	_status_container.size = Vector2(82, 18)
	_status_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_container.alignment = BoxContainer.ALIGNMENT_END
	_status_container.add_theme_constant_override("separation", 1)
	add_child(_status_container)
	status_detail_panel = StatusDetailScript.new()
	status_detail_panel.compact_mode = true
	status_detail_panel.z_as_relative = false
	status_detail_panel.z_index = 2000
	add_child(status_detail_panel)
	action_badge = ActionBadgeScript.new()
	action_badge.compact_mode = true
	action_badge.z_index = 8
	add_child(action_badge)
	for id in [&"pip_v2_empty", &"pip_v2_normal", &"pip_v2_power", &"pip_v2_shadow", &"pip_v2_fire", &"pip_v2_ice", &"pip_v2_storm", &"pip_v2_myth", &"pip_v2_life", &"pip_v2_death", &"pip_v2_balance"]:
		_pip_textures[id] = _fit_texture(ArtRegistryScript.texture(id))
	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	set_process(true)
	_apply_orientation_layout()


func bind(p_unit: BattleUnitStateV2, p_rune_id: StringName) -> void:
	unit = p_unit
	rune_id = p_rune_id
	rune_texture = _fit_texture(ArtRegistryScript.texture(RuneRegistryScript.asset_id(rune_id)))
	school_badge_texture = _fit_texture(ColoredSchoolArt.ui_symbol(StringName("school_" + str(unit.school_id))))
	displayed_hp = float(unit.hp)
	tooltip_text=_display_name()
	status_detail_panel.setup(unit)
	tooltip_text = _display_name() + str(get_meta("public_action_detail", ""))
	_refresh_statuses()
	status_detail_panel.refresh()
	queue_redraw()


func set_orientation(value: int) -> void:
	hud_orientation = value
	_apply_orientation_layout()
	queue_redraw()


func refresh() -> void:
	if unit == null:
		return
	tooltip_text = _display_name() + str(get_meta("public_action_detail", ""))
	_refresh_statuses()
	status_detail_panel.refresh()
	queue_redraw()


func hold_presentation_hp(value: int) -> void:
	presentation_hp_override = float(value)
	displayed_hp = float(value)
	queue_redraw()


func release_presentation_hp() -> void:
	presentation_hp_override = -1.0
	queue_redraw()


func set_presentation_statuses(statuses: Array[StatusInstanceV2]) -> void:
	presentation_status_override = statuses.duplicate()
	use_presentation_status_override = true
	status_detail_panel.set_presentation_statuses(statuses)
	_refresh_statuses()
	queue_redraw()


func clear_presentation_statuses() -> void:
	presentation_status_override.clear()
	use_presentation_status_override = false
	status_detail_panel.clear_presentation_statuses()
	_refresh_statuses()
	queue_redraw()


func _display_statuses() -> Array[StatusInstanceV2]:
	if unit == null:
		return []
	return presentation_status_override if use_presentation_status_override else unit.statuses


func status_icon_count(kind: StringName = &"") -> int:
	var statuses := _display_statuses()
	return statuses.size() if kind == &"" else statuses.filter(func(status): return status.kind == kind).size()


func set_flags(p_active: bool, p_valid: bool, p_selected: bool, p_debug: bool) -> void:
	active = p_active
	valid_target = p_valid
	selected_target = p_selected
	debug_mode = p_debug
	queue_redraw()


func set_linked_hover(value: bool) -> void:
	linked_hover = value
	queue_redraw()


func show_action(data: Dictionary, state: int) -> void:
	action_badge.show_action(data, state)


func show_choosing(accent: Color) -> void:
	action_badge.show_choosing(accent)


func clear_action() -> void:
	action_badge.clear()


func _process(delta: float) -> void:
	if unit == null:
		return
	var visual_target_hp := presentation_hp_override if presentation_hp_override >= 0.0 else float(unit.hp)
	var next_hp := move_toward(displayed_hp, visual_target_hp, maxf(24.0, unit.max_hp * delta * 1.8))
	if not is_equal_approx(next_hp, displayed_hp):
		displayed_hp = next_hp
		queue_redraw()


func _draw() -> void:
	if unit == null:
		return
	var offset_y:=28.0 if reference_layout else 0.0
	var left := hud_orientation == Orientation.RIGHT
	var x := Compact.CONTENT_X if left or reference_layout else Compact.CONTENT_X + 4
	var width := 210.0 if reference_layout else Compact.CONTENT_WIDTH
	_draw_painted_style(_panel_style, Rect2(Vector2(0,offset_y), Compact.SIZE if reference_layout else size))
	var friendly: bool=bool(get_meta("hud_friendly",left))
	var color := Compact.FRIEND_HP if friendly else Compact.ENEMY_HP
	if active or valid_target or selected_target or linked_hover:
		var highlight := Color("ffe1a0") if selected_target or active else color
		draw_line(Vector2(x, 74+offset_y), Vector2(x + width, 74+offset_y), Color(highlight, 0.65), 2.0)
	if rune_texture != null:
		var rune_x := 6.0 if reference_layout else (0.0 if left else size.x - Compact.RUNE)
		var rune_size := 40.0 if reference_layout else Compact.RUNE
		draw_texture_rect(rune_texture, Rect2(rune_x, 46 if reference_layout else 0, rune_size, rune_size), false, Color("f3dfac"))
	if school_badge_texture != null:
		var school_rect:=Rect2(30,offset_y+40,24,24) if reference_layout else Rect2(6.0 if left else size.x-Compact.SCHOOL-6,14,Compact.SCHOOL,Compact.SCHOOL)
		draw_texture_rect(school_badge_texture,school_rect,false)
	var shown_name := _display_name()
	while ThemeDB.fallback_font.get_string_size(shown_name, HORIZONTAL_ALIGNMENT_LEFT, -1, Compact.NAME_FONT).x > width and shown_name.length() > 1:
		shown_name = shown_name.trim_suffix("…").left(shown_name.trim_suffix("…").length() - 1) + "…"
	_text(Vector2(x, 20+offset_y), shown_name, width, Compact.NAME_FONT)
	var hp_text := "%d / %d" % [roundi(displayed_hp), unit.max_hp]
	if displayed_hp <= 0: hp_text += " · 倒下"
	_text(Vector2(x, 37+offset_y), hp_text, width, Compact.AUX_FONT, Color("ffada5") if displayed_hp <= unit.max_hp * 0.2 else Compact.TEXT)
	var hp := Rect2(x, 40+offset_y, width, 11)
	_draw_painted_style(_health_style, hp)
	var fill_width := width - 10.0
	_health_clip.position = hp.position + Vector2(5, 2)
	_health_clip.size = Vector2(fill_width * clampf(displayed_hp / maxf(1, unit.max_hp), 0, 1), 7)
	_health_clip.visible = displayed_hp > 0
	_health_fill.size = Vector2(fill_width, 7) / 0.07
	(_health_fill.material as ShaderMaterial).set_shader_parameter("enemy", not friendly)
	var aura := displayed_aura()
	if aura != null:
		if _aura_texture != null:
			draw_texture_rect(_aura_texture, Rect2(x + width - 100, 23+offset_y, 17, 17), false)
		_text(Vector2(x + width - 80, 36+offset_y), "剩余 %d 回合" % aura.ticks, 80, 12, Color("ffe3a1"))
	for i in ResourceStateV2.MAX_PIPS:
		var at := Vector2(x + 7 + i * Compact.PIP_STEP, 60+offset_y)
		_draw_pip_texture(_main_pip_asset(i) if i < _display_resources().pips.size() else &"pip_v2_empty", at, Compact.PIP, Color.WHITE if i < _display_resources().pips.size() else Color(1, 1, 1, 0.45))
	if reference_layout:
		draw_set_transform(Vector2.ZERO)
		_draw_painted_style(_panel_style,Rect2(x-3,0,58,24))
	for i in ResourceStateV2.MAX_SHADOW_PIPS:
		var at := Vector2(x+15+i*23,12) if reference_layout else Vector2(x + Compact.SHADOW_X + i * Compact.PIP_STEP, 60+offset_y)
		draw_arc(at, 6.5, 0, TAU, 20, Color("ac8fce"), 1, true)
		if i < _display_resources().shadow_pips:
			_draw_pip_texture(&"pip_v2_shadow", at, Compact.PIP, Color.WHITE)
	if debug_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color.CYAN, false)


func _text(at: Vector2, value: String, width: float, font_size: int, color: Color = Compact.TEXT) -> void:
	draw_string_outline(ThemeDB.fallback_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, 3, Color(0.02, 0.03, 0.05, 0.8))
	draw_string(ThemeDB.fallback_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, color)


func _painted_style(asset: StringName, source_margin: float, display_margin: float) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = ArtRegistryScript.texture(asset)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, source_margin)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.set_meta("display_margin", display_margin)
	return style


func _draw_painted_style(style: StyleBoxTexture, rect: Rect2) -> void:
	var factor := float(style.get_meta("display_margin")) / style.get_texture_margin(SIDE_LEFT)
	draw_set_transform(rect.position, 0, Vector2.ONE * factor)
	draw_style_box(style, Rect2(Vector2.ZERO, rect.size / factor))
	draw_set_transform(Vector2.ZERO)


func displayed_aura() -> StatusInstanceV2:
	for status in _display_statuses():
		if status.kind == &"aura" and status.ticks > 0:
			return status
	return null


func _main_pip_asset(index: int) -> StringName:
	match _display_resources().pips[index]:
		ResourceStateV2.PipKind.NORMAL: return &"pip_v2_normal"
		ResourceStateV2.PipKind.POWER: return &"pip_v2_power"
		ResourceStateV2.PipKind.SCHOOL: return StringName("pip_v2_%s" % str(_display_resources().pip_schools[index]))
	return &"pip_v2_empty"


func _draw_pip_texture(texture_id: StringName, center: Vector2, visual_size: float, tint: Color) -> void:
	var pip_texture := _pip_textures.get(texture_id) as Texture2D
	if pip_texture != null:
		draw_texture_rect(pip_texture, Rect2(center - Vector2.ONE * visual_size * 0.5, Vector2.ONE * visual_size), false, tint)


func _fit_texture(texture: Texture2D) -> Texture2D:
	if texture == null: return null
	var key := texture.get_instance_id()
	if _fitted_textures.has(key): return _fitted_textures[key]
	var image := texture.get_image()
	if image == null: return texture
	if image.is_compressed(): image.decompress()
	var used := image.get_used_rect()
	if used.size == Vector2i.ZERO: return texture
	# Crop transparent padding only; keep the source pixels and aspect ratio.
	var side := float(maxi(used.size.x, used.size.y))
	var fitted := AtlasTexture.new()
	fitted.atlas = texture
	fitted.region = Rect2(Vector2(used.position) + Vector2(used.size) * 0.5 - Vector2.ONE * side * 0.5, Vector2.ONE * side)
	_fitted_textures[key] = fitted
	return fitted


func _draw_ui_texture(asset_id: StringName, rect: Rect2, tint: Color = Color.WHITE) -> void:
	var texture := ArtRegistryScript.texture(asset_id)
	if texture != null:
		draw_texture_rect(texture, rect, false, tint)


func _refresh_statuses() -> void:
	if _status_container == null:
		return
	for child in _status_container.get_children():
		_status_container.remove_child(child)
		child.queue_free()
	if unit == null:
		return
	var ordered: Array[StatusInstanceV2] = _display_statuses().duplicate()
	var priorities := {"blade":0, "weakness":1, "shield":2, "trap":3, "dot":4, "hot":5, "delay_damage":6}
	ordered.sort_custom(func(a: StatusInstanceV2, b: StatusInstanceV2): return int(priorities.get(str(a.kind), 99)) < int(priorities.get(str(b.kind), 99)))
	var grouped: Array[StatusInstanceV2] = []
	var counts: Array[int] = []
	var keys: Array[String] = []
	for status in ordered:
		if status.kind == &"aura":
			continue
		var key := "%s|%s|%s|%s|%s|%s" % [status.definition_id, status.kind, status.school_filters, status.value, status.ticks, JSON.stringify(status.payload)]
		var index := keys.find(key)
		if index < 0:
			keys.append(key)
			grouped.append(status)
			counts.append(1)
		else:
			counts[index] += 1
	var shown := 0
	for index in mini(3, grouped.size()):
		var icon := StatusIconScript.new()
		icon.setup(grouped[index], SCHOOL_COLORS.get(str(grouped[index].school_filter), Color("#d4b664")), counts[index])
		icon.custom_minimum_size = Vector2.ONE * Compact.STATUS
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_status_container.add_child(icon)
		shown += counts[index]
	var ordinary_count := ordered.filter(func(status): return status.kind != &"aura").size()
	if ordinary_count > shown:
		var more := Label.new()
		more.custom_minimum_size = Vector2(25, 17)
		more.text = "+%d" % (ordinary_count - shown)
		more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		more.add_theme_font_size_override("font_size", Compact.AUX_FONT)
		more.mouse_filter = Control.MOUSE_FILTER_IGNORE
		more.add_theme_color_override("font_color", Color("#f6d77b"))
		_status_container.add_child(more)


func _apply_orientation_layout() -> void:
	if _status_container == null:
		return
	if reference_layout:
		_status_container.position=Vector2(Compact.CONTENT_X+Compact.STATUS_X,79)
		return
	var left := hud_orientation == Orientation.RIGHT
	var x := Compact.CONTENT_X if left or reference_layout else Compact.CONTENT_X + 4
	_status_container.position = Vector2(x + Compact.STATUS_X, 51)
	_status_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	if action_badge != null:
		action_badge.position = Vector2(302 if left else 4, 2)


func _open_status_detail() -> void:
	if bool(get_meta("suppress_hover_details",false)):return
	if unit == null:
		return
	if reference_layout and action_badge.visible and action_badge.get_global_rect().has_point(get_global_mouse_position()):return
	status_detail_panel.open_for(size, get_global_rect(), get_viewport_rect().size)


func _on_mouse_entered() -> void:
	linked_hover = true
	hover_changed.emit(unit.id, true)
	_open_status_detail()
	queue_redraw()


func _on_mouse_exited() -> void:
	linked_hover = false
	hover_changed.emit(unit.id, false)
	status_detail_panel.request_close()
	queue_redraw()


func _display_name() -> String:
	var player_name:=str(get_meta("player_display_name",""))
	if not player_name.is_empty():return player_name
	if not str(unit.name_key).begins_with("UNIT_") and not str(unit.name_key).is_empty():return str(unit.name_key)
	return {"fire_student":"赤焰学徒", "ice_guardian":"霜铃守卫", "life_healer":"苔光医师", "storm_duelist":"雷羽术士", "myth_scholar":"神话学者", "death_reaper":"暮影法师", "balance_adept":"平衡学者", "garden_ember":"余烬芽灵", "garden_frost":"霜壳守护灵", "garden_bloom":"裂芽园丁", "garden_arc":"导雷芽灵", "ember_skeleton":"灰烬术士", "frost_golem":"寒霜魔像", "thorn_witch":"荆棘女巫", "storm_wraith":"暮雷幽灵"}.get(str(unit.character_id),str(unit.character_id).replace("_", " ").capitalize())


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clicked.emit(unit.id)


var presentation_resources: ResourceStateV2
func _display_resources() -> ResourceStateV2:
	return presentation_resources if presentation_resources!=null else unit.resources
func hold_presentation_resources() -> void:
	presentation_resources=ResourceStateV2.new()
	presentation_resources.pips.assign(unit.resources.pips)
	presentation_resources.pip_schools.assign(unit.resources.pip_schools)
	presentation_resources.shadow_pips=unit.resources.shadow_pips
	queue_redraw()
func release_presentation_resources() -> void:
	presentation_resources=null
	queue_redraw()
