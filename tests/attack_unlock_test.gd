# Time attack tracks open with the campaign (Guillaume, 2026-11-13): a track is playable in
# Time attack once a campaign event on it is unlocked. Tracks raced in Time attack before
# the rule came in stay open. The list greys the others with a padlock, and a swipe on the
# event screen skips them.
#   godot --headless --path . --script tests/attack_unlock_test.gd
extends SceneTree

const Records = preload("res://scripts/records.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Defs = preload("res://scripts/track_defs.gd")

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func _names(open: Dictionary) -> Array:
	var out := []
	for t in open:
		out.append(Defs.TRACKS[t]["name"])
	out.sort()
	return out

func _gold(i: int) -> void:
	var e := Campaign.event(i)
	var k := Records.key(e["name"], e["variant"])
	Records.award_medal(k, e["mode"], Campaign.GOLD)

func _init() -> void:
	# every track is in the campaign, so every track can be opened
	for t in Defs.TRACKS.size():
		check(Campaign.first_event_of(t) >= 0, "%s has a campaign event" % Defs.TRACKS[t]["name"])
	check(Campaign.attack_order().size() == Defs.TRACKS.size(), "the Time attack list holds every track once")

	# a fresh player: only the track of the first event is open
	Records.reset()
	var first: String = Campaign.event(0)["name"]
	check(_names(Campaign.attack_tracks()) == [first], "fresh save: only %s is open (%s)" % [first, _names(Campaign.attack_tracks())])
	check(Campaign.attack_order()[0] == Campaign.event(0)["track"], "the first open track tops the list")

	# Gold on event 1 opens event 2, and its track opens in Time attack (not won yet)
	_gold(0)
	var second: int = Campaign.event(1)["track"]
	check(Campaign.attack_open(second), "Gold on event 1 opens %s in Time attack" % Defs.TRACKS[second]["name"])
	var third: int = Campaign.event(2)["track"]
	check(not Campaign.attack_open(third), "%s (event 3) stays shut until event 3 opens" % Defs.TRACKS[third]["name"])

	# a world finished opens the next world's first track
	var forest := Campaign.chapter_start(1)
	var ft: int = Campaign.event(forest)["track"]
	check(not Campaign.attack_open(ft), "%s shut while world 2 is locked" % Defs.TRACKS[ft]["name"])
	Records.set_flag("campaign", "done_" + String(Campaign.CHAPTERS[0]["theme"]))
	check(Campaign.attack_open(ft), "world 1 finished: %s opens" % Defs.TRACKS[ft]["name"])

	# an older save: tracks raced in Time attack before the rule stay open; after that, a time
	# set on a shut track (the Track of the day) does not open it
	Records.reset()
	var old := Records.key("Starfish", "reverse")
	Records.set_best(old, 41.5)
	check(Campaign.attack_open(Campaign.track_index("Starfish")), "old save: Starfish, raced before, stays open")
	Records.set_best(Records.key("Squall", "standard"), 38.0)
	check(not Campaign.attack_open(Campaign.track_index("Squall")), "a time on a shut track later does not open it")
	Records.reset()
	check(_names(Campaign.attack_tracks()) == [first], "progress reset shuts them again")

	# what the player sees: the list greys shut tracks, the swipe skips them
	root.size = Vector2i(1280, 720)
	preload("res://scripts/settings.gd")._load().set_value("options", "tutorial_done", true)
	_gold(0)
	_gold(1)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var menu = main.ui.menu
	main.ui.loading.visible = false
	root.size = Vector2i(1280, 720)
	menu.kind = "attack"
	menu.show_list()
	await frames(3)
	var open := Campaign.attack_tracks()
	var order: Array = menu._track_order()
	var cards: Array = menu._scroller.content.get_child(0).get_children()
	var ok := cards.size() == order.size()
	for p in mini(cards.size(), order.size()):
		if cards[p].disabled == open.has(order[p]):
			ok = false
	check(ok, "list: %d cards, the %d shut ones disabled" % [cards.size(), order.size() - open.size()])
	var shut := order.filter(func(t): return not open.has(t))
	var row_n := func(t): return cards[order.find(t)].get_child(0).get_child_count()
	check(shut.size() > 0 and row_n.call(shut[0]) == row_n.call(order[0]) + 1, "a shut card carries a padlock")
	menu.ev = { "track": order[0], "variant": "standard", "mode": "trial", "humans": 1, "kind": "attack", "idx": order[0], "theme": "snow" }
	menu.show_event()
	await frames(2)
	var seen := [order[0]]
	while menu._can_flip(1):
		menu._flip(1)
		await frames(1)
		seen.append(menu.ev["track"])
	var all_open := seen.all(func(t): return open.has(t))
	check(all_open and seen.size() == open.size(), "event screen: swiping walks the %d open tracks only (%d)" % [open.size(), seen.size()])
	check(not menu._can_flip(-1) or menu._flip_track(-1) >= 0, "no swipe onto a shut track")

	Records.reset()
	print("attack unlock test: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(1 if fails else 0)
