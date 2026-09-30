extends RefCounted
## Explicit quest-side scenery. Detached source scenes contribute only visual meshes.
var data_path: String = "res://resources/fusion_3d/orchard_quest_scenery_v1.json"
const ANCHORS := "res://resources/campaigns/star_orchard_world1_v2/map_anchors.json"
const SAMPLE := "res://resources/fusion_3d/orchard_forest_sample_20260926.json"
const CELL := 96.0
var _landscape: Node3D
var _forest: RefCounted
var _recipes: Dictionary = {}
var _batches: Dictionary = {}
var _routes: Array[Dictionary] = []
var _circles: Array[Dictionary] = []
var _placed: Array[Dictionary] = []
var _stats: Dictionary = {}
var _sample_bounds: Dictionary = {}
var _styler: RefCounted

func install(world: Node3D, landscape: Node3D, forest: RefCounted = null) -> void:
	if world.has_meta("orchard_quest_scenery") or world.has_node("OrchardQuestScenery"):
		return
	_landscape = landscape
	_forest = forest
	_styler = load("res://scripts/worlds/orchard_cloud_prop_style.gd").new()
	_recipes.clear()
	_batches.clear()
	_routes.clear()
	_circles.clear()
	_placed.clear()
	_stats = {"stage": "quest_scenery_v1", "requested": 0, "placed": 0, "shared_batches": 0, "decorative_colliders": 0, "accepted": [], "rejected": [], "rejection_counts": {}, "groups": {}, "terrain_sample_count": 0, "max_ground_span": 0.0, "max_fit_error": 0.0, "min_route_clearance": INF, "min_quest_clearance": INF}
	var data := _json(data_path)
	if data.is_empty() or not landscape.has_method("height_at"):
		_stats["error"] = "missing_data_or_terrain"
		world.set_meta("orchard_quest_scenery", _stats)
		return
	_cache_clearances(landscape.get("settings"))
	var sample: Dictionary = _json(SAMPLE)
	_sample_bounds = sample.get("replace_bounds", {})
	var assets: Dictionary = data.get("assets", {})
	var disabled_legacy_items := 0
	for group in data.get("groups", []):
		disabled_legacy_items += group.get("items", []).size()
	_stats["disabled_legacy_items"] = disabled_legacy_items
	_stats["disabled_legacy_groups"] = data.get("groups", []).size()
	for group in sample.get("groups", []):
		var group_id := str(group.get("id", "sample_decor"))
		_stats.groups[group_id] = {"label": group.get("label", group_id), "quest_ids": [], "placed": 0}
		for item in group.get("items", []):
			_stats.requested += 1
			_place(world, group_id, item, assets)
	_build_batches(world)
	_stats.shared_batches = _batches.size()
	_stats["protected_route_segments"] = _routes.size()
	_stats["protected_quest_zones"] = _circles.size()
	world.set_meta("orchard_quest_scenery", _stats)

func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

func _inside_sample(at: Vector2) -> bool:
	if _sample_bounds.is_empty():return false
	var low: Array = _sample_bounds.get("min", [])
	var high: Array = _sample_bounds.get("max", [])
	return low.size() == 2 and high.size() == 2 and at.x >= float(low[0]) and at.x <= float(high[0]) and at.y >= float(low[1]) and at.y <= float(high[1])

