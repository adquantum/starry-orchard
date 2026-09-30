extends Node3D
## Brief broad flash with tapered rays, rather than intersecting wire rings.
var school:="fire"
var kind:="impact"
var diameter:=2.5
var use_approved_casting:=false
var opacity:=1.0
var face: MeshInstance3D
var material: ShaderMaterial
func _ready() -> void:
	face=MeshInstance3D.new()
	var mesh:=QuadMesh.new()
	mesh.size=Vector2.ONE*diameter
	face.mesh=mesh
	face.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material=ShaderMaterial.new()
	material.shader=load("res://scripts/fusion_3d/vfx/soft_impact.gdshader")
	material.set_shader_parameter("painted_burst",preload("res://scripts/fusion_3d/vfx/painted_particle_assets.gd").texture("impact"))
	var palette: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/school_vfx.json"))
	material.set_shader_parameter("tint",Color(palette.get(school,palette.fire).accent))
	face.material_override=material
	add_child(face)
func _process(_delta: float) -> void:
	material.set_shader_parameter("opacity",opacity)
	var camera:=get_viewport().get_camera_3d()
	if camera!=null and face.global_position.distance_squared_to(camera.global_position)>0.001:
		face.look_at(camera.global_position,Vector3.UP,true)
