extends Node3D
## Temporary stage actor: no unit, HP, slot or turn-order registration.
static var spell_models: Dictionary={}
static func visual_spell_id(card: CardDefinitionV2) -> String:
	# Teaching cards borrow the source card's artwork and creature together.
	var source := str(card.presentation.get("source_card_id", ""))
	return source if not source.is_empty() else str(card.id)

static func has_spell_model(id: String) -> bool:
	if spell_models.is_empty():
		spell_models=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/spell_monster_actors.json"))
	return spell_models.has(id)
static func uses_summon(card: CardDefinitionV2) -> bool:
	# Free casts and non-damaging effects never request a creature or its camera.
	if card.pip_cost<=0 and not card.x_pip:return false
	var deals_damage:=false
	for effect in card.effects:
		if str(effect.get("type","")) in ["damage","drain","apply_dot","delay_damage"]:
			deals_damage=true
			break
	if not deals_damage:
		return has_spell_model(visual_spell_id(card)) and str(card.presentation.get("template",""))=="summon_heal"
	var id:=visual_spell_id(card)
	var template:=str(card.presentation.get("template",""))
	return has_spell_model(id) or template.begins_with("summon") or id=="fire_serpent"
static func model_for(id: String, school_id: String) -> String:
	if has_spell_model(id):return str(spell_models[id])
	if id=="fire_serpent":return "firesnake"
	if "phoenix" in id:return "firethephoenix01"
	return {"fire":"firelizard","ice":"icebear","storm":"stormbee","life":"lifetree","death":"deathknight","myth":"lifeape02","balance":"icewolf"}.get(school_id,"lifetree")
var school:="fire"
var spell_id:=""
var phase:=0.0
var attack:=0.0
var parts: Array[Node3D]=[]
var body: Node3D
var attack_player: AnimationPlayer
var attack_clip := ""
const INNER_CIRCLE_DIAMETER := 9.0
const OCCUPANCY := 0.8
var display_scale := 1.0
var model_size := Vector3.ONE
func solid(parent: Node3D, shape: Mesh, at: Vector3, color: Color, size: Vector3=Vector3.ONE) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	node.mesh=shape
	node.position=at
	node.scale=size
	var mat:=StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=0.48
	mat.metallic=0.35
	node.material_override=mat
	parent.add_child(node)
	return node
func orb(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var shape:=SphereMesh.new()
	shape.radial_segments=12
	shape.rings=6
	return solid(parent,shape,at,color,size)
func _ready() -> void:
	body=Node3D.new()
	add_child(body)
	var actor:=preload("res://scripts/fusion_3d/world_one_monster.gd").new()
	actor.model_id=model_for(spell_id,school)
	body.add_child(actor)
	parts.append(actor)
	if actor.visual!=null:
		model_size=actor.visual.get_meta("normalized_size",Vector3.ONE*2.5)*actor.presentation_scale
		# Normalize the actual silhouette, including wings/weapons, not source units.
		var extent: float=maxf(model_size.x,maxf(model_size.y,model_size.z))
		display_scale=INNER_CIRCLE_DIAMETER*OCCUPANCY/maxf(extent,.01)
	_prepare_attack(actor)

func _prepare_attack(actor: Node3D) -> void:
	if actor.animation:
		for clip in actor.animation.get_animation_list():
			if "071" in clip or "073" in clip or "Attack" in clip or "Cast" in clip:
				attack_player=actor.animation
				attack_clip=clip
				var library:=AnimationLibrary.new()
				var animation: Animation=attack_player.get_animation(clip).duplicate()
				animation.loop_mode=Animation.LOOP_NONE
				library.add_animation("strike",animation)
				attack_player.add_animation_library("spell_attack",library)
				return
	# The selected angel has only idle/death clips. Give this temporary actor
	# an authored skeletal casting gesture without changing the source model.
	var skeletons=actor.visual.find_children("*","Skeleton3D",true,false)
	if skeletons.is_empty():return
	var skeleton: Skeleton3D=skeletons[0]
	attack_player=AnimationPlayer.new();add_child(attack_player)
	var gesture:=Animation.new();gesture.length=1.0
	for bone_name in ["Bone_010","Bone_011","Bone_014","Bone_015","Bone_018"]:
		var index:=skeleton.find_bone(bone_name)
		if index<0:continue
		var base:=skeleton.get_bone_pose_rotation(index)
		var strength:=0.16 if bone_name=="Bone_018" else 0.7 if bone_name in ["Bone_010","Bone_014"] else 0.35
		var track:=gesture.add_track(Animation.TYPE_ROTATION_3D)
		gesture.track_set_path(track,NodePath(str(get_path_to(skeleton))+":"+bone_name))
		gesture.rotation_track_insert_key(track,0.0,base)
		gesture.rotation_track_insert_key(track,0.25,base*Quaternion(Vector3.BACK,-strength*0.25))
		gesture.rotation_track_insert_key(track,0.55,base*Quaternion(Vector3.BACK,strength))
		gesture.rotation_track_insert_key(track,0.78,base*Quaternion(Vector3.BACK,strength*0.8))
		gesture.rotation_track_insert_key(track,1.0,base)
	var library:=AnimationLibrary.new();library.add_animation("strike",gesture)
	attack_player.add_animation_library("spell_attack",library)
	attack_clip="authored_angel_cast"

func strike(duration: float) -> void:
	attack=1
	if attack_player:
		if parts[0].animation!=attack_player and parts[0].animation:parts[0].animation.pause()
		var clip:=attack_player.get_animation("spell_attack/strike")
		attack_player.play("spell_attack/strike",0.08,clip.length/maxf(duration,0.01))
	create_tween().tween_property(self,"attack",0.0,duration)

func release_global() -> Vector3:
	# Width includes wings and weapons: it must not push a mouth/chest emitter
	# metres beyond the creature. Use actual depth and its configured facing.
	var origin:=body.to_global(Vector3(0,model_size.y*.65,0))
	return origin+front_global()*model_size.z*.35*display_scale
func _process(delta: float) -> void:
	phase+=delta
	body.rotation.x=-attack*0.3
	body.position.y=sin(phase*2)*0.08
	if spell_id=="fire_serpent":body.rotation.z=sin(phase*2.4)*0.1


func face_target(point: Vector3) -> void:
	var horizontal:=Vector3(point.x,global_position.y,point.z)
	if global_position.distance_squared_to(horizontal)>0.0001:look_at(horizontal,Vector3.UP)
func front_global() -> Vector3:
	return parts[0].front_global() if not parts.is_empty() else -global_basis.z
