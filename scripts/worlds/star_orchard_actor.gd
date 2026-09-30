extends RefCounted
## Orchard actors are fitted from the visible idle pose, not the source bind mesh.
const Library = preload("res://scripts/fusion_3d/character_library.gd")
const Style = preload("res://scripts/worlds/star_orchard_npc_style.gd")
const Paint = preload("res://scripts/fusion_3d/world_one_lowpoly.gd")

static func place(parent: Node3D, id: String, at: Vector3, height: float) -> Node3D:
	var path := "res://assets/models/world_one/" + id + ".glb"
	if not ResourceLoader.exists(path):
		path = Library.model_path(id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var holder := Node3D.new()
	holder.set_meta("world_one_asset", id)
	parent.add_child(holder)
	holder.position = at
	var fit := Node3D.new()
	fit.name = "IdlePoseFit"
	holder.add_child(fit)
	var model := (load(path) as PackedScene).instantiate() as Node3D
	fit.add_child(model)
	if str(Library.entry(id).get("source", "")).contains("/cc/02human/"):
		model.rotate_x(-PI / 2.0)
	play_idle(holder, id)
	var bounds := pose_bounds(holder)
	if bounds.size.y > 0.01:
		var factor := height / bounds.size.y
		fit.scale = Vector3.ONE * factor
		fit.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
		holder.set_meta("normalized_size", bounds.size * factor)
		holder.set_meta("orchard_idle_source_bounds", bounds)
		holder.set_meta("orchard_pose_fitted", true)
	var painted_id := str(Library.entry(id).get("existing_painted", ""))
	Paint.auto_apply(holder, painted_id if not painted_id.is_empty() else id)
	Style.apply_to(holder, id)
	return holder

static func play_idle(holder: Node3D, id: String) -> String:
	var selected := ""
	for value in holder.find_children("*", "AnimationPlayer", true, false):
		var player := value as AnimationPlayer
		var clip := ""
		for candidate in Library.action_clips(id, "idle"):
			if player.has_animation(str(candidate)):
				clip = str(candidate)
				break
		if clip.is_empty():
			for candidate in player.get_animation_list():
				var key := str(candidate).to_lower()
				if "anim_000" in key or "idle" in key or "stand" in key:
					clip = str(candidate)
					break
		if clip.is_empty():
			continue
		# Looping one resident must not mutate the imported shared resource.
		for library_name in player.get_animation_library_list():
			var copy := player.get_animation_library(library_name).duplicate(true) as AnimationLibrary
			player.remove_animation_library(library_name)
			player.add_animation_library(library_name, copy)
		player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		player.play(clip)
		player.advance(0.0)
		if selected.is_empty():
			selected = clip
	for skeleton in holder.find_children("*", "Skeleton3D", true, false):
		skeleton.force_update_all_bone_transforms()
	holder.set_meta("orchard_actor_id", id)
	holder.set_meta("orchard_animation_clip", selected)
	return selected

static func pose_bounds(holder: Node3D) -> AABB:
	# CPU skinning is a one-time placement measurement and also works headless.
	# Raw get_aabb() contains the converter's bind orientation (often on its side).
	var result := AABB()
	var found := false
	var inverse := holder.global_transform.affine_inverse()
	for value in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh := value as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		var transforms: Array[Transform3D] = []
		if skeleton != null and mesh.skin != null:
			skeleton.force_update_all_bone_transforms()
			for bind in mesh.skin.get_bind_count():
				var bone: int = skeleton.find_bone(mesh.skin.get_bind_name(bind))
				if bone < 0:
					bone = mesh.skin.get_bind_bone(bind)
				transforms.append(skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) if bone >= 0 else Transform3D.IDENTITY)
		var space := inverse * (skeleton.global_transform if not transforms.is_empty() else mesh.global_transform)
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			# Glow cards are not feet or heads and must not set a person's height.
			if original != null and original.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS]:
				continue
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
			var influences := bones.size() / maxi(1, vertices.size())
			for index in vertices.size():
				var point := vertices[index]
				if not transforms.is_empty() and influences > 0:
					var posed := Vector3.ZERO
					var total := 0.0
					for influence in influences:
						var offset := index * influences + influence
						var bone := bones[offset]
						if bone >= 0 and bone < transforms.size():
							posed += (transforms[bone] * point) * weights[offset]
							total += weights[offset]
					if total > 0.0001:
						point = posed / total
				point = space * point
				if not point.is_finite():
					continue
				result = result.expand(point) if found else AABB(point, Vector3.ZERO)
				found = true
	return result
