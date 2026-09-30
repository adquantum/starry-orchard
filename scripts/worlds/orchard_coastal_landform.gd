extends RefCounted
## Analytic island envelopes + warped FBM, ridges, bays and a protected walking route.
const SEA := 220.0
var west := true
var broad := FastNoiseLite.new()
var ridge := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var route: PackedVector2Array
var local_route: PackedVector2Array
var profile_id := 0
var profile: Dictionary
var courts: Array[Dictionary]=[]

func _init(is_west: bool = true, selected_profile: int = -1) -> void:
	profile_id=selected_profile if selected_profile>=0 else (0 if is_west else 1)
	profile=preload("res://scripts/worlds/orchard_coastal_catalog.gd").profiles()[profile_id]
	west=profile_id in [0,2,4]
	broad.seed=9262101+profile_id
	broad.frequency=0.009
	broad.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	broad.fractal_octaves=4
	broad.fractal_gain=0.43
	broad.domain_warp_enabled=true
	broad.domain_warp_amplitude=28.0
	broad.domain_warp_frequency=0.005
	ridge.seed=broad.seed+100
	ridge.frequency=0.013
	ridge.fractal_type=FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves=3
	detail.seed=broad.seed+200
	detail.frequency=0.034
	detail.fractal_octaves=2
	# A connected orchard circuit serves all five clearings, leaving outer ridges intact.
	local_route=PackedVector2Array([Vector2(510,-211),Vector2(425,-225),Vector2(400,-215),Vector2(290,-170),Vector2(175,-205),Vector2(200,-315),Vector2(330,-305),Vector2(400,-215)]) if west else PackedVector2Array([Vector2(1040,480),Vector2(1010,510),Vector2(920,610),Vector2(1040,700),Vector2(1160,680),Vector2(1150,555),Vector2(1010,510)])
	for p in local_route:route.append(to_world(p))
	var sites := [Vector2(400,-215),Vector2(290,-170),Vector2(175,-205),Vector2(200,-315),Vector2(330,-305)] if west else [Vector2(1010,510),Vector2(920,610),Vector2(1040,700),Vector2(1160,680),Vector2(1150,555)]
	for i in sites.size():
		courts.append({"id":"coastal_%d_arena_%d"%[profile_id,i+1],"school":profile.school,"center":to_world(sites[i]),"height":_height_base(sites[i]),"battle_radius":18.0,"clear_radius":30.0,"blend_radius":55.0})

func to_world(at: Vector2) -> Vector2:
	var center := Vector2(270,-235) if west else Vector2(1080,594)
	return (at-center).rotated(float(profile.rotation))+Vector2(profile.center)

func to_local(at: Vector2) -> Vector2:
	var center := Vector2(270,-235) if west else Vector2(1080,594)
	return (at-Vector2(profile.center)).rotated(-float(profile.rotation))+center

func battle_weight(at: Vector2) -> float:
	var result := 0.0
	for court in courts:result=maxf(result,1.0-smoothstep(18,30,at.distance_to(court.center)))
	return result

func ellipse(at: Vector2, center: Vector2, radii: Vector2) -> float:
	return (1.0-((at-center)/radii).length())*minf(radii.x,radii.y)

func smooth_union(a: float,b: float,k: float) -> float:
	var h := clampf(0.5+0.5*(a-b)/k,0,1)
	return lerpf(b,a,h)+k*h*(1.0-h)

func coast_distance(at: Vector2) -> float:
	return _coast_distance(to_local(at))

func _coast_distance(at: Vector2) -> float:
	var warp := Vector2(broad.get_noise_2d(at.x+803,at.y),broad.get_noise_2d(at.x,at.y-907))*20.0
	var p := at+warp
	if west:
		var d := smooth_union(ellipse(p,Vector2(270,-235),Vector2(225,185)),ellipse(p,Vector2(448,-211),Vector2(90,67)),28.0)
		return minf(d,p.distance_to(Vector2(157,-45))-87.0)
	var d := smooth_union(ellipse(p,Vector2(1080,594),Vector2(264,215)),ellipse(p,Vector2(1240,666),Vector2(140,116)),34.0)
	return minf(d,p.distance_to(Vector2(1040,365))-83.0)

func path_distance(at: Vector2) -> float:
	return _path_distance(to_local(at))

func _path_distance(at: Vector2) -> float:
	var result := INF
	for i in range(local_route.size()-1):
		var a := local_route[i]
		var axis := local_route[i+1]-a
		var t := clampf((at-a).dot(axis)/axis.length_squared(),0,1)
		result=minf(result,at.distance_to(a+axis*t))
	return result

func height(at: Vector2) -> float:
	var h := _height_base(to_local(at))
	for court in courts:
		var weight := 1.0-smoothstep(float(court.clear_radius),float(court.blend_radius),at.distance_to(court.center))
		h=lerpf(h,float(court.height),weight)
	return h

func _height_base(at: Vector2) -> float:
	var d := _coast_distance(at)
	if d<0:return maxf(190.0,SEA+d*0.7)
	var shore := smoothstep(0,68,d)
	var low := broad.get_noise_2d(at.x,at.y)
	var small := detail.get_noise_2d(at.x,at.y)
	var crest := (ridge.get_noise_2d(at.x,at.y)+1.0)*0.5
	var highland: float
	if west:
		highland=32.0*exp(-pow((at.x-208.0)/145.0,2)-pow((at.y+322.0)/75.0,2))
	else:
		highland=74.0*exp(-pow((at.x-1257.0)/95.0,2)-pow((at.y-637.0)/154.0,2))
	var elevation := 15.0+low*14.0+small*2.2+highland*(0.65+crest*0.6)
	# The trail stays low and walkable but follows the same gently varying ground.
	var path_weight := 1.0-smoothstep(12,39,_path_distance(at))
	elevation=lerpf(elevation,9.0+low*3.0,path_weight)
	var result := SEA+shore*maxf(4.0,elevation)+minf(d,15.0)*0.11
	if west:
		var landing_weight := 1.0-smoothstep(8,31,at.distance_to(Vector2(510,-211)))
		result=lerpf(result,223.2,landing_weight)
		# Let the existing bridge deck meet its shore apron without terrain poking through.
		if profile_id==0 and at.x>=510:
			var under_deck := 1.0-smoothstep(8,22,absf(at.y+211.0))
			var deck := lerpf(221.4378,223.2,clampf((586.0-at.x)/76.0,0,1))-0.10
			result=lerpf(result,minf(result,deck),under_deck)
	return result
