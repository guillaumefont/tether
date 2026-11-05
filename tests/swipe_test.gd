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
	await drag(mid, Vector2(-300, 0))
	check(menu.screen == "event" and menu.ev["track"] == t0 + 1, "event screen: swipe to the next track")
	menu.ev["variant"] = "collect"
	menu.show_event()
	await frames(2)
	await drag(mid, Vector2(300, 0))
	check(menu.ev["track"] == t0 and menu.ev["variant"] == "collect", "previous track keeps the chosen variant")
	await drag(mid, Vector2(300, 0))
	await drag(mid, Vector2(300, 0))
	var t1: int = menu.ev["track"]
	menu.go_back()
	await frames(4)
	var card: Control = menu._scroller.content.get_child(0).get_child(t1)
	var r: Rect2 = card.get_global_rect()
	check(menu.screen == "list" and menu._scroller.get_global_rect().encloses(r), "back: the list shows that track's card (%d)" % t1)

	menu.kind = "campaign"
	menu.focus = 13
	menu.show_list()
	await frames(4)
	check(menu._scroller.scroll > 100.0, "campaign opens scrolled to the event in play (%.0f)" % menu._scroller.scroll)

	print("swipe test: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(1 if fails else 0)
