extends "res://scripts/duel_3d/duel_3d.gd"
signal encounter_finished(winner_team: int)
signal entrance_finished
var entering := true
var arrival_active := false
var arrival_token := 0
var shared_session: Node
var trial_context: RefCounted
var shot_tween: Tween
var shot_focus:=Vector3(0,0,1.8)
var shot_targets: Array[StringName]=[]
var shot_key: String=""
var action_caster_id: StringName=&""
var pair_shot_enabled:=false
var cinematic_rate:=1.0
var camera_config: Dictionary
# Local presentation ownership; never replicated.
var camera_action_id := 0
var camera_action_active := false
var camera_direct_request := false
var camera_failed := false
var camera_support := false
var camera_debug: Dictionary = {}
var camera_trace: Array[Dictionary] = []
var summon_frame: Dictionary = {}
var camera_side := Vector3.ZERO
var camera_cast_phase := ""
var camera_result_started := false
var camera_transition := "cut"
var shot_history: Array[String]=[]
var entry_origin := Vector3(0,0.1,10)
var entrance_scale := 1.0
var arena_surface: Node3D
var shell: Control
var center_pointer: Node3D
var visuals: Node3D
var current_template:=""
var pending_cast_consumptions: Array[BattleEventV2]=[]
var embedded := false
# Atlas prepares this stage while the map loads, then explicitly starts its entrance.
var manual_entrance := false
var entry_player: Node3D
var entry_avatar: Node3D
var entry_camera := Transform3D.IDENTITY
var entry_fov := 75.0
var encounter_id := ""
var encounter_spec: Dictionary = {}
var battle_music_context: StringName = &"combat_main"
var battle_music_boss := false
var campaign_level := 0
var party: Array[StringName] = [&"fire_student",&"ice_guardian",&"life_healer",&"storm_duelist"]
static var SLOT_COORDS: Dictionary=build_slot_coords()
static func build_slot_coords() -> Dictionary:
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/battle_board_layout.json"))
	var radius: float=float(layout.outer_radius)-float(layout.slot_radius)
	var result: Dictionary={}
	for id in layout.slot_angles:
		var angle:=deg_to_rad(float(layout.slot_angles[id]))
		result[StringName(id)]=Vector3(sin(angle)*radius,float(layout.foot_height),-cos(angle)*radius)
	return result
func _ready() -> void:
	if encounter_id.is_empty():encounter_id="town_showcase"
	if encounter_id=="town_showcase":campaign_level=0
	camera_config=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/camera_presentation.json"))
	build_stage()
	get_viewport().size_changed.connect(_on_planning_viewport_resized)
	if embedded and not manual_entrance:
		var clearance = preload("res://scripts/fusion_3d/battle_environment_clearance.gd").new()
		add_child(clearance)
		clearance.configure(self)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	shell = load("res://scenes/battle_v2/battle_scene_shell.tscn").instantiate()
	shell.set_script(load("res://scripts/fusion_3d/multiplayer_battle_shell.gd") if shared_session!=null else preload("res://scripts/fusion_3d/battle_shell_bridge.gd"))
	shell.stage = self
	shell.music_context = &"combat_boss" if battle_music_boss else battle_music_context
	# Configure before _ready: hidden warmup must never start the combat playlist.
	shell.music_start_paused = shared_session != null or manual_entrance
	var director: Control = shell.get_node("PresentationLayer")
	director.set_script(preload("res://scripts/fusion_3d/presentation_bridge.gd"))
	director.stage = self
	canvas.add_child(shell)
	shell.battle_finished.connect(func(winner: int): encounter_finished.emit(winner))
	shell.hide()
	if not manual_entrance:_enter_battle.call_deferred()

