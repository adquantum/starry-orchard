extends Node3D
## World-one actors and equipment share the existing, completed orchard world.
## Declared battle heights are shared with the server and the visible court mesh.
const DATA_PATH := "res://resources/campaigns/star_orchard_world1_v2/map_anchors.json"
const ENCOUNTERS_PATH := "res://resources/campaigns/star_orchard_world1_v2/encounters.json"
const OrchardActor = preload("res://scripts/worlds/star_orchard_actor.gd")
const Variants = preload("res://scripts/worlds/star_orchard_variant_materials.gd")
const Textures = preload("res://scripts/worlds/orchard_main_terrain.gd")
const FLOOR_MASK := (1 << 18) | (1 << 19) | (1 << 21)
const MISSION_FLOOR := 1 << 21
const COURT_RIM_MAX_GRADE := 0.25 # A 1:4 grading transition for existing paving.
const COURT_RIM_MAX_RISE := 0.75
const COURT_SURFACE_CLEARANCE := 0.025
const SCHOOLS := ["fire", "ice", "storm", "life", "death", "myth", "balance"]
var atlas: Node
var world: Node3D
var data: Dictionary = {}
var story: Dictionary = {}
var warnings: PackedStringArray = []
var _resolved: Dictionary = {}
var _actors: Dictionary = {}
var _props: Dictionary = {}
var _encounters: Dictionary = {}
var _encounter_nodes: Dictionary = {}
var _courts: Dictionary = {}
var _progress: Dictionary = {}
var _school := "life"
var _terrain: Node3D
var _materials: Dictionary = {}
var _ready_placements := false
var _static_only := false
var _prepared_travel: Dictionary = {}

func setup(owner_atlas: Node, owner_world: Node3D, story_data: Dictionary, static_only: bool = false) -> bool:
	if _ready_placements:
		return true
	atlas = owner_atlas
	world = owner_world
	story = story_data
	_static_only = static_only
	if not is_instance_valid(world) or not world.is_inside_tree():
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		push_error("World-one placement data is missing")
		return false
	data = parsed
	name = "StarOrchardWorld1Placements"
	if get_parent() == null:
		world.add_child(self)
	top_level = true
	global_transform = Transform3D.IDENTITY
	_school = str(atlas.get("current_school")) if is_instance_valid(atlas) else "life"
	if not _school in SCHOOLS:
		_school = "life"
	_terrain = world.get_node_or_null("OrchardProceduralLandscape") as Node3D
	var encounter_data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ENCOUNTERS_PATH))
	if encounter_data is Dictionary:
		for entry in encounter_data.get("encounters", []):
			_encounters[str(entry.id)] = entry
	for id in data.battle_sites:
		if _static_only and str(id) == "harbor_market":continue
		if not _make_court(str(id), data.battle_sites[id]):
			warnings.append("No safe ground under battle court: " + str(id))
	for id in data.anchors:
		var spec: Dictionary = data.anchors[id]
		var at: Vector3 = _safe_position(_point(spec.position), float(spec.get("search_radius", 7.0)), false)
		if at.is_finite():
			_resolved[str(id)] = at
		else:
			warnings.append("No floor for anchor: " + str(id))
	for id in data.actors:
		_make_actor(str(id), data.actors[id])
	if not _static_only:
		for id in data.targets:
			var target: Dictionary = data.targets[id]
			if bool(target.get("physical", false)) and str(target.get("npc_id", "")).is_empty() and str(target.kind) != "battle":
				_make_target(str(id), target)
		# Regional descriptions are physical signboards, never trigger portals.
		for pair in [["F01.entry", "露芽果坡"], ["F02.entry", "潮根堤岸"], ["F03.entry", "风铃云圃"], ["D01.entry_staging", "旧根回廊 · 维修根庭"]]:
			_make_region_sign(str(pair[0]), str(pair[1]))
	_ready_placements = true
	if not _static_only:set_story_state({})
	else:world.set_meta("orchard_static_npcs", _actors.size())
	set_meta("placement_warnings", warnings)
	if not warnings.is_empty():
		push_warning("Orchard world-one placements: " + "; ".join(warnings))
	return anchor("H01.harbor_arrival").is_finite() and (_static_only or _courts.size() == data.battle_sites.size())

