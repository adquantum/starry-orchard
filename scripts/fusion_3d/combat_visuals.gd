extends Node3D
## Presentation-only meshes. Source of truth remains BattleEngineV2.
var stage: Node3D
var pip_particles_enabled := true
var entry_effect_progress := 0.0
var entry_effects_started := false
var applied_entry_opacity := -1.0

func _fade_pip_root(root: Node3D, opacity: float) -> void:
	root.visible=opacity>0.0
	for mesh: GeometryInstance3D in root.find_children("*","GeometryInstance3D",true,false):
		mesh.transparency=1.0-opacity

func _update_entry_effects(delta: float) -> void:
	if stage.entering:
		entry_effect_progress=0.0
		entry_effects_started=false
	elif stage.shared_session==null or stage.shared_session.battle_ready:
		entry_effects_started=true
	# Readiness also toggles between rounds; only the entrance resets this fade.
	if entry_effects_started:entry_effect_progress=minf(1.0,entry_effect_progress+delta/0.9)
	var opacity:=smoothstep(0.0,1.0,entry_effect_progress)
	for highlight in stage.arena_surface.slot_highlights.values():
		if opacity<=0.0:highlight.hide()
		highlight.transparency=1.0-opacity
	if is_equal_approx(applied_entry_opacity,opacity):return
	applied_entry_opacity=opacity
	for actor in stage.actors.values():
		var body: Node3D=actor.get_node("Body")
		if "external" in body and is_instance_valid(body.external):
			body.external.battle_effect_opacity=opacity
	for root in pip_nodes.values():
		_fade_pip_root(root,opacity)

## Quality hook: disable particle nodes while retaining resource bodies and icons.
func set_pip_particles_enabled(enabled: bool) -> void:
	pip_particles_enabled = enabled
	for root in pip_nodes.values():
		if not is_instance_valid(root):continue
		for pip in root.get_children():
			if pip.has_method("set_particles_enabled"):
				pip.set_particles_enabled(enabled)

var caster_id: StringName=&""
var ring: Node3D
var caster_halo: Node3D
var clock:=0.0
var pointer_initialized:=false
var status_nodes: Dictionary={}
var pip_nodes: Dictionary={}
var pip_signatures: Dictionary={}
var signatures: Dictionary={}
var orbit_layouts: Dictionary={}
var pending_status_nodes: Dictionary={}
var aura_nodes: Dictionary={}
const PersistentAura = preload("res://scripts/fusion_3d/vfx/persistent_aura.gd")
const GOLD=Color("c6a45e")
const STANDING_CIRCLE_RADIUS := 1.16 # Authored standing_circle.glb XZ bounds.
const PIP_VISUAL_SCALE := 0.85
# Status effects keep their existing orbit, independent of resource placement.
const STATUS_ORBIT_RADIUS := 1.45
const CHARM_KINDS = ["blade", "weakness", "accuracy_blade", "accuracy_weakness", "healing_blade", "infection"]
func setup(value: Node3D) -> void:
	stage=value
	ring=stage.arena_surface.indicator
	caster_halo=Node3D.new()
	add_child(caster_halo)
	arc(caster_halo,1.05,0.045,TAU,Color("fff0b9"))
	arc(caster_halo,1.2,0.025,TAU*0.8,GOLD)
func material(color: Color, glow: bool=false) -> StandardMaterial3D:
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=0.45
	mat.metallic=0.45
	if glow:
		mat.emission_enabled=true
		mat.emission=color
		mat.emission_energy_multiplier=0.6
	return mat
func mesh(parent: Node3D, shape: Mesh, color: Color, glow: bool=false) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=shape
	node.material_override=material(color,glow)
	parent.add_child(node)
	return node
func arc(parent: Node3D, radius: float, width: float, span: float, color: Color) -> MeshInstance3D:
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 80:
		var a: float=-span/2.0+span*i/80.0
		var b: float=-span/2.0+span*(i+1)/80.0
		var points: Array[Vector3]=[]
		for pair in [Vector2(a,radius-width),Vector2(a,radius+width),Vector2(b,radius+width),Vector2(b,radius-width)]:
			points.append(Vector3(sin(pair.x)*pair.y,0,-cos(pair.x)*pair.y))
		for index in [0,2,1,0,3,2]:st.add_vertex(points[index])
	st.generate_normals()
	var node:=mesh(parent,st.commit(),color,true)
	(node.material_override as StandardMaterial3D).cull_mode=BaseMaterial3D.CULL_DISABLED
	return node
