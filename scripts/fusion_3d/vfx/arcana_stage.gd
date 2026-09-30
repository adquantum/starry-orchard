extends Node3D
## A single imported Arcana stage. The GLB owns its TRS animation; the motion
## sidecar only supplies visibility and material opacity, never a second TRS.
const ROOT := "res://assets/vfx/arcana/"
const DETAIL_TEXTURE := preload("res://assets/vfx/arcana/textures/arcane_detail_v1.png")
const FIRE_DRAGON_HEAD_TEXTURE := preload("res://assets/vfx/arcana/textures/fire_dragon_head_scales_v1.png")
const DEATH_SKULL_TEXTURE := preload("res://assets/vfx/arcana/textures/death_skull_bone_v1.png")
const MYTH_BEAST_TEXTURE := preload("res://assets/vfx/arcana/textures/myth_beast_hide_v1.png")
const MYTH_DISK_TEXTURE := preload("res://assets/vfx/arcana/textures/myth_runestone_v1.png")
var duration := 1.0
var elapsed := 0.0
var speed := 1.0
var motion: Dictionary = {}
var times: Array = []
var nodes_by_name: Dictionary = {}
var materials_by_name: Dictionary = {}
var player: AnimationPlayer
var animation_name: StringName
var model: Node3D
var ground_offsets: Dictionary = {}
var ground_offset_applied := false
var material_defs: Dictionary = {}
var rebuilt_lines: Dictionary = {}
var hidden_cast_rings: Dictionary = {}

func setup(school: String, level: int, stage: String, world_seconds: float, ground_delta: float = 0.0) -> void:
	name = "Arcana_%s_%d_%s" % [school, level, stage]
	var id := "%s_%d_%s" % [school, level, stage]
	var path := ROOT + "meshes/%s/%s.glb" % [stage, id]
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("Arcana GLB missing: " + path)
		return
	model = scene.instantiate()
	add_child(model)
	_index(model)
	var blueprint_path := ROOT + "blueprints/%s/%s.scene.json" % [stage, id]
	var blueprint: Variant = JSON.parse_string(FileAccess.get_file_as_string(blueprint_path))
	if blueprint is Dictionary:
		for definition in blueprint.get("materials", []):
			material_defs[str(definition.get("id", ""))] = definition
		_build_missing(blueprint)
		if stage == "cast":
			for ring in blueprint.get("roles", {}).get("rings", []):
				hidden_cast_rings[str(ring.get("o", {}).get("node", ""))] = true
	var motion_path := ROOT + "motion/%s/%s.motion.json" % [stage, id]
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(motion_path))
	if parsed is Dictionary:
		motion = parsed
		times = motion.get("times", [])
		duration = maxf(float(motion.get("duration_seconds", 1.0)), 0.001)
	speed = duration / maxf(world_seconds, 0.001)
	if stage == "impact" and absf(ground_delta) > 0.001:
		if blueprint is Dictionary:
			var rebind: Dictionary = blueprint.get("roles", {}).get("ground_rebind", {})
			var recipe_scale := float(blueprint.get("recipe_scale", 1.0))
			var correction := ground_delta / recipe_scale - (0.08 - 1.43) / recipe_scale
			for node_name in rebind.get("translate_nodes", []):
				if nodes_by_name.has(node_name):
					var item: Node3D = nodes_by_name[node_name]
					ground_offsets[item] = correction
	for candidate in find_children("*", "AnimationPlayer", true, false):
		player = candidate
		break
	if player != null:
		var animations := player.get_animation_list()
		if not animations.is_empty():
			animation_name = animations[0]
			player.play(animation_name)
			player.pause()
	_apply_sidecar(0.0)

func _index(item: Node) -> void:
	if item is Node3D:
		nodes_by_name[item.name] = item
	if item is MeshInstance3D:
		var mesh_node: MeshInstance3D = item
		for surface in mesh_node.get_surface_override_material_count():
			var source := mesh_node.get_active_material(surface)
			if source == null:
				continue
			var duplicate := source.duplicate()
			if duplicate is BaseMaterial3D:
				var body_texture := _projectile_body_texture(mesh_node.name)
				if body_texture != null:
					duplicate.albedo_texture = body_texture
			mesh_node.set_surface_override_material(surface, duplicate)
			if not materials_by_name.has(duplicate.resource_name):
				materials_by_name[duplicate.resource_name] = []
			materials_by_name[duplicate.resource_name].append(duplicate)
	for child in item.get_children():
		_index(child)

