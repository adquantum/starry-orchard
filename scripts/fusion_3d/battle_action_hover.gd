extends Control
## Read-only preview of public actions; never intercepts card or battlefield input.
var shell: Control
var shown_token: Control
var shown_card := ""
var content: Control
var description: Control
var card_view: Control

func setup(host: Control) -> void:
	shell=host;name="ActionHoverPreview";z_index=3000
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	host.add_child(self)

func _process(_delta: float) -> void:
	var hovered: Control
	if shell.is_visible_in_tree():
		var pointer:=shell.get_global_mouse_position()
		for view in shell.unit_views.values():
			var token: Control=view.nameplate.action_badge
			if token.is_visible_in_tree() and token.get_global_rect().has_point(pointer) and token.token_state in [ActionTokenV2.State.LOCKED,ActionTokenV2.State.ACTIVE,ActionTokenV2.State.COMPLETED]:
				hovered=token;break
	var card_id:=str(hovered.action_data.get("card_id","")) if hovered!=null else ""
	if hovered!=shown_token or card_id!=shown_card:
		_clear()
		if not card_id.is_empty():_show_card(hovered,card_id)
	if is_instance_valid(content):
		for view in shell.unit_views.values():view.nameplate.status_detail_panel.hide()
		var height:=maxf(320,description.get_combined_minimum_size().y)
		description.size=Vector2(350,height)
		card_view.position=Vector2(0,(height-312)*0.5)
		content.size=Vector2(578,height)
		var factor:=minf(1.0,minf((shell.size.x-48)/578,(shell.size.y-48)/height))
		content.scale=Vector2.ONE*factor
		content.position=(shell.size-content.size*factor)*0.5

func _clear() -> void:
	shown_token=null;shown_card=""
	if is_instance_valid(content):
		content.hide();content.queue_free()
	content=null

func _show_card(token: Control,card_id: String) -> void:
	var definition: CardDefinitionV2=shell.content.card(StringName(card_id))
	if definition==null:return
	shown_token=token;shown_card=card_id
	content=Control.new();content.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(content)
	card_view=preload("res://scenes/battle_v2/ui/battle_card_view_v2.gd").new()
	card_view.bind(CardInstanceV2.new(-1,definition),true)
	content.add_child(card_view);card_view.scale=Vector2.ONE*1.5
	for row in card_view.effect_renderer.get_children():
		if "data" in row:
			row.data=row.data.duplicate(true)
			row.data.value=str(row.data.value).trim_prefix("+").trim_prefix("-").trim_prefix("−")
			row.queue_redraw()
	card_view.process_mode=Node.PROCESS_MODE_DISABLED
	description=preload("res://scenes/battle_v2/ui/spell_tome_tooltip_v2.gd").new()
	description.setup(definition,{},false)
	description.position=Vector2(228,0);content.add_child(description)
	for control in content.find_children("*","Control",true,false):
		control.mouse_filter=Control.MOUSE_FILTER_IGNORE
		control.tooltip_text=""
