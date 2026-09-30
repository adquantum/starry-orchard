class_name StatusDetailPanelV2
extends Control

const Text = preload("res://scripts/battle_v2/presentation/status_text_v2.gd")
const PanelSkin = preload("res://scenes/battle_v2/ui/compact_battle_skin.gd")
const Art = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const GROUPS := {
	"咒符":["blade", "weakness", "healing_blade", "infection", "accuracy_blade", "accuracy_weakness", "dispel"],
	"结界":["shield", "trap", "prism", "absorb", "stun_block"],
	"持续效果":["dot", "hot", "delay_damage", "stun"],
	"光环":["aura", "stat_modifier"],
	"场地":["global"]
}
var compact_mode := false
var unit: BattleUnitStateV2
var content: ContentRegistryV2
var global_status_provider: Callable
var close_delay := -1.0
var presentation_status_override: Array[StatusInstanceV2] = []
var use_presentation_status_override := false
var panel: PanelContainer
var rows_box: VBoxContainer
var scroll: ScrollContainer
var last_signature := ""

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): close_delay = -1.0)
	mouse_exited.connect(request_close)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := PanelSkin.panel(true)
	frame.content_margin_left = 20
	frame.content_margin_right = 20
	frame.content_margin_top = 18
	frame.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", frame)
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "状态详情"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("f4d994"))
	layout.add_child(title)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.add_theme_constant_override("separation", 7)
	scroll.add_child(rows_box)
	refresh()

func setup(p_unit: BattleUnitStateV2) -> void:
	unit = p_unit
	refresh()

func set_presentation_statuses(statuses: Array[StatusInstanceV2]) -> void:
	presentation_status_override = statuses.duplicate()
	use_presentation_status_override = true
	refresh()

func clear_presentation_statuses() -> void:
	presentation_status_override.clear()
	use_presentation_status_override = false
	refresh()

func _display_statuses() -> Array[StatusInstanceV2]:
	if unit == null: return []
	var result: Array[StatusInstanceV2] = (presentation_status_override if use_presentation_status_override else unit.statuses).duplicate()
	if global_status_provider.is_valid(): result.append_array(global_status_provider.call())
	return result

func refresh() -> void:
	if not is_instance_valid(rows_box): return
	var statuses := _display_statuses()
	var signature := JSON.stringify(statuses.map(func(status): return status.to_dict()))
	if signature == last_signature: return
	last_signature = signature
	for child in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()
	for group in GROUPS:
		var members: Array[StatusInstanceV2] = []
		for status in statuses:
			if str(status.kind) in GROUPS[group]: members.append(status)
		var heading := _label("%s  ·  %d" % [group, members.size()], 15, Color("e2c383"))
		var group_row := HBoxContainer.new()
		group_row.add_theme_constant_override("separation", 7)
		group_row.add_child(_icon({"咒符":"category_charm","结界":"category_ward","持续效果":"dot","光环":"aura","场地":"global"}[group], 22))
		group_row.add_child(heading)
		rows_box.add_child(group_row)
		if members.is_empty():
			rows_box.add_child(_label("当前无场地效果" if group == "场地" else "暂无", 13, Color("9eaabb")))
		for entry in _group_statuses(members):
			var status: StatusInstanceV2 = entry.status
			var data := status.to_dict()
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			rows_box.add_child(row)
			var icon := _icon(str(status.kind), 22)
			icon.tooltip_text = Text.kind_name(str(status.kind))
			row.add_child(icon)
			var info := VBoxContainer.new()
			info.add_theme_constant_override("separation", 1)
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(info)
			var source := Text.source_name(data, content)
			var count := int(entry.count)
			info.add_child(_label(source + ("  ×%d" % count if count > 1 else ""), 14, Color("fff0d0")))
			var harmful := status.kind in [&"weakness", &"infection", &"accuracy_weakness", &"trap", &"dot", &"delay_damage"] or str(status.payload.get("polarity", "")) == "harmful"
			var tint := Color("f1b39d") if harmful else Color("a2dfca")
			var summary := Text.value_text(data)
			if status.kind != &"prism": summary = Text.school_text(data) + "  ·  " + summary
			info.add_child(_label(summary, 13, tint))
		rows_box.add_child(HSeparator.new())
	size = Vector2(420, 570)
	custom_minimum_size = Vector2.ZERO

# Presentation grouping only: preserve every underlying status instance.
func _group_statuses(statuses: Array[StatusInstanceV2]) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for status in statuses:
		var identity := status.to_dict()
		identity.erase("instance_id")
		identity.erase("caster_id")
		var filters: Array = identity.school_filters.duplicate()
		filters.sort()
		identity.school_filters = filters
		identity.erase("school_filter")
		var found := false
		for entry in groups:
			if entry.identity == identity:
				entry.count += 1
				found = true
				break
		if not found: groups.append({"identity":identity, "status":status, "count":1})
	return groups

func _icon(id: String, pixels: int) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = Art.texture(StringName(id))
	icon.custom_minimum_size = Vector2(pixels,pixels)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _effect_line(icon_id: String, text: String, tint: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_icon(icon_id, 21))
	row.add_child(_label(text, 14, tint))
	return row

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = preload("res://scenes/battle_v2/ui/hover_text_v2.gd").clean(text)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func open_for(nameplate_size: Vector2, nameplate_rect: Rect2, viewport_size: Vector2) -> void:
	for other in get_tree().get_nodes_in_group("battle_status_hover"):
		if other!=self:other.hide()
	if not is_in_group("battle_status_hover"):add_to_group("battle_status_hover")
	refresh()
	var parent_scale: Vector2 = get_parent().get_global_transform().get_scale()
	size.y = minf(570, (viewport_size.y - 16) / parent_scale.y)
	var screen_size := size * parent_scale
	var screen_pos := nameplate_rect.position + Vector2(nameplate_size.x + 7, 0) * parent_scale
	if screen_pos.x + screen_size.x > viewport_size.x - 8:
		screen_pos.x = nameplate_rect.position.x - screen_size.x - 7
	screen_pos.x = clampf(screen_pos.x, 8, maxf(8, viewport_size.x - screen_size.x - 8))
	screen_pos.y = clampf(screen_pos.y, 8, maxf(8, viewport_size.y - screen_size.y - 8))
	position = (screen_pos - nameplate_rect.position) / parent_scale
	close_delay = -1.0
	visible = true

func request_close() -> void:
	close_delay = 0.18

func _process(delta: float) -> void:
	if not visible: return
	var owner_plate:=get_parent() as Control
	if not owner_plate.is_visible_in_tree() or bool(owner_plate.get_meta("suppress_hover_details",false)):
		hide();return
	# Child controls and the scrollbar are part of the same hover surface.
	if Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		close_delay = -1.0
		return
	if owner_plate.get_global_rect().has_point(owner_plate.get_global_mouse_position()):
		close_delay=-1.0
		return
	# Exit signals can be missed when a camera/HUD moves beneath the cursor.
	if close_delay < 0.0:close_delay=0.08
	close_delay -= delta
	if close_delay <= 0.0:
		visible = false
		close_delay = -1.0
