extends Node3D

const Model:=preload("res://scripts/fusion_3d/world_one_model.gd")
const PAINTED_SHADER:=preload("res://assets/materials/world_one_lowpoly/painted_uv.gdshader")
const CATALOG_PATH:="res://resources/fusion_3d/frost_npcs.json"
const FIRST_WING:="monster_shenyingzhiyi_2920d0f2"
const FINAL_WING:="monster_tianshizhiyi_death_19b72648"

var atlas:Node
var world:Node3D
var entries:Array=[]
var actors:Dictionary={}
var nearest_id:=""
var active_id:=""
var dialog:PanelContainer
var dialog_title:Label
var dialog_role:Label
var dialog_body:Label
var shop_button:Button
var inventory_button:Button

func setup(owner_atlas:Node,owner_world:Node3D) -> void:
	atlas=owner_atlas
	world=owner_world
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary or int(parsed.get("schema_version",0))!=1:
		push_error("寒冰岛 NPC 目录无效")
		return
	entries=(parsed.get("npcs",[]) as Array).duplicate(true)
	_build_dialog()
	_spawn_all()
	var callback:=Callable(self,"_on_progression_changed")
	if Accounts.has_signal("progression_changed") and not Accounts.is_connected("progression_changed",callback):
		Accounts.progression_changed.connect(callback)

func _spawn_all() -> void:
	for value in entries:
		if not value is Dictionary:continue
		var entry:Dictionary=value
		var p:Array=entry.get("position",[])
		if p.size()!=3:continue
		var holder:=Model.place(self,str(entry.get("model_id","")),Vector3(float(p[0]),float(p[1]),float(p[2])),float(entry.get("height",2.35)),true,false)
		if not is_instance_valid(holder):
			push_error("无法放置寒冰岛 NPC："+str(entry.get("id","unknown")))
			continue
		# The shared loader also caps model width at 3.5 m. These three broad
		# merchants use their authored body height; preserve the loader's foot pivot.
		var normalized:Vector3=holder.get_meta("normalized_size",Vector3.ONE)
		var height_factor:=float(entry.get("height",2.35))/maxf(normalized.y,0.01)
		var model:=holder.get_child(0) as Node3D
		model.scale*=height_factor
		model.position*=height_factor
		holder.set_meta("normalized_size",normalized*height_factor)
		holder.name=str(entry.get("id","FrostNPC"))
		holder.rotation.y=deg_to_rad(float(entry.get("yaw_degrees",0.0)))
		_apply_texture(holder,entry)
		var label:=Label3D.new()
		label.name="InteractionLabel"
		label.text=str(entry.get("display_name","商人"))
		label.position=Vector3(0.0,float(entry.get("height",2.35))+0.28,0.0)
		label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test=true
		label.fixed_size=false
		label.pixel_size=0.004
		label.font_size=28
		label.outline_size=5
		label.modulate=Color("fff1bd")
		holder.add_child(label)
		var animation_player:AnimationPlayer=null
		var found:=holder.find_children("*","AnimationPlayer",true,false)
		if not found.is_empty():animation_player=found[0] as AnimationPlayer
		actors[str(entry.get("id",""))]={"entry":entry,"holder":holder,"label":label,"animation":animation_player}
		_play(str(entry.get("id","")),str(entry.get("idle_animation","")))

func _apply_texture(holder:Node3D,entry:Dictionary) -> void:
	var painted_path:=str(entry.get("painted_texture",""))
	if not ResourceLoader.exists(painted_path):
		push_error("寒冰岛 NPC 缺少重绘贴图："+painted_path)
		return
	var painted:Texture2D=load(painted_path)
	var wanted:=str(entry.get("material_name",""))
	var applied:=0
	for node in holder.find_children("*","MeshInstance3D",true,false):
		var mesh:=node as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var original:Material=mesh.mesh.surface_get_material(surface)
			if not original is StandardMaterial3D or original.resource_name!=wanted:continue
			var source:=original as StandardMaterial3D
			var material:=ShaderMaterial.new()
			material.shader=PAINTED_SHADER
			material.set_shader_parameter("painted_map",painted)
			if str(entry.get("id",""))=="frost_card_guide":
				# Only the held card face has mirrored lettering; keep the rest of the atlas intact.
				material.set_shader_parameter("mirror_uv_rect",Vector4(0.646812,0.7313805,0.7114543,0.8342457))
			material.set_shader_parameter("source_map",source.albedo_texture)
			material.set_shader_parameter("use_cutout",source.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)
			material.set_shader_parameter("alpha_cutoff",source.alpha_scissor_threshold)
			material.set_shader_parameter("source_alpha",source.albedo_color.a)
			mesh.set_surface_override_material(surface,material)
			applied+=1
	holder.set_meta("frost_npc_painted_texture",painted_path)
	holder.set_meta("frost_npc_painted_materials",applied)
	if applied!=1:push_error("寒冰岛 NPC 材质映射数量异常：%s/%d"%[str(entry.get("id","unknown")),applied])

