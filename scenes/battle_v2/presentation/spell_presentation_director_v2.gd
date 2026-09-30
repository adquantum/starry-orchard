class_name SpellPresentationDirectorV2
extends Control

signal marker_reached(marker: StringName, context: Dictionary)
signal presentation_finished(card_id: StringName, elapsed: float)

const SpellActorScript = preload("res://scenes/battle_v2/presentation/spell_presentation_actor_v2.gd")
const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const WorldStatusVisualScript = preload("res://scenes/battle_v2/presentation/world_status_visual_v2.gd")
const TEMPLATE_PATH := "res://resources/battle_v2/presentation/spell_templates.json"
const CAST_PRESET_PATH := "res://resources/battle_v2/presentation/school_cast_presets.json"
const MULTI_HIT_INTERVAL := 0.5

var templates: Dictionary = {}
var cast_presets: Dictionary = {}
var cast_phases: Array = []
var playback_speed := 1.0
var test_duration_scale := 1.0
var last_elapsed := 0.0
var last_nominal_duration := 0.0
var last_template_id: StringName
var marker_history: Array[StringName] = []
var active := false
var camera_template: StringName = &"camera_static"
var current_phase: StringName
var phase_elapsed := 0.0
var phase_duration := 1.0
var caster_anchor := Vector2.ZERO
var caster_floor_anchor := Vector2.ZERO
var target_anchors: Array[Vector2] = []
var target_floor_anchors: Array[Vector2] = []
var projectile_texture: Texture2D
var impact_texture: Texture2D
var impact_on_floor := false
var impact_floor_scale_y := 1.0
var last_impact_on_floor := false
var projectile_visible := false
var impact_visible := false
var school_cast_visible := false
var school_cast_texture: Texture2D
var school_cast_tint := Color.WHITE
var damage_popups: Array[Dictionary] = []
var result_wave_history: Array[Dictionary] = []
var current_context: Dictionary = {}
var spell_actor: SpellPresentationActorV2
var school_cast_audio: AudioStreamPlayer
var battle_center_global := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_load_templates()
	_load_cast_presets()
	spell_actor = SpellActorScript.new()
	spell_actor.z_index = 4
	add_child(spell_actor)
	school_cast_audio = AudioStreamPlayer.new()
	school_cast_audio.name = "SchoolCastAudio"
	school_cast_audio.volume_db = -5.5
	add_child(school_cast_audio)
	hide()
	set_process(true)


func set_playback_speed(value: float) -> void:
	playback_speed = clampf(value, 1.0, 2.0)


func set_battle_center(center_global: Vector2) -> void:
	battle_center_global = center_global


