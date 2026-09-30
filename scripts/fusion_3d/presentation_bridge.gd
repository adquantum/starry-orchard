extends "res://scenes/battle_v2/presentation/spell_presentation_director_v2.gd"
var stage: Node3D
var held_turn_actor: StringName = &""
var mechanics: Node3D
const StatusText = preload("res://scripts/battle_v2/presentation/status_text_v2.gd")
var cast_name_shown := false
var cast_name_label: Label3D

func hide_cast_spell_name() -> void:
	if is_instance_valid(cast_name_label):
		cast_name_label.hide()
		cast_name_label.queue_free()
	cast_name_label = null

func show_cast_spell_name() -> void:
	if cast_name_shown: return
	var card: CardDefinitionV2 = current_context.get("card")
	var id: StringName = stage.action_caster_id
	if card == null or not stage.actors.has(id):return
	cast_name_shown = true
	cast_name_label = Label3D.new()
	cast_name_label.text = Locale.text(str(card.name_key))
	cast_name_label.font_size = 48
	cast_name_label.pixel_size = 0.009
	cast_name_label.modulate = Color("f4d994")
	cast_name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	cast_name_label.no_depth_test = true
	cast_name_label.position = stage.actors[id].position + Vector3(0,3.1,0)
	stage.add_child(cast_name_label)

func show_status_result(event: BattleEventV2) -> void:
	var data: Dictionary = event.payload.get("status", {})
	var id := StringName(str(event.payload.get("target_id", data.get("caster_id", ""))))
	var kind := str(data.get("kind", ""))
	var harmful := kind in ["weakness", "infection", "accuracy_weakness", "trap", "dot", "delay_damage", "stun", "dispel"]
	var name := StatusText.kind_name(kind)
	var school_icons: Array[StringName] = []
	if kind in ["blade", "weakness", "accuracy_blade", "accuracy_weakness", "shield", "trap", "dot", "delay_damage", "dispel"]:
		var filters: Variant = data.get("school_filters", [data.get("school_filter", "*")])
		if not filters is Array: filters = [filters]
		var universal := false
		for filter in filters:
			if str(filter) in ["*", "", "all", "universal"]: universal = true
		if not universal:
			for filter in filters:
				var school := str(filter)
				if school in preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd").SCHOOLS:
					var school_icon := StringName("school_%s" % school)
					if not school_icons.has(school_icon): school_icons.append(school_icon)
		if not school_icons.is_empty(): name += " · " + StatusText.school_text(data)
	var icon_id := StringName(kind)
	if kind == "stat_modifier":
		var modifiers: Dictionary = (data.get("payload", {}) as Dictionary).get("modifiers", {})
		if not modifiers.is_empty():
			var stat := str(modifiers.keys()[0])
			var amount := float(modifiers[stat])
			if stat == "extra_power_pip_chance": icon_id = &"resource"
			elif stat == "incoming_damage": icon_id = &"shield" if amount < 0.0 else &"trap"
			else: icon_id = &"blade" if amount >= 0.0 else &"weakness"
		elif kind == "stat_modifier": icon_id = &"blade"
	var detail := StatusText.value_text(data)
	if kind in ["aura", "global", "stat_modifier"] and detail.contains("  ·  "):
		var parts := detail.rsplit("  ·  ", true, 1)
		if parts.size() == 2:
			name += " · " + parts[1]
			detail = parts[0]
	stage._float_text(id, name + "\n" + detail, Color("f1b39d") if harmful else Color("b5e4d4"),icon_id,school_icons)

func mechanic_director() -> Node3D:
	if not is_instance_valid(mechanics):
		mechanics = preload("res://scripts/fusion_3d/vfx/mechanic_choreography.gd").new()
		stage.add_child(mechanics)
		mechanics.stage = stage
	return mechanics

func _draw() -> void: pass
func _process(_delta: float) -> void: pass

static func turn_result_speed(count: int) -> float:
	return clampf(1.0+0.5*float(count-1),1.0,2.5)

