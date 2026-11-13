# Car cosmetics: vehicle (one per world), paint (colour + finish), livery (a pattern in an
# accent colour) and rope colour. Visual only: nothing here touches the car's handling, so rankings stay fair.
# Items are bought with coins (scripts/wallet.gd: earned with medals, the Track of the day
# and awards); a world's own paint can only be bought once that campaign world is finished.
# Paid packs are owned through a Store product. The player's picks live in settings.cfg.
extends RefCounted

const Settings = preload("res://scripts/settings.gd")
const Records = preload("res://scripts/records.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Store = preload("res://scripts/store.gd")
const Wallet = preload("res://scripts/wallet.gd")

# finishes: gloss (the default toy-car paint), metallic, matte, pearl, chrome, neon (glows)
# unlock: {} free · {"coins": n} bought for n coins (with "world": c, only once campaign
# world c is finished) · {"product": id} a paid Store pack
const PAINTS := [
	{ "id": "amber", "name": "Amber", "color": Color("#f2b134"), "finish": "gloss", "unlock": {} },
	{ "id": "frost", "name": "Frost", "color": Color("#eef2f5"), "finish": "gloss", "unlock": {} },
	{ "id": "signal", "name": "Signal", "color": Color("#e2402f"), "finish": "gloss", "unlock": { "coins": 150 } },
	{ "id": "cobalt", "name": "Cobalt", "color": Color("#2f6fe0"), "finish": "gloss", "unlock": { "coins": 200 } },
	{ "id": "ember", "name": "Ember", "color": Color("#f07a28"), "finish": "gloss", "unlock": { "coins": 250 } },
	{ "id": "lime", "name": "Lime", "color": Color("#9ad13b"), "finish": "gloss", "unlock": { "coins": 300 } },
	{ "id": "flamingo", "name": "Flamingo", "color": Color("#f06aa8"), "finish": "gloss", "unlock": { "coins": 400 } },
	{ "id": "slate", "name": "Slate", "color": Color("#3c434d"), "finish": "matte", "unlock": { "coins": 500 } },
	{ "id": "dusk", "name": "Dusk", "color": Color("#7d5ce0"), "finish": "metallic", "unlock": { "coins": 700 } },
	{ "id": "glacier", "name": "Glacier", "color": Color("#a9dcf2"), "finish": "pearl", "unlock": { "coins": 400, "world": 0 } },
	{ "id": "moss", "name": "Moss", "color": Color("#4f7a3a"), "finish": "matte", "unlock": { "coins": 400, "world": 1 } },
	{ "id": "dune", "name": "Dune", "color": Color("#d9b27a"), "finish": "pearl", "unlock": { "coins": 400, "world": 2 } },
	{ "id": "basalt", "name": "Basalt", "color": Color("#5a5f66"), "finish": "metallic", "unlock": { "coins": 400, "world": 3 } },
	{ "id": "gilded", "name": "Gilded", "color": Color("#e2b23c"), "finish": "metallic", "unlock": { "coins": 1000 } },
	{ "id": "pivot", "name": "Pivot teal", "color": Color("#5fe0d0"), "finish": "pearl", "unlock": { "coins": 900 } },
	{ "id": "chrome", "name": "Chrome", "color": Color("#d6dce2"), "finish": "chrome", "unlock": { "product": "chrome_pack" } },
	{ "id": "rosegold", "name": "Rose gold", "color": Color("#e8a68c"), "finish": "chrome", "unlock": { "product": "chrome_pack" } },
	{ "id": "blackchrome", "name": "Black chrome", "color": Color("#4a5058"), "finish": "chrome", "unlock": { "product": "chrome_pack" } },
	{ "id": "neonpink", "name": "Neon pink", "color": Color("#ff3fa4"), "finish": "neon", "unlock": { "product": "neon_pack" } },
	{ "id": "neonlime", "name": "Neon lime", "color": Color("#b6ff3a"), "finish": "neon", "unlock": { "product": "neon_pack" } },
	{ "id": "neoncyan", "name": "Neon cyan", "color": Color("#3ff2ff"), "finish": "neon", "unlock": { "product": "neon_pack" } },
]

const LIVERIES := [
	{ "id": "none", "name": "Plain", "unlock": {} },
	{ "id": "stripes", "name": "Twin stripes", "unlock": { "coins": 200 } },
	{ "id": "number", "name": "Race number", "unlock": { "coins": 250 } },
	{ "id": "flash", "name": "Speed lines", "unlock": { "coins": 350 } },
	{ "id": "twotone", "name": "Two-tone", "unlock": { "coins": 450 } },
	{ "id": "checker", "name": "Chequered", "unlock": { "coins": 600 } },
	{ "id": "bolt", "name": "Bolt", "unlock": { "coins": 800 } },
	{ "id": "glow", "name": "Neon trim", "unlock": { "product": "neon_pack" } },
]

const ROPES := [
	{ "id": "car", "name": "Car colour", "color": Color(0, 0, 0, 0), "unlock": {} },
	{ "id": "hemp", "name": "Hemp", "color": Color("#c9a66b"), "unlock": {} },
	{ "id": "white", "name": "Ice white", "color": Color("#f4f8fb"), "unlock": { "coins": 100 } },
	{ "id": "black", "name": "Black", "color": Color("#1e2228"), "unlock": { "coins": 250 } },
	{ "id": "gold", "name": "Gold", "color": Color("#f2c84a"), "unlock": { "coins": 500 } },
	{ "id": "neon", "name": "Neon", "color": Color("#3ff2ff"), "unlock": { "product": "neon_pack" } },
]

# Each world drives its own kind of vehicle (WorldView builds them): three per world, the
# first free and the one the rivals drive. "home" is the world it belongs to; the player
# picks one vehicle per world, and a race uses the pick of the world it is run in.
const BODIES := [
	{ "id": "sled", "name": "Snowmobile", "home": "snow", "unlock": {} },
	{ "id": "snowcat", "name": "Snowcat", "home": "snow", "unlock": { "coins": 600 } },
	{ "id": "van", "name": "Arctic van", "home": "snow", "unlock": { "coins": 900, "world": 0 } },
	{ "id": "pickup", "name": "Pickup", "home": "forest", "unlock": {} },
	{ "id": "jeep", "name": "Open 4x4", "home": "forest", "unlock": { "coins": 600 } },
	{ "id": "hauler", "name": "Timber hauler", "home": "forest", "unlock": { "coins": 900, "world": 1 } },
	{ "id": "buggy", "name": "Buggy", "home": "sand", "unlock": {} },
	{ "id": "rally", "name": "Rally truck", "home": "sand", "unlock": { "coins": 600 } },
	{ "id": "bug", "name": "Beach bug", "home": "sand", "unlock": { "coins": 900, "world": 2 } },
	{ "id": "monster", "name": "Monster truck", "home": "rock", "unlock": {} },
	{ "id": "crawler", "name": "Rock crawler", "home": "rock", "unlock": { "coins": 600 } },
	{ "id": "expedition", "name": "Expedition 6x6", "home": "rock", "unlock": { "coins": 900, "world": 3 } },
]

const SLOTS := { "body": BODIES, "paint": PAINTS, "livery": LIVERIES, "rope": ROPES }

static func items(slot: String) -> Array:
	return SLOTS[slot]

static func find(slot: String, id: String) -> Dictionary:
	for it in SLOTS[slot]:
		if it["id"] == id:
			return it
	return SLOTS[slot][0]

# ---------------------------------------------------------------- owning
# The medal-count rules of earlier builds. Looks a player had opened under them are
# theirs for good: they are marked bought once, the first time this build runs.
const LEGACY := {
	"paint:signal": { "medals": 2 }, "paint:cobalt": { "medals": 5 }, "paint:ember": { "medals": 10 },
	"paint:lime": { "medals": 15 }, "paint:flamingo": { "medals": 25 }, "paint:slate": { "medals": 35 },
	"paint:dusk": { "medals": 50 }, "paint:glacier": { "world": 0 }, "paint:moss": { "world": 1 },
	"paint:dune": { "world": 2 }, "paint:basalt": { "world": 3 }, "paint:gilded": { "golds": 20 },
	"paint:pivot": { "pivots": 10 }, "livery:stripes": { "medals": 3 }, "livery:number": { "medals": 8 },
	"livery:flash": { "medals": 12 }, "livery:twotone": { "medals": 20 }, "livery:checker": { "golds": 10 },
	"livery:bolt": { "pivots": 5 }, "rope:white": { "medals": 6 }, "rope:black": { "medals": 18 },
	"rope:gold": { "golds": 5 },
}

# medal tallies over every track and variant: earning Gold also counts its Bronze and
# Silver, so "medals" is the sum of the best tiers (Time trial and Race kept apart)
static func tally() -> Dictionary:
	var t := { "medals": 0, "golds": 0, "pivots": 0 }
	for d in Defs.TRACKS:
		for v in Defs.VARIANTS:
			for tier in [Campaign.medal(d["name"], v[0], "trial"), Records.get_medal(Records.key(d["name"], v[0]), "race")]:
				t["medals"] += tier
				if tier >= 3: t["golds"] += 1
				if tier >= 4: t["pivots"] += 1
	return t

static func legacy_open(rule: Dictionary, t: Dictionary) -> bool:
	if rule.has("world"):
		return Campaign.chapter_done(rule["world"])
	for k in rule:
		if t.get(k, 0) < rule[k]:
			return false
	return true

# once per save: hand over what the old rules had opened
static func migrate() -> void:
	if Wallet.get_v("meta", "migrated", false):
		return
	var t := tally()
	for k in LEGACY:
		if legacy_open(LEGACY[k], t):
			Wallet.set_owned(k)
	Wallet.set_v("meta", "migrated", true)

static func price(it: Dictionary) -> int:
	return int(it["unlock"].get("coins", 0))

static func owned(slot: String, it: Dictionary) -> bool:
	migrate()
	var u: Dictionary = it["unlock"]
	if u.is_empty():
		return true
	if u.has("product"):
		return Store.owns(u["product"])
	return Wallet.owns(slot + ":" + it["id"])

# a world paint waits for its world; everything else can be bought straight away
static func can_buy_yet(it: Dictionary) -> bool:
	var u: Dictionary = it["unlock"]
	return not u.has("world") or Campaign.chapter_done(u["world"])

# "ok", "owned", "locked" (world not finished), "poor" (not enough coins), "product"
static func buy(slot: String, it: Dictionary) -> String:
	if owned(slot, it):
		return "owned"
	if it["unlock"].has("product"):
		return "product"
	if not can_buy_yet(it):
		return "locked"
	if not Wallet.spend(price(it)):
		return "poor"
	Wallet.set_owned(slot + ":" + it["id"])
	return "ok"

static func requirement(it: Dictionary) -> String:
	var u: Dictionary = it["unlock"]
	if u.is_empty(): return "Free"
	if u.has("product"): return Store.product(u["product"])["name"]
	var txt := "%d coins" % u["coins"]
	if u.has("world"):
		txt = "Finish the %s leg, then %s" % [String(Campaign.CHAPTERS[u["world"]]["theme"]).capitalize(), txt]
	return txt

# ---------------------------------------------------------------- the player's picks
static func equipped(slot: String) -> String:
	if slot == "body":
		return equipped_body(Campaign.menu_theme())
	var id := String(Settings.get_opt("car_" + slot, SLOTS[slot][0]["id"]))
	var it := find(slot, id)
	return it["id"] if owned(slot, it) else SLOTS[slot][0]["id"]

static func equip(slot: String, id: String) -> bool:
	var it := find(slot, id)
	if it["id"] != id or not owned(slot, it):
		return false
	Settings.set_opt("car_body_" + it["home"] if slot == "body" else "car_" + slot, id)
	return true

# whether this item is what the player has on (a vehicle: for its own world)
static func is_equipped(slot: String, it: Dictionary) -> bool:
	if slot == "body":
		return equipped_body(it["home"]) == it["id"]
	return equipped(slot) == it["id"]

# the vehicle picked for a world (its default until another is bought and picked)
static func equipped_body(home: String) -> String:
	var id := String(Settings.get_opt("car_body_" + home, ""))
	var it := find("body", id)
	if it["id"] == id and it["home"] == home and owned("body", it):
		return id
	return default_body(home)

static func default_body(home: String) -> String:
	for it in BODIES:
		if it["home"] == home:
			return it["id"]
	return BODIES[0]["id"]

# world -> picked vehicle, for every world
static func bodies() -> Dictionary:
	var d := {}
	for c in Campaign.CHAPTERS:
		d[c["theme"]] = equipped_body(c["theme"])
	return d

# back to the default look (progress reset)
static func unequip_all() -> void:
	for slot in SLOTS:
		if slot == "body":
			for c in Campaign.CHAPTERS:
				Settings.set_opt("car_body_" + String(c["theme"]), "")
		else:
			Settings.set_opt("car_" + slot, SLOTS[slot][0]["id"])

# the look the 3D view builds: { color, finish, livery, accent, rope, bodies } plus "body"
# when one vehicle is asked for whatever the world (the Garage stage)
static func look(paint_id: String, livery_id: String, rope_id := "car", body_id := "") -> Dictionary:
	var p := find("paint", paint_id)
	var col: Color = p["color"]
	var rope: Color = find("rope", rope_id)["color"]
	var lk := { "color": col, "finish": p["finish"], "livery": livery_id,
		"accent": accent_for(col), "rope": col if rope.a == 0.0 else rope, "bodies": bodies() }
	if body_id != "":
		lk["body"] = body_id
	return lk

static func player_look() -> Dictionary:
	return look(equipped("paint"), equipped("livery"), equipped("rope"))

# liveries are drawn in white on dark paints and in near-black on light ones
static func accent_for(c: Color) -> Color:
	return Color("#1d2229") if c.get_luminance() > 0.62 else Color("#f4f1ea")
