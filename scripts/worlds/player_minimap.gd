extends Control
## North-up player map, using the existing world presence stream.
const Symbols=preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd")
var atlas: Node
var entries: Array[Dictionary]=[]
var origin:=Vector3.ZERO
var forward:=Vector2.UP
var map_range:=80.0
var tick:=0.0
var terrain_view: SubViewport
var terrain_camera: Camera3D
var terrain_world: Node3D

var regions: Array=[]
var encounter_markers:Array[Dictionary]=[]
var region_name:="旅人地图"

var CENTER:=Vector2(150,151)
var RADIUS:=102.0
var expanded:=false
var map_origin:=Vector3.ZERO
var world_center:=Vector3.ZERO
var world_range:=800.0
var previous_mouse_mode:=Input.MOUSE_MODE_VISIBLE
var mobile_layout:=false
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left=-322;offset_right=-22;offset_top=20;offset_bottom=322
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	terrain_view=SubViewport.new();terrain_view.size=Vector2i(256,256)
	terrain_view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	terrain_view.handle_input_locally=false;terrain_view.gui_disable_input=true
	add_child(terrain_view)
	terrain_camera=Camera3D.new();terrain_camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	terrain_camera.near=1.0;terrain_camera.far=6000.0
	terrain_view.add_child(terrain_camera);terrain_camera.current=true
	var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("43616f");environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("c6dce8");environment.ambient_light_energy=0.8
	terrain_camera.environment=environment

func set_mobile_layout(value: bool) -> void:
	mobile_layout=value
	if not expanded:_apply_collapsed_layout()

func _apply_collapsed_layout() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left=-322;offset_right=-22;offset_top=124 if mobile_layout else 20;offset_bottom=426 if mobile_layout else 322

func _process(delta: float) -> void:
	visible=is_instance_valid(atlas.world) and atlas.world.ready_world and not atlas.busy and not atlas.debug_panel.visible
	if not visible:return
	tick+=delta
	if tick<0.1:return
	tick=0.0
	origin=atlas.world.player.position
	var facing: Vector3=-atlas.world.avatar.basis.z
	forward=Vector2(facing.x,facing.z).normalized()
	var session: Node=atlas.encounters.session
	var net: Node=session.net
	entries.clear()
	entries.append({"point":origin,"name":str(Accounts.active_character.get("name","冒险者")),"school":atlas.current_school,"self":true})
	var reach:=80.0
	if net.connected:
		for peer in net.positions:
			if int(peer)==session.local_id():continue
			var profile: Dictionary=net.appearances.get(peer,{})
			var point: Vector3=net.positions[peer]
			entries.append({"point":point,"name":str(profile.get("name","冒险者")),"school":str(profile.get("school","life")),"self":false})
			reach=maxf(reach,Vector2(point.x-origin.x,point.z-origin.z).length()*1.18)
	# Expand immediately so every connected player remains visible; shrink smoothly.
	map_range=reach if reach>map_range else lerpf(map_range,reach,0.12)
	if terrain_world!=atlas.world:
		terrain_world=atlas.world;terrain_view.world_3d=atlas.world.get_world_3d()
		regions=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/frost_map_regions.json")) if "frostroarisland_teen" in str(atlas.world.world_root) else []
		encounter_markers.clear()
		if atlas.world.has_meta("orchard_procedural_world"):
			regions=atlas.world.get_meta("orchard_map_regions",[]).duplicate(true)
			for lesson in preload("res://scripts/server/star_orchard_tutorial.gd").all_sites():
				encounter_markers.append({"point":Vector3(lesson.center[0],lesson.center[1],lesson.center[2]),"label":"教程%d · %s" % [int(lesson.order),str(lesson.label)],"boss":false,"tutorial_id":str(lesson.id)})
		elif "star_orchard" in str(atlas.world.world_root):
			var satellites: Dictionary = preload("res://scripts/worlds/star_orchard_satellites.gd").document()
			regions=[{"name":"果园主岛", "center":[960,-225], "radius":360}]
			for profile in preload("res://scripts/worlds/orchard_coastal_catalog.gd").profiles():
				regions.append({"name":profile.name,"center":[profile.center.x,profile.center.y],"radius":285.0})
				var form := preload("res://scripts/worlds/orchard_coastal_landform.gd").new(true,int(profile.id))
				for court in form.courts:
					encounter_markers.append({"point":Vector3(court.center.x,court.height,court.center.y),"label":"预留","boss":false,"source":"战斗盘预留场地"})
			for island in satellites.islands:
				var sea_point: Array = island.get("sea_entry",island.center)
				regions.append({"name":island.name, "center":[sea_point[0],sea_point[2]], "radius":minf(float(island.radii[0]),300.0)})
				if str(island.id)=="orchard_wind":
					var oasis := preload("res://scripts/worlds/orchard_oasis_style.gd")
					regions.append({"name":"云冠西园", "center":[float(island.entry[0])-oasis.EXTENSION_SHIFT,float(island.entry[2])], "radius":245.0})
					regions.append({"name":"云冠绿谷", "center":[oasis.JOIN_X,-130.0], "radius":160.0})
			for anchor in preload("res://scripts/worlds/star_orchard_satellites.gd").resolved_anchors():
				if not preload("res://scripts/worlds/star_orchard_satellites.gd").battle_courts_enabled():continue
				if anchor.island_id == "orchard_temple":continue
				encounter_markers.append({"point":Vector3(anchor.center[0],anchor.center[1],anchor.center[2]),"label":"","boss":false,"source":"星庭战斗锚点"})
		if "frostroarisland_teen" in str(atlas.world.world_root) and not regions.is_empty():
			for site in preload("res://scripts/server/frost_encounter_catalog.gd").all_sites():
				if int(site.get("order",0))<=3 or bool(site.get("boss",false)):
					encounter_markers.append({"point":Vector3(float(site.center[0]),float(site.center[1]),float(site.center[2])),"label":str(site.get("map_marker",site.name)),"boss":bool(site.get("boss",false)),"source":str(site.get("source_hint",site.get("source","")))})
		terrain_camera.current=true
		_measure_world()
	region_name="旅人地图"
	var nearest:=INF
	for region in regions:
		var distance:=Vector2(origin.x-region.center[0],origin.z-region.center[1]).length()
		if distance<float(region.radius) and distance<float(nearest):nearest=distance;region_name=region.name
	map_origin=world_center if expanded else origin
	if expanded:map_range=maxf(world_range,reach)
	# Capture terrain and player markers at the same cadence to keep them aligned.
	terrain_camera.size=map_range*2.0
	terrain_camera.position=Vector3(map_origin.x,maxf(origin.y+700.0,700.0),map_origin.z)
	if expanded and atlas.world.has_meta("orchard_procedural_world"):
		terrain_camera.position.y=maxf(terrain_camera.position.y,1600.0)
	terrain_camera.look_at(Vector3(map_origin.x,0,map_origin.z),Vector3(0,0,-1))
	terrain_view.render_target_update_mode=SubViewport.UPDATE_ONCE
	queue_redraw()
