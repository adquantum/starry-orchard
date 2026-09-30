extends Node3D
## Original teen rigs: shared geosets, native clips, and source attachment sockets.
const DyeShader=preload("res://assets/materials/teen_dye/clothing.gdshader")
const HairShader=preload("res://assets/materials/teen_hair/hair.gdshader")
var hair_materials: Array[ShaderMaterial]=[]
var dye_materials: Array[ShaderMaterial]=[]
var rig: Dictionary
var outfit: Dictionary
var body: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var parts: Dictionary={}
var sockets: Dictionary={}
var attachments: Dictionary={}
var skinned_layers: Array[MeshInstance3D]=[]
var previous_position:=Vector3.ZERO
var initialized:=false
var horizontal_speed:=0.0
var supplied_speed:=-1.0
var supplied_speed_age:=1.0
var swimming:=false
var locomotion_clip:="base_000"
var airborne:=false
var vertical_speed:=0.0
var dead:=false
var locked:=0.0
var preview_clip:=""
static var textures: Dictionary={}
static var composites: Dictionary={}
func setup(value: Dictionary) -> void:
	var store=get_node("/root/Wardrobe")
	outfit=store.clean_teen(value)
	var sex: String=str(outfit.gender)
	rig=store.teen_catalog.rigs[sex]
	var chosen: Dictionary={}
	for slot in store.teen_catalog.slots:chosen[slot]=store.option(slot,str(outfit[slot]))
	preload("res://scripts/fusion_3d/apprentice_painted.gd").resolve_visuals(chosen,outfit,store)
	var body_shape: Dictionary=chosen.teen_body_shape
	var boot_shape: Dictionary=chosen.teen_boot_shape
	body=load(str(body_shape.get("body_model",boot_shape.get("body_model",rig.model)))).instantiate()
	add_child(body)
	body.scale=Vector3.ONE*0.50
	body.rotation.y=PI/2.0
	skeleton=find_kind(body,"Skeleton3D") as Skeleton3D
	player=find_kind(body,"AnimationPlayer") as AnimationPlayer
	for node in body.find_children("*","MeshInstance3D",true,false):
		if str(node.name).begins_with("Geo_"):parts[int(str(node.name).trim_prefix("Geo_"))]=node
	for id in rig.sockets:
		var socket:=BoneAttachment3D.new()
		socket.name="Socket_"+str(id)
		socket.bone_name=str(rig.sockets[id].bone)
		skeleton.add_child(socket)
		var origin:=Node3D.new()
		var p: Array=rig.sockets[id].offset
		origin.position=Vector3(p[0],p[1],p[2])
		socket.add_child(origin)
		sockets[id]=origin
	var shown: Array[int]=[302,int(chosen.teen_body_shape.shape),int(chosen.teen_boot_shape.shape)]
	if not chosen.teen_hair.has("model") and not chosen.teen_hat.has("model"):shown.append(int(chosen.teen_hair.get("shape",1)))
	if chosen.teen_back.has("texture"):shown.append(int(chosen.teen_back_shape.shape))
	var body_texture:=composite(chosen.teen_skin,chosen.teen_clothes,chosen.teen_boots)
	var dye: Dictionary=store.dye_spec(outfit)
	var hair: Dictionary=store.hair_spec(outfit)
	for id in parts:
		var part: MeshInstance3D=parts[id]
		part.visible=shown.has(id)
		if not part.visible:continue
		var texture: Texture2D=body_texture
		if id==302:texture=read_texture(str(chosen.teen_skin.get("face",rig.face)))
		elif id<10:texture=read_texture(str(chosen.teen_hair.get("texture","")))
		elif id>1000:texture=read_texture(str(chosen.teen_back.get("texture","")))
		for index in part.mesh.get_surface_count():
			if chosen.teen_clothes.has("swimwear_material") and id==int(chosen.teen_clothes.shape):
				var spec: Dictionary=chosen.teen_clothes.swimwear_material
				var swim: ShaderMaterial=load(str(spec.resource)).duplicate()
				swim.set_shader_parameter("base_map",body_texture)
				swim.set_shader_parameter("cloth_map",read_texture(str(chosen.teen_clothes.texture)))
				var masks: Dictionary=spec.masks_by_skin
				swim.set_shader_parameter("cloth_mask",read_texture(str(masks.get(str(chosen.teen_skin.texture),spec.mask))))
				swim.set_shader_parameter("cloth_roughness",float(spec.roughness))
				part.set_surface_override_material(index,swim)
				continue
			if not hair.is_empty() and id==int(hair.shape):
				var hair_material:=ShaderMaterial.new()
				hair_material.shader=HairShader
				hair_material.set_shader_parameter("painted_map",read_texture(str(hair.painted)))
				hair_material.set_shader_parameter("original_map",read_texture(str(hair.original)))
				hair_material.set_shader_parameter("dye_mask",read_texture(str(hair.mask)))
				hair_materials.append(hair_material)
				part.set_surface_override_material(index,hair_material)
				continue
			if not dye.is_empty() and id==int(dye.shape):
				var dyed:=ShaderMaterial.new()
				dyed.shader=DyeShader
				dyed.set_shader_parameter("original_map",body_texture)
				dyed.set_shader_parameter("painted_map",read_texture(str(dye.painted)))
				dyed.set_shader_parameter("dye_mask",read_texture(str(dye.mask)))
				dyed.set_shader_parameter("skin_mask",read_texture(str(dye.skin_mask)))
				dyed.set_shader_parameter("skin_map",read_texture(str(chosen.teen_skin.texture)))
				dye_materials.append(dyed)
				part.set_surface_override_material(index,dyed)
				continue
			var material:=StandardMaterial3D.new()
			material.albedo_texture=texture
			material.roughness=0.85
			material.cull_mode=BaseMaterial3D.CULL_DISABLED
			# Body/boot atlases also contain cutout regions; preserve their alpha.
			material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			part.set_surface_override_material(index,material)
	apply_skinned_layers(chosen)
	apply_clothing_occlusion(chosen)
	update_dyes(outfit)
	for slot in ["teen_hair","teen_hat","teen_weapon","teen_back"]:
		var item: Dictionary=chosen[slot]
		if not item.has("model"):continue
		if slot=="teen_hair" and chosen.teen_hat.has("model"):continue
		var obj: Node3D=load(str(item.model)).instantiate()
		var parent: Node3D=sockets["11" if slot in ["teen_hat","teen_hair"] else "1" if slot=="teen_weapon" else "15"]
		parent.add_child(obj)
		apply_equipment_textures(obj,item.get("texture_overrides",{}))
		if slot=="teen_hair" and not hair.is_empty():
			apply_attachment_hair(obj,hair)
		if item.has("offset"):
			var offset: Array=item.offset
			obj.position=Vector3(offset[0],offset[1],offset[2])
		attachments[slot]=obj
		# Equipment is authored in local attachment coordinates with its own small rig.
		var anim:=find_kind(obj,"AnimationPlayer") as AnimationPlayer
		if anim!=null:
			var names:=anim.get_animation_list()
			for name_value in names:
				if name_value!="RESET":
					anim.get_animation(name_value).loop_mode=Animation.LOOP_LINEAR
					anim.play(name_value)
					break
	# Attachments register their dye materials after the base body is built.
	update_dyes(outfit)
	preload("res://scripts/fusion_3d/apprentice_painted.gd").apply(self,outfit)
	if player!=null:
		for clip in rig.clips:
			var key:=animation_key(str(clip.id))
			if not key.is_empty():player.get_animation(key).loop_mode=Animation.LOOP_LINEAR if clip.loop else Animation.LOOP_NONE
		play("base_000")
		player.advance(0)
	if str(chosen.teen_clothes.get("hidden_character",""))=="anime_catgirl":
		for part in parts.values():part.visible=false
		for attachment in attachments.values():attachment.visible=false
		var hidden=load("res://scripts/fusion_3d/anime_character_retarget_test.gd").new()
		hidden.external_source=skeleton
		hidden.external_player=player
		hidden.rotation.y=PI
		hidden.name="HiddenAnimeCharacter"
		add_child(hidden)
