extends RefCounted
## Reusable source props only; all placements conform to the existing landscape.
const FILE := "res://assets/worlds/star_orchard/dewsprout_details/details.glb"
var recipes: Dictionary = {}
var colors := {"green": 0, "pink": 0, "gold": 0}
var stats := {"flowers": 0, "camp_props": 0, "camp": [], "trees": 0}
var _batches: Dictionary = {}
var _landscape: Node3D
var camps: Array[Vector2] = [Vector2(1038,-292), Vector2(1010,-305), Vector2(1014,-332)]
var _battle_sites: Array = []
var _flower_cells: Dictionary = {}
var ambient_anchors: Array[Vector3] = []
var _ambient_cells: Dictionary = {}

func prepare() -> void:
	var source := preload("res://scripts/worlds/orchard_scene_cache.gd").instantiate(FILE)
	if source == null:
		push_error("Orchard detail library could not load")
		return
	for node in source.get_children():
		if node is MeshInstance3D:
			recipes[str(node.name)] = {"bounds": node.mesh.get_aabb(), "parts": [{"mesh": node.mesh, "transform": Transform3D.IDENTITY}], "source_detail": true}
	source.free()

func tree_at(at: Vector3) -> Dictionary:
	if at.z < -555.0 or at.z > -245.0 or at.x < 730.0 or at.x > 1530.0: return {}
	# Patches of related colors with green predominating; avoid striped alternation.
	var cell := Vector2i(floori(at.x / 23.0), floori(at.z / 23.0))
	var pick := posmod(cell.x * 73 + cell.y * 37, 10)
	var color := "pink" if pick == 0 or pick == 1 else ("gold" if pick == 3 else "green")
	var key := color + "_" + str(posmod(roundi(at.x + at.z), 2))
	if not recipes.has(key): return {}
	var ambient_cell := Vector2i(floori(at.x/28.0),floori(at.z/28.0))
	if not _ambient_cells.has(ambient_cell):
		_ambient_cells[ambient_cell]=true
		ambient_anchors.append(at+Vector3.UP*6.0)
	colors[color] += 1
	stats.trees += 1
	return recipes[key]

func install(world: Node3D, landscape: Node3D, forest: RefCounted) -> void:
	_landscape = landscape
	if recipes.is_empty(): return
	_use_orchard_flag(world)
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/campaigns/star_orchard_world1_v2/map_anchors.json"))
	for key in ["orchard_lower","harbor_sluice","windgarden"]:
		var site: Dictionary = campaign.battle_sites[key].duplicate()
		site["id"] = key
		_battle_sites.append(site)
	var rng := RandomNumberGenerator.new()
	rng.seed = 27092027
	# Denser little bouquets along both edges of the accepted mountain road.
	var route: Array = landscape.settings.get("sampled_mountain_route", landscape.settings.mountain_route)
	for i in range(0,route.size()-1):
		var a := Vector2(route[i][0],route[i][2])
		var b := Vector2(route[i+1][0],route[i+1][2])
		var side := Vector2(-(b-a).y,(b-a).x).normalized()
		for sign_side in [-1.0,1.0]:
			var center: Vector2 = a + side*sign_side*rng.randf_range(13.5,24.0)
			_bouquet(center,rng.randi_range(5,9),rng,forest)
	# Broken clusters under trees, with bare patches between groups.
	for item in forest.get("_placed"):
		if not bool(item.tree): continue
		var at: Vector2 = item.at
		if at.y < -550.0 or at.y > -240.0: continue
		if rng.randf()>0.65: continue
		var angle := rng.randf_range(-PI,PI)
		_bouquet(at+Vector2(cos(angle),sin(angle))*rng.randf_range(3.0,6.0),rng.randi_range(3,6),rng,forest)
	stats["camps"] = []
	for i in camps.size():
		var center: Vector2 = camps[i]
		var size: float = [1.65,1.50,1.45][i]
		var yaw: float = [0.08,-0.24,0.22][i]
		var items := [["tent",Vector2.ZERO,size,yaw],["table",Vector2(10,3),1.65,yaw],["basket",Vector2(10,6),1.7,0.0],["crate",Vector2(-9,0),1.6,0.12],["banner",Vector2(-9,7),1.55,yaw]]
		for item in items:
			_place(item[0],center+item[1],item[2],item[3])
			stats.camp_props += 1
		stats.camps.append([center.x,landscape.height_at(center),center.y])
		for j in 16:
			var angle := TAU*float(j)/16.0
			_bouquet(center+Vector2(cos(angle),sin(angle))*rng.randf_range(11.5,16.0),5,rng,forest)
	stats["battle_borders"] = []
	for site in _battle_sites:
		var center := Vector2(site.center[0],site.center[2])
		var before: int = stats.flowers
		for i in 60:
			var angle := TAU*float(i)/60.0
			var radius := rng.randf_range(26.0,34.0)
			_bouquet(center+Vector2(cos(angle),sin(angle))*radius,5,rng,forest)
		# Flag and sampling baskets mark the approach, leaving its center open.
		var approach := (Vector2(site.approach[0],site.approach[2])-center).normalized()
		var side := Vector2(-approach.y,approach.x)
		var props := 0
		for sign_side in [-1.0,1.0]:
			for angle in [0.55,0.85,1.15,1.5,1.9]:
				var at: Vector2 = center+(approach*cos(angle)+side*sign_side*sin(angle))*32.0
				if not _flower_safe(at,forest): continue
				var fit: Vector3 = forest.call("_ground_fit",at,1.0)
				if fit.z>0.3: continue
				_place("banner",at,1.3,atan2(approach.x,approach.y))
				_place("basket",at+side*sign_side*2.0,1.4,0.0)
				props += 2
				break
		stats.battle_borders.append({"id":site.id,"flowers":stats.flowers-before,"props":props,"clear_radius":24.0})
	_add_screen_trees(forest)
	_flush(world)
	world.set_meta("orchard_local_ambient_anchors",ambient_anchors)
	stats["colors"] = colors
	stats["terrain_changed"] = false
	stats["flag_source"] = "BlenderSkySanctuary/SM_PROP_02_StarBanner"
	world.set_meta("orchard_local_fusion",stats)
	print("ORCHARD_LOCAL_FUSION ",JSON.stringify(stats))

