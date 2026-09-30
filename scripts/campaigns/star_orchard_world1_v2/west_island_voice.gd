extends Node
## Local dialogue audio; never pauses or changes authoritative battle turns.
signal clip_started(clip_id: String)
signal sequence_finished

const CATALOG := "res://resources/campaigns/star_orchard_world1_v2/west_voice.json"
var player: AudioStreamPlayer
var panel: Control
var clips: Dictionary = {}
var phrases: Array = []
var pending: Array[String] = []
var current_clip := ""
var missing_text: Dictionary = {}
var punctuation := RegEx.new()

func _ready() -> void:
	punctuation.compile("[\\s，。！？；：、,.!?;:…—“”「」（）()\\[\\]\"']")
	if FileAccess.file_exists(CATALOG):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if data is Dictionary:
			clips = data.get("clips", {})
			for id in clips:
				phrases.append({"id":str(id), "text":_normalize(str(clips[id].text))})
			phrases.sort_custom(func(a: Dictionary, b: Dictionary): return a.text.length() > b.text.length())
	if AudioServer.get_bus_index("AcademyVoice") < 0:
		var index := AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, "AcademyVoice")
		AudioServer.set_bus_send(index, "Master")
	player = AudioStreamPlayer.new()
	player.name = "DialogueVoice"
	player.bus = "AcademyVoice"
	player.volume_db = -2.0
	add_child(player)
	player.finished.connect(_play_next)
	panel = get_parent() as Control
	if panel != null: panel.visibility_changed.connect(_visibility_changed)

func _normalize(text: String) -> String:
	return punctuation.sub(text.replace("怪物动向：", ""), "", true)

func sequence_for(text: String) -> Array[String]:
	var rest := _normalize(text)
	var result: Array[String] = []
	while not rest.is_empty():
		var found := false
		for phrase in phrases:
			if not str(phrase.text).is_empty() and rest.begins_with(str(phrase.text)):
				result.append(str(phrase.id))
				rest = rest.substr(str(phrase.text).length())
				found = true
				break
		if not found: return []
	return result

func play_text(text: String) -> void:
	stop()
	if panel != null and not panel.is_visible_in_tree(): return
	pending = sequence_for(text)
	if pending.is_empty():
		if not text.is_empty() and not missing_text.has(text):
			missing_text[text] = true
			push_warning("West island voice has no matching recording for the displayed text.")
		return
	_play_next()

func stop() -> void:
	pending.clear()
	current_clip = ""
	if is_instance_valid(player): player.stop()

func _play_next() -> void:
	if panel != null and not panel.is_visible_in_tree():
		stop()
		return
	while not pending.is_empty():
		var id: String = pending.pop_front()
		var path := str(clips[id].file)
		var stream := load(path) as AudioStream
		if stream == null: continue
		current_clip = id
		player.stream = stream
		player.play()
		clip_started.emit(id)
		return
	current_clip = ""
	sequence_finished.emit()

func _visibility_changed() -> void:
	if not panel.is_visible_in_tree(): stop()

func _process(_delta: float) -> void:
	# Parent CanvasLayer visibility also matters when the whole world UI is hidden.
	if not current_clip.is_empty() and panel != null and not panel.is_visible_in_tree(): stop()
