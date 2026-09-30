extends RefCounted
var heights: Dictionary = {}
var terrain_size := 533.333313
var origin := Vector2(20000,20000)
func load_world(path: String) -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	terrain_size=float(data.tile_size);origin=Vector2(data.origin[0],data.origin[1])
	for tile in data.terrain:
		heights[Vector2i(tile.tile[0],tile.tile[1])]=FileAccess.get_file_as_bytes(tile.height).to_float32_array()
func height(at: Vector3) -> float:
	var x := at.x+origin.x
	var z := at.z+origin.y
	var tile := Vector2i(floori(x/terrain_size),floori(z/terrain_size))
	if not heights.has(tile):return -999.0
	var h: PackedFloat32Array=heights[tile]
	var u := clampf((x/terrain_size-tile.x)*128,0,128)
	var v := clampf((z/terrain_size-tile.y)*128,0,128)
	var ix := mini(int(u),127)
	var iz := mini(int(v),127)
	return lerpf(lerpf(h[iz*129+ix],h[iz*129+ix+1],u-ix),lerpf(h[(iz+1)*129+ix],h[(iz+1)*129+ix+1],u-ix),v-iz)
