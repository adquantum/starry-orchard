extends RefCounted
## Cached road geometry. All coordinates and widths are actual world units.
## The terrain owner uses this result for its one shared mesh/collision grid.

var route_length := 0.0
var _routes: Array[Dictionary] = []
var _segments: Array[Dictionary] = []
var _buckets: Dictionary = {}
var _reservations: Array[Dictionary] = []
var _bucket_size := 36.0
var _enabled := true
var _junction_blend := 16.0
var _junction_run := 65.0


func configure(main_points: Array, road_spec: Dictionary, spurs: Array) -> void:
	_routes.clear()
	_segments.clear()
	_buckets.clear()
	_reservations.clear()
	route_length = 0.0
	_enabled = bool(road_spec.get("enabled", true))
	_bucket_size = maxf(16.0, float(road_spec.get("bucket_size", 36.0)))
	_junction_blend = maxf(4.0, float(road_spec.get("junction_blend", 16.0)))
	_junction_run = maxf(20.0, float(road_spec.get("junction_run", 65.0)))
	if main_points.size() < 2:
		return
	var main := _bake_route(main_points, road_spec, 0)
	_routes.append(main)
	route_length = float(main.length)
	for raw in spurs:
		var spur: Dictionary = raw
		var controls: Array = spur.get("points", []).duplicate(true)
		if controls.is_empty() and spur.has("from") and spur.has("to"):
			controls = [spur["from"], spur["to"]]
		if controls.size() < 2:
			continue
		# The attachment uses the baked main line, including its true arc height.
		var attachment := _nearest_on_route(_xz(controls[0]), main)
		var attached_at: Vector2 = attachment.nearest
		controls[0] = [attached_at.x, float(attachment.height), attached_at.y]
		var profile: Dictionary = road_spec.duplicate(true)
		profile.merge(spur, true)
		var route_id := _routes.size()
		var branch := _bake_route(controls, profile, route_id)
		branch["id"] = str(spur.get("id", "spur_%d" % route_id))
		_routes.append(branch)
		var clear_radius := float(spur.get("terminal_clear_radius", 0.0))
		if clear_radius > 0.0:
			_reservations.append({
				"center": _xz(controls.back()),
				"radius": clear_radius,
				"blend": float(spur.get("terminal_protection_blend", 8.0))
			})
	for route in _routes:
		_index_route(route)


func sample(at: Vector2) -> Dictionary:
	var nearby: Array = _buckets.get(_bucket(at), [])
	if nearby.is_empty():
		return _empty_sample()
	var closest_by_section: Dictionary = {}
	for segment_id in nearby:
		var segment: Dictionary = _segments[int(segment_id)]
		var start: Vector2 = segment.a
		var delta: Vector2 = segment.delta
		var t := clampf((at - start).dot(delta) * float(segment.inverse_length_squared), 0.0, 1.0)
		var nearest := start + delta * t
		var distance_squared := at.distance_squared_to(nearest)
		if distance_squared > float(segment.reach_squared):
			continue
		var section_key := Vector2i(int(segment.route_id), int(segment.section_id))
		var current: Dictionary = closest_by_section.get(section_key, {})
		if not current.is_empty() and distance_squared >= float(current.distance_squared):
			continue
		closest_by_section[section_key] = {
			"distance_squared": distance_squared,
			"segment_id": int(segment_id),
			"t": t,
			"nearest": nearest
		}
	if closest_by_section.is_empty():
		return _empty_sample()
	var candidates: Array[Dictionary] = []
	var main: Dictionary = {}
	for section_key in closest_by_section:
		var nearest: Dictionary = closest_by_section[section_key]
		var segment: Dictionary = _segments[int(nearest.segment_id)]
		var route_id := int(segment.route_id)
		var route: Dictionary = _routes[route_id]
		var t := float(nearest.t)
		var direction: Vector2 = segment.mountain_a.lerp(segment.mountain_b, t)
		if direction.length_squared() < 0.001:
			direction = segment.mountain_a
		var candidate := {
			"distance": sqrt(float(nearest.distance_squared)),
			"height": lerpf(float(segment.height_a), float(segment.height_b), t),
			"nearest": nearest.nearest,
			"mountain_direction": direction.normalized(),
			"width": float(route.width),
			"mountain_run": float(route.mountain_run),
			"valley_run": float(route.valley_run),
			"cut_rise": float(route.cut_rise),
			"fill_drop": float(route.fill_drop),
			"shoulder": float(route.shoulder),
			"route_id": int(route_id),
			"along": lerpf(float(segment.along_a), float(segment.along_b), t)
		}
		candidates.append(candidate)
		if route_id == 0 and (main.is_empty() or float(candidate.distance) < float(main.distance)):
			main = candidate
	# A branch leaves the exact baked main surface gradually. Its shoulder cannot
	# overwrite a main-road core with a different longitudinal height.
	if not main.is_empty():
		for candidate in candidates:
			if int(candidate.route_id) == 0:
				continue
			var attachment_fade := 1.0 - smoothstep(_junction_run * 0.65, _junction_run, float(candidate.along))
			var across_fade := 1.0 - smoothstep(float(main.width), float(main.width) + _junction_blend, float(main.distance))
			candidate.height = lerpf(float(candidate.height), float(main.height), attachment_fade * across_fade)
	var selected: Dictionary = candidates[0]
	for candidate in candidates:
		if float(candidate.distance) < float(selected.distance):
			selected = candidate
	if not main.is_empty() and float(main.distance) <= float(main.width):
		selected = main
	var result: Dictionary = selected.duplicate()
	result["candidates"] = candidates
	return result


