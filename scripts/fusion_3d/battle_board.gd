extends Node3D
## Three Blender components; slots keep the battle's shared coordinate reference.
const APPEARANCE = preload("res://assets/shaders/battle_board_regional.gdshader")
const ARROW_PATH = "res://assets/models/battle_board/runtime/sequence_arrow.glb"
var appearance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/battle_board_appearance.json"))
var pointer_geometry: Node3D
var center_model: Node3D
var arrow_model: Node3D
var indicator: Node3D
var slot_nodes: Dictionary={}
var slot_highlights: Dictionary={}
var geometry: Array[MeshInstance3D]=[]
var indicator_materials: Array[Material]=[]
var active_id: StringName=&""
var arrival_light: MeshInstance3D
var arrival_material: ShaderMaterial
func set_arrival_progress(progress: float, existing_board: bool=false) -> void:
	var t:=clampf(progress,0.0,1.0)
	transparency=0.0 if existing_board else 1.0-smoothstep(0.08,0.72,t)
	if is_instance_valid(arrival_light):
		arrival_light.visible=not existing_board and t>0.0 and t<0.99
		arrival_material.set_shader_parameter("progress",t)
var transparency:=1.0:
	set(value):
		transparency=clampf(value,0,1)
		for node in geometry:
			if node.has_meta("arrival_surface"):
				node.transparency=0.0
				for i in node.mesh.get_surface_count():
					var mat:=node.get_active_material(i)
					if mat is ShaderMaterial:mat.set_shader_parameter("arrival_opacity",1.0-transparency)
					elif mat is StandardMaterial3D:mat.albedo_color.a=1.0-transparency
			else:node.transparency=transparency
func instance(path: String,parent: Node3D) -> Node3D:
	var result: Node3D=load(path).instantiate()
	parent.add_child(result)
	for mesh: MeshInstance3D in result.find_children("*","MeshInstance3D",true,false):
		geometry.append(mesh)
		mesh.transparency=transparency
		if path.ends_with("main_disc.glb") or path.ends_with("standing_circle.glb"):
			mesh.set_meta("arrival_surface",true)
			mesh.transparency=0.0
		for i in mesh.mesh.get_surface_count():
			var source:=mesh.get_active_material(i) as StandardMaterial3D
			if source==null:continue
			var material:=source.duplicate() as StandardMaterial3D
			# User art already contains painted lighting; side bevels retain physical shading.
			if material.albedo_texture!=null:
				material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
				material.emission_enabled=false
			if path.ends_with("main_disc.glb") or path.ends_with("standing_circle.glb"):
				material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
				material.albedo_color.a=1.0-transparency
				if material.albedo_texture != null:
					var painted := ShaderMaterial.new()
					painted.shader=APPEARANCE
					painted.set_shader_parameter("arrival_opacity",1.0-transparency)
					painted.set_shader_parameter("source_texture",material.albedo_texture)
					painted.set_shader_parameter("surface_texture",load("res://assets/models/battle_board/textures/regional_v8/surface.png"))
					painted.set_shader_parameter("orient_runes",path.ends_with("main_disc.glb"))
					var regions: Array[Vector4]=[]
					for id in appearance.rune_centers_px:
						var pt: Array=appearance.rune_centers_px[id]
						var x:=float(pt[0]);var y:=float(pt[1])
						var angle:=atan2(626.0-x,y-618.0)
						regions.append(Vector4(x/1254.0,y/1254.0,float(appearance.patch_radius_px)/1254.0,angle))
					painted.set_shader_parameter("rune_regions",regions)
					mesh.set_surface_override_material(i,painted)
					continue
				material.albedo_color=Color("aaa5bf").darkened(0.65)
				material.albedo_color.a=1.0-transparency
			mesh.set_surface_override_material(i,material)
	return result
func setup(slots: Dictionary) -> void:
	name="ModularBattleBoard"
	instance("res://assets/models/battle_board/main_disc.glb",self).name="MainDisc"
	for id in slots:
		var slot:=Node3D.new()
		slot.name="Slot_"+str(id)
		slot.position=Vector3(slots[id].x,0,slots[id].z)
		add_child(slot)
		instance("res://assets/models/battle_board/standing_circle.glb",slot)
		slot_nodes[id]=slot
		var highlight:=MeshInstance3D.new()
		highlight.name="SelectionLight"
		var torus:=TorusMesh.new()
		torus.inner_radius=1.17
		torus.outer_radius=1.20
		torus.rings=64
		torus.ring_segments=6
		highlight.mesh=torus
		highlight.position.y=.15
		var material:=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=Color("ffdf8e")
		material.emission_enabled=true
		material.emission=Color("ffcc67")
		material.emission_energy_multiplier=.7
		highlight.material_override=material
		highlight.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		slot.add_child(highlight)
		highlight.hide()
		slot_highlights[id]=highlight
		geometry.append(highlight)
	indicator=Node3D.new()
	indicator.name="TurnIndicator"
	add_child(indicator)
	pointer_geometry=preload("res://scripts/fusion_3d/battle_pointer_geometry.gd").new()
	indicator.add_child(pointer_geometry)
	pointer_geometry.build()
	center_model=pointer_geometry.center
	arrow_model=pointer_geometry.pointer
	geometry.append_array(pointer_geometry.meshes)
	indicator_materials.assign(pointer_geometry.materials)
	for material in indicator_materials:
		material.set_shader_parameter("gold_color",Color("aaa5bf"))
	set_caster(&"")
	transparency=transparency
	arrival_light=MeshInstance3D.new();arrival_light.name="ArrivalGroundLight"
	var plane:=PlaneMesh.new();plane.size=Vector2(17.0,17.0)
	arrival_light.mesh=plane;arrival_light.position.y=0.22
	arrival_light.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arrival_material=ShaderMaterial.new();arrival_material.shader=preload("res://assets/shaders/battle_arrival_light.gdshader")
	arrival_light.material_override=arrival_material;add_child(arrival_light);arrival_light.hide()
func set_caster(id: StringName, pointer_id: StringName=&"") -> void:
	if active_id!=id:
		for key in slot_highlights:slot_highlights[key].visible=key==id
	active_id=id
	if pointer_id==&"":pointer_id=id
	# Preserve the last orientation when no living actor remains.
	if pointer_id!=&"":indicator.show()
	if appearance.rune_centers_px.has(str(pointer_id)):
		var at:=rune_center(pointer_id)
		pointer_geometry.set_radius(Vector2(at.x,at.z).length())


func rune_center(id: StringName) -> Vector3:
	var px: Array=appearance.rune_centers_px[str(id)]
	return Vector3((float(px[0])-626.0)/float(appearance.disc_pixels_per_unit),0.17,(float(px[1])-618.0)/float(appearance.disc_pixels_per_unit))

func indicator_angle(id: StringName) -> float:
	var at:=rune_center(id)
	return atan2(-at.x,-at.z)
