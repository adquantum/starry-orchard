extends "res://scripts/worlds/frostroarisland_teen.gd"
## Independent work-copy; only its explicitly approved outer transition areas are reshaped.
const EXPANSION_ROOT := "res://assets/worlds/frostroarisland_expanded/"
var expansion_manifest: Dictionary = {}
var ice_spans: Array = []

func _ready() -> void:
	super._ready()
	# Base loading is deferred, so select the work-copy before it starts.
	world_root = EXPANSION_ROOT
	world_title = "冰霜岛 · 五区扩展工作副本"
	capture_root = "res://docs/frostroarisland_expanded/"
	expansion_manifest = JSON.parse_string(FileAccess.get_file_as_string(EXPANSION_ROOT + "expansion_manifest.json"))
	if variants_enabled:
		for assignment in expansion_manifest.variants:
			variant_assignments[int(assignment.index)] = assignment
	for region in expansion_manifest.regions:
		destinations.append(Vector3(float(region.view[0]),float(region.view_height)+3.0,float(region.view[1])))
		destination_names.append(str(region.name) + " · 外扩带")

func _build_terrain(entry: Dictionary) -> void:
	var first := get_child_count()
	super._build_terrain(entry)
	if not entry.has("expansion_weights"):return
	for i in range(first,get_child_count()):
		var surface := get_child(i) as MeshInstance3D
		if surface == null:continue
		var material := surface.material_override as ShaderMaterial
		# Runtime image loading also works before an editor import has run.
		var image := Image.load_from_file(str(entry.expansion_weights))
		image.generate_mipmaps()
		material.set_shader_parameter("has_weights",true)
		material.set_shader_parameter("layer_weights",ImageTexture.create_from_image(image))

func _configure_world_water(material: ShaderMaterial) -> void:
	var saved_root := world_root
	world_root = "res://assets/worlds/frostroarisland_teen/"
	super._configure_world_water(material)
	world_root = saved_root

func _build_water() -> void:
	super._build_water()
	if not "--frost-village-off" in OS.get_cmdline_user_args():
		var village := Node3D.new()
		village.set_script(load("res://scripts/worlds/frost_village.gd"))
		add_child(village)
		village.build(self)
	for region in expansion_manifest.regions:
		if str(region.id)=="peak" and expansion_manifest.get("peak_bridge_material","")=="wood":
			_build_peak_wood_bridge(region.bridges)
			continue
		var top := SurfaceTool.new()
		var sides := SurfaceTool.new()
		top.begin(Mesh.PRIMITIVE_TRIANGLES)
		sides.begin(Mesh.PRIMITIVE_TRIANGLES)
		if region.bridges.is_empty():continue
		for segment in region.bridges:
			var a := Vector3(float(segment[0][0]),float(segment[0][1]),float(segment[0][2]))
			var b := Vector3(float(segment[1][0]),float(segment[1][1]),float(segment[1][2]))
			var side := Vector3(-(b-a).z,0,(b-a).x).normalized()*8.0
			ice_spans.append({"a":a,"b":b,"half_width":8.0})
			var corners := [a-side,a+side,b+side,b-side]
			for index in [0,2,1,0,3,2]:
				var point: Vector3 = corners[index]
				top.set_uv(Vector2(point.x,point.z)/16.0)
				top.add_vertex(point)
			for pair in [[0,3],[2,1]]:
				var first: Vector3 = corners[pair[0]]
				var second: Vector3 = corners[pair[1]]
				var low_first := first-Vector3.UP*8.0
				var low_second := second-Vector3.UP*8.0
				for point in [first,second,low_second,first,low_second,low_first]:
					sides.set_uv(Vector2(point.x+point.z,point.y)/16.0)
					sides.add_vertex(point)
		top.generate_normals()
		sides.generate_normals()
		var mesh := top.commit()
		sides.commit(mesh)
		var snow := StandardMaterial3D.new()
		snow.albedo_texture=load("res://assets/worlds/frostroarisland_teen/terrain_repaint_v1/snow.png")
		snow.roughness=0.97
		snow.cull_mode=BaseMaterial3D.CULL_DISABLED
		var ice := snow.duplicate() as StandardMaterial3D
		ice.albedo_texture=load("res://assets/worlds/frostroarisland_teen/terrain_repaint_v1/ice.png")
		ice.albedo_color=Color("bdddea")
		mesh.surface_set_material(0,snow)
		mesh.surface_set_material(1,ice)
		var visual := MeshInstance3D.new()
		visual.name="OuterIceConnection_"+str(region.id)
		visual.mesh=mesh
		add_child(visual)
		visual.create_trimesh_collision()

