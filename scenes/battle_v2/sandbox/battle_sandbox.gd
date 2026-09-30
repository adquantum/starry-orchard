class_name BattleSandboxV2
extends Control

var controller := BattleSandboxControllerV2.new()
var summary: RichTextLabel
var log_view: RichTextLabel
var unit_option: OptionButton
var target_option: OptionButton
var card_option: OptionButton
var status_option: OptionButton
var school_option: OptionButton
var hp_spin: SpinBox
var normal_spin: SpinBox
var power_spin: SpinBox
var school_pip_spin: SpinBox
var shadow_spin: SpinBox


func _ready() -> void:
	_build_ui()
	_reset()


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 7)
	add_child(root)
	var title := Label.new()
	title.text = "Battle V2 Sandbox · Intent / State / Event Viewer"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)

	var top_buttons := HBoxContainer.new()
	root.add_child(top_buttons)
	_add_button(top_buttons, "重置场景", _reset)
	_add_button(top_buttons, "AI规划全部", _plan_all)
	_add_button(top_buttons, "结算并进入下轮", _step_round)
	_add_button(top_buttons, "自动完成战斗", _auto_finish)

	var editor := GridContainer.new()
	editor.columns = 6
	root.add_child(editor)
	unit_option = OptionButton.new()
	unit_option.item_selected.connect(_sync_selected_unit)
	_add_field(editor, "编辑单位", unit_option)
	target_option = OptionButton.new()
	_add_field(editor, "施法目标", target_option)
	card_option = OptionButton.new()
	_add_field(editor, "卡牌", card_option)
	status_option = OptionButton.new()
	_add_field(editor, "状态", status_option)
	school_option = OptionButton.new()
	_add_field(editor, "学院/充能", school_option)
	hp_spin = _spin(0, 9999)
	_add_field(editor, "HP", hp_spin)
	normal_spin = _spin(0, 7)
	_add_field(editor, "普通豆", normal_spin)
	power_spin = _spin(0, 7)
	_add_field(editor, "超级豆", power_spin)
	school_pip_spin = _spin(0, 7)
	_add_field(editor, "学院豆", school_pip_spin)
	shadow_spin = _spin(0, 2)
	_add_field(editor, "暗影豆", shadow_spin)

	var edit_buttons := HBoxContainer.new()
	root.add_child(edit_buttons)
	_add_button(edit_buttons, "应用 HP/资源", _apply_unit_values)
	_add_button(edit_buttons, "塞入手牌", _give_card)
	_add_button(edit_buttons, "添加状态", _add_status)
	_add_button(edit_buttons, "清空状态", _clear_statuses)
	_add_button(edit_buttons, "指定施法", _queue_cast)
	_add_button(edit_buttons, "该单位跳过", _queue_pass)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	summary = RichTextLabel.new()
	summary.bbcode_enabled = true
	summary.custom_minimum_size.x = 570
	split.add_child(summary)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	split.add_child(log_view)


func _add_button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func _add_field(grid: GridContainer, label_text: String, control: Control) -> void:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	control.custom_minimum_size.x = 130
	grid.add_child(control)


func _spin(minimum: float, maximum: float) -> SpinBox:
	var result := SpinBox.new()
	result.min_value = minimum
	result.max_value = maximum
	result.step = 1
	return result


func _reset() -> void:
	controller = BattleSandboxControllerV2.new()
	controller.setup_default()
	_populate_options()
	_sync_selected_unit(0)
	_refresh()


func _populate_options() -> void:
	unit_option.clear()
	target_option.clear()
	for unit in controller.engine.state.units:
		for option in [unit_option, target_option]:
			option.add_item(str(unit.id))
			option.set_item_metadata(option.item_count - 1, str(unit.id))
	card_option.clear()
	var card_ids: Array = controller.content.cards.keys()
	card_ids.sort()
	for card_id in card_ids:
		card_option.add_item(str(card_id))
		card_option.set_item_metadata(card_option.item_count - 1, str(card_id))
	status_option.clear()
	var status_ids: Array = controller.content.statuses.keys()
	status_ids.sort()
	for status_id in status_ids:
		status_option.add_item(str(status_id))
		status_option.set_item_metadata(status_option.item_count - 1, str(status_id))
	school_option.clear()
	var school_ids: Array = controller.content.schools.keys()
	school_ids.sort()
	for school_id in school_ids:
		school_option.add_item(str(school_id))
		school_option.set_item_metadata(school_option.item_count - 1, str(school_id))


