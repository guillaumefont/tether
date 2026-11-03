# Menu carousels: a sideways drag flips the page / track, a short tap still opens a card,
# and a swipe that starts on a card never opens it.
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

func drag(from: Vector2, dx: float, steps := 8) -> void:
	mouse(from, true)
	await frames(1)
	var p := from
	for k in steps:
		var q := from + Vector2(dx * (k + 1) / steps, 0)
		motion(q, q - p)
		p = q
		await frames(1)
	mouse(p, false)
	await create_timer(0.5).timeout   # slide out + slide in
	await frames(2)

func tap(pos: Vector2) -> void:
	mouse(pos, true)
	await frames(1)
	mouse(pos, false)
	await frames(3)

func _init() -> void:
	root.size = Vector2i(1280, 720)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var menu = main.ui.menu
	main.ui.loading.visible = false
	var mid := Vector2(root.get_visible_rect().size) * Vector2(0.5, 0.55)

	menu.kind = "attack"
	menu.page = 0
	menu.show_list()
	await frames(3)
	await drag(mid, -300)
	check(menu.screen == "list" and menu.page == 1, "swipe left: next page (page %d)" % menu.page)
	await drag(mid, 300)
	check(menu.page == 0, "swipe right: back to the first page (page %d)" % menu.page)
	await drag(mid, 300)
	check(menu.page == 0 and menu.screen == "list", "swipe right on the first page bounces back")
	await drag(mid, -40, 2)
	check(menu.page == 0 and menu.screen == "list", "a short slow drag snaps back, opens nothing")

	await tap(mid)
	check(menu.screen == "event", "a tap still opens the card (%s)" % menu.screen)
	var t0: int = menu.ev["track"]
	await drag(mid, -300)
	check(menu.screen == "event" and menu.ev["track"] == t0 + 1, "event screen: swipe to the next track")
	menu.ev["variant"] = "collect"
	menu.show_event()
	await frames(2)
	await drag(mid, 300)
	check(menu.ev["track"] == t0 and menu.ev["variant"] == "collect", "previous track keeps the chosen variant")
	menu.go_back()
	check(menu.screen == "list" and menu.page == t0 / 6, "back returns to that track's page")

	menu.kind = "campaign"
	menu.page = 0
	menu.show_list()
	await frames(2)
	await drag(mid, -300)
	check(menu.page == 1, "campaign: swipe to the next chapter")

	print("swipe test: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(1 if fails else 0)