func build_stage() -> void:
	if not embedded:
		var environment := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("090c18")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("b4bdd6")
		env.ambient_light_energy = 0.5
		env.glow_enabled = true
		env.glow_intensity = 0.45
		environment.environment = env
		add_child(environment)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45,-20,0)
		sun.light_energy = 0.8
		add_child(sun)
	arena_surface=preload("res://scripts/fusion_3d/battle_board.gd").new()
	add_child(arena_surface)
	arena_surface.setup(SLOT_COORDS)
	visuals=preload("res://scripts/fusion_3d/combat_visuals.gd").new()
	add_child(visuals)
	visuals.setup(self)
	center_pointer=visuals.ring
	camera = Camera3D.new()
	camera.position = planning_camera_position()
	camera.fov = planning_camera_fov()
	add_child(camera)
	shot_focus=planning_camera_focus()
	camera.look_at(to_global(shot_focus))
	camera.current = shared_session==null and not manual_entrance
	theatre = preload("res://scripts/duel_3d/spell_theatre.gd").new()
	add_child(theatre)
	theatre.configure(self)
	add_child(preload("res://scripts/fusion_3d/vfx/global_battlefield_v17.gd").new())
	theatre.preparation_duration = 1.8
	theatre.impact_fade_in=0.28
	theatre.marker.connect(func(marker_id: StringName):
		if marker_id==&"CAST_RELEASE" and visuals.caster_id!=&"":
			visuals.sync_pips(engine.state.unit_by_id(visuals.caster_id))
		if is_instance_valid(shell):
			if marker_id==&"CAST_BEGIN": shell.presentation_director.show_cast_spell_name()
			elif marker_id in [&"CAST_RELEASE", &"EXIT"]: shell.presentation_director.hide_cast_spell_name()
			shell.presentation_director.marker_history.append(marker_id)
			shell.presentation_director.marker_reached.emit(marker_id,{}))

	theatre.camera_event.connect(_on_camera_event)

func _build_actor(unit: BattleUnitStateV2) -> void:
	super._build_actor(unit)
	if not encounter_id.is_empty() and unit.team == 1 and not engine.state.pvp:
		var parent: Node3D = actors[unit.id]
		var old := parent.get_node("Body")
		parent.remove_child(old)
		old.queue_free()
		var specs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/chapter_encounters.json"))
		var selected: Dictionary=encounter_spec if not encounter_spec.is_empty() else specs[encounter_id]
		var model_id: String=selected.enemies[unit.slot].get("model","lifetree")
		if trial_context!=null:model_id=str(trial_context.encounter().enemies[unit.slot].model)
		var creature: Node3D
		if model_id=="professor":creature=preload("res://scripts/fusion_3d/world_one_magister.gd").new()
		else:
			creature=preload("res://scripts/fusion_3d/world_one_monster.gd").new()
			creature.model_id=model_id
		creature.name="Body"
		parent.add_child(creature)
	else:
		var body: Node3D=actors[unit.id].get_node("Body")
		body.replacement_model=preload("res://scenes/characters/modular_wizard.tscn")
		body.configure(COLORS.get(str(unit.school_id),GOLD),str(unit.school_id),unit.team==1)
		body.external.set_battle_mode(true)
		body.external.battle_effect_opacity=0.0 if entering else 1.0
		var hit_area: Area3D=actors[unit.id].find_children("*","Area3D",true,false)[0]
		hit_area.scale=Vector3.ONE*preload("res://scripts/fusion_3d/character_motion.gd").SIZE_RATIO
	var old_marker: Node=markers[unit.id]
	old_marker.get_parent().remove_child(old_marker)
	old_marker.queue_free()
	markers[unit.id]=arena_surface.slot_highlights[unit.id]

func bind_engine(value: BattleEngineV2) -> void:
	engine = value
	for unit in engine.state.units:
		_build_actor(unit)
		actors[unit.id].position = SLOT_COORDS[unit.id]
		var body: Node3D=actors[unit.id].get_node("Body")
		if body.has_method("face_center"):body.face_center(to_global(Vector3.ZERO))
		else:body.look_at(to_global(Vector3(0,0.1,0)))
		plates[unit.id].hide()
	sync_world_state()
	shell._layout_units()