func _selected_id(option: OptionButton) -> StringName:
	return StringName(str(option.get_item_metadata(option.selected))) if option.item_count > 0 else &""


func _sync_selected_unit(_index: int) -> void:
	var unit := controller.engine.state.unit_by_id(_selected_id(unit_option))
	if unit == null:
		return
	hp_spin.max_value = unit.max_hp
	hp_spin.value = unit.hp
	normal_spin.value = unit.resources.pips.count(ResourceStateV2.PipKind.NORMAL)
	power_spin.value = unit.resources.pips.count(ResourceStateV2.PipKind.POWER)
	school_pip_spin.value = unit.resources.pips.count(ResourceStateV2.PipKind.SCHOOL)
	shadow_spin.value = unit.resources.shadow_pips
	for index in school_option.item_count:
		if _selected_id_at(school_option, index) == unit.resources.next_charge_school:
			school_option.select(index)
			break


func _selected_id_at(option: OptionButton, index: int) -> StringName:
	return StringName(str(option.get_item_metadata(index)))


func _apply_unit_values() -> void:
	var unit_id := _selected_id(unit_option)
	var school_id := _selected_id(school_option)
	controller.set_hp(unit_id, roundi(hp_spin.value))
	controller.set_resources(unit_id, roundi(normal_spin.value), roundi(power_spin.value), roundi(school_pip_spin.value), school_id, roundi(shadow_spin.value))
	controller.engine.set_next_charge(unit_id, school_id)
	_refresh()


func _give_card() -> void:
	controller.give_card_to_hand(_selected_id(unit_option), _selected_id(card_option))
	_refresh()


func _add_status() -> void:
	var unit_id := _selected_id(unit_option)
	var status_id := _selected_id(status_option)
	var definition := controller.content.statuses.get(status_id, {}) as Dictionary
	var kind := StringName(str(definition.get("kind", status_id)))
	var value := -25.0 if kind in [&"weakness", &"shield"] else 30.0
	var ticks := 3 if kind in [&"dot", &"hot", &"delay_damage"] else 0
	controller.apply_status(unit_id, status_id, &"sandbox", unit_id, value, ticks, _selected_id(school_option))
	_refresh()


func _clear_statuses() -> void:
	controller.clear_statuses(_selected_id(unit_option))
	_refresh()


func _queue_cast() -> void:
	controller.queue_direct_cast(_selected_id(unit_option), _selected_id(card_option), [_selected_id(target_option)])
	_refresh()


func _queue_pass() -> void:
	controller.skip_unit(_selected_id(unit_option))
	_refresh()


func _plan_all() -> void:
	controller.plan_all_with_ai()
	_refresh()


func _step_round() -> void:
	controller.run_one_round()
	_sync_selected_unit(unit_option.selected)
	_refresh()


func _auto_finish() -> void:
	controller.run_auto_battle()
	_sync_selected_unit(unit_option.selected)
	_refresh()


func _refresh() -> void:
	var state := controller.engine.state
	summary.clear()
	summary.append_text("[b]Round %d · %s · Winner %d[/b]\n" % [state.round_index, BattleStateV2.Phase.keys()[state.phase], state.winner_team])
	for unit in state.units:
		summary.append_text("%s  HP %d/%d  Hand %d  Deck %d  Pips %s  Shadow %d  Status %d  Action %s\n" % [
			str(unit.id), unit.hp, unit.max_hp, unit.deck.hand.size(), unit.deck.draw_pile.size(),
			str(unit.resources.snapshot().pips), unit.resources.shadow_pips, unit.statuses.size(),
			"queued" if state.actions.has(unit.id) else "-"
		])
	log_view.clear()
	var start := maxi(0, controller.engine.event_stream.events.size() - 100)
	for index in range(start, controller.engine.event_stream.events.size()):
		var event := controller.engine.event_stream.events[index]
		log_view.append_text("%04d  [b]%s[/b]  %s\n" % [event.sequence, str(event.type), JSON.stringify(event.payload)])
