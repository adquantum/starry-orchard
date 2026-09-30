extends Node3D
## A true spherical delayed-damage token, facing outward on the shared floor orbit.
const COLORS={"fire":Color("ed623c"),"ice":Color("68caea"),"storm":Color("a981ef"),"myth":Color("e4b94f"),"life":Color("71c862"),"death":Color("b6a4dc"),"balance":Color("cf9067"),"all":Color("d6d8ed")}
func setup(school_id: String) -> void:
	var school:=school_id if COLORS.has(school_id) else "all"
	var color: Color=COLORS[school]
	set_meta("design","delay_bomb_v1")
	set_meta("school_symbol",school)
	set_meta("planar_status",false)
	var material:=StandardMaterial3D.new()
	material.albedo_color=color.darkened(0.40);material.roughness=0.9;material.metallic=0.0
	$Body.material_override=material
	var fuse_material:=StandardMaterial3D.new()
	fuse_material.albedo_color=color.lightened(0.4);fuse_material.roughness=1.0
	$Fuse.material_override=fuse_material
	var spark_material:=StandardMaterial3D.new()
	spark_material.albedo_color=color; spark_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	$FuseTip.material_override=spark_material
	# Conformal school decal follows the spherical body; it is not a floating billboard.
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in 10:
		for x in 10:
			for offset in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,0),Vector2i(1,1),Vector2i(0,1)]:
				var uv:=Vector2(x+offset.x,y+offset.y)/10.0
				var longitude: float=(uv.x-0.5)*1.55
				var latitude: float=(0.5-uv.y)*1.55
				var normal:=Vector3(sin(longitude)*cos(latitude),sin(latitude),cos(longitude)*cos(latitude))
				st.set_uv(uv);st.set_normal(normal);st.add_vertex(normal*0.284)
	var decal:=MeshInstance3D.new();decal.name="SchoolEmblem";decal.mesh=st.commit();add_child(decal)
	var decal_material:=StandardMaterial3D.new()
	decal_material.albedo_texture=ArtRegistryV2.texture(StringName("school_badge_"+school))
	decal_material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	decal_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	decal_material.cull_mode=BaseMaterial3D.CULL_DISABLED
	decal.material_override=decal_material
	for part in find_children("*","MeshInstance3D",true,false):part.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