func _bridge_box(surface: SurfaceTool, at: Vector3, basis: Basis, size: Vector3) -> void:
	var box := BoxMesh.new()
	box.size=size
	surface.append_from(box,0,Transform3D(basis,at))

func _build_peak_wood_bridge(segments: Array) -> void:
	if segments.is_empty():return
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name="PeakWoodBridgeFloorAndRails"
	add_child(body)
	for segment in segments:
		var a := Vector3(float(segment[0][0]),float(segment[0][1]),float(segment[0][2]))
		var b := Vector3(float(segment[1][0]),float(segment[1][1]),float(segment[1][2]))
		var forward := (b-a).normalized()
		var right := Vector3(forward.z,0,-forward.x).normalized()
		var up := forward.cross(right).normalized()
		var basis := Basis(right,up,forward)
		var length := a.distance_to(b)
		ice_spans.append({"a":a,"b":b,"half_width":5.0})
		# Thin continuous collision underneath separate visible planks.
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size=Vector3(10.0,.55,length+.03)
		collision.shape=shape
		collision.transform=Transform3D(basis,(a+b)*.5-up*.275)
		body.add_child(collision)
		var plank_count := maxi(1,ceili(length/.95))
		for i in plank_count:
			var at := a.lerp(b,(float(i)+.5)/float(plank_count))-up*.275
			_bridge_box(surface,at,basis,Vector3(10.0,.55,length/float(plank_count)-.025))
		for sign_value in [-1.0,1.0]:
			var side: Vector3 = right*4.85*float(sign_value)
			_bridge_box(surface,a+side+up*1.1,basis,Vector3(.5,2.9,.5))
			_bridge_box(surface,(a+b)*.5+side-up*.8,basis,Vector3(.65,.8,length+.04))
			for height in [1.05,2.25]:
				_bridge_box(surface,(a+b)*.5+side+up*height,basis,Vector3(.28,.28,length+.06))
			var rail_shape := BoxShape3D.new()
			rail_shape.size=Vector3(.45,2.8,length+.04)
			var rail := CollisionShape3D.new()
			rail.shape=rail_shape
			rail.transform=Transform3D(basis,(a+b)*.5+side+up*1.2)
			body.add_child(rail)
	var material := ShaderMaterial.new()
	material.shader=load("res://scripts/worlds/frost_bridge_wood.gdshader")
	material.set_shader_parameter("wood_atlas",load("res://assets/worlds/frostroarisland_teen/restyle_all/fuqiao_b19c49b6_painted.png"))
	var visual := MeshInstance3D.new()
	visual.name="PeakWoodBridge"
	visual.mesh=surface.commit()
	visual.material_override=material
	add_child(visual)

func _height(at: Vector3) -> float:
	var result := super._height(at)
	for span in ice_spans:
		var a: Vector3=span.a
		var b: Vector3=span.b
		var delta := Vector2(b.x-a.x,b.z-a.z)
		var offset := Vector2(at.x-a.x,at.z-a.z)
		var t := offset.dot(delta)/delta.length_squared()
		if t < 0.0 or t > 1.0:continue
		if (offset-delta*t).length() <= float(span.half_width):
			result=maxf(result,lerpf(a.y,b.y,t))
	return result
