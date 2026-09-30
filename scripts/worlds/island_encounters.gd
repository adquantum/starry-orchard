extends Node
## World triggers are separate from the authoritative battle session.
var atlas: Node
var world: Node3D
var session: Node
var active := false
var site: Dictionary = {}
var site_entries: Array[Dictionary] = []
var cooldowns: Dictionary = {}
var saved_position := Vector3.ZERO
var hidden_canvases: Array[CanvasLayer] = []
var hidden_geometry: Array[GeometryInstance3D] = []
var music: Node
var trigger_tick := 0.0
var staged_site := -1
var low_memory_tick := 0.0
var low_memory_camp := -1

func _ready() -> void:
	session=preload("res://scripts/worlds/island_battle_session.gd").new()
	session.name="IslandSession"
	session.manager=self
	add_child(session)

func install(target: Node3D) -> void:
	world=target;site_entries.clear();site={};cooldowns.clear();music=null;low_memory_camp=-1;low_memory_tick=0.0
	for child in world.get_children():
		if child.get_script()==preload("res://scripts/fusion_3d/exploration_music.gd"):music=child
	var key: String=str(world.world_root).trim_suffix("/").get_file()
	if key not in ["frostroarisland_teen", "frostroarisland_expanded"]:return
	var definitions: Array=preload("res://scripts/server/frost_encounter_catalog.gd").all_sites()
	for definition in definitions:
		var root := Node3D.new();root.name="Encounter_"+str(definition.id);world.add_child(root)
		if bool(definition.get("pvp",false)):
			var sigil=preload("res://scripts/worlds/pvp_sigil.gd").new();sigil.name="PvpSigil";root.add_child(sigil);sigil.setup(definition)
		var roaming: Array[Node3D]=[]
		if not GraphicsSettings.is_low():
			for index in definition.enemies.size():
				var spec: Dictionary=definition.enemies[index]
				var monster := preload("res://scripts/fusion_3d/world_one_monster.gd").new()
				monster.model_id=str(spec.model);root.add_child(monster)
				monster.scale=Vector3.ONE*float(definition.scale)
				if monster.animation!=null:
					for clip in monster.animation.get_animation_list():
						if "anim_004_" in clip:
							monster.animation.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
							monster.animation.play(clip);monster.animation.speed_scale=0.65;break
				monster.position=roam_position(definition,index,0)
				var title := Label3D.new()
				title.text="%s %d · %s [%s]  %d HP\n建议%d人 · %s装备" % [str(definition.get("difficulty_label", "难度")), int(definition.get("difficulty_rank", 1)), str(spec.name), str(spec.get("role_label", "怪物")), int(spec.hp), int(definition.get("recommended_players", 1)), str(definition.get("recommended_equipment_tier", "t0")).to_upper()]
				title.position=Vector3(0,3.0,0);title.billboard=BaseMaterial3D.BILLBOARD_ENABLED;title.font_size=28;title.pixel_size=0.006;title.no_depth_test=false
				monster.add_child(title)
				roaming.append(monster)
		site_entries.append({"config":definition,"root":root,"monsters":roaming})
		await get_tree().process_frame
		world.destinations.append(point(definition.approach));world.destination_names.append(str(definition.name))
	if not definitions.is_empty():site=definitions[0]
	var guide:=preload("res://scripts/worlds/frost_journey_guide.gd").new()
	guide.name="FrostJourneyGuide";world.add_child(guide);guide.setup(self,definitions)
	session.send_profile()

static func point(value: Array) -> Vector3:return Vector3(value[0],value[1],value[2])
static func roam_position(config: Dictionary,index: int,seconds: float) -> Vector3:
	return preload("res://scripts/server/encounter_geometry.gd").roam_position(config,index,seconds)

static func grounded_roam_position(target_world: Node3D,config: Dictionary,index: int,seconds: float) -> Vector3:
	var result:=roam_position(config,index,seconds)
	# Model-backed ice is not part of the terrain heightfield. Keep its audited top
	# plane independent from the optional visual lift used by the battle board.
	result.y=float(config.get("roam_surface_y",point(config.center).y)) if bool(config.get("fixed_roam_height",false)) else target_world._height(result)
	return result

static func battle_origin(config: Dictionary) -> Vector3:
	var result:=point(config.center)
	result.y+=float(config.get("battle_height_offset",0.0))
	return result

func _process(delta: float) -> void:
	if not is_instance_valid(world) or not world.ready_world or atlas.busy:return
	if GraphicsSettings.is_low():
		low_memory_tick -= delta
		if low_memory_tick <= 0.0:
			low_memory_tick = 0.5
			_refresh_low_memory_camp()
	var seconds: float=session.world_seconds()
	for entry in site_entries:
		if not entry.root.visible:continue
		for index in entry.monsters.size():
			var monster: Node3D=entry.monsters[index]
			var next := grounded_roam_position(world,entry.config,index,seconds)
			monster.face_center(next+Vector3(-sin(seconds*0.13+float(entry.config.order)*0.7+index*TAU/maxi(1,entry.monsters.size())),0,cos(seconds*0.13+float(entry.config.order)*0.7+index*TAU/maxi(1,entry.monsters.size()))))
			monster.position=next
	trigger_tick+=delta
	if active or trigger_tick<0.16 or not session.authority() or session.encounter_busy:return
	trigger_tick=0
	var positions: Dictionary=session.player_positions()
	for index in site_entries.size():
		if float(cooldowns.get(index,0))>Time.get_ticks_msec()/1000.0:continue
		for peer in positions:
			if touches(index,positions[peer]):session.start_contact(index,int(peer));return

