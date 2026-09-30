extends RefCounted
## Layered forest belts frame the accepted mountain shoulders and valleys.
## Dressing is visual only; roads, platforms and imported cities stay unobstructed.
const STONE := "res://assets/worlds/_shared_models/3ce8a628d5ab450a_Stone01.glb"
const Textures := preload("res://scripts/worlds/orchard_main_terrain.gd")
const PAINT_ROOT := "res://assets/worlds/star_orchard/paint_v1/"
const CLIFF_PAINT := "res://assets/worlds/star_orchard/coastal_art_v2/cliff_imagegen.png"
const CROWN_SHADER := "res://assets/worlds/star_orchard/procedural_main_v1/forest_crown_v10.gdshader"
var _landscape: Node3D
var _config: Dictionary = {}
var _spec: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _batches: Dictionary = {}
var _placed: Array[Dictionary] = []
var _clearing_spec: Dictionary = {}
var _clearing_removed := {"trees": 0, "rocks": 0}
var _sample_decor_points: Array[Vector2] = []
var _placement_buckets: Dictionary = {}
var _city_footprints: Array[Rect2] = []
var _city_footprint_buckets: Dictionary = {}
var _route_clearances: Array[Dictionary] = []
var _route_buckets: Dictionary = {}
var _tree_recipes: Array[Dictionary] = []
var _simple_tree_recipes: Array[Dictionary] = []
var _crown_sample_positions: Array[Vector3] = []
var _crown_color_counts := {"green": 0, "red": 0}
var _simple_crown_material: ShaderMaterial
var _stone_recipe: Dictionary = {}
var _counts: Dictionary = {"trees": 0, "detailed_trees": 0, "simple_trees": 0, "shadow_trees": 0, "rocks": 0, "large_rocks": 0}
var _regions: Array[Dictionary] = []
var _ambient_anchors: Array[Vector3] = []
var _local_details := preload("res://scripts/worlds/orchard_local_details.gd").new()
var _legacy: RefCounted


func install(world: Node3D, landscape: Node3D) -> void:
	var phase_started := Time.get_ticks_msec()
	var timings := {}
	if world.has_meta("orchard_mountain_dressing"):
		return
	_landscape = landscape
	_config = landscape.settings
	if not _config.has("sculpted_landform"):
		_legacy = LegacyDressing.new()
		_legacy.install(world, landscape)
		return
	if not bool(_config.get("mountain_dressing_enabled", true)):
		world.set_meta("orchard_mountain_dressing", {"trees": 0, "rocks": 0, "shared_batches": 0, "stage": "terrain_review"})
		return
	_spec = _config.get("mountain_dressing", {})
	_rng.seed = int(_config.get("seed", 9262026)) + 5010
	_cache_route_clearances()
	for node_name in ["BlenderSkySanctuary", "BlenderHarborCity"]:
		var city := world.get_node_or_null(node_name)
		if city != null:
			_collect_city_footprints(city)
	var sample_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/orchard_forest_sample_20260926.json"))
	_sample_decor_points.clear()
	if sample_data is Dictionary:
		_clearing_spec = sample_data
		for group in sample_data.get("groups", []):
			for item in group.get("items", []):
				var raw: Array = item.get("at", [])
				if raw.size() == 2:_sample_decor_points.append(Vector2(float(raw[0]), float(raw[1])))
	_local_details.prepare()
	timings["prepare_ms"] = Time.get_ticks_msec() - phase_started
	phase_started = Time.get_ticks_msec()
	_prepare_recipes(world)
	timings["recipes_ms"] = Time.get_ticks_msec() - phase_started
	phase_started = Time.get_ticks_msec()
	var camp: Vector2 = _local_details.plan_camp(landscape, self)
	if camp.is_finite():
		for center in _local_details.camps: _sample_decor_points.append(center)
	for raw in _spec.get("regions", _default_regions()):
		var region: Dictionary = raw
		_dress_region(region)
	preload("res://scripts/worlds/orchard_forest_sample.gd").new().install(world, landscape, self)
	timings["placement_ms"] = Time.get_ticks_msec() - phase_started
	phase_started = Time.get_ticks_msec()
	_build_batches(world)
	timings["batches_ms"] = Time.get_ticks_msec() - phase_started
	phase_started = Time.get_ticks_msec()
	var metadata: Dictionary = _counts.duplicate()
	metadata["shared_batches"] = _batches.size()
	metadata["regions"] = _regions
	metadata["ambient_anchors"] = _ambient_anchors
	metadata["clearing_removed"] = _clearing_removed
	metadata["stage"] = "layered_mountain_forest_v10"
	metadata["decorative_colliders"] = 0
	metadata["canopy_atlas_cells"] = [0, 6]
	metadata["wind"] = "shared_crown_shader_only_roots_fixed"
	world.set_meta("orchard_mountain_dressing", metadata)
	# Quest-side props and undergrowth reuse the accepted terrain and clearances.
	preload("res://scripts/worlds/orchard_quest_scenery.gd").new().install(world, landscape, self)
	_local_details.install(world, landscape, self)
	timings["local_details_ms"] = Time.get_ticks_msec() - phase_started
	world.set_meta("orchard_forest_load_timings", timings)
	if "--orchard-profile-load" in OS.get_cmdline_user_args(): print("ORCHARD_FOREST_LOAD_TIMINGS ", JSON.stringify(timings))


