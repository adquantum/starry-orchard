extends RefCounted
## Segmented existing wooden model, fitted to the final terrain. Collision uses
## the exact transformed visible triangles, preserving the open rail silhouette.
const MODEL := "res://assets/worlds/_shared_models/eb5b3997bc93305a_BrownWoodFence.glb"
var _faces: Dictionary = {}

func install(world: Node3D, landscape: Node3D, details: RefCounted) -> void:
	if world.has_meta("orchard_road_fences"): return
	var spec: Dictionary = landscape.settings.get("route_details", {}).get("wood_fences", {})
	if not bool(spec.get("enabled", false)): return
	var renderer = preload("res://scripts/worlds/orchard_quest_scenery.gd").new()
	renderer._styler = preload("res://scripts/worlds/orchard_cloud_prop_style.gd").new()
	var recipe: Dictionary = renderer._load_recipe(world, {"path": MODEL, "kind": "prop"})
	if recipe.is_empty(): return
	var bounds: AABB = recipe.bounds
	var scale_factor := float(spec.get("height", 3.0)) / bounds.size.y
	var length := bounds.size.z * scale_factor
	var pitch := length * 0.96
	var center := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var anchors: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/campaigns/star_orchard_world1_v2/map_anchors.json"))
	var clearing_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/orchard_forest_sample_20260926.json"))
	var clearing_helper = preload("res://scripts/worlds/orchard_forest_sample.gd").new()
	# Reuse the original fence recipe, scale, gaps, ground fit and collision builder.
	# A temporary route view keeps the main route furniture data unchanged.
	var extended: RefCounted = details.get_script().new()
	for property in ["_config", "_spec", "_city_footprints", "_lamp_positions"]:
		extended.set(property, details.get(property))
	extended.set("_routes", details.get("_routes").duplicate())
	for access in clearing_data.get("access_paths", []):
		var points := []
		for raw in access.path:points.append([raw[0], landscape.height_at(Vector2(float(raw[0]),float(raw[1]))), raw[1]])
		extended.call("_add_route", points)
	details = extended
	var counts: Array = []
	var accepted: Array = []
	var min_road_gap := INF
	var min_quest_gap := INF
	_faces.clear()
	for route_id in details._routes.size():
		var route: Dictionary = details._routes[route_id]
		var route_count := 0
		var slot := 0
		var distance := 18.0
		while distance < float(route.length) - 16.0:
			var current_slot := slot
			slot += 1
			var along := distance
			distance += pitch
			if current_slot % (int(spec.run_segments) + int(spec.gap_segments)) >= int(spec.run_segments): continue
			for side_sign in [-1.0, 1.0]:
				var middle: Vector2 = details._at(route, along)
				var tangent: Vector2 = details._tangent(route, along)
				var at: Vector2 = middle + Vector2(-tangent.y, tangent.x) * float(spec.roadside_offset) * float(side_sign)
				var ends: Array[Vector2] = [at - tangent * length * 0.5, at, at + tangent * length * 0.5]
				var safe := true
				var road_gap := INF
				var quest_gap := INF
				for point in ends:
					if details._protected(point, 1.2): safe = false
					for clearing in clearing_data.get("clearings", []):
						if point.distance_to(Vector2(float(clearing.at[0]),float(clearing.at[1]))) < float(clearing.radius)+2.0:safe = false
					for access in clearing_data.get("access_paths", []):
						if clearing_helper._line_distance(point, access.path) < float(access.half_width)+2.0:safe = false
					var gap: float = details._distance_to_roads(point) - bounds.size.x * scale_factor * 0.5
					road_gap = minf(road_gap, gap)
					if gap < 10.65: safe = false
					for anchor in anchors.get("anchors", {}).values():
						var p: Array = anchor.position
						quest_gap = minf(quest_gap, point.distance_to(Vector2(p[0],p[2])))
					if quest_gap < 16.0: safe = false
					for lamp in details._lamp_positions:
						if point.distance_to(lamp) < 2.5: safe = false
				if not safe: continue
				var h0: float = landscape.height_at(ends[0])
				var h1: float = landscape.height_at(ends[2])
				if absf(h1-h0) / length > 0.42: continue
				var forward := Vector3(tangent.x, (h1-h0)/length, tangent.y).normalized()
				var right := Vector3.UP.cross(forward).normalized()
				var up := forward.cross(right).normalized()
				var basis := Basis(right,up,forward).scaled(Vector3.ONE * scale_factor)
				var ground := (h0+h1)*0.5
				var fit := 0.0
				for fraction in [0.0,0.25,0.5,0.75,1.0]:
					var sample: Vector2 = ends[0].lerp(ends[2],fraction)
					fit = maxf(fit, absf(float(landscape.height_at(sample))-lerpf(h0,h1,fraction)))
				if fit > 0.28: continue
				var transform := Transform3D(basis, Vector3(at.x,ground-0.16,at.y)-basis*center)
				for part in recipe.parts:
					var final_transform: Transform3D = transform * part.transform
					renderer._queue(part,final_transform,at,true)
					if bool(spec.get("collision",true)):
						var cell := Vector2i(floori(at.x/96.0),floori(at.y/96.0))
						if not _faces.has(cell): _faces[cell] = PackedVector3Array()
						var vertices: PackedVector3Array = _faces[cell]
						for vertex in part.mesh.get_faces(): vertices.append(final_transform*vertex)
						_faces[cell] = vertices
				accepted.append({"route":route_id,"side":side_sign,"at":[at.x,at.y],"fit_error":fit,"road_gap":road_gap,"quest_gap":quest_gap})
				route_count += 1
				min_road_gap = minf(min_road_gap,road_gap)
				min_quest_gap = minf(min_quest_gap,quest_gap)
		counts.append(route_count)
	var container := Node3D.new()
	container.name = "MountainRoadFences"
	world.add_child(container)
	renderer._build_batches(container)
	for cell in _faces:
		var body := StaticBody3D.new()
		body.name = "FenceCollision_%d_%d" % [cell.x,cell.y]
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_faces[cell])
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		container.add_child(body)
	world.set_meta("orchard_road_fences",{"count":accepted.size(),"routes":counts,"batches":renderer._batches.size(),"collision_chunks":_faces.size(),"minimum_road_center_gap":min_road_gap,"minimum_anchor_gap":min_quest_gap,"accepted":accepted})