func _projectile_body_texture(node_name: String) -> Texture2D:
	match node_name:
		"fire_3_projectile_n001", "fire_3_projectile_n002", "fire_3_projectile_n004", "fire_3_projectile_n005":
			return FIRE_DRAGON_HEAD_TEXTURE
		"myth_2_projectile_n001", "myth_2_projectile_n003":
			return MYTH_DISK_TEXTURE
		"myth_3_projectile_n001", "myth_3_projectile_n003", "myth_3_projectile_n005", "myth_3_projectile_n013":
			return MYTH_BEAST_TEXTURE
		"death_2_projectile_n002", "death_2_projectile_n003", "death_3_projectile_n002", "death_3_projectile_n003":
			return DEATH_SKULL_TEXTURE
	return null

func _build_missing(blueprint: Dictionary) -> void:
	for definition in blueprint.get("nodes", []):
		if bool(definition.get("present_in_glb", true)):
			continue
		var parent_node: Node3D = nodes_by_name.get(str(definition.get("parent", "")), model)
		var kind := str(definition.get("type", ""))
		var geometry: Dictionary = definition.get("geometry", {})
		var node := MeshInstance3D.new()
		node.name = str(definition.get("node", ""))
		var mat_id := str(definition.get("material", ""))
		if kind == "Mesh" and str(geometry.get("kind", "")) == "PlaneGeometry":
			var plane := QuadMesh.new()
			plane.size = Vector2(2, 2)
			node.mesh = plane
		elif kind in ["LineSegments", "LineLoop", "Line"]:
			var lines := ImmediateMesh.new()
			var positions: Array = geometry.get("position", [])
			if not positions.is_empty():
				lines.surface_begin(Mesh.PRIMITIVE_LINES)
				if kind == "LineSegments":
					for i in range(0, positions.size() - 2, 3):
						lines.surface_add_vertex(Vector3(float(positions[i]), float(positions[i+1]), float(positions[i+2])))
				else:
					var point_count := int(positions.size() / 3)
					for i in point_count - 1:
						lines.surface_add_vertex(Vector3(float(positions[i*3]), float(positions[i*3+1]), float(positions[i*3+2])))
						lines.surface_add_vertex(Vector3(float(positions[(i+1)*3]), float(positions[(i+1)*3+1]), float(positions[(i+1)*3+2])))
					if kind == "LineLoop" and point_count > 2:
						lines.surface_add_vertex(Vector3(float(positions[(point_count-1)*3]), float(positions[(point_count-1)*3+1]), float(positions[(point_count-1)*3+2])))
						lines.surface_add_vertex(Vector3(float(positions[0]), float(positions[1]), float(positions[2])))
				lines.surface_end()
			node.mesh = lines
			rebuilt_lines[node.name] = lines
		else:
			node.free()
			continue
		parent_node.add_child(node)
		var p: Array = definition.get("translation", [0, 0, 0])
		var q: Array = definition.get("rotation", [0, 0, 0, 1])
		var s: Array = definition.get("scale", [1, 1, 1])
		node.position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		node.quaternion = Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))
		node.scale = Vector3(float(s[0]), float(s[1]), float(s[2]))
		node.visible = bool(definition.get("visible", true))
		if material_defs.has(mat_id):
			var material := _missing_material(material_defs[mat_id], kind == "Mesh")
			node.material_override = material
			if not materials_by_name.has(mat_id):
				materials_by_name[mat_id] = []
			materials_by_name[mat_id].append(material)
		nodes_by_name[node.name] = node

