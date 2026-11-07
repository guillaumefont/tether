extends SceneTree
# Renders the car design study (scripts/car_designs.gd): every style on every theme.
#   PREVIEW_OUT=/tmp/shots xvfb-run -s "-screen 0 900x700x24" godot --path . --rendering-method gl_compatibility --resolution 900x700 --script tools/car_design_preview.gd
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Designs = preload("res://scripts/car_designs.gd")

func _initialize() -> void:
	root.msaa_3d = Viewport.MSAA_4X
	var out := OS.get_environment("PREVIEW_OUT")
	var styles := _e("PREVIEW_STYLES", "pebble,arrow,buggy").split(",")
	var themes := _e("PREVIEW_THEMES", "snow,forest,sand,rock").split(",")
	var views := _e("PREVIEW_VIEWS", "34,game").split(",")
	var view := WorldView.new()
	root.add_child(view)
	await process_frame
	for t in themes:
		view.theme_override = t
		print("build ", t)
		view.build(TrackData.new(Defs.TRACKS[1], "standard"))
		for st in styles:
			var tr: TrackData = view.track
			var p := tr.point_at(tr.start_s + 260.0)
			var car := Designs.build(st, t, Color(_e("PREVIEW_COL", "#f5c518")))
			view.dyn_root.add_child(car)
			var pos: Vector2 = p["pos"]
			var dir: Vector2 = p["dir"]
			car.position = WorldView.w3(pos, view.track.height_at(tr.start_s + 260.0) + WorldView.ROAD_Y)
			car.rotation.y = -dir.angle()
			var fwd := Vector3(dir.x, 0, dir.y)
			var left := Vector3(dir.y, 0, -dir.x)
			for v in views:
				if v == "34":
					view.camera.position = car.position + fwd * 1.9 + left * 2.3 + Vector3(0, 1.75, 0)
					view.camera.fov = 30
				elif v == "back":
					view.camera.position = car.position - fwd * 1.5 + left * 1.3 + Vector3(0, 1.2, 0)
					view.camera.fov = 30
				elif v == "side":
					view.camera.position = car.position + left * 2.6 + Vector3(0, 0.35, 0)
					view.camera.fov = 26
				else:   # roughly the race camera: steep from above, far
					view.camera.position = car.position + Vector3(0, 17.0, 6.9)
					view.camera.fov = 14
				view.camera.look_at(car.position + Vector3(0, 0.25 if v != "game" else 0.0, 0))
				for k in 4:
					await process_frame
				await RenderingServer.frame_post_draw
				print("shot ", st, v)
				root.get_texture().get_image().save_png("%s/%s_%s_%s.png" % [out, st, t, v])
			car.queue_free()
			await process_frame
	quit()

func _e(k: String, d: String) -> String:
	var v := OS.get_environment(k)
	return v if v != "" else d