func _default_regions() -> Array:
	return [
		{"id": "lower_bay_inner", "center": [1278, -292], "radii": [53, 29], "trees": 58, "rocks": 8, "detailed": true, "height": [10, 19]},
		{"id": "lower_bay_outer", "center": [1417, -290], "radii": [39, 40], "trees": 64, "rocks": 9, "height": [11, 22]},
		{"id": "middle_east_forest", "center": [1402, -379], "radii": [72, 39], "trees": 108, "rocks": 12, "detailed": true, "height": [12, 24]},
		{"id": "middle_east_seaward", "center": [1462, -350], "radii": [32, 46], "trees": 63, "rocks": 9, "height": [10, 20]},
		{"id": "upper_east_forest", "center": [1471, -515], "radii": [52, 50], "trees": 92, "rocks": 10, "height": [13, 24]},
		{"id": "upper_east_south", "center": [1400, -469], "radii": [65, 33], "trees": 84, "rocks": 8, "height": [12, 23]},
		{"id": "west_site_forest", "center": [776, -481], "radii": [51, 57], "trees": 98, "rocks": 10, "detailed": true, "height": [13, 23]},
		{"id": "west_lower_forest", "center": [876, -413], "radii": [62, 28], "trees": 68, "rocks": 8, "detailed": true, "height": [10, 20]},
		{"id": "inner_valley_forest", "center": [1191, -380], "radii": [60, 49], "trees": 94, "rocks": 9, "detailed": true, "height": [12, 23]},
		{"id": "middle_site_back", "center": [1054, -402], "radii": [56, 23], "trees": 63, "rocks": 8, "detailed": true, "height": [11, 21]},
		{"id": "west_upper_shoulder", "center": [930, -495], "radii": [58, 23], "trees": 62, "rocks": 7, "detailed": true, "height": [12, 23]},
		{"id": "northwest_crest", "center": [842, -1203], "radii": [75, 40], "trees": 104, "rocks": 10, "height": [13, 25]},
		{"id": "north_crest_forest", "center": [966, -1238], "radii": [85, 34], "trees": 110, "rocks": 10, "height": [14, 25]},
		{"id": "northeast_crest", "center": [1145, -1243], "radii": [105, 44], "trees": 136, "rocks": 12, "height": [12, 24]},
		{"id": "north_east_rib", "center": [1298, -1196], "radii": [61, 56], "trees": 90, "rocks": 8, "height": [12, 23]},
		{"id": "west_mid_rib", "center": [719, -822], "radii": [34, 121], "trees": 115, "rocks": 10, "height": [11, 23]},
		{"id": "west_north_rib", "center": [734, -1050], "radii": [34, 91], "trees": 85, "rocks": 8, "height": [12, 23]},
		{"id": "west_south_rib", "center": [741, -596], "radii": [35, 66], "trees": 77, "rocks": 8, "height": [11, 23]},
		{"id": "east_middle_rib", "center": [1516, -802], "radii": [29, 115], "trees": 84, "rocks": 8, "height": [11, 22]},
		{"id": "east_upper_rib", "center": [1503, -1002], "radii": [34, 82], "trees": 72, "rocks": 7, "height": [11, 22]},
		{"id": "east_lower_rib", "center": [1510, -626], "radii": [33, 71], "trees": 72, "rocks": 8, "height": [12, 23]}
	]