func reset_prepared_party(next_party: Array,next_encounter: String) -> void:
	var entry_tick:=Time.get_ticks_usec()
	# Keep the preloaded board, theatre, textures and HUD. Only replace combatants.
	visuals.pip_nodes.clear();visuals.pip_signatures.clear()
	visuals.status_nodes.clear();visuals.signatures.clear()
	visuals.aura_nodes.clear()
	visuals.caster_id=&"";visuals.pointer_initialized=false
	arrival_token+=1;arrival_active=false
	entering=true;current_template="";pending_cast_consumptions.clear();shot_targets.clear()
	action_caster_id=&"";pair_shot_enabled=false
	if shot_tween!=null and shot_tween.is_valid():shot_tween.kill()
	set_planning_camera()
	shell.presentation_director.held_turn_actor=&"";shell.presentation_director.active=false
	for actor in actors.values():
		actor.get_parent().remove_child(actor);actor.queue_free()
	actors.clear();plates.clear();markers.clear()
	for view in shell.unit_views.values():
		view.nameplate.queue_free();view.get_parent().remove_child(view);view.queue_free()
	shell.unit_views.clear();shell.active_actor=null; shell.selected_card=null
	party.assign(next_party);encounter_id=next_encounter
	engine.party.assign(party);engine.encounter_id=encounter_id
	engine.encounter_spec=encounter_spec.duplicate(true)
	var listeners: Array=engine.event_stream.subscribers.duplicate()
	engine.event_stream.subscribers.clear()
	entry_tick=shared_session._entry_timing("reset_cleanup",entry_tick)
	var setup_ok: bool=engine.setup(shell.content,{},20260816)
	if not setup_ok:
		engine.event_stream.subscribers.assign(listeners)
		push_error("Failed to prepare encounter: "+next_encounter)
		return
	shared_session.configure_engine(engine)
	entry_tick=shared_session._entry_timing("reset_rules",entry_tick)
	shell._build_units();engine.start_battle()
	entry_tick=shared_session._entry_timing("reset_hud",entry_tick)
	engine.event_stream.subscribers.assign(listeners)
	shell.planning_round=-1;shell.planning_deadline=0;shell.resolving_network=false
	shell.action_token_cache.clear();shell.resolved_action_ids.clear()
	shell.selected_target_id=&"";shell.valid_target_ids.clear();shell.resolving_actor_id=&""
	bind_engine(engine)
	shared_session._entry_timing("reset_actors",entry_tick)

func _pick_unit(id: StringName) -> void:
	if is_instance_valid(shell): shell._on_unit_clicked(id)

func screen_floor(id: StringName) -> Vector2:
	return camera.unproject_position(actors[id].global_position)

func highlight(id: StringName, value: bool, targeting: bool=false, selected: bool=false) -> void:
	if entering: return
	if markers.has(id):
		markers[id].visible = value if targeting else ((visuals.caster_id==id) if visuals.caster_id!=&"" else value)
		markers[id].scale = Vector3.ONE*((1.12 if selected else 1.05)+0.04*sin(elapsed*5))
		var ring: TorusMesh=markers[id].mesh
		var inner: float=1.10 if selected else (1.13 if targeting else 1.17)
		var outer: float=1.26 if selected else (1.24 if targeting else 1.20)
		if not is_equal_approx(ring.inner_radius,inner):ring.inner_radius=inner
		if not is_equal_approx(ring.outer_radius,outer):ring.outer_radius=outer
		var material: StandardMaterial3D=markers[id].material_override
		material.albedo_color=Color("fff1a8") if selected else (Color("6fffd1") if targeting else Color("ffdf8e"))
		material.emission=material.albedo_color
		material.emission_energy_multiplier=1.5 if selected else (1.0 if targeting else 0.7)

func sync_world_state() -> void:
	if engine == null: return
	for unit in engine.state.units:
		actors[unit.id].get_node("Body").set_alive(unit.alive)
		_sync_status_art(unit)

func sync_roster() -> void:
	for unit in engine.state.units:
		if not actors.has(unit.id):
			_build_actor(unit);actors[unit.id].position=SLOT_COORDS[unit.id];plates[unit.id].hide()
			var body: Node3D=actors[unit.id].get_node("Body")
			if body.has_method("face_center"):body.face_center(to_global(Vector3.ZERO))
			else:body.look_at(to_global(Vector3(0,0.1,0)))
	shell.sync_roster_views()
	sync_world_state()

func _log(_message: String) -> void: pass
func _unhandled_key_input(_event: InputEvent) -> void: pass

func _process(delta: float) -> void:
	elapsed += delta
	if camera == null or arrival_active or (manual_entrance and entering): return
	camera.look_at(to_global(shot_focus))
	if visuals.caster_id!=&"" and markers.has(visuals.caster_id) and shell.ui_state!=shell.UIState.TARGETING:markers[visuals.caster_id].show()

func _sync_status_art(unit: BattleUnitStateV2) -> void:
	visuals.sync_status(unit)
	visuals.sync_pips(unit)