func apply_attachment_hair(obj: Node,spec: Dictionary) -> void:
	for mesh in obj.find_children("*","MeshInstance3D",true,false):
		for index in mesh.mesh.get_surface_count():
			var original: Material=mesh.get_active_material(index)
			if original==null or not spec.get("materials",[]).has(original.resource_name):continue
			var material:=ShaderMaterial.new()
			material.shader=HairShader
			material.set_shader_parameter("painted_map",read_texture(str(spec.painted)))
			material.set_shader_parameter("original_map",read_texture(str(spec.original)))
			material.set_shader_parameter("dye_mask",read_texture(str(spec.mask)))
			hair_materials.append(material)
			mesh.set_surface_override_material(index,material)
func apply_skinned_layers(chosen: Dictionary) -> void:
	# Authored garments share the production skeleton; their donor rig is never animated.
	for slot in ["teen_clothes","teen_boots","teen_hat"]:
		var item: Dictionary=chosen[slot]
		if not item.has("skinned_layer"):continue
		var spec: Dictionary=item.skinned_layer
		var donor: Node3D=load(str(spec.model)).instantiate()
		body.add_child(donor)
		for source_mesh in donor.find_children("*","MeshInstance3D",true,false):
			if not str(source_mesh.name) in spec.meshes:continue
			var mesh: MeshInstance3D=source_mesh.duplicate()
			var relative: Transform3D=body.global_transform.affine_inverse()*source_mesh.global_transform
			body.add_child(mesh)
			mesh.transform=relative
			mesh.skeleton=mesh.get_path_to(skeleton)
			# Resolve binds by name, since imported skeleton bone order can differ.
			mesh.skin=source_mesh.skin.duplicate()
			# Dense source atlases have skin islands next to cloth; avoid mip colour bleed.
			for surface in mesh.mesh.get_surface_count():
				var authored: Material=source_mesh.get_active_material(surface)
				if authored is BaseMaterial3D:
					var local_material: BaseMaterial3D=authored.duplicate()
					local_material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR
					mesh.set_surface_override_material(surface,local_material)
			var donor_skeleton: Skeleton3D=source_mesh.get_node(source_mesh.skeleton)
			for bind in mesh.skin.get_bind_count():
				if mesh.skin.get_bind_name(bind)==&"":
					mesh.skin.set_bind_name(bind,donor_skeleton.get_bone_name(mesh.skin.get_bind_bone(bind)))
			skinned_layers.append(mesh)
			if spec.has("pose_corrective"):
				mesh.set_script(load(str(spec.pose_corrective)))
				mesh.configure(skeleton,parts)
		donor.free()
		for hidden in spec.get("hide_shapes",[]):
			if parts.has(int(hidden)):parts[int(hidden)].visible=false
