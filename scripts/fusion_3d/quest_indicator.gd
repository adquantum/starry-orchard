extends Control
var town: Node3D
var target_label: Label
var distance_label: Label
var heading := 0.0
var metres := 0.0
var objective_provider: Node
var arrival_distance := 3.8
func setup(value: Node3D) -> void:
	town=value;name="QuestIndicator"
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left=-240;offset_right=240;offset_top=-106;offset_bottom=-16
	target_label=Label.new();target_label.position=Vector2(98,15);target_label.size=Vector2(358,28);target_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;target_label.add_theme_font_size_override("font_size",20);target_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(target_label)
	distance_label=Label.new();distance_label.position=Vector2(98,47);distance_label.size=Vector2(358,26);distance_label.add_theme_font_size_override("font_size",18);distance_label.modulate=Color("e8cc8a");distance_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(distance_label)
	refresh()
static func bearing(delta: Vector3, camera_basis: Basis) -> float:
	var right := camera_basis.x;right.y=0;right=right.normalized()
	var forward := -camera_basis.z;forward.y=0;forward=forward.normalized()
	return atan2(delta.dot(right),delta.dot(forward))
func _process(_delta: float) -> void:refresh()
func refresh() -> void:
	if town==null:return
	if is_instance_valid(objective_provider):
		var source: Node = objective_provider
		var objective: Dictionary = source.shown_objective()
		var at: Vector3 = source.objective_point()
		visible = not objective.is_empty() and at != Vector3.ZERO and not source._battle_busy() and not source.is_open()
		if not visible:return
		var delta: Vector3 = at - town.player.global_position
		metres = delta.length()
		var camera := town.get_viewport().get_camera_3d()
		if not is_instance_valid(camera):hide();return
		heading = bearing(delta, camera.global_basis)
		arrival_distance = float(objective.get("arrival_distance",13.0 if str(objective.get("kind", "")) == "arrive" else 7.0))
		target_label.text = source._objective_text(objective)
		distance_label.text = str(objective.get("arrival_text","已到达 · 按 E 互动")) if metres <= arrival_distance else "%d 米 · 当前目标" % ceili(metres)
		queue_redraw()
		return
	var chapter=town.chapter
	visible=chapter!=null and town.battle==null and not town.dialogue.visible
	if not visible:return
	var id:String=chapter.target()
	if chapter.step>=chapter.steps.size() and chapter.tracked_side.is_empty():hide();return
	if not chapter.points.has(id):hide();return
	var at:Vector3=town.to_global(chapter.points[id])
	var delta:Vector3=at-town.player.global_position
	metres=delta.length();heading=bearing(delta,town.camera.global_basis)
	var title:String=str(chapter.current_quest().get("text","前往任务目标"))
	if town.citizen_labels.has(id):title=town.citizen_labels[id].text
	elif not chapter.tracked_side.is_empty():
		for task in chapter.side_tasks:
			if task.id==chapter.tracked_side:
				for i in task.objects.size():
					if id=="side_"+str(task.id)+"_"+str(i):title=str(task.objects[i])
	else:
		var q:Dictionary=chapter.current_quest()
		var objects:Array=q.get("objects",[])
		for i in objects.size():
			if id==str(q.get("target",""))+"_"+str(i):title=str(objects[i])
	target_label.text=title
	distance_label.text="已到达 · 按 E 互动" if metres<=3.8 else "%d 米 · 当前目标" % ceili(metres)
	queue_redraw()
func _draw() -> void:
	draw_style_box(preload("res://scripts/fusion_3d/combat_scroll_skin.gd").style(),Rect2(Vector2.ZERO,size))
	var center:=Vector2(51,45)
	draw_arc(center,26,0,TAU,40,Color("b79b62"),1.5,true)
	if metres<=arrival_distance:
		draw_circle(center,8,Color("a9db94"));return
	var points:=PackedVector2Array()
	for p in [Vector2(0,-21),Vector2(15,15),Vector2(0,7),Vector2(-15,15)]:points.append(center+p.rotated(heading))
	draw_colored_polygon(points,Color("f4d18a"))
	points.append(points[0]);draw_polyline(points,Color("fff1c6"),1.5,true)
