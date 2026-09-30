extends RefCounted
## Locked, cell-seeded forest sample for two neighbouring mountain courts.
const CONFIG := "res://resources/fusion_3d/orchard_forest_sample_20260926.json"
const CELL := 6.0
const ANCHORS := "res://resources/campaigns/star_orchard_world1_v2/map_anchors.json"

func install(world: Node3D, landscape: Node3D, forest: RefCounted) -> void:
	if world.has_meta("orchard_forest_sample"):
		return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	if not value is Dictionary:
		push_error("Missing orchard forest sample data")
		return
	var spec: Dictionary = value
	_install_access(world, landscape, spec)
	var recipes: Array = forest.get("_simple_tree_recipes")
	if recipes.is_empty():
		return
	var protected := []
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ANCHORS))
	for anchor in campaign.get("anchors", {}).values():
		var point: Array = anchor.position
		protected.append({"at": Vector2(float(point[0]), float(point[2])), "radius": maxf(14.0, float(anchor.get("search_radius", 7.0)) + 7.0)})
	for site in campaign.get("battle_sites", {}).values():
		var point: Array = site.center
		protected.append({"at": Vector2(float(point[0]), float(point[2])), "radius": maxf(40.0, float(site.get("outer_radius", 21.0)) + 12.0) if Vector2(float(point[0]), float(point[2])) in [Vector2(1080.0, -350.0), Vector2(840.0, -445.0)] else float(site.get("outer_radius", 21.0)) + 12.0})
	for group in spec.get("groups", []):
		for item in group.get("items", []):
			var point: Array = item.get("at", [])
			if point.size() == 2:protected.append({"at": Vector2(float(point[0]), float(point[1])), "radius": 5.0})
	var root := Node3D.new()
	root.name = "OrchardForestSampleColliders"
	world.add_child(root)
	var counts := {}
	var occupied: Dictionary = {}
	var total := 0
	for zone in spec.get("forest_zones", []):
		var points: Array = zone.path
		var width: float = float(zone.half_width)
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for raw in points:
			var p := Vector2(float(raw[0]), float(raw[1]))
			minimum = minimum.min(p)
			maximum = maximum.max(p)
		minimum -= Vector2.ONE * width
		maximum += Vector2.ONE * width
		var first_x := floori(minimum.x / CELL)
		var last_x := ceili(maximum.x / CELL)
		var first_z := floori(minimum.y / CELL)
		var last_z := ceili(maximum.y / CELL)
		var count := 0
		for zi in range(first_z, last_z + 1):
			for xi in range(first_x, last_x + 1):
				var cell := Vector2i(xi, zi)
				if occupied.has(cell):
					continue
				var rng := RandomNumberGenerator.new()
				rng.seed = int(spec.seed) + str(zone.id).hash() * 1000003 + xi * 73856093 + zi * 19349663
				var at := Vector2((xi + rng.randf()) * CELL, (zi + rng.randf()) * CELL)
				var edge: float = _line_distance(at, points)
				if edge >= width:
					continue
				if rng.randf() > float(zone.density) * lerpf(0.48, 1.0, 1.0 - edge / width):
					continue
				var height := rng.randf_range(float(zone.height[0]), float(zone.height[1]))
				var recipe: Dictionary = recipes[rng.randi_range(0, recipes.size() - 1)]
				var bounds: AABB = recipe.bounds
				var factor: float = height / maxf(bounds.size.y, 0.1)
				var crown_radius: float = Vector2(maxf(absf(bounds.position.x), absf(bounds.end.x)), maxf(absf(bounds.position.z), absf(bounds.end.z))).length() * factor
				if _protected(at, crown_radius, protected):continue
				if bool(forest.call("clearing_blocked", at, crown_radius)):continue
				if float(forest.call("_road_distance", at)) < 16.0 + crown_radius:
					continue
				if not bool(forest.call("_clear", at, crown_radius, maxf(2.3, height * 0.17), true)):
					continue
				var y: float = landscape.height_at(at)
				if y < float(landscape.settings.sea_level) + 5.0 or y > 375.0:
					continue
				var fit: Vector3 = forest.call("_ground_fit", at, 2.0)
				if fit.z > 0.34 or fit.y - fit.x > 2.1:
					continue
				var base_y := minf(y, fit.x + 0.18) - 0.12
				var yaw := rng.randf_range(-PI, PI)
				var transform := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * factor), Vector3(at.x, base_y - bounds.position.y * factor, at.y))
				var tint := Color(rng.randf(), rng.randf(), rng.randf(), clampf(height / 24.0, 0.4, 0.9))
				forest.call("_queue_recipe", recipe, transform, false, true, tint)
				forest.call("_remember_placement", at, maxf(2.3, height * 0.17), true)
				_add_trunk(root, Vector3(at.x, base_y, at.y), factor)
				occupied[cell] = true
				count += 1
				total += 1
		counts[str(zone.id)] = count
	world.set_meta("orchard_forest_sample", {"revision": spec.revision, "trees": total, "solid_trunks": total, "zones": counts, "seed": spec.seed})

func _protected(at: Vector2, crown_radius: float, places: Array) -> bool:
	for place in places:
		if at.distance_to(place.at) < float(place.radius) + crown_radius:return true
	return false

func _line_distance(at: Vector2, points: Array) -> float:
	var nearest := INF
	for index in range(points.size() - 1):
		var a := Vector2(float(points[index][0]), float(points[index][1]))
		var b := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
		var span := b - a
		var t := clampf((at - a).dot(span) / maxf(span.length_squared(), 0.001), 0.0, 1.0)
		nearest = minf(nearest, at.distance_to(a + span * t))
	return nearest

func _add_trunk(root: Node3D, base: Vector3, factor: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	root.add_child(body)
	body.position = base + Vector3.UP * 2.55 * factor
	var shape := CylinderShape3D.new()
	shape.radius = 0.39 * factor
	shape.height = 5.1 * factor
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)


func _install_access(world: Node3D, _landscape: Node3D, spec: Dictionary) -> void:
	# Access paths are now painted into the existing terrain's trail channel.
	# No floating overlay, mismatched normals, or duplicate coplanar surfaces.
	world.set_meta("orchard_clearing_access", {"paths":spec.get("access_paths",[]).size(),"surface":"terrain_trail_channel","overlays":0})


func _path_side(points: Array, index: int, half_width: float) -> Vector2:
	var p := Vector2(float(points[index][0]),float(points[index][1]))
	var prev := Vector2(float(points[maxi(0,index-1)][0]),float(points[maxi(0,index-1)][1]))
	var next := Vector2(float(points[mini(points.size()-1,index+1)][0]),float(points[mini(points.size()-1,index+1)][1]))
	var incoming := (p-prev).normalized() if index>0 else (next-p).normalized()
	var outgoing := (next-p).normalized() if index<points.size()-1 else incoming
	var tangent := (incoming+outgoing).normalized()
	return Vector2(-tangent.y,tangent.x)*half_width/maxf(tangent.dot(outgoing),0.65)
