extends RefCounted
## Authored landform in final world coordinates. Roads and imported city surfaces
## are applied by OrchardProceduralLandscape after this height field is sampled.


class PolygonField:
	extends RefCounted

	var points: PackedVector2Array = PackedVector2Array()
	var vectors: PackedVector2Array = PackedVector2Array()
	var lengths_squared: PackedFloat32Array = PackedFloat32Array()
	var bounds: Rect2 = Rect2()

	func configure(rows: Array) -> void:
		points.clear()
		vectors.clear()
		lengths_squared.clear()
		for value in rows:
			var row: Array = value
			if row.size() >= 2:
				points.append(Vector2(float(row[0]), float(row[1])))
		if points.is_empty():
			return
		bounds = Rect2(points[0], Vector2.ZERO)
		for index in range(points.size()):
			bounds = bounds.expand(points[index])
			var edge: Vector2 = points[(index + 1) % points.size()] - points[index]
			vectors.append(edge)
			lengths_squared.append(maxf(edge.length_squared(), 0.0001))

	## Positive distance is inland. The other components identify the nearest
	## authored coast edge and its interpolation amount for the shore profile.
	func sample(at: Vector2) -> Vector3:
		var inside: bool = false
		var nearest_squared: float = INF
		var nearest_edge: int = 0
		var nearest_t: float = 0.0
		for index in range(points.size()):
			var start: Vector2 = points[index]
			var edge: Vector2 = vectors[index]
			var finish: Vector2 = start + edge
			var along: float = clampf((at - start).dot(edge) / lengths_squared[index], 0.0, 1.0)
			var distance_squared: float = at.distance_squared_to(start + edge * along)
			if distance_squared < nearest_squared:
				nearest_squared = distance_squared
				nearest_edge = index
				nearest_t = along
			if (start.y > at.y) != (finish.y > at.y):
				var crossing_x: float = start.x + edge.x * (at.y - start.y) / edge.y
				if at.x < crossing_x:
					inside = not inside
		var distance: float = sqrt(nearest_squared)
		return Vector3(distance if inside else -distance, float(nearest_edge), nearest_t)


class ShelfField:
	extends RefCounted

	var polygon: PolygonField = PolygonField.new()
	var sample_bounds: Rect2 = Rect2()
	var center: Vector2 = Vector2.ZERO
	var tilt: Vector2 = Vector2.ZERO
	var height: float = 270.0
	var blend: float = 24.0
	var rock_strength: float = 0.65


var _sea_level: float = 220.0
var _sea_floor: float = 190.0
var _offshore_run: float = 36.0
var _base_height: float = 271.0
var _base_south_z: float = -235.0
var _base_gradient: float = 0.16
var _base_cap: float = 310.0
var _height_cap: float = 349.0
var _east_drop: float = 26.0
var _coast: PolygonField = PolygonField.new()
var _coast_bounds: Rect2 = Rect2()
var _coast_runs: PackedFloat32Array = PackedFloat32Array()
var _beach_runs: PackedFloat32Array = PackedFloat32Array()
var _shelves: Array[ShelfField] = []
var _wall_crest: Array[Vector4] = []
var _wall_toe_height: float = 332.0
var _wall_edge_fade: float = 40.0

# Flattened segment caches keep JSON and polyline conversion out of height_at.
var _ridge_starts: PackedVector2Array = PackedVector2Array()
var _ridge_vectors: PackedVector2Array = PackedVector2Array()
var _ridge_lengths_squared: PackedFloat32Array = PackedFloat32Array()
var _ridge_start_heights: PackedFloat32Array = PackedFloat32Array()
var _ridge_height_deltas: PackedFloat32Array = PackedFloat32Array()
var _ridge_widths: PackedFloat32Array = PackedFloat32Array()
var _ridge_bounds: Array[Rect2] = []
var _valley_starts: PackedVector2Array = PackedVector2Array()
var _valley_vectors: PackedVector2Array = PackedVector2Array()
var _valley_lengths_squared: PackedFloat32Array = PackedFloat32Array()
var _valley_widths: PackedFloat32Array = PackedFloat32Array()
var _valley_depths: PackedFloat32Array = PackedFloat32Array()
var _valley_bounds: Array[Rect2] = []


