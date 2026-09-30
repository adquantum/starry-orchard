extends Node3D
## One deterministic sampled landscape for rendering, collision and floor queries.
## The harbor and city are reservations; no old town assets or story flags are loaded.
const CONFIG := "res://resources/fusion_3d/orchard_procedural_landscape.json"
const CONFIG_V8 := "res://resources/fusion_3d/orchard_procedural_landscape_v8.json"
const LandformV8 := preload("res://scripts/worlds/orchard_landform_v8.gd")
const RoadsV8 := preload("res://scripts/worlds/orchard_roads_v8.gd")
const Textures := preload("res://scripts/worlds/orchard_main_terrain.gd")
const CHUNK_CELLS := 32
const SAMPLING_CACHE := "res://assets/worlds/star_orchard/runtime_cache/terrain_samples.bin"
var settings: Dictionary = {}
var grid_start := Vector2.ZERO
var grid_cells := Vector2i.ZERO
var grid_step := 8.0
var heights := PackedFloat32Array()
var trail_weights := PackedFloat32Array()
var route: Array[Vector3] = []
var city_entrance := Vector3(1080, 620, -430)
var city_center := Vector3(1080, 620, -630)
var harbor_center := Vector3(1010, 226, 1450)
var geometry_scale := 1.0
var elevation_scale := 1.0
var scale_pivot := Vector2(1080, -630)
var broad := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var _built := false
var _material: ShaderMaterial
var _landform_v8: RefCounted
var _roads_v8: RefCounted
var _protection_caps := PackedFloat32Array()
var _support_heights := PackedFloat32Array()
var _support_weights := PackedFloat32Array()
var _biomes := PackedVector2Array()
var _revision_v8 := false

func _prepare() -> void:
	if not heights.is_empty(): return
	var config_path := CONFIG if "--orchard-terrain-v7" in OS.get_cmdline_user_args() else CONFIG_V8
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not parsed is Dictionary:
		push_error("Could not load orchard terrain profile: " + config_path)
		return
	settings = parsed
	_revision_v8 = settings.has("sculpted_landform")
	_resolve_scaled_profile()
	grid_start = Vector2(settings.grid_start[0], settings.grid_start[1])
	grid_cells = Vector2i(settings.grid_cells[0], settings.grid_cells[1])
	grid_step = float(settings.grid_step)
	broad.seed = int(settings.seed)
	broad.frequency = 0.0015
	broad.fractal_octaves = 3
	detail.seed = int(settings.seed) + 193
	detail.frequency = 0.009
	detail.fractal_octaves = 2
	for point in settings.mountain_route:
		route.append(Vector3(point[0], point[1], point[2]))
	var entrance: Array = settings.sky_city.entrance
	city_entrance = Vector3(entrance[0], entrance[1], entrance[2])
	var city: Array = settings.sky_city.center
	city_center = Vector3(city[0], city[1], city[2])
	var harbor: Array = settings.harbor.center
	harbor_center = Vector3(harbor[0], harbor[1], harbor[2])
	route[route.size()-1] = city_entrance
	var count := (grid_cells.x + 1) * (grid_cells.y + 1)
	heights.resize(count)
	trail_weights.resize(count)
	if _revision_v8:
		_prepare_revision(count)
		if _restore_sampling_cache(count): return
	for z in range(grid_cells.y + 1):
		for x in range(grid_cells.x + 1):
			var at := grid_start + Vector2(x, z) * grid_step
			var index := z * (grid_cells.x + 1) + x
			if _revision_v8:
				var sample: Dictionary = _roads_v8.sample(at)
				heights[index] = _revised_height(at, sample, index)
				trail_weights[index] = 1.0 - smoothstep(7.0, 14.0, float(sample.distance))
				_biomes[index] = _landform_v8.biome_at(at)
			else:
				var road := _route_sample(at)
				heights[index] = _analytic_height(at, road)
				trail_weights[index] = 1.0 - smoothstep(8.0, 18.0, road.x)

	_paint_access_trails()