func _build_dialog() -> void:
	dialog=PanelContainer.new()
	dialog.name="FrostNPCDialog"
	dialog.process_mode=Node.PROCESS_MODE_ALWAYS
	dialog.mouse_filter=Control.MOUSE_FILTER_STOP
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.offset_left=-330.0;dialog.offset_right=330.0
	dialog.offset_top=-205.0;dialog.offset_bottom=205.0
	var style:=StyleBoxFlat.new()
	style.bg_color=Color("102438f5")
	style.border_color=Color("c8a96b")
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left=24;style.content_margin_right=24
	style.content_margin_top=20;style.content_margin_bottom=20
	dialog.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);dialog.add_child(column)
	dialog_title=Label.new();dialog_title.add_theme_font_size_override("font_size",25);column.add_child(dialog_title)
	dialog_role=Label.new();dialog_role.add_theme_color_override("font_color",Color("94d9e8"));column.add_child(dialog_role)
	dialog_body=Label.new();dialog_body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;dialog_body.custom_minimum_size=Vector2(600,170);column.add_child(dialog_body)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);column.add_child(row)
	shop_button=_button(row,"打开商店",_open_shop)
	inventory_button=_button(row,"打开背包",_open_inventory)
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(spacer)
	_button(row,"离开",close)
	atlas.ui.add_child(dialog)
	dialog.hide()

