# Menus: the track / event list scrolls with a drag (and glides after a flick), the event
# screen flips track with a sideways swipe, a short tap still opens a card, and a drag that
# starts on a card never opens it.
#   godot --headless --path . --script tests/swipe_test.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	root.push_input(e, true)

func motion(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e, true)

func drag(from: Vector2, delta: Vector2, steps := 8, settle := 0.5) -> void:
	mouse(from, true)
	await frames(1)
	var p := from
	for k in steps:
		var q := from + delta * (k + 1) / steps
		motion(q, q - p)
		p = q
		await frames(1)
	mouse(p, false)
	await create_timer(settle).timeout   # slide / glide
	await frames(2)

func tap(pos: Vector2) -> void:
	mouse(pos, true)
	await frames(1)
	mouse(pos, false)
	await frames(3)

func _init() -> void:
	root.size = Vector2i(1280, 720)
	# a fresh install would open on the tutorial: start on the menu (in memory, not saved)
	preload("res://scripts/settings.gd")._load().set_value("options", "tutorial_done", true)
	# every Time attack track open, as for a player who has raced them all (in memory, not saved)
	var rec: ConfigFile = preload("res://scripts/records.gd")._load()
	rec.set_value("campaign", "attack_gate", true)
	for d in preload("res://scripts/track_defs.gd").TRACKS:
		rec.set_value("attack", d["name"], true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var menu = main.ui.menu
	main.ui.loading.visible = false
	root.size = Vector2i(1280, 720)   # headless starts with a tiny window
	await frames(3)
	var mid := Vector2(root.get_visible_rect().size) * Vector2(0.5, 0.55)

	# the track list: one long list, dragged up and down
	menu.kind = "attack"
	menu._list_scroll.clear()
	menu.show_list()
	await frames(3)
	check(menu._scroller.max_scroll() > 100.0, "all %d tracks in one list taller than the screen" % menu._scroller.content.get_child(0).get_child_count())
	await drag(mid, Vector2(0, -200), 8, 0.1)
	check(menu.screen == "list" and menu._scroller.scroll > 150.0, "drag up scrolls the list (%.0f), opens nothing" % menu._scroller.scroll)
	await create_timer(1.5).timeout
	var y0: float = menu._scroller.scroll
	await drag(mid, Vector2(0, 90), 3, 0.05)   # a short quick flick back down
	await create_timer(0.6).timeout
	check(menu.screen == "list" and menu._scroller.scroll < y0 - 150.0, "a flick keeps gliding, opens nothing (%.0f -> %.0f)" % [y0, menu._scroller.scroll])
	await create_timer(2.5).timeout
	await drag(mid, Vector2(0, 6000), 10, 1.5)
	check(menu._scroller.scroll == 0.0, "dragged past the top springs back to 0 (%.1f)" % menu._scroller.scroll)
	await drag(mid, Vector2(0, -6000), 10, 1.5)
	check(absf(menu._scroller.scroll - menu._scroller.max_scroll()) < 1.0, "and past the bottom to the end (%.1f / %.1f)" % [menu._scroller.scroll, menu._scroller.max_scroll()])
	await drag(mid, Vector2(-300, 0))
	check(menu.screen == "list", "a sideways drag on the list opens nothing")

	await tap(mid)
	check(menu.screen == "event", "a tap still opens the card (%s)" % menu.screen)
	var t0: int = menu.ev["track"]
	var order: Array = menu._track_order()
	await drag(mid, Vector2(-300, 0))
	check(menu.screen == "event" and menu.ev["track"] == order[order.find(t0) + 1], "event screen: swipe to the next track")
	menu.ev["variant"] = "collect"
	menu.show_event()
	await frames(2)
	await drag(mid, Vector2(300, 0))
	check(menu.ev["track"] == t0 and menu.ev["variant"] == "standard", "Time attack swipes stay on the Standard layout")
	await drag(mid, Vector2(300, 0))
	await drag(mid, Vector2(300, 0))
	var t1: int = menu.ev["track"]
	menu.go_back()
	await frames(4)
	var card: Control = menu._scroller.content.get_child(0).get_child(order.find(t1))
	var r: Rect2 = card.get_global_rect()
	check(menu.screen == "list" and menu._scroller.get_global_rect().encloses(r), "back: the list shows that track's card (%d)" % t1)

	# the campaign opens on the world select; tapping the world in play lists its events as
	# lines; a world tab switches world; back returns to the world select
	menu.kind = "campaign"
	menu.world = -1
	menu.show_list()
	await frames(4)
	check(menu.screen == "worlds", "the campaign opens on the world select (%s)" % menu.screen)
	var Campaign = preload("res://scripts/campaign.gd")
	var w0: int = Campaign.chapter_of(menu._first_open_event())
	var photos: Array = menu.body.find_children("*", "Button", true, false).filter(func(b): return b.get_parent() is GridContainer)
	check(photos.size() == Campaign.CHAPTERS.size(), "a photo per world (%d)" % photos.size())
	await tap(photos[w0].get_global_rect().get_center())
	await frames(3)
	check(menu.world == w0 and menu._scroller.content.get_child(0).get_child_count() == Campaign.chapter_size(w0), "campaign opens on the world in play (%d), one line per event" % menu.world)
	var tabs: Array = menu.body.find_children("*", "Button", true, false).filter(func(b): return b.custom_minimum_size.y == 66)
	check(tabs.size() == Campaign.CHAPTERS.size(), "a tab per world (%d)" % tabs.size())
	menu.go_back()
	await frames(3)
	check(menu.screen == "worlds", "back from a world's events goes to the world select (%s)" % menu.screen)

	# the home screen's bookmark tabs take taps (the frame round the page must not eat them)
	menu.show_home()
	await frames(4)
	var cup: Button = menu._tabs.get_child(1)
	await tap(cup.get_global_rect().get_center() + Vector2(10, 0))
	check(menu.screen == "garage", "a tap on the Garage bookmark opens the Garage (%s)" % menu.screen)

	print("swipe test: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(1 if fails else 0)
