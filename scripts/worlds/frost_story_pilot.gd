extends Node3D
# Visual-only clusters; original world placements and collision pool remain untouched.
var prop_count := 0
var placement_audit: Array = []
func build(world: Node3D) -> void:
 name = "FrostStoryPilot"
 var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/fusion_3d/frost_story_pilot.json"))
 for region in config.regions:
  for cluster in region.clusters:
   var group := Node3D.new()
   group.name = cluster.id
   add_child(group)
   for entry in cluster.props:
    var path := "res://assets/worlds/frostroarisland_teen/models/"+str(entry.model)+".glb"
    var parts: Array = world.prototypes[path]
    var basis := Basis(Vector3.UP,float(entry.yaw)).scaled(Vector3(entry.scale[0],entry.scale[1],entry.scale[2]))
    var bounds := AABB()
    var first := true
    for part in parts:
     var box: AABB = Transform3D(basis,Vector3.ZERO)*part.transform*part.mesh.get_aabb()
     bounds = box if first else bounds.merge(box)
     first = false
    var at := Vector3(entry.at[0],0,entry.at[1])
    var floor_y: float = world._height(at)
    at.y = floor_y-bounds.position.y-0.045
    var transform := Transform3D(basis,at)
    for part in parts:
     var visual := MeshInstance3D.new()
     visual.mesh = part.mesh
     visual.transform = transform*part.transform
     visual.visibility_range_end = 220.0
     visual.visibility_range_end_margin = 20.0
     group.add_child(visual)
    prop_count += 1
    placement_audit.append({"cluster":cluster.id,"model":entry.model,"position":str(at),"bounds":str(AABB(bounds.position+at,bounds.size))})
 print("FROST_STORY_READY props=",prop_count," clusters=",get_child_count())
