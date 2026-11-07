extends SceneTree
# Obstacles posts stay off the racing line: on every track the AI drives clean Time Trial
# runs (fresh seeds, not the ones tools/gen_obstacles.gd placed the posts with) and never
# touches a post, and every track has posts. Rerun tools/gen_obstacles.gd if this fails
# after a layout change.
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")

func _init() -> void:
	var bad := 0
	for d in Defs.TRACKS:
		var tr0 := TrackData.new(d, "obstacles")
		if tr0.obstacles.size() < 1:
			bad += 1
			printerr("%s: only %d posts" % [d["name"], tr0.obstacles.size()])
		var hits: Array = []
		for run in 8:
			seed(500 + run)
			var tr := TrackData.new(d, "obstacles")
			var race := Race.new(tr, "trial", 1)
			var c = race.cars[0]
			var dt := 1.0 / 60.0
			while race.clock < 400.0 and not c.finished:
				race.ai_think(c)
				race.inputs[0]["held"] = c.hook >= 0
				race.update(dt)
				race.events.clear()
			hits.append(c.hits)
			if c.hits > 0 or not c.finished:
				bad += 1
		printerr("%-14s %d posts, AI hits per run %s" % [d["name"], tr0.obstacles.size(), str(hits)])
	printerr("FAILS: ", bad)
	quit(1 if bad else 0)