func _dress_region(region: Dictionary) -> void:
	var center: Vector2 = _xz(region.get("center", [0, 0]))
	var radii: Vector2 = _xz(region.get("radii", [30, 30]))
	var tree_target: int = mini(int(region.get("trees", 65)), 160)
	var rock_target: int = mini(int(region.get("rocks", 8)), 16)
	var height_range: Array = region.get("height", [11.0, 23.0])
	var trees: int = 0
	var rocks: int = 0
	# These overlapping forest envelopes follow the island's landforms. Spacing is
	# measured at trunks, allowing closed crowns and several rows of forest depth.
	for kind in ["tree", "rock"]:
		var target: int = tree_target if kind == "tree" else rock_target
		for attempt in range(target * 38):
			if (kind == "tree" and trees >= target) or (kind == "rock" and rocks >= target):
				break
			if int(_counts.trees) >= int(_spec.get("tree_limit", 1250)) and kind == "tree":
				break
			if int(_counts.rocks) >= int(_spec.get("rock_limit", 185)) and kind == "rock":
				break
			var angle: float = _rng.randf_range(-PI, PI)
			var radial: float = sqrt(_rng.randf())
			var at: Vector2 = center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * radial
			var is_tree: bool = kind == "tree"
			var is_large: bool = not is_tree and rocks < 2 and attempt < mini(70, target * 10)
			var height: float = _rng.randf_range(float(height_range[0]), float(height_range[1])) if is_tree else _rng.randf_range(2.2, 4.5)
			if is_tree and _rng.randf() < 0.19:
				height *= 0.64 # Young trees form a lower layer below the mature canopy.
			if is_large:
				height = _rng.randf_range(5.0, 7.2)
			var recipe: Dictionary = _stone_recipe
			var road_distance: float = _road_distance(at)
			var detailed: bool = is_tree and bool(region.get("detailed", false)) and road_distance < 64.0 and _rng.randf() < 0.27 and int(_counts.detailed_trees) < int(_spec.get("detailed_tree_limit", 72))
			if is_tree:
				var choices: Array[Dictionary] = _tree_recipes if detailed and not _tree_recipes.is_empty() else _simple_tree_recipes
				if choices.is_empty():
					continue
				recipe = choices[(trees + int(_regions.size())) % choices.size()]
			if recipe.is_empty():
				continue
			var bounds: AABB = recipe.bounds
			var scale_factor: float = height / maxf(bounds.size.y, 0.1)
			var footprint: float = Vector2(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z))).length() * scale_factor
			footprint = maxf(2.0, footprint)
			if not is_tree:
				footprint *= 1.18
			if is_tree and at.x >= 730.0 and at.x <= 1190.0 and at.y >= -540.0 and at.y <= -285.0:
				if at.distance_to(Vector2(1080.0, -350.0)) < 40.0 + footprint or at.distance_to(Vector2(840.0, -445.0)) < 40.0 + footprint or _road_distance(at) < 16.0 + footprint:continue
			if is_tree and str(region.get("id", "")) == "west_lower_forest" and at.distance_to(Vector2(872.0, -414.0)) < 8.0 + footprint:
				continue
			var near_sample_decor := false
			for reserved in _sample_decor_points:
				if at.distance_to(reserved) < 7.0 + footprint:
					near_sample_decor = true
					break
			if near_sample_decor:continue
			var trunk_space: float = clampf(height * 0.14, 1.65, 3.1) if is_tree else footprint * 0.62
			if not _clear(at, footprint, trunk_space, is_tree):
				continue
			var y: float = _landscape.height_at(at)
			if y < float(_config.sea_level) + 5.0:
				continue
			var sample_radius: float = clampf(height * 0.11, 1.2, 2.3) if is_tree else clampf(footprint * 0.45, 2.5, 5.0)
			var fit: Vector3 = _ground_fit(at, sample_radius)
			if fit.z > (0.74 if is_tree else 0.86):
				continue
			if fit.y - fit.x > (sample_radius * 1.45 if is_tree else sample_radius * 1.65):
				continue
			var base_y: float = minf(y, fit.x + 0.22) if is_tree else minf(y, fit.x + height * 0.16)
			base_y -= 0.10 if is_tree else height * 0.19
			var yaw: float = _rng.randf_range(-PI, PI)
			var size: Vector3 = Vector3.ONE * scale_factor
			if not is_tree:
				size.x *= _rng.randf_range(0.96, 1.18)
				size.z *= _rng.randf_range(0.92, 1.12)
			var transform: Transform3D = Transform3D(Basis(Vector3.UP, yaw).scaled(size), Vector3(at.x, base_y - bounds.position.y * scale_factor, at.y))
			var shadow: bool = is_large or (is_tree and int(_counts.shadow_trees) < int(_spec.get("shadow_tree_limit", 150)) and (detailed or (road_distance < 70.0 and _rng.randf() < 0.3)))
			var variation: Color = Color(_rng.randf(), _rng.randf(), _rng.randf(), clampf(height / 24.0, 0.25, 1.0))
			if is_tree and str(region.get("id", "")) == "lower_bay_outer" and int(recipe.get("simple_shape", -1)) == 0 and _crown_sample_positions.size() < 10:
				_crown_sample_positions.append(Vector3(at.x, base_y, at.y))
			_queue_recipe(recipe, transform, shadow, is_tree, variation)
			_remember_placement(at, trunk_space, is_tree)
			if is_tree:
				if trees == 0 and _ambient_anchors.size() < 16:
					_ambient_anchors.append(Vector3(at.x, base_y + height * 0.45, at.y))
				trees += 1
				_counts.trees += 1
				if shadow:
					_counts.shadow_trees += 1
				if detailed and not _tree_recipes.is_empty():
					_counts.detailed_trees += 1
				else:
					_counts.simple_trees += 1
			else:
				rocks += 1
				_counts.rocks += 1
				if is_large:
					_counts.large_rocks += 1
	_regions.append({"id": str(region.get("id", "grove")), "trees": trees, "rocks": rocks})