func _place(world: Node3D, group: String, item: Dictionary, assets: Dictionary) -> void:
	var key := str(item.get("asset", ""))
	var record: Dictionary = {"group": group, "asset": key, "at": item.get("at", [])}
	if not assets.has(key) or record.at.size() < 2:
		_reject(record, "invalid_asset_or_position")
		return
	if not group.begins_with("sample_") and _inside_sample(_xz(record.at)):
		_stats["replaced_old_items"] = int(_stats.get("replaced_old_items", 0)) + 1
		return
	var asset: Dictionary = assets[key]
	if not _recipes.has(key):
		_recipes[key] = _load_recipe(world, asset)
	var recipe: Dictionary = _recipes[key]
	if recipe.is_empty():
		_reject(record, "empty_asset")
		return
	var bounds: AABB = recipe.bounds
	var height := float(item.get("height", asset.get("height", 5.0)))
	var factor := height / maxf(bounds.size.y, 0.001)
	var half := Vector2(bounds.size.x, bounds.size.z) * factor * 0.5
	var radius := maxf(half.length(), 0.3)
	var at := _xz(record.at)
	var yaw := deg_to_rad(float(item.get("yaw", 0.0)))
	var is_tree := asset.has("tree_school") or str(asset.get("kind", "")) == "tree"
	var align := bool(item.get("align_to_ground", false)) and not is_tree and height <= 4.0 and str(asset.get("kind", "")) in ["prop", "stone"]
	var rotation := Basis(Vector3.UP, yaw)
	var slope := 0.0
	if align:
		var gradient := Vector2((_height(at + Vector2.RIGHT) - _height(at - Vector2.RIGHT)) * 0.5, (_height(at + Vector2.DOWN) - _height(at - Vector2.DOWN)) * 0.5)
		var normal := Vector3(-gradient.x, 1.0, -gradient.y).normalized()
		var forward := (rotation.z - normal * rotation.z.dot(normal)).normalized()
		rotation = Basis(normal.cross(forward).normalized(), normal, forward)
		slope = gradient.length()
		# Include the tilted top, so a leaning edge cannot enter reserved walkways.
		var tilted: AABB = Transform3D(rotation, Vector3.ZERO) * AABB(Vector3(-half.x, 0, -half.y), Vector3(half.x * 2.0, height, half.y * 2.0))
		radius = Vector2(maxf(absf(tilted.position.x), absf(tilted.end.x)), maxf(absf(tilted.position.z), absf(tilted.end.z))).length()
	record["align_to_ground"] = align
	record["ground_normal"] = [rotation.y.x, rotation.y.y, rotation.y.z]
	var spacing := clampf(height * 0.14, 1.6, 3.6) if is_tree else radius
	var clear := _clearance(at, radius, height)
	record["height"] = height
	record["footprint"] = radius
	record["route_clearance"] = clear.x
	record["quest_clearance"] = clear.y
	if clear.x < 0.0 or clear.y < 0.0:
		_reject(record, "route_clearance" if clear.x < 0.0 else "quest_clearance")
		return
	if _forest != null and _forest.has_method("_clear") and not bool(_forest.call("_clear", at, radius, spacing, is_tree)):
		_reject(record, "existing_forest_or_city")
		return
	for previous in _placed:
		# Keep canopies away from authored equipment, while allowing groundcover
		# and neighbouring trees to share a natural canopy edge.
		var equipment_pair: bool = (is_tree and bool(previous.get("prop", false))) or (str(asset.get("kind", "")) == "prop" and bool(previous.get("tree", false)))
		var required_space: float = radius + float(previous.get("footprint", previous.radius)) + 1.0 if equipment_pair else spacing + float(previous.radius) + 0.5
		if at.distance_to(previous.at) < required_space:
			_reject(record, "scenery_overlap")
			return
	var samples: Array[float] = [_height(at)]
	var residuals: Array[float] = [samples[0]]
	var fit_half := half.min(Vector2.ONE * clampf(height * 0.1, 0.3, 1.4)) if is_tree else half
	# Rotated bounds corners and edge midpoints catch banks, terraces and drops.
	# Trees sample their root area; their full crowns still obey route/quest clearances.
	for offset in [Vector2(-fit_half.x, -fit_half.y), Vector2(fit_half.x, -fit_half.y), Vector2(fit_half.x, fit_half.y), Vector2(-fit_half.x, fit_half.y), Vector2(fit_half.x, 0), Vector2(-fit_half.x, 0), Vector2(0, fit_half.y), Vector2(0, -fit_half.y)]:
		var base_offset: Vector3 = rotation * Vector3(offset.x, 0, offset.y)
		var sample: float = _height(at + Vector2(base_offset.x, base_offset.z))
		samples.append(sample)
		residuals.append(sample - base_offset.y)
		if not align:
			slope = maxf(slope, absf(sample - samples[0]) / maxf(offset.length(), 0.4))
	var low: float = samples.min()
	var high: float = samples.max()
	var span := high - low
	var fit_low: float = residuals.min()
	var fit_error: float = float(residuals.max()) - fit_low
	record["ground_span"] = span
	record["fit_error"] = fit_error
	record["ground_slope"] = slope
	var settings: Dictionary = _landscape.get("settings")
	if low < float(settings.get("sea_level", 0.0)) + 1.0 or not is_finite(low):
		_reject(record, "water_or_invalid_ground")
		return
	if slope > float(item.get("max_slope", asset.get("max_slope", 0.45))) or fit_error > float(item.get("max_ground_span", asset.get("max_ground_span", maxf(0.7, height * 0.28)))):
		_reject(record, "steep_ground")
		return
	var sink := maxf(float(item.get("sink", asset.get("sink", 0.08))), 0.0)
	var base_y := fit_low - sink
	var center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var basis := rotation.scaled(Vector3.ONE * factor)
	var transform := Transform3D(basis, Vector3(at.x, base_y, at.y) - basis * center)
	for part in recipe.parts:
		_queue(part, transform * part.transform, at, bool(item.get("shadow", item.get("shadows", asset.get("shadow", true)))))
	_placed.append({"at": at, "radius": spacing, "footprint": radius, "tree": is_tree, "prop": str(asset.get("kind", "")) == "prop"})
	if _forest != null and _forest.has_method("_remember_placement"):
		_forest.call("_remember_placement", at, spacing, is_tree)
	record["position"] = [at.x, base_y, at.y]
	record["yaw"] = rad_to_deg(yaw)
	record["sink"] = sink
	_stats.accepted.append(record)
	_stats.placed += 1
	_stats.groups[group].placed += 1
	_stats.max_ground_span = maxf(float(_stats.max_ground_span), span)
	_stats.max_fit_error = maxf(float(_stats.max_fit_error), fit_error)
	_stats.min_route_clearance = minf(float(_stats.min_route_clearance), clear.x)
	_stats.min_quest_clearance = minf(float(_stats.min_quest_clearance), clear.y)

