extends RefCounted
const TRACK := "res://assets/audio/music/haqitown teen.mp3"
static func start(parent: Node) -> AudioStreamPlayer:
	if AudioServer.get_bus_index("AcademyMusic") < 0:
		var index := AudioServer.bus_count
		AudioServer.add_bus()
		AudioServer.set_bus_name(index, "AcademyMusic")
		AudioServer.set_bus_send(index, "Master")
	var player := AudioStreamPlayer.new()
	player.name = "MenuMusic"
	player.bus = "AcademyMusic"
	player.stream = (load(TRACK) as AudioStreamMP3).duplicate()
	(player.stream as AudioStreamMP3).loop = true
	player.volume_db = -15.0
	parent.add_child(player)
	player.play()
	return player
