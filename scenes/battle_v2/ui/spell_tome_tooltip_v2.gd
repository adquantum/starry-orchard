class_name SpellTomeTooltipV2
extends PanelContainer
const Grammar=preload("res://scripts/battle_v2/presentation/card_effect_grammar_v2.gd")
const Explanation=preload("res://scenes/battle_v2/ui/effect_tooltip_v2.gd")
var definition: CardDefinitionV2
var payment_debug: Dictionary={}
var debug_cost_view:=false
var art_texture: Texture2D
var display_title:=""
func setup(value: CardDefinitionV2,payment: Dictionary,debug: bool) -> void:
	definition=value;payment_debug=payment.duplicate(true);debug_cost_view=debug
	if not value.art_path.is_empty():art_texture=load(value.art_path) as Texture2D
func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
	custom_minimum_size=Vector2(350,0)
	var frame: StyleBoxTexture=preload("res://scenes/battle_v2/ui/compact_battle_skin.gd").panel(true)
	# Preserve the verified wrapped-description clearance.
	frame.content_margin_left=22;frame.content_margin_right=22;frame.content_margin_top=20;frame.content_margin_bottom=44
	add_theme_stylebox_override("panel",frame)
	var box:=VBoxContainer.new();box.add_theme_constant_override("separation",10);add_child(box)
	var title:=Label.new();title.text=display_title if not display_title.is_empty() else Locale.text(str(definition.name_key));title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",22);box.add_child(title)
	var school_label := "全系光环" if definition.tags.has(&"universal_aura") else str(Explanation.SCHOOLS.get(str(definition.school_id),"全系"))+"学院"
	var info:=Label.new();info.text="%s  ·  %s 魔豆  ·  命中 %d%%" % [school_label,definition.cost_label(),roundi(definition.accuracy*100)];info.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;box.add_child(info)
	var icon:=TextureRect.new();icon.name="SpellIcon";icon.texture=art_texture;icon.custom_minimum_size=Vector2(0,140);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;box.add_child(icon)
	var glossary: Array[String] = []
	var previous_target := ""
	for row in Grammar.adapt(definition):
		var parts := Explanation.description_parts(row)
		if str(row.source.type) == "apply_status":
			var target := str(Explanation.TARGETS.get(str(row.target_icon).trim_prefix("target_"), "目标"))
			if target != previous_target:
				var target_label := Label.new()
				target_label.text = "目标：" + target
				target_label.add_theme_font_size_override("font_size", 14)
				box.add_child(target_label)
			previous_target = target
		else: previous_target = ""
		var label:=Label.new();label.text=parts.effect;label.custom_minimum_size.x=306;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",16);box.add_child(label)
		for note: String in parts.notes:
			if not glossary.has(note): glossary.append(note)
	if not glossary.is_empty():
		box.add_child(HSeparator.new())
		for note in glossary:
			var explanation := RichTextLabel.new()
			explanation.fit_content = true
			explanation.scroll_active = false
			explanation.custom_minimum_size.x = 306
			explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			explanation.add_theme_font_size_override("normal_font_size", 16)
			explanation.add_theme_font_size_override("bold_font_size", 16)
			explanation.add_theme_color_override("default_color", Color("fff0d0"))
			var bold := FontVariation.new()
			bold.base_font = get_theme_default_font()
			bold.variation_embolden = 0.7
			explanation.add_theme_font_override("bold_font", bold)
			box.add_child(explanation)
			var split := note.find("：") + 1
			explanation.push_bold()
			explanation.add_text(note.left(split))
			explanation.pop()
			explanation.add_text(note.substr(split))
	if definition.shadow_cost>0:
		var extra:=Label.new();extra.text="额外需要 %d 枚暗影魔豆" % definition.shadow_cost;box.add_child(extra)
	if not definition.school_pip_requirements.is_empty():
		var extra:=Label.new();extra.text="学院魔豆要求："+definition.school_requirement_label();extra.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(extra)
	if debug_cost_view:
		var debug_label:=Label.new();debug_label.text="费用诊断："+JSON.stringify(payment_debug);debug_label.custom_minimum_size.x=306;debug_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(debug_label)
	for node in box.get_children():
		node.mouse_filter=Control.MOUSE_FILTER_IGNORE
		if node is Label:node.add_theme_color_override("font_color",Color("fff0d0"))
