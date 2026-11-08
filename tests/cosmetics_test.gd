extends SceneTree
# Garage items: every item is free, priced in coins (maybe behind a campaign world) or in a
# real Store product; ids are unique; every old medal rule has an item; every look builds a
# car on every theme kit; cosmetics never reach the race sim (a painted car laps in the same time).
const Cosmetics = preload("res://scripts/cosmetics.gd")
const Store = preload("res://scripts/store.gd")
const WorldView = preload("res://scripts/world_view.gd")
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func _init() -> void:
	for slot in Cosmetics.SLOTS:
		var ids := {}
		var items: Array = Cosmetics.items(slot)
		if not items[0]["unlock"].is_empty():
			fail("%s: the first (default) item must be free" % slot)
		for it in items:
			if ids.has(it["id"]):
				fail("%s: duplicate id %s" % [slot, it["id"]])
			ids[it["id"]] = true
			var u: Dictionary = it["unlock"]
			for k in u:
				if not k in ["coins", "world", "product"]:
					fail("%s %s: unknown unlock rule %s" % [slot, it["id"], k])
			if u.has("product") and not Store.PRODUCTS.has(u["product"]):
				fail("%s %s: no Store product %s" % [slot, it["id"], u["product"]])
			if u.has("world") and not u.has("coins"):
				fail("%s %s: a world item needs a coin price too" % [slot, it["id"]])
			if u.has("coins") and int(u["coins"]) <= 0:
				fail("%s %s: a priced item must cost something" % [slot, it["id"]])
			if not u.is_empty() and not u.has("coins") and not u.has("product"):
				fail("%s %s: neither free, priced nor paid" % [slot, it["id"]])
			if Cosmetics.requirement(it) == "":
				fail("%s %s: no requirement text" % [slot, it["id"]])
	for k in Cosmetics.LEGACY:
		var p: PackedStringArray = k.split(":")
		if Cosmetics.find(p[0], p[1])["id"] != p[1]:
			fail("old unlock rule %s has no item" % k)
	# every paint x livery builds on every theme kit
	var view := WorldView.new()
	for theme in ["snow", "forest", "sand", "rock"]:
		view.th = preload("res://scripts/themes.gd").get_theme(theme)
		for p in Cosmetics.PAINTS:
			for l in Cosmetics.LIVERIES:
				var lk := Cosmetics.look(p["id"], l["id"], "hemp")
				var car: Node3D = view._make_car(lk["color"], false, lk)
				if car.get_meta("body").get_child_count() < 5:
					fail("%s %s on %s: car has no body" % [p["id"], l["id"], theme])
				car.free()
	view.free()
	# a painted car is the same car: the race plays out the same whatever the paint
	var times := []
	for colour in [Color("#f2b134"), Color("#ff3fa4")]:
		seed(7)
		var tr := TrackData.new(Defs.TRACKS[1], "standard")
		var race := Race.new(tr, "race", 0)
		race.cars[0].color = colour
		for k in 60 * 40:
			race.update(1.0 / 60.0)
			race.events.clear()
			Race.spin_anchors(tr, 1.0 / 60.0)
		times.append([race.cars[0].pos, race.cars[0].prog])
	if times[0] != times[1]:
		fail("the car's colour changed the race: %s" % str(times))
	printerr("COSMETICS BAD: %d" % bad)
	quit(1 if bad > 0 else 0)
