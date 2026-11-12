# The campaign: hand-picked track + variant + mode events in chapters (worlds) of twelve.
# An event unlocks once the one before it has Gold (or Pivot): you need Gold to advance.
# Each chapter is one world (a sub-campaign) dressed in its theme. The first world is open
# from the start; finishing a world (Gold in all its events) opens the next one and
# unlocks its theme for Time Attack, the menu backdrop and the loading screen.
extends RefCounted

const Defs = preload("res://scripts/track_defs.gd")
const Records = preload("res://scripts/records.gd")
const Medals = preload("res://scripts/medals.gd")

const GOLD := 3   # the medal tier that clears an event (Medals.NAMES[GOLD - 1])

# Twelve events per world, easiest first. Every event is a different track + variant + mode,
# so each one is its own medal. Rock is the hardest world: the long, twisting tracks.
const CHAPTERS := [
	{ "name": "First pivots", "theme": "snow", "events": [
		["Lasso", "standard", "trial"], ["Twin Bend", "standard", "race"], ["Big Top", "standard", "trial"],
		["Coil", "standard", "race"], ["Arch", "standard", "trial"], ["Lasso", "standard", "race"],
		["Arch", "obstacles", "trial"], ["Twin Bend", "reverse", "trial"], ["Coil", "reverse", "trial"],
		["Lasso", "reverse", "race"], ["Big Top", "obstacles", "race"], ["Arch", "reverse", "race"]] },
	{ "name": "Over and under", "theme": "forest", "events": [
		["Diamond Eight", "standard", "trial"], ["Trefoil", "standard", "race"], ["Pretzel", "standard", "race"],
		["Three Fingers", "standard", "race"], ["Three Fingers", "collect", "trial"], ["Halo", "standard", "trial"],
		["Coil", "collect", "trial"], ["Sidestep", "standard", "trial"], ["Sidestep", "reverse", "race"],
		["Diamond Eight", "reverse", "trial"], ["Trefoil", "obstacles", "trial"], ["Pretzel", "obstacles", "race"]] },
	{ "name": "Tight knots", "theme": "sand", "events": [
		["Triskel", "standard", "race"], ["Knot", "standard", "race"], ["Fishhook", "standard", "trial"],
		["Big Top", "collect", "trial"], ["Three Fingers", "reverse", "race"], ["Knot", "collect", "trial"],
		["Sidestep", "obstacles", "trial"], ["Squall", "standard", "race"], ["Triskel", "reverse", "trial"],
		["Diamond Eight", "collect", "trial"], ["Twin Bend", "obstacles", "race"], ["Pretzel", "reverse", "race"]] },
	{ "name": "Master line", "theme": "rock", "events": [
		["Knucklebone", "standard", "trial"], ["Starfish", "standard", "race"], ["Halo", "reverse", "race"],
		["Squall", "reverse", "trial"], ["Fishhook", "obstacles", "trial"], ["Knot", "obstacles", "race"],
		["Knucklebone", "reverse", "race"], ["Squall", "collect", "trial"], ["Fishhook", "reverse", "race"],
		["Starfish", "reverse", "trial"], ["Starfish", "collect", "trial"], ["Knucklebone", "collect", "trial"]] },
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
	if mode == "trial":   # the saved tier, or the one the best time reaches
		return maxi(Records.get_medal(k, "trial"), Medals.trial_tier(track_name, variant, Records.get_best(k)))
	return Records.get_medal(k, "race")

static func event_medal(i: int) -> int:
	var e := event(i)
	return medal(e["name"], e["variant"], e["mode"])

# an event is cleared with Gold or better; that opens the next one
static func cleared(i: int) -> bool:
	return event_medal(i) >= GOLD

# the first event of an open world, the event after a Gold, or one already medalled
# (a medal earned before stays playable: worlds grew between builds, and earlier builds
# opened the next event on any medal)
static func unlocked(i: int) -> bool:
	var c := chapter_of(i)
	if i == chapter_start(c):
		return chapter_open(c)
	return cleared(i - 1) or event_medal(i) > 0

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

# events of world c cleared with Gold or better
static func chapter_golds(c: int) -> int:
	var n := 0
	for k in chapter_size(c):
		if cleared(chapter_start(c) + k):
			n += 1
	return n

# Gold in every event. Saved once reached, so a world stays finished (and its theme unlocked)
# if events are added later or the rule gets stricter: worlds finished in earlier builds (six
# events each, any medal was enough) were saved then and stay finished.
static func chapter_done(c: int) -> bool:
	var k := "done_" + String(CHAPTERS[c]["theme"])
	if Records.get_flag("campaign", k):
		return true
	var done := chapter_golds(c) == chapter_size(c)
	if done:
		Records.set_flag("campaign", k)
	return done

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
