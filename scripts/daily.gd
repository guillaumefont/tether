# Track of the day: one track + variant in Time trial, picked from the local date alone
# (no server, works offline: everyone on the same day gets the same track). Tracks come in
# a shuffled order that covers all of them before any comes back, never the same track two
# days running; each pass round the tracks moves every track on to its next variant, so
# every track + variant shows up once every 17 x 4 days.
# Finishing it pays coins once a day, plus more per medal tier (an improvement later the
# same day pays the difference).
extends RefCounted

const Defs = preload("res://scripts/track_defs.gd")
const Wallet = preload("res://scripts/wallet.gd")

const BASE := 40       # coins for finishing it
const PER_TIER := 30   # and for each medal tier of the run

# days since 1970-01-01 in the player's own time zone
static func today() -> int:
	var d := Time.get_date_dict_from_system()
	return day_of(int(d["year"]), int(d["month"]), int(d["day"]))

static func day_of(y: int, m: int, d: int) -> int:
	var t := Time.get_unix_time_from_datetime_dict({ "year": y, "month": m, "day": d, "hour": 12, "minute": 0, "second": 0 })
	return int(floor(t / 86400.0))

# a small deterministic generator (same numbers on every device and build)
static func _next(s: int) -> int:
	return (s * 1103515245 + 12345) % 2147483648

static func _order(cycle: int) -> Array:
	var n := Defs.TRACKS.size()
	var o: Array = range(n)
	var s := posmod(cycle * 7919 + 104729, 2147483648)
	for i in range(n - 1, 0, -1):
		s = _next(s)
		var j := (s >> 16) % (i + 1)
		var tmp = o[i]; o[i] = o[j]; o[j] = tmp
	return o

# { track, name, variant } for a day
static func pick(day: int) -> Dictionary:
	var n := Defs.TRACKS.size()
	var cycle := int(floor(float(day) / n))
	var pos := day - cycle * n
	var o := _order(cycle)
	# the first day of a pass never repeats the last day of the one before
	if o[0] == _order(cycle - 1)[n - 1]:
		var tmp = o[0]; o[0] = o[1]; o[1] = tmp
	var t: int = o[pos]
	var v: String = Defs.VARIANTS[posmod(cycle + t, Defs.VARIANTS.size())][0]
	return { "track": t, "name": Defs.TRACKS[t]["name"], "variant": v }

static func current() -> Dictionary:
	return pick(today())

static func is_today(track_i: int, variant: String) -> bool:
	var p := current()
	return p["track"] == track_i and p["variant"] == variant

# the best medal tier already paid today (-1: not finished today)
static func paid_tier() -> int:
	if int(Wallet.get_v("daily", "day", -999999)) != today():
		return -1
	return int(Wallet.get_v("daily", "tier", -1))

# coins a finished run on today's track pays, given what today already paid
static func coins_for(paid: int, run_tier: int) -> int:
	if paid < 0:
		return BASE + PER_TIER * run_tier
	return PER_TIER * maxi(0, run_tier - paid)

# a finished run on today's track: pay it and remember it; returns the coins paid
static func claim(run_tier: int) -> int:
	var paid := paid_tier()
	var n := coins_for(paid, run_tier)
	if paid < 0:
		Wallet.bump("dailies")
	if paid < 0 or run_tier > paid:
		Wallet.set_v("daily", "day", today())
		Wallet.set_v("daily", "tier", maxi(run_tier, paid))
	Wallet.add(n)
	return n