func emblem(parent: Node3D, school: String, size: float) -> Sprite3D:
	var node:=Sprite3D.new()
	node.texture=ArtRegistryV2.texture(StringName("school_badge_"+school))
	if node.texture!=null:node.pixel_size=size/float(node.texture.get_width())
	node.position.z=0.085
	node.shaded=false
	parent.add_child(node)
	return node
func token(parent: Node3D, kind: String, school: String) -> Node3D:
	if kind=="delay_damage":
		var bomb:=preload("res://assets/vfx/status_tokens/delay_bomb.tscn").instantiate()
		parent.add_child(bomb);bomb.setup(school);return bomb
	if kind in ["shield","trap","absorb","dot","hot"]:
		var authored:=preload("res://scripts/fusion_3d/vfx/authored_status_token.gd").new()
		parent.add_child(authored);authored.setup(kind,school);return authored
	var root:=Node3D.new()
	parent.add_child(root)
	if kind in ["accuracy_blade", "accuracy_weakness"]:
		build_target(root, school, kind == "accuracy_weakness")
		return root
	if kind in ["healing_blade", "infection"]:
		build_heart(root, kind == "infection")
		return root
	var outline: Array[Vector2]=[]
	if kind in ["shield","trap"]:
		var base: Array[Vector2]=[Vector2(-0.42,0.38),Vector2(0,0.49),Vector2(0.42,0.38),Vector2(0.34,-0.17),Vector2(0,-0.5),Vector2(-0.34,-0.17)]
		for i in base.size():
			var start: Vector2=base[i]
			var end: Vector2=base[(i+1)%base.size()]
			outline.append(start)
			if kind=="trap":
				# Three teeth on each of the six shield edges: 18 teeth total.
				for tooth in 3:
					var fraction: float=(tooth+0.5)/3.0
					var middle: Vector2=start.lerp(end,fraction)
					outline.append(start.lerp(end,fraction-0.11))
					outline.append(middle+middle.normalized()*0.085)
					outline.append(start.lerp(end,fraction+0.11))
	elif kind in ["blade","weakness"]:
		build_sword(root,school,kind=="weakness")
		return root
	else:
		outline=[Vector2(0,0.48),Vector2(0.36,0),Vector2(0,-0.48),Vector2(-0.36,0)]
		if kind=="dot":
			var diamond: Array[Vector2]=outline.duplicate()
			outline.clear()
			for edge in diamond.size():
				var start: Vector2=diamond[edge]
				var end: Vector2=diamond[(edge+1)%diamond.size()]
				outline.append(start)
				for tooth in 3:
					var fraction: float=(tooth+0.5)/3.0
					var middle: Vector2=start.lerp(end,fraction)
					outline.append(start.lerp(end,fraction-0.11))
					outline.append(middle+middle.normalized()*0.075)
					outline.append(start.lerp(end,fraction+0.11))
	var color: Color=stage.COLORS.get(school,GOLD)
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in outline.size():
		var a:=Vector3(outline[i].x,outline[i].y,0)
		var b:=Vector3(outline[(i+1)%outline.size()].x,outline[(i+1)%outline.size()].y,0)
		for vertex in [Vector3(0,0,0.06),a+Vector3(0,0,0.06),b+Vector3(0,0,0.06),a,b,b+Vector3(0,0,0.06),a,b+Vector3(0,0,0.06),a+Vector3(0,0,0.06)]:st.add_vertex(vertex)
	st.generate_normals()
	var border:=mesh(root,st.commit(),Color("db8e69") if kind=="trap" else GOLD)
	(border.material_override as StandardMaterial3D).cull_mode=BaseMaterial3D.CULL_DISABLED
	var face:=mesh(root,st.commit(),color.darkened(0.65))
	face.scale=Vector3(0.82,0.82,1)
	face.position.z=0.012
	(face.material_override as StandardMaterial3D).cull_mode=BaseMaterial3D.CULL_DISABLED
	emblem(root,school,0.52)
	if kind in ["dot","hot","delay_damage"]:
		root.scale=Vector3.ONE*0.68
		var label:=Label3D.new()
		label.text="+" if kind=="hot" else ("…" if kind=="delay_damage" else "−")
		label.font_size=38
		label.pixel_size=0.008
		label.position=Vector3(0,-0.31,0.1)
		root.add_child(label)
	return root