func _ground_fit(at: Vector2, radius: float) -> Vector3:
	var y: float = _landscape.height_at(at)
	var minimum := y
	var maximum := y
	for offset in [Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius), Vector2(radius, radius) * 0.7, Vector2(-radius, -radius) * 0.7]:
		var sampled: float = _landscape.height_at(at + offset)
		minimum = minf(minimum, sampled)
		maximum = maxf(maximum, sampled)
	return Vector3(minimum, maximum, (maximum - minimum) / (2.0 * radius))


func _cache_route_clearances() -> void:
	var road: Dictionary = _config.get("terrace_road", {})
	var main: Array = _config.get("sampled_mountain_route", _config.get("mountain_route", []))
	_cache_line(main, float(road.get("half_width", 10.0)) + 4.0)
	for raw in _config.get("sampled_terrace_spurs", _config.get("terrace_spurs", [])):
		var spur: Dictionary = raw
		var points: Array = spur.get("points", [spur.get("from", []), spur.get("to", [])])
		_cache_line(points, float(spur.get("half_width", 10.0)) + 4.0)
	var harbor: Dictionary = _config.get("harbor_asset", {})
	_cache_line(harbor.get("approach_route", []), float(harbor.get("approach_half_width", 6.0)) + 8.0)
	for access in harbor.get("access_routes", []):
		_cache_line(access.get("points", []), float(access.get("half_width", 8.0)) + 8.0)


func _cache_line(points: Array, clearance: float) -> void:
	for index in range(points.size() - 1):
		if points[index].size() < 2 or points[index + 1].size() < 2:
			continue
		var a := _xz(points[index])
		var b := _xz(points[index + 1])
		var segment: Dictionary = {"a": a, "span": b - a, "inverse": 1.0 / maxf(a.distance_squared_to(b), 0.001), "clearance": clearance}
		_route_clearances.append(segment)
		var bounds: Rect2 = Rect2(a, Vector2.ZERO).expand(b).grow(96.0)
		for z in range(floori(bounds.position.y / 48.0), floori(bounds.end.y / 48.0) + 1):
			for x in range(floori(bounds.position.x / 48.0), floori(bounds.end.x / 48.0) + 1):
				var bucket: Vector2i = Vector2i(x, z)
				if not _route_buckets.has(bucket):
					_route_buckets[bucket] = []
				_route_buckets[bucket].append(segment)


func _nearby_routes(at: Vector2) -> Array:
	return _route_buckets.get(Vector2i(floori(at.x / 48.0), floori(at.y / 48.0)), [])


func _road_distance(at: Vector2) -> float:
	var nearest_distance: float = INF
	for segment in _nearby_routes(at):
		var span: Vector2 = segment.span
		var nearest: Vector2 = segment.a + span * clampf((at - segment.a).dot(span) * float(segment.inverse), 0.0, 1.0)
		nearest_distance = minf(nearest_distance, at.distance_to(nearest))
	return nearest_distance


func _clear(at: Vector2, radius: float, trunk_space: float, is_tree: bool) -> bool:
	if _local_details.camp_blocked(at, radius): return false
	# The root-gallery repair court and its approach stay clear of new dressing.
	if at.distance_to(Vector2(1374.0, -718.0)) < 32.0 + radius:
		return false
	for segment in _nearby_routes(at):
		var delta: Vector2 = segment.span
		var nearest: Vector2 = segment.a + delta * clampf((at - segment.a).dot(delta) * float(segment.inverse), 0.0, 1.0)
		# Tree trunks leave a clear shoulder. Crowns may form a canopy above it.
		var road_radius: float = trunk_space if is_tree else radius
		if at.distance_to(nearest) < float(segment.clearance) + road_radius:
			return false
	for platform in _config.get("battle_reservations", []):
		var clearance := maxf(float(platform.get("foliage_clearance", 0.0)), float(platform.get("clear_radius", 28.0)) + 10.0)
		if at.distance_to(_xz(platform.center)) < clearance + radius:
			return false
	var city_bucket := Vector2i(floori(at.x / 40.0), floori(at.y / 40.0))
	var city_nearby: Array = _city_footprint_buckets.get(city_bucket, []) if radius <= 22.0 else _city_footprints
	for footprint in city_nearby:
		if footprint.grow(radius + 2.0).has_point(at):
			return false
	for key in ["sky_city", "harbor_asset"]:
		var city: Dictionary = _config.get(key, {})
		for entrance_key in ["entrance", "land_exit", "spawn", "swim_landing"]:
			if city.has(entrance_key) and at.distance_to(_xz(city[entrance_key])) < 26.0 + radius:
				return false
	var bucket: Vector2i = Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
	for z in range(bucket.y - 2, bucket.y + 3):
		for x in range(bucket.x - 2, bucket.x + 3):
			for previous in _placement_buckets.get(Vector2i(x, z), []):
				var other_radius: float = float(previous.radius)
				if not is_tree and bool(previous.tree):
					other_radius = 1.0
				var personal_space: float = trunk_space + other_radius
				if at.distance_to(previous.at) < maxf(personal_space, 4.4 if is_tree else 2.8):
					return false
	return true