func configure(spec: Dictionary, sea_level: float, sea_floor: float) -> void:
	_sea_level = sea_level
	_sea_floor = sea_floor
	_offshore_run = maxf(float(spec.get("offshore_run", 36.0)), 1.0)
	var base: Dictionary = spec.get("base_slope", {})
	_base_height = float(base.get("south_height", 271.0))
	_base_south_z = float(base.get("south_z", -235.0))
	_base_gradient = float(base.get("north_gradient", 0.16))
	_base_cap = float(base.get("north_height_cap", 310.0))
	_east_drop = float(base.get("east_bay_drop", 26.0))
	_height_cap = float(spec.get("maximum_height", 349.0))
	var coast_rows: Array = spec.get("coastline", [])
	_coast.configure(coast_rows)
	_coast_bounds = _coast.bounds.grow(_offshore_run)
	_coast_runs.clear()
	_beach_runs.clear()
	for value in coast_rows:
		var row: Array = value
		if row.size() < 2:
			continue
		_coast_runs.append(maxf(float(row[2]) if row.size() > 2 else 28.0, 8.0))
		_beach_runs.append(maxf(float(row[3]) if row.size() > 3 else 1.0, 0.0))
	_shelves.clear()
	for value in spec.get("shoulder_shelves", []):
		var item: Dictionary = value
		var shelf: ShelfField = ShelfField.new()
		var rows: Array = item.get("polygon", [])
		shelf.polygon.configure(rows)
		if shelf.polygon.points.size() < 3:
			continue
		shelf.height = float(item.get("height", 270.0))
		shelf.blend = maxf(float(item.get("blend", 24.0)), 1.0)
		shelf.rock_strength = clampf(float(item.get("rock_strength", 0.65)), 0.0, 1.0)
		var center: Array = item.get("center", [0.0, 0.0])
		var tilt: Array = item.get("tilt", [0.0, 0.0])
		shelf.center = Vector2(float(center[0]), float(center[1]))
		shelf.tilt = Vector2(float(tilt[0]), float(tilt[1]))
		shelf.sample_bounds = shelf.polygon.bounds.grow(shelf.blend + 12.0)
		_shelves.append(shelf)
	_configure_ridges(spec.get("ridges", []))
	_configure_valleys(spec.get("valleys", []))
	_configure_backdrop_wall(spec.get("backdrop_wall", {}))


func height_at(at: Vector2) -> float:
	if _coast.points.size() < 3 or not _coast_bounds.has_point(at):
		return _sea_floor
	var coast_sample: Vector3 = _coast.sample(at)
	var inland: float = coast_sample.x
	var shoreline: float = _sea_level - 0.6
	if inland <= 0.0:
		return lerpf(_sea_floor, shoreline, _smooth(-_offshore_run, 0.0, inland))
	var height: float = minf(_base_height + (_base_south_z - at.y) * _base_gradient, _base_cap)
	# The southeastern flank falls into the harbor bay; this removes the old
	# broad, uniformly high apron while preserving the central climbing route.
	height -= _east_drop * _smooth(1245.0, 1465.0, at.x) * (1.0 - _smooth(345.0, 610.0, -at.y))
	height -= 8.0 * (1.0 - _smooth(730.0, 910.0, at.x)) * (1.0 - _smooth(440.0, 720.0, -at.y))
	height = maxf(height, _sea_level + 4.0)
	for index in range(_ridge_starts.size()):
		if not _ridge_bounds[index].has_point(at):
			continue
		var start: Vector2 = _ridge_starts[index]
		var edge: Vector2 = _ridge_vectors[index]
		var along: float = clampf((at - start).dot(edge) / _ridge_lengths_squared[index], 0.0, 1.0)
		var distance: float = at.distance_to(start + edge * along)
		var influence: float = 1.0 - _smooth(0.0, _ridge_widths[index], distance)
		if influence <= 0.0:
			continue
		var crest: float = _ridge_start_heights[index] + _ridge_height_deltas[index] * along
		# Max prevents overlapping ribs from stacking into an unintended peak.
		height = maxf(height, lerpf(height, crest, influence))
	for shelf in _shelves:
		if not shelf.sample_bounds.has_point(at):
			continue
		var edge_distance: float = shelf.polygon.sample(at).x
		var shelf_weight: float = _smooth(-shelf.blend, 3.0, edge_distance)
		var shelf_height: float = shelf.height + (at - shelf.center).dot(shelf.tilt)
		height = lerpf(height, shelf_height, shelf_weight)
	height -= _valley_depth_at(at)
	# A short, deliberately shaped rock wall closes the old empty northern
	# plateau. City floor caps still have final authority in the shared grid.
	height = maxf(height, _backdrop_height(at, height))
	height = clampf(height, _sea_level + 2.0, _height_cap)
	var edge_index: int = int(coast_sample.y)
	var next_index: int = (edge_index + 1) % _coast_runs.size()
	var cliff_run: float = lerpf(_coast_runs[edge_index], _coast_runs[next_index], coast_sample.z)
	var beach_run: float = lerpf(_beach_runs[edge_index], _beach_runs[next_index], coast_sample.z)
	var beach_top: float = _sea_level + 2.0
	if beach_run > 0.1 and inland < beach_run:
		return lerpf(shoreline, beach_top, _smooth(0.0, beach_run, inland))
	var slope_start: float = beach_top if beach_run > 0.1 else shoreline
	var cliff_t: float = clampf((inland - beach_run) / cliff_run, 0.0, 1.0)
	return lerpf(slope_start, height, _faceted_ramp(cliff_t))