func apply_height(at: Vector2, original: float, road_sample: Dictionary) -> float:
	if not _enabled or float(road_sample.get("distance", INF)) == INF:
		return original
	var reservation_weight := 1.0
	for reservation in _reservations:
		var distance := at.distance_to(reservation.center)
		reservation_weight = minf(reservation_weight, smoothstep(float(reservation.radius), float(reservation.radius) + float(reservation.blend), distance))
	if reservation_weight <= 0.0:
		return original
	var closest_distance := float(road_sample.distance)
	var core_width := float(road_sample.width)
	if closest_distance <= core_width:
		return lerpf(original, float(road_sample.height), reservation_weight)
	var candidates: Array = road_sample.get("candidates", [road_sample])
	var weighted_target := 0.0
	var total_weight := 0.0
	var strongest_weight := 0.0
	for candidate in candidates:
		var profile := _profile(at, original, candidate)
		var weight := profile.y
		# Resolve all intersecting shoulders together, once, rather than applying
		# a series of destructive road-height overwrites.
		var contribution := weight * weight * weight
		weighted_target += profile.x * contribution
		total_weight += contribution
		strongest_weight = maxf(strongest_weight, weight)
	if total_weight <= 0.000001:
		return original
	var primary := _profile(at, original, road_sample)
	# Preserve continuity at the exact edge of the flat driving surface.
	var junction_mix := smoothstep(core_width, core_width + 6.0, closest_distance)
	var target := lerpf(primary.x, weighted_target / total_weight, junction_mix)
	return lerpf(original, target, strongest_weight * reservation_weight)


func baked_main_points() -> Array:
	if _routes.is_empty():
		return []
	return _export_points(_routes[0])


func baked_spur_points() -> Array:
	var result: Array = []
	for index in range(1, _routes.size()):
		var route: Dictionary = _routes[index]
		result.append({"id": route.id, "points": _export_points(route), "half_width": float(route.width)})
	return result


func _profile(at: Vector2, original: float, candidate: Dictionary) -> Vector2:
	var distance := float(candidate.distance)
	var width := float(candidate.width)
	var level := float(candidate.height)
	if distance <= width:
		return Vector2(level, 1.0)
	var nearest: Vector2 = candidate.nearest
	var mountain_direction: Vector2 = candidate.mountain_direction
	var mountain_side := smoothstep(-2.0, 2.0, (at - nearest).dot(mountain_direction))
	var run := lerpf(float(candidate.valley_run), float(candidate.mountain_run), mountain_side)
	var beyond := distance - width
	if beyond >= run:
		return Vector2(original, 0.0)
	var shoulder := float(candidate.shoulder)
	var valley_drop := float(candidate.fill_drop) * smoothstep(shoulder, maxf(shoulder + 1.0, run * 0.80), beyond)
	var mountain_rise := float(candidate.cut_rise) * smoothstep(0.0, run * 0.75, beyond)
	var target := level + lerpf(-valley_drop, mountain_rise, mountain_side)
	# A broad uphill apron carries the cut; the valley has a short shoulder and
	# then a descending grade. Both blend to the landform within finite bounds.
	var influence := 1.0 - smoothstep(0.0, run, beyond)
	return Vector2(target, influence)


