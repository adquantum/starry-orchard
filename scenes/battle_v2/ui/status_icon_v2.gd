class_name StatusIconV2
extends Control

const ArtRegistryScript = preload("res://scripts/battle_v2/presentation/art_registry_v2.gd")

var status: StatusInstanceV2
var accent := Color.WHITE
var glyph_texture: Texture2D
var stack_count := 1


func setup(p_status: StatusInstanceV2, p_accent: Color, p_stack_count: int = 1) -> void:
	status = p_status
	accent = p_accent
	stack_count = maxi(1, p_stack_count)
	glyph_texture = ArtRegistryScript.texture(status.kind if status != null else &"")
	if status != null and status.kind in [&"shield", &"trap", &"dot", &"hot"]:
		glyph_texture = ArtRegistryScript.texture(StringName("status_%s_%s" % [status.kind, ArtRegistryScript.status_school_key(status)]))
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	custom_minimum_size = Vector2(19, 19)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = preload("res://scenes/battle_v2/ui/hover_text_v2.gd").clean(_tooltip())
	queue_redraw()


func _draw() -> void:
	var kind := str(status.kind) if status != null else "?"
	if glyph_texture != null:
		draw_texture_rect(glyph_texture, Rect2(0.5, 0.5, 18, 18), false)
	else:
		var symbol: String = str({"blade":"B", "weakness":"W", "shield":"S", "trap":"T", "dot":"D", "hot":"H", "delay_damage":"Δ"}.get(kind, "?"))
		draw_string(ThemeDB.fallback_font, Vector2(2, 15), symbol, HORIZONTAL_ALIGNMENT_CENTER, 15, 10, Color.WHITE)
	if stack_count > 1:
		draw_string(ThemeDB.fallback_font, Vector2(8, 18), "×%d" % stack_count, HORIZONTAL_ALIGNMENT_RIGHT, 11, 8, Color("#fff2b0"))


func _tooltip() -> String:
	if status == null:
		return ""
	var title := str(status.definition_id).replace("_", " ").capitalize()
	var detail := "%+.0f%%" % status.value
	if status.kind == &"dot":
		detail = "%d damage · %d ticks" % [int(status.payload.get("amount", status.value)), status.ticks]
	elif status.kind == &"hot":
		detail = "%d healing · %d ticks" % [int(status.payload.get("amount", status.value)), status.ticks]
	elif status.kind == &"delay_damage":
		detail = "%d delayed damage · %d rounds" % [int(status.payload.get("amount", status.value)), status.ticks]
	return "%s\n%s\nStack: %d\nSource: %s\nGroup: %s" % [title, detail, stack_count, str(status.source_id), str(status.source_group)]