## x: exposed rock shoulder; y: sheltered, slightly damp shallow valley.
## The terrain shader still determines the final rock coverage from slope.
func biome_at(at: Vector2) -> Vector2:
	if _coast.points.size() < 3 or not _coast_bounds.has_point(at):
		return Vector2.ZERO
	var coast_sample: Vector3 = _coast.sample(at)
	if coast_sample.x <= 0.0:
		return Vector2.ZERO
	var edge_index: int = int(coast_sample.y)
	var next_index: int = (edge_index + 1) % _coast_runs.size()
	var cliff_run: float = lerpf(_coast_runs[edge_index], _coast_runs[next_index], coast_sample.z)
	var beach_run: float = lerpf(_beach_runs[edge_index], _beach_runs[next_index], coast_sample.z)
	var rock: float = _smooth(beach_run, beach_run + 6.0, coast_sample.x)
	rock *= 1.0 - _smooth(beach_run + cliff_run - 5.0, beach_run + cliff_run + 10.0, coast_sample.x)
	rock *= 0.8 * (1.0 - clampf(beach_run / 36.0, 0.0, 0.65))
	for shelf in _shelves:
		if not shelf.sample_bounds.has_point(at):
			continue
		var distance: float = shelf.polygon.sample(at).x
		var exposed_edge: float = _smooth(-shelf.blend, -shelf.blend * 0.4, distance)
		exposed_edge *= 1.0 - _smooth(-2.0, 9.0, distance)
		rock = maxf(rock, exposed_edge * shelf.rock_strength)
	var damp: float = clampf(_valley_depth_at(at) / 17.0, 0.0, 1.0)
	damp *= _smooth(10.0, 35.0, coast_sample.x)
	if _backdrop_height(at, _base_cap) > _base_cap + 22.0:
		rock = maxf(rock, 0.96)
		damp = 0.0
	return Vector2(clampf(rock, 0.0, 1.0), damp)


func _configure_backdrop_wall(spec: Dictionary) -> void:
	_wall_crest.clear()
	if not bool(spec.get("enabled", false)):
		return
	_wall_toe_height = float(spec.get("front_toe_height", 332.0))
	_wall_edge_fade = maxf(float(spec.get("edge_fade", 40.0)), 1.0)
	var default_run: float = float(spec.get("front_run", 102.0))
	for value in spec.get("crest", []):
		var row: Array = value
		if row.size() >= 3:
			_wall_crest.append(Vector4(float(row[0]), float(row[1]), float(row[2]),
				maxf(float(row[3]) if row.size() >= 4 else default_run, 12.0)))