func _sampling_key() -> String:
	var paths := [CONFIG_V8, "res://scripts/worlds/orchard_procedural_landscape.gd", "res://scripts/worlds/orchard_landform_v8.gd", "res://scripts/worlds/orchard_roads_v8.gd", "res://resources/fusion_3d/orchard_forest_sample_20260926.json"]
	for path in settings.terrain_protection.values():
		if path is String and str(path).begins_with("res://"): paths.append(path)
	var hashes := PackedStringArray()
	for path in paths: hashes.append(str(path) + ":" + FileAccess.get_sha256(str(path)))
	return "\n".join(hashes).sha256_text()

func _restore_sampling_cache(count: int) -> bool:
	if "--orchard-rebuild-terrain" in OS.get_cmdline_user_args() or not FileAccess.file_exists(SAMPLING_CACHE): return false
	var file := FileAccess.open(SAMPLING_CACHE, FileAccess.READ)
	if file == null: return false
	var cached: Variant = file.get_var(false)
	if not cached is Dictionary or str(cached.get("key", "")) != _sampling_key(): return false
	if not cached.get("heights") is PackedFloat32Array or not cached.get("trails") is PackedFloat32Array or not cached.get("biomes") is PackedVector2Array: return false
	if cached.heights.size() != count or cached.trails.size() != count or cached.biomes.size() != count: return false
	heights = cached.heights
	trail_weights = cached.trails
	_biomes = cached.biomes
	set_meta("sampling_cache_used", true)
	return true