func anchor(id: String) -> Vector3:
	id = id.replace("{school}", _school)
	if id == "H01.mentor_own" and _actors.has("N11." + _school):
		return (_actors["N11." + _school] as Node3D).global_position
	if id == "N11":
		id = "N11." + _school
	if _actors.has(id) and is_instance_valid(_actors[id]):
		return (_actors[id] as Node3D).global_position
	if _resolved.has(id):
		return _resolved[id]
	var target: Dictionary = data.get("targets", {}).get(id, {})
	var npc_id: String = str(target.get("npc_id", ""))
	if not npc_id.is_empty() and not bool(target.get("remote", false)):
		return anchor(npc_id)
	return Vector3.INF

func label_for(id: String) -> String:
	if id == "N11":
		id = "N11." + _school
	if data.get("actors", {}).has(id):
		return str(data.actors[id].label)
	var target: Dictionary = data.get("targets", {}).get(id, {})
	if not target.is_empty():
		return str(target.get("label", id))
	return str(data.get("anchors", {}).get(id, {}).get("label", id))

func interactable_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for id in data.get("targets", {}):
		var target: Dictionary = data.targets[id]
		if bool(target.get("physical", false)) and anchor(str(id)).is_finite():
			result.append(str(id).replace("{school}", _school))
	return result

func battle_site(encounter_id: String) -> Dictionary:
	encounter_id = encounter_id.replace("{school}", _school)
	var site_id: String = str(data.get("encounter_sites", {}).get(encounter_id, encounter_id))
	if not _courts.has(site_id):
		return {}
	var raw: Dictionary = data.battle_sites[site_id]
	var result: Dictionary = raw.duplicate(true)
	result["id"] = site_id
	result["center"] = _point(raw.center)
	var approach: Vector3 = anchor(encounter_id)
	result["approach"] = approach if approach.is_finite() else _point(raw.approach)
	return result

func surface_height(at: Vector3) -> float:
	if not _ready_placements or not is_instance_valid(world) or not world.is_inside_tree():
		return -INF
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.2, at - Vector3.UP * 24.0, MISSION_FLOOR)
	query.hit_back_faces = false
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or float(hit.normal.y) < 0.68:
		return -INF
	return float(hit.position.y)

func prepare_travel(anchor_id: String) -> bool:
	if not _ready_placements or not is_instance_valid(world):
		return false
	var player: CharacterBody3D = world.get("player") as CharacterBody3D
	var point: Vector3 = anchor(anchor_id)
	if player == null or not point.is_finite():
		return false
	point = _safe_position(point, 5.0, true)
	if not point.is_finite():
		return false
	_prepared_travel = {"anchor": anchor_id, "point": point,
		"expires_at": Time.get_ticks_msec() + 15000, "world_id": world.get_instance_id()}
	return true

func travel_to(anchor_id: String) -> bool:
	if not _ready_placements or not is_instance_valid(world):
		return false
	var player: CharacterBody3D = world.get("player") as CharacterBody3D
	if player == null:
		return false
	var prepared: bool = str(_prepared_travel.get("anchor", "")) == anchor_id
	prepared = prepared and int(_prepared_travel.get("expires_at", 0)) >= Time.get_ticks_msec()
	prepared = prepared and int(_prepared_travel.get("world_id", 0)) == world.get_instance_id()
	if not prepared and not prepare_travel(anchor_id):
		return false
	var point: Vector3 = _prepared_travel.point
	_prepared_travel.clear()
	player.velocity = Vector3.ZERO
	player.global_position = point + Vector3.UP * 0.16
	player.reset_physics_interpolation()
	var flight: Node = world.get("flight") as Node
	if flight != null and flight.has_method("land"):
		flight.call("land")
	return true