func _enter_battle() -> void:
	if manual_entrance:
		await _enter_from_world()
		return
	var origins: Dictionary={}
	for unit in engine.state.units:
		var destination: Vector3=SLOT_COORDS[unit.id]
		var start:=Vector3(destination.x*1.12,0.1,10.5 if unit.team==0 else -10.5)
		if unit.id==&"P0":start=entry_origin
		origins[str(unit.id)]=to_global(start)
	await preload("res://scripts/fusion_3d/battle_arrival.gd").play(self,origins,false)
	center_pointer.show();entering=false
	shell.modulate.a=1.0;shell.visible=shared_session==null or shared_session.active_local
	shell._refresh_all();entrance_finished.emit()

func present_cast_consumptions() -> void:
	# The core already orders these newest first. Keep each trigger visible before
	# releasing the spell instead of starting all charm animations in one frame.
	for event in pending_cast_consumptions:
		visuals.consume(StringName(str(event.payload.get("unit_id",""))),int(event.payload.get("status_id",-1)),str(event.payload.get("kind","")))
		await get_tree().create_timer(0.24*cinematic_rate).timeout
	pending_cast_consumptions.clear()

func move_shot(at: Vector3, focus: Vector3, fov_value: float, duration: float) -> void:
	if camera_action_active and not camera_direct_request:return
	camera_transition="move" if duration>0.0 else "cut"
	# The stage is the sole combat-camera writer. Spells and mechanics request
	# shots here; a new request always cancels the previous position/FOV tween.
	if shot_tween!=null and shot_tween.is_valid():shot_tween.kill()
	shot_tween=null
	shot_key=""
	if duration<=0.0:
		camera.position=at
		shot_focus=focus
		camera.fov=fov_value
		camera.look_at(to_global(shot_focus))
		return
	shot_tween=create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	shot_tween.tween_property(camera,"position",at,maxf(duration*cinematic_rate,0.001))
	shot_tween.tween_property(self,"shot_focus",focus,maxf(duration*cinematic_rate,0.001))
	shot_tween.tween_property(camera,"fov",fov_value,maxf(duration*cinematic_rate,0.001))
func focus_unit(id: StringName, role: String) -> void:
	if camera_action_active and not camera_direct_request:return
	if not actors.has(id):return
	var key:=role+":"+str(id)
	if shot_key==key:return
	shot_history.append(role+":"+str(id))
	if role in ["caster","caster_rear"]:
		if visuals.caster_id!=id and markers.has(visuals.caster_id):markers[visuals.caster_id].hide()
		visuals.caster_id=id
		if shell.unit_views.has(id):shell.unit_views[id].nameplate.modulate=Color(1.2,1.12,0.95)
	var at: Vector3=actors[id].position
	if role in ["caster","caster_rear"]:
		var cfg: Dictionary=camera_config.shots.cast_rear if role=="caster_rear" else camera_config.shots.cast
		var forward:=cast_forward(id)
		var right:=forward.cross(Vector3.UP).normalized()
		# A stable full-body composition, shifted toward the symbol's presentation
		# space. Do not track the moving hand or the particles.
		var focus:=at+Vector3.UP*float(cfg.focus_height)*actor_size_ratio(id)+forward*float(cfg.focus_forward)+right*float(cfg.focus_side)
		move_shot(at+forward*float(cfg.front)+right*float(cfg.side)+Vector3.UP*float(cfg.height),focus,float(cfg.fov),0.0)
	else:
		var cfg: Dictionary=camera_config.shots.target
		var inward:=horizontal(-at)
		move_shot(at+inward*float(cfg.distance)+Vector3.UP*float(cfg.height),at+Vector3.UP*float(cfg.focus_height)*actor_size_ratio(id),float(cfg.fov),0.0)
	shot_key=key

func horizontal(value: Vector3) -> Vector3:
	value.y=0.0
	return value.normalized() if value.length_squared()>0.0001 else Vector3.FORWARD

func cast_forward(id: StringName) -> Vector3:
	# Keep the original front view, including ally/self casts. The spell's
	# recipient must not swing this camera behind an unchanged casting pose.
	var body: Node3D=actors[id].get_node("Body")
	var forward: Vector3=body.front_global() if body.has_method("front_global") else -body.global_basis.z
	return horizontal(global_basis.inverse()*forward)