func _bake_route(raw_points: Array, profile: Dictionary, route_id: int) -> Dictionary:
	var controls: Array[Vector3] = []
	for point in raw_points:
		controls.append(_xyz(point))
	var curve := Curve3D.new()
	var spacing := maxf(1.0, float(profile.get("bake_spacing", 3.0)))
	curve.bake_interval = spacing * 0.5
	var tension := clampf(float(profile.get("curve_tension", 0.22)), 0.0, 0.32)
	for index in range(controls.size()):
		var planar := Vector3(controls[index].x, 0.0, controls[index].z)
		var previous := Vector3(controls[maxi(0, index - 1)].x, 0.0, controls[maxi(0, index - 1)].z)
		var following := Vector3(controls[mini(controls.size() - 1, index + 1)].x, 0.0, controls[mini(controls.size() - 1, index + 1)].z)
		var incoming_length := planar.distance_to(previous)
		var outgoing_length := planar.distance_to(following)
		var handle_length := minf(incoming_length, outgoing_length) * tension
		if index == 0:
			handle_length = outgoing_length * tension
		elif index == controls.size() - 1:
			handle_length = incoming_length * tension
		var tangent := (following - previous).normalized() * handle_length
		curve.add_point(planar, -tangent, tangent)
	var length := curve.get_baked_length()
	var knots := PackedFloat32Array()
	var values := PackedFloat32Array()
	for point in controls:
		knots.append(curve.get_closest_offset(Vector3(point.x, 0.0, point.z)))
		values.append(point.y)
	knots[0] = 0.0
	knots[knots.size() - 1] = length
	var slopes := _monotone_slopes(knots, values)
	var directions: Array = profile.get("mountain_directions", [])
	var points := PackedVector3Array()
	var offsets := PackedFloat32Array()
	var uphill := PackedVector2Array()
	var sections := PackedInt32Array()
	var count := maxi(1, ceili(length / spacing))
	var knot_index := 0
	for index in range(count + 1):
		var offset := length * float(index) / float(count)
		while knot_index < knots.size() - 2 and offset > knots[knot_index + 1]:
			knot_index += 1
		var point := curve.sample_baked(offset)
		point.y = _monotone_value(offset, knot_index, knots, values, slopes)
		points.append(point)
		offsets.append(offset)
		sections.append(knot_index)
		# These are authored terrain-side vectors, never directions from city center.
		var direction := Vector2(0.0, -1.0)
		if not directions.is_empty():
			var raw_direction: Array = directions[mini(knot_index, directions.size() - 1)]
			direction = Vector2(raw_direction[0], raw_direction[1]).normalized()
			if knot_index + 1 < directions.size():
				var next_raw: Array = directions[knot_index + 1]
				var next_direction := Vector2(next_raw[0], next_raw[1]).normalized()
				var turn_blend := smoothstep(0.65, 1.0, (offset - knots[knot_index]) / maxf(0.001, knots[knot_index + 1] - knots[knot_index]))
				direction = direction.lerp(next_direction, turn_blend).normalized()
		uphill.append(direction)
	return {
		"route_id": route_id,
		"curve": curve,
		"points": points,
		"offsets": offsets,
		"uphill": uphill,
		"sections": sections,
		"length": length,
		"width": float(profile.get("half_width", 10.0)),
		"mountain_run": float(profile.get("mountain_run", 54.0)),
		"valley_run": float(profile.get("valley_run", 30.0)),
		"cut_rise": float(profile.get("cut_rise", 15.0)),
		"fill_drop": float(profile.get("fill_drop", 19.0)),
		"shoulder": float(profile.get("shoulder", 3.0))
	}


func _monotone_slopes(knots: PackedFloat32Array, values: PackedFloat32Array) -> PackedFloat32Array:
	var slopes := PackedFloat32Array()
	slopes.resize(values.size())
	var intervals := PackedFloat32Array()
	var secants := PackedFloat32Array()
	for index in range(values.size() - 1):
		var interval := maxf(0.001, knots[index + 1] - knots[index])
		intervals.append(interval)
		secants.append((values[index + 1] - values[index]) / interval)
	slopes[0] = secants[0]
	slopes[slopes.size() - 1] = secants[secants.size() - 1]
	for index in range(1, values.size() - 1):
		var before := secants[index - 1]
		var after := secants[index]
		if before * after <= 0.0:
			slopes[index] = 0.0
		else:
			var w1 := 2.0 * intervals[index] + intervals[index - 1]
			var w2 := intervals[index] + 2.0 * intervals[index - 1]
			slopes[index] = (w1 + w2) / (w1 / before + w2 / after)
	return slopes