func set_story_state(progress: Dictionary) -> void:
	_progress = progress.duplicate(true)
	var active: Array[Dictionary] = _active_objectives()
	var destinations: Dictionary = {}
	for npc in data.get("actors", {}):
		destinations[str(npc)] = str(data.actors[npc].home)
	# Keep the latest conversation point through this quest's preparation or
	# inspection steps. A tracked side quest owns its participants until finished.
	for quest in _ordered_quests():
		var qid: String = str(quest.id)
		if not bool(_progress.get("accepted", {}).get(qid, false)) or qid in _progress.get("completed", []):
			continue
		var counts: Dictionary = _progress.get("objectives", {}).get(qid, {})
		var phases: Dictionary = {}
		var chosen_now: Dictionary = {}
		for objective in quest.get("objectives", []):
			if str(objective.get("kind", "")) != "talk" or bool(objective.get("remote", false)):
				continue
			var npc: String = str(objective.get("npc_id", ""))
			if npc == "N11":
				npc = "N11." + _school
			if npc.is_empty():
				continue
			var complete: bool = int(counts.get(str(objective.id), 0)) >= int(objective.get("count", 1))
			if complete and not chosen_now.has(npc):
				phases[npc] = str(objective.get("phase_anchor", ""))
			elif not complete and objective in active and not chosen_now.has(npc):
				phases[npc] = str(objective.get("phase_anchor", ""))
				chosen_now[npc] = true
		for npc in phases:
			if not bool(destinations.get("chosen:" + str(npc), false)):
				destinations[npc] = phases[npc]
				destinations["chosen:" + str(npc)] = true
	for id in _actors:
		var destination: String = str(destinations.get(id, ""))
		# The public mentor anchor follows the selected actor for prepare/talk;
		# movement itself always starts from the immutable authored hub.
		var at: Vector3 = _resolved.get(destination, Vector3.INF)
		if not at.is_finite():
			continue
		if str(id).begins_with("N11.") and destination == "H01.mentor_own":
			var index: int = SCHOOLS.find(str(id).get_slice(".", 1))
			at += Vector3((float(index) - 3.0) * 8.0, 0.0, -5.0 - absf(float(index) - 3.0) * 0.4)
		elif str(id) == "N02":
			at += Vector3(3.5, 0.0, 2.0)
		var grounded: Vector3 = _safe_position(_outside_courts(at), 7.0, true)
		if grounded.is_finite():
			(_actors[id] as Node3D).global_position = grounded
		if str(id) == "N10":
			(_actors[id] as Node3D).visible = bool(_progress.get("accepted", {}).get("SO1_M28", false)) or _flag("so1_win_e24")
		elif str(id) == "N12":
			(_actors[id] as Node3D).visible = bool(_progress.get("accepted", {}).get("SO1_M29", false)) or _flag("so1_world_restored")
	var active_battles: Dictionary = {}
	var site_previews: Dictionary = {}
	for objective in active:
		if str(objective.get("kind", "")) == "battle":
			var encounter: String = str(objective.get("target", "")).replace("{school}", _school)
			active_battles[encounter] = true
			if not _encounter_nodes.has(encounter):
				_make_encounter_actor(encounter)
			var site_id: String = str(data.encounter_sites.get(encounter, ""))
			if not site_previews.has(site_id):
				site_previews[site_id] = []
			if not encounter in site_previews[site_id]:
				site_previews[site_id].append(encounter)
	for id in _encounter_nodes:
		(_encounter_nodes[id] as Node3D).visible = active_battles.has(id)
	for site_id in site_previews:
		var ids: Array = site_previews[site_id]
		for index in range(ids.size()):
			if not _encounter_nodes.has(ids[index]):
				continue
			var center: Vector3 = _point(data.battle_sites[site_id].center)
			var offset: float = (float(index) - float(ids.size() - 1) * 0.5) * 6.0
			(_encounter_nodes[ids[index]] as Node3D).global_position = center + Vector3(offset, 0.0, 0.0)
	for id in _props:
		var node: Node3D = _props[id]
		var complete: bool = _target_done(str(id))
		node.set_meta("investigated", complete)
		var label: Label3D = node.get_node_or_null("QuestLabel") as Label3D
		if label != null:
			label.modulate = Color("9fb9a0") if complete else Color("f5dfb0")
		var wheel: Node3D = node.get_node_or_null("ValveWheel") as Node3D
		if wheel != null:
			wheel.rotation.z = PI * 0.5 if complete else 0.0
		var crystal: MeshInstance3D = node.get_node_or_null("FlowCrystal") as MeshInstance3D
		if crystal != null:
			crystal.material_override = _plain_material("restored" if complete or _flag("so1_world_restored") else "crystal")
	set_meta("world_restored", _flag("so1_world_restored"))

