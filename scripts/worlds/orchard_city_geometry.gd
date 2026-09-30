extends RefCounted
## Repair exported closed ground shells before either rendering or collision.
## Several Blender slabs have inward winding; using backface collision would
## preserve the invisible tops and put characters on their lower faces.
const Collision = preload("res://scripts/worlds/orchard_city_collision.gd")
const CELL := 24.0
var stats := {"inward_meshes_repaired": 0, "repaired_instances": 0, "paving_bevels": 0, "stair_toes": 0, "overhanging_slabs_trimmed": 0}
var _fixed: Dictionary = {}
var _nodes: Array[MeshInstance3D] = []
var _ground: Dictionary = {}
var _city := ""

func repair(city_root: Node3D, city: String) -> Dictionary:
	_city = city
	for child in city_root.find_children("*", "MeshInstance3D", true, false):
		var node := child as MeshInstance3D
		if node.mesh == null: continue
		_nodes.append(node)
		var owner := String(node.name).get_slice("__", 0)
		if not _is_ground(owner): continue
		var id := node.mesh.get_instance_id()
		if not _fixed.has(id):
			_fixed[id] = _repair_winding(node.mesh)
		if _fixed[id] != null:
			node.mesh = _fixed[id]
			stats.repaired_instances += 1
			node.set_meta("city_winding_repaired", true)
		if owner == "C_SO_PATH_AcademyAxis": _trim_box_end(node, -32.84)
		if owner == "C_SO_R2_Harbor_UpperLanding": _trim_box_end(node, 226.98)
		if owner == "C_SO_R3_Academy_UpperApron": _trim_box_end(node, -32.80)
		_index_ground(node)
	return stats

func finish(city_root: Node3D) -> Dictionary:
	# A visible bevel connects the raised paving to its actual adjacent floor.
	# The source top, walls, cliffs, buildings and stairs retain their collision.
	var additions := Node3D.new()
	additions.name = "CityGroundTransitions"
	additions.top_level = true
	city_root.add_child(additions)
	additions.global_transform = Transform3D.IDENTITY
	for node in _nodes:
		var owner := String(node.name).get_slice("__", 0)
		if _bevel_owner(owner):
			_add_bevels(node, additions)
		if owner.contains("Stair_Flight_") or (owner.begins_with("C_ARRAY_") and owner.contains("Stair")) or owner.begins_with("C_INST_SideSteps_"):
			_add_stair_toe(node, additions, owner.begins_with("C_ARRAY_POL_"))
	city_root.set_meta("city_geometry_repairs", stats.duplicate())
	return stats.duplicate()

func _is_ground(owner: String) -> bool:
	for token in ["Rail", "Fence", "Posts", "Handrail", "_INST_"]:
		if owner.contains(token) and not owner.begins_with("C_ARRAY_"): return false
	for prefix in ["C_SO_DOCK_", "C_SO_R2_DOCK_", "C_SO_PARAPET_", "C_LAND_", "C_PLATFORM_", "C_PAVING_", "C_PLAZA_", "C_ARRAY_", "C_SUPPORT_", "C_SO_LAND_", "C_SO_PATH_", "C_SO_PLAZA_", "C_SO_GARDEN_BED_", "V_TERRACE_", "V_SOIL_", "C_BRIDGE_POL_", "C_ABUTMENT_"]:
		if owner.begins_with(prefix): return true
	if owner.begins_with("C_EXP_") or owner.begins_with("V_EXP_"):
		return owner.ends_with("_Meadow") or owner.ends_with("_Terrace") or owner.ends_with("_RoundPlaza")
	if owner == "C_SO_R2_Harbor_UpperLanding": return true
	if owner.begins_with("C_SO_R3_"):
		for token in ["_PATH_", "_Path", "Apron", "_Court_", "_Rest_", "Landing", "Stair_Flight_", "Stair_Support_"]:
			if owner.contains(token): return true
	return false