func _height(at: Vector2) -> float:
	_stats.terrain_sample_count += 1
	return float(_landscape.call("height_at", at)) # Actual terrain triangle interpolation.

func _reject(record: Dictionary, reason: String) -> void:
	record["reason"] = reason
	_stats.rejected.append(record)
	_stats.rejection_counts[reason] = int(_stats.rejection_counts.get(reason, 0)) + 1

func _cache_clearances(settings: Dictionary) -> void:
	var road: Dictionary = settings.get("terrace_road", {})
	_line(settings.get("sampled_mountain_route", settings.get("mountain_route", [])), float(road.get("half_width", 10.0)) + 4.0)
	for spur in settings.get("sampled_terrace_spurs", settings.get("terrace_spurs", [])):
		_line(spur.get("points", [spur.get("from", []), spur.get("to", [])]), float(spur.get("half_width", 10.0)) + 4.0)
	var harbor: Dictionary = settings.get("harbor_asset", {})
	_line(harbor.get("approach_route", []), float(harbor.get("approach_half_width", 6.0)) + 5.0)
	for access in harbor.get("access_routes", []):
		_line(access.get("points", []), float(access.get("half_width", 8.0)) + 4.0)
	for site in settings.get("battle_reservations", []):
		_circles.append({"at": _xz(site.center), "radius": maxf(float(site.get("foliage_clearance", 0.0)), float(site.get("clear_radius", 28.0)) + 4.0)})
	var campaign := _json(ANCHORS)
	for anchor in campaign.get("anchors", {}).values():
		_circles.append({"at": _xz(anchor.position), "radius": maxf(16.0, float(anchor.get("search_radius", 7.0)) + 5.0)})
	for site in campaign.get("battle_sites", {}).values():
		_circles.append({"at": _xz(site.center), "radius": float(site.get("outer_radius", site.get("radius", 18.0))) + 4.0})
		_line([site.get("approach", site.center), site.center], 8.0)

func _line(points: Array, radius: float) -> void:
	for i in range(points.size() - 1):
		if points[i].size() < 2 or points[i + 1].size() < 2:
			continue
		_routes.append({"a": _xz(points[i]), "b": _xz(points[i + 1]), "radius": radius})