func _ordered_quests() -> Array:
	var ordered: Array = []
	var side_id: String = str(_progress.get("tracked_side", ""))
	for quest in story.get("side_quests", []):
		if str(quest.id) == side_id:
			ordered.append(quest)
	ordered.append_array(story.get("main_quests", []))
	return ordered

func _active_objectives() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var accepted: Dictionary = _progress.get("accepted", {})
	for quest in _ordered_quests():
		var qid: String = str(quest.id)
		if not bool(accepted.get(qid, false)) or qid in _progress.get("completed", []):
			continue
		var counts: Dictionary = _progress.get("objectives", {}).get(qid, {})
		for item in quest.get("objectives", []):
			if int(counts.get(str(item.id), 0)) >= int(item.get("count", 1)):
				continue
			var available: bool = true
			for needed in item.get("requires_objectives", []):
				if int(counts.get(str(needed), 0)) < 1:
					available = false
			if available:
				result.append(item)
	return result

func _target_done(id: String) -> bool:
	for quest in story.get("main_quests", []) + story.get("side_quests", []):
		var counts: Dictionary = _progress.get("objectives", {}).get(str(quest.id), {})
		for objective in quest.get("objectives", []):
			if str(objective.get("target", "")) == id and int(counts.get(str(objective.id), 0)) >= int(objective.get("count", 1)):
				return true
	return false

func _flag(id: String) -> bool:
	return bool(_progress.get("flags", {}).get(id, false))

func _ground_at(hint: Vector3, include_courts: bool = true) -> Vector3:
	if not hint.is_finite() or hint.z < -830.0:
		return Vector3.INF
	var best: float = -INF
	if include_courts:
		for id in _courts:
			var spec: Dictionary = data.battle_sites[id]
			var center: Vector3 = _point(spec.center)
			if Vector2(hint.x - center.x, hint.z - center.z).length() < float(spec.radius) - 0.05:
				best = center.y
	var query := PhysicsRayQueryParameters3D.create(hint + Vector3.UP * 12.0, hint - Vector3.UP * 16.0, FLOOR_MASK)
	query.hit_back_faces = false
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and float(hit.normal.y) >= 0.68 and absf(float(hit.position.y) - hint.y) <= 12.0:
		best = maxf(best, float(hit.position.y))
	if is_instance_valid(_terrain) and _terrain.has_method("height_at"):
		var height: float = float(_terrain.call("height_at", Vector2(hint.x, hint.z)))
		if is_finite(height) and height > 222.5 and absf(height - hint.y) <= 12.0:
			var hx: float = float(_terrain.call("height_at", Vector2(hint.x + 1.0, hint.z)))
			var hz: float = float(_terrain.call("height_at", Vector2(hint.x, hint.z + 1.0)))
			if absf(hx - height) < 0.7 and absf(hz - height) < 0.7:
				best = maxf(best, height)
	return Vector3(hint.x, best, hint.z) if is_finite(best) else Vector3.INF

func _safe_position(hint: Vector3, search_radius: float = 7.0, check_body: bool = true) -> Vector3:
	if not hint.is_finite():
		return Vector3.INF
	for radius in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 12.0]:
		if float(radius) > search_radius:
			continue
		for i in (1 if float(radius) == 0.0 else 8):
			var angle: float = TAU * float(i) / 8.0
			var at: Vector3 = _ground_at(hint + Vector3(cos(angle) * float(radius), 0.0, sin(angle) * float(radius)))
			if at.is_finite() and (not check_body or _body_fits(at)):
				return at
	return Vector3.INF