func focus_summon_lane(_ids: Array[StringName]) -> void:
	if camera_action_active and not camera_direct_request:return
	if summon_frame.is_empty():return
	var cfg: Dictionary=camera_config.shots.summon
	var size: Vector3=summon_frame.size
	var front: Vector3=summon_frame.axis
	var extent:=maxf(size.x,maxf(size.y,size.z))
	var focus: Vector3=summon_frame.anchor
	var distance:=maxf(float(cfg.min_distance),extent*float(cfg.distance_scale))
	var direction: Vector3=(front*float(cfg.front_weight)+camera_side).normalized()
	move_shot(focus+direction*distance+Vector3.UP*float(cfg.height),focus,float(cfg.fov),0.0)
	shot_key="summon:"+str(camera_action_id)
	shot_history.append("summon")

func prepare_summon_frame(context: Dictionary) -> void:
	summon_frame=context.duplicate()
	var target:=Vector3.ZERO
	var count:=0
	for id in shot_targets:
		if actors.has(id):
			target+=actors[id].position+Vector3.UP*1.6*actor_size_ratio(id)
			count+=1
	if count==0:target=summon_frame.anchor+horizontal(summon_frame.front)
	else:target/=float(count)
	summon_frame.target=target
	var axis:=horizontal(target-Vector3(summon_frame.anchor))
	summon_frame.axis=axis
	camera_side=axis.cross(Vector3.UP)
	var home:=planning_camera_position()-Vector3(summon_frame.anchor)
	if camera_side.dot(home)<-0.01 or (absf(camera_side.dot(home))<=0.01 and camera_side.x<0):camera_side=-camera_side

func move_summon_sequence(beat: String, duration: float) -> void:
	# Snapshot both subjects once. Same side, bounded travel, no chasing a
	# projectile and no FOV changes anywhere in the continuous summon shot.
	var cfg: Dictionary=camera_config.shots.summon_motion
	var source: Vector3=summon_frame.anchor
	var target: Vector3=summon_frame.target
	var axis: Vector3=summon_frame.axis
	var focus:=source.lerp(target,float(cfg.reveal_bias if beat=="reveal" else cfg.attack_bias))
	var size: Vector3=summon_frame.size
	var extent:=maxf(size.x,maxf(size.y,size.z))
	var spread:=source.distance_to(target)
	for id in shot_targets:
		if actors.has(id):spread=maxf(spread,source.distance_to(actors[id].position))
	var distance:=maxf(float(cfg.min_distance),spread*float(cfg.axis_scale)+extent*float(cfg.body_scale))
	var direction: Vector3=(axis*float(cfg.reveal_front_weight if beat=="reveal" else cfg.attack_front_weight)+camera_side).normalized()
	var at:=focus+direction*distance+Vector3.UP*float(cfg.height)
	# Relative endpoints must not turn a large body/arena into a fast fly-through.
	at=camera.position+(at-camera.position).limit_length(float(cfg.max_travel))
	move_shot(at,focus,camera.fov,duration)
	shot_key=("summon_reveal:" if beat=="reveal" else "pair:")+str(camera_action_id)

func settle_summon_result() -> void:
	if camera_result_started:return
	camera_result_started=true
	var cfg: Dictionary=camera_config.shots.summon_motion
	var desired: Vector3=Vector3(summon_frame.anchor).lerp(summon_frame.target,float(cfg.result_bias))
	var focus:=shot_focus+(desired-shot_focus).limit_length(float(cfg.result_max_shift))
	move_shot(camera.position,focus,camera.fov,float(cfg.result_seconds))
	shot_key="pair:result:"+str(camera_action_id)

