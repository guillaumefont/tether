extends SceneTree
# Renders the loading-screen artwork with the game's own 3D world: AI cars swinging round
# a tower on a snowy track at dusk. One landscape and one portrait image; needs a display.
# Render at twice the wanted size and set ART_SIZE: the frame is scaled down (supersampled)
# for clean edges. Loading art is 2560x1440 / 1440x2560:
#   ART_THEME=snow ART_OUT=res://art/loading_snow_land.jpg ART_SIZE=2560x1440 xvfb-run -s "-screen 0 5120x2880x24" godot --path . --rendering-method gl_compatibility --resolution 5120x2880 --script tools/gen_loading_art.gd
#   ART_THEME=snow ART_OUT=res://art/loading_snow_port.jpg ART_SIZE=1440x2560 ART_YAW=260 ART_DIST=1500 ART_AIM_UP=30 xvfb-run -s "-screen 0 2880x5120x24" godot --path . --rendering-method gl_compatibility --resolution 2880x5120 --script tools/gen_loading_art.gd
# Sand landscape uses ART_YAW=265 (a palm sits in front at 250). The AI race and the scenery
# shift when tracks or terrain change: sweep ART_YAW / ART_SECS at low res with ART_BAKE_AO=0 first.
# ART_SCENERY=1 renders the land beside the track, looking away from it (world cards).
# Ambient occlusion is ray traced on the CPU and multiplied into the frame (ART_BAKE_AO =
# strength, 0 = off; ART_AO_RES = AO buffer width; ART_AO_RANGE = ray length in metres),
# so it works with the phone renderer and keeps the game's look.
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
	root.msaa_3d = Viewport.MSAA_4X
	RenderingServer.directional_shadow_atlas_set_size(8192, true)
	WorldView.detail = int(_env("ART_DETAIL", 2))   # artwork uses the high-detail models
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
	var secs := _env("ART_SECS", 8.0)
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
	# ambient occlusion and indirect light (Forward+ only: --rendering-method forward_plus)
	if RenderingServer.get_current_rendering_method() == "forward_plus" and _env("ART_AO", 1.0) > 0.0:
		env.ssao_enabled = true
		env.ssao_radius = _env("ART_AO_RADIUS", 2.0)
		env.ssao_intensity = _env("ART_AO", 4.0)
		env.ssao_power = 1.6
		env.ssao_detail = 0.6
		env.ssao_light_affect = 0.15
		env.ssil_enabled = true
		env.ssil_radius = 4.0
		env.ssil_intensity = 0.6
		# Forward+ renders the same scene flatter and hazier than the phone renderer:
		# thinner haze and a little contrast bring it back to the game's look
		env.fog_density = _env("ART_FOG", 0.0025)
		env.adjustment_enabled = true
		env.adjustment_brightness = _env("ART_BRIGHT", 1.08)
		env.adjustment_contrast = _env("ART_CONTRAST", 1.18)
		env.adjustment_saturation = _env("ART_SAT", 1.12)
	var c = race.cars[0]
	var a: TrackData.Anchor = tr.anchors[c.hook]
	var mid: Vector2 = (c.pos * 0.6 + a.pos * 0.4)
	var focus := Vector3(mid.x, tr.height_at(c.s) + 20.0, mid.y) * WorldView.U
	var pitch := deg_to_rad(_env("ART_PITCH", 14.0))
	var yaw := deg_to_rad(_env("ART_YAW", 250.0))
	var dist := _env("ART_DIST", 1050.0) * WorldView.U
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
	var want := OS.get_environment("ART_SIZE").split("x")
	if want.size() == 2:
		img.resize(int(want[0]), int(want[1]), Image.INTERPOLATE_LANCZOS)
	if _env("ART_BAKE_AO", 0.7) > 0.0:
		img = await _bake_ao(view, img, _env("ART_BAKE_AO", 0.7))
	var out := OS.get_environment("ART_OUT")
	if out == "":
		out = "res://art/loading_bg.jpg"
	img.save_jpg(out, 0.88)
	print("saved ", out, " ", img.get_size(), " hooked=", c.hook)
	quit()


