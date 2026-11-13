extends SceneTree
# Under a bridge the car stays in sight (Guillaume, 2026-11-13): on every track, every bit of
# deck that lies over the lane below is part of a see-through window, every bridge gets one,
# each world has its own window look, and building the 3D view really puts the window in
# (and leaves the asphalt out there). Visual only: race.gd is not involved.
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Themes = preload("res://scripts/themes.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

# distance from p to the road's centre line, near point index a only (the lane below)
func _dist_to_lane(tr: TrackData, a: int, p: Vector2) -> float:
	var best := INF
	for k in range(a - 25, a + 26):
		var i := posmod(k, tr.n)
		var p0: Vector2 = tr.P[i]
		var p1: Vector2 = tr.P[(i + 1) % tr.n]
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, p0, p1).distance_to(p))
	return best

func _initialize() -> void:
	var view := WorldView.new()
	root.add_child(view)
	await process_frame
	var bridges := 0
	for d in Defs.TRACKS:
		var tr := TrackData.new(d, "standard")
		view.track = tr
		view._wins = view._window_spans()
		if view._wins.size() != tr.bridges.size():
			fail("%s: %d bridges but %d windows" % [d["name"], tr.bridges.size(), view._wins.size()])
		for B in tr.bridges:
			bridges += 1
			# which pass is on top: the higher of the two
			var a: int = B["under"]
			var b: int = (int(B["from"]) + posmod(int(B["to"]) - int(B["from"]), tr.n) / 2) % tr.n
			if tr.height_at(tr.s_of(a, 0.5)) > tr.height_at(tr.s_of(b, 0.5)):
				var t := a; a = b; b = t
			# walk the deck round the crossing; any deck point over the lane below must be glass
			var miss := 0
			var s0 := tr.s_of(b, 0.5)
			var sv := s0 - 900.0
			while sv < s0 + 900.0:
				var q := tr.point_at(sv)
				var nrm := TrackData.perp(q["dir"])
				for off in range(-int(TrackData.HW), int(TrackData.HW) + 1, 30):
					var p: Vector2 = q["pos"] + nrm * off
					if absf(tr.height_at(sv) - tr.height_at(tr.s_of(a, 0.5))) > 60.0 \
							and _dist_to_lane(tr, a, p) < TrackData.HW - 10.0 and view._in_window(sv).is_empty():
						miss += 1
				sv += 10.0
			if miss > 0:
				fail("%s: %d deck points over the lane below are not see-through" % [d["name"], miss])
	if bridges < 5:
		fail("only %d bridges in all tracks: the test looks at the wrong thing" % bridges)
	# a look per world, and the 3D build puts the window in
	for theme in Themes.ORDER:
		var m: ShaderMaterial = view._window_mat(Themes.get_theme(theme)["kit"])
		if m == null or int(m.get_shader_parameter("kind")) < 0:
			fail("%s: no window look" % theme)
		view.theme_override = theme
		view.build(TrackData.new(Defs.TRACKS[1], "standard"))   # Diamond Eight: one bridge
		await process_frame
		var w: Node = null
		for ch in view.static_root.get_children():
			if ch.has_meta("deck_window") and not ch.is_queued_for_deletion():
				w = ch
		if w == null or (w as MeshInstance3D).mesh.get_aabb().get_longest_axis_size() < 2.0:
			fail("%s: the deck window was not built" % theme)
	print("underpass: %d bridges checked, %d problems" % [bridges, bad])
	quit(1 if bad > 0 else 0)
