extends Node
## Quest-driven local battle bridge. The caller owns unlocks, persistence and rewards.
signal encounter_started(encounter_id: String)
signal encounter_finished(encounter_id: String, won: bool)
const Catalog = preload("res://scripts/worlds/star_orchard_encounter_catalog.gd")
const Stage = preload("res://scenes/fusion_3d/battle_stage.tscn")
const Satellites = preload("res://scripts/worlds/star_orchard_satellites.gd")
const Variants = preload("res://scripts/worlds/star_orchard_variant_materials.gd")

var atlas: Node
var world: Node3D
var active := false
var active_id := ""
var stage: Node3D
var exit_layer: CanvasLayer
var music: Node
var saved_position := Vector3.ZERO
var saved_yaw := 0.0
var saved_pitch := 0.0
var saved_distance := 9.0
var hidden_canvases: Array[CanvasLayer] = []

func setup(target_atlas: Node, target_world: Node3D) -> void:
	atlas = target_atlas
	world = target_world
	for child in world.get_children():
		if child.get_script() == preload("res://scripts/fusion_3d/exploration_music.gd"):
			music = child
			break

func begin(encounter_id: String) -> bool:
	if active or not is_instance_valid(world) or not is_instance_valid(atlas) or not world.ready_world or atlas.busy:
		return false
	var definition := Catalog.get_encounter(encounter_id)
	if definition.is_empty(): return false
	# Sea-route editing temporarily suspends branch arenas; keep all quest progress.
	if not Satellites.battle_courts_enabled() and str(definition.get("anchor_id", "")).begins_with("orchard_") and not str(definition.get("anchor_id", "")).begins_with("orchard_temple"):
		return false
	var anchor := _anchor(str(definition.anchor_id))
	var site := Catalog.site_for_anchor(encounter_id, anchor)
	if site.is_empty(): return false
	active = true
	active_id = encounter_id
	if is_instance_valid(atlas.encounters): atlas.encounters.active = true
	saved_position = world.player.position
	saved_yaw = world.yaw
	saved_pitch = world.pitch
	saved_distance = world.distance
	world.input_suspended = true
	world.player.velocity = Vector3.ZERO
	atlas.ui.hide()
	hidden_canvases.clear()
	for child in world.get_children():
		if child is CanvasLayer and child.visible:
			hidden_canvases.append(child)
			child.hide()
	if is_instance_valid(music): music.set_battle(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stage = Stage.instantiate()
	stage.embedded = true
	stage.manual_entrance = true
	stage.encounter_id = encounter_id
	stage.encounter_spec = Catalog.battle_spec(encounter_id)
	stage.battle_music_context = &"combat_main"
	stage.battle_music_boss = bool(definition.get("boss", false)) or str(definition.get("encounter_role", "")) in ["boss", "final"]
	stage.party = _party()
	stage.position = _point(site.center)
	stage.scale = Vector3.ONE * float(site.scale)
	stage.entry_origin = (saved_position-stage.position)/float(site.scale)
	stage.entry_player = world.player
	stage.entry_avatar = world.avatar
	stage.entry_camera = world.camera.global_transform.orthonormalized()
	stage.entry_fov = world.camera.fov
	world.add_child(stage)
	stage.actors[&"P0"].get_node("Body").external.scale = Vector3.ONE * world.explorer_scale / float(site.scale)
	# Use the player's configured learned deck, rather than the showcase preset.
	if is_instance_valid(atlas.loadout):
		if not stage.shell.engine.configure_deck(&"P0", atlas.loadout.counts()):
			push_error("Could not apply current deck for Star Orchard encounter " + encounter_id)
			_finish(-1)
			return false
	stage.shell.engine.state.unit_by_id(&"P0").deck.treasure_pile.clear()
	for index in site.enemies.size():
		var variant_id := str(site.enemies[index].get("variant_id", ""))
		if variant_id.is_empty(): continue
		var actor: Node3D = stage.actors.get(StringName("E" + str(index)))
		if is_instance_valid(actor):
			var body := actor.get_node("Body") as Node3D
			if body != null: Variants.apply(body, variant_id)
	stage.encounter_finished.connect(_finish)
	stage.show()
	stage.shell.set_music_paused(false)
	stage._enter_battle()
	_build_exit()
	encounter_started.emit(encounter_id)
	return true

func _party() -> Array[StringName]:
	var names: Dictionary = {
		"fire": &"fire_student", "ice": &"ice_guardian", "storm": &"storm_duelist",
		"life": &"life_healer", "death": &"death_reaper", "myth": &"myth_scholar",
		"balance": &"balance_adept"
	}
	var lead: StringName = StringName(str(atlas.loadout.character())) if is_instance_valid(atlas.loadout) else StringName(names.get(str(atlas.current_school), &"life_healer"))
	var result: Array[StringName] = [lead]
	for candidate in [&"ice_guardian", &"life_healer", &"fire_student", &"storm_duelist"]:
		if not result.has(candidate) and result.size() < 4: result.append(candidate)
	return result

func _anchor(anchor_id: String) -> Dictionary:
	for entry in Satellites.resolved_anchors():
		if str(entry.get("id", "")) == anchor_id: return entry.duplicate(true)
	return {}

func _point(coords: Array) -> Vector3:
	return Vector3(float(coords[0]), float(coords[1]), float(coords[2]))

func _build_exit() -> void:
	exit_layer = CanvasLayer.new()
	exit_layer.layer = 30
	exit_layer.hide()
	add_child(exit_layer)
	var control := Control.new()
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	exit_layer.add_child(control)
	var button := Button.new()
	button.text = "退出战斗 · 返回锚点"
	control.add_child(button)
	button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	button.offset_left = -115
	button.offset_right = 115
	button.offset_top = 45
	button.offset_bottom = 85
	button.pressed.connect(func(): _finish(-1))
	stage.entrance_finished.connect(func():
		if is_instance_valid(exit_layer): exit_layer.show())

func _finish(winner_team: int) -> void:
	if not active: return
	var finished_id := active_id
	active = false
	active_id = ""
	if is_instance_valid(atlas) and is_instance_valid(atlas.encounters): atlas.encounters.active = false
	if is_instance_valid(stage):
		stage.hide()
		stage.queue_free()
	stage = null
	if is_instance_valid(exit_layer): exit_layer.queue_free()
	exit_layer = null
	if is_instance_valid(world):
		for canvas in hidden_canvases:
			if is_instance_valid(canvas): canvas.show()
		hidden_canvases.clear()
		world.player.position = saved_position
		world.player.velocity = Vector3.ZERO
		world.player.show()
		world.yaw = saved_yaw
		world.pitch = saved_pitch
		world.distance = saved_distance
		world.camera.current = true
		world.input_suspended = false
		if is_instance_valid(world.avatar): world.avatar.set_locomotion(false, 0, 0)
	if is_instance_valid(atlas): atlas.ui.show()
	if is_instance_valid(music): music.set_battle(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	encounter_finished.emit(finished_id, winner_team == 0)
