extends HBoxContainer
## Displays the existing character-owned Empower inventory; never changes it.
const ICON_PATH := "res://assets/ui/currency/empower_coin_v1.png"
var compact := false
var amount: Label

func _ready() -> void:
	add_theme_constant_override("separation",6)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var icon:=TextureRect.new();icon.texture=load(ICON_PATH)
	icon.custom_minimum_size=Vector2(28,28);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(icon)
	amount=Label.new();amount.add_theme_font_size_override("font_size",17);amount.add_theme_color_override("font_color",Color("493827"));amount.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(amount)
	Accounts.progression_changed.connect(refresh)
	refresh(Accounts.progression_snapshot)

func refresh(snapshot: Dictionary) -> void:
	var total:=int(snapshot.get("treasure_inventory",{}).get("tc_empower",0))
	var reserved:=int(snapshot.get("treasure_reserved",{}).get("tc_empower",0))
	var available:=maxi(0,total-reserved)
	amount.text="赋能 %d"%total
	if not compact and reserved>0:amount.text+=" · 可用 %d / 保留 %d"%[available,reserved]
	tooltip_text="本角色赋能：%d；可支付：%d；本场保留：%d"%[total,available,reserved]
