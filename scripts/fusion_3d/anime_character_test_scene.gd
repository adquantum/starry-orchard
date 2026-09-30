extends Node3D
var actor:Node3D
var camera:Camera3D
var yaw=0.0
var elevation=1.15
var distance=3.7
var status:Label
var moving=false
var jump_button:Button
func _ready():
	DisplayServer.window_set_title("动漫角色 · 女性动作测试")
	get_tree().root.content_scale_size=Vector2i(1000,900)
	actor=load("res://scripts/fusion_3d/anime_character_retarget_test.gd").new();add_child(actor)
	var env=WorldEnvironment.new();var e=Environment.new();e.background_mode=Environment.BG_COLOR;e.background_color=Color("394658");e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color.WHITE;e.ambient_light_energy=.45;env.environment=e;add_child(env)
	var light=DirectionalLight3D.new();add_child(light);light.rotation_degrees=Vector3(-35,-25,0);light.light_energy=.7
	var floor_mesh=MeshInstance3D.new();var plane=PlaneMesh.new();plane.size=Vector2(30,30);floor_mesh.mesh=plane;add_child(floor_mesh)
	var mat=StandardMaterial3D.new();mat.albedo_color=Color("526070");floor_mesh.material_override=mat
	camera=Camera3D.new();add_child(camera);camera.current=true;camera.fov=38
	var layer=CanvasLayer.new();add_child(layer);var box=VBoxContainer.new();box.position=Vector2(18,18);layer.add_child(box)
	var title=Label.new();title.text="动漫角色 · 女性动作转接测试";title.add_theme_font_size_override("font_size",26);box.add_child(title)
	var mode=CheckButton.new();mode.text="切换为模型自带动作（对比）";mode.toggled.connect(func(v):
		if v and actor.active=="jump":actor.play_action("idle")
		actor.set_native(v);jump_button.disabled=v)
	box.add_child(mode)
	var row=HBoxContainer.new();box.add_child(row)
	for spec in [["待机","idle"],["走路","walk"],["跑步","run"],["施法","cast"],["跳跃","jump"],["受击","hit"],["倒地","fall"]]:
		var b=Button.new();b.text=spec[0];b.pressed.connect(func():actor.play_action(spec[1]));row.add_child(b)
		if spec[1]=="jump":jump_button=b
	status=Label.new();status.text="右键拖动旋转视角 · 滚轮缩放 · WASD移动 · Shift跑步\n自带动作模式：待机为静止帧，不含跳跃";box.add_child(status)
func _process(delta):
	var direction=Vector3(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),0,float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
	if direction.length()>0:
		moving=true
		var fast=Input.is_physical_key_pressed(KEY_SHIFT);actor.position+=direction.normalized()*delta*(2.3 if fast else 1.2)
		actor.rotation.y=atan2(direction.x,direction.z)
		var action="run" if fast else "walk"
		if actor.active!=action:actor.play_action(action)
	elif moving:
		moving=false;actor.play_action("idle")
	camera.position=actor.position+Vector3(sin(yaw)*distance,elevation,cos(yaw)*distance);camera.look_at(actor.position+Vector3(0,.9,0))
func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):yaw-=event.relative.x*.008;elevation=clampf(elevation+event.relative.y*.008,-.6,3.5)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:distance=maxf(1.3,distance-.2)
		if event.button_index==MOUSE_BUTTON_WHEEL_DOWN:distance=minf(8,distance+.2)



