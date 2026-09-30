extends Node3D
## All coordinates are in the board's XZ plane; no atlas cuts define silhouettes.
const RADIUS := 3.65
const POINTER_INNER := 0.88
const POINTER_OUTER := 1.00
var triangles: Array[PackedVector3Array]=[]
var center: Node3D
var pointer: Node3D
var connector: MeshInstance3D
var materials: Array[Material]=[]
var meshes: Array[MeshInstance3D]=[]
func metal(color: Color) -> ShaderMaterial:
	var m:=ShaderMaterial.new()
	m.shader=preload("res://assets/shaders/battle_inlaid_gold.gdshader")
	m.set_shader_parameter("gold_color",color)
	materials.append(m)
	return m
func surface(parent: Node3D, points: PackedVector3Array, mat: Material, label: String, radial_inner: float=-1.0, radial_outer: float=1.0) -> MeshInstance3D:
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var uv_coords: Array[Vector2]=[Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,0),Vector2(1,1),Vector2(0,1)]
	for i in points.size():
		var uv: Vector2=uv_coords[i%6]
		if radial_inner>=0.0:
			uv=Vector2(0.0,(Vector2(points[i].x,points[i].z).length()-radial_inner)/(radial_outer-radial_inner))
		st.set_normal(Vector3.UP);st.set_uv(uv);st.add_vertex(points[i])
	var node:=MeshInstance3D.new();node.name=label;node.mesh=st.commit();node.material_override=mat
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node);meshes.append(node);return node
func annulus(parent: Node3D, inner: float, outer: float, mat: Material, label: String) -> void:
	var vertices:=PackedVector3Array()
	for i in 256:
		var a:=TAU*i/256.0;var b:=TAU*(i+1)/256.0
		var p:=Vector3(sin(a)*inner,0,-cos(a)*inner)
		var q:=Vector3(sin(a)*outer,0,-cos(a)*outer)
		var r:=Vector3(sin(b)*outer,0,-cos(b)*outer)
		var s:=Vector3(sin(b)*inner,0,-cos(b)*inner)
		vertices.append_array(PackedVector3Array([p,q,r,p,r,s]))
	surface(parent,vertices,mat,label,inner,outer)
func build() -> void:
	var gold:=metal(Color("d3ae69"));var copper:=metal(Color("a97b3d"))
	center=Node3D.new();center.name="ConcentricTriangles";center.position.y=.18;add_child(center)
	annulus(center,RADIUS-.045,RADIUS+.045,copper,"ClosedCircumcircle")
	for t in 2:
		var corners:=PackedVector3Array();var inner:=PackedVector3Array()
		for i in 3:
			var a:=TAU*i/3.0+PI*t
			corners.append(Vector3(sin(a)*RADIUS,0.002*t,-cos(a)*RADIUS))
			inner.append(Vector3(sin(a)*(RADIUS-.14),0.002*t,-cos(a)*(RADIUS-.14)))
		triangles.append(corners)
		var points:=PackedVector3Array()
		for i in 3:
			var j: int=(i+1)%3
			points.append_array(PackedVector3Array([corners[i],corners[j],inner[j],corners[i],inner[j],inner[i]]))
		surface(center,points,gold if t==0 else copper,"EquilateralTriangle%d"%t)
	pointer=Node3D.new();pointer.name="ClosedPointerRing";pointer.position.y=.18;add_child(pointer)
	annulus(pointer,POINTER_INNER,POINTER_OUTER,gold,"Ring256Segments")
	connector=MeshInstance3D.new();connector.name="VertexToRing";var box:=BoxMesh.new();box.size=Vector3(.08,.012,1);connector.mesh=box;connector.material_override=gold;add_child(connector);meshes.append(connector)
func set_radius(distance: float) -> void:
	pointer.position.z=-distance
	var near_edge:=distance-POINTER_OUTER
	connector.position=Vector3(0,.18,-(RADIUS+near_edge)*.5)
	connector.scale.z=maxf(.01,near_edge-RADIUS+.02)