func apply_clothing_occlusion(chosen: Dictionary) -> void:
	var dress: bool=str(chosen.teen_clothes.id)=="clean_v3_dress"
	var stockings: bool=str(chosen.teen_boots.id)=="clean_v3_shoes"
	var sakura: bool=str(chosen.teen_clothes.id)=="pink_sakura_kimono"
	var starweave: bool=str(chosen.teen_clothes.id)=="starweave_v1_robe"
	var starweave_boots: bool=str(chosen.teen_boots.id)=="starweave_v1_boots"
	if not (dress or stockings or starweave or starweave_boots or sakura) or not parts.has(898) or not parts[898].visible:return
	# Outfit-local visibility mesh: retain all original vertices, UVs and bone weights.
	# Covered body triangles are omitted only while this clothing is worn.
	var part: MeshInstance3D=parts[898]
	var original: Mesh=part.mesh
	var arrays: Array=original.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var visible:=PackedInt32Array()
	for offset in range(0,indices.size(),3):
		var covered:=true
		for corner in 3:
			var p: Vector3=vertices[indices[offset+corner]]
			var torso: bool=dress and p.y>2.15 and p.y<(2.68 if p.x>0.14 else 2.66) and absf(p.z)<(0.65 if p.y<2.28 else 0.43)
			var leg: bool=stockings and p.y<0.79 and p.y>0.24
			if sakura:
				torso=torso or (p.y>1.45 and p.y<2.78 and absf(p.z)<0.44)
			if starweave:
				# Omit only covered body regions; the head and hands remain the production meshes.
				torso=torso or (p.y>1.55 and p.y<2.70 and absf(p.z)<0.45)
				var arm_axis:=Vector2(0.35,2.795).lerp(Vector2(1.16,2.365),clampf((absf(p.z)-0.35)/0.81,0.0,1.0))
				torso=torso or (absf(p.z)>0.35 and absf(p.z)<1.10 and absf(p.y-arm_axis.y)<0.18)
			if starweave_boots:leg=leg or (p.y>0.24 and p.y<0.88)
			if not (torso or leg):covered=false;break
		if not covered:
			for corner in 3:visible.append(indices[offset+corner])
	arrays[Mesh.ARRAY_INDEX]=visible
	var local_mesh:=ArrayMesh.new();local_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	part.mesh=local_mesh