func focus_combat_pair(caster_id: StringName, ids: Array[StringName]) -> void:
	if camera_action_active and not camera_direct_request:return
	if not actors.has(caster_id) or ids.is_empty():return
	var key:="pair:"+str(caster_id)+":"+str(ids)
	if shot_key==key:return
	var source: Vector3=actors[caster_id].position+Vector3.UP*1.6*actor_size_ratio(caster_id)
	var extent:=2.0
	if not summon_frame.is_empty():
		source=summon_frame.anchor
		var size: Vector3=summon_frame.size
		extent=maxf(size.x,maxf(size.y,size.z))
	var points: Array[Vector3]=[source]
	var target_center:=Vector3.ZERO
	for id in ids:
		if not actors.has(id):continue
		var point: Vector3=actors[id].position+Vector3.UP*1.6*actor_size_ratio(id)
		target_center+=point
		points.append(point)
	if points.size()==1:return
	target_center/=float(points.size()-1)
	var forward:=horizontal(target_center-source)
	var side:=forward.cross(Vector3.UP)
	var cfg: Dictionary=camera_config.shots.attack
	var focus:=source.lerp(target_center,float(cfg.target_bias))
	if camera_side.length_squared()>0.01:
		if side.dot(camera_side)<0:side=-side
	else:
		var home:=planning_camera_position()-focus
		if side.dot(home)<-0.01 or (absf(side.dot(home))<=0.01 and side.x<0):side=-side
		camera_side=side
	var spread:=0.0
	for point in points:spread=maxf(spread,point.distance_to(focus))
	var distance:=maxf(float(cfg.min_distance),(spread+extent*0.5+float(cfg.result_margin))*float(cfg.distance_scale))
	move_shot(focus+side*distance+Vector3.UP*float(cfg.height),focus,float(cfg.fov),0.0)
	shot_key=key
	shot_history.append(key)

func begin_camera_action(caster_id: StringName, card: CardDefinitionV2, events: Array[BattleEventV2]) -> int:
	cancel_camera_action()
	camera_action_active=true
	action_caster_id=caster_id
	camera_failed=false
	camera_support=card.target_type in [&"ally",&"self",&"all_allies",&"dead_ally"] or current_template in ["self_buff","target_buff","ground_spell","delayed_spell"]
	for event in events:
		if event.type in [&"ActionFizzled",&"SpellDispelled",&"SpellMissed",&"ActionStunned"]:camera_failed=true
	return camera_action_id

func cancel_camera_action() -> void:
	camera_action_id+=1
	camera_action_active=false
	camera_direct_request=false
	summon_frame.clear()
	camera_side=Vector3.ZERO
	camera_cast_phase=""
	camera_result_started=false
	shot_key=""
	if shot_tween!=null and shot_tween.is_valid():shot_tween.kill()
	shot_tween=null

func _on_camera_event(event: StringName, context: Dictionary, token: int) -> void:
	if not camera_action_active or token!=camera_action_id or not is_inside_tree():return
	camera_direct_request=true
	var kind:=""
	var subject:=str(action_caster_id)
	match event:
		&"CAST_BEGIN":
			if camera_cast_phase.is_empty():
				camera_cast_phase="rear"
				focus_unit(action_caster_id,"caster_rear")
				kind="CAST"
		&"CAST_FRAME":
			if camera_cast_phase=="rear":
				camera_cast_phase="front"
				focus_unit(action_caster_id,"caster")
				kind="CAST"
		&"SUMMON_APPEAR":
			if not camera_failed:
				prepare_summon_frame(context)
				focus_summon_lane(shot_targets)
				kind="SUMMON";subject="summon"
		&"SUMMON_REVEAL":
			if not summon_frame.is_empty() and not camera_failed:
				move_summon_sequence("reveal",float(context.seconds))
				kind="SUMMON";subject="summon"
		&"SUMMON_ATTACK", &"ATTACK_RELEASE":
			if not camera_failed and not (shot_key.begins_with("pair:") or shot_key.begins_with("target")):
				if not summon_frame.is_empty():
					move_summon_sequence("attack",float(context.get("seconds",0.77)))
					kind="ATTACK";subject="summon"
				elif not camera_support:
					focus_combat_pair(action_caster_id,shot_targets)
					kind="ATTACK";subject="summon" if not summon_frame.is_empty() else str(action_caster_id)
				elif shot_targets.size()>1 or (not shot_targets.is_empty() and shot_targets[0]!=action_caster_id):
					focus_targets(shot_targets)
					kind="TARGET";subject=str(shot_targets)
		&"IMPACT":
			if not summon_frame.is_empty() and not camera_failed and not camera_result_started:
				settle_summon_result()
				kind="ATTACK";subject=str(shot_targets)
	camera_direct_request=false
	if not kind.is_empty():record_camera(kind,subject,str(event))

