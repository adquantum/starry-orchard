class_name CardEffectRendererV2
extends Control
const Grammar=preload("res://scripts/battle_v2/presentation/card_effect_grammar_v2.gd")
const Row=preload("res://scenes/battle_v2/ui/effect_row_v2.gd")
const Tokens=preload("res://scenes/battle_v2/ui/effect_tokens_v2.gd")
var definition: CardDefinitionV2
var rows: Array[Dictionary]=[]
func setup(value: CardDefinitionV2) -> void:
	definition=value
	mouse_filter=Control.MOUSE_FILTER_PASS
	for child in get_children():
		remove_child(child);child.queue_free()
	rows=Grammar.adapt(value) if value!=null else []
	for i in mini(rows.size(),3):
		var row:=Row.new();row.name="EffectRow"+str(i+1)
		row.position=Vector2(0,Tokens.top(rows.size())+i*(Tokens.HEIGHT+Tokens.GAP))
		add_child(row);row.setup(rows[i])
	queue_redraw()
func _draw() -> void:
	if definition!=null:
		draw_line(Vector2(3,0),Vector2(size.x-3,0),Color(Tokens.accent(str(definition.school_id)),.28),1)