func reserve_orbit(id: StringName, status_id: int, group: String, preferred: float=0.0) -> float:
	var layout = orbit_layout(id,group)
	layout.add(status_id,preferred,clock,0.35 if group=="floor" else 0.5)
	return layout.phase(status_id,clock)

func orbit_layout(id: StringName, group: String):
	var key:=str(id)+":"+group
	if not orbit_layouts.has(key):orbit_layouts[key]=preload("res://scripts/fusion_3d/vfx/status_orbit_layout.gd").new()
	return orbit_layouts[key]

func orbit_phase(id: StringName, status_id: int, group: String) -> float:
	return orbit_layout(id,group).phase(status_id,clock)

func register_arrival(id: StringName, status_id: int, item: Node3D) -> void:
	if not pending_status_nodes.has(id):pending_status_nodes[id]={}
	pending_status_nodes[id][status_id]=item

func sync_status(unit: BattleUnitStateV2) -> void:
	_sync_aura(unit)
	var signature:=str(unit.alive)
	for status in unit.statuses:signature+="/"+str(status.instance_id)+":"+str(status.school_filters)
	if signatures.get(unit.id,"")==signature:return
	signatures[unit.id]=signature
	var previous: Dictionary={}
	for node in status_nodes.get(unit.id,[]):
		if is_instance_valid(node):previous[int(node.get_meta("status_id"))]=node
	status_nodes[unit.id]=[]
	var groups: Dictionary={"upper":[],"ward":[],"floor":[]}
	for status in unit.statuses:
		if not unit.alive:break
		if status.kind == &"aura":continue
		var group: String="floor" if status.kind in [&"dot",&"hot",&"delay_damage"] else ("upper" if str(status.kind) in CHARM_KINDS else "ward")
		groups[group].append(status)
	for group in groups:
		var retained: Array[int]=[]
		for i in groups[group].size():
			var status: StatusInstanceV2=groups[group][i]
			var school:=ArtRegistryV2.status_school_key(status)
			if status.kind in [&"healing_blade", &"infection"]:school="all"
			var node: Node3D=previous.get(status.instance_id)
			previous.erase(status.instance_id)
			# An actual school conversion changes just this token's artwork.
			if node!=null and str(node.get_meta("school_symbol",""))!=school:
				node.queue_free()
				node=null
			if node==null:
				var pending = pending_status_nodes.get(unit.id,{}).get(status.instance_id)
				if is_instance_valid(pending) and not pending.is_queued_for_deletion():
					node=pending
					node.reparent(stage.actors[unit.id],true)
					node.set_meta("orbit_adopted",true)
				else:node=token(stage.actors[unit.id],str(status.kind),school)
			if pending_status_nodes.has(unit.id):pending_status_nodes[unit.id].erase(status.instance_id)
			node.set_meta("radial_facing",true)
			node.set_meta("status_id",status.instance_id)
			node.set_meta("school_symbol",school)
			node.set_meta("group",group)
			node.set_meta("angle",reserve_orbit(unit.id,status.instance_id,group,TAU*i/maxf(groups[group].size(),1)))
			status_nodes[unit.id].append(node)
			retained.append(status.instance_id)
		orbit_layout(unit.id,group).retain(retained,clock,0.35 if group=="floor" else 0.5)
	for node in previous.values():node.queue_free()
	_update_status_orbits()