func play_turn_start_events(events: Array[BattleEventV2], view_by_id: Dictionary, frozen_status_views: Array[Control]) -> void:
	var result_events: Array[BattleEventV2] = []
	for event: BattleEventV2 in events:
		if event.type in [&"DamageResolved", &"HealingResolved"]:
			result_events.append(event)
	if result_events.is_empty():
		for frozen_view in frozen_status_views:
			frozen_view.clear_presentation_statuses()
		return
	active = true
	show()
	impact_visible = true
	impact_on_floor = true
	impact_floor_scale_y = 0.42
	last_impact_on_floor = true
	current_phase = &"turn_start_tick"
	phase_duration = 0.42 / playback_speed
	phase_elapsed = 0.0
	var touched_views: Dictionary = {}
	for event: BattleEventV2 in result_events:
		var target_id := StringName(str(event.payload.get("target_id", "")))
		var target_view: Control = view_by_id.get(target_id)
		if target_view == null:
			continue
		touched_views[target_id] = target_view
		target_anchors = [target_view.get_target_anchor_global()]
		var is_heal := event.type == &"HealingResolved"
		var origin := StringName(str(event.payload.get("origin", "dot")))
		var ground_kind := &"hot" if is_heal else &"delay_damage" if origin == &"delay_damage" else &"dot"
		target_floor_anchors = [target_view.get_cast_floor_anchor_global() + WorldStatusVisualScript.ground_visual_offset(ground_kind)]
		impact_texture = ArtRegistryScript.texture(StringName("world_%s" % ground_kind))
		damage_popups = [{
			"position":target_view.get_target_anchor_global() - Vector2(0, 48),
			"amount":int(event.payload.get("final_amount", 0)), "heal":is_heal
		}]
		target_view.notify_status_event(ground_kind)
		target_view.nameplate.hold_presentation_hp(int(event.payload.get("hp_before", target_view.unit.hp)))
		target_view.play_character_animation(&"revive" if is_heal else &"hit")
		phase_elapsed = 0.0
		queue_redraw()
		await get_tree().create_timer(phase_duration * 0.34).timeout
		target_view.nameplate.hold_presentation_hp(int(event.payload.get("hp_after", target_view.unit.hp)))
		await get_tree().create_timer(phase_duration * 0.66).timeout
	for frozen_view in frozen_status_views:
		frozen_view.clear_presentation_statuses()
	for target_view: Control in touched_views.values():
		target_view.nameplate.release_presentation_hp()
	damage_popups.clear()
	impact_visible = false
	active = false
	hide()
	queue_redraw()

func play_action(caster_view: Control, target_views: Array[Control], card: CardDefinitionV2, events: Array[BattleEventV2], hp_before: Dictionary, frozen_status_views: Array[Control] = []) -> float:
	var started := Time.get_ticks_msec()
	current_context = {"caster_view":caster_view, "target_views":target_views, "card":card, "events":events, "hp_before":hp_before, "frozen_status_views":frozen_status_views}
	caster_anchor = caster_view.get_target_anchor_global()
	caster_floor_anchor = caster_view.get_cast_floor_anchor_global()
	target_anchors.clear()
	target_floor_anchors.clear()
	for target_view in target_views:
		target_anchors.append(target_view.get_target_anchor_global())
		target_floor_anchors.append(target_view.get_cast_floor_anchor_global())
	var config := card.presentation
	var template_id := StringName(str(config.get("template", "direct_projectile")))
	last_template_id = template_id
	marker_history.clear()
	var template := templates.get(str(template_id), {}) as Dictionary
	if template.is_empty():
		template = templates.get("direct_projectile", {}) as Dictionary
	camera_template = StringName(str(config.get("camera", template.get("camera", "camera_static"))))
	projectile_texture = ArtRegistryScript.texture(StringName(str(config.get("projectile", "magic_%s_projectile" % str(card.school_id)))))
	var impact_asset_id := StringName(str(config.get("impact", "magic_%s_impact" % str(card.school_id))))
	impact_texture = ArtRegistryScript.texture(impact_asset_id)
	impact_on_floor = str(impact_asset_id).ends_with("_ground") or template_id in [&"ground_spell", &"delayed_spell"] or _card_has_timed_ground_effect(card)
	impact_floor_scale_y = 1.0 if str(impact_asset_id).ends_with("_ground") else 0.42
	last_impact_on_floor = impact_on_floor
	result_wave_history.clear()
	if template_id in [&"summon_attack", &"summon_cast"]:
		spell_actor.setup(StringName(str(config.get("summon", "fire_serpent"))))
		var summon_center := battle_center_global if battle_center_global != Vector2.ZERO else size * 0.5
		spell_actor.position = summon_center - Vector2(128, 128)
	active = true
	show()
	queue_redraw()
	var duration_scale := maxf(0.01, float(config.get("duration_scale", 1.0)) * test_duration_scale)
	last_nominal_duration = (cast_preset_duration(card.school_id) + template_duration(template_id)) * float(config.get("duration_scale", 1.0))
	await _play_school_cast(card.school_id, duration_scale)
	for phase_value in template.get("phases", []):
		var phase := phase_value as Dictionary
		if StringName(str(phase.get("id", ""))) == &"caster_cast":
			continue
		await _play_phase(phase, duration_scale)
	_cleanup()
	var elapsed := float(Time.get_ticks_msec() - started) / 1000.0
	last_elapsed = elapsed
	presentation_finished.emit(card.id, elapsed)
	return elapsed


