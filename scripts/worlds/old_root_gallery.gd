extends Node3D
## Authored interior, loaded only on entry. Isolated render and collision layers
## preserve the existing explorer/avatar/session and exterior map on return.
const LAYER := 1 << 17
const ASSETS := "res://assets/worlds/star_orchard/old_root_gallery/"
const WORLD_SCALE := 2.0
const SPAWN := Vector3(-49,8.15,42)*WORLD_SCALE
const EXIT := Vector3(-58.5,8,42)*WORLD_SCALE
var layout: Dictionary
var environment: Environment
var collision_count := 0
var animations: Array[AnimationPlayer] = []

func build() -> Error:
	scale = Vector3.ONE*WORLD_SCALE
	layout = JSON.parse_string(FileAccess.get_file_as_string(ASSETS+"layout_manifest.json"))
	var model := preload("res://scripts/worlds/orchard_scene_cache.gd").instantiate(ASSETS+"old_root_gallery.glb")
	if model == null: return ERR_CANT_CREATE
	add_child(model)
	_configure(model)
	for zone in layout.zones:
		var body := StaticBody3D.new()
		body.collision_layer = LAYER
		body.collision_mask = 0
		body.position = Vector3(zone.p[0],zone.p[1]-.88,zone.p[2])
		var shape := CollisionShape3D.new()
		var disk := CylinderShape3D.new()
		disk.radius = zone.r
		disk.height = 2.0
		shape.shape = disk
		body.add_child(shape)
		add_child(body)
		collision_count += 1
	for route in layout.routes: _bridge_collision(route)
	_cavern()
	_environment()
	var exit_title := Label3D.new()
	exit_title.text = "杩斿洖姣嶆爲"
	exit_title.font_size = 48
	exit_title.pixel_size = .02
	exit_title.position = EXIT/WORLD_SCALE+Vector3(2,5,0)
	exit_title.rotation.y = PI*.5
	exit_title.layers = LAYER
	exit_title.modulate = Color("efdab1")
	add_child(exit_title)
	for animation_player in animations:
		# GLB has separate channels for wheels and the three star orbits.
		var library := animation_player.get_animation_list()
		if not library.is_empty():
			var combined := Animation.new()
			combined.length = 24.0
			combined.loop_mode = Animation.LOOP_LINEAR
			for animation_name in library:
				if animation_name == "RESET": continue
				var clip := animation_player.get_animation(animation_name)
				for track in clip.get_track_count():
					var index := combined.add_track(clip.track_get_type(track))
					combined.track_set_path(index,clip.track_get_path(track))
					combined.track_set_interpolation_type(index,clip.track_get_interpolation_type(track))
					for key in clip.track_get_key_count(track):
						combined.track_insert_key(index,clip.track_get_key_time(track,key)/maxf(.01,clip.length)*24.0,clip.track_get_key_value(track,key))
			var lib := AnimationLibrary.new()
			lib.add_animation("flow",combined)
			animation_player.add_animation_library("gallery",lib)
			animation_player.play("gallery/flow")
	return OK

func _configure(node: Node) -> void:
	if node is AnimationPlayer: animations.append(node)
	if node is MeshInstance3D:
		node.layers = LAYER
		node.lod_bias = 128.0
		var label := str(node.name)
		if label == "05_Main_Sluice__architecture__Brushed_Old_Brass":
			# The left valve guide and pipe overlap the approach to the core bridge.
			# Move their visible geometry and collider together beside the stone pier.
			var adjusted := ArrayMesh.new()
			for surface_index in node.mesh.get_surface_count():
				var arrays: Array = node.mesh.surface_get_arrays(surface_index)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var links: Dictionary = {}
				for vertex in vertices: links[vertex] = []
				for i in range(0,indices.size(),3):
					var a := vertices[indices[i]]
					var b := vertices[indices[i+1]]
					var c := vertices[indices[i+2]]
					links[a].append_array([b,c])
					links[b].append_array([a,c])
					links[c].append_array([a,b])
				var visited: Dictionary = {}
				var moved: Dictionary = {}
				for vertex in links:
					if visited.has(vertex): continue
					var pending: Array = [vertex]
					var component: Array = []
					var bounds := AABB(vertex,Vector3.ZERO)
					while not pending.is_empty():
						var at: Vector3 = pending.pop_back()
						if visited.has(at): continue
						visited[at] = true
						component.append(at)
						bounds = bounds.expand(at)
						pending.append_array(links[at])
					var midpoint := bounds.get_center()
					if midpoint.x>45 and midpoint.x<48.5 and midpoint.z> -24 and midpoint.z< -19 and bounds.end.y>30.5 and bounds.end.y<40 and bounds.position.y>26:
						for at in component: moved[at] = true
				for i in vertices.size():
					if moved.has(vertices[i]): vertices[i].x -= 3.0
				arrays[Mesh.ARRAY_VERTEX] = vertices
				adjusted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
				adjusted.surface_set_material(surface_index,node.mesh.surface_get_material(surface_index))
			node.mesh = adjusted
		var solid := label.contains("__architecture__") or label.contains("__terrain__") or label.contains("__supports__")
		# Bridge treads use a smooth walk ramp, with separate guard colliders.
		if solid and not label.begins_with("Bridge_"):
			var body := StaticBody3D.new()
			body.collision_layer = LAYER
			body.collision_mask = 0
			var shape := CollisionShape3D.new()
			var faces: PackedVector3Array = node.mesh.get_faces()
			# Decorative cornice rings protrude beyond platform edges. Keep
			# railings and props solid, but let clean floor disks meet the ramps.
			for zone in layout.zones:
				if label.begins_with(str(zone.id)+"__architecture__"):
					var filtered := PackedVector3Array()
					for index in range(0,faces.size(),3):
						var top := maxf(faces[index].y,maxf(faces[index+1].y,faces[index+2].y))
						var bottom := minf(faces[index].y,minf(faces[index+1].y,faces[index+2].y))
						var center := Vector2(zone.p[0],zone.p[2])
						var midpoint := (faces[index]+faces[index+1]+faces[index+2])/3.0
						var outside_disk := Vector2(midpoint.x,midpoint.z).distance_to(center)>float(zone.r)
						var terrace_top := outside_disk and top-bottom<.04 and bottom>=float(zone.p[1])-.01
						if top<float(zone.p[1])+.2 and not terrace_top: continue
						filtered.append_array(PackedVector3Array([faces[index],faces[index+1],faces[index+2]]))
					faces = filtered
					break
			if faces.is_empty():
				body.free()
				shape.free()
			else:
				var triangle_shape := ConcavePolygonShape3D.new()
				triangle_shape.set_faces(faces)
				shape.shape = triangle_shape
				body.add_child(shape)
				node.add_child(body)
				collision_count += 1
	for child in node.get_children(): _configure(child)

