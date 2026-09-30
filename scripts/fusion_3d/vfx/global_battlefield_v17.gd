extends Node3D
## One persistent wall bound to the authoritative singleton Global status.
const COLORS={"fire":Color("ff6029"),"ice":Color("62caff"),"storm":Color("a68aff"),"life":Color("58d578"),"death":Color("ad72d5"),"myth":Color("e9b74d"),"balance":Color("ddc98e")}
const PATTERNS={
	"fire":"res://assets/vfx/global_v19/patterns/fire.png",
	"ice":"res://assets/vfx/global_v19/patterns/ice.png",
	"storm":"res://assets/vfx/global_v19/patterns/storm.png",
	"life":"res://assets/vfx/global_v19/patterns/life.png",
	"death":"res://assets/vfx/global_v19/patterns/death.png",
	"myth":"res://assets/vfx/global_v19/patterns/myth.png",
	"balance":"res://assets/vfx/global_v19/patterns/balance.png"
}
var stage: Node3D
var current_id := -1
var wall: MeshInstance3D
func _ready() -> void:
	stage=get_parent()
func _process(_delta: float) -> void:
	if stage.engine==null or stage.engine.state==null:return
	if is_instance_valid(stage.shell) and stage.shell.presentation_director.active and not stage.get_meta("global_cast_released",false):return
	var globals: Array=stage.engine.state.global_statuses
	var next_id: int=-1 if globals.is_empty() else globals[-1].instance_id
	if stage.engine.state.phase==BattleStateV2.Phase.FINISHED:next_id=-1
	if next_id==current_id:return
	current_id=next_id
	if is_instance_valid(wall):wall.free()
	if current_id<0:return
	var status: StatusInstanceV2=globals[-1]
	var card: CardDefinitionV2=stage.shell.content.card(status.source_id)
	var school: String=str(card.school_id) if card!=null else "balance"
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/battle_board_layout.json"))
	var mesh:=CylinderMesh.new()
	mesh.top_radius=float(layout.outer_radius)+.35;mesh.bottom_radius=mesh.top_radius
	mesh.height=5.0;mesh.radial_segments=128;mesh.cap_top=false;mesh.cap_bottom=false
	wall=MeshInstance3D.new();wall.name="GlobalWall_"+school;wall.mesh=mesh;wall.position.y=mesh.height*0.5+0.02
	wall.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=ShaderMaterial.new();mat.shader=preload("res://assets/vfx/global_v17/wall.gdshader")
	mat.set_shader_parameter("school_pattern",load(PATTERNS.get(school,PATTERNS.balance)))
	mat.set_shader_parameter("school_color",COLORS.get(school,Color.WHITE))
	wall.material_override=mat;add_child(wall)
