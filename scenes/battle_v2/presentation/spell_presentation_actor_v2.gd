class_name SpellPresentationActorV2
extends Control

const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")

var actor_id: StringName
var pose_texture: Texture2D
var pose_id: StringName
var alpha := 1.0
var visual_scale := 1.0
var flip_h := false


func setup(p_actor_id: StringName) -> void:
	actor_id = p_actor_id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	size = Vector2(256, 256)
	hide()


func show_pose(pose: StringName) -> void:
	pose_id = pose
	pose_texture = ArtRegistryScript.texture(StringName("%s_%s" % [str(actor_id), str(pose)]))
	alpha = 1.0
	show()
	queue_redraw()


func clear_actor() -> void:
	pose_texture = null
	hide()


func _draw() -> void:
	if pose_texture == null:
		return
	var rect := Rect2(Vector2.ZERO, size)
	draw_set_transform(Vector2(size.x, 0) if flip_h else Vector2.ZERO, 0.0, Vector2(-1, 1) if flip_h else Vector2.ONE)
	draw_texture_rect(pose_texture, rect, false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO)