func _add_screen_trees(forest: RefCounted) -> void:
	var count := 0
	var positions := []
	for group in [Vector2(1050,-385),Vector2(1081,-393),Vector2(1110,-384)]:
		for offset in [Vector2(-6,1),Vector2(5,-3),Vector2(0,-13),Vector2(12,-14)]:
			var at: Vector2 = group+offset
			if at.distance_to(Vector2(1080,-350))<35.0: continue
			if float(forest.call("_road_distance",at))<20.0: continue
			var crowded := false
			for old in forest.get("_placed"):
				if bool(old.tree) and at.distance_to(old.at)<6.5: crowded=true;break
			if crowded: continue
			var height: float = _landscape.height_at(at)
			var fit: Vector3 = forest.call("_ground_fit",at,0.8)
			if height<240 or fit.z>1.1: continue
			var key: String = ["green_0","green_1","pink_0","green_1","gold_0"][count%5]
			var bounds: AABB=recipes[key].bounds
			_place(key,at,(15.5+float(count%3))/bounds.size.y,float(count)*1.7)
			ambient_anchors.append(Vector3(at.x,height+6.5,at.y))
			positions.append([at.x,height,at.y])
			count+=1
	stats["screen_trees"] = count
	stats["screen_positions"] = positions

func plan_camp(landscape: Node3D, _forest: RefCounted) -> Vector2:
	_landscape = landscape
	stats.camp = [camps[0].x,landscape.height_at(camps[0]),camps[0].y]
	return camps[0]

func camp_blocked(at: Vector2, radius: float) -> bool:
	for center in camps:
		if at.distance_to(center)<15.0+radius: return true
	return false

func _bouquet(center: Vector2, count: int, rng: RandomNumberGenerator, forest: RefCounted) -> void:
	for i in count:
		var at := center+Vector2(rng.randf_range(-3.4,3.4),rng.randf_range(-3.4,3.4))
		var cell := Vector2i(floori(at.x/1.2),floori(at.y/1.2))
		if _flower_cells.has(cell) or not _flower_safe(at,forest): continue
		var inside_tent := false
		for camp in camps:
			if absf(at.x-camp.x)<9.0 and absf(at.y-camp.y)<10.0: inside_tent=true
		if inside_tent: continue
		_place("flowers",at,rng.randf_range(1.05,1.6),rng.randf_range(-PI,PI))
		_flower_cells[cell]=true
		stats.flowers+=1