func _remember_placement(at: Vector2, radius: float, is_tree: bool) -> void:
	var placement: Dictionary = {"at": at, "radius": radius, "tree": is_tree}
	var bucket: Vector2i = Vector2i(floori(at.x / 16.0), floori(at.y / 16.0))
	if not _placement_buckets.has(bucket):
		_placement_buckets[bucket] = []
	_placement_buckets[bucket].append(placement)
	_placed.append(placement)


func _collect_city_footprints(node: Node) -> void:
	# Cache each actual imported mesh, including noncolliding visual overhangs.
	# A single harbor-sized rectangle incorrectly erased the lower mountain groves.
	if node is MeshInstance3D and node.mesh != null:
		var bounds: AABB = node.global_transform * node.mesh.get_aabb()
		if bounds.size.x > 0.05 and bounds.size.z > 0.05:
			var footprint := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
			_city_footprints.append(footprint)
			var expanded := footprint.grow(24.0)
			for z in range(floori(expanded.position.y / 40.0), floori(expanded.end.y / 40.0) + 1):
				for x in range(floori(expanded.position.x / 40.0), floori(expanded.end.x / 40.0) + 1):
					var bucket := Vector2i(x, z)
					if not _city_footprint_buckets.has(bucket):
						_city_footprint_buckets[bucket] = []
					_city_footprint_buckets[bucket].append(footprint)
	for child in node.get_children():
		_collect_city_footprints(child)


func _prepare_recipes(world: Node3D) -> void:
	for school in ["life", "balance"]:
		if world.has_method("_v4_parts"):
			var parts: Array = world.call("_v4_parts", school, "A")
			if not parts.is_empty():
				_tree_recipes.append(_recipe(parts))
	_prepare_simple_trees()
	var packed := load(STONE) as PackedScene
	if packed == null:
		return
	var instance := packed.instantiate()
	var stones: Array = []
	_collect(instance, Transform3D.IDENTITY, stones)
	instance.free()
	var material := _painted_material(CLIFF_PAINT, Color(0.9, 0.94, 0.94))
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.22
	for part in stones:
		part["material"] = material
	if not stones.is_empty():
		_stone_recipe = _recipe(stones)


func _prepare_simple_trees() -> void:
	# Two shared geometry resources, one bark material and one crown shader serve
	# every simple tree. Color family lives in MultiMesh instance custom data.
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.21
	trunk.bottom_radius = 0.43
	trunk.height = 5.5
	trunk.radial_segments = 7
	trunk.rings = 1
	var crown := SphereMesh.new()
	crown.radius = 2.45
	crown.height = 4.2
	crown.radial_segments = 10
	crown.rings = 4
	var bark := _painted_material(PAINT_ROOT + "bark_imagegen.png", Color.WHITE)
	bark.uv1_triplanar = true
	bark.uv1_scale = Vector3(0.7, 0.35, 0.7)
	var leaves: ShaderMaterial = ShaderMaterial.new()
	leaves.shader = load(CROWN_SHADER) as Shader
	leaves.set_shader_parameter("leaves_atlas", Textures.asset_texture(PAINT_ROOT + "leaves_imagegen.png"))
	leaves.set_shader_parameter("wind_strength", float(_spec.get("canopy_wind_strength", 0.12)))
	leaves.set_shader_parameter("color_strength", 1.0)
	_simple_crown_material = leaves
	for shape in range(3):
		var slender: float = 0.84 if shape == 1 else 1.0
		var tall: float = 1.20 if shape == 1 else (0.86 if shape == 2 else 1.0)
		var parts: Array = [
			{"mesh": trunk, "material": bark, "transform": Transform3D(Basis.IDENTITY, Vector3(0, 2.75, 0))},
			{"mesh": crown, "material": leaves, "transform": Transform3D(Basis.IDENTITY.scaled(Vector3(1.12 * slender, 1.17 * tall, 0.99 * slender)), Vector3(0.15, 7.05, 0))},
			{"mesh": crown, "material": leaves, "transform": Transform3D(Basis.IDENTITY.scaled(Vector3(0.90 * slender, 0.92 * tall, 0.87)), Vector3(-1.95 * slender, 5.68, 0.49))},
			{"mesh": crown, "material": leaves, "transform": Transform3D(Basis.IDENTITY.scaled(Vector3(0.84 * slender, 0.79 * tall, 0.98)), Vector3(1.78 * slender, 6.10, -0.47))}
		]
		var recipe := _recipe(parts)
		recipe["simple_shape"] = shape
		_simple_tree_recipes.append(recipe)