func _sync_aura(unit: BattleUnitStateV2) -> void:
	var active: StatusInstanceV2 = null
	if unit.alive:
		for status: StatusInstanceV2 in unit.statuses:
			if status.kind == &"aura":active = status
	var current = aura_nodes.get(unit.id)
	if is_instance_valid(current):
		if active != null and current.status_id == active.instance_id:return
		current.dismiss(not unit.alive)
		aura_nodes.erase(unit.id)
	if active == null or not stage.actors.has(unit.id):return
	var key := str(active.payload.get("visual_id", ""))
	if key.is_empty():return
	var aura := PersistentAura.new()
	aura.visual_id = key
	aura.status_id = active.instance_id
	aura.scale = Vector3(1.0, stage.actor_size_ratio(unit.id), 1.0)
	stage.actors[unit.id].add_child(aura)
	aura_nodes[unit.id] = aura
func sync_pips(unit: BattleUnitStateV2) -> void:
	if stage.shell.unit_views.has(unit.id) and stage.shell.unit_views[unit.id].nameplate.presentation_resources!=null:return
	unit.resources.sort_pips()
	var signature:=str(unit.alive)+str(unit.resources.pips)+str(unit.resources.pip_schools)+str(unit.resources.shadow_pips)
	if pip_signatures.get(unit.id,"")==signature and is_instance_valid(pip_nodes.get(unit.id)):
		pip_nodes[unit.id].rotation.y=stage.actors[unit.id].get_node("Body").rotation.y
		return
	pip_signatures[unit.id]=signature
	if pip_nodes.has(unit.id):
		pip_nodes[unit.id].hide()
		pip_nodes[unit.id].queue_free()
	var root:=Node3D.new()
	root.visible=entry_effect_progress>0.0
	stage.actors[unit.id].add_child(root)
	pip_nodes[unit.id]=root
	root.rotation.y=stage.actors[unit.id].get_node("Body").rotation.y
	if not unit.alive:return
	for i in unit.resources.pips.size():
		var kind: int=unit.resources.pips[i]
		var school:=str(unit.resources.pip_schools[i])
		var color: Color=Color("ffdc24") if kind==1 else Color.WHITE
		if kind==2:color=stage.COLORS.get(school,GOLD)
		var width: float=0.25 if kind==0 else 0.29
		var node:=pip_orb(root,color,width,school if kind==2 else "")
		var bead_radius: float=width*PIP_VISUAL_SCALE*0.5
		var orbit_radius: float=STANDING_CIRCLE_RADIUS-bead_radius
		var angle: float=-0.75+i*1.5/6.0
		# Main beads are internally tangent in the board plane, resting above the rim.
		node.position=Vector3(sin(angle)*orbit_radius,0.04+bead_radius,-cos(angle)*orbit_radius)
	for i in unit.resources.shadow_pips:
		var node:=pip_orb(root,Color("08090b"),0.27,"",true)
		# Tangency uses the visible dark core/rim, not the diffuse particle envelope.
		var core_radius: float=0.86*0.5*0.34*PIP_VISUAL_SCALE
		var orbit_radius: float=STANDING_CIRCLE_RADIUS+core_radius
		var angle: float=-0.18+i*0.36
		node.position=Vector3(sin(angle)*orbit_radius,0.04+core_radius,-cos(angle)*orbit_radius)
	_fade_pip_root(root,smoothstep(0.0,1.0,entry_effect_progress))

func pip_orb(parent: Node3D, color: Color, width: float, school: String, is_shadow: bool=false) -> Node3D:
	var root:=preload("res://assets/vfx/magic_beans/magic_bean.gd").new()
	root.name="Pip_"+(school if school!="" else "Main")
	var tones: Dictionary={"fire":Color("db5422"),"ice":Color("419cdb"),"storm":Color("8541cc"),"myth":Color("daab26"),"life":Color("399b35"),"death":Color("502b85"),"balance":Color("ad782f")}
	root.tint=tones.get(school,color)
	root.school=school
	root.diameter=width
	root.shadow=is_shadow
	root.particles_enabled=pip_particles_enabled
	parent.add_child(root)
	return root

