extends GPUParticles3D
## Owned by one resource token: deletion of that token removes its whole effect.
var magic_color:=Color.WHITE
var shadow:=false
func _ready() -> void:
	name="RisingMagic"
	top_level=true
	local_coords=false
	amount=5 if shadow else 7
	lifetime=1.8
	preprocess=1.0
	randomness=0.35
	visibility_aabb=AABB(Vector3(-0.3,-0.15,-0.3),Vector3(0.6,1.3,0.6))
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var motion:=ParticleProcessMaterial.new()
	motion.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	motion.emission_sphere_radius=0.085
	motion.direction=Vector3.UP
	motion.spread=9
	motion.initial_velocity_min=0.26
	motion.initial_velocity_max=0.43
	motion.gravity=Vector3(0,0.055,0)
	motion.scale_min=0.5
	motion.scale_max=1.0
	var fade:=Gradient.new()
	fade.set_color(0,Color(1,1,1,0))
	fade.add_point(0.15,Color(1,1,1,0.8))
	fade.add_point(0.65,Color(1,1,1,0.55))
	fade.set_color(fade.get_point_count()-1,Color(1,1,1,0))
	var ramp:=GradientTexture1D.new()
	ramp.gradient=fade
	motion.color_ramp=ramp
	process_material=motion
	# A translucent center and colored rim read as bubbles instead of solid sparks.
	var radial:=Gradient.new()
	var core:=Color("09070d") if shadow else magic_color
	radial.set_color(0,Color(core,0.12))
	radial.add_point(0.56,Color(core,0.12))
	radial.add_point(0.77,Color(magic_color,0.85))
	radial.add_point(0.88,Color(magic_color.lightened(0.35),0.7))
	radial.set_color(radial.get_point_count()-1,Color(magic_color,0))
	var bubble:=GradientTexture2D.new()
	bubble.width=32
	bubble.height=32
	bubble.gradient=radial
	bubble.fill=GradientTexture2D.FILL_RADIAL
	bubble.fill_from=Vector2(0.5,0.5)
	bubble.fill_to=Vector2(0.5,0)
	var surface:=StandardMaterial3D.new()
	surface.albedo_texture=bubble
	surface.vertex_color_use_as_albedo=true
	surface.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.billboard_mode=BaseMaterial3D.BILLBOARD_PARTICLES
	surface.cull_mode=BaseMaterial3D.CULL_DISABLED
	var quad:=QuadMesh.new()
	quad.size=Vector2.ONE*0.095
	quad.material=surface
	draw_pass_1=quad
	_follow_token()
	emitting=true
func _process(_delta: float) -> void:
	_follow_token()
func _follow_token() -> void:
	# Tokens face the camera; the emitter keeps world-up as the camera changes.
	var token:=get_parent() as Node3D
	if token!=null:
		global_transform=Transform3D(Basis.IDENTITY,token.global_position+Vector3.UP*0.10)