func play_turn_start_events(events: Array[BattleEventV2], view_by_id: Dictionary, frozen_status_views: Array[Control]) -> void:
	stage.cinematic_rate=maxf(test_duration_scale/playback_speed,0.001)
	var turn_rate: float=stage.cinematic_rate
	var result_count:=0
	for event in events:
		if event.type in [&"DamageResolved",&"HealingResolved"]:result_count+=1
	stage.theatre.duration_factor=stage.cinematic_rate
	stage.theatre.audio_speed=playback_speed
	stage.shot_targets.clear()
	stage.theatre.current_summon=false
	held_turn_actor = &""
	# Establish the acting unit's shot before any temporal result is presented.
	for event in events:
		if event.type==&"ActionTurnStarted":
			held_turn_actor=StringName(str(event.payload.get("unit_id","")))
			break
	if held_turn_actor==&"":
		for event in events:
			if event.type in [&"DamageResolved", &"HealingResolved"]:
				held_turn_actor=StringName(str(event.payload.get("target_id",event.payload.get("unit_id",""))))
				break
	if result_count>0 and stage.actors.has(held_turn_actor):
		stage.current_template=""
		stage.focus_unit(held_turn_actor,"caster")
		stage.shot_targets.assign([held_turn_actor])
		await stage.wait_for_shot()
	# Compress stacked ticks together, while a single tick keeps its full animation.
	var tick_speed:=turn_result_speed(result_count)
	stage.cinematic_rate=turn_rate/tick_speed
	stage.theatre.duration_factor=stage.cinematic_rate
	stage.theatre.audio_speed=playback_speed*tick_speed
	stage.result_text_duration_factor=1.4/1.58
	var effects_before: Array[Node]=stage.theatre.layer.get_children()
	await _present_results(events,view_by_id,true)
	await _wait_for_new_result_effects(effects_before)
	stage.cinematic_rate=turn_rate
	stage.theatre.duration_factor=turn_rate
	stage.theatre.audio_speed=playback_speed
	stage.result_text_duration_factor=1.0
	for view in frozen_status_views: view.clear_presentation_statuses()
	stage.sync_world_state()
	mechanic_director().clear()
	# A redirected result may have moved the camera away from the acting unit.
	if result_count>0 and stage.actors.has(held_turn_actor) and not stage.shot_targets.has(held_turn_actor):
		stage.focus_unit(held_turn_actor,"caster")
		stage.shot_targets.assign([held_turn_actor])
		await stage.wait_for_shot()
	if result_count>0:
		await get_tree().create_timer(0.1*turn_rate).timeout
	# Hold this camera through the immediately following cast.

func _wait_for_new_result_effects(previous: Array[Node]) -> void:
	var pending: Array[Node]=[]
	for effect in stage.theatre.layer.get_children():
		if not previous.has(effect):pending.append(effect)
	while not pending.is_empty():
		for index in range(pending.size()-1,-1,-1):
			if not is_instance_valid(pending[index]):pending.remove_at(index)
		if not pending.is_empty():await get_tree().process_frame