func consume(id: StringName, status_id: int, kind: String) -> void:
	for node in status_nodes.get(id,[]):
		if not is_instance_valid(node) or node.get_meta("status_id")!=status_id:continue
		if kind=="shield":
			var origin: Vector3=stage.to_local(node.global_position)
			for i in 7:
				var shape:=PrismMesh.new()
				shape.size=Vector3(0.12,0.2,0.06)
				var shard:=mesh(stage,shape,stage.COLORS.get(str(node.get_meta("school_symbol", "all")),Color("d6d8ed")))
				shard.position=origin
				var angle:=TAU*i/7.0
				var scatter:=create_tween().set_parallel(true)
				scatter.tween_property(shard,"position",origin+Vector3(sin(angle),cos(angle),0.3)*0.65,0.4*stage.cinematic_rate)
				scatter.tween_property(shard,"scale",Vector3.ONE*0.01,0.4*stage.cinematic_rate)
				scatter.chain().tween_callback(shard.queue_free)
		var effect:=create_tween().set_parallel(true)
		effect.tween_property(node,"scale",Vector3.ONE*(0.03 if kind=="trap" else 1.7),0.22*stage.cinematic_rate)
		effect.tween_property(node,"position:y",node.position.y+0.3,0.22*stage.cinematic_rate)
		effect.chain().tween_callback(node.hide)
static func resting_pointer_id(state: BattleStateV2, turns: TurnManagerV2) -> StringName:
	# Planning already holds the upcoming round number; between casts preview the next round.
	var preview:=BattleStateV2.new()
	preview.units=state.units
	preview.round_index=maxi(state.round_index,1)
	if state.phase==BattleStateV2.Phase.RESOLVING:preview.round_index+=1
	for unit in turns.resolution_order(preview):
		if unit.alive:return unit.id
	return &""

func _process(delta: float) -> void:
	clock+=delta
	if stage==null:return
	_update_entry_effects(delta)
	visible=not stage.entering
	caster_halo.visible=false # Authored standing circle and its selection light provide the active foot ring.
	var pointer_id:=caster_id
	if pointer_id==&"" and stage.engine!=null:
		pointer_id=resting_pointer_id(stage.engine.state,stage.engine.turn_manager)
	stage.arena_surface.set_caster(caster_id,pointer_id)
	# The indicator belongs to the board, so hiding CombatVisuals cannot hide it.
	if stage.entering:stage.arena_surface.indicator.hide()
	if pointer_id!=&"" and stage.actors.has(pointer_id):
		var angle: float=stage.arena_surface.indicator_angle(pointer_id)
		ring.rotation.y=lerp_angle(ring.rotation.y,angle,minf(delta*9.0,1)) if pointer_initialized else angle
		pointer_initialized=true
	if caster_id!=&"" and stage.actors.has(caster_id):
		var at: Vector3=stage.actors[caster_id].position
		caster_halo.position=at+Vector3.UP*0.12
		caster_halo.rotation.y=clock*0.65
	for id in pip_nodes:
		pip_nodes[id].rotation.y=stage.actors[id].get_node("Body").rotation.y
		for pip in pip_nodes[id].get_children():
			pip.look_at(stage.camera.global_position,Vector3.UP,true)
	_update_status_orbits()

func _update_status_orbits() -> void:
	for id in status_nodes:
		for node in status_nodes[id]:
			if not is_instance_valid(node) or not node.visible or node.get_meta("choreography_locked",false):continue
			var group: String=node.get_meta("group")
			var is_planar: bool=bool(node.get_meta("planar_status",false))
			var phase: float=orbit_phase(id,int(node.get_meta("status_id")),group)
			node.set_meta("angle",phase)
			var angle: float=phase+clock*(0.35 if group=="floor" else 0.5)
			var height: float=0.07 if is_planar else (0.38 if group=="floor" else (2.7 if group=="upper" else 0.95))
			var ratio: float=stage.actor_size_ratio(id)
			height*=ratio
			var radius: float=STATUS_ORBIT_RADIUS
			node.position=Vector3(sin(angle)*radius,height,cos(angle)*radius)
			# All token fronts use local +Z, tangent to the orbit and facing away from its center.
			node.rotation=Vector3(0,angle,0)


