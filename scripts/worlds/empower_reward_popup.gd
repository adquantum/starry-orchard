extends Node
## Presentation only: amounts come from a committed, character-specific receipt.
signal reward_shown(battle_id:String,amount:int)
const ICON_PATH:="res://assets/ui/currency/empower_coin_v1.png"
const DURATION:=1.9
var atlas:Node
var pending:Array[Dictionary]=[]
var seen:Dictionary={}
var current:Dictionary={}
var elapsed:=0.0
var layer:CanvasLayer
var row:HBoxContainer
var amount_label:Label

func setup(owner_atlas:Node) -> void:
	atlas=owner_atlas
	layer=CanvasLayer.new();layer.layer=35;add_child(layer)
	row=HBoxContainer.new();row.mouse_filter=Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation",5);layer.add_child(row)
	_label("赋能")
	var icon:=TextureRect.new();icon.texture=load(ICON_PATH)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size=Vector2(28,28);icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(icon)
	amount_label=_label("");row.hide()

func _label(text:String) -> Label:
	var label:=Label.new();label.text=text;label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",25)
	label.add_theme_color_override("font_color",Color("ffdf7f"))
	label.add_theme_color_override("font_outline_color",Color("233049"))
	label.add_theme_constant_override("outline_size",5);row.add_child(label)
	return label

func confirm(receipt:Dictionary,snapshot:Dictionary) -> bool:
	var cid:=str(Accounts.active_character.get("id",""))
	var aid:=str(Accounts.account.get("id",""))
	if not Accounts.character_ready or cid.is_empty() or aid.is_empty():return false
	if str(receipt.get("character_id",""))!=cid or str(snapshot.get("character_id",""))!=cid or str(snapshot.get("account_id",""))!=aid:return false
	var battle_id:=str(receipt.get("battle_id",""))
	var rewards:Variant=receipt.get("rewards",{})
	if battle_id.is_empty() or not rewards is Dictionary:return false
	var quantity:Variant=rewards.get("tc_empower",0)
	if not (quantity is int or quantity is float) or float(quantity)<=0 or float(quantity)!=floorf(float(quantity)):return false
	var key:=aid+"|"+cid+"|"+battle_id
	if seen.has(key):return false
	seen[key]=true
	pending.append({"account_id":aid,"character_id":cid,"battle_id":battle_id,"amount":int(quantity)})
	return true

func _belongs_to_player(receipt:Dictionary) -> bool:
	return Accounts.character_ready and str(receipt.account_id)==str(Accounts.account.get("id","")) and str(receipt.character_id)==str(Accounts.active_character.get("id",""))

func _process(delta:float) -> void:
	if not is_instance_valid(row) or not is_instance_valid(atlas):return
	if not current.is_empty() and not _belongs_to_player(current):current.clear()
	while not pending.is_empty() and not _belongs_to_player(pending[0]):pending.pop_front()
	row.hide()
	if not is_instance_valid(atlas.world) or not atlas.world.ready_world or atlas.busy:return
	var world:Node3D=atlas.world
	if not is_instance_valid(world.player) or not world.player.is_visible_in_tree() or not is_instance_valid(world.avatar):return
	if is_instance_valid(atlas.encounters) and atlas.encounters.active:return
	var camera:=world.get_viewport().get_camera_3d()
	if camera==null:return
	var anchor:Vector3=world.avatar.anchor_global("HeadStatus")
	if camera.is_position_behind(anchor):return
	if current.is_empty():
		if pending.is_empty():return
		current=pending.pop_front();elapsed=0.0
		amount_label.text="+%d"%int(current.amount)
		row.reset_size()
		reward_shown.emit(str(current.battle_id),int(current.amount))
	elapsed+=delta
	if elapsed>=DURATION:current.clear();return
	row.show()
	row.modulate.a=1.0-clampf((elapsed-1.05)/(DURATION-1.05),0.0,1.0)
	row.position=camera.unproject_position(anchor)-Vector2(row.size.x*0.5,row.size.y+8.0+38.0*elapsed/DURATION)