func record_camera(kind: String, subject: String, reason: String) -> void:
	camera_debug={"shot":kind,"action":camera_action_id,"subject":subject,"targets":shot_targets.duplicate(),"reason":reason,"transition":camera_transition}
	if bool(camera_config.get("debug",false)) or OS.get_cmdline_user_args().has("--battle-camera-debug"):
		camera_trace.append(camera_debug.duplicate(true))
		if camera_trace.size()>128:camera_trace.pop_front()
		print("BATTLE_CAMERA ",JSON.stringify(camera_debug))

func _exit_tree() -> void:
	cancel_camera_action()

func focus_targets(ids: Array[StringName]) -> void:
	if camera_action_active and not camera_direct_request:return
	if ids.is_empty():return
	shot_targets=ids.duplicate()
	if ids.size()==1:
		focus_unit(ids[0],"target")
	else:
		var key:="target_group:"+str(ids)
		if shot_key==key:return
		var center:=Vector3.ZERO
		for id in ids:center+=actors[id].position
		center/=ids.size()
		shot_history.append("target_group")
		# Face either team's recipients from the arena centre, including group heals.
		var inward:=Vector3(-center.x,0,-center.z).normalized()
		if inward.length_squared()<0.01:inward=Vector3(0,0,planning_view_sign())
		var spread:=0.0
		for id in ids:spread=maxf(spread,center.distance_to(actors[id].position))
		var cfg: Dictionary=camera_config.shots.target_group
		var distance:=maxf(float(cfg.min_distance),spread*float(cfg.distance_scale))
		move_shot(center+inward*distance+Vector3.UP*float(cfg.height),center+Vector3.UP*float(cfg.focus_height),float(cfg.fov),0.0)
		shot_key=key
func wait_for_shot() -> void:
	# A killed Tween never emits finished. Stop waiting when ownership changes.
	var pending: Tween=shot_tween
	var token:=camera_action_id
	while token==camera_action_id and pending!=null and pending==shot_tween and pending.is_valid() and pending.is_running():
		await get_tree().process_frame
func restore_planning_camera() -> void:
	cancel_camera_action()
	visuals.caster_id=&""
	for view in shell.unit_views.values():view.nameplate.modulate=Color.WHITE
	shot_targets.clear()
	shot_history.append("planning")
	move_shot(planning_camera_position(),planning_camera_focus(),planning_camera_fov(),0.0)
	record_camera("ARENA","arena","planning")
	await wait_for_shot()
var last_result_text_tween: Tween
var result_text_duration_factor:=1.0