func build_target(root: Node3D, school: String, broken: bool) -> void:
	root.name="CrackedAccuracyTarget" if broken else "AccuracyTarget"
	var color: Color=stage.COLORS.get(school,Color("d5dbea"))
	# Two independently extruded semicircles leave a genuine gap through every ring.
	for half in (2 if broken else 1):
		var part:=Node3D.new()
		root.add_child(part)
		if broken:
			part.position.x=-0.055 if half==0 else 0.055
			part.rotation.z=0.09 if half==0 else -0.09
		for layer in 5:
			var radius:=0.46-layer*0.082
			var points:=PackedVector2Array()
			var start: float=PI*0.5 if half==0 else -PI*0.5
			var span: float=PI if broken else TAU
			var steps: int=12 if broken else 24
			for i in range(steps+1):
				var a: float=start+span*float(i)/steps
				points.append(Vector2(cos(a),sin(a))*radius)
			var tone: Color=color.lightened(0.48) if layer%2==0 else Color("293344")
			if broken:tone=tone.darkened(0.30)
			var disc:=polygon_solid(part,points,tone,0.035)
			disc.position.z=layer*0.04
			var mat:=disc.material_override as StandardMaterial3D
			mat.emission_enabled=true;mat.emission=color;mat.emission_energy_multiplier=0.12 if broken else 0.25
	# Mount the school motif directly on the central bullseye's front surface.
	if school not in ["all", "*", ""]:
		var badge:=emblem(root,school,0.23)
		badge.position=Vector3(0,0,0.201)


func build_heart(root: Node3D, broken: bool) -> void:
	root.name="BrokenHealingHeart" if broken else "HealingHeart"
	var left:=PackedVector2Array([Vector2(0,0.27),Vector2(-0.15,0.43),Vector2(-0.34,0.43),Vector2(-0.47,0.29),Vector2(-0.47,0.08),Vector2(-0.32,-0.14),Vector2(0,-0.46),Vector2(-0.035,-0.20),Vector2(0.045,-0.06),Vector2(-0.045,0.08)])
	var right:=PackedVector2Array([Vector2(0,0.27),Vector2(0.15,0.43),Vector2(0.34,0.43),Vector2(0.47,0.29),Vector2(0.47,0.08),Vector2(0.32,-0.14),Vector2(0,-0.46),Vector2(-0.035,-0.20),Vector2(0.045,-0.06),Vector2(-0.045,0.08)])
	var outlines: Array=[left,right] if broken else [PackedVector2Array([Vector2(0,0.27),Vector2(-0.15,0.43),Vector2(-0.34,0.43),Vector2(-0.47,0.29),Vector2(-0.47,0.08),Vector2(-0.32,-0.14),Vector2(0,-0.46),Vector2(0.32,-0.14),Vector2(0.47,0.08),Vector2(0.47,0.29),Vector2(0.34,0.43),Vector2(0.15,0.43)])]
	for i in outlines.size():
		var part:=Node3D.new();root.add_child(part)
		if broken:part.position.x=-0.055 if i==0 else 0.055
		var border:=polygon_solid(part,outlines[i],Color("786484") if broken else Color("ffd8d1"),0.07)
		var face:=polygon_solid(part,outlines[i],Color("17121f") if broken else Color("ef6686"),0.11)
		face.scale=Vector3(0.87,0.87,1);face.position.z=0.02
		var mat:=border.material_override as StandardMaterial3D
		mat.emission_enabled=true;mat.emission=Color("9473ae") if broken else Color("ff8da8");mat.emission_energy_multiplier=0.30


func polygon_solid(parent: Node3D, points: PackedVector2Array, color: Color, depth: float=0.055, cap_back: bool=false) -> MeshInstance3D:
	# Triangulate concave profiles rather than a center fan that fills notches.
	var indices:=Geometry2D.triangulate_polygon(points)
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		st.add_vertex(Vector3(points[index].x,points[index].y,depth))
	if cap_back:
		for i in range(0,indices.size(),3):
			for index in [indices[i+2],indices[i+1],indices[i]]:
				st.add_vertex(Vector3(points[index].x,points[index].y,0))
	for i in points.size():
		var a:=Vector3(points[i].x,points[i].y,0)
		var b:=Vector3(points[(i+1)%points.size()].x,points[(i+1)%points.size()].y,0)
		for vertex in [a,b,b+Vector3(0,0,depth),a,b+Vector3(0,0,depth),a+Vector3(0,0,depth)]:st.add_vertex(vertex)
	st.generate_normals()
	var result:=mesh(parent,st.commit(),color)
	(result.material_override as StandardMaterial3D).cull_mode=BaseMaterial3D.CULL_DISABLED
	return result