## Called only by the explicit offline cache generation tool.
func save_sampling_cache() -> Error:
	_prepare()
	var file := FileAccess.open(SAMPLING_CACHE, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_var({"key": _sampling_key(), "heights": heights, "trails": trail_weights, "biomes": _biomes})
	return OK

func install(world: Node3D) -> void:
	build(world)

func build(world: Node3D) -> void:
	_prepare()
	if get_parent() == null: world.add_child(self)
	if _built: return
	name = "OrchardProceduralLandscape"
	world.set_meta("orchard_procedural_world", true)
	world.set_meta("orchard_generated_terrain", str(settings.revision))
	world.set_meta("orchard_landscape_profile", settings.revision)
	world.set_meta("orchard_geometry_scale", geometry_scale)
	world.set_meta("orchard_elevation_scale", elevation_scale)
	var harbor_radius := maxf(float(settings.harbor.size[0]), float(settings.harbor.size[1]))*0.5+25.0
	world.set_meta("orchard_map_regions", [
		{"name": "星果港湾", "center": [harbor_center.x, harbor_center.z], "radius": harbor_radius},
		{"name": "山脚小径", "center": [1380, -260], "radius": 100},
		{"name": "沿崖山路", "center": [1120, -430], "radius": 150},
		{"name": "高山天空城", "center": [1080, -630], "radius": 620}
	])
	world.set_meta("orchard_terrain_clearances", {
		"route": settings.mountain_route.duplicate(true),
		"route_half_width": float(settings.terrace_road.foliage_clearance),
		"spurs": settings.terrace_spurs.duplicate(true),
		"platforms": settings.battle_reservations.duplicate(true),
		"harbor_asset": settings.get("harbor_asset", {}).duplicate(true)
	})
	set_meta("generation_seed", settings.seed)
	set_meta("generated_from_functions", true)
	_make_material()
	for z in range(0, grid_cells.y, CHUNK_CELLS):
		for x in range(0, grid_cells.x, CHUNK_CELLS):
			_build_chunk(Vector2i(x, z))
	for id in ["harbor", "sky_city"]:
		var marker := Marker3D.new()
		marker.name = "Reservation_" + id
		var spec := reservation(id)
		marker.position = spec.center
		marker.set_meta("reservation", spec)
		add_child(marker)
	var battle_sites: Array[Dictionary] = []
	for raw in settings.get("battle_reservations", []):
		var spec: Dictionary = raw.duplicate(true)
		var point: Array = spec.center
		var center := Vector3(point[0], height_at(Vector2(point[0], point[2])), point[2])
		spec.center = center
		spec.role = "terrain_reservation_only"
		spec.enabled = false
		spec.disabled = true
		var marker := Marker3D.new()
		marker.name = str(spec.id)
		marker.position = center
		marker.set_meta("reserved_battle_site", spec)
		marker.set_meta("disabled", true)
		add_child(marker)
		battle_sites.append(spec)
		var regions: Array = world.get_meta("orchard_map_regions", [])
		regions.append({"name": spec.name, "center": [center.x, center.z], "radius": float(spec.clear_radius)+20.0, "disabled": true})
		world.set_meta("orchard_map_regions", regions)
	world.set_meta("orchard_battle_reservations", battle_sites)
	_built = true

func height_at(at: Vector2) -> float:
	_prepare()
	var point := (at - grid_start) / grid_step
	var x := floori(point.x)
	var z := floori(point.y)
	if x < 0 or z < 0 or x >= grid_cells.x or z >= grid_cells.y:
		return float(settings.sea_floor)
	var width := grid_cells.x + 1
	var a := z * width + x
	var u := point.x - x
	var v := point.y - z
	if u + v <= 1.0:
		return heights[a] + (heights[a+1] - heights[a]) * u + (heights[a+width] - heights[a]) * v
	return heights[a+width+1] + (heights[a+width] - heights[a+width+1]) * (1.0-u) + (heights[a+1] - heights[a+width+1]) * (1.0-v)

func surface_height(at: Vector3) -> float:
	return height_at(Vector2(at.x, at.z))

func reservation(id: String) -> Dictionary:
	_prepare()
	if not settings.has(id): return {}
	var result: Dictionary = settings[id].duplicate(true)
	var point: Array = result.center
	result.center = Vector3(point[0], point[1], point[2])
	result.size = Vector2(result.size[0], result.size[1])
	if result.has("entrance"):
		var entry: Array = result.entrance
		result.entrance = Vector3(entry[0], entry[1], entry[2])
	return result

func spawn_point() -> Vector3:
	_prepare()
	var point: Array = settings.harbor.spawn
	if bool(settings.get("harbor_asset", {}).get("enabled", false)):
		return Vector3(point[0], point[1], point[2])
	return Vector3(point[0], height_at(Vector2(point[0], point[2])) + 2.0, point[2])

func destination_points() -> Array[Vector3]:
	_prepare()
	var points: Array[Vector3] = [spawn_point()]
	for site in settings.get("battle_reservations", []):
		var center: Array = site.center
		points.append(Vector3(center[0], height_at(Vector2(center[0], center[2]))+2.0, center[2]))
	points.append(city_entrance+Vector3.UP*2.0)
	return points

func destination_names() -> Array[String]:
	_prepare()
	var names: Array[String] = ["星果港湾"]
	for site in settings.get("battle_reservations", []): names.append(str(site.name))
	names.append("天空城山门")
	return names

func _ellipse(at: Vector2, center: Vector2, radii: Vector2) -> float:
	return (1.0 - ((at - center) / radii).length()) * minf(radii.x, radii.y)

func _scaled_xz(point: Array) -> Array:
	var result := scale_pivot+(Vector2(point[0], point[1])-scale_pivot)*geometry_scale
	return [result.x, result.y]

func _scaled_elevation(height: float) -> float:
	var sea := float(settings.sea_level)
	return sea+(height-sea)*elevation_scale if height > sea else height

func _resolve_scaled_profile() -> void:
	geometry_scale = float(settings.get("geometry_scale", 1.0))
	elevation_scale = float(settings.get("elevation_scale", 1.0))
	if _revision_v8 or not settings.has("reference_landform"): return
	scale_pivot = Vector2(settings.scale_pivot[0], settings.scale_pivot[1])
	var shape: Dictionary = settings.reference_landform.duplicate(true)
	for key in ["coast_center", "plateau_center"]: shape[key] = _scaled_xz(shape[key])
	for key in ["coast_radii", "plateau_radii"]:
		shape[key] = [float(shape[key][0])*geometry_scale, float(shape[key][1])*geometry_scale]
	for key in ["coast_warp", "shore_width", "slope_run", "harbor_blend", "beach_run", "entrance_blend", "entrance_inside_fade_start", "entrance_inside_fade_end"]:
		shape[key] = float(shape[key])*geometry_scale
	for key in ["lowland_height", "plateau_height"]: shape[key] = _scaled_elevation(float(shape[key]))
	shape.hill_amplitude = float(shape.hill_amplitude)*elevation_scale
	settings.landform = shape
	settings.grid_start = _scaled_xz(settings.reference_grid_start)
	settings.grid_step = float(settings.reference_grid_step)*geometry_scale
	var port: Dictionary = settings.reference_harbor
	var xz := _scaled_xz([port.center[0], port.center[2]])
	settings.harbor.center = [xz[0], _scaled_elevation(float(port.center[1])), xz[1]]
	settings.harbor.size = [float(port.size[0])*geometry_scale, float(port.size[1])*geometry_scale]
	settings.harbor.spawn = [xz[0], _scaled_elevation(float(port.center[1]))+2.0, xz[1]]
	# Imported harbor coordinates are absolute, independent of mountain scaling.
	var asset: Dictionary = settings.get("harbor_asset", {})
	if bool(asset.get("enabled", false)):
		settings.harbor.center = asset.center.duplicate()
		settings.harbor.size = asset.size.duplicate()
		settings.harbor.spawn = asset.spawn.duplicate()
		settings.harbor.status = "imported_harbor_city"
		if asset.has("terrain_extent"):
			var extent: Array = asset.terrain_extent
			var step := float(settings.grid_step)
			var previous_start := Vector2(settings.grid_start[0], settings.grid_start[1])
			var previous_end := previous_start+Vector2(settings.grid_cells[0], settings.grid_cells[1])*step
			var start := Vector2(minf(previous_start.x, floorf(float(extent[0])/step)*step), minf(previous_start.y, floorf(float(extent[1])/step)*step))
			var end := Vector2(maxf(previous_end.x, float(extent[2])), maxf(previous_end.y, float(extent[3])))
			settings.grid_start = [start.x, start.y]
			settings.grid_cells = [ceili((end.x-start.x)/step), ceili((end.y-start.y)/step)]

func _analytic_height(at: Vector2, road: Vector4) -> float:
	var shape: Dictionary = settings.landform
	var noise_at := scale_pivot+(at-scale_pivot)/geometry_scale
	var noise := broad.get_noise_2d(noise_at.x, noise_at.y)
	var coast_center := Vector2(shape.coast_center[0], shape.coast_center[1])
	var coast_radii := Vector2(shape.coast_radii[0], shape.coast_radii[1])
	var warped := at + Vector2(broad.get_noise_2d(noise_at.x+911, noise_at.y-220), noise) * float(shape.coast_warp)
	var coast := _ellipse(warped, coast_center, coast_radii)
	var inland := smoothstep(0.0, 220.0*geometry_scale, coast)
	var lowland := float(shape.lowland_height)
	var coast_top := float(settings.reference_landform.lowland_height) if settings.has("reference_landform") else lowland
	var height := _scaled_elevation(lerpf(float(settings.sea_floor), coast_top, smoothstep(-float(shape.shore_width), 24.0*geometry_scale, coast)))
	var plateau_center := Vector2(shape.plateau_center[0], shape.plateau_center[1])
	var plateau_radii := Vector2(shape.plateau_radii[0], shape.plateau_radii[1])
	var outward := maxf(0.0, -_ellipse(at, plateau_center, plateau_radii))
	var highland := 1.0-smoothstep(0.0, float(shape.slope_run), outward)
	height += inland * highland * (float(shape.plateau_height)-lowland)
	# Broad hills disappear on the city plateau and at the waterline.
	var hill_weight := inland * smoothstep(50.0*geometry_scale, 300.0*geometry_scale, outward)
	height += hill_weight * (noise*float(shape.hill_amplitude) + detail.get_noise_2d(noise_at.x, noise_at.y)*1.5*elevation_scale)
	var harbor_xz := Vector2(harbor_center.x, harbor_center.z)
	var half_size := Vector2(settings.harbor.size[0], settings.harbor.size[1])*0.5
	var delta := (at-harbor_xz).abs()-half_size
	var distance := Vector2(maxf(delta.x, 0.0), maxf(delta.y, 0.0)).length()
	var imported_harbor := bool(settings.get("harbor_asset", {}).get("enabled", false))
	if not imported_harbor:
		height = lerpf(height, harbor_center.y, 1.0-smoothstep(0.0, float(shape.harbor_blend), distance))
	# The harbor's south frontage grades out to deep water over a broad beach.
	var beach_start := harbor_center.z+half_size.y
	var beach_end := beach_start+float(shape.beach_run)
	var beach_width := 1.0-smoothstep(half_size.x*0.75, half_size.x+130.0*geometry_scale, absf(at.x-harbor_center.x))
	if at.y > beach_start and not imported_harbor:
		var shore_height := lerpf(harbor_center.y, float(settings.sea_floor), smoothstep(beach_start, beach_end, at.y))
		height = lerpf(height, shore_height, beach_width)
	height = _terraced_height(at, height, road)
	# Touch the real doorway with earth; no bridge or separately raised road shelf.
	var entrance_distance := at.distance_to(Vector2(city_entrance.x, city_entrance.z))
	var entrance_weight := 1.0-smoothstep(15.0, float(shape.entrance_blend), entrance_distance)
	# Taper back below the interior streets; the approach belongs outside the gate.
	entrance_weight *= smoothstep(-float(shape.entrance_inside_fade_end), -float(shape.entrance_inside_fade_start), at.y-city_entrance.z)
	height = lerpf(height, city_entrance.y-0.08, entrance_weight)
	height = _harbor_asset_height(at, height)
	return maxf(float(settings.sea_floor), height)

func _harbor_asset_height(at: Vector2, original: float) -> float:
	var asset: Dictionary = settings.get("harbor_asset", {})
	if not bool(asset.get("enabled", false)): return original
	var height := original
	for patch in asset.get("terrain_patches", []):
		var center := Vector2(patch.center[0], patch.center[1])
		var half_size := Vector2(patch.size[0], patch.size[1])*0.5
		var delta := (at-center).abs()-half_size
		var distance := Vector2(maxf(delta.x, 0.0), maxf(delta.y, 0.0)).length()
		var weight := 1.0-smoothstep(0.0, float(patch.blend), distance)
		var target := float(patch.height)
		if str(patch.get("mode", "cap")) == "cap": target = minf(height, target)
		height = lerpf(height, target, weight)
	var paths: Array = asset.get("access_routes", []).duplicate()
	paths.append({"points": asset.get("approach_route", []), "half_width": asset.get("approach_half_width", 12.0), "blend": asset.get("approach_blend", 20.0)})
	for path in paths:
		var points: Array = path.points
		for i in range(points.size()-1):
			var a := Vector2(points[i][0], points[i][2])
			var b := Vector2(points[i+1][0], points[i+1][2])
			var segment := b-a
			var t := clampf((at-a).dot(segment)/maxf(segment.length_squared(), 0.001), 0.0, 1.0)
			var distance := at.distance_to(a+segment*t)
			var half_width := float(path.half_width)
			var weight := 1.0-smoothstep(half_width, half_width+float(path.blend), distance)
			var level := lerpf(float(points[i][1]), float(points[i+1][1]), t)
			height = lerpf(height, level, weight)
	return height

func _terraced_height(at: Vector2, original: float, road: Vector4) -> float:
	var spec: Dictionary = settings.get("terrace_road", {})
	if not bool(spec.get("enabled", false)): return original
	var minimum := Vector2(spec.city_protection_min[0], spec.city_protection_min[1])
	var maximum := Vector2(spec.city_protection_max[0], spec.city_protection_max[1])
	if at.x >= minimum.x and at.x <= maximum.x and at.y >= minimum.y and at.y <= maximum.y:
		return original
	var nearest := Vector2(road.z, road.w)
	var outward := (at-nearest).dot((nearest-Vector2(city_center.x, city_center.z)).normalized())
	var blend := float(spec.outward_blend) if outward >= 0.0 else float(spec.inward_blend)
	var half_width := float(spec.half_width)
	var weight := 1.0-smoothstep(half_width, half_width+blend, road.x)
	var height := lerpf(original, road.y, weight)
	for site in settings.get("battle_reservations", []):
		var center := Vector2(site.center[0], site.center[2])
		var delta := at-center
		var angle := atan2(delta.y, delta.x)+float(site.shape_phase)
		# A generous clear circle remains inside a softly irregular rock shelf.
		var radius := float(site.clear_radius)*(1.10+0.06*sin(angle*3.0)+0.04*sin(angle*5.0))
		var outer_side := delta.dot((center-Vector2(city_center.x, city_center.z)).normalized()) >= 0.0
		var rim := float(site.outer_blend) if outer_side else float(site.inner_blend)
		var shelf_weight := 1.0-smoothstep(radius, radius+rim, delta.length())
		height = lerpf(height, float(site.center[1]), shelf_weight)
	return height

func _route_sample(at: Vector2) -> Vector4:
	if _revision_v8 and _roads_v8 != null:
		var sampled: Dictionary = _roads_v8.sample(at)
		var nearest: Vector2 = sampled.nearest
		return Vector4(float(sampled.distance), float(sampled.height), nearest.x, nearest.y)
	var closest := INF
	var level := 226.0
	var nearest := Vector2.ZERO
	for i in range(route.size()-1):
		var a := Vector2(route[i].x, route[i].z)
		var b := Vector2(route[i+1].x, route[i+1].z)
		var delta := b-a
		var t := clampf((at-a).dot(delta)/delta.length_squared(), 0.0, 1.0)
		var distance := at.distance_to(a+delta*t)
		if distance < closest:
			closest = distance
			level = lerpf(route[i].y, route[i+1].y, t)
			nearest = a+delta*t
	for spur in settings.get("terrace_spurs", []):
		var a := Vector2(spur.from[0], spur.from[2])
		var b := Vector2(spur.to[0], spur.to[2])
		var delta := b-a
		var t := clampf((at-a).dot(delta)/delta.length_squared(), 0.0, 1.0)
		var distance := at.distance_to(a+delta*t)
		if distance < closest:
			closest = distance
			level = lerpf(float(spur.from[1]), float(spur.to[1]), t)
			nearest = a+delta*t
	return Vector4(closest, level, nearest.x, nearest.y)

func _make_material() -> void:
	_material = ShaderMaterial.new()
	if _revision_v8:
		_material.shader = preload("res://assets/worlds/star_orchard/procedural_main_v1/ground_v8.gdshader")
	else:
		_material.shader = preload("res://assets/worlds/star_orchard/procedural_main_v1/ground.gdshader")
	var grass := Textures.texture("orchard_meadow_generated.png")
	_material.set_shader_parameter("base_texture", grass)
	_material.set_shader_parameter("grass", grass)
	_material.set_shader_parameter("soil", Textures.texture("orchard_soil_generated.png"))
	_material.set_shader_parameter("cliff_texture", Textures.asset_texture("res://assets/worlds/star_orchard/coastal_art_v2/cliff_gray_violet_v1.png"))
	_material.set_shader_parameter("plaza_enabled", false)


func _grid_height(x: int, z: int) -> float:
	return heights[clampi(z, 0, grid_cells.y)*(grid_cells.x+1)+clampi(x, 0, grid_cells.x)]

func _build_chunk(start: Vector2i) -> void:
	var cells := Vector2i(mini(CHUNK_CELLS, grid_cells.x-start.x), mini(CHUNK_CELLS, grid_cells.y-start.y))
	var width := cells.x+1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var highest := 190.0
	for z in range(cells.y+1):
		for x in range(cells.x+1):
			var gx := start.x+x
			var gz := start.y+z
			var at := grid_start+Vector2(gx, gz)*grid_step
			var h := _grid_height(gx, gz)
			highest = maxf(highest, h)
			vertices.append(Vector3(at.x, h, at.y))
			var dx := _grid_height(gx+1, gz)-_grid_height(gx-1, gz)
			var dz := _grid_height(gx, gz+1)-_grid_height(gx, gz-1)
			normals.append(Vector3(-dx, grid_step*2.0, -dz).normalized())
			var index := gz * (grid_cells.x + 1) + gx
			var biome := _biomes[index] if _revision_v8 else Vector2.ZERO
			colors.append(Color(biome.x, trail_weights[index], biome.y, 1.0))
			uvs.append(at*0.01)
	# The world's broad sea-floor collider supplies fully flat ocean chunks.
	if highest <= 190.01: return
	for z in cells.y:
		for x in cells.x:
			var a := z*width+x
			indices.append_array(PackedInt32Array([a, a+1, a+width, a+1, a+width+1, a+width]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var display := MeshInstance3D.new()
	display.name = "Landscape_%d_%d" % [start.x, start.y]
	display.mesh = mesh
	add_child(display)
	display.create_trimesh_collision()


func _prepare_revision(count: int) -> void:
	_landform_v8 = LandformV8.new()
	_landform_v8.configure(settings.sculpted_landform, float(settings.sea_level), float(settings.sea_floor))
	_roads_v8 = RoadsV8.new()
	_roads_v8.configure(settings.mountain_route, settings.terrace_road, settings.terrace_spurs)
	settings.sampled_mountain_route = _roads_v8.baked_main_points()
	settings.sampled_terrace_spurs = _roads_v8.baked_spur_points()
	_biomes.resize(count)
	var protection: Dictionary = settings.terrain_protection
	_protection_caps = FileAccess.get_file_as_bytes(str(protection.caps)).to_float32_array()
	_support_heights = FileAccess.get_file_as_bytes(str(protection.support_heights)).to_float32_array()
	_support_weights = FileAccess.get_file_as_bytes(str(protection.support_weights)).to_float32_array()
	if _protection_caps.size() != count or _support_heights.size() != count or _support_weights.size() != count:
		push_error("Orchard v8 city protection grid is incomplete; city terrain is lowered for safety.")
		_protection_caps.resize(count)
		_protection_caps.fill(INF)
		_support_heights.resize(count)
		_support_weights.resize(count)
		_support_weights.fill(0.0)
		# Missing profile data must never create solid earth across imported streets.
		for z in range(grid_cells.y + 1):
			for x in range(grid_cells.x + 1):
				var at := grid_start + Vector2(x, z) * grid_step
				if Rect2(730, -1154, 768, 653).has_point(at) or Rect2(730, -280, 690, 675).has_point(at):
					_protection_caps[z * (grid_cells.x + 1) + x] = float(settings.sea_floor)


func _revised_height(at: Vector2, road: Dictionary, index: int) -> float:
	var height: float = _landform_v8.height_at(at)
	# Footprint-derived shoulders are part of this same surface and collision mesh.
	height = maxf(height, lerpf(height, _support_heights[index], _support_weights[index]))
	height = _reservation_height_v8(at, height)
	height = _roads_v8.apply_height(at, height, road)
	# A small apron meets the real gate; no broad raised disk crosses the low plaza.
	var gate := Vector2(city_entrance.x, city_entrance.z)
	var apron := 1.0 - smoothstep(12.0, 30.0, at.distance_to(gate))
	apron *= smoothstep(-5.0, 1.0, at.y - gate.y)
	height = lerpf(height, city_entrance.y - 0.08, apron)
	height = _swim_landing_height_v8(at, height)
	# Imported streets and thresholds have final authority, including at junctions.
	height = minf(height, _protection_caps[index])
	# The imported entrance paving sits above a low, clipped terrain pocket.
	# Bring the mountain up to the underside of its foreground platforms.
	# Keep the top below the lowest authored slab and taper into the old slope.
	var entry_outside := maxf(absf(at.x - 1080.0) - 70.0, absf(at.y + 550.0) - 40.0)
	var entry_support := 1.0 - smoothstep(0.0, 14.0, entry_outside)
	height = maxf(height, lerpf(height, 310.25, entry_support))
	return maxf(float(settings.sea_floor), height)


func _reservation_height_v8(at: Vector2, original: float) -> float:
	var height := original
	for site in settings.battle_reservations:
		var center := Vector2(site.center[0], site.center[2])
		var delta := at - center
		var angle := atan2(delta.y, delta.x) + float(site.shape_phase)
		# The irregular outer lip never reduces the original clear circular interior.
		var radius := float(site.clear_radius) + 4.0 + 2.0 * sin(angle * 3.0) + 1.5 * sin(angle * 5.0)
		var blend := float(site.inner_blend)
		var amount := 1.0 - smoothstep(radius, radius + blend, delta.length())
		height = lerpf(height, float(site.center[1]), amount)
	return height


func _swim_landing_height_v8(at: Vector2, original: float) -> float:
	var asset: Dictionary = settings.harbor_asset
	var nearest := INF
	var target := original
	var amount := 0.0
	for access in asset.get("access_routes", []):
		var points: Array = access.points
		for i in range(points.size() - 1):
			var a := Vector2(points[i][0], points[i][2])
			var b := Vector2(points[i + 1][0], points[i + 1][2])
			var span := b - a
			var t := clampf((at - a).dot(span) / maxf(span.length_squared(), 0.001), 0.0, 1.0)
			var distance := at.distance_to(a + span * t)
			if distance >= nearest: continue
			nearest = distance
			target = lerpf(float(points[i][1]), float(points[i + 1][1]), t)
			amount = 1.0 - smoothstep(float(access.half_width), float(access.half_width) + float(access.blend), distance)
	return lerpf(original, target, amount)

func _paint_access_trails() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/orchard_forest_sample_20260926.json"))
	for path in spec.get("access_paths",[]):
		var points: Array = path.path
		var half_width: float = path.half_width
		for i in range(points.size()-1):
			var a := Vector2(points[i][0],points[i][1])
			var b := Vector2(points[i+1][0],points[i+1][1])
			var span := b-a
			var bounds := Rect2(a,Vector2.ZERO).expand(b).grow(half_width+grid_step)
			var first := Vector2i(((bounds.position-grid_start)/grid_step).floor()).max(Vector2i.ZERO)
			var last := Vector2i(((bounds.end-grid_start)/grid_step).ceil()).min(grid_cells)
			for z in range(first.y,last.y+1):
				for x in range(first.x,last.x+1):
					var at := grid_start+Vector2(x,z)*grid_step
					var t := clampf((at-a).dot(span)/maxf(span.length_squared(),0.001),0.0,1.0)
					var distance := at.distance_to(a+span*t)
					var weight := 1.0-smoothstep(half_width-2.0,half_width+3.0,distance)
					var index := z*(grid_cells.x+1)+x
					trail_weights[index]=maxf(trail_weights[index],weight)
