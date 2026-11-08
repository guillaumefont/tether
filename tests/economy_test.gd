extends SceneTree
# Coins, Track of the day and awards: medal coins pay the full value once per tier and a
# quarter for repeats; the daily pick depends only on the date, covers every track before
# repeating, never shows a track two days running and brings every variant round; the
# daily pays once (plus the difference for a better medal); buying spends coins, keeps the
# look and refuses when short; a world paint waits for its world; awards pay once; a reset
# empties the wallet and the records.
const Wallet = preload("res://scripts/wallet.gd")
const Daily = preload("res://scripts/daily.gd")
const Awards = preload("res://scripts/awards.gd")
const Cosmetics = preload("res://scripts/cosmetics.gd")
const Records = preload("res://scripts/records.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Times = preload("res://scripts/medal_times.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func expect(got, want, what: String) -> void:
	if got != want:
		fail("%s: got %s, want %s" % [what, str(got), str(want)])

func _init() -> void:
	# medal coins
	expect(Wallet.medal_coins(0, 0), 0, "no medal")
	expect(Wallet.medal_coins(0, 1), 20, "first Bronze")
	expect(Wallet.medal_coins(0, 4), 180, "straight to Pivot")
	expect(Wallet.medal_coins(1, 3), 80, "Bronze to Gold")
	expect(Wallet.medal_coins(3, 3), 12, "Gold again")
	expect(Wallet.medal_coins(4, 2), 8, "Silver run while holding Pivot")
	# daily pick: deterministic, covers every track, no repeats on consecutive days
	var n := Defs.TRACKS.size()
	var d0 := Daily.day_of(2026, 11, 8)
	expect(Daily.day_of(2026, 11, 9) - d0, 1, "days count up")
	expect(Daily.pick(d0), Daily.pick(d0), "same day, same track")
	var seen := {}
	var combos := {}
	var prev := -1
	for k in range(-n * 5, n * 12):
		var p := Daily.pick(d0 + k)
		if p["track"] == prev:
			fail("same track two days running at day %d" % (d0 + k))
		prev = p["track"]
		if not Times.REF.has(p["name"]) or not Times.REF[p["name"]].has(p["variant"]):
			fail("daily %s %s has no medal times" % [p["name"], p["variant"]])
		combos[p["name"] + "/" + p["variant"]] = true
	for k in n:   # one full pass of tracks starting at a pass boundary
		var day := int(floor(float(d0) / n)) * n + k
		seen[Daily.pick(day)["track"]] = true
	expect(seen.size(), n, "every track in one pass")
	expect(combos.size(), n * Defs.VARIANTS.size(), "every track + variant comes round")
	# a clean slate
	Records.reset()
	Wallet.reset()
	expect(Wallet.coins(), 0, "coins after reset")
	# daily pays once, then the difference for a better medal
	expect(Daily.claim(1), Daily.BASE + Daily.PER_TIER, "first daily finish (Bronze)")
	expect(Daily.claim(1), 0, "same medal again today")
	expect(Daily.claim(3), 2 * Daily.PER_TIER, "Gold later the same day")
	expect(Wallet.stat("dailies"), 1, "one daily counted")
	expect(Wallet.coins(), Daily.BASE + 3 * Daily.PER_TIER, "daily coins in the wallet")
	# buying
	var signal_paint := Cosmetics.find("paint", "signal")
	var cost := Cosmetics.price(signal_paint)
	expect(Cosmetics.owned("paint", signal_paint), false, "Signal not owned on a fresh save")
	expect(Cosmetics.buy("paint", Cosmetics.find("paint", "gilded")), "poor", "Gilded too dear")
	Wallet.add(cost)
	var before := Wallet.coins()
	expect(Cosmetics.buy("paint", signal_paint), "ok", "buy Signal")
	expect(Wallet.coins(), before - cost, "Signal paid")
	expect(Cosmetics.owned("paint", signal_paint), true, "Signal owned")
	expect(Cosmetics.equip("paint", "signal"), true, "Signal equips")
	Wallet.add(10000)
	expect(Cosmetics.buy("paint", Cosmetics.find("paint", "moss")), "locked", "Moss waits for the Forest world")
	expect(Cosmetics.buy("paint", Cosmetics.find("paint", "chrome")), "product", "Chrome is a paid pack")
	# awards pay once
	var c0 := Wallet.coins()
	var won := Awards.check({ "mode": "trial", "variant": "obstacles", "finished": true, "clean_laps": 3, "streak": 12, "hits": 0 })
	var ids := won.map(func(a): return a["id"])
	ids.sort()
	expect(ids, ["clean_laps", "no_posts", "streak10"], "awards from one run")
	expect(Wallet.coins() - c0, 150 + 100 + 100, "award coins")
	expect(Awards.check({ "mode": "trial", "variant": "obstacles", "finished": true, "clean_laps": 3, "streak": 12, "hits": 0 }).size(), 0, "awards pay once")
	expect(Awards.check({ "mode": "race", "finished": true, "place": 1, "lead": 4.0 }).size(), 2, "win and runaway")
	for a in Awards.LIST:
		if a["coins"] <= 0 or a["name"] == "" or a["desc"] == "":
			fail("award %s incomplete" % a["id"])
	# reset
	Records.award_medal(Records.key("Lasso", "standard"), "race", 3)
	Records.set_best(Records.key("Lasso", "standard"), 9.0)
	Records.reset()
	Wallet.reset()
	Cosmetics.unequip_all()
	expect(Wallet.coins(), 0, "coins after reset")
	expect(Records.get_medal(Records.key("Lasso", "standard"), "race"), 0, "medals after reset")
	expect(Records.get_best(Records.key("Lasso", "standard")), -1.0, "records after reset")
	expect(Cosmetics.owned("paint", signal_paint), false, "looks after reset")
	expect(Cosmetics.equipped("paint"), "amber", "default paint after reset")
	expect(Wallet.has_award("clean_laps"), false, "awards after reset")
	# the migration of an old save does not hand looks back after a reset
	Cosmetics.migrate()
	expect(Cosmetics.owned("paint", signal_paint), false, "no looks from the old rules after reset")
	# an old save: the looks its medals had opened become owned, the rest stay to buy
	Records.award_medal(Records.key("Lasso", "standard"), "race", 3)
	Wallet.set_v("meta", "migrated", false)
	expect(Cosmetics.owned("paint", signal_paint), true, "old save keeps Signal (2 medals)")
	expect(Cosmetics.owned("livery", Cosmetics.find("livery", "stripes")), true, "old save keeps Twin stripes (3 medals)")
	expect(Cosmetics.owned("paint", Cosmetics.find("paint", "cobalt")), false, "Cobalt (5 medals) still to buy")
	Records.reset()
	Wallet.reset()
	printerr("ECONOMY BAD: %d" % bad)
	quit(1 if bad > 0 else 0)
