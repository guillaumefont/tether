extends SceneTree
# The tutorial can be finished: a scripted thumb taps, holds and lets go when the guided
# bends freeze, then the AI drives; the run reaches the end panel, the AI beats the
# target on its first try, and the extras lap has posts and gems.
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Tutorial = preload("res://scripts/tutorial.gd")

func _init() -> void:
	var bad := 0
	var tr := TrackData.new(Defs.TUTORIAL, "standard")
	Tutorial.dress(tr)
	if tr.obstacles.size() < 2 or tr.tokens.size() < 5:
		bad += 1
		printerr("extras: %d posts, %d gems" % [tr.obstacles.size(), tr.tokens.size()])
	var race := Race.new(tr, "trial", 1)
	var tut := Tutorial.new(race)
	var c = race.cars[0]
	var dt := 1.0 / 60.0
	var t := 0.0
	var waits := {}
	var laps: Array = []
	while t < 300.0 and not tut.complete:
		t += dt
		if tut.wait != "":
			waits[tut.wait] = waits.get(tut.wait, 0) + 1
		match tut.wait:
			"tap": tut.tap()
			"hold": race.press(0)
			"release": race.release(0)
			_:
				if tut.hooks >= 1:
					race.ai_think(c)
					race.inputs[0]["held"] = c.hook >= 0
		var sc := tut.update(dt)
		race.update(dt * sc)
		for e in race.events:
			if e["t"] == "lap":
				laps.append(e["lt"])
				tut.on_lap(c.lap - 1, e["lt"])
		race.events.clear()
	printerr("TUTORIAL laps=%s target=%.1f tries=%d hits=%d gems=%d/%d waits=%s" % [str(laps), tut.target, tut.tries, c.hits, c.gems, tr.tokens.size(), str(waits)])
	if not tut.complete:
		bad += 1
		printerr("did not reach the end (stage %s)" % tut.stage)
	if not (waits.has("hold") and waits.has("release") and waits.has("tap")):
		bad += 1
		printerr("the first bend did not freeze for hold and release")
	if tut.tries != 1:
		bad += 1
		printerr("AI needed %d tries at the target" % tut.tries)
	if c.gems == 0:
		bad += 1
		printerr("no gem picked up on the extras lap")
	printerr("TUTORIAL BAD: %d" % bad)
	quit(1 if bad > 0 else 0)