func _clearance(at: Vector2, radius: float, height: float) -> Vector2:
	var result := Vector2(INF, INF)
	for route in _routes:
		var delta: Vector2 = route.b - route.a
		var near: Vector2 = route.a + delta * clampf((at - route.a).dot(delta) / maxf(delta.length_squared(), 0.001), 0.0, 1.0)
		result.x = minf(result.x, at.distance_to(near) - float(route.radius) - radius)
	for circle in _circles:
		result.y = minf(result.y, at.distance_to(circle.at) - float(circle.radius) - radius)
	if height > 4.0 and at.y > -432.0 - radius and at.y < -387.0 + radius and absf(at.x - 904.0) < 22.0 + radius:
		result.y = -1.0 # Keep the lookout's south-facing view open.
	return result

func _load_recipe(world: Node3D, asset: Dictionary) -> Dictionary:
	var parts: Array = []
	if asset.has("tree_school") and world.has_method("_v4_parts"):
		for source in world.call("_v4_parts", str(asset.tree_school), str(asset.get("tree_variant", "A"))):
			parts.append(source.duplicate())
	else:
		var path := str(asset.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			return {}
		var packed := load(path) as PackedScene
		if packed == null:
			return {}
		var instance := packed.instantiate()
		# Never add source instances to the tree: no ready, animation, physics or process.
		_collect(instance, Transform3D.IDENTITY, parts)
		instance.free()
		for part in parts:
			part.mesh = _styler.call("style_mesh", path, part.mesh)
	if parts.is_empty():
		return {}
	var bounds: AABB = parts[0].transform * parts[0].mesh.get_aabb()
	for part in parts:
		bounds = bounds.merge(part.transform * part.mesh.get_aabb())
	return {"parts": parts, "bounds": bounds}

func _collect(node: Node, parent: Transform3D, parts: Array) -> void:
	var transform := parent
	if node is Node3D:
		if not node.visible:
			return
		transform = parent * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var mesh: Mesh = node.mesh
		var copied := false
		for surface in range(mesh.get_surface_count()):
			var override: Material = node.get_surface_override_material(surface)
			if override != null:
				if not copied:
					mesh = mesh.duplicate() as Mesh
					copied = true
				mesh.surface_set_material(surface, override)
		parts.append({"mesh": mesh, "material": node.material_override, "overlay": node.material_overlay, "shadow": node.cast_shadow, "transform": transform})
	for child in node.get_children():
		_collect(child, transform, parts)

func _queue(part: Dictionary, transform: Transform3D, at: Vector2, shadows: bool) -> void:
	var cell := Vector2i(floori(at.x / CELL), floori(at.y / CELL))
	var material: Material = part.get("material")
	var overlay: Material = part.get("overlay")
	var shadow := int(part.get("shadow", GeometryInstance3D.SHADOW_CASTING_SETTING_ON)) if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var key := "%s|%d|%d|%d|%d" % [cell, part.mesh.get_instance_id(), material.get_instance_id() if material else 0, overlay.get_instance_id() if overlay else 0, shadow]
	if not _batches.has(key):
		_batches[key] = {"mesh": part.mesh, "material": material, "overlay": overlay, "shadow": shadow, "origin": Vector3(cell.x * CELL, 0, cell.y * CELL), "transforms": []}
	transform.origin -= _batches[key].origin
	_batches[key].transforms.append(transform)

func _build_batches(world: Node3D) -> void:
	var root := Node3D.new()
	root.name = "OrchardQuestScenery"
	world.add_child(root)
	for batch in _batches.values():
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = batch.mesh
		multi.instance_count = batch.transforms.size()
		for i in range(multi.instance_count):
			multi.set_instance_transform(i, batch.transforms[i])
		var visual := MultiMeshInstance3D.new()
		visual.name = "QuestScenery_%d" % root.get_child_count()
		visual.position = batch.origin
		visual.multimesh = multi
		visual.material_override = batch.material
		visual.material_overlay = batch.overlay
		visual.cast_shadow = batch.shadow
		visual.visibility_range_end = 1100.0
		visual.visibility_range_end_margin = 70.0
		root.add_child(visual)

func _xz(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[2] if raw.size() >= 3 else raw[1]))