func project(point: Vector3) -> Vector2:
	return CENTER+Vector2(point.x-map_origin.x,point.z-map_origin.z)*RADIUS/map_range
func _draw() -> void:
	draw_style_box(preload("res://scripts/fusion_3d/combat_scroll_skin.gd").style(false),Rect2(Vector2.ZERO,size))
	var area:=Rect2(CENTER-Vector2.ONE*RADIUS,Vector2.ONE*RADIUS*2.0)
	draw_rect(area.grow(3),Color("b39759"))
	draw_rect(area,Color("151e25"))
	if is_instance_valid(terrain_view) and terrain_world!=null:
		draw_texture_rect(terrain_view.get_texture(),area,false)
	for region in regions:
		var point:=project(Vector3(region.center[0],0,region.center[1]))
		if not area.grow(-45).has_point(point):continue
		draw_string_outline(ThemeDB.fallback_font,point-Vector2(45,0),region.name,HORIZONTAL_ALIGNMENT_CENTER,90,12,4,Color("182431"))
		draw_string(ThemeDB.fallback_font,point-Vector2(45,0),region.name,HORIZONTAL_ALIGNMENT_CENTER,90,12,Color("fff0be"))
	for marker in encounter_markers:
		if marker.has("tutorial_id"):
			if not atlas.encounters.has_method("current_tutorial_id") or marker.tutorial_id != atlas.encounters.current_tutorial_id():continue
		var marker_at:=project(marker.point)
		if not area.grow(-10).has_point(marker_at):continue
		var marker_color:=Color("ffcf63") if marker.boss else Color("91ddff")
		draw_circle(marker_at,7.0,Color("14232ddd"))
		draw_arc(marker_at,7.0,0,TAU,20,marker_color,2.0,true)
		if expanded:
			draw_string_outline(ThemeDB.fallback_font,marker_at+Vector2(9,4),str(marker.label),HORIZONTAL_ALIGNMENT_LEFT,190,12,3,Color("14232d"))
			draw_string(ThemeDB.fallback_font,marker_at+Vector2(9,4),str(marker.label),HORIZONTAL_ALIGNMENT_LEFT,190,12,marker_color)
	var font:=ThemeDB.fallback_font
	draw_string(font,Vector2(20,29),(str(atlas.world.world_title)+" · 大地图" if expanded else region_name),HORIZONTAL_ALIGNMENT_LEFT,size.x-100,18,Color("ffedc4"))
	if expanded:
		var hint := "蓝色：入门营地 · 金色：永久翅膀 Boss（现有营地）"
		if atlas.world.has_meta("orchard_procedural_world"):
			hint="高山天空城 · 绕山步道 · 半山预留平台 · 南岸港湾"
		elif "star_orchard" in str(atlas.world.world_root):
			hint="五系果岛 · 西侧栈桥通行 · 各岛预留战斗场地"
		draw_string(font,Vector2(20,50),hint,HORIZONTAL_ALIGNMENT_LEFT,size.x-40,13,Color("d9e9ef"))
	draw_string(font,Vector2(size.x-73,29),"%d 人" % entries.size(),HORIZONTAL_ALIGNMENT_RIGHT,53,14,Color("e6d3a7"))
	draw_string(font,Vector2(CENTER.x-8,47),"北",HORIZONTAL_ALIGNMENT_CENTER,16,13,Color("e6d3a7"))
	var used: Array[Rect2]=[]
	for entry in entries:
		var at:=project(entry.point)
		if not area.grow(-15).has_point(at):continue
		if entry.self:draw_arc(at,15,0,TAU,32,Color("ffe3a0"),2,true)
		var icon: Texture2D=Symbols.ui_symbol(StringName("school_"+entry.school))
		if icon!=null:draw_texture_rect(icon,Rect2(at-Vector2(11,11),Vector2(22,22)),false)
		var label:=Rect2(at+Vector2(-46,15),Vector2(92,20))
		label.position.x=clampf(label.position.x,14,size.x-106)
		for placed in used:
			if label.intersects(placed):label.position.y=placed.end.y+2
		used.append(label)
		draw_style_box(_label_background(),label)
		draw_string(font,label.position+Vector2(2,15),entry.name,HORIZONTAL_ALIGNMENT_CENTER,88,13,Color("fff3d5") if entry.self else Color("d9e9ef"))
	var self_at:=project(origin)
	var tip:=self_at+forward*36
	var side:=Vector2(-forward.y,forward.x)
	draw_colored_polygon(PackedVector2Array([tip,self_at+forward*19+side*6,self_at+forward*22,self_at+forward*19-side*6]),Color("ffe09b"))
	draw_string(font,Vector2(16,size.y-23),"X %.0f  ·  Z %.0f  ·  高度 %.0f" % [origin.x,origin.z,origin.y],HORIZONTAL_ALIGNMENT_CENTER,size.x-32,14,Color("fff0cb"))
	draw_string(font,Vector2(16,size.y-6),("M / Esc 收起 · 北向固定" if expanded else "M 大地图 · 北向固定"),HORIZONTAL_ALIGNMENT_CENTER,size.x-32,11,Color("c6b991"))