func _painted_material(path: String, tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = Textures.asset_texture(path)
	material.albedo_color = tint
	material.roughness = 0.94
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material


func _recipe(parts: Array) -> Dictionary:
	var bounds: AABB = parts[0].transform * parts[0].mesh.get_aabb()
	for part in parts:
		bounds = bounds.merge(part.transform * part.mesh.get_aabb())
	return {"parts": parts, "bounds": bounds}


func _queue_recipe(recipe: Dictionary, placement: Transform3D, shadows: bool, is_tree: bool, variation: Color) -> void:
	var bounds: AABB = recipe.bounds
	var crown: float = Vector2(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z))).length() * placement.basis.get_scale().x
	if clearing_blocked(Vector2(placement.origin.x, placement.origin.z), crown):
		_clearing_removed["trees" if is_tree else "rocks"] += 1
		return # Preserve legacy random sequence and placements outside these masks.
	# Preserve accepted positions, terrain and road reservations; replace only local trees.
	if is_tree:
		var authored: Dictionary = _local_details.tree_at(placement.origin)
		if not authored.is_empty():
			var old_height := bounds.size.y * placement.basis.get_scale().y
			var base := placement.origin.y + bounds.position.y * placement.basis.get_scale().y
			var new_bounds: AABB = authored.bounds
			var factor := clampf(old_height, 9.0, 17.0) / new_bounds.size.y
			placement.basis = placement.basis.orthonormalized().scaled(Vector3.ONE * factor)
			placement.origin.y = base - new_bounds.position.y * factor
			recipe = authored
	var region_size: float = maxf(64.0, float(_spec.get("batch_region_size", 112.0)))
	var region: Vector2i = Vector2i(floori(placement.origin.x / region_size), floori(placement.origin.z / region_size))
	var simple_crown := is_tree and recipe.has("simple_shape")
	var red_crown := false # Keep the mountain forest in the existing green crown family.
	if simple_crown:
		_crown_color_counts["red" if red_crown else "green"] += 1
	for part in recipe.parts:
		var mesh: Mesh = part.mesh
		var material: Material = part.get("material", null)
		var material_key: int = material.get_instance_id() if material != null else 0
		var key: String = "%d_%d_%d_%d_%d" % [mesh.get_instance_id(), material_key, region.x, region.y, int(shadows)]
		if not _batches.has(key):
			var origin: Vector3 = Vector3((float(region.x) + 0.5) * region_size, placement.origin.y, (float(region.y) + 0.5) * region_size)
			_batches[key] = {"mesh": mesh, "material": material, "transforms": [], "custom": [], "region": region, "origin": origin, "shadows": shadows, "tree": is_tree}
		var local_transform: Transform3D = placement * part.transform
		local_transform.origin -= Vector3(_batches[key].origin)
		_batches[key].transforms.append(local_transform)
		var custom := variation
		if red_crown and material == _simple_crown_material:
			custom.a = -variation.a
		_batches[key].custom.append(custom)


func _build_batches(world: Node3D) -> void:
	var root := Node3D.new()
	root.name = "MountainShoulderForest"
	world.add_child(root)
	world.set_meta("orchard_crown_colors", {"green": _crown_color_counts.green, "red": _crown_color_counts.red, "sample_positions": _crown_sample_positions})
	for batch in _batches.values():
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = batch.mesh
		multimesh.instance_count = batch.transforms.size()
		for index in range(multimesh.instance_count):
			multimesh.set_instance_transform(index, batch.transforms[index])
			multimesh.set_instance_custom_data(index, batch.custom[index])
		var visual := MultiMeshInstance3D.new()
		visual.name = "Groves_%d_%d" % [batch.region.x, batch.region.y]
		visual.position = batch.origin
		visual.multimesh = multimesh
		visual.material_override = batch.material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(batch.shadows) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 1550.0 if bool(batch.tree) else (1000.0 if bool(batch.shadows) else 520.0)
		visual.visibility_range_end_margin = 65.0
		visual.extra_cull_margin = 1.0
		root.add_child(visual)