func apply_equipment_textures(obj: Node,overrides: Dictionary) -> void:
	# Variant-local albedo overrides retain the original mesh, skin, hair and effect materials.
	if overrides.is_empty():return
	for mesh in obj.find_children("*","MeshInstance3D",true,false):
		for index in mesh.mesh.get_surface_count():
			var original: Material=mesh.get_active_material(index)
			if not original is BaseMaterial3D or not overrides.has(original.resource_name):continue
			var material: BaseMaterial3D=original.duplicate()
			material.albedo_texture=read_texture(str(overrides[original.resource_name]))
			mesh.set_surface_override_material(index,material)
func find_kind(root: Node,kind: String) -> Node:
	if root.is_class(kind):return root
	for child in root.get_children():
		var found:=find_kind(child,kind)
		if found!=null:return found
	return null
static func read_texture(path: String) -> Texture2D:
	if path.is_empty():return null
	if not textures.has(path):textures[path]=load(path)
	return textures[path]
static func composite(skin: Dictionary,clothes: Dictionary,boots: Dictionary) -> Texture2D:
	var key: String=str(skin.id)+str(clothes.id)+str(boots.id)+"|"+str(clothes.get("cutout_mask",""))+"|"+str(boots.get("cutout_mask",""))
	if composites.has(key):return composites[key]
	var image: Image=read_texture(str(skin.texture)).get_image()
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(512,512)
	for item in [clothes,boots]:
		if item.get("base_layer",false):continue
		var overlay: Image=read_texture(str(item.texture)).get_image()
		if overlay.is_compressed():overlay.decompress()
		overlay.convert(Image.FORMAT_RGBA8)
		var shoe: bool=item==boots
		overlay.resize(256 if shoe else 512,128 if shoe else 512)
		image.blend_rect(overlay,Rect2i(Vector2i.ZERO,overlay.get_size()),Vector2i(0,384) if shoe else Vector2i.ZERO)
	# Cut clothing and boots independently so mixed outfits never borrow the other item's mask.
	for item in [clothes,boots]:
		if not item.has("cutout_mask"):continue
		var cutout: Image=read_texture(str(item.cutout_mask)).get_image()
		if cutout.is_compressed():cutout.decompress()
		var offset:=Vector2i(0,384) if item==boots else Vector2i.ZERO
		for y in cutout.get_height():
			for x in cutout.get_width():
				if cutout.get_pixel(x,y).r<0.5:
					var at:=Vector2i(x,y)+offset
					var pixel:=image.get_pixelv(at);pixel.a=0.0;image.set_pixelv(at,pixel)
	var result:=ImageTexture.create_from_image(image)
	if composites.size()>=64:composites.erase(composites.keys()[0])
	composites[key]=result
	return result