func _body_fits(at: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.72
	shape.height = 3.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * 2.05)
	query.collision_mask = 1
	query.collide_with_areas = false
	query.margin = 0.02
	var player: CharacterBody3D = world.get("player") as CharacterBody3D
	if player != null:
		query.exclude = [player.get_rid()]
	return world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _outside_courts(at: Vector3) -> Vector3:
	for id in _courts:
		var site: Dictionary = data.battle_sites[id]
		var center: Vector3 = _point(site.center)
		var delta := Vector2(at.x - center.x, at.z - center.z)
		if delta.length() < float(site.radius) + 3.0:
			if delta.length_squared() < 0.01:
				delta = Vector2.DOWN
			delta = delta.normalized() * (float(site.outer_radius) + 3.0)
			at.x = center.x + delta.x
			at.z = center.z + delta.y
	return at

func _make_actor(id: String, spec: Dictionary) -> void:
	var home: Vector3 = _resolved.get(str(spec.home), Vector3.INF)
	if not home.is_finite():
		warnings.append("Actor has no ground anchor: " + id)
		return
	var point: Vector3 = _safe_position(_outside_courts(home), 7.0, true)
	if not point.is_finite():
		point = _safe_position(_outside_courts(home), 12.0, true)
	if not point.is_finite():
		warnings.append("Actor standing space blocked: " + id)
		return
	var holder: Node3D = OrchardActor.place(self, str(spec.model_id), point, float(spec.extent))
	if holder == null:
		warnings.append("Actor model missing: " + str(spec.model_id))
		return
	holder.name = id.replace(".", "_")
	holder.set_meta("world1_npc", str(spec.npc_id))
	var visual_size: Vector3 = holder.get_meta("normalized_size", Vector3(0, float(spec.extent), 0))
	_label(holder, str(spec.label), visual_size.y + 0.7, true)
	_actors[id] = holder

func _make_target(id: String, target: Dictionary) -> void:
	var at: Vector3 = anchor(id)
	if not at.is_finite():
		return
	at = _safe_position(_outside_courts(at), 7.0, true)
	if not at.is_finite():
		at = _safe_position(_outside_courts(anchor(id)), 12.0, true)
	if not at.is_finite():
		warnings.append("Equipment has no standing floor: " + id)
		return
	_resolved[id] = at
	var holder := Node3D.new()
	holder.name = "Target_" + id.replace(".", "_")
	add_child(holder)
	holder.global_position = at
	holder.set_meta("world1_target", id)
	var kind: String = str(target.get("prop_kind", "sample"))
	if kind == "valve":
		_make_valve(holder)
	elif kind == "route_marker":
		_asset(holder, str(data.assets.sign), 3.4)
	elif kind == "record":
		_asset(holder, str(data.assets.record), 2.4)
	elif id.contains("resonator") or id.contains("signal") or id.contains("synchronize"):
		_make_crystal(holder)
	elif id.contains("seedling") or id.contains("healthy_fruit") or id.contains("reversed_fruit"):
		_asset(holder, str(data.assets.sapling), 3.2)
	elif kind == "station":
		_asset(holder, str(data.assets.table), 2.3)
		_sample_tray(holder, 1.7)
	elif id.contains("bell") or id.contains("gauge") or id.contains("boundary"):
		_make_gauge(holder)
	else:
		_asset(holder, str(data.assets.crate), 1.8)
		_sample_tray(holder, 1.65)
	_label(holder, str(target.label), 3.6, false)
	_props[id] = holder

func _make_region_sign(id: String, title: String) -> void:
	var at: Vector3 = anchor(id)
	if not at.is_finite():
		return
	var holder := Node3D.new()
	holder.name = "Region_" + id.get_slice(".", 0)
	add_child(holder)
	holder.global_position = at
	_asset(holder, str(data.assets.sign), 4.0)
	_label(holder, title, 4.4, false)

