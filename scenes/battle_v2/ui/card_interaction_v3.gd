extends Control
enum State {NORMAL,PLAYABLE,HOVERED,SELECTED,UNPLAYABLE,INSUFFICIENT_PIP,INVALID_TARGET}
const Tokens=preload("res://scenes/battle_v2/ui/effect_tokens_v2.gd")
var host: Control
var state: int=State.NORMAL
var signature: String=""
var invalid_target:=false
var playable:=false
func setup(card_view: Control) -> void:
	host=card_view;size=Vector2(138,208);mouse_filter=Control.MOUSE_FILTER_IGNORE
func sync() -> void:
	if host.card==null:return
	state=State.SELECTED if host.is_selected else (State.HOVERED if host.hover_amount>.02 else (State.PLAYABLE if playable else State.NORMAL))
	if host.dimmed:state=State.UNPLAYABLE
	if not host.affordable:state=State.INSUFFICIENT_PIP
	if invalid_target:state=State.INVALID_TARGET
	var next:=str([state,host.card.instance_id,host.hover_amount>.02,host.card.definition.treasure])
	if next!=signature:
		signature=next;queue_redraw();host.queue_redraw()
	for row in host.effect_renderer.get_children():
		var target=row.get_node_or_null("TargetBadge")
		if target!=null and target.has_method("set_invalid"):target.set_invalid(invalid_target)
func _draw() -> void:
	if host==null or host.card==null:return
	var accent:=Tokens.accent(str(host.card.definition.school_id))
	if state in [State.PLAYABLE,State.HOVERED,State.SELECTED]:
		var opacity: float=.12 if state==State.PLAYABLE else (.36 if state==State.HOVERED else .62)
		draw_rect(Rect2(1,1,136,206),Color(accent,opacity),false,1)
		if state==State.SELECTED:draw_rect(Rect2(-1,-1,140,210),Color("d5bd79"),false,1.5)
	if state==State.INSUFFICIENT_PIP:
		draw_arc(Vector2(17,35),13,0,TAU,32,Color("d99e73"),2,true)
		# A stable small notch keeps the state distinguishable without a red card wash.
		draw_line(Vector2(8,50),Vector2(26,50),Color("d99e73"),2)
