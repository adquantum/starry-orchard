extends MeshInstance3D
## One depth-tested, compact glow; no extra light/shadow or particle emitter.
var strength:=1.0
var source: Node3D
static func create(parent: Node3D, color: Color, diameter: float) -> MeshInstance3D:
	var glow=load("res://scripts/fusion_3d/vfx/magic_radiance.gd").new()
	glow.name="MagicRadiance"
	var quad:=QuadMesh.new()
	quad.size=Vector2.ONE*diameter
	glow.mesh=quad
	glow.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=ShaderMaterial.new()
	mat.shader=preload("res://scripts/fusion_3d/vfx/magic_radiance.gdshader")
	mat.set_shader_parameter("tint",color)
	glow.material_override=mat
	parent.add_child(glow)
	return glow
func _process(_delta: float) -> void:
	material_override.set_shader_parameter("strength",strength)
	if is_instance_valid(source):global_position=source.release_global()
