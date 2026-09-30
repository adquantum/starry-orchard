extends RefCounted
static var styles: Dictionary = {}
static func style(card: bool = false) -> StyleBoxTexture:
	if styles.has(card): return styles[card]
	var box := StyleBoxTexture.new()
	box.texture = ArtRegistryV2.texture(&"combat_scroll_card" if card else &"combat_scroll_panel")
	box.texture_margin_left = 8 if card else 24
	box.texture_margin_right = 8 if card else 24
	box.texture_margin_top = 12 if card else 15
	box.texture_margin_bottom = 12 if card else 15
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	styles[card] = box
	return box

static var slices: Dictionary={}
static func sliced(texture: Texture2D) -> StyleBoxTexture:
	var key:=texture.get_instance_id()
	if slices.has(key):return slices[key]
	var box:=StyleBoxTexture.new();box.texture=texture
	box.texture_margin_left=minf(16,texture.get_width()*0.2)
	box.texture_margin_right=box.texture_margin_left
	box.texture_margin_top=minf(10,texture.get_height()*0.2)
	box.texture_margin_bottom=box.texture_margin_top
	slices[key]=box
	return box