func _repair_winding(source: Mesh) -> ArrayMesh:
	var faces := source.get_faces()
	var center := source.get_aabb().get_center()
	var volume := 0.0
	var edges: Dictionary = {}
	for index in range(0, faces.size(), 3):
		var a := faces[index] - center
		var b := faces[index + 1] - center
		var c := faces[index + 2] - center
		# Godot's front-facing winding is clockwise.
		volume += a.dot(c.cross(b)) / 6.0
		for edge in [[faces[index], faces[index + 1]], [faces[index + 1], faces[index + 2]], [faces[index + 2], faces[index]]]:
			var key := _edge_key(edge[0], edge[1])
			edges[key] = int(edges.get(key, 0)) + 1
	if volume >= -0.0001: return null
	# Never infer orientation from an open grass/card/road sheet.
	for count in edges.values():
		if int(count) % 2 != 0: return null
	var result := ArrayMesh.new()
	for surface in range(source.get_surface_count()):
		var arrays := source.surface_get_arrays(surface)
		var indices := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array: indices = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			indices.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for i in indices.size(): indices[i] = i
		for i in range(0, indices.size(), 3):
			var saved := indices[i + 1]
			indices[i + 1] = indices[i + 2]
			indices[i + 2] = saved
		arrays[Mesh.ARRAY_INDEX] = indices
		var normals := PackedVector3Array()
		if arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array: normals = arrays[Mesh.ARRAY_NORMAL]
		for i in normals.size(): normals[i] = -normals[i]
		arrays[Mesh.ARRAY_NORMAL] = normals
		var tangents := PackedFloat32Array()
		if arrays[Mesh.ARRAY_TANGENT] is PackedFloat32Array: tangents = arrays[Mesh.ARRAY_TANGENT]
		for i in range(3, tangents.size(), 4): tangents[i] = -tangents[i]
		arrays[Mesh.ARRAY_TANGENT] = tangents
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.surface_get_material(surface))
	result.resource_name = source.resource_name + "_Outward"
	stats.inward_meshes_repaired += 1
	return result

func _edge_key(a: Vector3, b: Vector3) -> String:
	var ka := "%d,%d,%d" % [roundi(a.x * 10000.0), roundi(a.y * 10000.0), roundi(a.z * 10000.0)]
	var kb := "%d,%d,%d" % [roundi(b.x * 10000.0), roundi(b.y * 10000.0), roundi(b.z * 10000.0)]
	return ka + ":" + kb if ka < kb else kb + ":" + ka

func _index_ground(node: MeshInstance3D) -> void:
	var source := node.mesh.get_faces()
	for i in range(0, source.size(), 3):
		var a := node.global_transform * source[i]
		var b := node.global_transform * source[i + 1]
		var c := node.global_transform * source[i + 2]
		if (c - a).cross(b - a).normalized().y < 0.8: continue
		var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
		var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
		for z in range(floori(lo.y / CELL), floori(hi.y / CELL) + 1):
			for x in range(floori(lo.x / CELL), floori(hi.x / CELL) + 1):
				var cell := Vector2i(x, z)
				if not _ground.has(cell): _ground[cell] = []
				_ground[cell].append([a, b, c])

func _ground_height(at: Vector3) -> float:
	var found := -INF
	for triangle in _ground.get(Vector2i(floori(at.x / CELL), floori(at.z / CELL)), []):
		var a: Vector3 = triangle[0]
		var b: Vector3 = triangle[1]
		var c: Vector3 = triangle[2]
		var aa := Vector2(a.x, a.z)
		var v0 := Vector2(b.x, b.z) - aa
		var v1 := Vector2(c.x, c.z) - aa
		var v2 := Vector2(at.x, at.z) - aa
		var denominator := v0.cross(v1)
		if absf(denominator) < 0.00001: continue
		var u := v2.cross(v1) / denominator
		var v := v0.cross(v2) / denominator
		if u >= -0.001 and v >= -0.001 and u + v <= 1.001:
			var y := a.y + u * (b.y - a.y) + v * (c.y - a.y)
			if y <= at.y + 0.02: found = maxf(found, y)
	return found

func _add_bevels(node: MeshInstance3D, parent: Node3D) -> void:
	var stair_landing := String(node.name).begins_with("C_PLAZA_TreeDais__")
	var edges: Dictionary = {}
	var source := node.mesh.get_faces()
	for i in range(0, source.size(), 3):
		var a := node.global_transform * source[i]
		var b := node.global_transform * source[i + 1]
		var c := node.global_transform * source[i + 2]
		if (c - a).cross(b - a).normalized().y < 0.97: continue
		for pair in [[a, b], [b, c], [c, a]]:
			var key := _edge_key(pair[0], pair[1])
			if edges.has(key): edges.erase(key)
			else: edges[key] = pair
	var faces := PackedVector3Array()
	for pair in edges.values():
		var edge_a: Vector3 = pair[0]
		var edge_b: Vector3 = pair[1]
		var segments := maxi(1, ceili(edge_a.distance_to(edge_b) / 2.0))
		for segment in segments:
			var a := edge_a.lerp(edge_b, float(segment) / float(segments))
			var b := edge_a.lerp(edge_b, float(segment + 1) / float(segments))
			var direction := b - a
			direction.y = 0.0
			var outside := Vector3(direction.z, 0.0, -direction.x).normalized()
			var midpoint := (a + b) * 0.5
			var ground_y := _ground_height(midpoint + outside * 0.3)
			var drop := midpoint.y - ground_y
			if not is_finite(ground_y) or drop < 0.04 or drop > (2.0 if stair_landing else 0.9): continue
			var width := maxf(0.7, drop * 3.0)
			var aa := a + outside * width
			var bb := b + outside * width
			aa.y = _ground_height(aa)
			bb.y = _ground_height(bb)
			if not is_finite(aa.y) or not is_finite(bb.y): continue
			# The sanctuary's round dais joins the final stair on a slope;
			# sampling it as flat grass rejected the needed entrance bevel.
			var variation := maxf(0.2, width * 0.75) if stair_landing else 0.2
			if absf(aa.y - ground_y) > variation or absf(bb.y - ground_y) > variation: continue
			if absf((bb - a).cross(b - a).normalized().y) < 0.68: continue
			if absf((aa - a).cross(bb - a).normalized().y) < 0.68: continue
			aa.y += 0.015
			bb.y += 0.015
			Collision._triangle(faces, a, b, bb, Vector3.UP)
			Collision._triangle(faces, a, bb, aa, Vector3.UP)
	if faces.is_empty(): return
	var bevel := Collision.make_faces_mesh(faces, node.get_active_material(0))
	bevel.name = "C_RUNTIME_PavingBevel_" + String(node.name).get_slice("__", 0)
	bevel.set_meta("city_walk_surface", true)
	parent.add_child(bevel)
	stats.paving_bevels += 1

