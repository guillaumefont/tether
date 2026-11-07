# Car cosmetics: paint (colour + finish), livery (a pattern in an accent colour) and rope
# colour. Visual only: nothing here touches the car's handling, so rankings stay fair.
# Items unlock with medals (total held, Golds, Pivots), by finishing a campaign world, or
# are owned through a Store product (paid packs). The player's picks live in settings.cfg.
extends RefCounted

const Settings = preload("res://scripts/settings.gd")
const Records = preload("res://scripts/records.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Store = preload("res://scripts/store.gd")

# finishes: gloss (the default toy-car paint), metallic, matte, pearl, chrome, neon (glows)
# unlock: {} free · {"medals": n} medals held · {"golds": n} Gold or better ·
# {"pivots": n} Pivot medals · {"world": c} campaign world c finished · {"product": id} Store
const PAINTS := [
	{ "id": "amber", "name": "Amber", "color": Color("#f2b134"), "finish": "gloss", "unlock": {} },
	{ "id": "frost", "name": "Frost", "color": Color("#eef2f5"), "finish": "gloss", "unlock": {} },
	{ "id": "signal", "name": "Signal", "color": Color("#e2402f"), "finish": "gloss", "unlock": { "medals": 2 } },
	{ "id": "cobalt", "name": "Cobalt", "color": Color("#2f6fe0"), "finish": "gloss", "unlock": { "medals": 5 } },
	{ "id": "ember", "name": "Ember", "color": Color("#f07a28"), "finish": "gloss", "unlock": { "medals": 10 } },
	{ "id": "lime", "name": "Lime", "color": Color("#9ad13b"), "finish": "gloss", "unlock": { "medals": 15 } },
	{ "id": "flamingo", "name": "Flamingo", "color": Color("#f06aa8"), "finish": "gloss", "unlock": { "medals": 25 } },
	{ "id": "slate", "name": "Slate", "color": Color("#3c434d"), "finish": "matte", "unlock": { "medals": 35 } },
	{ "id": "dusk", "name": "Dusk", "color": Color("#7d5ce0"), "finish": "metallic", "unlock": { "medals": 50 } },
	{ "id": "glacier", "name": "Glacier", "color": Color("#a9dcf2"), "finish": "pearl", "unlock": { "world": 0 } },
	{ "id": "moss", "name": "Moss", "color": Color("#4f7a3a"), "finish": "matte", "unlock": { "world": 1 } },
	{ "id": "dune", "name": "Dune", "color": Color("#d9b27a"), "finish": "pearl", "unlock": { "world": 2 } },
	{ "id": "basalt", "name": "Basalt", "color": Color("#5a5f66"), "finish": "metallic", "unlock": { "world": 3 } },
	{ "id": "gilded", "name": "Gilded", "color": Color("#e2b23c"), "finish": "metallic", "unlock": { "golds": 20 } },
	{ "id": "pivot", "name": "Pivot teal", "color": Color("#5fe0d0"), "finish": "pearl", "unlock": { "pivots": 10 } },
	{ "id": "chrome", "name": "Chrome", "color": Color("#d6dce2"), "finish": "chrome", "unlock": { "product": "chrome_pack" } },
	{ "id": "rosegold", "name": "Rose gold", "color": Color("#e8a68c"), "finish": "chrome", "unlock": { "product": "chrome_pack" } },
	{ "id": "blackchrome", "name": "Black chrome", "color": Color("#4a5058"), "finish": "chrome", "unlock": { "product": "chrome_pack" } },
	{ "id": "neonpink", "name": "Neon pink", "color": Color("#ff3fa4"), "finish": "neon", "unlock": { "product": "neon_pack" } },
	{ "id": "neonlime", "name": "Neon lime", "color": Color("#b6ff3a"), "finish": "neon", "unlock": { "product": "neon_pack" } },
	{ "id": "neoncyan", "name": "Neon cyan", "color": Color("#3ff2ff"), "finish": "neon", "unlock": { "product": "neon_pack" } },
]

const LIVERIES := [
	{ "id": "none", "name": "Plain", "unlock": {} },
	{ "id": "stripes", "name": "Twin stripes", "unlock": { "medals": 3 } },
	{ "id": "number", "name": "Race number", "unlock": { "medals": 8 } },
	{ "id": "flash", "name": "Speed lines", "unlock": { "medals": 12 } },
	{ "id": "twotone", "name": "Two-tone", "unlock": { "medals": 20 } },
	{ "id": "checker", "name": "Chequered", "unlock": { "golds": 10 } },
	{ "id": "bolt", "name": "Bolt", "unlock": { "pivots": 5 } },
	{ "id": "glow", "name": "Neon trim", "unlock": { "product": "neon_pack" } },
]

const ROPES := [
	{ "id": "car", "name": "Car colour", "color": Color(0, 0, 0, 0), "unlock": {} },
	{ "id": "hemp", "name": "Hemp", "color": Color("#c9a66b"), "unlock": {} },
	{ "id": "white", "name": "Ice white", "color": Color("#f4f8fb"), "unlock": { "medals": 6 } },
	{ "id": "black", "name": "Black", "color": Color("#1e2228"), "unlock": { "medals": 18 } },
	{ "id": "gold", "name": "Gold", "color": Color("#f2c84a"), "unlock": { "golds": 5 } },
	{ "id": "neon", "name": "Neon", "color": Color("#3ff2ff"), "unlock": { "product": "neon_pack" } },
]

const SLOTS := { "paint": PAINTS, "livery": LIVERIES, "rope": ROPES }

static func items(slot: String) -> Array:
	return SLOTS[slot]

static func find(slot: String, id: String) -> Dictionary:
	for it in SLOTS[slot]:
		if it["id"] == id:
			return it
	return SLOTS[slot][0]

# ---------------------------------------------------------------- progress
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

static func unlocked(it: Dictionary, t = null) -> bool:
	var u: Dictionary = it["unlock"]
	if u.is_empty():
		return true
	if u.has("product"):
		return Store.owns(u["product"])
	if u.has("world"):
		return Campaign.chapter_done(u["world"])
	if t == null:
		t = tally()
	for k in ["medals", "golds", "pivots"]:
		if u.has(k) and t[k] < u[k]:
			return false
	return true

# how far along the unlock is: [have, need] (need 0 = no counter, e.g. a paid item)
static func progress(it: Dictionary, t: Dictionary) -> Array:
	var u: Dictionary = it["unlock"]
	for k in ["medals", "golds", "pivots"]:
		if u.has(k):
			return [mini(t[k], u[k]), u[k]]
	if u.has("world"):
		var c: int = u["world"]
		return [Campaign.chapter_medals(c), Campaign.chapter_size(c)]
	return [0, 0]

static func requirement(it: Dictionary) -> String:
	var u: Dictionary = it["unlock"]
	if u.is_empty(): return "Free"
	if u.has("medals"): return "%d medals" % u["medals"]
	if u.has("golds"): return "%d Gold medals" % u["golds"]
	if u.has("pivots"): return "%d Pivot medals" % u["pivots"]
	if u.has("world"): return "Finish the %s world" % String(Campaign.CHAPTERS[u["world"]]["theme"]).capitalize()
	if u.has("product"): return Store.product(u["product"])["name"]
	return ""

# every item open right now, as "slot:id" (to spot what a race just unlocked)
static func open_ids() -> Array:
	var t := tally()
	var out: Array = []
	for slot in SLOTS:
		for it in SLOTS[slot]:
			if unlocked(it, t):
				out.append(slot + ":" + it["id"])
	return out

# "Signal paint, Twin stripes livery" for the ids in `now` but not in `before`
static func new_names(before: Array, now: Array) -> String:
	var names: Array = []
	for k in now:
		if not before.has(k):
			var p: PackedStringArray = k.split(":")
			names.append("%s %s" % [find(p[0], p[1])["name"], p[0]])
	return ", ".join(names)

# ---------------------------------------------------------------- the player's picks
static func equipped(slot: String) -> String:
	var id := String(Settings.get_opt("car_" + slot, SLOTS[slot][0]["id"]))
	var it := find(slot, id)
	return it["id"] if unlocked(it) else SLOTS[slot][0]["id"]

static func equip(slot: String, id: String) -> bool:
	if not unlocked(find(slot, id)):
		return false
	Settings.set_opt("car_" + slot, id)
	return true

# the look the 3D view builds: { color, finish, livery, accent, rope }
static func look(paint_id: String, livery_id: String, rope_id := "car") -> Dictionary:
	var p := find("paint", paint_id)
	var col: Color = p["color"]
	var rope: Color = find("rope", rope_id)["color"]
	return { "color": col, "finish": p["finish"], "livery": livery_id,
		"accent": accent_for(col), "rope": col if rope.a == 0.0 else rope }

static func player_look() -> Dictionary:
	return look(equipped("paint"), equipped("livery"), equipped("rope"))

# liveries are drawn in white on dark paints and in near-black on light ones
static func accent_for(c: Color) -> Color:
	return Color("#1d2229") if c.get_luminance() > 0.62 else Color("#f4f1ea")
