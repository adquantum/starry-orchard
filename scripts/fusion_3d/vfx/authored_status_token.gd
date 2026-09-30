extends Node3D
## Original authored model and layered materials; only the center badge is replaced.
const ART = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")
const SOURCES = {"shield":"res://assets/vfx/status_tokens/damageshieldandthorn_level1_wood_shield.scn", "absorb":"res://assets/vfx/status_tokens/damageshieldandthorn_level1_wood_shield.scn", "trap":"res://assets/vfx/status_tokens/death_globaldamagetrap.scn", "dot":"res://assets/vfx/status_tokens/life_dot.scn", "hot":"res://assets/vfx/status_tokens/life_hot.scn"}
const COLORS = {"fire":Color("f47546"),"ice":Color("6bcde7"),"storm":Color("a280df"),"life":Color("7dc05c"),"death":Color("9787c0"),"myth":Color("d7bb5f"),"balance":Color("c7936c"),"all":Color("c8c8e0")}
const ARMOR_COLOR=Color("e4b84b")
var kind: String
var school: String
func setup(status_kind: String, school_id: String) -> void:
	kind=status_kind if SOURCES.has(status_kind) else "shield"
	school=school_id if COLORS.has(school_id) else "all"
	var display_color: Color=ARMOR_COLOR if kind=="absorb" else COLORS[school]
	set_meta("design","redrawn_v4");set_meta("reference_model",SOURCES[kind])
	set_meta("art_source",ART.path(StringName("school_badge_"+school)))
	var is_planar:=kind in ["dot","hot"]
	set_meta("planar_status",is_planar)
	var pivot:=Node3D.new();pivot.name="OriginalAuthoredModel";add_child(pivot)
	var model: Node3D=load(SOURCES[kind]).instantiate();pivot.add_child(model)
	var bounds:=AABB();var first:=true
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		var box: AABB=global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		bounds=box if first else bounds.merge(box);first=false
	var factor: float=(0.90 if kind in ["dot","hot"] else 1.02)/maxf(0.01,maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z)))
	model.scale*=factor;model.position-=bounds.get_center()*factor
	if kind in ["shield","trap","absorb"]:
		pivot.rotation.y=-PI/2
	for player in model.find_children("*","AnimationPlayer",true,false):player.stop()
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in mesh.mesh.get_surface_count():
			var source: StandardMaterial3D=mesh.get_active_material(i)
			var mat:=ShaderMaterial.new();mat.shader=preload("res://assets/vfx/status_tokens/restored_authored.gdshader")
			mat.set_shader_parameter("source_map",load("res://assets/vfx/status_tokens/wood_clean.res") if kind in ["shield","absorb"] else source.albedo_texture)
			mat.set_shader_parameter("source_factor",source.albedo_color)
			mat.set_shader_parameter("school_color",display_color)
			mat.set_shader_parameter("keep_green",school=="life" and kind!="absorb")
			mat.set_shader_parameter("thin_shield_glow",kind in ["shield","absorb"])
			mat.set_shader_parameter("clear_center",kind not in ["shield","absorb"])
			mat.set_shader_parameter("floor_token",kind in ["dot","hot"])
			mat.set_shader_parameter("mesh_center",bounds.get_center())
			mat.set_shader_parameter("mesh_factor",factor)
			mesh.set_surface_override_material(i,mat)
	var glyph:=Sprite3D.new();glyph.name="OriginalSchoolMotif"
	glyph.texture=ART.texture(StringName("school_badge_"+school));glyph.pixel_size=(0.48 if kind in ["shield","trap","absorb"] else 0.38)/float(glyph.texture.get_width());glyph.shaded=false;glyph.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# The authored shield is only 0.11 deep after normalization; the old 0.18
	# offset floated the motif visibly ahead of it when seen along the orbit.
	var front_bounds:=AABB();var first_face:=true
	for part in model.find_children("*","MeshInstance3D",true,false):
		var box: AABB=global_transform.affine_inverse()*part.global_transform*part.get_aabb()
		front_bounds=box if first_face else front_bounds.merge(box);first_face=false
	if is_planar:
		# DOT/HOT markers sit on the arena floor. Their authored base is already
		# turned horizontal above; keep the replacement school motif on that same
		# surface instead of leaving it as an upright billboard.
		glyph.position=Vector3(0,0.045,0)
		glyph.rotation.x=-PI/2
	else:
		glyph.position=Vector3(0,0,front_bounds.end.z+0.004)
	glyph.billboard=BaseMaterial3D.BILLBOARD_DISABLED
	glyph.no_depth_test=false
	add_child(glyph)

