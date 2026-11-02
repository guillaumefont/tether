extends SceneTree
# Offline helper: nudges tower positions (and curve radii) of the given tracks until
# every bend can stay flat (bridge ramps only on straights), roads keep clear of each
# other and of towers, and the layout stays as compact as the original.
# Usage: godot --headless --path . --script tools/fix_layouts.gd -- 0,7,10
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const HW := TrackData.HW
const Check = preload("res://tools/layout_check.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var ids: Array = []
	for x in (args[0] if args.size() else "0").split(","): ids.append(int(x))
	seed(7)
	for ti in ids:
		var d0: Dictionary = Defs.TRACKS[ti]
		var base := Check.check(d0)
		var best := d0.duplicate(true)
		var bc := base
		var best_cost := _cost(bc, base, d0, best)
		printerr("%s start bad=%d L=%d bridges=%d" % [d0["name"], bc["bad"], bc["L"], bc["bridges"]])
		var step := 260.0
		for it in 4000:
			if bc["bad"] == 0.0 and it > 900: break
			var cand := best.duplicate(true)
			var k: int = randi() % cand["turns"].size()
			var t: Array = cand["turns"][k]
			var same: Array = []  # towers sharing a position move together
			for u in cand["turns"]:
				if absf(u[0] - t[0]) < 1 and absf(u[1] - t[1]) < 1: same.append(u)
			var dx := roundf(randf_range(-step, step)); var dy := roundf(randf_range(-step, step))
			for u in same:
				u[0] += dx; u[1] += dy
			if randf() < 0.12:
				var r := 750.0 if (t.size() < 4 or t[3] < 700) else 350.0
				if t.size() < 4: t.append(r)
				else: t[3] = r
			var c := Check.check(cand)
			if c["bridges"] < base["bridges"]: continue
			var cost := _cost(c, base, d0, cand)
			if cost < best_cost:
				best_cost = cost; best = cand; bc = c
			if it % 300 == 299: step = maxf(60.0, step * 0.8)
		printerr("%s done bad=%d L=%d (was %d) bridges=%d levels=%s" % [d0["name"], bc["bad"], bc["L"], base["L"], bc["bridges"], str(bc["levels"])])
		var ts := []
		for t in best["turns"]:
			var parts := [str(int(t[0])), str(int(t[1])), str(int(t[2]))]
			if t.size() > 3 and t[3] != TrackData.TURN_R: parts.append(str(int(t[3])))
			ts.append("[" + ",".join(parts) + "]")
		print("RESULT %d %s" % [ti, "[" + ",".join(ts) + "]"])
	quit()

func _cost(c: Dictionary, base: Dictionary, d0: Dictionary, d: Dictionary) -> float:
	var move := 0.0
	for k in d["turns"].size():
		move += Vector2(d["turns"][k][0], d["turns"][k][1]).distance_to(Vector2(d0["turns"][k][0], d0["turns"][k][1]))
	return c["bad"] + maxf(0.0, c["L"] - base["L"]) * 0.1 + move * 0.01
