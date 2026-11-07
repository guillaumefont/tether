extends SceneTree
# Renders one car per cosmetic look on a track for design previews (garage art too).
#   PREVIEW_OUT=/tmp/shots PREVIEW_SET=liveries xvfb-run -s "-screen 0 1200x900x24" godot --path . --rendering-method gl_compatibility --resolution 1200x900 --script tools/car_preview.gd
# PREVIEW_SET: liveries | paints | themes ; PREVIEW_THEME: snow, forest, rock, sand
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Cosmetics = preload("res://scripts/cosmetics.gd")

func _initialize() -> void:
	root.msaa_3d = Viewport.MSAA_4X
	var out := OS.get_environment("PREVIEW_OUT")
	var set := OS.get_environment("PREVIEW_SET")
	var theme := OS.get_environment("PREVIEW_THEME")
	if theme == "": theme = "snow"
	var looks: Array = []   # [file, theme, paint, livery]
	match set:
		"paints":
			for p in Cosmetics.PAINTS:
				looks.append([p["id"], theme, p["id"], "none"])
		"themes":
			for t in ["snow", "forest", "sand", "rock"]:
				looks.append(["theme_" + t, t, "cobalt", "stripes"])
		_:
			var paints := ["amber", "signal", "cobalt", "frost", "lime", "flamingo", "ember", "slate"]
			var i := 0
			for l in Cosmetics.LIVERIES:
				looks.append([l["id"], theme, paints[i % paints.size()], l["id"]])
				i += 1
	var view := WorldView.new()
	root.add_child(view)
	await process_frame
	var cur := ""
	for lk in looks:
		if lk[1] != cur:
			cur = lk[1]
			view.theme_override = cur
			view.build(TrackData.new(Defs.TRACKS[1], "standard"))
		var tr: TrackData = view.track
		var p := tr.point_at(tr.start_s + 260.0)
		var look := Cosmetics.look(lk[2], lk[3])
		var car := view._make_car(look["color"], false, look)
		view.dyn_root.add_child(car)
		var pos: Vector2 = p["pos"]
		var dir: Vector2 = p["dir"]
		car.position = WorldView.w3(pos, view.track.height_at(tr.start_s + 260.0) + WorldView.ROAD_Y)
		car.rotation.y = -dir.angle()
		# camera: three-quarter view from the front left, above
		var fwd := Vector3(dir.x, 0, dir.y)
		var left := Vector3(dir.y, 0, -dir.x)
		var eye := car.position + (fwd * float(_e("PREVIEW_F", "-1.3")) + left * float(_e("PREVIEW_L", "1.5")) + Vector3(0, float(_e("PREVIEW_UP", "1.9")), 0))
		view.camera.position = eye
		view.camera.look_at(car.position + Vector3(0, 0.25, 0))
		view.camera.fov = 32
		for k in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("%s/%s.png" % [out, lk[0]])
		car.queue_free()
		await process_frame
	quit()

func _e(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d
