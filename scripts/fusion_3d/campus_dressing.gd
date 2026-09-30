extends Node3D
## District-scale compositions, never random scatter inside the duel court.
const Model=preload("res://scripts/fusion_3d/world_one_model.gd")
const THEMES={
	"fire":["castlehousestove","castlehousefirewood","metalbarrel","waterbarrel"],
	"ice":["fengmozhu_ice","stormstone01","bookstand","flowerpot"],
	"storm":["fengmozhu_storm","waterattributetotem","metalbarrel","bookstand"],
	"myth":["championstatuary","castlehouseshelf02","bookstand","fuwenstone01"],
	"life":["shengmingzhiquan","flowerpot_1","castlehousepot","thicketgrass_04"],
	"death":["deathisland_sculpture","hurricanelamp","bookstand","deathflower"],
	"balance":["chuansongjitan","fuwenstone02","contracttable","bookstand"],
	"headmaster":["championstatuary","castledoor_blueflag","bookstand","flowerpot"]
}
var terrain: Node3D
var center:=Vector3.ZERO
func prop(id: String, offset: Vector3, size: float, solid: bool=false) -> Node3D:
	var at:=center+offset
	# Leave road intersections and the full offset encounter footprint accessible.
	if Vector2(offset.x,offset.z-7.0).length()<13.5:return null
	if terrain.near_bridge(at,minf(5.0,1.8+size*0.4)):return null
	var item:=Model.place(self,id,at,size,false,solid)
	if item!=null:item.set_meta("campus_composition",true)
	return item
func build(source: Node3D) -> void:
	terrain=source
	for region in terrain.layout.regions:
		center=terrain.point(region.center)
		var id: String=region.id
		if id in preload("res://scripts/fusion_3d/functional_town_layout.gd").REPLACED:continue
		if id!="astral":garden_court(Vector3(20,0,6))
		if id=="astral":
			preload("res://scripts/fusion_3d/world_one_art_kit.gd").home(self,center+Vector3(0,0,-22),12,1)
			prop("castledoor_maintower",Vector3(19,0,-17),12,true)
			prop("castlehousegemshop",Vector3(-20,0,-3),9,true)
			market(Vector3(-20,0,5))
			rest_garden(Vector3(-19,0,19))
			prop("championstatuary",Vector3(19,0,20),4.5,true)
			prop("castlehousesignboard01",Vector3(-16,0,0),2.3,true)
			continue
		var theme: Array=THEMES.get(id,THEMES.balance)
		var x: float=float(region.radius)-7.0
		prop(theme[0],Vector3(-x,0,-7),5.2,true)
		prop(theme[1],Vector3(-x-2,0,-3),2.2,true)
		rest_garden(Vector3(x,0,6))
		prop("castlehousesignboard02",Vector3(x-1,0,-5),2.1,true)
		prop("castledoor_blueflag" if id in ["ice","life"] else "castledoor_redflag",Vector3(x,0,-11),3.8)
func market(at: Vector3) -> void:
	for i in 1:
		var p:=at+Vector3(0,0,i*5.0)
		prop("castlehouseshed01" if i==0 else "castlehouseshed02",p,4.2,true)
		prop("woodenbattenbox",p+Vector3(-2,0,1),1.0,true)
func rest_garden(at: Vector3) -> void:
	prop("goldenrodlongbench",at,3.0,true)
	prop("curlyironstreetlamp01",at+Vector3(2.0,0,0),3.6,true)
	prop("flowerpot_1",at+Vector3(-2.2,0,0),1.4,true)

func walkway(a: Vector3,b: Vector3,width: float) -> void:
	var strip:=MeshInstance3D.new()
	var shape:=BoxMesh.new()
	shape.size=Vector3(width,0.045,a.distance_to(b))
	strip.mesh=shape
	strip.material_override=terrain.art.paving
	add_child(strip)
	strip.position=center+(a+b)*0.5+Vector3(0,0.035,0)
	strip.rotation.y=atan2(b.x-a.x,b.z-a.z)
	strip.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func garden_court(at: Vector3) -> void:
	# Low planted edges frame usable space without blocking the battle camera.
	for z in [-4.0,0.0,4.0]:
		var outer:=at+Vector3(signf(at.x)*1.8,0,z)
		prop("thicketgrass_03",outer,2.0)
	prop("brownwoodbench",at+Vector3(0,0,4),3.2,true)
	prop("curlyironstreetlamp01",at+Vector3(0,0,-4),4.0,true)




