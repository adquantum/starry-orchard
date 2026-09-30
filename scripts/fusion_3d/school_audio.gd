extends Node
## Presentation audio. Approved clips supply the animation's release timing.
signal cast_started(school: String, serial: int)
signal feedback_started(key: String, path: String)
var config: Dictionary
var presets: Dictionary
var school_player: AudioStreamPlayer
var impact_player: AudioStreamPlayer
var ui_player: AudioStreamPlayer
var music: AudioStreamPlayer
var music_base := 0.0
var music_tween: Tween
var fade_tween: Tween
var serial := 0
var played_serial := -1
var school := "fire"
var speed := 1.0
var active := false
var start_counts: Dictionary = {}
var impact_count := 0
var delay_token := 0
var feedback_players: Dictionary = {}
var result_cues: Dictionary = {}
var draw_pending := false

func begin_result_batch() -> void:
	result_cues.clear()

func result_feedback(event: BattleEventV2) -> void:
	var key := ""
	if event.type == &"SpellMissed": key = "spell_miss"
	elif event.type == &"UnitDied": key = "unit_down"
	if not key.is_empty() and not result_cues.has(key):
		result_cues[key] = true
		_play_feedback(key)

func planning_feedback(event: BattleEventV2, local_actor: bool) -> void:
	if not local_actor: return
	if event.type in [&"CardDrawn", &"TreasureDrawn"]:
		if event.payload.get("deck_config", false) or draw_pending: return
		draw_pending = true
		_flush_draw.call_deferred()
	elif event.type == &"ActionLocked": _play_feedback("action_confirm")
	elif event.type == &"CardsFused": _play_feedback("fusion")

func _flush_draw() -> void:
	if not draw_pending: return
	draw_pending = false
	_play_feedback("card_draw")

func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/audio_mix.json"))
	presets = JSON.parse_string(FileAccess.get_file_as_string(config.source_presets)).presets
	for title in ["AcademyMusic","AcademyCast","AcademyImpact","AcademyUI"]:
		if AudioServer.get_bus_index(title) < 0:
			var index := AudioServer.bus_count
			AudioServer.add_bus()
			AudioServer.set_bus_name(index,title)
			AudioServer.set_bus_send(index,"Master")
	school_player = _player("SchoolCast","AcademyCast",config.cast_volume_db)
	impact_player = _player("HitFeedback","AcademyImpact",config.impact_volume_db)
	impact_player.max_polyphony = 4
	ui_player = _player("UIFeedback","AcademyUI",config.ui_volume_db)