func animation_key(id: String) -> String:
	if player==null:return ""
	for key in player.get_animation_list():
		if str(key)==id or str(key).ends_with("/"+id):return str(key)
	return ""
func play(id: String,speed: float=1.0) -> void:
	var key:=animation_key(id)
	if key.is_empty():return
	if str(player.current_animation)!=key:player.play(key,0.12,speed)
func preview_animation(id: String) -> void:
	preview_clip=id
	locked=0
	dead=false
	if id.is_empty():play("base_000")
	else:
		var key:=animation_key(id)
		if not key.is_empty():player.stop();player.play(key)
func set_locomotion(in_air: bool,speed_y: float,planar_speed: float=-1.0) -> void:
	supplied_speed=planar_speed
	supplied_speed_age=0.0
	if airborne and not in_air and not dead and not swimming:
		locked=0.22
		play("base_039")
	airborne=in_air
	vertical_speed=speed_y
func _physics_process(delta: float) -> void:
	var distance:=Vector2(global_position.x-previous_position.x,global_position.z-previous_position.z).length() if initialized else 0.0
	previous_position=global_position
	initialized=true
	# Sample movement on the same clock as CharacterBody3D. Rendering may run
	# several times between physics ticks and must never turn those gaps into idle.
	var measured_speed:=distance/maxf(delta,0.001)
	if supplied_speed>=0.0 and supplied_speed_age<0.1:measured_speed=supplied_speed
	supplied_speed_age+=delta
	# Ignore relocations and smooth interpolated remote/tweened movement.
	if distance>1.0:measured_speed=0.0;horizontal_speed=0.0
	horizontal_speed=lerpf(horizontal_speed,measured_speed,1.0-exp(-20.0*delta))
	if dead or not preview_clip.is_empty():return
	locked=maxf(0,locked-delta)
	if locked>0:return
	if swimming:
		play("base_042" if horizontal_speed>0.2 else "base_041")
		return
	if airborne:play("base_037" if vertical_speed>1 else "base_038")
	else:
		# Separate enter/leave thresholds keep the stride continuous near a boundary.
		if horizontal_speed<(0.12 if locomotion_clip!="base_000" else 0.25):locomotion_clip="base_000"
		elif horizontal_speed>(2.6 if locomotion_clip=="base_004" else 3.4):locomotion_clip="base_004"
		else:locomotion_clip="base_013"
		play(locomotion_clip)
func action_key(action: String) -> String:
	return animation_key(str(rig.get("actions",{}).get(action,"")))
func has_equipped_wings() -> bool:
	var back: Dictionary=get_node("/root/Wardrobe").option("teen_back",str(outfit.get("teen_back","none")))
	if back.get("id","none")=="none":return false
	# Back-slot items include capes, toys and backpacks; only reviewed wings use wing casting.
	if str(back.get("cast_style","ground"))!="wing":return false
	if attachments.has("teen_back"):return true
	var shape: Dictionary=get_node("/root/Wardrobe").option("teen_back_shape",str(outfit.get("teen_back_shape","")))
	var part: int=int(shape.get("shape",0))
	return back.has("texture") and parts.has(part) and parts[part].visible
func grounded_wing_cast() -> String:
	# Imported wing clips use a different root origin. Rebase onto this rig's idle
	# pose without changing the shared imported animation or its relative motion.
	const LIBRARY := "grounded_cast"
	const CLIP := "wing"
	if player.has_animation_library(LIBRARY):return LIBRARY+"/"+CLIP
	var source_key:=action_key("wing_cast")
	var idle_key:=action_key("idle")
	if source_key.is_empty() or idle_key.is_empty():return action_key("cast")
	var source: Animation=player.get_animation(source_key)
	var idle: Animation=player.get_animation(idle_key)
	var corrected: Animation=source.duplicate(true)
	for track in corrected.get_track_count():
		if corrected.track_get_type(track)!=Animation.TYPE_POSITION_3D:continue
		var path: NodePath=corrected.track_get_path(track)
		if not str(path).ends_with(":Bone_000"):continue
		var reference:=idle.find_track(path,Animation.TYPE_POSITION_3D)
		if reference<0 or idle.track_get_key_count(reference)==0 or corrected.track_get_key_count(track)==0:continue
		var offset: Vector3=idle.track_get_key_value(reference,0)-corrected.track_get_key_value(track,0)
		for key in corrected.track_get_key_count(track):
			corrected.track_set_key_value(track,key,corrected.track_get_key_value(track,key)+offset)
	corrected.loop_mode=Animation.LOOP_NONE
	var library:=AnimationLibrary.new()
	library.add_animation(CLIP,corrected)
	player.add_animation_library(LIBRARY,library)
	return LIBRARY+"/"+CLIP

