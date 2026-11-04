extends SceneTree
# Renders the loading-screen artwork with the game's own 3D world: AI cars swinging round
# a tower on a snowy track at dusk. One landscape and one portrait image; needs a display:
#   ART_THEME=snow ART_OUT=res://art/loading_snow_land.jpg xvfb-run godot --path . --rendering-method gl_compatibility --resolution 1920x1080 --script tools/gen_loading_art.gd
#   ART_THEME=snow ART_OUT=res://art/loading_snow_port.jpg ART_DIST=1900 ART_AIM_UP=60 xvfb-run godot --path . --rendering-method gl_compatibility --resolution 1080x1920 --script tools/gen_loading_art.gd
# ART_SCENERY=1 renders the land beside the track, looking away from it (world cards).
# Optional env: ART_THEME (snow, forest, rock, sand), ART_TRACK (index), ART_SECS (sim time), ART_PITCH, ART_YAW (degrees), ART_DIST (world units), ART_OUT
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")
const WorldView = preload("res://scripts/world_view.gd")

func _env(k: String, d: float) -> float:
	var v := OS.get_environment(k)
	return float(v) if v != "" else d

func _initialize() -> void:
	seed(4242)
	var view := WorldView.new()
	root.add_child(view)
	await process_frame
	var theme := OS.get_environment("ART_THEME")
	view.theme_override = theme if theme != "" else "snow"
	var tr := TrackData.new(Defs.TRACKS[int(_env("ART_TRACK", 1))], "standard")
	view.build(tr)
	var race := Race.new(tr, "race", 0)
	view.setup_cars(race, false)
	var dt := 1.0 / 60.0
	var secs := _env("ART_SECS", 6.0)
	var hooked_t := 0.0
	while race.clock < secs or hooked_t < 0.35:
		race.update(dt)
		race.events.clear()
		Race.spin_anchors(tr, dt)
		hooked_t = hooked_t + dt if race.cars[0].hook >= 0 else 0.0
		if race.clock > secs + 20.0:
			break
	view.sync(race, "race", null, {}, dt)
	view.sync(race, "race", null, {}, dt)
	# dusk: low warm sun from the side, cool sky light
	view.light.rotation = Vector3(deg_to_rad(-24), deg_to_rad(_env("ART_SUN", -60)), 0)
	view.light.light_color = Color("#ffc890")
	view.light.light_energy = 1.05
	view.light.directional_shadow_max_distance = _env("ART_SHADOW", 45.0)
	# dusk sky and a little haze for depth
	var we: WorldEnvironment = null
	for ch in view.get_children():
		if ch is WorldEnvironment:
			we = ch
	var env: Environment = we.environment
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#1b2f52")
	sky_mat.sky_horizon_color = Color("#e9b7aa")
	sky_mat.ground_horizon_color = Color("#e9b7aa")
	sky_mat.ground_bottom_color = (view.th["ground"] as Color).lerp(Color("#9fb3c8"), 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.fog_enabled = true
	env.fog_light_color = Color("#e9b7aa")
	env.fog_density = _env("ART_FOG", 0.0045)
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	var c = race.cars[0]
	var a: TrackData.Anchor = tr.anchors[c.hook]
	var mid: Vector2 = (c.pos * 0.6 + a.pos * 0.4)
	var focus := Vector3(mid.x, tr.height_at(c.s) + 20.0, mid.y) * WorldView.U
	var pitch := deg_to_rad(_env("ART_PITCH", 14.0))
	var yaw := deg_to_rad(_env("ART_YAW", 20.0))
	var dist := _env("ART_DIST", 1250.0) * WorldView.U
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	view.camera.fov = 42.0
	view.camera.position = focus + off
	view.camera.look_at(focus + Vector3(0, _env("ART_AIM_UP", 0.0) * WorldView.U, 0), Vector3.UP)
	if OS.get_environment("ART_SCENERY") != "":
		# world card: no track, just the land. Stand past the track's edge and look out.
		var ctr := tr.bounds.get_center()
		var out_dir := Vector2.from_angle(deg_to_rad(_env("ART_YAW", 20.0)))
		var edge := ctr
		while tr.bounds.grow(120.0).has_point(edge):
			edge += out_dir * 20.0
		var eye := Vector3(edge.x, _env("ART_EYE", 260.0), edge.y) * WorldView.U
		var tgt := Vector3(edge.x + out_dir.x * 1500.0, 0.0, edge.y + out_dir.y * 1500.0) * WorldView.U
		view.camera.position = eye
		view.camera.look_at(tgt, Vector3.UP)
	view.snowfall.visible = false
	for k in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := OS.get_environment("ART_OUT")
	if out == "":
		out = "res://art/loading_bg.jpg"
	img.save_jpg(out, 0.88)
	print("saved ", out, " ", img.get_size(), " hooked=", c.hook)
	quit()