func _float_text(id: StringName, value: String, color: Color, icon_id: StringName = &"", school_icons: Array[StringName] = []) -> void:
	if not actors.has(id):return
	value = preload("res://scripts/fusion_3d/floating_popup_anchor.gd").display_text(value)
	var popup:=preload("res://scripts/fusion_3d/floating_popup_anchor.gd").new()
	popup.camera=camera
	popup.position=actors[id].position+Vector3(0,3.1,0)
	var label:=Label3D.new()
	label.text=value
	label.font_size=36 if "\n" in value else (48 if value.length()>6 else 64)
	label.pixel_size=0.009
	label.modulate=Color(color,0)
	label.billboard=BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test=true
	var occupied := 0
	for child in get_children():
		if child.has_meta("result_unit") and child.get_meta("result_unit") == id: occupied += 1
	var safe_top := 150.0
	if camera != null: safe_top = maxf(80.0,float(camera.get_viewport().get_visible_rect().size.y) * 0.17)
	var stacked_y := popup.position.y + occupied * 0.85
	if camera != null and camera.unproject_position(to_global(Vector3(popup.position.x,stacked_y,popup.position.z))).y < safe_top:
		stacked_y = popup.position.y - occupied * 0.85
	popup.position.y = stacked_y
	if camera != null:
		for attempt in 12:
			if camera.unproject_position(to_global(popup.position)).y >= safe_top: break
			popup.position.y -= 0.25
	popup.set_meta("result_unit", id)
	add_child(popup)
	popup.add_child(label)
	var icons: Array[Sprite3D] = []
	var icon_ids: Array[StringName] = school_icons.duplicate()
	if icon_id != &"": icon_ids.append(icon_id)
	var cell_size := 0.44 if "\n" in value else 0.60
	var cell_gap := 0.035
	for asset_id in icon_ids:
		var texture: Texture2D = preload("res://scripts/fusion_3d/floating_popup_art.gd").texture(asset_id)
		if texture == null: continue
		var icon := Sprite3D.new()
		icon.texture = texture
		icon.pixel_size = cell_size / maxf(float(texture.get_width()),float(texture.get_height()))
		icon.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		icon.no_depth_test = true
		icon.modulate = Color(1,1,1,0)
		if "\n" in value:
			icon.position.y = float(label.font_size) * label.pixel_size * (0.5 if asset_id == &"aura" else -0.5)
		icons.append(icon)
	var icons_width := float(icons.size()) * (cell_size + cell_gap)
	var text_width := 0.0
	for line in value.split("\n"):
		text_width = maxf(text_width,ThemeDB.fallback_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,label.font_size).x * label.pixel_size)
	if not icons.is_empty():
		var cursor := -(icons_width + text_width) * 0.5
		for icon in icons:
			icon.position.x = cursor + cell_size * 0.5
			popup.add_child(icon)
			cursor += cell_size + cell_gap
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.position.x = cursor
	popup.configure_layout(Vector2(icons_width + text_width,float(label.font_size) * label.pixel_size * value.split("\n").size()))
	var rate:=maxf(cinematic_rate,0.01)
	var fade:=create_tween()
	last_result_text_tween=fade
	fade.tween_property(label,"modulate:a",1.0,0.28*rate*result_text_duration_factor)
	for icon in icons: fade.parallel().tween_property(icon,"modulate:a",1.0,0.28*rate*result_text_duration_factor)
	fade.tween_interval(0.65*rate*result_text_duration_factor)
	fade.tween_property(label,"modulate:a",0.0,0.65*rate*result_text_duration_factor)
	for icon in icons: fade.parallel().tween_property(icon,"modulate:a",0.0,0.65*rate*result_text_duration_factor)
	fade.tween_callback(popup.queue_free)
	create_tween().tween_property(popup,"position:y",popup.position.y+0.65,1.58*rate*result_text_duration_factor)

func actor_size_ratio(id: StringName) -> float:
	var body: Node3D=actors[id].get_node("Body")
	return preload("res://scripts/fusion_3d/character_motion.gd").SIZE_RATIO if "external" in body and body.external!=null else 1.0

func _enter_from_world() -> void:
	var origins: Dictionary={}
	for unit in engine.state.units:
		origins[str(unit.id)]=to_global(SLOT_COORDS[unit.id]+Vector3(0,0,3.0 if unit.team==0 else -3.0))
	await preload("res://scripts/fusion_3d/battle_arrival.gd").play(self,origins,true,false,entry_player,entry_avatar)
	await RenderingServer.frame_post_draw
	center_pointer.show();entering=false
	shell._refresh_all();shell.modulate.a=1.0;shell.show()
	entrance_finished.emit()

func planning_view_sign() -> float:
	if shared_session!=null and shared_session.has_method("local_team") and bool(shared_session.descriptor.get("pvp",false)):
		return -1.0 if shared_session.local_team()==1 else 1.0
	return 1.0

func planning_camera_fov() -> float:
	var viewport_size:=get_viewport().get_visible_rect().size
	var aspect:=viewport_size.x/maxf(1.0,viewport_size.y)
	var base:=float(camera_config.shots.arena.fov)
	# Keep the reference's horizontal framing in narrower windows.
	return rad_to_deg(2.0*atan(tan(deg_to_rad(base)*0.5)*maxf(1.0,(16.0/9.0)/aspect)))

func _on_planning_viewport_resized() -> void:
	if arrival_active or camera_action_active or not is_instance_valid(shell):return
	if shell.ui_state==shell.UIState.RESOLVING:return
	set_planning_camera()

func planning_camera_position() -> Vector3:return Vector3(0,float(camera_config.shots.arena.height),float(camera_config.shots.arena.distance)*planning_view_sign())
func planning_camera_focus() -> Vector3:return Vector3(0,0,float(camera_config.shots.arena.focus_forward)*planning_view_sign())
func set_planning_camera() -> void:
	cancel_camera_action()
	if shot_tween!=null and shot_tween.is_valid():shot_tween.kill()
	shot_tween=null
	shot_key=""
	shot_focus=planning_camera_focus();camera.position=planning_camera_position();camera.fov=planning_camera_fov()
	camera.look_at(to_global(shot_focus))