func _make_encounter_actor(id: String) -> void:
	if not _encounters.has(id):
		return
	var site: Dictionary = battle_site(id)
	if site.is_empty():
		return
	var encounter: Dictionary = _encounters[id]
	var enemies: Array = encounter.get("enemies", [])
	if enemies.is_empty():
		return
	var enemy: Dictionary = enemies[0]
	var at: Vector3 = site.center
	var holder: Node3D = OrchardActor.place(self, str(enemy.get("model", "")), at, 4.6)
	if holder == null:
		warnings.append("Encounter preview model missing: " + id)
		return
	holder.name = "Encounter_" + id
	var variant_id: String = str(enemy.get("variant_id", ""))
	if not variant_id.is_empty() and not bool(enemy.get("no_variant", false)):
		Variants.apply(holder, variant_id)
	holder.set_meta("world1_encounter", id)
	_label(holder, str(encounter.get("name", id)), 5.5, true)
	_encounter_nodes[id] = holder

func _make_court(id: String, spec: Dictionary) -> bool:
	var center: Vector3 = _point(spec.center)
	var radius: float = float(spec.radius)
	var outer_radius: float = float(spec.outer_radius)
	var rim_blend_width := minf(outer_radius - radius, radius * 0.2)
	var core_radius := radius - rim_blend_width
	var rim_rise_limit := minf(COURT_RIM_MAX_RISE, maxf(0.12, rim_blend_width * COURT_RIM_MAX_GRADE))
	var core := PackedVector3Array()
	var actual_rim_rise := 0.0
	var outer: PackedVector3Array = PackedVector3Array()
	var inner: PackedVector3Array = PackedVector3Array()
	var foundation_base := PackedVector3Array()
	# This server-authored harbor court straddles an existing inlet. Its
	# physical quay stays inside the declared footprint and retains the
	# authoritative battle center, height, radius and approach unchanged.
	var shore_court := id == "harbor_supply"
	if shore_court and not _ground_at(center, false).is_finite():
		return false
	for i in 48:
		var angle: float = TAU * float(i) / 48.0
		var offset := Vector3(cos(angle), 0.0, sin(angle))
		var edge: Vector3 = _ground_at(center + offset * outer_radius, false)
		var sample: Vector3 = _ground_at(center + offset * (radius - 0.2), false)
		if sample.is_finite() and sample.y + COURT_SURFACE_CLEARANCE > center.y + rim_rise_limit:
			return false
		if not shore_court and (not edge.is_finite() or not sample.is_finite()):
			return false
		if shore_court:
			var base := center + offset * outer_radius
			base.y = edge.y - 2.0 if edge.is_finite() else 219.5
			foundation_base.append(base)
			if not edge.is_finite():
				edge = center + offset * outer_radius - Vector3.UP * 0.025
		outer.append(edge + Vector3.UP * 0.025)
		var rim := center + offset * radius
		if sample.is_finite():
			# Existing paving and its bevel may reach the court edge. Grade
			# that margin within the same bounded rule for every court;
			# retain the authoritative center and reject larger obstructions.
			rim.y = maxf(rim.y, sample.y + COURT_SURFACE_CLEARANCE)
		inner.append(rim)
		core.append(center + offset * core_radius)
		actual_rim_rise = maxf(actual_rim_rise, rim.y - center.y)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 48:
		var next: int = (i + 1) % 48
		# Keep the complete combat board flat at the server floor. Only
		# the outside margin grades up to the corrected town paving.
		_triangle(surface, center, core[next], core[i])
		_triangle(surface, core[i], core[next], inner[next])
		_triangle(surface, core[i], inner[next], inner[i])
		_triangle(surface, inner[i], inner[next], outer[next])
		_triangle(surface, inner[i], outer[next], outer[i])
	var mesh: ArrayMesh = surface.commit()
	var visual := MeshInstance3D.new()
	visual.name = "Court_" + id
	visual.set_meta("court_flat_core_radius", core_radius)
	visual.set_meta("court_actual_rim_rise", actual_rim_rise)
	visual.mesh = mesh
	visual.material_override = _court_material(str(spec.get("material", "soil")), center, radius)
	add_child(visual)
	var body := StaticBody3D.new()
	body.name = "CourtGround_" + id
	body.collision_layer = 1 | MISSION_FLOOR
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
	if shore_court:
		_add_court_foundation(id, center, outer, foundation_base)
	_courts[id] = visual
	return true

