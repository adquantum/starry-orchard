extends "res://scripts/fusion_3d/academy_town.gd"
func _ready() -> void:
	persist_progress=false
	chapter_enabled=false
	super._ready()
	player.position=Vector3(60,6.5,-28)
	view_controller.close_view=true
	view_controller.yaw=-PI/2
	if "--market-test" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1).timeout
		var samples: Array[Vector3]=[Vector3(58,6,-28),Vector3(75,6,-28),Vector3(83,6,-28.3),Vector3(83,7.2,-32)]
		for at in samples:
			var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*2,at-Vector3.UP*2)
			query.exclude=[player.get_rid()]
			var hit:=get_world_3d().direct_space_state.intersect_ray(query)
			assert(not hit.is_empty(),"Missing market floor "+str(at))
			assert(absf(hit.position.y-at.y)<0.7,"Obstructed market route "+str(at)+" hit "+str(hit.position))
		print("MARKET_ROUTE_TEST_OK entry/court/stairs/terrace")
		get_tree().quit()
	if "--market-capture" in OS.get_cmdline_user_args():
		set_physics_process(false);set_process(false)
		await get_tree().create_timer(2).timeout
		camera.position=Vector3(43,35,6);camera.look_at(Vector3(75,7,-32));camera.fov=53
		await get_tree().create_timer(1).timeout
		var filename:="before" if "--before" in OS.get_cmdline_user_args() else "after"
		get_viewport().get_texture().get_image().save_png("res://docs/market_revision/"+filename+".png")
		print("MARKET_PREVIEW_OK ",filename)
		get_tree().quit()
