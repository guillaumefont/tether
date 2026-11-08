# Awards: one-off goals that pay coins once. Some are about a single run (three clean laps,
# every gem), others about the player's whole progress (ten Gold medals, a world finished).
# Checked when a one-player run ends; earned ones are kept in the wallet.
extends RefCounted

const Wallet = preload("res://scripts/wallet.gd")
const Records = preload("res://scripts/records.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Defs = preload("res://scripts/track_defs.gd")

const LIST := [
	{ "id": "clean_laps", "name": "Clean triple", "desc": "Three clean laps in a row: no rail, no post", "coins": 150 },
	{ "id": "streak10", "name": "Smooth operator", "desc": "Ten clean bends in a row", "coins": 100 },
	{ "id": "streak25", "name": "Flawless", "desc": "Twenty-five clean bends in a row", "coins": 250 },
	{ "id": "no_posts", "name": "Untouchable", "desc": "Finish an Obstacles run without hitting a post", "coins": 100 },
	{ "id": "all_gems", "name": "Full basket", "desc": "Pick up every gem in a Collect run", "coins": 150 },
	{ "id": "first_win", "name": "First win", "desc": "Win a race", "coins": 50 },
	{ "id": "runaway", "name": "Runaway", "desc": "Win a race by 3 seconds or more", "coins": 150 },
	{ "id": "first_pivot", "name": "Pivot!", "desc": "Earn your first Pivot medal", "coins": 200 },
	{ "id": "golds10", "name": "Gold standard", "desc": "Hold 10 Gold medals or better", "coins": 250 },
	{ "id": "every_track", "name": "Globetrotter", "desc": "A medal on every track", "coins": 400 },
	{ "id": "world_snow", "name": "Snow champion", "desc": "Finish the Snow world", "coins": 200 },
	{ "id": "world_forest", "name": "Forest champion", "desc": "Finish the Forest world", "coins": 300 },
	{ "id": "world_sand", "name": "Sand champion", "desc": "Finish the Sand world", "coins": 400 },
	{ "id": "world_rock", "name": "Rock champion", "desc": "Finish the Rock world", "coins": 500 },
	{ "id": "dailies7", "name": "Daily driver", "desc": "Finish seven Tracks of the day", "coins": 300 },
	{ "id": "records25", "name": "Record breaker", "desc": "Set 25 new records", "coins": 150 },
]

static func find(id: String) -> Dictionary:
	for a in LIST:
		if a["id"] == id:
			return a
	return {}

static func earned_count() -> int:
	return LIST.filter(func(a): return Wallet.has_award(a["id"])).size()

# medals held over every track and variant (Time trial and Race): per-tier counts and
# whether each track has any medal at all
static func _medal_state() -> Dictionary:
	var st := { "golds": 0, "pivots": 0, "tracks": 0 }
	for d in Defs.TRACKS:
		var any := false
		for v in Defs.VARIANTS:
			for tier in [Campaign.medal(d["name"], v[0], "trial"), Records.get_medal(Records.key(d["name"], v[0]), "race")]:
				if tier >= 3: st["golds"] += 1
				if tier >= 4: st["pivots"] += 1
				if tier > 0: any = true
		if any:
			st["tracks"] += 1
	return st

# which awards a run (and the progress it left behind) reaches. `run` holds:
# mode, variant, finished, clean_laps (most clean laps in a row), streak (most clean bends
# in a row), hits (posts), gems_all, place (race), lead (seconds ahead of 2nd)
static func reached(run: Dictionary) -> Array:
	var ids: Array = []
	if run.get("clean_laps", 0) >= 3: ids.append("clean_laps")
	if run.get("streak", 0) >= 10: ids.append("streak10")
	if run.get("streak", 0) >= 25: ids.append("streak25")
	if run.get("finished", false):
		if run.get("variant", "") == "obstacles" and run.get("hits", 1) == 0: ids.append("no_posts")
		if run.get("variant", "") == "collect" and run.get("gems_all", false): ids.append("all_gems")
		if run.get("mode", "") == "race" and run.get("place", 0) == 1:
			ids.append("first_win")
			if run.get("lead", 0.0) >= 3.0: ids.append("runaway")
	var st := _medal_state()
	if st["pivots"] >= 1: ids.append("first_pivot")
	if st["golds"] >= 10: ids.append("golds10")
	if st["tracks"] >= Defs.TRACKS.size(): ids.append("every_track")
	for c in Campaign.CHAPTERS.size():
		if Campaign.chapter_done(c): ids.append("world_" + String(Campaign.CHAPTERS[c]["theme"]))
	if Wallet.stat("dailies") >= 7: ids.append("dailies7")
	if Wallet.stat("records") >= 25: ids.append("records25")
	return ids

# pay every award the run reached for the first time; returns those awards
static func check(run: Dictionary) -> Array:
	var out: Array = []
	for id in reached(run):
		if Wallet.has_award(id):
			continue
		var a := find(id)
		Wallet.set_award(id)
		Wallet.add(a["coins"])
		out.append(a)
	return out
