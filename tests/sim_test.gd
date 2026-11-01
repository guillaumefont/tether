extends SceneTree
# Headless check: every track and variant builds, and AI drivers finish the race.
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")

func _init() -> void:
	var fails := 0
	var only := OS.get_environment("VARS")
	var vars := only.split(",") if only != "" else PackedStringArray(["standard", "reverse", "obstacles", "collect"])
	for d in Defs.TRACKS:
		for v in vars:
			var tr := TrackData.new(d, v)
			var race := Race.new(tr, "race", 0)
			var t0 := Time.get_ticks_msec()
			var dt := 1.0 / 60.0
			while race.clock < 300.0:
				race.update(dt)
				race.events.clear()
				if race.cars.all(func(c): return c.finished): break
			var res := []
			for c in race.cars:
				res.append("%s:%s" % [c.name, ("%.1f" % c.finish_time) if c.finished else "DNF(lap %d)" % c.lap])
			var ok: bool = race.cars.all(func(c): return c.finished)
			if not ok: fails += 1
			printerr("%-14s %-9s %s cpu=%dms  %s" % [d["name"], v, "OK  " if ok else "FAIL", Time.get_ticks_msec() - t0, " ".join(res)])
	printerr("FAILS: ", fails)
	quit(1 if fails else 0)
