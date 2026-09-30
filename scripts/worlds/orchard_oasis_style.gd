extends RefCounted
## Mature orchard groves and a shared valley joining the original island to its west copy.
const ROOT := "res://assets/worlds/star_orchard/cloud_repaint/"
static var _ground: ShaderMaterial
const EXTENSION_SHIFT := 533.333313*0.75
const JOIN_X := 533.333313*35.0-20000.0+615.0+EXTENSION_SHIFT

static func is_oasis(spec: Dictionary) -> bool:
	return str(spec.id) in ["orchard_wind","orchard_wind_extension"]

static func keep_cell(spec: Dictionary, at: Vector3) -> bool:
	return at.x<JOIN_X if str(spec.id)=="orchard_wind_extension" else at.x>=JOIN_X

static func joined_height(at: Vector3) -> float:
	var weight := 1.0-smoothstep(125.0,175.0,absf(at.x-JOIN_X))
	var across := absf(at.z+130.0)
	# One shared valley floor on both sides of the join, with coastal slopes.
	var ridge := 16.0*exp(-pow((across-132.0)/27.0,2.0))
	var coast := smoothstep(155.0,205.0,across)
	var target := lerpf(228.0+ridge,190.0,coast)
	return lerpf(at.y,target,weight)

static func ground_material() -> ShaderMaterial:
	if _ground!=null:return _ground
	var material := ShaderMaterial.new()
	material.shader=preload("res://assets/worlds/star_orchard/sea_routes/oasis_ground.gdshader")
	material.set_shader_parameter("meadow",surface_texture("orchard_meadow_generated.png"))
	material.set_shader_parameter("sand",surface_texture("orchard_soil_generated.png"))
	material.set_shader_parameter("stone",surface_texture("orchard_stone_generated.png"))
	_ground=material
	return material

static func surface_texture(filename: String) -> Texture2D:
	var texture := load(ROOT+filename) as Texture2D
	var image := texture.get_image()
	if image.has_mipmaps():return texture
	if image.is_compressed():image.decompress()
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

static func is_tree_replacement(path: String) -> bool:
	return "_DesertRocks" in path or "_DesertSmallRock" in path or "_FireBirdLandRock" in path or "_Cactus" in path

static func plant_join_groves(region: Node3D, world: Node3D) -> void:
	var side := -1.0 if str(region.definition.id)=="orchard_wind_extension" else 1.0
	for index in 12:
		var x := JOIN_X+side*(24.0+float(index%3)*24.0)
		var z := -130.0+(-1.0 if index<6 else 1.0)*(42.0+float((index/3)%2)*27.0)
		z+=sin(float(index)*2.4)*7.0
		var y: float=region.surface_height(Vector3(x,400.0,z))
		if not is_finite(y) or y<222.0 or y>250.0:continue
		var at: Vector3=Vector3(x,y,z)-region.source_offset
		plant_tree(region,world,"_DesertRocks_join",Transform3D(Basis.IDENTITY,at),2000+index+(100 if side<0 else 0))

static func plant_tree(region: Node3D, world: Node3D, source: String, original: Transform3D, index: int) -> void:
	var small := "SmallRock" in source or "Cactus" in source
	# Sparse mature groves, rather than one tiny sapling for every pebble.
	var sites: Array=region.get_meta("oasis_tree_sites",[])
	for site: Vector3 in sites:
		if Vector2(site.x-original.origin.x,site.z-original.origin.z).length()<(10.0 if small else 14.0):return
	sites.append(original.origin)
	region.set_meta("oasis_tree_sites",sites)
	var school := "life" if index%5!=0 else "fire"
	var parts: Array=world._v4_parts(school,"A" if index%2==0 else "B")
	if parts.is_empty():return
	var bounds := AABB()
	var first := true
	for part in parts:
		var box: AABB=part.transform*part.mesh.get_aabb()
		bounds=box if first else bounds.merge(box)
		first=false
	var height := (14.0+float(index%4)*1.4) if small else (25.0+float(index%5)*2.0)
	var scale_factor := height/maxf(bounds.size.y,0.01)
	var tree := Node3D.new()
	tree.name="OasisFruitTree_%04d"%index
	region.add_child(tree)
	tree.position=original.origin-Vector3.UP*0.08
	tree.rotation.y=float(index)*2.39996
	tree.set_meta("replaces_source_model",source)
	for part in parts:
		var node := MeshInstance3D.new()
		node.mesh=part.mesh
		node.transform=Transform3D(Basis.IDENTITY.scaled(Vector3(1.12,1.0,1.12)*scale_factor),Vector3(0,-bounds.position.y*scale_factor,0))*part.transform
		tree.add_child(node)
	# Remove the old boulder collision with its visual; only the new trunk is solid.
	var body := StaticBody3D.new()
	tree.add_child(body)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius=0.6 if small else 1.0
	shape.height=height*0.45
	collider.shape=shape
	collider.position.y=shape.height*0.5
	body.add_child(collider)