func _bridge_collision(route: Dictionary) -> void:
	var a := Vector3(route.start[0],route.start[1],route.start[2])
	var b := Vector3(route.end[0],route.end[1],route.end[2])
	var horizontal := Vector3(b.x-a.x,0,b.z-a.z).normalized()
	var lower := a+horizontal*1.35+Vector3.UP*.12
	var upper := b-horizontal*1.35+Vector3.UP*.12
	var slope_direction := (upper-lower).normalized()
	var direction := (b-a).normalized()
	var side := direction.cross(Vector3.UP).normalized()
	var normal := side.cross(slope_direction).normalized()
	var basis := Basis(side,normal,-slope_direction)
	var width: float = route.width
	# One connected top surface avoids capsule snags on overlapping box edges.
	var deck := PackedVector3Array()
	var stations := [a-horizontal*.7+Vector3.UP*.12,lower,upper,b+horizontal*.7+Vector3.UP*.12]
	for i in 3:
		var left_a: Vector3 = stations[i]-side*width*.5
		var right_a: Vector3 = stations[i]+side*width*.5
		var left_b: Vector3 = stations[i+1]-side*width*.5
		var right_b: Vector3 = stations[i+1]+side*width*.5
		deck.append_array(PackedVector3Array([left_a,right_a,right_b,left_a,right_b,left_b]))
	var deck_body := StaticBody3D.new()
	deck_body.collision_layer = LAYER
	deck_body.collision_mask = 0
	var deck_shape := ConcavePolygonShape3D.new()
	deck_shape.backface_collision = true
	deck_shape.set_faces(deck)
	var deck_collision := CollisionShape3D.new()
	deck_collision.shape = deck_shape
	deck_body.add_child(deck_collision)
	add_child(deck_body)
	collision_count += 1
	basis = Basis(side,side.cross(direction).normalized(),-direction)
	for sign_value in [-1,1]:
		_box_collision(Transform3D(basis,(a+b)*.5+side*sign_value*(width*.5+.1)+Vector3.UP*1.3),Vector3(.24,2.6,a.distance_to(b)+.3))

func _box_collision(transform_value: Transform3D,size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.transform = transform_value
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	collision_count += 1

func _cavern() -> void:
	# Closed faceted shell with a ceiling, behind the authored cliffs and roots.
	# No sky-facing opening even from the highest platform.
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 14
	var sectors := 52
	for ring in rings:
		for sector in sectors:
			var points: Array[Vector3] = []
			for ij in [Vector2i(ring,sector),Vector2i(ring+1,sector),Vector2i(ring+1,sector+1),Vector2i(ring,sector+1)]:
				var theta := float(ij.x)/rings*PI*.52
				var phi := float(ij.y)/sectors*TAU
				var relief := 1.0+.024*sin(float(ij.y)*2.4+float(ij.x)*1.8)
				points.append(Vector3(sin(theta)*cos(phi)*115*relief,cos(theta)*112-8,sin(theta)*sin(phi)*131*relief-15))
			for index in [0,1,2,0,2,3]: surface.add_vertex(points[index])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "ClosedCavernCeiling"
	mesh.layers = LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("233b40")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 1.0
	mesh.material_override = material
	add_child(mesh)
	var shell_body := StaticBody3D.new()
	shell_body.collision_layer = LAYER
	shell_body.collision_mask = 0
	var shell_collision := CollisionShape3D.new()
	var shell_shape := mesh.mesh.create_trimesh_shape()
	shell_shape.backface_collision = true
	shell_collision.shape = shell_shape
	shell_body.add_child(shell_collision)
	mesh.add_child(shell_body)

func _environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("12282f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("a6c4c7")
	environment.ambient_light_energy = .55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("18343c")
	environment.fog_density = .0035/WORLD_SCALE
	var light := DirectionalLight3D.new()
	light.layers = LAYER
	light.rotation_degrees = Vector3(-65,-25,0)
	light.light_color = Color("f4e7c8")
	light.light_energy = .8
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 110*WORLD_SCALE
	add_child(light)
	for zone in layout.zones:
		var lamp := OmniLight3D.new()
		lamp.layers = LAYER
		lamp.position = Vector3(zone.p[0],zone.p[1]+6,zone.p[2])
		lamp.light_color = Color("8bd5d7")
		lamp.light_energy = 2.0
		lamp.omni_range = 22*WORLD_SCALE
		add_child(lamp)

func floor_height(point: Vector3) -> float:
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*1.4,point-Vector3.UP*90,LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return float(hit.position.y) if not hit.is_empty() else -40.0
