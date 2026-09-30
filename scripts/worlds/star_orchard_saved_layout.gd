extends RefCounted
const LAYOUT_PATH := "res://resources/fusion_3d/star_orchard_layout.json"
const Actor := preload("res://scripts/fusion_3d/world_one_monster.gd")
const Style := preload("res://scripts/worlds/star_orchard_npc_style.gd")

static func document() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH):return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	return parsed if parsed is Dictionary else {}

static func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

static func play_actor(holder: Node3D, id: String, requested: String) -> void:
	var players := holder.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():return
	var player := players[0] as AnimationPlayer
	var clip := requested
	if clip.is_empty() or not player.has_animation(clip):
		clip = ""
		for candidate in player.get_animation_list():
			if "000" in candidate or "Idle" in candidate:
				clip = candidate
				break
		if clip.is_empty() and not player.get_animation_list().is_empty():clip = player.get_animation_list()[0]
	if clip.is_empty():return
	for library_name in player.get_animation_library_list():
		var copy := player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
		player.remove_animation_library(library_name)
		player.add_animation_library(library_name, copy)
	player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	player.play(clip)
	player.advance(0.0)
	holder.set_meta("orchard_actor_id", id)
	holder.set_meta("orchard_animation_clip", clip)

static func install(world: Node3D) -> void:
	if world.has_node("OrchardSavedPlacements"):return
	var saved := document()
	if saved.get("world_root", "") != world.world_root:return
	# Legacy sculpt edits are already included in the procedural terrain bake.
	if not world.has_meta("orchard_generated_terrain"):
		apply_terrain(world, saved.get("terrain", {}))
	var root := Node3D.new()
	root.name = "OrchardSavedPlacements"
	world.add_child(root)
	var actor_count := 0
	for value in saved.get("objects", []):
		var entry: Dictionary = value
		Style.prepare_entry(entry)
		var node := Node3D.new()
		root.add_child(node)
		node.position = vector(entry.position)
		node.rotation_degrees = vector(entry.rotation)
		node.scale = vector(entry.scale)
		node.set_meta("layout_entry", entry.duplicate(true))
		if str(entry.kind) in ["actor", "npc"]:
			var id := str(entry.get("actor_id", entry.get("npc_id", "")))
			var actor := Actor.new()
			actor.model_id = id
			node.add_child(actor)
			if actor.visual == null:
				push_error("Star Orchard actor missing: " + id)
				continue
			Style.apply_to(actor, id)
			play_actor(actor, id, str(entry.get("animation_clip", "")))
			actor_count += 1
		elif str(entry.kind) == "model":
			var path := str(entry.get("path", ""))
			if not world.prototypes.has(path) and ResourceLoader.exists(path):
				var instance: Node3D = load(path).instantiate()
				var parts: Array = []
				world._collect_meshes(instance, Transform3D.IDENTITY, parts)
				instance.free()
				world.prototypes[path] = parts
			if not world.prototypes.has(path):
				push_error("Star Orchard prop missing: " + path)
				continue
			for part in world.prototypes[path]:
				var display := MultiMeshInstance3D.new()
				display.multimesh = MultiMesh.new()
				display.multimesh.transform_format = MultiMesh.TRANSFORM_3D
				display.multimesh.mesh = part.mesh
				display.multimesh.instance_count = 1
				display.multimesh.set_instance_transform(0, part.transform)
				world._configure_visual_group(display, {"path":path, "transforms":[node.transform], "placement_ids":[-1]}, part)
				node.add_child(display)
				if bool(entry.get("solid", false)):
					var body := StaticBody3D.new()
					var shape := CollisionShape3D.new()
					shape.shape = part.mesh.create_trimesh_shape()
					shape.transform = part.transform
					body.add_child(shape)
					node.add_child(body)
	root.set_meta("actor_count", actor_count)
	print("ORCHARD_LAYOUT_READY actors=", actor_count, " objects=", root.get_child_count(), " terrain_tiles=", saved.get("terrain", {}).size())

static func apply_terrain(world: Node3D, edits: Dictionary) -> void:
	for node in world.get_children():
		if not node is MeshInstance3D or not node.has_meta("creator_terrain_tile"):continue
		var tile: Vector2i = node.get_meta("creator_terrain_tile")
		var key := "%d,%d" % [tile.x, tile.y]
		if not edits.has(key) or not world.heights.has(tile):continue
		var heights: PackedFloat32Array = world.heights[tile].duplicate()
		for index in edits[key]:
			var i := int(index)
			if i >= 0 and i < heights.size():heights[i] = float(edits[key][index])
		world.heights[tile] = heights
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var spacing: float = world.terrain_size / 128.0
		for z in 129:
			for x in 129:
				var i := z * 129 + x
				vertices[i].y = heights[i]
				normals[i] = Vector3(heights[z*129+maxi(x-1,0)]-heights[z*129+mini(x+1,128)], 2*spacing, heights[maxi(z-1,0)*129+x]-heights[mini(z+1,128)*129+x]).normalized()
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, node.mesh.surface_get_material(0))
		node.mesh = mesh
		for body in node.get_children():
			if body is StaticBody3D:
				for shape in body.get_children():
					if shape is CollisionShape3D:shape.shape = mesh.create_trimesh_shape()
