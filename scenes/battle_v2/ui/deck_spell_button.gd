extends Button
var definition: CardDefinitionV2
var extra_description: String=""

func _make_custom_tooltip(_text: String) -> Object:
	if definition==null:return null
	var tip:=preload("res://scenes/battle_v2/ui/spell_tome_tooltip_v2.gd").new()
	tip.setup(definition,{},false)
	if not extra_description.is_empty():
		tip.ready.connect(func():
			var source:=Label.new();source.text=extra_description;source.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;source.custom_minimum_size.x=306;source.add_theme_color_override("font_color",Color("ffe5b0"));tip.get_child(0).add_child(source))
	return tip
