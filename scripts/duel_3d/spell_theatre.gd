extends Node3D
## Scene-only spell choreography. Combat is resolved by the existing engine afterwards.
var host: Node3D
var audio: Node
var audio_speed := 1.0
var layer: Node3D
var phase := "idle"
var current_spell := ""
var current_summon := false
var cost_presentation: Callable
var library_projectile_level := 0
var library_projectile_school := ""
signal marker(id: StringName)
signal camera_event(id: StringName, context: Dictionary, action_id: int)
# Shared actual spawn position: both presentation and camera consume this value.
var summon_position := Vector3.ZERO
var duration_factor := 1.0
var preparation_duration := 0.62
var impact_fade_in:=0.13
# The level-three casting floor circle reaches just past the standing circle.
const CAST_STAGE_SCALE := 1.1
# Keep the floating glyph ahead of the standing ring and casting gesture.
const CAST_SYMBOL_FORWARD_DISTANCE := 1.8

func configure(owner_node: Node3D) -> void:
	host = owner_node
	audio = preload("res://scripts/fusion_3d/school_audio.gd").new()
	add_child(audio)
	marker.connect(audio.on_marker)
	layer = Node3D.new()
	layer.name = "SpellEffects"
	host.add_child(layer)

func clear() -> void:
	if host.has_method("cancel_camera_action"):host.cancel_camera_action()
	audio.stop_all()
	for child in layer.get_children(): child.queue_free()
	phase = "idle"

func effect(school: String,kind: String,at: Vector3,size_value: float,approved_casting: bool=false) -> Node3D:
	var fx=preload("res://scripts/fusion_3d/vfx/soft_impact.gd").new() if kind=="impact" else preload("res://scripts/fusion_3d/school_vfx.gd").new()
	fx.use_approved_casting=approved_casting
	fx.school=school
	fx.kind=kind
	fx.diameter=size_value
	fx.position=at
	layer.add_child(fx)
	return fx

func ground(id: StringName,position_value: Vector3,size_value: float) -> Node3D:
	var parts:=str(id).split("_")
	return effect(parts[1],parts[2],position_value,size_value)

func sprite(id: StringName, at: Vector3, world_size: float) -> Sprite3D:
	var node := Sprite3D.new()
	node.texture = ArtRegistryV2.texture(id)
	if node.texture != null:
		node.pixel_size = world_size / float(node.texture.get_width())
	node.position = at
	node.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	node.no_depth_test = false
	node.shaded = false
	layer.add_child(node)
	return node

