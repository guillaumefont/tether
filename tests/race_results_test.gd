extends SceneTree
# Race results say what the player saw on the road. Regression case from a real bug
# (2026-11-12, "Twin Bend"): Guillaume crossed the line first in the campaign race on Twin
# Bend (Obstacles), but the results said "4th place" and no Gold. Each post he had hit added
# a second to his finish time after the line, so rivals who crossed later ranked ahead.
# Now a Race is won by the first car over the line (posts cost speed on the road), while
# Time trial still adds its +1 s per post and +0.25 s per missed gem.
# Usage: godot --headless --path . --script tests/race_results_test.gd
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Rivals = preload("res://scripts/rivals.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Records = preload("res://scripts/records.gd")

const DT := 1.0 / 60.0

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func expect(got, want, what: String) -> void:
	if got != want:
		fail("%s: got %s, want %s" % [what, str(got), str(want)])

func _event_index(track_name: String, variant: String, mode: String) -> int:
	for i in Campaign.count():
		var e := Campaign.event(i)
		if e["name"] == track_name and e["variant"] == variant and e["mode"] == mode:
			return i
	return -1

func _track(track_name: String) -> Dictionary:
	for d in Defs.TRACKS:
		if d["name"] == track_name:
			return d
	return {}

# Drive a whole race with the player's car steered like the AI. `hits` posts are put on
# the player's card before the start (as if hit along the way). Returns the order the cars
# crossed the finish line in, and the race.
func _run(d: Dictionary, variant: String, mode: String, tier: int, hits: int) -> Dictionary:
	var race := Race.new(TrackData.new(d, variant), mode, 1)
	if mode == "race":
		race.set_rivals(tier, true)
	var me = race.cars[0]
	me.hits = hits
	var crossed: Array = []
	var line_clock := {}
	while race.clock < 300.0 and not race.cars.all(func(c): return c.finished):
		race.ai_think(me, DT)
		race.inputs[0]["held"] = me.hook >= 0
		race.update(DT)
		for e in race.events:
			if e["t"] == "finish":
				crossed.append(e["car"])
				line_clock[e["car"]] = race.clock
		race.events.clear()
	return { "race": race, "me": me, "crossed": crossed, "line": line_clock }

func _init() -> void:
	Records.reset()
	var d := _track("Twin Bend")
	var ev := _event_index("Twin Bend", "obstacles", "race")
	if d.is_empty() or ev < 0:
		fail("Twin Bend Obstacles race is no longer a campaign event: point this test at another race")
		quit(1)
		return
	var tier := Rivals.campaign_tier(Campaign.chapter_of(ev))

	# --- the Twin Bend case: first over the line with posts hit on the way
	var wins_with_hits := 0
	for r in 6:
		seed(700 + r)
		var run := _run(d, "obstacles", "race", tier, 3)
		var race = run["race"]
		var me = run["me"]
		if not race.cars.all(func(c): return c.finished):
			fail("seed %d: not every car finished" % r)
			continue
		var res: Dictionary = race.result()
		var crossed: Array = run["crossed"]
		var seen: int = crossed.find(me) + 1
		expect(res["place"], seen, "seed %d: results place = the place the player crossed the line in" % r)
		var st: Array = res["standings"]
		for k in st.size():
			expect(st[k].name, crossed[k].name, "seed %d: results row %d = car %d over the line" % [r, k + 1, k + 1])
		expect(me.finish_time, run["line"][me], "seed %d: no seconds added after the line in a race" % r)
		if seen == 1:
			wins_with_hits += 1
			expect(res["title"], "%s wins" % me.name, "seed %d: the results title says the player won" % r)
			expect(res["lead"] > 0.0, true, "seed %d: a winner leads the 2nd car" % r)
			# the medal and the campaign follow the same place
			Records.reset()
			var won := Campaign.save_race("Twin Bend", "obstacles", res["place"], res["lead"], res["finished"])
			expect(won["tier"] >= Campaign.GOLD, true, "seed %d: a race win earns Gold or better" % r)
			expect(Campaign.event_medal(ev) >= Campaign.GOLD, true, "seed %d: the campaign line shows the Gold" % r)
			if ev + 1 < Campaign.count() and Campaign.chapter_of(ev + 1) == Campaign.chapter_of(ev):
				expect(Campaign.unlocked(ev + 1), true, "seed %d: the win opens the next event" % r)
		else:
			expect(res["title"], "%s place" % Race.ordinal(seen), "seed %d: the results title gives the place" % r)
	if wins_with_hits == 0:
		fail("the stand-in player never crossed first: the case was not checked (pick other seeds)")

	# --- a hand-made finish: the player is first over the line with the most posts hit
	var race2 := Race.new(TrackData.new(d, "obstacles"), "race", 1)
	var hits := [3, 0, 0, 0]
	for k in race2.cars.size():
		var c = race2.cars[k]
		c.finished = true
		c.finish_time = 40.0 + k * 0.4   # crossing order = field order, all within 3 s
		c.hits = hits[k]
	var res2: Dictionary = race2.result()
	expect(res2["place"], 1, "first over the line with 3 posts: 1st")
	expect(res2["title"], "Player 1 wins", "results title")

	# --- Time trial keeps its penalties: +1 s per post hit
	seed(700)
	var trial := _run(d, "obstacles", "trial", 0, 2)
	var tc = trial["me"]
	if not tc.finished:
		fail("Time trial run did not finish")
	else:
		expect(tc.hits >= 2, true, "Time trial: the posts stay on the card")
		expect(snappedf(tc.finish_time - trial["line"][tc], 0.001), snappedf(tc.hits * Race.OBS_PEN, 0.001), "Time trial: +1 s per post hit")

	Records.reset()
	printerr("FAILS: ", bad)
	quit(1 if bad else 0)
