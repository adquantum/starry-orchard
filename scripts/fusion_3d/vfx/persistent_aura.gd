extends Node3D
## One visual per authoritative aura status; cylinders are the production default.
@export var visual_id: String = "defense"
@export var hemisphere_preview: bool = false
@export var play_entrance: bool = true
var status_id: int = -1
var _player: AnimationPlayer
var _appear: StringName = &""
var _loop: StringName = &""
var _disappear: StringName = &""
var _retiring := false
var _dome_materials: Array[ShaderMaterial] = []
var _dome_meshes: Dictionary = {}
var _motes: Array[MeshInstance3D] = []
var _elapsed := 0.0
const WISPS = preload("res://scripts/fusion_3d/vfx/casting_wisps.gd")
const DOME = preload("res://scripts/fusion_3d/vfx/aura_hemisphere_preview.gdshader")
const VALID = ["defense","all_attack","weakness","vulnerability","school_fire","school_ice","school_storm","school_life","school_death","school_myth","school_balance"]
const SCENES = {
	"defense":"res://assets/vfx/persistent_auras/universal/glb/aura_defense.glb",
	"all_attack":"res://assets/vfx/persistent_auras/universal/glb/aura_all_attack.glb",
	"weakness":"res://assets/vfx/persistent_auras/universal/glb/aura_weakness.glb",
	"vulnerability":"res://assets/vfx/persistent_auras/universal/glb/aura_vulnerability.glb",
	"school_fire":"res://assets/vfx/persistent_auras/school/glb/aura_school_fire.glb",
	"school_ice":"res://assets/vfx/persistent_auras/school/glb/aura_school_ice.glb",
	"school_storm":"res://assets/vfx/persistent_auras/school/glb/aura_school_storm.glb",
	"school_life":"res://assets/vfx/persistent_auras/school/glb/aura_school_life.glb",
	"school_death":"res://assets/vfx/persistent_auras/school/glb/aura_school_death.glb",
	"school_myth":"res://assets/vfx/persistent_auras/school/glb/aura_school_myth.glb",
	"school_balance":"res://assets/vfx/persistent_auras/school/glb/aura_school_balance.glb",
}

func _ready() -> void:
	if visual_id not in VALID:
		push_warning("Unknown aura visual: " + visual_id)
		return
	var path: String = SCENES[visual_id]
	var scene := load(path) as PackedScene
	if scene == null:return
	var model := scene.instantiate() as Node3D
	add_child(model)
	_prepare(model)
	_player = _find_player(model)
	if _player != null:
		for clip in _player.get_animation_list():
			var simple := str(clip).get_file().to_lower()
			if simple in ["aura_loop","aura"]:_loop = clip
			elif simple == "appear":_appear = clip
			elif simple == "disappear":_disappear = clip
		_player.animation_finished.connect(_animation_finished)
		if play_entrance and not _appear.is_empty():_player.play(_appear)
		else:_play_loop()
	var colors := {"defense":"92d8ff","all_attack":"eed6ff","weakness":"b38af0","vulnerability":"f086b7","school_fire":"ff985c","school_ice":"9eeaff","school_storm":"c09aff","school_life":"8de7a7","school_death":"be91ee","school_myth":"f4d084","school_balance":"eed6a0"}
	# Six faint heads, with two trailing copies each, reuse the casting streak mesh.
	for i in 18:
		_motes.append(WISPS.make_spark(self, Color(colors.get(visual_id,"ddd9ff"))))
	_process(0.0)

func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:return node as AnimationPlayer
	for child in node.get_children():
		var result := _find_player(child)
		if result != null:return result
	return null

func _play_loop() -> void:
	if _loop.is_empty():return
	_player.get_animation(_loop).loop_mode = Animation.LOOP_LINEAR
	_player.play(_loop)

func dismiss(immediate: bool = false) -> void:
	if _retiring:return
	_retiring = true
	if immediate or _player == null or _disappear.is_empty():queue_free()
	else:_player.play(_disappear)

func _animation_finished(clip: StringName) -> void:
	if _retiring and clip == _disappear:queue_free()
	elif not _retiring and clip == _appear:_play_loop()

func _prepare(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if hemisphere_preview and node is MeshInstance3D and node.mesh != null:
		var original: Mesh = node.mesh
		if not _dome_meshes.has(original):_dome_meshes[original] = _subdivide(original)
		node.mesh = _dome_meshes[original]
		for i in node.mesh.get_surface_count():
			var source := node.get_active_material(i) as BaseMaterial3D
			if source == null:continue
			var mat := ShaderMaterial.new()
			mat.shader = DOME
			mat.set_shader_parameter("aura_texture", source.albedo_texture)
			mat.set_shader_parameter("textured", source.albedo_texture != null)
			mat.set_shader_parameter("tint", source.albedo_color)
			mat.set_shader_parameter("source_height", 2.4 if visual_id.begins_with("school_") else 2.15)
			node.set_surface_override_material(i, mat)
			_dome_materials.append(mat)
	for child in node.get_children():_prepare(child)

func _subdivide(source: Mesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if indices.is_empty():
			for i in positions.size():indices.append(i)
		var builder := SurfaceTool.new()
		builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(0, indices.size(), 3):
			var a := indices[i];var b := indices[i+1];var c := indices[i+2]
			_triangle(builder, positions[a], positions[b], positions[c], uv[a] if a<uv.size() else Vector2.ZERO, uv[b] if b<uv.size() else Vector2.ZERO, uv[c] if c<uv.size() else Vector2.ZERO, 3)
		builder.commit(result)
		result.surface_set_material(surface, source.surface_get_material(surface))
	return result

func _triangle(builder: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, depth: int) -> void:
	if depth == 0:
		builder.set_uv(ua);builder.add_vertex(a)
		builder.set_uv(ub);builder.add_vertex(b)
		builder.set_uv(uc);builder.add_vertex(c)
		return
	var ab := (a+b)*0.5;var bc := (b+c)*0.5;var ca := (c+a)*0.5
	var uab := (ua+ub)*0.5;var ubc := (ub+uc)*0.5;var uca := (uc+ua)*0.5
	_triangle(builder,a,ab,ca,ua,uab,uca,depth-1)
	_triangle(builder,ab,b,bc,uab,ub,ubc,depth-1)
	_triangle(builder,ca,bc,c,uca,ubc,uc,depth-1)
	_triangle(builder,ab,bc,ca,uab,ubc,uca,depth-1)

func _process(delta: float) -> void:
	_elapsed += delta
	for i in _motes.size():
		var group := i / 3
		var tail := i % 3
		var t := fposmod(_elapsed / 2.8 + group / 6.0 - tail * 0.025, 1.0)
		var angle := group * 2.39996 + _elapsed * 0.08
		var radial := Vector3(cos(angle), 0, sin(angle))
		var mote := _motes[i]
		mote.visible = not _retiring
		mote.position = radial * (0.95 + t * 0.85) + Vector3.UP * (0.3 + fmod(group * 0.37, 1.2) + t * 0.25)
		mote.quaternion = Quaternion(Vector3.UP, (radial + Vector3.UP * 0.3).normalized())
		var size := sin(t * PI) * (0.17 - tail * 0.035)
		mote.scale = Vector3(size * 0.55, size, size * 0.55)
		(mote.material_override as StandardMaterial3D).albedo_color.a = 0.38 * sin(t * PI)
	for mat in _dome_materials:
		mat.set_shader_parameter("aura_world", global_transform)
		mat.set_shader_parameter("aura_inverse", global_transform.affine_inverse())
