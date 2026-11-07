extends SceneTree
# Every bend must be flat and every crossing must have the two roads on different
# levels with room to ramp. Prints each track's bend levels; fails on any problem.
const TrackData = preload("res://scripts/track.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Medals = preload("res://scripts/medals.gd")
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
	# every track and variant needs medal targets (rerun tools/gen_medals.gd after a layout change)
	for d in Defs.TRACKS:
		for v in Defs.VARIANTS:
			if Medals.targets(d["name"], v[0])[0] <= 0.0:
				bad += 1
				printerr("no medal times for %s %s: run tools/gen_medals.gd" % [d["name"], v[0]])
	# every campaign event names a real track and variant
	for i in Campaign.count():
		var e := Campaign.event(i)
		if e["track"] < 0 or not Defs.VARIANTS.any(func(v): return v[0] == e["variant"]) or not e["mode"] in ["trial", "race"]:
			bad += 1
			printerr("bad campaign event %d: %s" % [i, str(e)])
	# no event repeats another one (each is its own medal), and every world has twelve
	var seen := {}
	for i in Campaign.count():
		var e := Campaign.event(i)
		var k := "%s/%s/%s" % [e["name"], e["variant"], e["mode"]]
		if seen.has(k):
			bad += 1
			printerr("campaign event %d repeats event %d: %s" % [i, seen[k], k])
		seen[k] = i
	for c in Campaign.CHAPTERS.size():
		if Campaign.chapter_size(c) != 12:
			bad += 1
			printerr("campaign world %d has %d events" % [c, Campaign.chapter_size(c)])
	printerr("BAD: ", bad)
	quit(1 if bad else 0)