func touches(index: int,position: Vector3) -> bool:
	if index<0 or index>=site_entries.size():return false
	return preload("res://scripts/server/encounter_geometry.gd").in_arena(position,site_entries[index].config)
func can_start() -> bool:return false

func restore_roaming() -> void:
	# A dropped/rejected room connection must not leave server-busy encounter roots hidden.
	if active:return
	for entry in site_entries:
		if is_instance_valid(entry.root):entry.root.show()
	staged_site=-1

func begin_local(index: int,participating: bool) -> void:
	staged_site=index
	if not bool(site_entries[index].config.get("pvp",false)):site_entries[index].root.hide()
	if not participating:return
	if active:
		world.player.hide();return
	active=true;site=site_entries[index].config
	if GraphicsSettings.is_low():_refresh_low_memory_camp()
	saved_position=world.player.position
	world.input_suspended=true;world.player.velocity=Vector3.ZERO;world.player.hide()
	atlas.game_menu.close();atlas.wardrobe_panel.hide();atlas.ui.hide()
	hidden_canvases.clear()
	for child in world.get_children():
		if child is CanvasLayer and child.visible:hidden_canvases.append(child);child.hide()
	hidden_geometry.clear()
	for child in world.get_children():
		if not child is MultiMeshInstance3D or not child.visible:continue
		var bounds: AABB=child.global_transform*child.get_aabb()
		if bounds.size.y<6:continue
		var center:=point(site.center)
		var nearest:=Vector2(clampf(center.x,bounds.position.x,bounds.end.x),clampf(center.z,bounds.position.z,bounds.end.z))
		if nearest.distance_to(Vector2(center.x,center.z))<45:hidden_geometry.append(child);child.hide()
	if is_instance_valid(music):music.set_battle(true)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func finish_local(winner: int,exit_position: Variant=null) -> void:
	if staged_site>=0 and staged_site<site_entries.size():
		cooldowns[staged_site]=Time.get_ticks_msec()/1000.0+maxf(20.0,float(site_entries[staged_site].config.get("cooldown_seconds",20)))
		site_entries[staged_site].root.show()
		var idle: Node=site_entries[staged_site].root.get_node_or_null("PvpSigil/IdleBoard")
		if idle!=null:idle.show()
	if active and is_instance_valid(world):
		world.player.position=exit_position if exit_position is Vector3 else point(site.approach)
		world.player.velocity=Vector3.ZERO;world.player.show();world.camera.current=true
		world._refresh_collisions();world.input_suspended=false;atlas.ui.show()
		for layer in hidden_canvases:
			if is_instance_valid(layer):layer.show()
		for geometry in hidden_geometry:
			if is_instance_valid(geometry):geometry.show()
		if is_instance_valid(music):music.set_battle(false)
		atlas.game_menu.message.text="战斗胜利！继续探索下一处营地。" if winner==0 else "已返回安全位置，可调整卡组与助战再挑战。"
	active=false;staged_site=-1

# Keep encounter definitions/routing for every camp; only one nearby camp's
# decorative roaming actors is resident. Authoritative battles are unchanged.
func _refresh_low_memory_camp() -> void:
	var wanted := -1
	var nearest := 60.0
	if not active and not is_instance_valid(session.stage):
		for index in site_entries.size():
			var entry: Dictionary = site_entries[index]
			if not entry.root.visible or bool(entry.config.get("pvp",false)):continue
			var gap: float = world.player.position.distance_to(point(entry.config.center))
			if gap < nearest:nearest=gap;wanted=index
	if wanted == low_memory_camp:return
	for entry in site_entries:
		for monster in entry.monsters:
			if is_instance_valid(monster):monster.queue_free()
		entry.monsters.clear()
	low_memory_camp=wanted
	if wanted < 0:return
	var entry: Dictionary=site_entries[wanted]
	var definition: Dictionary=entry.config
	var root: Node3D=entry.root
	var roaming: Array[Node3D]=[]
	for index in definition.enemies.size():
		var spec: Dictionary=definition.enemies[index]
		var monster := preload("res://scripts/fusion_3d/world_one_monster.gd").new()
		monster.model_id=str(spec.model);root.add_child(monster)
		monster.scale=Vector3.ONE*float(definition.scale)
		if monster.animation!=null:
			for clip in monster.animation.get_animation_list():
				if "anim_004_" in clip:
					monster.animation.get_animation(clip).loop_mode=Animation.LOOP_LINEAR
					monster.animation.play(clip);monster.animation.speed_scale=0.65;break
		monster.position=grounded_roam_position(world,definition,index,session.world_seconds())
		var title := Label3D.new()
		title.text="%s %d · %s [%s]  %d HP\n建议%d人 · %s装备" % [str(definition.get("difficulty_label", "难度")), int(definition.get("difficulty_rank", 1)), str(spec.name), str(spec.get("role_label", "怪物")), int(spec.hp), int(definition.get("recommended_players", 1)), str(definition.get("recommended_equipment_tier", "t0")).to_upper()]
		title.position=Vector3(0,3.0,0);title.billboard=BaseMaterial3D.BILLBOARD_ENABLED;title.font_size=28;title.pixel_size=0.006;title.no_depth_test=false
		monster.add_child(title)
		roaming.append(monster)

	entry.monsters=roaming
	print("FRIEND_LOW_MEMORY_CAMP ",wanted," actors=",roaming.size())