func play_action(caster_view: Control, target_views: Array[Control], card: CardDefinitionV2, events: Array[BattleEventV2], hp_before: Dictionary, frozen_status_views: Array[Control] = []) -> float:
	var started := Time.get_ticks_msec()
	active = true
	hide_cast_spell_name()
	cast_name_shown = false
	stage.set_meta("global_cast_released",false)
	marker_history.clear()
	current_context = {"card":card,"events":events,"hp_before":hp_before}
	# Include self-cost recipients even when the selected target is an enemy.
	for event in events:
		if event.type in [&"HealthSpent", &"DamageResolved", &"HealingResolved"]:
			var affected:=StringName(str(event.payload.get("target_id",event.payload.get("unit_id",""))))
			if stage.shell.unit_views.has(affected) and not hp_before.has(affected):
				hp_before[affected]=int(event.payload.get("hp_before",stage.shell.unit_views[affected].unit.hp))
				stage.shell.unit_views[affected].nameplate.hold_presentation_hp(hp_before[affected])
	var targets: Array[BattleUnitStateV2] = []
	for view in target_views: targets.append(view.unit)
	stage.cinematic_rate=maxf(test_duration_scale/playback_speed,0.001)
	stage.shot_targets.clear()
	for target in targets:stage.shot_targets.append(target.id)
	stage.current_template=str(card.presentation.get("template",""))
	stage.action_caster_id=caster_view.unit.id
	stage.pair_shot_enabled=false
	if not card.x_pip and card.pip_cost<=3 and preload("res://scripts/fusion_3d/vfx/arcana_spell_vfx.gd").level_for(card)>0:
		for target in targets:
			if target.team!=caster_view.unit.team:
				stage.pair_shot_enabled=true
				break
	stage.pending_cast_consumptions.clear()
	for event in events:
		if event.type==&"StatusConsumed" and str(event.payload.get("kind","")) in ["blade","weakness","healing_blade","infection"]:stage.pending_cast_consumptions.append(event)
	var camera_token: int=stage.begin_camera_action(caster_view.unit.id,card,events)
	held_turn_actor = &""
	stage.theatre.audio_speed = playback_speed
	stage.theatre.duration_factor = test_duration_scale/playback_speed
	# Costs before the card's first outcome belong at cast release, not after
	# its entire attack/heal/buff presentation. Later recoil keeps event order.
	var release_costs: Array[BattleEventV2]=[]
	for event in events:
		if event.type in [&"DamageResolved",&"HealingResolved",&"StatusApplied",&"ResourceModified"]:break
		if event.type==&"HealthSpent":release_costs.append(event)
	stage.theatre.cost_presentation=func():
		var shot_targets: Array[StringName]=stage.shot_targets.duplicate()
		for event in release_costs:await present_health_cost(event,stage.shell.unit_views)
		stage.shot_targets.assign(shot_targets)
	await stage.theatre.play(caster_view.unit,card,targets,false)
	if camera_cancelled(camera_token):return 0.0
	stage.theatre.cost_presentation=Callable()
	# Result focus adjustment runs alongside impact/number display, not before it.
	marker_history.append(&"IMPACT")
	marker_reached.emit(&"IMPACT",current_context)
	var remaining: Array[BattleEventV2]=[]
	for event in events:
		if not release_costs.has(event):remaining.append(event)
	await _present_results(remaining,stage.shell.unit_views)
	if camera_cancelled(camera_token):return 0.0
	for view in frozen_status_views: view.clear_presentation_statuses()
	stage.sync_world_state()
	mechanic_director().clear()
	stage.theatre.audio.on_marker(&"EXIT")
	stage.set_meta("global_cast_released",true)
	marker_history.append(&"EXIT")
	marker_reached.emit(&"EXIT",current_context)
	var hold_seconds: float=float(stage.camera_config.low_cost_result_hold if stage.pair_shot_enabled else stage.camera_config.result_hold)
	await get_tree().create_timer(hold_seconds*stage.cinematic_rate).timeout
	if stage.last_result_text_tween!=null and stage.last_result_text_tween.is_running():
		await stage.last_result_text_tween.finished
	await wait_for_reactions(events,camera_token)
	await stage.wait_for_shot()
	if camera_cancelled(camera_token):return 0.0
	stage.camera_action_active=false
	stage.pair_shot_enabled=false
	stage.action_caster_id=&""
	active = false
	last_elapsed = float(Time.get_ticks_msec()-started)/1000.0
	presentation_finished.emit(card.id,last_elapsed)
	return last_elapsed

func camera_cancelled(token: int) -> bool:
	if token==stage.camera_action_id:return false
	# Never clear ownership belonging to a newer action.
	if not stage.camera_action_active:
		hide_cast_spell_name()
		active=false
		stage.theatre.cost_presentation=Callable()
	return true

func reaction_running(body: Node) -> bool:
	# Read the existing animation/tween state, rather than inventing a hit delay.
	for child_property in ["external","teen"]:
		if child_property in body and is_instance_valid(body.get(child_property)):
			return reaction_running(body.get(child_property))
	if "recoil" in body and absf(float(body.get("recoil")))>0.001:return true
	if "life_tween" in body:
		var tween: Tween=body.get("life_tween")
		if tween!=null and tween.is_running():return true
	for player_property in ["animation","player"]:
		if not player_property in body:continue
		var player: AnimationPlayer=body.get(player_property)
		if not is_instance_valid(player) or not player.is_playing():continue
		var clip:=player.get_animation(player.current_animation)
		if clip!=null and clip.loop_mode==Animation.LOOP_NONE and player.current_animation_position<clip.length-0.01:return true
	return false

func wait_for_reactions(events: Array[BattleEventV2], token: int) -> void:
	var affected: Array[StringName]=[]
	for event in events:
		if event.type in [&"DamageResolved",&"UnitDied"]:
			var id:=StringName(str(event.payload.get("target_id",event.payload.get("unit_id",""))))
			if not affected.has(id):affected.append(id)
	while token==stage.camera_action_id:
		var pending:=false
		for id in affected:
			if stage.actors.has(id) and reaction_running(stage.actors[id].get_node("Body")):pending=true
		if not pending:return
		await get_tree().process_frame