func _xz(raw: Array) -> Vector2:
	return Vector2(float(raw[0]), float(raw[2] if raw.size() >= 3 else raw[1]))


func _collect(node: Node, parent: Transform3D, parts: Array) -> void:
	var transform := parent
	if node is Node3D:
		transform = parent * node.transform
	if node is MeshInstance3D and node.mesh != null:
		parts.append({"mesh": node.mesh, "material": node.material_override, "transform": transform})
	for child in node.get_children():
		_collect(child, transform, parts)


class LegacyDressing:
	extends RefCounted
	## A few roadside groves and rock groups; all road/arena reservations remain empty.
	const STONE := "res://assets/worlds/_shared_models/3ce8a628d5ab450a_Stone01.glb"
	const City := preload("res://scripts/worlds/orchard_sky_city.gd")
	var _batches: Dictionary = {}
	var _placed: Array[Vector2] = []
	var _city_footprints: Array[Rect2] = []
	var _config: Dictionary
	var _route: Array
	var _landscape: Node3D
	var _rng := RandomNumberGenerator.new()
	
	func install(world: Node3D, landscape: Node3D) -> void:
		if world.has_meta("orchard_mountain_dressing"): return
		_landscape = landscape
		_config = landscape.settings
		if not bool(_config.get("mountain_dressing_enabled", true)):
			world.set_meta("orchard_mountain_dressing", {"trees": 0, "rocks": 0, "shared_batches": 0, "stage": "terrain_review"})
			return
		_route = _config.get("sampled_mountain_route", _config.mountain_route)
		if _route.size() < 3: return
		var city := world.get_node_or_null("BlenderSkySanctuary")
		if city != null: _collect_city_footprints(city)
		var harbor := world.get_node_or_null("BlenderHarborCity")
		if harbor != null: _collect_city_footprints(harbor)
		_rng.seed = int(_config.seed) + 4701
		var trees: Array = []
		for school in ["life", "balance"]:
			if world.has_method("_v4_parts"):
				trees.append(world.call("_v4_parts", school, "A"))
		var stones: Array = []
		var packed := load(STONE) as PackedScene
		if packed != null:
			var instance := packed.instantiate()
			_collect(instance, Transform3D.IDENTITY, stones)
			instance.free()
		var tree_count := 0
		var rock_count := 0
		# Each accepted group has a shared center; no full-map random carpet.
		var road_clear: float = _config.terrace_road.get("foliage_clearance", float(_config.terrace_road.get("half_width", 16.0)) + 6.0)
		for group in 320:
			if tree_count >= 220 and rock_count >= 100: break
			var index := 1 + group % (_route.size() - 2)
			var a := _point(_route[index])
			var b := _point(_route[index + 1])
			var tangent := (b - a).normalized()
			var side := Vector2(-tangent.y, tangent.x) * (1.0 if group % 3 != 0 else -1.0)
			var center := a.lerp(b, _rng.randf_range(0.12, 0.88)) + side * (road_clear + _rng.randf_range(10.0, 45.0))
			# Every fourth grove sits behind a reserved arena rather than beside the road.
			var platforms: Array = _config.get("battle_reservations", [])
			if group % 4 == 3 and not platforms.is_empty():
				var platform: Dictionary = platforms[(group / 4) as int % platforms.size()]
				var platform_center := _point(platform.center)
				var away := (platform_center - a.lerp(b, 0.5)).normalized()
				var radius: float = platform.get("foliage_clearance", float(platform.clear_radius) + 12.0)
				center = platform_center + away * (radius + _rng.randf_range(15.0, 36.0))
			for item in 8:
				var is_tree := item < 6
				if (is_tree and tree_count >= 220) or (not is_tree and rock_count >= 100): continue
				var at := center + Vector2(_rng.randf_range(-18.0, 18.0), _rng.randf_range(-18.0, 18.0))
				if not _clear(at, 6.0 if is_tree else 4.0): continue
				var y: float = landscape.height_at(at)
				if y < float(_config.sea_level) + 2.5: continue
				var slope_x: float = absf(landscape.height_at(at + Vector2(3, 0)) - landscape.height_at(at - Vector2(3, 0))) / 6.0
				var slope_z: float = absf(landscape.height_at(at + Vector2(0, 3)) - landscape.height_at(at - Vector2(0, 3))) / 6.0
				if maxf(slope_x, slope_z) > (0.62 if is_tree else 1.3): continue
				var parts: Array = stones
				if is_tree:
					if trees.is_empty(): continue
					parts = trees[group % trees.size()]
				if parts.is_empty(): continue
				var bounds := _bounds(parts)
				var height := _rng.randf_range(9.0, 16.0) if is_tree else _rng.randf_range(2.5, 5.0)
				var factor := height / maxf(bounds.size.y, 0.1)
				var position := Vector3(at.x, y - bounds.position.y * factor - (0.0 if is_tree else height * 0.16), at.y)
				var transform := Transform3D(Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3.ONE * factor), position)
				for part in parts:
					var key: int = part.mesh.get_instance_id()
					if not _batches.has(key): _batches[key] = {"mesh": part.mesh, "transforms": []}
					_batches[key].transforms.append(transform * part.transform)
				_placed.append(at)
				if is_tree: tree_count += 1
				else: rock_count += 1
		var root := Node3D.new()
		root.name = "MountainRoadGroves"
		world.add_child(root)
		for batch in _batches.values():
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = batch.mesh
			multi.instance_count = batch.transforms.size()
			for i in multi.instance_count: multi.set_instance_transform(i, batch.transforms[i])
			var visual := MultiMeshInstance3D.new()
			visual.multimesh = multi
			root.add_child(visual)
		world.set_meta("orchard_mountain_dressing", {"trees": tree_count, "rocks": rock_count, "shared_batches": _batches.size()})
	
	func _clear(at: Vector2, margin: float) -> bool:
		var road_clear: float = _config.terrace_road.get("foliage_clearance", float(_config.terrace_road.get("half_width", 16.0)) + 6.0) + margin
		for i in range(_route.size() - 1):
			if _segment_distance(at, _point(_route[i]), _point(_route[i + 1])) < road_clear: return false
		for spur in _config.get("terrace_spurs", []):
			if _segment_distance(at, _point(spur.from), _point(spur.to)) < road_clear: return false
		for platform in _config.get("battle_reservations", []):
			var radius: float = platform.get("foliage_clearance", float(platform.clear_radius) + 12.0)
			if at.distance_to(_point(platform.center)) < radius + margin: return false
		var harbor: Dictionary = _config.harbor
		var delta := (at - _point(harbor.center)).abs()
		if delta.x < float(harbor.size[0]) * 0.5 + 45.0 and delta.y < float(harbor.size[1]) * 0.5 + 45.0: return false
		if _city_footprints.is_empty():
			if at.x > City.WORLD_MIN.x - margin and at.x < City.WORLD_MAX.x + margin and at.y > City.WORLD_MIN.z - margin and at.y < City.WORLD_MAX.z + margin: return false
		else:
			for footprint in _city_footprints:
				if footprint.grow(margin).has_point(at): return false
		for other in _placed:
			if at.distance_to(other) < margin: return false
		return true
	
	func _collect_city_footprints(node: Node) -> void:
		if node is MeshInstance3D and node.mesh != null and str(node.name).begins_with("C_"):
			var bounds: AABB = node.global_transform * node.mesh.get_aabb()
			_city_footprints.append(Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)))
		for child in node.get_children(): _collect_city_footprints(child)
	
	func _point(raw: Array) -> Vector2:
		return Vector2(float(raw[0]), float(raw[2]))
	
	func _segment_distance(at: Vector2, a: Vector2, b: Vector2) -> float:
		var span := b - a
		return at.distance_to(a + span * clampf((at - a).dot(span) / maxf(span.length_squared(), 0.01), 0.0, 1.0))
	
	func _bounds(parts: Array) -> AABB:
		var result: AABB = parts[0].transform * parts[0].mesh.get_aabb()
		for part in parts: result = result.merge(part.transform * part.mesh.get_aabb())
		return result
	
	func _collect(node: Node, parent: Transform3D, parts: Array) -> void:
		var transform := parent
		if node is Node3D: transform = parent * node.transform
		if node is MeshInstance3D and node.mesh != null: parts.append({"mesh": node.mesh, "transform": transform})
		for child in node.get_children(): _collect(child, transform, parts)

func clearing_blocked(at: Vector2, radius: float) -> bool:
	for clearing in _clearing_spec.get("clearings", []):
		var center := Vector2(float(clearing.at[0]), float(clearing.at[1]))
		var angle := (at - center).angle()
		var edge := float(clearing.radius) + 2.0 + 2.0 * sin(angle * 3.0 + center.x)
		if at.distance_to(center) < edge + radius:return true
	for path in _clearing_spec.get("access_paths", []):
		var points: Array = path.path
		for index in range(points.size()-1):
			var a := Vector2(float(points[index][0]),float(points[index][1]))
			var b := Vector2(float(points[index+1][0]),float(points[index+1][1]))
			var span := b-a
			var t := clampf((at-a).dot(span)/maxf(span.length_squared(),0.001),0.0,1.0)
			if at.distance_to(a+span*t) < float(path.half_width)+2.5+radius:return true
	return false