func _flower_safe(at: Vector2, forest: RefCounted) -> bool:
	if at.y < -555.0 or at.y > -238.0 or _landscape.height_at(at)<234.0: return false
	if float(forest.call("_road_distance",at))<11.7: return false
	var grid: Vector2i = Vector2i(((at-_landscape.grid_start)/_landscape.grid_step).round())
	if grid.x>=0 and grid.y>=0 and grid.x<=_landscape.grid_cells.x and grid.y<=_landscape.grid_cells.y:
		if _landscape.trail_weights[grid.y*(_landscape.grid_cells.x+1)+grid.x]>0.25: return false
	var fit: Vector3=forest.call("_ground_fit",at,0.7)
	if fit.z>0.50: return false
	for site in _battle_sites:
		var center := Vector2(site.center[0],site.center[2])
		if at.distance_to(center)<24.0: return false
		var target := Vector2(site.approach[0],site.approach[2])
		var span := target-center
		var t := clampf((at-center).dot(span)/maxf(span.length_squared(),0.01),0.0,1.6)
		if at.distance_to(center+span*t)<8.0: return false
	var footprints: Array = forest.get("_city_footprint_buckets").get(Vector2i(floori(at.x/40.0),floori(at.y/40.0)),[])
	for bounds in footprints:
		if bounds.grow(0.8).has_point(at): return false
	return true

func _use_orchard_flag(world: Node3D) -> void:
	var city := world.get_node_or_null("BlenderSkySanctuary")
	if city==null: return
	var cloth := city.find_child("V_INST_EntranceBanner_1_0__SM_PROP_02_StarBanner",true,false) as MeshInstance3D
	var mast := city.find_child("V_BannerMast_1_0__BannerMast_1_0",true,false) as MeshInstance3D
	if cloth==null or mast==null:
		push_error("Existing orchard flag nodes missing")
		return
	var mesh := ArrayMesh.new()
	for node in [cloth,mast]:
		var transform: Transform3D = node.transform
		transform.origin-=Vector3(11.1,6.8,46.5)
		for i in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			for k in vertices.size():
				vertices[k]=transform*vertices[k]
				if k<normals.size(): normals[k]=(transform.basis*normals[k]).normalized()
			arrays[Mesh.ARRAY_VERTEX]=vertices
			arrays[Mesh.ARRAY_NORMAL]=normals
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			mesh.surface_set_material(mesh.get_surface_count()-1,node.get_active_material(i))
	recipes["banner"]={"bounds":mesh.get_aabb(),"parts":[{"mesh":mesh,"transform":Transform3D.IDENTITY}]}

func _safe(at: Vector2, radius: float, forest: RefCounted) -> bool:
	if at.y < -535.0 or at.y > -255.0: return false
	if _landscape.height_at(at) < 234.0: return false
	if bool(forest.call("clearing_blocked",at,radius)): return false
	if not bool(forest.call("_clear",at,radius,radius,false)): return false
	var fit: Vector3 = forest.call("_ground_fit",at,minf(radius,1.0))
	return fit.z < 0.32

func _place(key: String, at: Vector2, scale_factor: float, yaw: float) -> void:
	var recipe: Dictionary = recipes[key]
	var bounds: AABB = recipe.bounds
	var basis := Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale_factor)
	if key in ["tent","table","crate","basket","flowers"]:
		var dx: float = (_landscape.height_at(at+Vector2(3,0))-_landscape.height_at(at-Vector2(3,0)))/6.0
		var dz: float = (_landscape.height_at(at+Vector2(0,3))-_landscape.height_at(at-Vector2(0,3)))/6.0
		var up := Vector3(-dx,1.0,-dz).normalized()
		var forward := (basis.z-up*basis.z.dot(up)).normalized()
		basis=Basis(up.cross(forward).normalized(),up,forward).scaled(Vector3.ONE*scale_factor)
	var anchor := Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
	var height: float = _landscape.height_at(at)
	var transform := Transform3D(basis,Vector3(at.x,height-0.08,at.y)-basis*anchor)
	if not _batches.has(key): _batches[key] = []
	_batches[key].append(transform)

func _flush(world: Node3D) -> void:
	var root := Node3D.new()
	root.name = "OrchardLocalDetails"
	world.add_child(root)
	for key in _batches:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = recipes[key].parts[0].mesh
		mm.instance_count = _batches[key].size()
		for i in mm.instance_count: mm.set_instance_transform(i,_batches[key][i])
		var visual := MultiMeshInstance3D.new()
		visual.name = key
		visual.multimesh = mm
		visual.visibility_range_end = 600.0
		visual.visibility_range_end_margin = 50.0
		root.add_child(visual)

