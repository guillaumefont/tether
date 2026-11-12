extends SceneTree
# Medals are saved and shown. Regression cases from real bugs (2026-11-12, "Pretzel"):
# - a campaign Race won (Pretzel, 1st) saves its medal, stamps the event and shows in the
#   home page tally (the tally used to count Time trial medals only);
# - a records LAYOUT_VERSION bump drops best times but never the medals they earned (Time
#   trial medals used to be worked out from the best time only, so they all vanished).
const Records = preload("res://scripts/records.gd")
const Medals = preload("res://scripts/medals.gd")
const Campaign = preload("res://scripts/campaign.gd")

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

func _tally() -> int:
	var n := 0
	for c in Campaign.medal_counts():
		n += c
	return n

func _init() -> void:
	Records.reset()
	expect(_tally(), 0, "fresh save: no medals")

	# --- the Pretzel case: 1st in the campaign Race
	var ev := _event_index("Pretzel", "standard", "race")
	if ev < 0:
		fail("Pretzel standard race is no longer a campaign event: point this test at another race")
	else:
		var world := Campaign.chapter_of(ev)
		var before := Campaign.chapter_golds(world)
		var won := Campaign.save_race("Pretzel", "standard", 1, 1.2, true)
		expect(won["tier"], 3, "1st place = Gold")
		expect(won["held"], 0, "nothing held before")
		expect(won["new"], true, "first win is an upgrade")
		expect(Records.get_medal(Records.key("Pretzel", "standard"), "race"), 3, "race medal saved")
		expect(Campaign.event_medal(ev), 3, "campaign line stamped Gold")
		expect(Campaign.chapter_golds(world), before + 1, "world Gold count goes up")
		expect(Campaign.medal_counts()[2], 1, "home tally shows the Gold")
		if ev + 1 < Campaign.count() and Campaign.chapter_of(ev + 1) == world:
			expect(Campaign.unlocked(ev + 1), true, "the next event opens")
		# a worse run later never takes it away, a runaway win upgrades it
		expect(Campaign.save_race("Pretzel", "standard", 3, 0.0, true)["new"], false, "3rd after a win: no change")
		expect(Campaign.event_medal(ev), 3, "Gold kept after a worse race")
		expect(Campaign.save_race("Pretzel", "standard", 1, 0.0, false)["tier"], 0, "DNF earns nothing")
		var up := Campaign.save_race("Pretzel", "standard", 1, Medals.RACE_TOP_GAP + 0.5, true)
		expect(up["tier"], 4, "win by the top gap = Pivot")
		expect(up["held"], 3, "upgrade from Gold")
		expect(Campaign.medal_counts(), [0, 0, 0, 1], "tally: one Pivot, not Gold + Pivot")
	# podium places map to tiers
	expect(Medals.race_tier(2, 0.0), 2, "2nd = Silver")
	expect(Medals.race_tier(3, 0.0), 1, "3rd = Bronze")
	expect(Medals.race_tier(4, 0.0), 0, "4th = none")

	# --- Time trial medals count on the tally too
	var lk := Records.key("Lasso", "standard")
	Records.set_best(lk, Medals.targets("Lasso", "standard")[0])   # a Bronze lap
	expect(Campaign.medal("Lasso", "standard", "trial"), 1, "Bronze lap = Bronze medal")
	expect(Campaign.medal_counts(), [1, 0, 0, 1], "tally: trial Bronze + race Pivot")

	# --- a layout bump drops the times, never the medals
	var old := ConfigFile.new()
	old.set_value(Records.META, "layouts", Records.LAYOUT_VERSION - 1)
	old.set_value(lk, "best", Medals.targets("Lasso", "standard")[2])   # a Gold lap
	old.set_value(Records.key("Pretzel", "standard"), "medal_race", 4)
	old.save(Records.PATH)
	Records._cfg = null   # as if the game started again on the new build
	expect(Records.get_best(lk), -1.0, "old layout time dropped")
	expect(Campaign.medal("Lasso", "standard", "trial"), 3, "old layout Gold kept")
	expect(Campaign.event_medal(ev), 4, "race Pivot kept")
	expect(Campaign.medal_counts(), [0, 0, 1, 1], "tally after the bump")
	Records.set_best(lk, 99.0)   # a slow lap on the new layout
	expect(Campaign.medal("Lasso", "standard", "trial"), 3, "a slower time never takes a medal away")
	Records._cfg = null   # and once migrated, a restart keeps it
	expect(Campaign.medal("Lasso", "standard", "trial"), 3, "kept after a restart")

	Records.reset()
	expect(_tally(), 0, "progress reset clears every medal")
	printerr("MEDALS BAD: %d" % bad)
	quit(1 if bad > 0 else 0)
