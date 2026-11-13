extends SceneTree
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const WorldView = preload("res://scripts/world_view.gd")

func _e(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return d if v == "" else v

func _initialize() -> void:
	root.msaa_3d = Viewport.MSAA_4X
	var out := _e("OUT", "/tmp")
	var ti := int(_e("TRACK", "1"))
	var bi := int(_e("BRIDGE", "0"))
	var off := float(_e("OFF", "0"))
	var view := WorldView.new()
	root.add_child(view)
	await process_frame
	for theme in _e("THEMES", "snow,forest,sand,rock").split(","):
		view.theme_override = theme
		view.underpass = PackedStringArray(_e("STYLE", "").split(",", false))
		var tr := TrackData.new(Defs.TRACKS[ti], "standard")
		view.build(tr)
		if bi >= tr.bridges.size():
			print("no bridge ", bi, " of ", tr.bridges.size()); quit(); return
		var B: Dictionary = tr.bridges[bi]
		var s := tr.s_of(int(B["under"]), 0.0) + off
		var p := tr.point_at(s)
		print(theme, " bridges=", tr.bridges.size(), " under h=", tr.height_at(s), " deck h=", tr.height_at(tr.s_of(int(B["from"]) , 0.0)))
		var car := view._make_car(Color("#f2b134"), false, {})
		view.dyn_root.add_child(car)
		if view.underpass.has("xray"):
			WorldView.xray(car, Color("#f2b134"))
		var pos: Vector2 = p["pos"]
		var dir: Vector2 = p["dir"]
		car.position = WorldView.w3(pos, tr.height_at(s) + WorldView.ROAD_Y)
		car.rotation.y = -dir.angle()
		var vis := 1450.0 * float(_e("ZOOM", "0.6"))
		var dist := vis * WorldView.U * 0.5 / tan(deg_to_rad(WorldView.FOV) * 0.5) * 0.92
		var focus := WorldView.w3(pos, tr.height_at(s))
		view.camera.fov = WorldView.FOV
		view.camera.position = focus + Vector3(0, sin(WorldView.PITCH), cos(WorldView.PITCH)) * dist
		view.camera.look_at(focus, Vector3.UP)
		view.light.directional_shadow_max_distance = clampf(dist * 2.2, 30.0, 200.0)
		for k in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, _e("TAG", "before"), theme])
		car.queue_free()
		await process_frame
	quit()