func burst(at: Vector3, color: Color, count: int = 20, upward: bool = false) -> void:
	if current_spell != "death_empower":
		for i in mini(count, 9):
			var angle := float(i) * TAU / 9.0
			var direction := Vector3(sin(angle),1.3 if upward else 0.4 + float(i%3)*0.3,cos(angle)).normalized()
			var spark := preload("res://scripts/fusion_3d/vfx/casting_wisps.gd").make_spark(layer,color)
			if upward:
				spark.material_override.emission_enabled=true
				spark.material_override.emission=color.lightened(0.2)
				spark.material_override.emission_energy_multiplier=1.6
			spark.position = at
			spark.scale = Vector3.ONE * (0.24 if upward else 0.32)
			spark.quaternion = Quaternion(Vector3.UP,direction)
			var tween := create_tween().set_parallel(true)
			var life := 0.48 * maxf(duration_factor,0.001)
			tween.tween_property(spark,"position",at + direction * 1.2,life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(spark,"scale",Vector3.ZERO,life)
			tween.chain().tween_callback(spark.queue_free)
		return
	for i in count:
		var angle := float(i)*TAU/float(count)
		var ball: MeshInstance3D = host._orb(layer,at,0.055+float(i%3)*0.018,color)
		var direction := Vector3(sin(angle),0.35+float(i%5)*0.3,cos(angle))
		if upward: direction = Vector3(sin(angle)*0.5,2.0+float(i%3)*0.4,cos(angle)*0.5)
		var tween := create_tween().set_parallel(true)
		tween.tween_property(ball,"position",at+direction*(0.6+float(i%4)*0.25),0.7)
		tween.tween_property(ball,"scale",Vector3.ONE*0.01,0.7)
		tween.chain().tween_callback(ball.queue_free)

func impact(target_id: StringName, school: String, healing: bool, origin: String = "spell") -> void:
	audio.hit_feedback(healing, school, origin)
	if library_projectile_level>0 and school==library_projectile_school and not healing and origin=="spell":
		host.actors[target_id].get_node("Body").hit()
		return
	var at: Vector3 = host.actors[target_id].position
	var flash := effect(school,"heal" if healing else "impact",host.to_local(host.actors[target_id].get_node("Body").anchor_global("HitPoint")),2.5)
	flash.scale = Vector3.ONE*0.2
	flash.opacity=0.0
	var tween := create_tween()
	var flash_in: float=(impact_fade_in if healing else 0.06)*duration_factor
	tween.tween_property(flash,"scale",Vector3.ONE,flash_in)
	tween.parallel().tween_property(flash,"opacity",1.0,flash_in)
	tween.tween_property(flash,"opacity",0.0,(0.75 if healing else 0.24)*duration_factor)
	tween.tween_callback(flash.queue_free)
	if origin!="health_cost":burst(at+Vector3.UP,host.COLORS.get(school,host.GOLD),18,healing)
	if not healing: host.actors[target_id].get_node("Body").hit()

func play(caster: BattleUnitStateV2, card: CardDefinitionV2, targets: Array[BattleUnitStateV2], fast: bool) -> void:
	if "shell" in host and is_instance_valid(host.shell): audio.bind_music(host.shell.battle_music)
	var rate := (0.2 if fast else 1.0)*duration_factor
	rate = maxf(rate, 0.001)
	var school := str(card.school_id)
	var universal_aura := "universal_aura" in card.tags
	var cast_school := "all" if universal_aura else school
	audio.begin_action(cast_school, 1.0 / rate)
	var cast_lead: float = audio.release_seconds(cast_school, preparation_duration)
	var gather_rate := rate * cast_lead / 1.8
	var color: Color = Color("cfccff") if universal_aura else host.COLORS.get(school,host.GOLD)
	var origin: Vector3 = host.actors[caster.id].position
	current_spell = str(card.id)
	current_summon = preload("res://scripts/fusion_3d/summoned_actor.gd").uses_summon(card)
	var arcana_library=preload("res://scripts/fusion_3d/vfx/arcana_spell_vfx.gd")
	library_projectile_level=arcana_library.level_for(card)
	var cast_visual_level: int=3 if not universal_aura and arcana_library.cast_level_for(card)>0 else 0
	library_projectile_school=school
	if library_projectile_level>0 and card.pip_cost<=3:current_summon=false
	elif current_summon and card.pip_cost in [4,5,6,7]:
		library_projectile_level=clampi(card.pip_cost-3,1,3)
	host.cinematic_target = origin+Vector3.UP
	if not targets.is_empty(): host.cinematic_target = (origin+host.actors[targets[0].id].position)*0.5+Vector3.UP
	create_tween().tween_property(host,"cinematic_weight",1.0,0.3*rate)
	var camera_token: int=host.camera_action_id if "camera_action_id" in host else -1
	phase = "charge"
	camera_event.emit(&"CAST_BEGIN",{},camera_token)
	marker.emit(&"CAST_BEGIN")
	var cast_started := Time.get_ticks_usec()
	var release_at := cast_started + int(cast_lead * rate * 1000000.0)
	var cast_framed:=false
	var front_cut_fraction: float=clampf(float(host.camera_config.shots.cast.front_cut_fraction),0.0,1.0) if "camera_config" in host else 0.0
	# Preserve the existing 1.8 / 2.7 gesture calibration for each school.
	host.actors[caster.id].get_node("Body").play_cast(cast_lead * 1.5 * rate)
	# Every seven-school spell uses its Arcana casting stage, including support.
	var rune: Node3D
	if cast_visual_level>0:
		rune=Node3D.new()
		layer.add_child(rune)
		var arcana_cast=preload("res://scripts/fusion_3d/vfx/arcana_stage.gd").new()
		layer.add_child(arcana_cast)
		arcana_cast.position=origin
		arcana_cast.scale=Vector3.ONE*CAST_STAGE_SCALE
		arcana_cast.setup(school,cast_visual_level,"cast",cast_lead*rate)
	else:
		rune=effect(cast_school,"rune",origin+Vector3.UP*0.15,3.2)
		rune.name="CastingFootRing"
	var symbol_at:=cast_symbol_position(caster.id)
	var aura := sprite(StringName("cast_symbol_"+cast_school+"_hd"),symbol_at,2.5)
	aura.pixel_size=2.5/float(aura.texture.get_width())
	aura.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	aura.name="CastingSchoolSymbol"
	aura.modulate.a=0
	aura.scale=Vector3.ONE*0.25
	var glyph:=create_tween().set_parallel(true)
	glyph.tween_property(aura,"modulate:a",1.0,0.5*gather_rate)
	glyph.tween_property(aura,"scale",Vector3.ONE,0.9*gather_rate).set_trans(Tween.TRANS_SINE)
	if current_spell == "death_empower":
		for i in 10:
			var angle:=i*TAU/10.0
			var spark: MeshInstance3D=host._orb(layer,origin+Vector3(sin(angle)*1.4,0.3,cos(angle)*1.4),0.065,color)
			var gather:=create_tween()
			gather.tween_interval(i*0.045*gather_rate)
			gather.tween_property(spark,"position",symbol_at,1.0*gather_rate)
			gather.tween_callback(spark.queue_free)
	else:
		var wisps := preload("res://scripts/fusion_3d/vfx/casting_wisps.gd").new()
		wisps.origin = origin + Vector3.UP * 0.3
		wisps.destination = symbol_at
		wisps.color = color
		wisps.seven_schools = universal_aura
		wisps.seconds = cast_lead * rate
		layer.add_child(wisps)
	if cast_visual_level==0:
		rune.scale = Vector3.ONE*0.15
		create_tween().tween_property(rune,"scale",Vector3.ONE,0.45*gather_rate)
	if current_spell == "death_empower": burst(origin+Vector3.UP*1.8,color,12,true)
	# A newly created SceneTreeTimer can consume the loading frame's entire delta.
	# Use the cast's start clock so first-use loading cannot release it early.
	while Time.get_ticks_usec() < release_at:
		if not cast_framed and Time.get_ticks_usec()-cast_started>=int(cast_lead*rate*front_cut_fraction*1000000.0):
			cast_framed=true
			camera_event.emit(&"CAST_FRAME",{},camera_token)
		await get_tree().process_frame
		if "camera_action_id" in host and camera_token!=host.camera_action_id:return
	if not cast_framed:camera_event.emit(&"CAST_FRAME",{},camera_token)
	phase = "release"
	if cost_presentation.is_valid():await cost_presentation.call()
	if "camera_action_id" in host and camera_token!=host.camera_action_id:return
	if host.has_method("present_cast_consumptions"):await host.present_cast_consumptions()
	if "camera_action_id" in host and camera_token!=host.camera_action_id:return
	marker.emit(&"CAST_RELEASE")
	# The cast glyph belongs to preparation, never to projectile flight/results.
	aura.hide()
	rune.hide()
	if universal_aura:
		var sparks = preload("res://scripts/fusion_3d/vfx/casting_wisps.gd")
		for i in 42:
			var spark: MeshInstance3D = sparks.make_spark(layer, sparks.SCHOOL_COLORS[i % 7])
			spark.position = symbol_at
			spark.scale = Vector3(0.10,0.32+(i%3)*0.06,0.10)
			var direction := Vector3(cos(i*TAU/21),((i%3)-1)*0.45,sin(i*TAU/21)).normalized()
			spark.quaternion = Quaternion(Vector3.UP,direction)
			var release := create_tween().set_parallel(true)
			release.tween_property(spark,"position",symbol_at+direction*(1.5+(i%4)*0.22),0.48*rate).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			release.tween_property(spark,"scale",Vector3.ZERO,0.48*rate)
			release.chain().tween_callback(spark.queue_free)
	if "camera_failed" in host and host.camera_failed:
		rune.queue_free();aura.queue_free()
		phase="idle"
		return
	var template := str(card.presentation.get("template",""))
	var support := card.target_type in [&"ally",&"self",&"all_allies",&"dead_ally"] or template in ["self_buff","target_buff","ground_spell","delayed_spell"]
	if library_projectile_level>0:support=false
	if template == "aoe" or card.target_type in [&"all_enemies",&"all_allies"]:
		var wave := ground(StringName("magic_"+school+"_rune"),Vector3(0,0.24,0),12.0)
		wave.scale = Vector3.ONE*0.08
		var expand := create_tween()
		expand.tween_property(wave,"scale",Vector3.ONE,0.48*rate)
		expand.parallel().tween_property(wave,"opacity",0.0,0.55*rate)
		expand.tween_callback(wave.queue_free)
	var summon: Node3D=null
	if current_summon:
		var circle:=ground(StringName("magic_"+school+"_rune"),summon_position+Vector3(0,0.25,0),4.8)
		# Give the central stage camera time to settle before the creature appears.
		if host.has_method("wait_for_shot"):await host.wait_for_shot()
		if "camera_action_id" in host and camera_token!=host.camera_action_id:return
		summon=preload("res://scripts/fusion_3d/summoned_actor.gd").new()
		summon.school=school
		summon.spell_id=preload("res://scripts/fusion_3d/summoned_actor.gd").visual_spell_id(card)
		layer.add_child(summon)
		summon.position=summon_position
		if not targets.is_empty():summon.face_target(host.actors[targets[0].id].global_position)
		summon.scale=Vector3.ONE*0.02
		summon.position.y=summon_position.y-0.3
		var frame_size: Vector3=summon.model_size*summon.display_scale
		camera_event.emit(&"SUMMON_APPEAR",{"anchor":host.to_local(layer.to_global(summon_position))+Vector3.UP*frame_size.y*(float(host.camera_config.shots.summon.focus_height_ratio) if "camera_config" in host else 0.4),"size":frame_size,"front":(host.global_basis.inverse()*summon.front_global()).normalized()},camera_token)
		marker.emit(&"SUMMON_APPEAR")
		var arrival_seconds:=0.9
		var attack_release_seconds:=0.77
		var arrive:=create_tween().set_parallel(true)
		arrive.tween_property(summon,"scale",Vector3.ONE*summon.display_scale,arrival_seconds*rate).set_trans(Tween.TRANS_CUBIC)
		arrive.tween_property(summon,"position:y",summon_position.y,arrival_seconds*rate)
		var reveal_fraction: float=clampf(float(host.camera_config.shots.summon.reveal_start_fraction),0.0,0.9) if "camera_config" in host else 0.3
		arrive.tween_callback(func():camera_event.emit(&"SUMMON_REVEAL",{"seconds":arrival_seconds*(1.0-reveal_fraction)},camera_token)).set_delay(arrival_seconds*rate*reveal_fraction)
		await arrive.finished
		if "camera_action_id" in host and camera_token!=host.camera_action_id:return
		marker.emit(&"SUMMON_HOLD")
		var charge=preload("res://scripts/fusion_3d/vfx/magic_radiance.gd").create(layer,host.COLORS.get(school,host.GOLD),0.9)
		charge.name="SummonChargeGlow"
		charge.source=summon
		charge.global_position=summon.release_global()
		charge.strength=0.05
		var gather:=create_tween()
		gather.tween_property(charge,"strength",1.15,1.32*rate).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await get_tree().create_timer(0.55*rate).timeout
		if "camera_action_id" in host and camera_token!=host.camera_action_id:return
		summon.strike(1.4*rate)
		camera_event.emit(&"SUMMON_ATTACK",{"seconds":attack_release_seconds},camera_token)
		marker.emit(&"SUMMON_ATTACK")
		# Release from the visible attack pose, not from the animation's first frame.
		await get_tree().create_timer(attack_release_seconds*rate).timeout
		if "camera_action_id" in host and camera_token!=host.camera_action_id:return
		var discharge:=create_tween()
		discharge.tween_property(charge,"strength",0.0,0.12*rate)
		discharge.tween_callback(charge.queue_free)
		var vanish:=create_tween()
		vanish.tween_interval(1.8*rate)
		vanish.tween_property(summon,"scale",Vector3.ONE*0.01,0.5*rate)
		vanish.tween_callback(summon.queue_free)
		vanish.tween_callback(circle.queue_free)
	camera_event.emit(&"ATTACK_RELEASE",{},camera_token)
	marker.emit(&"ATTACK_RELEASE")
	var cast_body: Node3D = host.actors[caster.id].get_node("Body")
	var release_position: Vector3 = host.to_local(cast_body.anchor_global("CastRelease"))
	if summon!=null:release_position=host.to_local(summon.release_global())
	if library_projectile_level>0:
		await play_library_projectile(release_position,targets,rate,card.target_type==&"all_allies",camera_token)
		if "camera_action_id" in host and camera_token!=host.camera_action_id:return
		rune.queue_free();aura.queue_free()
		create_tween().tween_property(host,"cinematic_weight",0.0,0.35*rate)
		phase="idle"
		if not ("shell" in host):marker.emit(&"EXIT")
		return
	for target in targets:
		var destination: Vector3 = host.to_local(host.actors[target.id].get_node("Body").anchor_global("HitPoint"))
		if not support and template == "direct_beam":
			var start := release_position
			var beam := MeshInstance3D.new()
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.055
			mesh.bottom_radius = 0.13
			mesh.height = start.distance_to(destination)
			beam.mesh = mesh
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = color
			beam.material_override = mat
			layer.add_child(beam)
			beam.position = (start+destination)*0.5
			var direction := (destination-start).normalized()
			beam.quaternion = Quaternion(Vector3.UP,direction)
			var fade_beam := create_tween()
			fade_beam.tween_property(beam,"transparency",1.0,0.5*rate)
			fade_beam.tween_callback(beam.queue_free)
		if not support or summon!=null:
			if template=="direct_beam" and not support:continue
			var missile := effect(cast_school,"heal" if support else "projectile",release_position,2.0)
			if release_position.distance_to(destination)>0.01:missile.look_at(layer.to_global(destination))
			var flight := create_tween()
			flight.tween_property(missile,"position",destination,0.48*rate).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			flight.tween_callback(missile.queue_free)
	await get_tree().create_timer(0.5*rate).timeout
	if "camera_action_id" in host and camera_token!=host.camera_action_id:return
	camera_event.emit(&"IMPACT",{},camera_token)
	phase = "impact"
	for target in targets:
		# Actual damage/miss is supplied by combat events, so this is only the release flash.
		if support:
			var sigil := effect(cast_school,"heal",host.actors[target.id].position+Vector3.UP*0.15,2.0)
			var fade := create_tween()
			fade.tween_property(sigil,"opacity",0.0,0.6*rate)
			fade.tween_callback(sigil.queue_free)
	rune.queue_free()
	aura.queue_free()
	create_tween().tween_property(host,"cinematic_weight",0.0,0.35*rate)
	phase = "idle"
	if not ("shell" in host): marker.emit(&"EXIT")







func play_library_projectile(start: Vector3, targets: Array[BattleUnitStateV2], rate: float, healing: bool=false, camera_token: int=-1) -> void:
	var library=preload("res://scripts/fusion_3d/vfx/arcana_spell_vfx.gd")
	# Keep the target shot established at release; do not cut out to the entire
	# arena and back again during a sub-second flight. The host scales shot time.
	var destinations: Array[Vector3]=[]
	var longest_distance := 0.0
	for target in targets:
		var destination: Vector3=host.to_local(host.actors[target.id].get_node("Body").anchor_global("HitPoint"))
		destinations.append(destination)
		longest_distance=maxf(longest_distance,start.distance_to(destination))
	# A volley shares one arrival beat even when the enemy slots differ in range.
	var flight_seconds: float=library.flight_duration(longest_distance,library_projectile_school)
	var missiles: Array=[]
	for destination in destinations:
		var missile=library.new();layer.add_child(missile)
		missile.setup(library_projectile_school,library_projectile_level,"missile",rate);missile.position=start
		if current_summon:missile.scale*=1.25
		missile.launch(start,destination,flight_seconds,library_projectile_school)
		missiles.append(missile)
	marker.emit(&"LIBRARY_PROJECTILE_LAUNCH")
	if not missiles.is_empty():await missiles[-1].arrived
	if "camera_action_id" in host and camera_token!=host.camera_action_id:return
	camera_event.emit(&"IMPACT",{},camera_token)
	phase="impact"
	for target_index in destinations.size():
		var destination: Vector3=destinations[target_index]
		if healing:
			var heal_flash=effect("life","heal",destination,2.5)
			var fade=create_tween();fade.tween_property(heal_flash,"opacity",0.0,.8*rate);fade.tween_callback(heal_flash.queue_free)
			continue
		var explosion=library.new();layer.add_child(explosion)
		var floor_y: float=host.actors[targets[target_index].id].position.y
		explosion.setup(library_projectile_school,library_projectile_level,"end",rate,floor_y-destination.y);explosion.position=destination
	marker.emit(&"LIBRARY_PROJECTILE_IMPACT")

func cast_symbol_position(caster_id: StringName) -> Vector3:
	var body: Node3D=host.actors[caster_id].get_node("Body")
	var forward: Vector3=host.global_basis.inverse()*(-body.global_basis.z)
	forward.y=0
	var ratio: float=host.actor_size_ratio(caster_id) if host.has_method("actor_size_ratio") else 1.0
	return host.actors[caster_id].position+forward.normalized()*CAST_SYMBOL_FORWARD_DISTANCE+Vector3.UP*2.05*ratio

func status_effect(id: String, target_id: StringName) -> Node3D:
	if not host.actors.has(target_id):return null
	var fx=preload("res://scripts/fusion_3d/vfx/approved_status_effect.gd").new()
	layer.add_child(fx)
	var ratio: float=host.actor_size_ratio(target_id) if host.has_method("actor_size_ratio") else 1.0
	var rate: float=host.cinematic_rate if "cinematic_rate" in host else 1.0
	fx.setup(id,ratio,rate)
	fx.position+=host.actors[target_id].position
	if id in ["15","16"]:
		fx.rotation.y+=host.actors[target_id].get_node("Body").rotation.y
	return fx

func dot_impact(target_id: StringName, school: String) -> bool:
	var ids={"fire":"17","death":"18","storm":"19","ice":"23","myth":"25","balance":"26","life":"24"}
	if not ids.has(school):return false
	status_effect(ids[school],target_id)
	audio.hit_feedback(false, school, "dot")
	if host.actors.has(target_id):host.actors[target_id].get_node("Body").hit()
	return true

func status_event(event: BattleEventV2) -> bool:
	audio.status_feedback(event)
	var p=event.payload
	var id=StringName(str(p.get("target_id",p.get("unit_id",""))))
	var kind=str(p.get("kind",""))
	if event.type==&"StatusApplied" and str(p.get("status",{}).get("kind","")) in ["shield","absorb"]:
		status_effect("15",id)
		return true
	if (event.type in [&"StatusConsumed",&"StatusRemoved",&"StatusExpired"] and kind in ["shield","absorb"]) or (event.type==&"AbsorbTriggered" and int(p.get("remaining_capacity",1))<=0):
		status_effect("16",id)
		return true
	if event.type==&"StatusRemoved" and str(p.get("reason",""))=="cleanse":
		status_effect("22",id)
		return true
	return false