func _missing_material(definition: Dictionary, is_plane: bool) -> Material:
	var color_values: Variant = definition.get("color_linear", null)
	if not color_values is Array or color_values.is_empty():
		color_values = definition.get("uniforms", {}).get("uColor", null)
	if not color_values is Array or color_values.is_empty():
		color_values = [0.6, 0.8, 1.0]
	var color := Color(float(color_values[0]), float(color_values[1]), float(color_values[2]), float(definition.get("opacity", 1.0)))
	if is_plane:
		var flame := str(definition.get("shader_id", "")) == "37e59db502bc32a0"
		var result := ShaderMaterial.new()
		result.shader = load(ROOT + "shaders/flame.gdshader" if flame else ROOT + "shaders/rune.gdshader")
		result.set_shader_parameter("uColor", Vector3(color.r, color.g, color.b))
		result.set_shader_parameter("uOpacity", float(definition.get("uniforms", {}).get("uOpacity", 1.0)))
		result.set_shader_parameter("uTime", 0.0)
		result.set_shader_parameter("uDetail", DETAIL_TEXTURE)
		if flame:
			var hot: Array = definition.get("uniforms", {}).get("uHot", [1.0, 0.8, 0.35])
			result.set_shader_parameter("uHot", Vector3(float(hot[0]), float(hot[1]), float(hot[2])))
		else:
			result.set_shader_parameter("uPattern", float(definition.get("uniforms", {}).get("uPattern", 0.0)))
		return result
	var result := StandardMaterial3D.new()
	result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	result.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	result.no_depth_test = false
	result.albedo_color = color
	result.emission_enabled = true
	result.emission = color
	result.emission_energy_multiplier = 1.2
	result.cull_mode = BaseMaterial3D.CULL_DISABLED
	return result

func _process(delta: float) -> void:
	if motion.is_empty():
		return
	elapsed = minf(elapsed + delta * speed, duration)
	if ground_offset_applied:
		for item in ground_offsets:
			item.position.y -= float(ground_offsets[item])
	if player != null and animation_name != &"":
		player.seek(elapsed, true)
	for item in ground_offsets:
		item.position.y += float(ground_offsets[item])
	ground_offset_applied = true
	_apply_sidecar(elapsed)
	if elapsed >= duration:
		queue_free()

func _apply_sidecar(time_value: float) -> void:
	if times.is_empty():
		return
	var frame := 0
	while frame + 1 < times.size() and float(times[frame + 1]) <= time_value:
		frame += 1
	for entry in motion.get("nodes", []):
		var item: Node3D = nodes_by_name.get(str(entry.get("node", "")))
		if item == null:
			continue
		if hidden_cast_rings.has(item.name):
			item.visible = false
			continue
		if entry.has("visible"):
			item.visible = bool(entry.visible[mini(frame, entry.visible.size() - 1)])
		elif entry.has("static_visible"):
			item.visible = bool(entry.static_visible)
		if item is MeshInstance3D and item.name in rebuilt_lines:
			_apply_missing_trs(item, entry, frame)
		elif item is MeshInstance3D and item.mesh is QuadMesh:
			_apply_missing_trs(item, entry, frame)
	for entry in motion.get("dynamic_lines", []):
		var line_name := str(entry.get("node", ""))
		if not rebuilt_lines.has(line_name):
			continue
		var line_mesh: ImmediateMesh = rebuilt_lines[line_name]
		var frames: Array = entry.get("frames", [])
		if frames.is_empty():
			continue
		var sample: Dictionary = frames[mini(frame, frames.size() - 1)]
		line_mesh.clear_surfaces()
		if not bool(sample.get("visible", false)):
			continue
		var positions: Array = sample.get("positions", [])
		if positions.is_empty():
			continue
		line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(0, positions.size() - 2, 3):
			line_mesh.surface_add_vertex(Vector3(float(positions[i]), float(positions[i+1]), float(positions[i+2])))
		line_mesh.surface_end()
	for entry in motion.get("materials", []):
		var mats: Array = materials_by_name.get(str(entry.get("material", "")), [])
		if mats.is_empty() or not entry.has("opacity"):
			continue
		var values: Array = entry.opacity
		if values.is_empty():
			continue
		var alpha := float(values[mini(frame, values.size() - 1)])
		for mat in mats:
			if mat is BaseMaterial3D:
				var base: BaseMaterial3D = mat
				var color := base.albedo_color
				color.a = alpha
				base.albedo_color = color
			elif mat is ShaderMaterial:
				mat.set_shader_parameter("uOpacity", alpha)
				mat.set_shader_parameter("uTime", time_value)

func _apply_missing_trs(item: Node3D, entry: Dictionary, frame: int) -> void:
	for field in ["translation", "scale"]:
		if not entry.has(field):
			continue
		var values: Array = entry[field]
		var index := mini(frame * 3, values.size() - 3)
		var value := Vector3(float(values[index]), float(values[index+1]), float(values[index+2]))
		if field == "translation":
			item.position = value
		else:
			item.scale = value
	if entry.has("rotation"):
		var values: Array = entry.rotation
		var index := mini(frame * 4, values.size() - 4)
		item.quaternion = Quaternion(float(values[index]), float(values[index+1]), float(values[index+2]), float(values[index+3]))