func _bevel_owner(owner: String) -> bool:
	if owner in ["C_SO_R2_Harbor_UpperLanding", "C_SO_R3_EastBridge_LowerLanding", "C_SO_R3_EastBridge_UpperLanding", "C_PLAZA_TreeDais"]: return true
	for prefix in ["C_SO_PATH_", "C_SO_R3_PATH_", "C_SO_R3_Stable_Entrance_Path"]:
		if owner.begins_with(prefix): return true
	return false

func _add_stair_toe(node: MeshInstance3D, parent: Node3D, along_x: bool) -> void:
	var axis := 0 if along_x else 2
	var across := 2 if along_x else 0
	var bounds := node.mesh.get_aabb()
	var y_at_min := -INF
	var y_at_max := -INF
	for vertex in node.mesh.get_faces():
		if absf(vertex[axis] - bounds.position[axis]) < 0.001: y_at_min = maxf(y_at_min, vertex.y)
		if absf(vertex[axis] - bounds.end[axis]) < 0.001: y_at_max = maxf(y_at_max, vertex.y)
	if not is_finite(y_at_min) or not is_finite(y_at_max): return
	var sign_run := -1.0 if y_at_min < y_at_max else 1.0
	var low_run := bounds.position[axis] if sign_run < 0.0 else bounds.end[axis]
	var local := bounds.get_center()
	local[axis] = low_run + sign_run * 0.55
	local.y = bounds.position.y
	var midpoint := node.global_transform * local
	var outside := node.global_transform.basis[axis].normalized() * sign_run
	outside.y = 0.0
	var ground_y := _ground_height(midpoint + outside * 0.5)
	var drop := midpoint.y - ground_y
	if not is_finite(ground_y) or drop < 0.015 or drop > 1.0: return
	var end := midpoint + outside * maxf(0.7, drop * 3.0)
	end.y = ground_y + 0.008
	var width := bounds.size[across] * node.global_transform.basis[across].length() * 0.5
	var toe := Collision.make_join_mesh(midpoint, end, width, node.get_active_material(0))
	toe.name = "C_RUNTIME_StairToe_" + String(node.name).get_slice("__", 0)
	toe.set_meta("city_walk_surface", true)
	parent.add_child(toe)
	stats.stair_toes += 1

func _trim_box_end(node: MeshInstance3D, max_world_z: float) -> void:
	# Source box slabs project beyond the top stair nosing. Their lower
	# face becomes a low ceiling above the final flight. Shorten that authored
	# excess while retaining the six closed faces, UVs and original material.
	var source := node.mesh
	var world_box: AABB = node.global_transform * source.get_aabb()
	if max_world_z <= world_box.position.z or max_world_z >= world_box.end.z: return
	for vertex in source.get_faces():
		var z := (node.global_transform * vertex).z
		if absf(z - world_box.position.z) > 0.001 and absf(z - world_box.end.z) > 0.001:
			push_warning("Expected an authored box slab: " + String(node.name))
			return
	var result := ArrayMesh.new()
	var inverse := node.global_transform.affine_inverse()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vertices.size():
			var point := node.global_transform * vertices[i]
			point.z = minf(point.z, max_world_z)
			vertices[i] = inverse * point
		arrays[Mesh.ARRAY_VERTEX] = vertices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, source.surface_get_material(surface))
	node.mesh = result
	stats.overhanging_slabs_trimmed += 1