func _add_court_foundation(id: String, center: Vector3, edge: PackedVector3Array, bottom: PackedVector3Array) -> void:
	# The existing court is the top cap. These outward sides and downward
	# bottom close its exposed inlet arc; the land-side portions are buried.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bottom_center := Vector3(center.x, 219.5, center.z)
	for i in edge.size():
		var next := (i + 1) % edge.size()
		var normal := Vector3(edge[i].x + edge[next].x - center.x * 2.0, 0.0, edge[i].z + edge[next].z - center.z * 2.0).normalized()
		_foundation_triangle(surface, edge[i], edge[next], bottom[next], normal)
		_foundation_triangle(surface, edge[i], bottom[next], bottom[i], normal)
		_foundation_triangle(surface, bottom_center, bottom[i], bottom[next], Vector3.DOWN)
	var mesh := surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_texture = Textures.asset_texture("res://assets/worlds/star_orchard/coastal_art_v2/cliff_imagegen.png")
	material.albedo_color = Color("c8c5ba")
	material.roughness = 0.98
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.12
	var visual := MeshInstance3D.new()
	visual.name = "CourtQuayFoundation_" + id
	visual.mesh = mesh
	visual.material_override = material
	add_child(visual)
	var body := StaticBody3D.new()
	body.name = "CourtQuaySolid_" + id
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	add_child(body)
	visual.set_meta("closed_with_court_top", true)
	visual.set_meta("source_battle_site", id)

func _foundation_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	if (c - a).cross(b - a).dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
	var normal := (c - a).cross(b - a).normalized()
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.x, point.y) * 0.12)
		surface.add_vertex(point)

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot treats clockwise winding as the front. Renderer, trimesh collider
	# and upward-only floor rays must all see the same upward face.
	if (c - a).cross(b - a).y < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_uv(Vector2(point.x, point.z) * 0.11)
		surface.add_vertex(point)

func _court_material(kind: String, center: Vector3, radius: float) -> Material:
	if kind == "soil":
		var meadow := ShaderMaterial.new()
		meadow.shader = preload("res://assets/worlds/star_orchard/procedural_main_v1/court_meadow_wear.gdshader")
		meadow.set_shader_parameter("meadow", Textures.texture("orchard_meadow_generated.png"))
		meadow.set_shader_parameter("soil", Textures.texture("orchard_soil_generated.png"))
		meadow.set_shader_parameter("court_center", Vector2(center.x, center.z))
		meadow.set_shader_parameter("court_radius", radius)
		return meadow
	var key: String = "court_" + kind
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_texture = Textures.texture("orchard_stone_generated.png")
	material.albedo_color = Color("bdc2ae")
	material.roughness = 0.98
	_materials[key] = material
	return material
func _asset(parent: Node3D, path: String, extent: float) -> Node3D:
	var scene: PackedScene = load(path) as PackedScene
	if scene == null:
		warnings.append("Prop model missing: " + path)
		return null
	var holder := Node3D.new()
	parent.add_child(holder)
	var node: Node3D = scene.instantiate() as Node3D
	if node == null:
		holder.queue_free()
		return null
	holder.add_child(node)
	var bounds := AABB()
	var found: bool = false
	for item in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := item as MeshInstance3D
		var box: AABB = holder.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if not found else bounds.merge(box)
		found = true
	if found:
		var factor: float = extent / maxf(bounds.size.y, 0.1)
		factor = minf(factor, extent * 1.8 / maxf(bounds.size.x, bounds.size.z))
		node.scale *= factor
		node.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	for item in node.find_children("*", "CollisionObject3D", true, false):
		item.collision_layer = 0
		item.collision_mask = 0
	return holder