func _button(parent:Node,text:String,callback:Callable) -> Button:
	var button:=Button.new()
	button.text=text
	button.custom_minimum_size=Vector2(118,40)
	button.focus_mode=Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _process(_delta:float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(world.player):return
	if is_instance_valid(atlas.encounters) and atlas.encounters.active:
		if is_open():close()
		nearest_id=""
		_update_labels()
		return
	var best_distance:=INF
	nearest_id=""
	for id in actors:
		var holder:Node3D=actors[id].holder
		var distance:float=world.player.global_position.distance_to(holder.global_position)
		if distance<best_distance:
			best_distance=distance
			nearest_id=str(id)
	if best_distance>4.0:nearest_id=""
	_update_labels()
	for id in actors:
		var animation_player:AnimationPlayer=actors[id].animation
		if is_instance_valid(animation_player) and not animation_player.is_playing():
			_play(str(id),str((actors[id].entry as Dictionary).get("idle_animation","")))

func _update_labels() -> void:
	for id in actors:
		var data:Dictionary=actors[id]
		var label:Label3D=data.label
		var entry:Dictionary=data.entry
		var distance:float=world.player.global_position.distance_to((data.holder as Node3D).global_position)
		label.visible=distance<=6.0 and not is_open()
		var close_enough:=str(id)==nearest_id and not is_open()
		label.text=("[E] "+str(entry.get("display_name","商人"))+"\n"+str(entry.get("role",""))) if close_enough else str(entry.get("display_name","商人"))
		label.modulate=Color("fff1bd") if close_enough else Color("d8e8ed")

func _input(event:InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:return
	if event.keycode==KEY_ESCAPE and is_open():
		close();get_viewport().set_input_as_handled();return
	if event.keycode==KEY_E and not nearest_id.is_empty() and not is_open():
		if (is_instance_valid(atlas.first_entry_guide) and atlas.first_entry_guide.visible) or atlas.game_menu.is_open() or atlas.wardrobe_panel.visible or atlas.library_is_open():return
		if get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit:return
		open(nearest_id);get_viewport().set_input_as_handled()

func open(id:String) -> void:
	if not actors.has(id):return
	if atlas.busy or (is_instance_valid(atlas.encounters) and atlas.encounters.active):return
	if atlas.game_menu.is_open():atlas.game_menu.close()
	if is_instance_valid(atlas.wardrobe_panel):atlas.wardrobe_panel.hide()
	if atlas.library_is_open():atlas.character_library_panel.hide()
	active_id=id
	var entry:Dictionary=actors[id].entry
	dialog_title.text=str(entry.get("display_name","商人"))
	dialog_role.text=str(entry.get("role",""))
	dialog_body.text=str(entry.get("greeting",""))+"\n\n当前目标："+_current_objective(Accounts.progression_snapshot)
	shop_button.text="打开%s"%_shop_name(str(entry.get("shop_id","")))
	inventory_button.text="查看%s"%_inventory_name(str(entry.get("inventory_tab","cards")))
	dialog.show()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	_play(id,str(entry.get("talk_animation","")))

func close() -> void:
	if not is_instance_valid(dialog) or not dialog.visible:return
	dialog.hide()
	active_id=""
	get_viewport().gui_release_focus()

func is_open() -> bool:
	return is_instance_valid(dialog) and dialog.visible

func _open_shop() -> void:
	if active_id.is_empty() or not actors.has(active_id):return
	var shop_id:=str((actors[active_id].entry as Dictionary).get("shop_id",""))
	close()
	if atlas.game_menu.has_method("open_shop"):
		atlas.game_menu.call("open_shop",shop_id)
	else:
		atlas.game_menu.message.text="商店界面正在准备，请稍后再试。"

func _open_inventory() -> void:
	if active_id.is_empty() or not actors.has(active_id):return
	var tab_id:=str((actors[active_id].entry as Dictionary).get("inventory_tab","cards"))
	close()
	if atlas.game_menu.has_method("open_inventory"):
		atlas.game_menu.call("open_inventory",tab_id)
	else:
		atlas.game_menu.toggle()

func _current_objective(snapshot:Dictionary) -> String:
	var wings:Array=snapshot.get("wing_unlocks",[])
	if FINAL_WING in wings:return "寒霜天使已经败退。继续按自己的节奏收集赋能、完善卡组与装扮。"
	if FIRST_WING in wings:return "首翼已经解锁。整备卡组和装备后，前往 frost_field_25 挑战寒霜天使。"
	var equipment:Array=snapshot.get("equipment_unlocks",[])
	var inventory:Dictionary=snapshot.get("treasure_inventory",{})
	var empower:=int(inventory.get("tc_empower",0))
	if empower<=0:return "前往港口入门营地 03，击败怪物取得可施放也可交易的赋能。"
	if equipment.is_empty():return "你已有 %d 张赋能。可先兑换本系宝藏卡，或攒到 6 张换一件 T1 属性装备。"%empower
	return "基础装备已经就绪。沿地图前往 frost_field_08，击败风翼鹰取得第一副永久翅膀。"

func _shop_name(id:String) -> String:
	return {"treasure":"宝藏卡商店","equipment":"装备商店","cosmetic":"装扮商店"}.get(id,"商店")

func _inventory_name(id:String) -> String:
	return {"cards":"卡牌","equipment":"装备","appearance":"装扮","personal":"个人形象"}.get(id,"背包")

func _play(id:String,animation_name:String) -> void:
	if animation_name.is_empty() or not actors.has(id):return
	var animation_player:AnimationPlayer=actors[id].animation
	if is_instance_valid(animation_player) and animation_player.has_animation(animation_name):animation_player.play(animation_name)

func _on_progression_changed(snapshot:Dictionary) -> void:
	if is_open() and actors.has(active_id):
		var entry:Dictionary=actors[active_id].entry
		dialog_body.text=str(entry.get("greeting",""))+"\n\n当前目标："+_current_objective(snapshot)

func _exit_tree() -> void:
	var callback:=Callable(self,"_on_progression_changed")
	if Accounts.has_signal("progression_changed") and Accounts.is_connected("progression_changed",callback):Accounts.progression_changed.disconnect(callback)
	if is_instance_valid(dialog):dialog.queue_free()
