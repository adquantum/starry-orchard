extends Node
var players: Array[AudioStreamPlayer] = []
var config: Dictionary
var current := ""
var transition: Tween
var in_battle := false
var muted := false
var town_track_override := ""
var town_volume_db_offset := 0.0
func _ready() -> void:
	config = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/exploration_music.json"))
	if AudioServer.get_bus_index("AcademyMusic")<0:
		var index := AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index,"AcademyMusic")
		AudioServer.set_bus_send(index,"Master")
	for id in ["town","garden"]:
		var player := AudioStreamPlayer.new()
		player.name = id
		player.bus = "AcademyMusic"
		var stream_path := town_track_override if id == "town" and not town_track_override.is_empty() else str(config[id])
		player.stream = (load(stream_path) as AudioStream).duplicate()
		if player.stream is AudioStreamMP3: player.stream.loop = true
		player.volume_db = -60
		add_child(player)
		players.append(player)
	set_region("town")
func set_region(id: String) -> void:
	if id == current: return
	current = id
	if transition != null and transition.is_valid(): transition.kill()
	transition = create_tween().set_parallel(true)
	for player in players:
		var selected := player.name == id
		if selected and not player.playing: player.play()
		player.stream_paused = in_battle or muted
		var target_db := float(config.volume_db) + (town_volume_db_offset if id == "town" else 0.0)
		transition.tween_property(player,"volume_db",target_db if selected else -60.0,float(config.crossfade_seconds))
func set_battle(value: bool) -> void:
	in_battle = value
	if transition != null and transition.is_valid(): transition.kill()
	if in_battle:
		# Cut the exploration tail immediately before the combat stream starts.
		for player in players:
			player.volume_db = -80.0
			player.stream_paused = true
	else:
		transition = create_tween().set_parallel(true)
		for player in players:
			player.stream_paused = muted
			var target_db := float(config.volume_db) + (town_volume_db_offset if player.name == "town" else 0.0)
			transition.tween_property(player, "volume_db", target_db if player.name == current else -60.0, 0.25)
func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("AcademyMusic"),muted)
	for player in players: player.stream_paused = in_battle or muted
func _exit_tree() -> void:
	for player in players: player.stop()