func _label(parent: Node3D, title: String, height: float, actor: bool) -> void:
	var label := Label3D.new()
	label.name = "QuestLabel"
	label.text = title
	label.position.y = height
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 30 if actor else 24
	label.pixel_size = 0.023
	label.outline_size = 7
	label.modulate = Color("f5dfb0")
	label.no_depth_test = false
	label.visibility_range_end = 65.0 if actor else 35.0
	parent.add_child(label)

func _plain_material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var material := StandardMaterial3D.new()
	material.albedo_color = {"wood": Color("795738"), "metal": Color("9a8966"), "stone": Color("aaa794"), "crystal": Color("608db1"), "restored": Color("83b28b"), "paper": Color("e3d6a8"), "fruit": Color("b6673c")}.get(kind, Color.WHITE)
	material.roughness = 0.84
	_materials[kind] = material
	return material

func _part(parent: Node3D, mesh: Mesh, at: Vector3, material: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.material_override = _plain_material(material)
	parent.add_child(node)
	return node

func _make_valve(parent: Node3D) -> void:
	var plinth := CylinderMesh.new()
	plinth.top_radius = 1.05
	plinth.bottom_radius = 1.35
	plinth.height = 0.65
	plinth.radial_segments = 10
	_part(parent, plinth, Vector3(0, 0.325, 0), "stone")
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.22
	pipe.bottom_radius = 0.3
	pipe.height = 1.7
	pipe.radial_segments = 8
	_part(parent, pipe, Vector3(0, 1.25, 0), "metal")
	var wheel := Node3D.new()
	wheel.name = "ValveWheel"
	wheel.position = Vector3(0, 2.1, 0)
	parent.add_child(wheel)
	for i in 8:
		var angle: float = float(i) * TAU / 8.0
		var beam := BoxMesh.new()
		beam.size = Vector3(0.16, 1.18, 0.16)
		var spoke: MeshInstance3D = _part(wheel, beam, Vector3.ZERO, "metal")
		spoke.rotation.z = angle
	var ring := TorusMesh.new()
	ring.inner_radius = 0.74
	ring.outer_radius = 0.9
	ring.rings = 16
	ring.ring_segments = 6
	var ring_node: MeshInstance3D = _part(wheel, ring, Vector3.ZERO, "metal")
	ring_node.rotation.x = PI * 0.5

func _make_crystal(parent: Node3D) -> void:
	var base := CylinderMesh.new()
	base.top_radius = 0.85
	base.bottom_radius = 1.1
	base.height = 0.55
	base.radial_segments = 8
	_part(parent, base, Vector3(0, 0.275, 0), "stone")
	var crystal := PrismMesh.new()
	crystal.size = Vector3(1.1, 2.3, 1.1)
	var node: MeshInstance3D = _part(parent, crystal, Vector3(0, 1.65, 0), "crystal")
	node.name = "FlowCrystal"
	node.rotation.y = PI * 0.25

func _make_gauge(parent: Node3D) -> void:
	var post := BoxMesh.new()
	post.size = Vector3(0.32, 2.7, 0.32)
	_part(parent, post, Vector3(0, 1.35, 0), "wood")
	for i in 5:
		var mark := BoxMesh.new()
		mark.size = Vector3(0.75 if i % 2 == 0 else 0.5, 0.06, 0.14)
		_part(parent, mark, Vector3(0.15, 0.55 + float(i) * 0.4, 0.2), "paper")

func _sample_tray(parent: Node3D, height: float) -> void:
	var tray := BoxMesh.new()
	tray.size = Vector3(1.25, 0.12, 0.8)
	_part(parent, tray, Vector3(0, height, 0), "paper")
	for i in 3:
		var fruit := SphereMesh.new()
		fruit.radius = 0.18
		fruit.height = 0.3
		fruit.radial_segments = 7
		fruit.rings = 3
		_part(parent, fruit, Vector3(float(i - 1) * 0.35, height + 0.17, 0), "fruit")

func _point(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2])) if value.size() >= 3 else Vector3.INF

