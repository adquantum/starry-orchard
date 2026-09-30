extends Control
const TONES={"fire":Color("633427"),"ice":Color("285065"),"storm":Color("463662"),"life":Color("32543c"),"death":Color("44334f"),"myth":Color("625431"),"balance":Color("535043")}
const SCHOOL_NAMES={"fire":"火焰","ice":"冰霜","storm":"风暴","life":"生命","death":"死亡","myth":"神话","balance":"平衡"}
const DIAMETER:=20.0
const STEP:=22.0
var definition: CardDefinitionV2
var insufficient:=false
var entries: Array[Dictionary]=[]
func setup(card: CardDefinitionV2, affordable: bool) -> void:
	definition=card;insufficient=not affordable;entries.clear()
	var descriptions: Array[String]=[]
	# Stable school order independent of JSON dictionary ordering.
	for school in ["fire","ice","storm","life","death","myth","balance"]:
		var count:=int(card.school_pip_requirements.get(school,0))
		if count<=0:continue
		descriptions.append("%d 枚%s学院魔豆" % [count,SCHOOL_NAMES[school]])
		for i in count:entries.append({"icon":StringName("school_"+school),"tone":TONES[school]})
	if card.shadow_cost>0:
		descriptions.append("%d 枚暗影魔豆" % card.shadow_cost)
		for i in card.shadow_cost:entries.append({"icon":&"shadow_pip","tone":Color("211629")})
	size=Vector2(entries.size()*STEP,DIAMETER)
	visible=not entries.is_empty()
	mouse_filter=Control.MOUSE_FILTER_PASS
	tooltip_text="额外消耗："+"；".join(descriptions)+"。与主费用共同满足，由原费用规则结算。"
	if insufficient:tooltip_text+="当前费用条件未满足。"
	queue_redraw()
func _draw() -> void:
	for i in entries.size():
		var center:=Vector2(10+i*STEP,10)
		draw_circle(center,10,entries[i].tone)
		draw_arc(center,9.5,0,TAU,32,Color("d99e73") if insufficient else Color("b7ac8b"),1,true)
		var tex:=preload("res://scenes/battle_v2/ui/card_painted_assets_v8.gd").ui_symbol(entries[i].icon)
		if tex!=null:draw_texture_rect(tex,Rect2(center-Vector2(7,7),Vector2(14,14)),false)
