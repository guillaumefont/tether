extends SceneTree
# Headless check of the AI rivals' difficulty tiers. A stand-in player (the reference AI
# driver that sets the medal times, so roughly a Gold-medal player, and a scrappier one)
# races every campaign race event against each tier, with the campaign's catch-up on.
# Checks: every car finishes, harder tiers are harder (worse average place), the good
# stand-in can still win at Master and the scrappy one wins most Rookie races.
# Usage: godot --headless --path . --script tests/rivals_test.gd   (RUNS=n seeds per race)
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Rivals = preload("res://scripts/rivals.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Defs = preload("res://scripts/track_defs.gd")

const PLAYERS := [
	{ "name": "good", "skill": 1.0, "aim": 1.0 },
	{ "name": "scrappy", "skill": 0.95, "aim": 2.2 },
]

func _race(d: Dictionary, variant: String, tier: int, pl: Dictionary, catch_up: bool) -> Dictionary:
	var tr := TrackData.new(d, variant)
	var race := Race.new(tr, "race", 1)
	race.set_rivals(tier, catch_up)
	var me = race.cars[0]
	me.skill = pl["skill"]; me.aim = pl["aim"]
	var dt := 1.0 / 60.0
	var moves := 0
	while race.clock < 300.0 and not race.cars.all(func(c): return c.finished):
		race.ai_think(me, dt)   # the stand-in player drives like the AI (no blocking)
		race.inputs[0]["held"] = me.hook >= 0
		race.update(dt)
		race.events.clear()
		for c in race.cars:
			if c.lane_t > 0.0: moves += 1
	var st := race.standings()
	return { "ok": race.cars.all(func(c): return c.finished), "place": st.find(me) + 1, "moves": moves }

func _init() -> void:
	var runs := int(OS.get_environment("RUNS")) if OS.get_environment("RUNS") != "" else 2
	var events: Array = []
	for i in Campaign.count():
		var e := Campaign.event(i)
		if e["mode"] == "race":
			events.append(e)
	var fails := 0
	var avg := {}
	for pl in PLAYERS:
		for t in Rivals.TIERS.size():
			var places := 0
			var wins := 0
			var n := 0
			var moves := 0
			for e in events:
				for r in runs:
					seed(500 + r)
					var res := _race(Defs.TRACKS[e["track"]], e["variant"], t, pl, true)
					if not res["ok"]:
						fails += 1
						printerr("DNF: %s %s tier %s" % [e["name"], e["variant"], Rivals.tier_name(t)])
					places += res["place"]
					wins += 1 if res["place"] == 1 else 0
					moves += res["moves"]
					n += 1
			avg[[pl["name"], t]] = float(places) / n
			avg[[pl["name"], t, "win"]] = float(wins) / n
			printerr("%-8s vs %-7s  avg place %.2f  wins %d/%d  sidestep frames %d" % [pl["name"], Rivals.tier_name(t), float(places) / n, wins, n, moves])
	for pl in PLAYERS:
		var nm: String = pl["name"]
		if avg[[nm, 0]] > avg[[nm, Rivals.TIERS.size() - 1]]:
			fails += 1
			printerr("FAIL: %s does better against Master than Rookie" % nm)
	if avg[["good", Rivals.TIERS.size() - 1, "win"]] < 0.2:
		fails += 1
		printerr("FAIL: a Gold-level player rarely beats Master rivals")
	if avg[["scrappy", 0, "win"]] < 0.5:
		fails += 1
		printerr("FAIL: a scrappy player rarely beats Rookie rivals")
	printerr("FAILS: ", fails)
	quit(1 if fails else 0)
