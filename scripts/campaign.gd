# The campaign: hand-picked track + variant + mode events in chapters of six.
# An event unlocks once the one before it has at least a Bronze medal.
# Each chapter is one world: its events are dressed in the chapter's theme.
extends RefCounted

const Defs = preload("res://scripts/track_defs.gd")
const Records = preload("res://scripts/records.gd")
const Medals = preload("res://scripts/medals.gd")

const CHAPTERS := [
	{ "name": "First pivots", "theme": "forest", "events": [
		["Lasso", "standard", "trial"], ["Twin Bend", "standard", "race"], ["Big Top", "standard", "trial"],
		["Coil", "standard", "race"], ["Arch", "obstacles", "trial"], ["Lasso", "reverse", "race"]] },
	{ "name": "Over and under", "theme": "sand", "events": [
		["Diamond Eight", "standard", "trial"], ["Pretzel", "standard", "race"], ["Three Fingers", "collect", "trial"],
		["Halo", "standard", "trial"], ["Sidestep", "reverse", "race"], ["Trefoil", "obstacles", "trial"]] },
	{ "name": "Tight knots", "theme": "rock", "events": [
		["Triskel", "standard", "race"], ["Fishhook", "standard", "trial"], ["Knot", "collect", "trial"],
		["Squall", "standard", "race"], ["Big Top", "collect", "trial"], ["Twin Bend", "obstacles", "race"]] },
	{ "name": "Master line", "theme": "snow", "events": [
		["Knucklebone", "standard", "trial"], ["Starfish", "standard", "race"], ["Halo", "reverse", "race"],
		["Fishhook", "obstacles", "trial"], ["Squall", "collect", "trial"], ["Starfish", "reverse", "trial"]] },
]

static func count() -> int:
	var n := 0
	for ch in CHAPTERS:
		n += ch["events"].size()
	return n

# event i (0-based across chapters) -> { track, variant, mode, chapter, idx }
static func event(i: int) -> Dictionary:
	var k := i
	for c in CHAPTERS.size():
		var evs: Array = CHAPTERS[c]["events"]
		if k < evs.size():
			var e: Array = evs[k]
			return { "track": track_index(e[0]), "name": e[0], "variant": e[1], "mode": e[2], "chapter": c, "idx": i, "theme": CHAPTERS[c]["theme"] }
		k -= evs.size()
	return {}

static func track_index(name: String) -> int:
	for i in Defs.TRACKS.size():
		if Defs.TRACKS[i]["name"] == name:
			return i
	return -1

static func medal(track_name: String, variant: String, mode: String) -> int:
	var k := Records.key(track_name, variant)
	if mode == "trial":
		return Medals.trial_tier(track_name, variant, Records.get_best(k))
	return Records.get_medal(k, "race")

static func event_medal(i: int) -> int:
	var e := event(i)
	return medal(e["name"], e["variant"], e["mode"])

static func unlocked(i: int) -> bool:
	return i == 0 or event_medal(i - 1) > 0

static func total_medals() -> int:
	var n := 0
	for i in count():
		n += event_medal(i)
	return n
