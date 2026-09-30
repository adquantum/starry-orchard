class_name BattleHandViewV2
extends Control

signal card_selected(card: CardInstanceV2)
signal card_drag_started(card: CardInstanceV2, origin_global: Vector2)
signal card_drag_moved(card: CardInstanceV2, pointer_global: Vector2, origin_global: Vector2)
signal card_drag_ended(card: CardInstanceV2, pointer_global: Vector2)
signal card_discard_requested(card: CardInstanceV2)
signal hand_layout_changed

const CardViewScript = preload("res://scenes/battle_v2/ui/battle_card_view_v2.gd")

var actor: BattleUnitStateV2
var engine: BattleEngineV2
var selected_instance_id := -1
var targeting := false
var resolving := false
var resolving_tween: Tween
var cards: Array[Control] = []
var debug_cost_view := false
var draw_origin_control: Control
var previous_card_ids: Array[int] = []
var central_presentation := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_arrange)


func show_hand(p_actor: BattleUnitStateV2, p_engine: BattleEngineV2) -> void:
	var unchanged: bool=actor==p_actor and engine==p_engine and cards.size()==p_actor.deck.hand.size()
	if unchanged:
		for index in cards.size():
			if cards[index].card!=p_actor.deck.hand[index] or cards[index].locking:unchanged=false;break
	if unchanged:
		for view in cards:
			view.affordable=p_engine.cost_resolver.can_pay(p_actor,view.card.definition)
			if view.requirement_badge!=null:view.requirement_badge.setup(view.card.definition,view.affordable)
			view.queue_redraw()
		return
	previous_card_ids.clear()
	if actor == p_actor:
		for view in cards:previous_card_ids.append(view.card.instance_id)
	actor = p_actor
	engine = p_engine
	selected_instance_id = -1
	targeting = false
	resolving = false
	_rebuild()


func clear_hand() -> void:
	actor = null
	selected_instance_id = -1
	for card in cards:
		card.hide();card.queue_free()
	cards.clear()
	hand_layout_changed.emit()


func set_selected(instance_id: int, p_targeting: bool, p_confirmed: bool = false) -> void:
	selected_instance_id = instance_id
	targeting = p_targeting
	for view in cards:
		view.set_invalid_target(false)
		var chosen: bool = view.card.instance_id == selected_instance_id
		view.set_state(chosen, false, chosen and p_confirmed)


func set_resolving(value: bool) -> void:
	if resolving==value:return
	resolving = value
	if resolving_tween!=null and resolving_tween.is_valid():resolving_tween.kill()
	if central_presentation:
		# The common planning parent owns the fade, including its frame and buttons.
		position=Vector2.ZERO;modulate.a=1.0
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		return
	var tween := create_tween().set_parallel()
	resolving_tween=tween
	tween.tween_property(self, "modulate:a", 0.18 if value else 1.0, 0.22)
	tween.tween_property(self, "position:y", 74.0 if value else 0.0, 0.22).set_trans(Tween.TRANS_QUAD)
	mouse_filter = Control.MOUSE_FILTER_IGNORE if value else Control.MOUSE_FILTER_PASS


func set_debug_cost_view(value: bool) -> void:
	debug_cost_view = value
	for view in cards:
		view.set_debug_cost_view(value)


func animate_lock(instance_id: int) -> void:
	for view: Control in cards:
		if view.card.instance_id != instance_id:
			continue
		view.dragging = false
		view.locking = true
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tween := create_tween().set_parallel()
		tween.tween_property(view, "scale", Vector2.ONE * 0.36, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(view, "modulate:a", 0.0, 0.16)
		tween.tween_property(view, "position:y", -70.0, 0.18)
		break


func _rebuild() -> void:
	for child in cards:
		child.hide();child.queue_free()
	cards.clear()
	if actor == null:
		return
	for instance: CardInstanceV2 in actor.deck.hand:
		var view := CardViewScript.new()
		var payment_debug := engine.cost_resolver.available_payment_summary(actor, instance.definition) if OS.is_debug_build() else {}
		view.bind(instance, engine.cost_resolver.can_pay(actor, instance.definition), payment_debug)
		view.set_debug_cost_view(debug_cost_view)
		view.selected.connect(_on_card_selected)
		view.drag_started.connect(func(card: CardInstanceV2, origin: Vector2): card_drag_started.emit(card, origin))
		view.drag_moved.connect(func(card: CardInstanceV2, pointer: Vector2, origin: Vector2): card_drag_moved.emit(card, pointer, origin))
		view.drag_ended.connect(_on_card_drag_ended)
		view.discard_requested.connect(func(card: CardInstanceV2): card_discard_requested.emit(card))
		add_child(view)
		view.interaction.playable=true
		cards.append(view)
	_arrange()
	_animate_hand_entry()


func _animate_hand_entry() -> void:
	var deal_index := 0
	for view in cards:
		view.position = view.layout_position
		view.rotation = view.layout_rotation
		view.scale = Vector2.ONE
		if previous_card_ids.has(view.card.instance_id):continue
		if not is_instance_valid(draw_origin_control):continue
		var origin := get_global_transform().affine_inverse() * (draw_origin_control.get_global_transform() * (draw_origin_control.size*0.5))
		var destination: Vector2 = view.layout_position
		view.set_process(false)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		view.position = origin
		view.scale = Vector2.ONE*0.28
		view.rotation = -0.24
		view.modulate.a = 0.0
		view.z_index = 350
		var tween := view.create_tween()
		tween.tween_interval(deal_index*0.09)
		tween.tween_property(view,"modulate:a",1.0,0.08)
		tween.tween_method(func(t: float):
			view.position=origin.lerp(destination,t)+Vector2(0,-sin(t*PI)*120)
			view.scale=Vector2.ONE*lerpf(0.28,1.0,t)
			view.rotation=lerpf(-0.24,view.layout_rotation,t)
		,0.0,1.0,0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.tween_callback(func():
			view.mouse_filter=Control.MOUSE_FILTER_STOP
			view.set_process(true))
		deal_index+=1


func _arrange() -> void:
	if cards.is_empty():
		hand_layout_changed.emit()
		return
	var count := cards.size()
	var step := minf(142.0, maxf(78.0, (size.x - 162.0) / maxf(1.0, count - 1.0)))
	var total_width := 138.0 + step * float(count - 1)
	var start_x := (size.x - total_width) * 0.5
	for index in count:
		var view := cards[index]
		if view.dragging:
			continue
		var distance_from_center := float(index) - float(count - 1) * 0.5
		var layout_position := Vector2(start_x + step * index, 4.0 + absf(distance_from_center) * 0.4)
		var layout_rotation := deg_to_rad(distance_from_center * 0.35)
		view.set_layout_pose(layout_position, layout_rotation, index, view.position == Vector2.ZERO)
	hand_layout_changed.emit()


func get_card_arrow_anchor_global(instance_id: int) -> Vector2:
	for view: Control in cards:
		if view.card.instance_id == instance_id:
			return view.get_arrow_anchor_global()
	return global_position + Vector2(size.x * 0.5, 0)


func is_dragging_card() -> bool:
	for view: Control in cards:
		if view.dragging:
			return true
	return false


func cancel_drag() -> void:
	for view: Control in cards:
		if view.drag_controller != null:
			view.drag_controller.cancel_drag()


func _on_card_selected(card: CardInstanceV2) -> void:
	card_selected.emit(card)


func _on_card_drag_ended(card: CardInstanceV2, pointer: Vector2) -> void:
	card_drag_ended.emit(card, pointer)
	_arrange()
