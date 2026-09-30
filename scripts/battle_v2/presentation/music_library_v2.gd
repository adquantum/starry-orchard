class_name MusicLibraryV2
extends RefCounted

const TRACK_PATHS := {
	&"combat_main":"res://assets/audio/music/combat_main.mp3",
	&"combat_ice":"res://assets/audio/music/combat_ice.mp3",
	&"combat_boss":"res://assets/audio/music/combat_boss.mp3",
	&"combat_sand":"res://assets/audio/music/combat_sand.mp3",
	&"wizard_river_town":"res://assets/audio/music/wizard_river_town.mp3",
	&"wizard_town_main":"res://assets/audio/music/wizard_town_main_theme.mp3",
}

const PLAYLISTS := {
	&"combat_main":[&"combat_main"],
	&"combat_frost":[&"combat_main", &"combat_ice"],
	&"combat_boss":[&"combat_boss"],
	&"combat_sand":[&"combat_sand"],
	&"town":[&"wizard_river_town", &"wizard_town_main"],
}


static func playlist(context: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for track_id in PLAYLISTS.get(context, []):
		result.append(StringName(str(track_id)))
	return result


static func load_track(track_id: StringName) -> AudioStream:
	var path := str(TRACK_PATHS.get(track_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_warning("Music track is missing: %s" % track_id)
		return null
	return load(path) as AudioStream


static func play_random(player: AudioStreamPlayer, context: StringName) -> StringName:
	if player == null:
		return &""
	var track_ids := playlist(context)
	if track_ids.is_empty():
		return &""
	var track_id := track_ids[randi_range(0, track_ids.size() - 1)]
	var audio := load_track(track_id)
	if audio == null:
		return &""
	var mp3_stream := audio as AudioStreamMP3
	if mp3_stream != null:
		mp3_stream.loop = true
	player.stop()
	player.stream = audio
	player.play()
	return track_id
