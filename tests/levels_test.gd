extends SceneTree
# Every bend must be flat and every crossing must have the two roads on different
# levels with room to ramp. Prints each track's bend levels; fails on any problem.
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
func _init() -> void:
	var bad := 0
	for d in Defs.TRACKS:
		for v in ["standard", "reverse"]:
			var t0 := Time.get_ticks_msec()
			var T := TrackData.new(d, v)
			var ms := Time.get_ticks_msec() - t0
			# bends flat: height constant from entry to exit
			var flat := true
			for k in T.arcs.size():
				var a: Dictionary = T.arcs[k]
				var h0 := T.height_at(a["s0"])
				var x := 0.0
				while x <= a["len"]:
					if absf(T.height_at(a["s0"] + x) - h0) > 0.5: flat = false
					x += 20.0
			var ok: bool = flat and T.ramp_report == ""
			if not ok: bad += 1
			printerr("%-14s %-8s bends %s  %s%s %dms" % [d["name"], v, str(Array(T.arc_level)), "OK" if ok else "FAIL ", ("" if flat else "bend not flat; ") + T.ramp_report, ms])
	printerr("BAD: ", bad)
	quit(1 if bad else 0)
