extends Node3D
## Reuse the local mount rig/socket logic without running remote flight physics.
var avatar: Node3D
var swimming:=false
var controller: Node
func _ready() -> void:
	avatar=get_parent()
	controller=preload("res://scripts/worlds/wing_flight.gd").new()
	controller.world=self
	add_child(controller)
func apply(profile: Dictionary) -> void:
	var id:=str(profile.get("wings",""))
	if controller.equipped_id!=id or controller.bound_teen!=avatar.teen or (not id.is_empty() and not is_instance_valid(controller.wings)):controller.equip(id)
func motion(flying: bool,flapping: bool,underwater: bool) -> void:
	swimming=underwater
	var has_wings:bool=not controller.equipped_id.is_empty() and is_instance_valid(controller.wings)
	controller.flying=flying and has_wings;controller.flap_time=0.2 if flapping and has_wings else 0.0
	controller._set_wing_clip(str(controller.profile.get("flap_clip","004")) if flapping and has_wings else str(controller.profile.get("glide_clip","013")) if flying and has_wings else "000")
	if is_instance_valid(controller.wings):controller.wings.visible=not swimming
	if controller.wing_player!=null:controller.wing_player.speed_scale=1.8 if flapping else 0.7

static func attach(body: Node3D,profile: Dictionary) -> Node:
	var rig:=body.get_node_or_null("ReplicatedWings")
	if rig==null:
		rig=load("res://scripts/worlds/replicated_wings.gd").new();rig.name="ReplicatedWings";body.add_child(rig)
	rig.apply(profile)
	return rig