# ---------------------------------------------------------------- baked ambient occlusion
# Every visible mesh goes into one collision trimesh. For each pixel of a small AO buffer a
# camera ray finds the surface, then a fan of hemisphere rays measures how much of the sky
# nearby geometry hides. The buffer is multiplied over the frame on the GPU.
func _collect_faces(n: Node, faces: PackedVector3Array, focus: Vector3, reach: float) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		if mi.global_position.distance_to(focus) < reach or mi.mesh.get_aabb().size.length() > 20.0:
			var xf := mi.global_transform
			for v in mi.mesh.get_faces():
				faces.append(xf * v)
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm.mesh != null:
			var local := mm.mesh.get_faces()
			var base := (n as MultiMeshInstance3D).global_transform
			for i in mm.instance_count:
				var xf := base * mm.get_instance_transform(i)
				if xf.origin.distance_to(focus) > reach:
					continue
				for v in local:
					faces.append(xf * v)
	for ch in n.get_children():
		_collect_faces(ch, faces, focus, reach)

func _bake_ao(view: Node3D, img: Image, strength: float) -> Image:
	var t0 := Time.get_ticks_msec()
	var cam: Camera3D = view.camera
	var size := img.get_size()
	var focus := cam.global_position + -cam.global_basis.z * 15.0
	var faces := PackedVector3Array()
	_collect_faces(view, faces, focus, 90.0)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	# camera rays and controls use the stretched viewport size, not the window's pixels
	var vis := root.get_visible_rect().size
	var aw := int(_env("ART_AO_RES", 960.0))
	var ah := int(round(aw * float(size.y) / size.x))
	var reach := _env("ART_AO_RANGE", 1.4)
	# cosine-weighted hemisphere directions (z up), rotated per pixel
	var dirs: Array[Vector3] = []
	var n_dirs := int(_env("ART_AO_RAYS", 24.0))
	for k in n_dirs:
		var u := (k + 0.5) / n_dirs
		var phi := k * 2.39996
		var r := sqrt(u)
		dirs.append(Vector3(cos(phi) * r, sin(phi) * r, sqrt(1.0 - u)))
	var q := PhysicsRayQueryParameters3D.new()
	q.hit_back_faces = true
	var ao := Image.create(aw, ah, false, Image.FORMAT_L8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in ah:
		for x in aw:
			var sp := Vector2((x + 0.5) * vis.x / aw, (y + 0.5) * vis.y / ah)
			var o := cam.project_ray_origin(sp)
			var d := cam.project_ray_normal(sp)
			q.from = o
			q.to = o + d * 200.0
			var hit := space.intersect_ray(q)
			var val := 1.0
			if not hit.is_empty():
				var p: Vector3 = hit["position"]
				var nrm: Vector3 = hit["normal"]
				if nrm.dot(d) > 0.0:
					nrm = -nrm
				var tng := nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
				tng = tng.rotated(nrm, rng.randf() * TAU)
				var btg := nrm.cross(tng)
				var occ := 0.0
				# start a little off the surface so decals and overlapping strips (lane
				# dashes, bank seams) do not shadow themselves
				var start := p + nrm * 0.05
				for v in dirs:
					var w := (tng * v.x + btg * v.y + nrm * v.z).normalized()
					q.from = start
					q.to = start + w * reach
					var h2 := space.intersect_ray(q)
					if not h2.is_empty():
						var dd := start.distance_to(h2["position"])
						if dd > 0.04:
							occ += 1.0 - dd / reach * 0.6
				var far := clampf((p.distance_to(cam.global_position) - 60.0) / 40.0, 0.0, 1.0)
				val = 1.0 - strength * (occ / n_dirs) * (1.0 - far)
			ao.set_pixel(x, y, Color(val, val, val))
	body.queue_free()
	print("ao ", aw, "x", ah, " tris=", faces.size() / 3, " in ", (Time.get_ticks_msec() - t0) / 1000.0, " s")
	if OS.get_environment("ART_AO_DUMP") != "":
		ao.save_png(OS.get_environment("ART_AO_DUMP"))
	# soften the ray noise, scale up to the frame and multiply it in
	ao.resize(aw / 2, ah / 2, Image.INTERPOLATE_BILINEAR)
	ao.resize(aw, ah, Image.INTERPOLATE_CUBIC)
	ao.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGB8)
	var px := img.get_data()
	var av := ao.get_data()
	for i in av.size():
		var f := av[i]
		if f < 255:
			var j := i * 3
			px[j] = px[j] * f / 255
			px[j + 1] = px[j + 1] * f / 255
			px[j + 2] = px[j + 2] * f / 255
	var out := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, px)
	return out