func _play_phase(phase: Dictionary, duration_scale: float) -> void:
	current_phase = StringName(str(phase.get("id", "unknown")))
	phase_duration = float(phase.get("duration", 0.25)) * duration_scale / playback_speed
	phase_elapsed = 0.0
	_enter_phase(current_phase)
	var markers := phase.get("markers", {}) as Dictionary
	var marker_entries: Array[Dictionary] = []
	for marker_name in markers:
		marker_entries.append({"name":StringName(str(marker_name)), "time":float(markers[marker_name]) * duration_scale / playback_speed})
	marker_entries.sort_custom(func(a: Dictionary, b: Dictionary): return float(a["time"]) < float(b["time"]))
	var cursor := 0.0
	for marker in marker_entries:
		var marker_time := clampf(float(marker["time"]), cursor, phase_duration)
		if marker_time > cursor:
			await get_tree().create_timer(marker_time - cursor).timeout
		cursor = marker_time
		await _handle_marker(marker["name"])
	if phase_duration > cursor:
		await get_tree().create_timer(phase_duration - cursor).timeout


func _enter_phase(phase: StringName) -> void:
	school_cast_visible = str(phase).begins_with("school_")
	projectile_visible = phase in [&"projectile_spawn", &"projectile_travel", &"beam", &"buff_fly", &"aoe_release"]
	impact_visible = phase in [&"impact", &"heal_particles", &"ground_rune"]
	match phase:
		&"school_ready":
			(current_context["caster_view"] as Control).play_character_animation(&"cast_start")
		&"caster_cast":
			(current_context["caster_view"] as Control).play_character_animation(&"cast_start")
		&"summon_circle":
			spell_actor.show_pose(&"appear")
			spell_actor.modulate.a = 0.45
		&"summon_appear":
			spell_actor.show_pose(&"appear")
			spell_actor.modulate.a = 1.0
		&"summon_idle": spell_actor.show_pose(&"idle")
		&"summon_attack": spell_actor.show_pose(&"attack")
		&"summon_exit": spell_actor.show_pose(&"exit")
	queue_redraw()


func _handle_marker(marker: StringName) -> void:
	marker_history.append(marker)
	marker_reached.emit(marker, current_context)
	match marker:
		&"CAST_RELEASE":
			(current_context["caster_view"] as Control).play_character_animation(&"cast_release")
		&"IMPACT":
			impact_visible = true
			_release_status_snapshots()
			await _show_results()
		&"EXIT":
			spell_actor.modulate.a = 0.55
	queue_redraw()


func _release_status_snapshots() -> void:
	for view: Control in current_context.get("frozen_status_views", []):
		view.clear_presentation_statuses()


