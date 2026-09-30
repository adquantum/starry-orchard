extends CanvasLayer

const DEFAULT_ARTWORK_PATH := "res://assets/ui/loading/frost_island_lowpoly_v1.png"
const WORLD_ARTWORK_PATHS := {
	"res://scenes/worlds/star_orchard.tscn": "res://assets/ui/loading/star_orchard_painterly_v1.png",
}
var _artwork: TextureRect
var progress: ProgressBar
var title: Label
var finishing:=false
var _load_generation := 0
var music: AudioStreamPlayer

static func obtain(tree: SceneTree) -> Node:
	var overlay:=tree.root.get_node_or_null("WorldLoading")
	if overlay != null and overlay.is_queued_for_deletion():
		overlay.name = "RetiringWorldLoading"
		overlay = null
	if overlay==null:
		overlay=load("res://scripts/worlds/world_loading.gd").new();overlay.name="WorldLoading";tree.root.add_child(overlay)
	return overlay
func _ready() -> void:
	layer=120
	var background:=ColorRect.new();background.color=Color("0c192b");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	_artwork=TextureRect.new()
	_artwork.name="LoadingArtwork"
	_set_world_artwork("")
	_artwork.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_artwork.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;_artwork.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_artwork.mouse_filter=Control.MOUSE_FILTER_IGNORE;background.add_child(_artwork)
	var center:=CenterContainer.new();center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.add_child(center)
	center.anchor_top=0.73;center.anchor_bottom=0.97
	var box:=VBoxContainer.new();box.custom_minimum_size.x=700;box.add_theme_constant_override("separation",12);center.add_child(box)
	var heading:=Label.new();heading.text="Starry Orchard" if Locale.locale=="en" else "星界果园";heading.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;heading.add_theme_font_size_override("font_size",32);heading.modulate=Color("223e5c");box.add_child(heading)
	title=Label.new();title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;title.add_theme_font_size_override("font_size",25);title.modulate=Color("294764");box.add_child(title)
	progress=ProgressBar.new();progress.custom_minimum_size.y=16;progress.show_percentage=false;box.add_child(progress)
	for key in ["background","fill"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("233c52") if key=="background" else Color("b9dff0");style.set_corner_radius_all(8);progress.add_theme_stylebox_override(key,style)
	var hint:=Label.new();hint.text="P edit deck   ·   B change outfit   ·   Double tap Space to fly" if Locale.locale=="en" else "P 配置卡组   ·   B 更换装束   ·   双击空格起飞";hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;hint.add_theme_font_size_override("font_size",20);hint.modulate=Color("365470");box.add_child(hint)
func begin(label: String, carried_music: AudioStreamPlayer=null, world_path: String="") -> void:
	_load_generation += 1
	_set_world_artwork(world_path)
	if is_instance_valid(carried_music) and carried_music != music:
		if is_instance_valid(music):music.stop();music.queue_free()
		music=carried_music
		music.reparent(self)
	if not is_instance_valid(music):
		music=preload("res://scripts/fusion_3d/frontend_music.gd").start(self)
	show();finishing=false;title.text=label;progress.value=0
func report(value: float,label: String="") -> void:
	progress.value=maxf(progress.value,clampf(value,0,100))
	if not label.is_empty():title.text=label
func finish() -> void:
	if finishing:return
	finishing=true;progress.value=100
	var finished_generation := _load_generation
	if is_instance_valid(music):music.stop()
	await get_tree().process_frame
	if finished_generation != _load_generation: return
	hide()
	queue_free()

# Select by stable scene path, not translated loading text. Reset on every begin
# because the account screen can hand the same overlay to the world atlas.
func _set_world_artwork(world_path: String) -> void:
	var selected_path: String = str(WORLD_ARTWORK_PATHS.get(world_path, DEFAULT_ARTWORK_PATH))
	var selected_texture: Texture2D = null
	if ResourceLoader.exists(selected_path):
		selected_texture = load(selected_path) as Texture2D
	if selected_texture == null and selected_path != DEFAULT_ARTWORK_PATH:
		if ResourceLoader.exists(DEFAULT_ARTWORK_PATH):
			selected_texture = load(DEFAULT_ARTWORK_PATH) as Texture2D
	_artwork.texture = selected_texture
