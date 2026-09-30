extends Node3D
## Seven preserved cloud regions around the original orchard. Source assets are read-only.
const CloudRegion = preload("res://scripts/worlds/orchard_cloud_region.gd")
var cloud_regions: Array[Node3D] = []
var battle_courts: Array[Dictionary] = []
const CONFIG := "res://resources/fusion_3d/star_orchard_satellites.json"
const GROUND := "res://assets/worlds/star_orchard/terrain_paint_layers_v1/"
const Layout := preload("res://scripts/worlds/star_orchard_saved_layout.gd")
const Actor := preload("res://scripts/fusion_3d/world_one_monster.gd")
const Style := preload("res://scripts/worlds/star_orchard_npc_style.gd")
var world: Node3D
var config: Dictionary = {}
var portals: Array[Dictionary] = []
var portal_cooldown := 0.0
var last_safe := Vector3.ZERO
var sea_access: Node3D

static func document() -> Dictionary:
	if not preload("res://scripts/worlds/star_orchard_features.gd").SATELLITES_ENABLED:
		return {"islands":[],"anchors":[]}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONFIG))
	return value if value is Dictionary else {}

static func point(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func battle_courts_enabled() -> bool:
	return "--orchard-battle-courts" in OS.get_cmdline_user_args()

static func resolved_anchors() -> Array:
	var anchors: Array = document().get("anchors", []).duplicate(true)
	var path := "user://creative_worlds/star_orchard.json"
	if not FileAccess.file_exists(path):return anchors
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not saved is Dictionary or saved.get("world_root", "") != "res://assets/worlds/star_orchard/":return anchors
	for entry in saved.get("objects", []):
		var id := str(entry.get("satellite_anchor_id", ""))
		if id.is_empty():continue
		for anchor in anchors:
			if anchor.id != id:continue
			var saved_point := point(entry.position)
			if int(entry.get("satellite_layout_version",1)) < 2 and anchor.has("legacy_center"):
				saved_point = point(anchor.center) + saved_point-point(anchor.legacy_center)
			elif int(entry.get("satellite_layout_version",1)) < 3 and anchor.has("layout_v2_center"):
				saved_point = point(anchor.center) + saved_point-point(anchor.layout_v2_center)
			entry = entry.duplicate(true)
			entry.position = [saved_point.x,saved_point.y,saved_point.z]
			var shift := saved_point - point(anchor.position)
			anchor.position = entry.position.duplicate()
			anchor.center = entry.position.duplicate()
			var saved_scale := float(entry.get("scale", [2,2,2])[0])
			if int(entry.get("satellite_layout_version",1)) < 2:
				saved_scale *= float(anchor.scale)/float(anchor.get("legacy_scale",2.0))
			anchor.scale = clampf(saved_scale, 0.5, 4.0)
			anchor.radius = 8.3*float(anchor.scale)
			var approach := point(anchor.approach) + shift
			anchor.approach = [approach.x, approach.y, approach.z]
			for key in ["ramp_start","ramp_end"]:
				if anchor.has(key) and anchor[key] is Array:
					var moved := point(anchor[key])+shift
					anchor[key]=[moved.x,moved.y,moved.z]
	return anchors

func install(target: Node3D) -> void:
	world = target
	config = document()
	for island in config.islands:
		_build_island(island)
		world.destinations.append(point(island.get("sea_entry",island.entry)))
		world.destination_names.append(str(island.name))
	_build_goddess()
	sea_access = preload("res://scripts/worlds/orchard_sea_access.gd").new()
	sea_access.name = "SeaAccess"
	add_child(sea_access)
	sea_access.install(world,self)
	_build_temple()
	var shown_courts: Dictionary={}
	for anchor in resolved_anchors():
		var marker := Marker3D.new()
		marker.name = str(anchor.id)
		marker.position = point(anchor.center)
		marker.set_meta("satellite_anchor", anchor)
		add_child(marker)
		if str(anchor.island_id) != "orchard_temple" and not battle_courts_enabled():continue
		var court_key := str(marker.position)+":"+str(anchor.radius)
		if shown_courts.has(court_key):continue
		shown_courts[court_key]=true
		if str(anchor.island_id) != "orchard_temple":_battle_court(anchor)
		if not "--orchard-editor" in OS.get_cmdline_user_args():
			var ring := TorusMesh.new()
			ring.inner_radius=float(anchor.radius)-0.20
			ring.outer_radius=float(anchor.radius)
			ring.rings=64
			ring.ring_segments=6
			var stone := StandardMaterial3D.new()
			stone.albedo_color=Color("b7b5a1")
			stone.roughness=0.98
			_mesh(marker,ring,stone,"BattleCourtInlay",false).position.y=0.14
	last_safe = point(config.main_return)
	print("ORCHARD_SATELLITES_READY islands=7 anchors=22 portals=", portals.size())

func surface_height(at: Vector3) -> float:
	if is_instance_valid(sea_access):
		var access_height: float = sea_access.surface_height(at)
		if is_finite(access_height):return access_height
	for court in battle_courts:
		var center: Vector3 = court.center
		if Vector2(at.x-center.x,at.z-center.z).length() <= float(court.radius):
			return center.y
	for region in cloud_regions:
		if not region.visible:continue
		var value: float = region.surface_height(at)
		if is_finite(value):return value
	var temple: Dictionary = config.get("temple", {})
	if not temple.is_empty():
		var center := point(temple.center)
		if at.y > 9000 and Vector2(at.x-center.x, at.z-center.z).length() < 32:return center.y
	return -INF

func _build_island(island: Dictionary) -> void:
	var region := CloudRegion.new()
	add_child(region)
	region.install(world,island)
	cloud_regions.append(region)
	if str(island.id)=="orchard_wind":
		var extension: Dictionary=island.duplicate(true)
		extension.id="orchard_wind_extension"
		extension.source_offset[0]-=preload("res://scripts/worlds/orchard_oasis_style.gd").EXTENSION_SHIFT
		var west := CloudRegion.new()
		add_child(west)
		west.install(world,extension)
		cloud_regions.append(west)
	_npc(island)
	_label(self,str(island.name),point(island.entry)+Vector3(0,11,0),46)
	var investigation := Marker3D.new()
	investigation.name = str(island.id)+"_investigate"
	investigation.position = point(island.investigate)
	investigation.set_meta("orchard_island_id", str(island.id))
	add_child(investigation)

func _battle_court(anchor: Dictionary) -> void:
	# A thin removable game board over the source ground; no source vertex is flattened.
	var center := point(anchor.center)
	var radius := float(anchor.radius)
	var disk := CylinderMesh.new()
	disk.top_radius=radius
	disk.bottom_radius=radius
	disk.height=0.3
	disk.radial_segments=64
	var material := StandardMaterial3D.new()
	material.albedo_texture=load(GROUND+"material_paving.png")
	material.albedo_color=Color("b6c3a0")
	material.uv1_scale=Vector3(3,3,3)
	material.roughness=1.0
	if str(anchor.island_id)=="orchard_grove":
		material.albedo_color=Color("bfab80")
		var bridge := "res://assets/worlds/_shared_models/d5a9caa379378816_ELongChaoXue_muqiao.glb"
		for part in world.prototypes.get(bridge,[]):
			var original: Material=part.mesh.surface_get_material(0)
			if original is StandardMaterial3D and original.albedo_texture!=null:
				material.albedo_texture=original.albedo_texture
				break
	var node := _mesh(self,disk,material,"SourceBattleCourt_"+str(anchor.id),true)
	node.position=center-Vector3.UP*0.15
	node.set_meta("source_ground_unchanged",true)
	battle_courts.append({"center":center,"radius":radius})
	if str(anchor.island_id)=="orchard_grove":_timber_supports(anchor,material)

func _timber_supports(anchor: Dictionary, material: Material) -> void:
	var center := point(anchor.center)
	for along_x in [true,false]:
		var beam := BoxMesh.new()
		beam.size=Vector3(32,0.9,1.5) if along_x else Vector3(1.5,0.9,32)
		_mesh(self,beam,material,"OrchardDeckTimberBeam",true).position=center-Vector3.UP*0.7
	for dx in [-3.0,3.0]:
		for dz in [-3.0,3.0]:
			var foot := center+Vector3(dx,0,dz)
			var ground := -INF
			for region in cloud_regions:
				if region.name=="orchard_grove":ground=region.surface_height(foot)
			if not is_finite(ground):continue
			var length := maxf(1.2,center.y-ground+0.4)
			var post := BoxMesh.new()
			post.size=Vector3(1.1,length,1.1)
			_mesh(self,post,material,"OrchardDeckTimberPost",true).position=Vector3(foot.x,center.y-length*0.5-0.2,foot.z)
	if not anchor.get("ramp_end") is Array:return
	var start := point(anchor.ramp_start)
	var end := point(anchor.ramp_end)+Vector3.UP*0.08
	var a := start+Vector3(-2.8,0,0)
	var b := start+Vector3(2.8,0,0)
	var c := end+Vector3(2.8,0,0)
	var d := end+Vector3(-2.8,0,0)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in [a,c,b,a,d,c]:
		surface.set_uv(Vector2(vertex.x,vertex.z)*0.16)
		surface.add_vertex(vertex)
	surface.generate_normals()
	_mesh(self,surface.commit(),material,"OrchardDeckAccessRamp",true)

func _mesh(parent: Node3D, mesh: Mesh, material: Material, title: String, solid: bool) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = title
	visual.mesh = mesh
	visual.material_override = material
	parent.add_child(visual)
	if solid:visual.create_trimesh_collision()
	return visual

func _npc(island: Dictionary) -> void:
	var root := Node3D.new()
	root.name=str(island.npc.id)
	add_child(root)
	root.position=point(island.npc.position)
	root.set_meta("orchard_island_id",str(island.id))
	root.set_meta("layout_entry",{"kind":"npc","npc_id":island.npc.model,"name":str(island.name)+"引路人","position":island.npc.position})
	var actor := Actor.new()
	actor.model_id=str(island.npc.model)
	root.add_child(actor)
	actor.scale=Vector3.ONE*2.0
	Style.apply_to(actor,actor.model_id)
	Layout.play_actor(actor,actor.model_id,"")
	_label(root,str(island.name)+"引路人",Vector3(0,6,0),30)

func _label(parent: Node3D, title: String, at: Vector3, font_size: int) -> void:
	var label := Label3D.new()
	label.text=title
	label.position=at
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size=font_size
	label.pixel_size=0.014
	label.modulate=Color("fff1c4")
	label.visibility_range_end=160
	parent.add_child(label)

func _portal(at: Vector3, target: Vector3, title: String, color: Color) -> void:
	portals.append({"point":at,"target":target})
	var material := StandardMaterial3D.new()
	material.albedo_color=color
	material.emission_enabled=true
	material.emission=color*0.4
	var ring := TorusMesh.new()
	ring.inner_radius=3.4
	ring.outer_radius=4.2
	var visual := _mesh(self,ring,material,"TravelSigil",false)
	visual.position=at+Vector3.UP*0.3
	_label(self,title+"\n踏入光环传送",at+Vector3.UP*6,32)
	for direction in [-1,1]:
		var pillar := CylinderMesh.new()
		pillar.top_radius=0.45
		pillar.bottom_radius=0.65
		pillar.height=4.5
		var post := _mesh(self,pillar,material,"GateLantern",true)
		post.position=at+Vector3(direction*4.8,2.2,0)

func _build_routes() -> void:
	var islands: Array = config.islands
	_label(self,"秩序神殿 · 踏入原传送门",Vector3(1247,279,-311),38)
	_label(self,"返回果园 · 原传送门",Vector3(1138,10272,-46),34)
	_portal(point(config.main_gate),point(islands[0].entry)+Vector3(8,1,0),"星庭航路 · "+str(islands[0].name),Color("f2cb81"))
	for i in islands.size():
		var island: Dictionary=islands[i]
		var previous: Vector3=point(config.main_return) if i==0 else point(islands[i-1].exit)+Vector3(-9,1,0)
		var next: Vector3=point(config.main_return) if i==islands.size()-1 else point(islands[i+1].entry)+Vector3(9,1,0)
		_portal(point(island.entry),previous,"返回主岛" if i==0 else "返回 · "+str(islands[i-1].name),Color("a1cee0"))
		_portal(point(island.exit),next,"归航 · 主岛" if i==islands.size()-1 else "前往 · "+str(islands[i+1].name),Color("efd096"))
		_portal(point(island["return"]),point(config.main_return),"整备捷径 · 主岛",Color("a9dfc4"))

func _build_temple() -> void:
	var center := point(config.temple.center)
	var stone := StandardMaterial3D.new()
	stone.albedo_texture=load(GROUND+"material_paving.png")
	stone.uv1_scale=Vector3(4,4,4)
	var disk := CylinderMesh.new()
	disk.top_radius=32
	disk.bottom_radius=25
	disk.height=7
	disk.radial_segments=64
	var visual := _mesh(self,disk,stone,"TempleBattleForecourt",true)
	visual.position=center-Vector3.UP*3.5
	_portal(Vector3(1138,10265,-24),point(config.temple.entry)+Vector3(0,1,-8),"神殿 · 星核外庭",Color("efce89"))
	_portal(point(config.temple.entry),point(config.temple["return"]),"返回神殿",Color("a9d8ee"))
	_label(self,"星核外庭",center+Vector3(0,8,-27),42)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(world) or not world.ready_world or world.input_suspended:return
	portal_cooldown=maxf(0,portal_cooldown-delta)
	var at: Vector3=world.player.position
	var height := surface_height(at)
	if is_finite(height) and absf(at.y-height)<5:
		for island in config.islands:
			var entry := point(island.entry)
			if Vector2(at.x-entry.x,at.z-entry.z).length()<900:
				last_safe=entry+Vector3(0,2,8)
	# Source worlds span several kilometres; rescue below their lowest authored ground.
	if not world.flight.flying and at.y < 150 and Vector2(at.x-950,at.z+220).length()>600:
		world._travel_gate(last_safe)
		portal_cooldown=2
		return
	if portal_cooldown>0:return
	for portal in portals:
		var gate: Vector3=portal.point
		if absf(at.y-gate.y)<4 and Vector2(at.x-gate.x,at.z-gate.z).length()<3.0:
			world._travel_gate(portal.target)
			portal_cooldown=2.0
			return

func _build_goddess() -> void:
	var root := Node3D.new()
	root.name="orchard_goddess"
	root.position=point(config.goddess.position)
	root.set_meta("layout_entry", {"kind":"npc","npc_id":config.goddess.model,"name":"星庭女神","position":config.goddess.position})
	add_child(root)
	var actor := Actor.new()
	actor.model_id=str(config.goddess.model)
	root.add_child(actor)
	actor.scale=Vector3.ONE*2
	Style.apply_to(actor,actor.model_id)
	Layout.play_actor(actor,actor.model_id,"")
	_label(root,"星庭女神",Vector3(0,7,0),36)