func _show_results() -> void:
	damage_popups.clear()
	result_wave_history.clear()
	var waves: Array = []
	var occurrence_by_target: Dictionary = {}
	for event: BattleEventV2 in current_context["events"]:
		if event.type not in [&"DamageResolved", &"HealingResolved", &"UnitRevived"]:
			continue
		var target_id := StringName(str(event.payload.get("target_id", event.payload.get("unit_id", ""))))
		var wave_index := int(occurrence_by_target.get(target_id, 0))
		occurrence_by_target[target_id] = wave_index + 1
		while waves.size() <= wave_index:
			waves.append([])
		(waves[wave_index] as Array).append(event)
	for wave_index in waves.size():
		damage_popups.clear()
		for event: BattleEventV2 in waves[wave_index] as Array:
			var target_id := StringName(str(event.payload.get("target_id", event.payload.get("unit_id", ""))))
			var target_view := _target_view(target_id)
			if target_view == null:
				continue
			var heal := event.type != &"DamageResolved"
			var amount := int(event.payload.get("final_amount", event.payload.get("amount", event.payload.get("hp", 0))))
			target_view.play_character_animation(&"revive" if heal else &"hit")
			target_view.nameplate.hold_presentation_hp(int(event.payload.get("hp_after", target_view.unit.hp)))
			var popup := {"position":target_view.get_target_anchor_global() - Vector2(0, 48), "amount":amount, "heal":heal, "wave":wave_index, "target_id":target_id}
			damage_popups.append(popup)
			result_wave_history.append(popup.duplicate())
		queue_redraw()
		if wave_index < waves.size() - 1:
			await get_tree().create_timer(MULTI_HIT_INTERVAL * maxf(test_duration_scale, 0.01) / playback_speed).timeout
	for target_view: Control in current_context["target_views"]:
		target_view.nameplate.release_presentation_hp()


func _target_view(target_id: StringName) -> Control:
	for target_view: Control in current_context.get("target_views", []):
		if target_view.unit.id == target_id:
			return target_view
	return null


func _card_has_timed_ground_effect(card: CardDefinitionV2) -> bool:
	for effect: Dictionary in card.effects:
		if StringName(str(effect.get("type", ""))) in [&"apply_dot", &"apply_hot", &"delay_damage"]:
			return true
	return false


func _process(delta: float) -> void:
	if not active:
		return
	phase_elapsed += delta
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	_draw_camera_overlay()
	var target := target_anchors[0] if not target_anchors.is_empty() else size * 0.5
	var progress := clampf(phase_elapsed / maxf(phase_duration, 0.001), 0.0, 1.0)
	if projectile_visible and projectile_texture != null:
		var position := caster_anchor.lerp(target, progress if current_phase in [&"projectile_travel", &"beam", &"buff_fly"] else 0.08)
		var visual_size := Vector2.ONE * (82.0 if current_phase == &"beam" else 68.0)
		draw_texture_rect(projectile_texture, Rect2(position - visual_size * 0.5, visual_size), false)
	if impact_visible and impact_texture != null:
		var impact_anchors := target_floor_anchors if impact_on_floor else target_anchors
		for anchor in impact_anchors:
			var visual_size := Vector2.ONE * (104.0 + sin(progress * PI) * 24.0)
			if impact_on_floor:
				draw_set_transform(anchor, 0.0, Vector2(1.0, impact_floor_scale_y))
				draw_texture_rect(impact_texture, Rect2(-visual_size * 0.5, visual_size), false, Color(1, 1, 1, 0.92))
				draw_set_transform(Vector2.ZERO)
			else:
				draw_texture_rect(impact_texture, Rect2(anchor - visual_size * 0.5, visual_size), false, Color(1, 1, 1, 0.92))
	if school_cast_visible and school_cast_texture != null:
		var cast_progress := clampf(phase_elapsed / maxf(phase_duration, 0.001), 0.0, 1.0)
		var cast_size := 138.0 + sin(cast_progress * PI) * 24.0
		var cast_alpha := 0.38 + sin(cast_progress * PI) * 0.52
		# The cast atlas uses a shared floor anchor at 78% of the cell height.
		# Align that rune center with the wizard's actual foot ring, not the chest target anchor.
		draw_texture_rect(school_cast_texture, Rect2(caster_floor_anchor - Vector2(cast_size * 0.5, cast_size * 0.78), Vector2.ONE * cast_size), false, Color(school_cast_tint, cast_alpha))
	for popup in damage_popups:
		var color := Color("#8dffad") if bool(popup["heal"]) else Color("#fff0a0")
		draw_string(ThemeDB.fallback_font, popup["position"], str(absi(int(popup["amount"]))), HORIZONTAL_ALIGNMENT_CENTER, 100, 28, color)