func build_sword(root: Node3D, school: String, broken: bool) -> void:
	var sword:=Node3D.new()
	sword.name="BrokenSword" if broken else "Sword"
	sword.rotation.z=0.0
	root.add_child(sword)
	var silver:=Color("cddce5") if not broken else Color("aaa2b5")
	var blade:=PackedVector2Array([Vector2(-0.14,-0.14),Vector2(0.14,-0.14),Vector2(0.14,0.49),Vector2(0.11,0.56),Vector2(0,0.72),Vector2(-0.11,0.56),Vector2(-0.14,0.49)])
	if broken:
		blade=PackedVector2Array([Vector2(-0.14,-0.14),Vector2(0.14,-0.14),Vector2(0.14,0.17),Vector2(0.055,0.10),Vector2(-0.015,0.21),Vector2(-0.075,0.13),Vector2(-0.14,0.19)])
		var tip:=polygon_solid(sword,PackedVector2Array([Vector2(-0.14,0.30),Vector2(-0.075,0.24),Vector2(-0.015,0.32),Vector2(0.055,0.22),Vector2(0.14,0.29),Vector2(0.14,0.49),Vector2(0.11,0.56),Vector2(0,0.72),Vector2(-0.11,0.56),Vector2(-0.14,0.49)]),silver,0.055,true)
		tip.name="SeparatedTip"
		tip.position.x=0.09
		tip.rotation.z=-0.14
	polygon_solid(sword,blade,silver,0.055,true).name="Blade"
	# A slim beveled fuller leaves the long parallel cutting edges readable.
	var ridge:=polygon_solid(sword,PackedVector2Array([Vector2(-0.025,-0.12),Vector2(0.025,-0.12),Vector2(0.025,0.09 if broken else 0.49),Vector2(0,0.12 if broken else 0.59),Vector2(-0.025,0.09 if broken else 0.49)]),Color("f6f2d8"),0.065)
	ridge.name="Fuller"
	var guard_points:=PackedVector2Array([Vector2(-0.34,-0.11),Vector2(-0.30,-0.24),Vector2(-0.12,-0.20),Vector2(0.12,-0.20),Vector2(0.30,-0.24),Vector2(0.34,-0.11),Vector2(0.12,-0.12),Vector2(-0.12,-0.12)])
	polygon_solid(sword,guard_points,GOLD).name="Crossguard"
	# The front keeps its gold trim; a steel rear cover hides the exposed gold mesh.
	var guard_back:=polygon_solid(sword,guard_points,Color("718795"),0.003,true)
	guard_back.name="CrossguardBack";guard_back.position.z=-0.006
	polygon_solid(sword,PackedVector2Array([Vector2(-0.065,-0.20),Vector2(0.065,-0.20),Vector2(0.055,-0.48),Vector2(-0.055,-0.48)]),Color("594052")).name="Grip"
	polygon_solid(sword,PackedVector2Array([Vector2(0,-0.60),Vector2(0.12,-0.51),Vector2(0,-0.42),Vector2(-0.12,-0.51)]),GOLD)
	# The school socket is part of the crossguard, leaving a narrow usable grip.
	var socket_points:=PackedVector2Array([Vector2(0,0.085),Vector2(0.19,-0.025),Vector2(0.19,-0.185),Vector2(0,-0.285),Vector2(-0.19,-0.185),Vector2(-0.19,-0.025)])
	polygon_solid(sword,socket_points,Color("a98a50"),0.085).name="SchoolGuardSocket"
	var socket_back:=polygon_solid(sword,socket_points,Color("647884"),0.003,true)
	socket_back.name="SchoolGuardSocketBack";socket_back.position.z=-0.010
	var colors:Dictionary={"fire":Color("ff804c"),"ice":Color("7edcff"),"storm":Color("b18aff"),"life":Color("85dd75"),"death":Color("ab9acb"),"myth":Color("e3c368"),"balance":Color("d5a475"),"all":Color("d1d6f1")}
	var color:Color=colors.get(school,colors.all)
	var inset:=polygon_solid(sword,socket_points,color.darkened(0.80),0.09)
	inset.name="SchoolGuardInset";inset.scale=Vector3(0.86,0.86,1);inset.position=Vector3(0,-0.014,0.006)
	var badge:=emblem(sword,school,0.30)
	badge.name="SchoolGuardMotif";badge.position=Vector3(0,-0.10,0.102)
	var guard:MeshInstance3D=sword.get_node("Crossguard");guard.scale.x=1.12
	guard_back.scale.x=guard.scale.x
	for part_name in ["Blade","Fuller","SeparatedTip"]:
		var part:=sword.get_node_or_null(part_name) as MeshInstance3D
		if part==null:continue
		var mat:StandardMaterial3D=part.material_override.duplicate()
		mat.albedo_color=color.lightened(0.88 if part_name=="Fuller" else 0.58)
		mat.metallic=0.6;mat.roughness=0.38;mat.emission_enabled=true
		mat.emission=color.lightened(0.75) if part_name=="Fuller" else color
		mat.emission_energy_multiplier=(0.65 if part_name=="Fuller" else 0.36)*(0.55 if broken else 1.0)
		part.material_override=mat
	# Broken swords retain the visible missing section rather than a whole-sword halo.
	if not broken:
		var aura:=MeshInstance3D.new();aura.name="BladeEdgeGlow"
		var quad:=QuadMesh.new();quad.size=Vector2(0.58,1.12);aura.mesh=quad;aura.position=Vector3(0,0.29,0.025)
		aura.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glow:=ShaderMaterial.new();glow.shader=preload("res://assets/vfx/status_tokens/blade_halo.gdshader")
		glow.set_shader_parameter("glow_color",color);aura.material_override=glow;sword.add_child(aura)

