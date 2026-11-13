# Home page bookmark tabs (Awards, Garage, Settings) stay on screen and take taps, in portrait
# and landscape, on a phone's 450 logical pixels. The "2183 coins" case (Guillaume, 2026-11-13):
# a 1080x2410 phone with a four-digit coin count and a medal of every kind made the page wider
# than planned, and the tabs ended up past the screen's right edge. The Time attack line's
# subtitle was also cut ("the campaign opens m…"): every line's subtitle must fit its line.
#   godot --headless --path . --script tests/home_tabs_test.gd
extends SceneTree

const Records = preload("res://scripts/records.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Wallet = preload("res://scripts/wallet.gd")

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func mouse(pos: Vector2, down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = down
	e.position = pos
	e.global_position = pos
	root.push_input(e, true)

func tap(pos: Vector2) -> void:
	mouse(pos, true)
	await frames(1)
	mouse(pos, false)
	await frames(3)

func _init() -> void:
	root.size = Vector2i(1280, 720)
	preload("res://scripts/settings.gd")._load().set_value("options", "tutorial_done", true)
	# the save from the screenshot (in memory, not saved): 2183 coins, some campaign done,
	# a medal of every kind, part of Time attack open
	Wallet._load().set_value("wallet", "coins", 2183)
	for i in 13:
		var e := Campaign.event(i)
		Records.award_medal(Records.key(e["name"], e["variant"]), e["mode"], Campaign.GOLD + (1 if i % 2 else 0))
	for i in [13, 14]:
		var e := Campaign.event(i)
		Records.award_medal(Records.key(e["name"], e["variant"]), e["mode"], 1 + i % 2)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var ui = main.ui
	var menu = ui.menu
	ui.loading.visible = false
	ui._uh = 450   # a phone's logical height, as on the device

	# phone sizes: the 1080x2410 of the report, a 16:9 phone, both ways round
	for sz in [Vector2i(1080, 2410), Vector2i(720, 1280), Vector2i(2410, 1080), Vector2i(1280, 720)]:
		root.size = sz
		await frames(4)
		menu.show_home()
		await create_timer(1.0).timeout   # the page lands
		await frames(2)
		var vp: Rect2 = root.get_visible_rect()
		var tag := "%dx%d" % [sz.x, sz.y]
		var names := ["awards", "garage"]
		for k in 2:
			var t: Button = menu._tabs.get_child(k)
			var r: Rect2 = t.get_global_rect()
			# the part of the tab past the page (the rest lies under nothing, on the page)
			check(r.end.x <= vp.end.x + 0.5, "%s: %s tab ends on screen (%.0f <= %.0f)" % [tag, names[k], r.end.x, vp.end.x])
			var gear: Button = menu._tabs.get_child(2)
			check(gear.get_global_rect().end.x <= vp.end.x + 0.5, "%s: settings tab ends on screen" % tag)
			var page: Rect2 = menu._page.get_global_rect()
			check(r.end.x - page.end.x >= 30.0, "%s: %s tab shows %.0f px past the page" % [tag, names[k], r.end.x - page.end.x])
			# tap the part that sticks out
			await tap(Vector2((page.end.x + r.end.x) * 0.5, r.get_center().y))
			check(menu.screen == names[k], "%s: a tap on the %s tab opens it (%s)" % [tag, names[k], menu.screen])
			menu.show_home()
			await create_timer(1.0).timeout
			await frames(2)
		# every roadbook line's subtitle shows whole, on two lines at most, inside its line
		for lbl in menu.body.find_children("*", "Label", true, false):
			if not lbl.has_meta("road_sub"):
				continue
			var n: int = lbl.get_line_count()
			var line: Control = lbl.get_parent().get_parent().get_parent()   # the roadbook line
			var r: Rect2 = lbl.get_global_rect()
			check(n <= 2 and lbl.get_visible_line_count() == n, "%s: \"%s\" shows whole (%d line(s))" % [tag, lbl.text, n])
			check(line.get_global_rect().encloses(r), "%s: \"%s\" stays inside its line" % [tag, lbl.text])

		# the whole page and the photo stay on screen
		var pr: Rect2 = menu._page.get_global_rect()
		check(pr.end.y <= vp.end.y, "%s: the page ends on screen (%.0f <= %.0f)" % [tag, pr.end.y, vp.end.y])

	print("home tabs test: %s" % ("PASS" if fails == 0 else "%d failure(s)" % fails))
	quit(1 if fails else 0)
