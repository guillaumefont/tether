# AI rivals: difficulty tiers and the three named drivers' styles.
# A tier sets how fast and how tidy the rivals are; each driver then adds a personality on
# top. Campaign races take the tier of their world (snow = Rookie ... rock = Master).
extends RefCounted

# pace: speed-cap multiplier for the lead rival (the others sit a little below it)
# aim: scales the random hook timing error (1.0 = the reference driver's error)
# blunder: chance per bend of hooking far too late (a wide, scruffy line, maybe a wall)
# block: how much the rivals drift across to cover a player right behind them (0 = never)
const TIERS := [
	{ "name": "Rookie", "pace": 0.93, "aim": 1.6, "blunder": 0.10, "block": 0.0 },
	{ "name": "Club", "pace": 0.955, "aim": 1.25, "blunder": 0.05, "block": 0.45 },
	{ "name": "Pro", "pace": 0.975, "aim": 1.0, "blunder": 0.025, "block": 0.75 },
	{ "name": "Master", "pace": 0.99, "aim": 0.75, "blunder": 0.01, "block": 1.0 },
]

# per driver (by roster name): pace offset from the tier, and multipliers on the tier's
# aim error, blunders and blocking
const STYLES := {
	"Vesna": { "pace": 0.0, "aim": 0.85, "blunder": 0.7, "block": 0.6 },    # clean, quick, fair
	"Okoro": { "pace": -0.02, "aim": 1.1, "blunder": 1.2, "block": 1.6 },   # scrappy, shuts the door
	"Brandt": { "pace": -0.04, "aim": 1.0, "blunder": 0.5, "block": 1.0 },  # steady, rarely errs
}

const VERSUS_TIER := 1
const ATTRACT_TIER := 2

# the tier rivals race at in a campaign event of chapter c (one tier per world)
static func campaign_tier(chapter: int) -> int:
	return clampi(chapter, 0, TIERS.size() - 1)

static func tier_name(t: int) -> String:
	return TIERS[clampi(t, 0, TIERS.size() - 1)]["name"]

# fills a car's driving traits for tier t
static func apply(c, t: int) -> void:
	var tier: Dictionary = TIERS[clampi(t, 0, TIERS.size() - 1)]
	var st: Dictionary = STYLES.get(c.name, { "pace": 0.0, "aim": 1.0, "blunder": 1.0, "block": 1.0 })
	c.skill = tier["pace"] + st["pace"]
	c.aim = tier["aim"] * st["aim"]
	c.blunder = tier["blunder"] * st["blunder"]
	c.block = tier["block"] * st["block"]
