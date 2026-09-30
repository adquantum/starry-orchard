extends "res://scripts/fusion_3d/imported_professor.gd"
var crown: Node3D
func _ready() -> void:
	super._ready()
	for mesh in model.find_children("*","MeshInstance3D",true,false):
		for surface in mesh.mesh.get_surface_count():
			var source: Material=mesh.get_active_material(surface)
			if source is StandardMaterial3D:
				var material: StandardMaterial3D=source.duplicate()
				material.albedo_color=Color("8d79b3")
				mesh.set_surface_override_material(surface,material)
	crown=Node3D.new();add_child(crown);crown.position.y=3.2
	for i in 3:
		var shard:=MeshInstance3D.new();var prism:=PrismMesh.new();prism.size=Vector3(0.2,0.65,0.2);shard.mesh=prism
		var mat:=StandardMaterial3D.new();mat.albedo_color=Color("bd9fe8");mat.emission_enabled=true;mat.emission=Color("70509d");shard.material_override=mat
		shard.position=Vector3(cos(float(i)*TAU/3)*0.6,0,sin(float(i)*TAU/3)*0.6);crown.add_child(shard)
func _process(delta: float) -> void:
	if crown:crown.rotation.y+=delta*0.45