func present_health_cost(event: BattleEventV2, views: Dictionary) -> void:
	var id:=StringName(str(event.payload.get("target_id",event.payload.get("unit_id",""))))
	var single: Array[BattleEventV2]=[event]
	marker_history.append(&"SELF_COST_BEGIN")
	await mechanic_director().sacrifice(id,func():
		marker_history.append(&"SELF_COST_FORMED")
		stage._process_events(single)
		stage.theatre.audio.result_feedback(event)
		if views.has(id):views[id].nameplate.hold_presentation_hp(int(event.payload.get("hp_after",views[id].unit.hp))))
	marker_history.append(&"SELF_COST_END")

func _present_results(events: Array[BattleEventV2], views: Dictionary, wait_for_each_result: bool=false) -> void:
	var result_token: int=stage.camera_action_id
	stage.theatre.audio.begin_result_batch()
	var seen := false
	for event in events:
		if result_token!=stage.camera_action_id:return
		if await mechanic_director().present(event):
			if event.type == &"StatusApplied": show_status_result(event)
			stage.theatre.status_event(event)
			continue
		if event.type == &"GlobalApplied": show_status_result(event)
		if event.type==&"ResourceModified" and str(event.payload.get("operation","")) in ["add_normal","add_power","add_school","add_shadow"]:
			var recipient:=StringName(str(event.payload.get("unit_id","")))
			var gained:=int(event.payload.get("count",0))
			if gained>0 and stage.actors.has(recipient):
				var recipients: Array[StringName]=[recipient]
				stage.focus_targets(recipients)
				await stage.wait_for_shot()
				await stage.visuals.receive_pip_magic(recipient,gained)
			continue
		if event.type == &"UnitDied":
			stage.theatre.audio.result_feedback(event)
			continue
		if stage.theatre.status_event(event):
			await get_tree().create_timer(0.3*stage.cinematic_rate).timeout
		if event.type==&"StatusConsumed":
			if str(event.payload.get("kind","")) in ["blade","weakness","healing_blade","infection"]:continue
			stage.visuals.consume(StringName(str(event.payload.get("unit_id",""))),int(event.payload.get("status_id",-1)),str(event.payload.get("kind","")))
			await get_tree().create_timer(0.24*stage.cinematic_rate).timeout
			continue
		if event.type not in [&"DamageResolved",&"HealthSpent",&"HealingResolved",&"UnitRevived",&"SpellMissed",&"SpellDispelled",&"ActionFizzled"]: continue
		if seen and not wait_for_each_result: await get_tree().create_timer(float(stage.camera_config.result_interval)*maxf(test_duration_scale,0.01)/playback_speed).timeout
		if result_token!=stage.camera_action_id:return
		var focus_id:=StringName(str(event.payload.get("target_id",event.payload.get("unit_id",event.payload.get("caster_id","")))))
		if not stage.pair_shot_enabled and not stage.shot_targets.has(focus_id) and stage.actors.has(focus_id):
			var focus_ids: Array[StringName]=[focus_id]
			stage.focus_targets(focus_ids)
		await stage.wait_for_shot()
		seen = true
		var effects_before: Array[Node]=stage.theatre.layer.get_children()
		var single: Array[BattleEventV2] = [event]
		if event.type == &"HealthSpent":
			await present_health_cost(event,views)
		else:stage._process_events(single)
		if event.type!=&"HealthSpent":stage.theatre.audio.result_feedback(event)
		if event.type == &"UnitRevived":
			var revived_id := StringName(str(event.payload.get("target_id",event.payload.get("unit_id",""))))
			if stage.actors.has(revived_id):
				stage.actors[revived_id].get_node("Body").set_alive(true)
				stage.theatre.impact(revived_id,"life",true,"revive")
				stage._float_text(revived_id,"复活",Color("81f0b1"),&"revive")
		var id := StringName(str(event.payload.get("target_id",event.payload.get("unit_id",""))))
		if views.has(id):
			views[id].nameplate.hold_presentation_hp(int(event.payload.get("hp_after",event.payload.get("hp",views[id].unit.hp))))
		if wait_for_each_result:
			if stage.last_result_text_tween!=null and stage.last_result_text_tween.is_running():
				await stage.last_result_text_tween.finished
			await _wait_for_new_result_effects(effects_before)
	for view in views.values(): view.nameplate.release_presentation_hp()