func _player(title: String, bus: String, db: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = title
	player.bus = bus
	player.volume_db = db
	add_child(player)
	return player

func bind_music(player: AudioStreamPlayer) -> void:
	if music == player: return
	music = player
	music_base = player.volume_db
	music.bus = "AcademyMusic"

func release_seconds(spell_school: String, fallback: float) -> float:
	return maxf(float(presets.get(spell_school, {}).get("audio_release_seconds", fallback)), 0.05)

func begin_action(spell_school: String, playback: float) -> void:
	delay_token += 1
	serial += 1
	active = true
	school = spell_school
	speed = maxf(playback, 0.01)
	if fade_tween != null and fade_tween.is_valid(): fade_tween.kill()
	school_player.stop()
	school_player.volume_db = config.cast_volume_db

func on_marker(id: StringName) -> void:
	if str(id) == str(config.trigger_marker) and active and played_serial != serial:
		# Consume before any await: duplicate markers, targets and acceleration cannot replay.
		played_serial = serial
		var offset := float(config.school_offsets_seconds.get(school,0.0))/speed
		var token := delay_token
		if offset > 0:
			await get_tree().create_timer(offset).timeout
			if token != delay_token or not active: return
		var path := str(presets.get(school,{}).get("audio",""))
		if not ResourceLoader.exists(path): return
		school_player.stream = load(path) as AudioStream
		school_player.pitch_scale = speed if config.pitch_follows_speed else 1.0
		school_player.play()
		start_counts[school] = int(start_counts.get(school,0))+1
		cast_started.emit(school,serial)
		_duck(music_base+float(config.music_duck_db),config.duck_in_seconds)
	elif id == &"EXIT": end_action()

func hit_feedback(healing: bool = false, damage_school: String = "", origin: String = "spell") -> void:
	impact_count += 1
	# Immediate recovery and HOT have separate approved clips; revive remains unselected.
	if healing and origin == "revive":
		return
	var key := "heal" if healing else "damage"
	if healing and origin == "hot": key = "hot_tick"
	if not healing and not damage_school.is_empty():
		var school_key := damage_school + ("_dot" if origin == "dot" else "_impact")
		if config.impact_streams.has(school_key):
			key = school_key
	_play_feedback(key)

func status_feedback(event: BattleEventV2) -> void:
	var payload := event.payload
	var kind := str(payload.get("kind", ""))
	if event.type == &"StatusRemoved" and str(payload.get("reason", "")) == "cleanse":
		if not result_cues.has("cleanse"):
			result_cues["cleanse"] = true
			_play_feedback("cleanse")
		return
	if event.type == &"StatusApplied":
		kind = str(payload.get("status", {}).get("kind", ""))
		if kind == "trap":
			_play_feedback("trap_added")
		elif kind in config.get("status_added_kinds", []):
			_play_feedback("status_added")
	elif event.type == &"StatusConsumed" and kind in ["shield", "absorb"]:
		if str(payload.get("reason", "")) != "debug_clear":
			_play_feedback("shield_break")
	elif event.type == &"AbsorbTriggered":
		_play_feedback("shield_break" if int(payload.get("remaining_capacity", 1)) <= 0 else "absorb_hit")
	elif event.type == &"StatusRemoved" and kind in ["shield", "absorb"]:
		if str(payload.get("reason", "")) not in ["debug_clear", "expired"]:
			_play_feedback("shield_break")

func _play_feedback(key: String) -> void:
	var path := str(config.impact_streams.get(key, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	# Keep one stream per player: changing a player's stream would cut off the preceding cue.
	var player := feedback_players.get(key) as AudioStreamPlayer
	if player == null:
		var stream := load(path) as AudioStream
		if stream == null:
			return
		player = impact_player if key == "heal" else _player("Feedback_" + key, "AcademyImpact", config.impact_volume_db)
		if key in ["card_draw", "action_confirm", "fusion"]:
			player.bus = "AcademyUI"
			player.volume_db = config.ui_volume_db
		player.max_polyphony = 4
		player.stream = stream
		feedback_players[key] = player
	player.play()
	feedback_started.emit(key, path)

func end_action() -> void:
	active = false
	delay_token += 1
	if fade_tween != null and fade_tween.is_valid(): fade_tween.kill()
	fade_tween = create_tween()
	fade_tween.tween_property(school_player,"volume_db",-60.0,float(config.cast_fade_seconds))
	fade_tween.tween_callback(school_player.stop)
	_duck(music_base,config.duck_out_seconds)

func _duck(db: float, seconds: float) -> void:
	if not is_instance_valid(music): return
	if music_tween != null and music_tween.is_valid(): music_tween.kill()
	music_tween = create_tween()
	music_tween.tween_property(music,"volume_db",db,seconds).set_trans(Tween.TRANS_SINE)

func stop_all() -> void:
	draw_pending = false
	result_cues.clear()
	active = false
	delay_token += 1
	if fade_tween != null and fade_tween.is_valid(): fade_tween.kill()
	if music_tween != null and music_tween.is_valid(): music_tween.kill()
	for player in [school_player,impact_player,ui_player]:
		if is_instance_valid(player):
			player.stop()
	for player: AudioStreamPlayer in feedback_players.values():
		player.stop()
	# Retain cached streams for the next action. The parent owns these players and
	# frees them on exit; don't queue child deletion during the parent's teardown.
	if is_instance_valid(music): music.volume_db = music_base

func _exit_tree() -> void:
	active = false
	delay_token += 1
	if fade_tween != null and fade_tween.is_valid(): fade_tween.kill()
	if music_tween != null and music_tween.is_valid(): music_tween.kill()
	# AudioStreamPlayer children stop themselves while exiting, before this callback.
	if is_instance_valid(music): music.volume_db = music_base

