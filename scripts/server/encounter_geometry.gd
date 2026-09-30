extends RefCounted
## Godot world units are metres. Terrain height is checked separately from XZ range.
const CONTACT_METRES := 2.0
const CONTACT_HEIGHT := 4.0
static func point(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])
static func roam_position(config: Dictionary,index: int,seconds: float) -> Vector3:
	var angle := float(config.order)*0.7+index*TAU/maxi(1,config.enemies.size())+seconds*0.13
	var arena_radius:=float(config.get("radius",16.6))
	if not config.get("tutorial",{}).is_empty():
		# A slow rosette visits the centre and rim instead of following one narrow ring.
		var phase := seconds*0.071+float(index)*2.1+float(config.order)
		var radius := (arena_radius-1.5)*sin(phase)
		return point(config.center)+Vector3(cos(angle)*radius,0,sin(angle)*radius)
	var center_lane:=arena_radius*0.56
	var lane_offset:=(float(index)-float(maxi(0,config.enemies.size()-1))*0.5)*1.1
	var radius:=clampf(center_lane+lane_offset,4.0,maxf(4.0,arena_radius-4.0))
	return point(config.center)+Vector3(cos(angle)*radius,0,sin(angle)*radius)
static func touches(player: Vector3,monster: Vector3) -> bool:
	var d := player-monster
	return Vector2(d.x,d.z).length()<=CONTACT_METRES+0.00001 and absf(d.y)<CONTACT_HEIGHT
static func in_arena(player: Vector3,config: Dictionary) -> bool:
	var d := player-point(config.center)
	return Vector2(d.x,d.z).length()<=float(config.radius)+0.00001 and absf(d.y)<8.0

static func can_begin_story(player: Vector3,config: Dictionary) -> bool:
	# Tutorial contact and authority admission must cover the same whole platform.
	if not config.get("tutorial",{}).is_empty():return in_arena(player,config)
	var d := player-point(config.approach)
	return Vector2(d.x,d.z).length()<=20.0 and absf(d.y)<=18.0

static func scattered_exits(config: Dictionary,peers: Array,rng: RandomNumberGenerator=null) -> Dictionary:
	var result: Dictionary={}
	if peers.is_empty():return result
	var random:=rng if rng!=null else RandomNumberGenerator.new()
	if rng==null:random.randomize()
	var ordered:=peers.duplicate()
	for index in range(ordered.size()-1,0,-1):
		var other:=random.randi_range(0,index)
		var swap: Variant=ordered[index];ordered[index]=ordered[other];ordered[other]=swap
	var base:=point(config.approach)
	var away:=Vector3(base.x-float(config.center[0]),0,base.z-float(config.center[2])).normalized()
	if away.is_zero_approx():away=Vector3.FORWARD
	if not config.get("tutorial",{}).is_empty():
		# Place retries outside the trigger so standing still cannot reopen a lost battle.
		base=point(config.center)+away*(float(config.radius)+1.0)
	var side:=Vector3(-away.z,0,away.x)
	for index in ordered.size():
		var row:=index/4
		var column:=index%4
		var row_size:=mini(4,ordered.size()-row*4)
		var lateral: float=(float(column)-float(row_size-1)*0.5)*2.2+random.randf_range(-0.1,0.1)
		if row_size==1:lateral=random.randf_range(-1.4,1.4)
		var outward: float=1.5+float(row)*2.4+random.randf_range(-0.1,0.1)
		result[int(ordered[index])]=base+away*outward+side*lateral
	return result
