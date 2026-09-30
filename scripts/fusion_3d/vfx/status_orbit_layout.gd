extends RefCounted
## Continuous phases relative to the shared orbit clock. Never wrap a correction
## into a forward lap: the base rotation plus bounded drift stays positive.
var members: Dictionary = {}

func phase(id: int, now: float) -> float:
	var entry: Dictionary = members[id]
	var t: float = clampf((now-entry.start)/entry.duration,0.0,1.0)
	return lerpf(entry.from,entry.to,t*t*(3.0-2.0*t))

func add(id: int, preferred: float, now: float, speed: float) -> void:
	if members.has(id):return
	var position := preferred
	if not members.is_empty():
		var phases: Array[float] = []
		for key in members:phases.append(wrapf(phase(key,now),0.0,TAU))
		phases.sort()
		var largest := -1.0
		var nearest := INF
		for i in phases.size():
			var end: float = phases[(i+1)%phases.size()]+(TAU if i==phases.size()-1 else 0.0)
			var gap: float = end-phases[i]
			var middle: float = (phases[i]+end)*0.5
			var distance := absf(wrapf(middle-preferred,-PI,PI))
			if gap>largest+0.001 or (absf(gap-largest)<0.001 and distance<nearest):
				largest=gap;nearest=distance;position=middle
	members[id]={"from":position,"to":position,"start":now,"duration":1.0}
	redistribute(now,speed)

func retain(ids: Array[int], now: float, speed: float) -> void:
	var changed := false
	for id in members.keys():
		if id not in ids:
			members.erase(id)
			changed=true
	if changed:redistribute(now,speed)

func redistribute(now: float, speed: float) -> void:
	if members.is_empty():return
	var ordered: Array = []
	for id in members:ordered.append({"id":id,"phase":wrapf(phase(id,now),0.0,TAU)})
	ordered.sort_custom(func(a,b):return a.phase<b.phase)
	# Least-squares shared origin preserves cyclic order and minimizes displacement.
	var base := 0.0
	for i in ordered.size():base+=ordered[i].phase-TAU*i/ordered.size()
	base/=ordered.size()
	var displacement := 0.0
	for i in ordered.size():displacement=maxf(displacement,absf(base+TAU*i/ordered.size()-ordered[i].phase))
	# smoothstep's maximum derivative is 1.5. Drift <= 65% of base speed:
	# no reversal, no chase loop, and no dependency on cinematic playback speed.
	var duration := maxf(1.8,displacement*1.5/(speed*0.65))
	for i in ordered.size():
		members[ordered[i].id]={"from":ordered[i].phase,"to":base+TAU*i/ordered.size(),"start":now,"duration":duration}
