extends SceneTree
# Obstacles posts stay off the racing line: on every track the AI drives Time Trial runs
# (fresh seeds, not the ones tools/gen_obstacles.gd placed the posts with) and never
# touches a post on a lap where it has not bumped a wall yet (a clean line never meets a
# post; a lap already gone wide may), and every track has posts. Seeds 1000-1002 are the
# medal runs. The AI bumps walls a lot on some tracks (Arch) and its line is chaotic, so
# runs drift apart between machines after a bump: only pre-bump hits are counted.
# Rerun tools/gen_obstacles.gd if this fails after a layout change. RUNS=<n> drives more
# runs per track.
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")

func _init() -> void:
	var bad := 0
	var n_runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 10
	var seeds: Array = [1000, 1001, 1002]
	for k in n_runs:
		seeds.append(500 + k)
	for d in Defs.TRACKS:
		var tr0 := TrackData.new(d, "obstacles")
		if tr0.obstacles.size() < 1:
			bad += 1
			printerr("%s: no posts" % d["name"])
		var clean_hits := 0
		var dirty_hits := 0
		for sd in seeds:
			seed(sd)
			var tr := TrackData.new(d, "obstacles")
			var race := Race.new(tr, "trial", 1)
			var c = race.cars[0]
			var dt := 1.0 / 60.0
			var lap_clean := true
			while race.clock < 400.0 and not c.finished:
				race.ai_think(c)
				race.inputs[0]["held"] = c.hook >= 0
				var lap0: int = c.lap
				race.update(dt)
				for e in race.events:
					if e["t"] == "wall":
						lap_clean = false
					elif e["t"] == "post":
						if lap_clean:
							clean_hits += 1
							printerr("  %s seed %d: post hit on a clean lap (lap %d, t %.2f)" % [d["name"], sd, c.lap, race.clock])
						else:
							dirty_hits += 1
				race.events.clear()
				if c.lap != lap0:
					lap_clean = true
			if not c.finished:
				bad += 1
		bad += clean_hits
		printerr("%-14s %d posts, %d runs: posts hit on clean laps %d, after a wall bump %d" % [d["name"], tr0.obstacles.size(), seeds.size(), clean_hits, dirty_hits])
	printerr("FAILS: ", bad)
	quit(1 if bad else 0)
