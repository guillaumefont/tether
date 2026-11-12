extends SceneTree
# Coins, Track of the day and awards: medal coins pay the full value once per tier and a
# quarter for repeats; the daily pick depends only on the date, covers every track before
# repeating, never shows a track two days running and brings every variant round; the
# daily pays once (plus the difference for a better medal); buying spends coins, keeps the
# look and refuses when short; a world paint waits for its world; awards are collected once; a reset
# empties the wallet and the records.
const Wallet = preload("res://scripts/wallet.gd")
const Daily = preload("res://scripts/daily.gd")
const Awards = preload("res://scripts/awards.gd")
const Cosmetics = preload("res://scripts/cosmetics.gd")
const Records = preload("res://scripts/records.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Times = preload("res://scripts/medal_times.gd")
const Medals = preload("res://scripts/medals.gd")
const Campaign = preload("res://scripts/campaign.gd")

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
	expect(Wallet.coins() - c0, 0, "awards wait to be collected")
	expect(Awards.ready_count(), 3, "three awards to collect")
	expect(Awards.claim("clean_laps") + Awards.claim("no_posts") + Awards.claim("streak10"), 150 + 100 + 100, "collected coins")
	expect(Awards.claim("clean_laps"), 0, "collected once")
	expect(Wallet.coins() - c0, 150 + 100 + 100, "award coins")
	expect(Awards.ready_count(), 0, "nothing left to collect")
	expect(Awards.check({ "mode": "trial", "variant": "obstacles", "finished": true, "clean_laps": 3, "streak": 12, "hits": 0 }).size(), 0, "awards pay once")
	expect(Awards.check({ "mode": "race", "finished": true, "place": 1, "lead": 4.0 }).size(), 2, "win and runaway")
	for a in Awards.LIST:
		if a["coins"] <= 0 or a["name"] == "" or a["desc"] == "":
			fail("award %s incomplete" % a["id"])
	# a layout bump drops the times but keeps the Time trial medals they earned
	var lk := Records.key("Lasso", "standard")
	var old := ConfigFile.new()
	old.set_value(Records.META, "layouts", Records.LAYOUT_VERSION - 1)
	old.set_value(lk, "best", Medals.targets("Lasso", "standard")[2])   # a Gold lap
	old.set_value(lk, "medal_race", 2)
	old.save(Records.PATH)
	Records._cfg = null
	expect(Records.get_best(lk), -1.0, "old layout time dropped")
	expect(Records.get_medal(lk, "trial"), 3, "old layout Gold kept")
	expect(Campaign.medal("Lasso", "standard", "trial"), 3, "campaign sees the kept Gold")
	expect(Records.get_medal(lk, "race"), 2, "race medal kept")
	# a slower lap on the new layout never takes a medal away
	Records.set_best(lk, 99.0)
	expect(Campaign.medal("Lasso", "standard", "trial"), 3, "medal outlives a slower time")
	# reset
	Records.award_medal(Records.key("Lasso", "standard"), "race", 3)
	Records.set_best(Records.key("Lasso", "standard"), 9.0)
	Records.reset()
	Wallet.reset()
	Cosmetics.unequip_all()
	expect(Wallet.coins(), 0, "coins after reset")
	expect(Records.get_medal(Records.key("Lasso", "standard"), "race"), 0, "medals after reset")
	expect(Records.get_medal(Records.key("Lasso", "standard"), "trial"), 0, "trial medals after reset")
	expect(Records.get_best(Records.key("Lasso", "standard")), -1.0, "records after reset")
	expect(Cosmetics.owned("paint", signal_paint), false, "looks after reset")
	expect(Cosmetics.equipped("paint"), "amber", "default paint after reset")
	expect(Wallet.has_award("clean_laps"), false, "awards after reset")
	expect(Awards.claimed("clean_laps"), false, "collected awards after reset")
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
	_campaign_gold()
	Records.reset()
	Wallet.reset()
	printerr("ECONOMY BAD: %d" % bad)
	quit(1 if bad > 0 else 0)

# give campaign event i medal tier `tier`, the way playing it would
func _medal_event(i: int, tier: int) -> void:
	var e := Campaign.event(i)
	var k := Records.key(e["name"], e["variant"])
	if e["mode"] == "trial":
		Records.set_best(k, Medals.targets(e["name"], e["variant"])[tier - 1])
	else:
		Records.award_medal(k, "race", tier)

# Gold opens the next event and finishes a world; an older save keeps what it had
func _campaign_gold() -> void:
	Records.reset()
	var s1 := Campaign.chapter_start(1)
	expect(Campaign.unlocked(0), true, "first event open")
	expect(Campaign.unlocked(1), false, "second event shut at start")
	_medal_event(0, 2)
	expect(Campaign.unlocked(1), false, "Silver does not open the next event")
	_medal_event(0, 3)
	expect(Campaign.unlocked(1), true, "Gold opens the next event")
	expect(Campaign.cleared(0), true, "Gold clears the event")
	for i in range(1, s1):
		_medal_event(i, 3 if i < s1 - 1 else 2)
	expect(Campaign.chapter_done(0), false, "a world with a Silver is not finished")
	expect(Campaign.chapter_open(1), false, "next world shut until the last Gold")
	_medal_event(s1 - 1, 4)
	expect(Campaign.chapter_done(0), true, "Gold (or Pivot) everywhere finishes the world")
	expect(Campaign.chapter_open(1), true, "and opens the next one")
	# an old save, from when any medal opened the next event: Bronze on events 0..2
	Records.reset()
	for i in 3:
		_medal_event(i, 1)
	expect(Campaign.unlocked(2), true, "an event already medalled stays playable")
	expect(Campaign.unlocked(3), false, "the next one waits for Gold")
	# a world finished under the old rule stays finished
	Records.set_flag("campaign", "done_" + String(Campaign.CHAPTERS[0]["theme"]))
	expect(Campaign.chapter_open(1), true, "a world saved as finished keeps the next one open")