func _label_background() -> StyleBoxFlat:
	var box:=StyleBoxFlat.new();box.bg_color=Color("101921c9");box.set_corner_radius_all(3);return box

func _measure_world() -> void:
	var bounds:=Rect2()
	var first:=true
	for tile in atlas.world.data.get("terrain",[]):
		var start: Vector2=Vector2(float(tile.tile[0]),float(tile.tile[1]))*atlas.world.terrain_size-atlas.world.origin
		var rect:=Rect2(start,Vector2.ONE*atlas.world.terrain_size)
		bounds=rect if first else bounds.merge(rect)
		first=false
	world_center=Vector3(bounds.get_center().x,0,bounds.get_center().y) if not first else origin
	world_range=maxf(200.0,maxf(bounds.size.x,bounds.size.y)*0.55)
	# Frost Island's terrain tiles contain a large ocean margin. Frame its authored
	# regions instead so the island fills the expanded map while keeping every
	# region, marker and label on the same world-space projection.
	if not regions.is_empty():
		var region_bounds:=Rect2()
		var first_region:=true
		for region in regions:
			var center:=Vector2(float(region.center[0]),float(region.center[1]))
			var radius:=float(region.radius)
			var region_rect:=Rect2(center-Vector2.ONE*radius,Vector2.ONE*radius*2.0)
			region_bounds=region_rect if first_region else region_bounds.merge(region_rect)
			first_region=false
		if not first_region:
			world_center=Vector3(region_bounds.get_center().x,0,region_bounds.get_center().y)
			# Keep the harbour spawn and its marker inside the safe label area.
			world_range=maxf(200.0,maxf(region_bounds.size.x,region_bounds.size.y)*0.70)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if not is_visible_in_tree() or atlas.busy:return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:return
	if event.keycode==KEY_M or (expanded and event.keycode==KEY_ESCAPE):
		set_expanded(not expanded)
		get_viewport().set_input_as_handled()

func set_expanded(value: bool) -> void:
	expanded=value
	if expanded:
		previous_mouse_mode=Input.mouse_mode
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		var extent:=minf(820.0,get_viewport_rect().size.y-60.0)
		set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		offset_left=-extent/2;offset_right=extent/2;offset_top=-extent/2;offset_bottom=extent/2
		CENTER=Vector2(extent/2,extent/2);RADIUS=extent/2-55
		terrain_view.size=Vector2i(768,768)
	else:
		Input.mouse_mode=previous_mouse_mode
		_apply_collapsed_layout()
		CENTER=Vector2(150,151);RADIUS=102.0;map_range=80.0
		terrain_view.size=Vector2i(256,256)
	tick=1.0
	queue_redraw()