func _monotone_value(at: float, index: int, knots: PackedFloat32Array, values: PackedFloat32Array, slopes: PackedFloat32Array) -> float:
	var interval := maxf(0.001, knots[index + 1] - knots[index])
	var t := clampf((at - knots[index]) / interval, 0.0, 1.0)
	var t2 := t * t
	var t3 := t2 * t
	var value := (2.0 * t3 - 3.0 * t2 + 1.0) * values[index]
	value += (t3 - 2.0 * t2 + t) * interval * slopes[index]
	value += (-2.0 * t3 + 3.0 * t2) * values[index + 1]
	value += (t3 - t2) * interval * slopes[index + 1]
	return clampf(value, minf(values[index], values[index + 1]), maxf(values[index], values[index + 1]))


func _index_route(route: Dictionary) -> void:
	var points: PackedVector3Array = route.points
	var offsets: PackedFloat32Array = route.offsets
	var uphill: PackedVector2Array = route.uphill
	var sections: PackedInt32Array = route.sections
	var reach := float(route.width) + maxf(float(route.mountain_run), float(route.valley_run))
	for index in range(points.size() - 1):
		var a := Vector2(points[index].x, points[index].z)
		var b := Vector2(points[index + 1].x, points[index + 1].z)
		var delta := b - a
		var segment_id := _segments.size()
		_segments.append({
			"a": a, "delta": delta,
			"inverse_length_squared": 1.0 / maxf(0.00001, delta.length_squared()),
			"height_a": points[index].y, "height_b": points[index + 1].y,
			"mountain_a": uphill[index], "mountain_b": uphill[index + 1],
			"along_a": offsets[index], "along_b": offsets[index + 1],
			"route_id": route.route_id, "section_id": sections[index],
			"reach_squared": reach * reach
		})
		var minimum := _bucket(Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2.ONE * reach)
		var maximum := _bucket(Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2.ONE * reach)
		for y in range(minimum.y, maximum.y + 1):
			for x in range(minimum.x, maximum.x + 1):
				var key := Vector2i(x, y)
				if not _buckets.has(key):
					_buckets[key] = []
				_buckets[key].append(segment_id)


func _nearest_on_route(at: Vector2, route: Dictionary) -> Dictionary:
	var points: PackedVector3Array = route.points
	var closest := INF
	var result := {"nearest": Vector2.ZERO, "height": 0.0}
	for index in range(points.size() - 1):
		var a := Vector2(points[index].x, points[index].z)
		var b := Vector2(points[index + 1].x, points[index + 1].z)
		var delta := b - a
		var t := clampf((at - a).dot(delta) / maxf(0.00001, delta.length_squared()), 0.0, 1.0)
		var nearest := a + delta * t
		var distance := at.distance_squared_to(nearest)
		if distance < closest:
			closest = distance
			result.nearest = nearest
			result.height = lerpf(points[index].y, points[index + 1].y, t)
	return result


func _export_points(route: Dictionary) -> Array:
	var result: Array = []
	var points: PackedVector3Array = route.points
	for point in points:
		result.append([point.x, point.y, point.z])
	return result


func _bucket(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / _bucket_size), floori(at.y / _bucket_size))


func _xz(point: Variant) -> Vector2:
	if point is Vector3:
		return Vector2(point.x, point.z)
	return Vector2(point[0], point[2])


func _xyz(point: Variant) -> Vector3:
	if point is Vector3:
		return point
	return Vector3(point[0], point[1], point[2])


func _empty_sample() -> Dictionary:
	return {
		"distance": INF, "height": 0.0, "nearest": Vector2.ZERO,
		"mountain_direction": Vector2(0.0, -1.0), "width": 10.0,
		"mountain_run": 54.0, "valley_run": 30.0,
		"cut_rise": 15.0, "fill_drop": 19.0, "candidates": []
	}