func _draw_camera_overlay() -> void:
	if camera_template == &"camera_static":
		return
	var alpha := 0.10 if camera_template == &"camera_full_field" else 0.18
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.02, 0.05, alpha))
	var stage_center := battle_center_global if battle_center_global != Vector2.ZERO else size * 0.5
	var focus := stage_center if camera_template == &"camera_center_summon" else (target_anchors[0] if not target_anchors.is_empty() else caster_anchor)
	draw_circle(focus, 118, Color(0.3, 0.6, 1.0, 0.035))


func _cleanup() -> void:
	_release_status_snapshots()
	for target_view: Control in current_context.get("target_views", []):
		target_view.nameplate.release_presentation_hp()
	projectile_visible = false
	impact_visible = false
	impact_on_floor = false
	impact_floor_scale_y = 1.0
	school_cast_visible = false
	school_cast_texture = null
	damage_popups.clear()
	spell_actor.clear_actor()
	if school_cast_audio != null:
		school_cast_audio.stop()
		school_cast_audio.stream = null
	active = false
	hide()
	queue_redraw()


func _load_templates() -> void:
	var file := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if file == null:
		push_error("SpellPresentationDirector missing template registry")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		templates = (parsed.get("templates", {}) as Dictionary).duplicate(true)


func _load_cast_presets() -> void:
	var file := FileAccess.open(CAST_PRESET_PATH, FileAccess.READ)
	if file == null:
		push_error("SpellPresentationDirector missing school cast presets")
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		cast_presets = (parsed.get("presets", {}) as Dictionary).duplicate(true)
		cast_phases = (parsed.get("shared_phases", []) as Array).duplicate(true)


func _play_school_cast(school_id: StringName, duration_scale: float) -> void:
	var preset := cast_presets.get(str(school_id), cast_presets.get("fire", {})) as Dictionary
	school_cast_texture = ArtRegistryScript.texture(StringName(str(preset.get("asset", "cast_fx_fire"))))
	school_cast_tint = Color(str(preset.get("tint", "#ffffff")))
	_play_school_cast_audio(str(preset.get("audio", "")))
	school_cast_audio.pitch_scale = playback_speed / maxf(duration_scale, 0.01)
	var timing_scale := _school_cast_timing_scale(school_id)
	for phase_value in cast_phases:
		await _play_phase(phase_value as Dictionary, duration_scale * timing_scale)


func _play_school_cast_audio(audio_path: String) -> void:
	if school_cast_audio == null:
		return
	school_cast_audio.stop()
	if audio_path.is_empty() or not ResourceLoader.exists(audio_path):
		school_cast_audio.stream = null
		return
	school_cast_audio.stream = load(audio_path) as AudioStream
	school_cast_audio.pitch_scale = playback_speed
	school_cast_audio.play()


func template_duration(template_id: StringName) -> float:
	var template := templates.get(str(template_id), {}) as Dictionary
	var total := 0.0
	for value in template.get("phases", []):
		if StringName(str((value as Dictionary).get("id", ""))) != &"caster_cast":
			total += float((value as Dictionary).get("duration", 0.0))
	return total


func _school_cast_timing_scale(school_id: StringName) -> float:
	var elapsed := 0.0
	for value in cast_phases:
		var phase := value as Dictionary
		var markers := phase.get("markers", {}) as Dictionary
		if markers.has("CAST_RELEASE"):
			var base_release := elapsed + float(markers["CAST_RELEASE"])
			var preset := cast_presets.get(str(school_id), {}) as Dictionary
			return float(preset.get("audio_release_seconds", base_release)) / maxf(base_release, 0.01)
		elapsed += float(phase.get("duration", 0.0))
	return 1.0

func cast_preset_duration(school_id: StringName) -> float:
	var total := 0.0
	for value in cast_phases:
		total += float((value as Dictionary).get("duration", 0.0))
	return total * _school_cast_timing_scale(school_id)