func _backdrop_height(at: Vector2, ground: float) -> float:
	if _wall_crest.size() < 2:
		return ground
	var first: Vector4 = _wall_crest[0]
	var last: Vector4 = _wall_crest[_wall_crest.size() - 1]
	if at.x < first.x or at.x > last.x:
		return ground
	for index in range(_wall_crest.size() - 1):
		var a: Vector4 = _wall_crest[index]
		var b: Vector4 = _wall_crest[index + 1]
		if at.x < a.x or at.x > b.x:
			continue
		var along: float = clampf((at.x - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
		var crest_z: float = lerpf(a.z, b.z, along)
		var run: float = lerpf(a.w, b.w, along)
		var progress: float = clampf((crest_z + run - at.y) / run, 0.0, 1.0)
		if progress <= 0.0:
			return ground
		var height: float = lerpf(a.y, b.y, along)
		# Three broad rock faces give each summit a sloping foot, steep middle
		# buttress and a narrow crest. The crest follows authored unequal peaks.
		var rise: float
		if progress < 0.26:
			rise = progress * (0.13 / 0.26)
		elif progress < 0.72:
			rise = 0.13 + (progress - 0.26) * (0.53 / 0.46)
		else:
			rise = 0.66 + (progress - 0.72) * (0.34 / 0.28)
		var toe: float = maxf(ground, _wall_toe_height)
		var wall: float = ground + (toe - ground) * _smooth(0.0, 0.18, progress)
		wall += (height - toe) * rise
		# Past the crest only a narrow shoulder remains; the authored coastline
		# immediately cuts the rear face down to the sea instead of another slope.
		wall -= clampf(crest_z - at.y, 0.0, 28.0) * 0.24
		var side_weight: float = _smooth(first.x, first.x + _wall_edge_fade, at.x)
		side_weight *= 1.0 - _smooth(last.x - _wall_edge_fade, last.x, at.x)
		return lerpf(ground, maxf(ground, wall), side_weight)
	return ground


func _configure_ridges(rows: Array) -> void:
	_ridge_starts.clear()
	_ridge_vectors.clear()
	_ridge_lengths_squared.clear()
	_ridge_start_heights.clear()
	_ridge_height_deltas.clear()
	_ridge_widths.clear()
	_ridge_bounds.clear()
	for value in rows:
		var item: Dictionary = value
		var points: Array = item.get("points", [])
		var width: float = maxf(float(item.get("width", 70.0)), 1.0)
		for index in range(points.size() - 1):
			var first: Array = points[index]
			var second: Array = points[index + 1]
			var start: Vector2 = Vector2(float(first[0]), float(first[2]))
			var finish: Vector2 = Vector2(float(second[0]), float(second[2]))
			_ridge_starts.append(start)
			_ridge_vectors.append(finish - start)
			_ridge_lengths_squared.append(maxf(start.distance_squared_to(finish), 0.0001))
			_ridge_start_heights.append(float(first[1]))
			_ridge_height_deltas.append(float(second[1]) - float(first[1]))
			_ridge_widths.append(width)
			_ridge_bounds.append(Rect2(start, Vector2.ZERO).expand(finish).grow(width))


func _configure_valleys(rows: Array) -> void:
	_valley_starts.clear()
	_valley_vectors.clear()
	_valley_lengths_squared.clear()
	_valley_widths.clear()
	_valley_depths.clear()
	_valley_bounds.clear()
	for value in rows:
		var item: Dictionary = value
		var points: Array = item.get("points", [])
		var width: float = maxf(float(item.get("width", 40.0)), 1.0)
		var depth: float = maxf(float(item.get("depth", 14.0)), 0.0)
		for index in range(points.size() - 1):
			var first: Array = points[index]
			var second: Array = points[index + 1]
			var start: Vector2 = Vector2(float(first[0]), float(first[1]))
			var finish: Vector2 = Vector2(float(second[0]), float(second[1]))
			_valley_starts.append(start)
			_valley_vectors.append(finish - start)
			_valley_lengths_squared.append(maxf(start.distance_squared_to(finish), 0.0001))
			_valley_widths.append(width)
			_valley_depths.append(depth)
			_valley_bounds.append(Rect2(start, Vector2.ZERO).expand(finish).grow(width))


func _valley_depth_at(at: Vector2) -> float:
	var depth: float = 0.0
	for index in range(_valley_starts.size()):
		if not _valley_bounds[index].has_point(at):
			continue
		var start: Vector2 = _valley_starts[index]
		var edge: Vector2 = _valley_vectors[index]
		var along: float = clampf((at - start).dot(edge) / _valley_lengths_squared[index], 0.0, 1.0)
		var distance: float = at.distance_to(start + edge * along)
		var weight: float = 1.0 - _smooth(0.0, _valley_widths[index], distance)
		# Junctions keep the deepest single cut, avoiding seams from stacked cuts.
		depth = maxf(depth, _valley_depths[index] * weight)
	return depth


func _smooth(from: float, to: float, value: float) -> float:
	var amount: float = clampf((value - from) / maxf(to - from, 0.0001), 0.0, 1.0)
	return amount * amount * (3.0 - 2.0 * amount)


func _faceted_ramp(amount: float) -> float:
	# Three broad faces provide a toe, a cliff face and a short shoulder bevel.
	if amount < 0.15:
		return amount * (0.08 / 0.15)
	if amount < 0.82:
		return 0.08 + (amount - 0.15) * (0.84 / 0.67)
	return 0.92 + (amount - 0.82) * (0.08 / 0.18)
