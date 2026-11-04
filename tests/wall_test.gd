extends SceneTree
# Headless check: a car on the road edge never stays pinned there. A driver who never
# hooks drifts into walls all lap; it must keep moving and get off the rail again.
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")

func _init() -> void:
	var fails := 0
	var dt := 1.0 / 60.0
	for d in Defs.TRACKS:
		var tr := TrackData.new(d, "standard")
		var race := Race.new(tr, "trial", 1)
		var c = race.cars[0]
		var scrape_t := 0.0
		var run := 0.0
		var worst_run := 0.0
		var slow_t := 0.0
		var dist := 0.0
		var t := 0.0
		while t < 20.0:
			var p0: Vector2 = c.pos
			race.update(dt)
			race.events.clear()
			t += dt
			dist += c.pos.distance_to(p0)
			if c.scrape > 0.0:
				scrape_t += dt
				run += dt
				worst_run = maxf(worst_run, run)
			else:
				run = 0.0
			if c.speed() < 150.0:
				slow_t += dt
		var ok := worst_run < 1.5 and slow_t < 4.0
		if not ok: fails += 1
		printerr("%-14s %s on-edge=%4.1fs longest=%4.1fs slow=%4.1fs avg=%4.0f" % [d["name"], "OK  " if ok else "FAIL", scrape_t, worst_run, slow_t, dist / t])
	printerr("FAILS: ", fails)
	quit(1 if fails else 0)
