extends RefCounted
## School starter clothing, keyed by exact item IDs so other outfits remain independent.
const ClothingShader=preload("res://assets/materials/teen_dye/apprentice_painted.gdshader")
const HatShader=preload("res://assets/materials/teen_dye/apprentice_hat.gdshader")
const CATALOG_PATH="res://resources/fusion_3d/apprentice_painted_v1.json"
static var enabled:=true
static var catalog: Dictionary={}

static func data() -> Dictionary:
	if catalog.is_empty():catalog=JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	return catalog

static func resolve_visuals(chosen: Dictionary,value: Dictionary,store: Node) -> void:
	# Retain owned item IDs while standardizing the Balance starter silhouette.
	var overrides: Dictionary=data().get("visual_overrides",{})
	for slot in ["teen_clothes","teen_boots","teen_hat"]:
		var spec: Dictionary=overrides.get(str(value.get(slot,"")),{})
		if spec.is_empty() or str(spec.gender)!=str(value.gender):continue
		chosen[slot]=chosen[slot].duplicate(true)
		for field in ["texture","model","shape"]:
			if spec.has(field):chosen[slot][field]=spec[field]
		if spec.has("shape"):
			var shape_slot: String="teen_body_shape" if slot=="teen_clothes" else "teen_boot_shape"
			value[shape_slot]=str(value.gender)+"_"+str(int(spec.shape))
			chosen[shape_slot]=store.option(shape_slot,str(value[shape_slot]))

static func apply(avatar: Node3D,value: Dictionary) -> void:
	if not enabled:return
	var entries:=data()
	var clothes: Dictionary=entries.clothes.get(str(value.get("teen_clothes","")),{})
	var boots: Dictionary=entries.get("boots",{}).get(str(value.get("teen_boots","")),{})
	if not clothes.is_empty() and str(value.gender)!=str(clothes.gender):clothes={}
	if not boots.is_empty() and str(value.gender)!=str(boots.gender):boots={}
	if not clothes.is_empty() or not boots.is_empty():
		for id in avatar.parts:
			var part: MeshInstance3D=avatar.parts[id]
			if not part.visible or id<500 or id>=1000:continue
			if id<800 and boots.is_empty():continue
			for surface in part.mesh.get_surface_count():
				var original: Material=part.get_active_material(surface)
				# Existing special/dye shaders own their rendering when selected.
				if not original is BaseMaterial3D:continue
				var material:=ShaderMaterial.new()
				material.shader=ClothingShader
				material.set_shader_parameter("base_map",original.albedo_texture)
				material.set_shader_parameter("has_clothes",not clothes.is_empty())
				material.set_shader_parameter("has_boots",not boots.is_empty())
				if not clothes.is_empty():
					material.set_shader_parameter("painted_map",avatar.read_texture(str(clothes.painted)))
					material.set_shader_parameter("cloth_mask",avatar.read_texture(str(clothes.original)))
				if not boots.is_empty():
					material.set_shader_parameter("boots_map",avatar.read_texture(str(boots.painted)))
					material.set_shader_parameter("boots_mask",avatar.read_texture(str(boots.original)))
				part.set_surface_override_material(surface,material)
	var hat: Dictionary=entries.hats.get(str(value.get("teen_hat","")),{})
	if hat.is_empty() or not avatar.attachments.has("teen_hat"):return
	if str(value.get("gender",""))!=str(hat.gender):return
	var node: Node3D=avatar.attachments.teen_hat
	for mesh in node.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var original: Material=mesh.get_active_material(surface)
			if not original is BaseMaterial3D:continue
			var path: String=str(hat.materials.get(original.resource_name,""))
			if path.is_empty():continue
			if bool(hat.get("preserve_eyewear",false)):
				var painted:=ShaderMaterial.new()
				painted.resource_name=original.resource_name
				painted.shader=HatShader
				painted.set_shader_parameter("original_map",original.albedo_texture)
				painted.set_shader_parameter("painted_map",avatar.read_texture(path))
				mesh.set_surface_override_material(surface,painted)
				continue
			var material: BaseMaterial3D=original.duplicate()
			material.albedo_texture=avatar.read_texture(path)
			material.roughness=0.85
			mesh.set_surface_override_material(surface,material)