func add_pip_bubbles(token: Node3D, color: Color, is_shadow: bool) -> void:
	var effect:=preload("res://scripts/fusion_3d/pip_magic_bubbles.gd").new()
	effect.magic_color=color
	effect.shadow=is_shadow
	token.add_child(effect)

func receive_pip_magic(unit_id: StringName, count: int) -> void:
	if count<=0 or not stage.actors.has(unit_id):return
	var root:=Node3D.new()
	stage.actors[unit_id].add_child(root)
	var ratio: float=stage.actor_size_ratio(unit_id)
	var duration: float=0.85*stage.cinematic_rate
	var tween:=root.create_tween().set_parallel(true)
	for index in mini(count,7):
		var shape:=SphereMesh.new();shape.radius=0.16;shape.height=0.32
		var orb:=mesh(root,shape,Color.WHITE,true)
		var mat:=orb.material_override as StandardMaterial3D
		mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_energy_multiplier=2.0
		orb.position=Vector3((index-(count-1)*0.5)*0.34,5.5*ratio,0)
		var delay: float=index*0.12*stage.cinematic_rate
		tween.tween_property(orb,"position",Vector3(0,1.25*ratio,0),duration).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(orb,"scale",Vector3.ONE*0.02,0.2*stage.cinematic_rate).set_delay(delay+duration)
		# Smaller trailing motes follow the same fall into the body.
		for trail_index in 3:
			var mote:=mesh(root,shape,Color("dcecff"),true)
			mote.scale=Vector3.ONE*(0.45-trail_index*0.1)
			mote.position=orb.position+Vector3.UP*(trail_index+1)*0.22
			tween.tween_property(mote,"position",Vector3(0,1.25*ratio,0),duration+0.12*stage.cinematic_rate).set_delay(delay)
			tween.tween_property(mote,"scale",Vector3.ZERO,0.12*stage.cinematic_rate).set_delay(delay+duration)
	await tween.finished
	if is_instance_valid(root):root.queue_free()
	if stage.shell.unit_views.has(unit_id):stage.shell.unit_views[unit_id].nameplate.release_presentation_resources()
	stage._float_text(unit_id,"+%d 魔豆" % count,Color.WHITE,&"pip")
	stage.sync_world_state()
