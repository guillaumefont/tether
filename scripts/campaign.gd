# The campaign: hand-picked track + variant + mode events in chapters of six.
# An event unlocks once the one before it has at least a Bronze medal.
# Each chapter is one world (a sub-campaign) dressed in its theme. The first world is open
# from the start; finishing a world (a medal in all its events) opens the next one and
# unlocks its theme for Time Attack, the menu backdrop and the loading screen.
extends RefCounted

const Defs = preload("res://scripts/track_defs.gd")
const Records = preload("res://scripts/records.gd")
const Medals = preload("res://scripts/medals.gd")

const CHAPTERS := [
	{ "name": "First pivots", "theme": "snow", "events": [
		["Lasso", "standard", "trial"], ["Twin Bend", "standard", "race"], ["Big Top", "standard", "trial"],
		["Coil", "standard", "race"], ["Arch", "obstacles", "trial"], ["Lasso", "reverse", "race"]] },
	{ "name": "Over and under", "theme": "forest", "events": [
		["Diamond Eight", "standard", "trial"], ["Pretzel", "standard", "race"], ["Three Fingers", "collect", "trial"],
		["Halo", "standard", "trial"], ["Sidestep", "reverse", "race"], ["Trefoil", "obstacles", "trial"]] },
	{ "name": "Tight knots", "theme": "sand", "events": [
		["Triskel", "standard", "race"], ["Fishhook", "standard", "trial"], ["Knot", "collect", "trial"],
		["Squall", "standard", "race"], ["Big Top", "collect", "trial"], ["Twin Bend", "obstacles", "race"]] },
	{ "name": "Master line", "theme": "rock", "events": [
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

# ---------------------------------------------------------------- worlds
static func chapter_start(c: int) -> int:
	var n := 0
	for k in c:
		n += CHAPTERS[k]["events"].size()
	return n

static func chapter_size(c: int) -> int:
	return CHAPTERS[c]["events"].size()

static func chapter_of(i: int) -> int:
	for c in CHAPTERS.size():
		if i < chapter_start(c) + chapter_size(c):
			return c
	return CHAPTERS.size() - 1

static func chapter_medals(c: int) -> int:
	var n := 0
	for k in chapter_size(c):
		if event_medal(chapter_start(c) + k) > 0:
			n += 1
	return n

static func chapter_done(c: int) -> bool:
	return chapter_medals(c) == chapter_size(c)

static func chapter_open(c: int) -> bool:
	return c == 0 or chapter_done(c - 1)

static func theme_unlocked(theme: String) -> bool:
	for c in CHAPTERS.size():
		if CHAPTERS[c]["theme"] == theme:
			return c == 0 or chapter_done(c)
	return false

# the theme of the furthest finished world (the first world before that): the menu
# backdrop and the loading screen wear it
static func menu_theme() -> String:
	var t: String = CHAPTERS[0]["theme"]
	for c in CHAPTERS.size():
		if chapter_done(c):
			t = CHAPTERS[c]["theme"]
	return t

# a track outside the campaign wears its home theme once that theme is unlocked
static func track_theme(track_i: int) -> String:
	var home := String(Defs.TRACKS[track_i].get("theme", "snow"))
	return home if theme_unlocked(home) else menu_theme()