func play_cast(duration: float) -> void:
	if dead:return
	preview_clip=""
	var key:=grounded_wing_cast() if has_equipped_wings() else action_key("cast")
	if key.is_empty():key=action_key("cast")
	if key.is_empty():return
	locked=maxf(duration,0.1)
	player.stop()
	player.play(key,0.1,player.get_animation(key).length/locked)
func hit() -> void:
	if dead:return
	var key:=action_key("hit")
	if key.is_empty():return
	preview_clip=""
	locked=maxf(player.get_animation(key).length,0.1)
	player.stop()
	player.play(key,0.1)
func set_alive(alive: bool) -> void:
	dead=not alive
	preview_clip=""
	locked=0
	var key:=action_key("idle" if alive else "death")
	if key.is_empty():return
	player.stop()
	player.play(key,0.12)
func anchor_global(id: String) -> Vector3:
	var hidden=get_node_or_null("HiddenAnimeCharacter")
	if hidden!=null and id in ["HandGrip","StaffSocket","CastRelease","OffHandGrip","HeadStatus","HitPoint"]:
		var bone_name="L_Hand" if id=="OffHandGrip" else "Head" if id=="HeadStatus" else "Spine01" if id=="HitPoint" else "R_Hand"
		var bone=hidden.target.find_bone(bone_name)
		return hidden.target.to_global(hidden.target.get_bone_global_pose(bone).origin)
	if id=="CastRelease" and attachments.has("teen_weapon"):
		var item: Dictionary=get_node("/root/Wardrobe").option("teen_weapon",str(outfit.teen_weapon))
		var lo: Array=item.bounds[0]
		var hi: Array=item.bounds[1]
		var low:=Vector3(lo[0],lo[2],-hi[1])
		var high:=Vector3(hi[0],hi[2],-lo[1])
		var axis: int=(high-low).max_axis_index()
		var tip: Vector3=(low+high)*0.5
		tip[axis]=high[axis] if absf(high[axis])>=absf(low[axis]) else low[axis]
		return attachments.teen_weapon.to_global(tip)
	if id in ["HandGrip","StaffSocket","CastRelease","OffHandGrip"]:
		return sockets["2" if id=="OffHandGrip" else "1"].global_position
	return to_global(Vector3(0,2.15,0) if id=="HeadStatus" else Vector3(0,1.05,0) if id=="HitPoint" else Vector3(0,0.025,0))
func set_head_preview(value: bool) -> void:
	if has_node("HiddenAnimeCharacter"):
		for item in attachments.values():item.visible=false
		return
	for slot in attachments:attachments[slot].visible=not value if slot in ["teen_hat","teen_weapon","teen_back"] else true

func update_dyes(value: Dictionary) -> void:
	for material in hair_materials:material.set_shader_parameter("hair_color",Color(get_node("/root/Wardrobe").hair_color(value)))
	outfit=value.duplicate(true)
	var colors: Array=get_node("/root/Wardrobe").dye_colors(outfit)
	if colors.size()!=4:return
	var uniforms: Array[String]=["primary_color","secondary_color","trim_color","hardware_color"]
	for material in dye_materials:
		for zone in 4:material.set_shader_parameter(uniforms[zone],Color(str(colors[zone])))


func set_swimming(value: bool) -> void:
	if swimming!=value:locked=0
	swimming=value
