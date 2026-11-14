# Off the Map (Guillaume, 2026-11-14): a slightly hidden way to a custom run. The home page has
# a pencilled "off the map" link (not a numbered line); its screen picks any track, world,
# mode, layout, lap count and rival level, with nothing locked even on a fresh save. A run
# there is practice: it saves no record, ghost, medal or coin, so it never opens the Road Trip.
#   godot --headless --path . --script tests/custom_game_test.gd
extends SceneTree

const Records = preload("res://scripts/records.gd")
const Wallet = preload("res://scripts/wallet.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Themes = preload("res://scripts/themes.gd")
const Rivals = preload("res://scripts/rivals.gd")
const Menu = preload("res://scripts/menu.gd")
const Settings = preload("res://scripts/settings.gd")

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

func tap(b: Control) -> void:
	var p := b.get_global_rect().get_center()
	mouse(p, true)
	await frames(1)
	mouse(p, false)
	await frames(3)

func _find(menu, meta: String) -> Array:
	return menu.body.find_children("*", "Button", true, false).filter(func(b): return b.has_meta(meta) and b.is_visible_in_tree())

func _picks(menu, key: String) -> Array:
	return _find(menu, "pick").filter(func(b): return b.get_meta("pick")[0] == key)

# bring a tile of the picks list into view (it scrolls on a short screen), then tap it
func pick(menu, b: Control) -> void:
	var sc = menu._scroller
	var top: float = b.get_global_rect().position.y - sc.get_global_rect().position.y
	var bottom: float = b.get_global_rect().end.y - sc.get_global_rect().end.y
	if bottom > 0.0:
		sc.scroll += bottom + 4.0
	elif top < 0.0:
		sc.scroll += top - 4.0
	await frames(2)
	await tap(b)

func _on_screen(c: Control) -> bool:
	return root.get_visible_rect().grow(1.0).encloses(c.get_global_rect())

func _init() -> void:
	Records.reset()
	Settings._load().set_value("options", "tutorial_done", true)
	Settings._load().set_value("options", "custom", {})
	var coins0 := Wallet.coins()

	# the event a set of picks starts
	var c := Menu.custom_defaults()
	c["mode"] = "versus"; c["track"] = 5; c["theme"] = "rock"; c["variant"] = "reverse"; c["laps"] = 1; c["tier"] = 3
	var ev := Menu.custom_event(c)
	check(ev["kind"] == "custom" and ev["mode"] == "race" and ev["humans"] == 2, "Two players = a 2-player race")
	check(ev["theme"] == "rock" and ev["variant"] == "reverse" and ev["laps"] == 1 and ev["tier"] == 3, "the event carries every pick")
	c["mode"] = "trial"
	check(Menu.custom_event(c)["mode"] == "trial" and Menu.custom_event(c)["humans"] == 1, "Time trial is one player")
	# a save with a pick that no longer exists falls back to the default
	Settings._load().set_value("options", "custom", { "track": 999, "variant": "gone", "laps": 7, "theme": "moon" })
	var pk := Menu.custom_picks()
	check(pk["track"] == Defs.TRACKS.size() - 1 and pk["variant"] == "standard" and pk["laps"] == 0 and pk["theme"] in Themes.ORDER, "stale saved picks are cleaned")
	Settings._load().set_value("options", "custom", {})

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var ui = main.ui
	var menu = ui.menu
	ui.loading.visible = false
	ui._uh = 450   # a phone

	# a fresh save (nothing unlocked), both ways round: the link is on the page and opens the screen
	for sz in [Vector2i(1280, 720), Vector2i(720, 1280), Vector2i(2410, 1080), Vector2i(1080, 2410)]:
		root.size = sz
		await frames(4)
		menu.custom = {}
		menu.show_home()
		await create_timer(1.0).timeout   # the page lands
		await frames(2)
		var tag := "%dx%d" % [sz.x, sz.y]
		var link := _find(menu, "off_map")
		check(link.size() == 1, "%s: one Off the Map link on the home page" % tag)
		if link.is_empty():
			continue
		check(_on_screen(link[0]), "%s: the link is on screen" % tag)
		check(link[0].size.y >= 30.0, "%s: the link is big enough to tap (%.0f px)" % [tag, link[0].size.y])
		await tap(link[0])
		check(menu.screen == "custom", "%s: tapping it opens Off the Map" % tag)
		await create_timer(1.0).timeout
		await frames(2)
		var start := _find(menu, "custom_start")
		check(start.size() == 1 and _on_screen(start[0]), "%s: START is on screen" % tag)
		for key in ["theme", "mode", "variant", "laps"]:
			var tiles := _picks(menu, key)
			check(tiles.size() > 0 and tiles.all(func(b): return not b.disabled), "%s: %s choices all open (%d)" % [tag, key, tiles.size()])
			for b in tiles:
				var r: Rect2 = b.get_global_rect()
				check(r.position.x >= 0.0 and r.end.x <= root.get_visible_rect().end.x, "%s: %s tile %s inside the screen width" % [tag, key, str(b.get_meta("pick")[1])])
		check(_picks(menu, "theme").size() == Themes.ORDER.size(), "%s: every world, even locked ones" % tag)
		check(_picks(menu, "variant").size() == Defs.VARIANTS.size(), "%s: every layout" % tag)
		check(_picks(menu, "tier").is_empty(), "%s: no rival level for a Time trial" % tag)
		menu.go_back()
		await frames(2)
		check(menu.screen == "home", "%s: back goes home" % tag)
		# the home page itself still fits (the scrap must not push it off the screen)
		await create_timer(1.0).timeout
		check(menu._page.get_global_rect().end.y <= root.get_visible_rect().end.y, "%s: the home page ends on screen" % tag)

	# every track can be reached with the arrows, though the campaign has opened none of them
	root.size = Vector2i(1280, 720)
	menu.show_custom()
	await frames(3)
	var seen := {}
	for i in Defs.TRACKS.size():
		seen[menu.custom["track"]] = true
		await tap(_find(menu, "custom_track").filter(func(b): return b.get_meta("custom_track") == 1)[0])
	check(seen.size() == Defs.TRACKS.size(), "the arrows reach all %d tracks (%d)" % [Defs.TRACKS.size(), seen.size()])

	# picks: tapping one fills it in, keeps it in the settings, and Race shows the rival levels
	await pick(menu, _picks(menu, "mode").filter(func(b): return b.get_meta("pick")[1] == "race")[0])
	check(menu.custom["mode"] == "race", "tap Race: picked")
	check(Settings.get_opt("custom", {}).get("mode", "") == "race", "the pick is kept in the settings")
	check(_picks(menu, "tier").size() == Rivals.TIERS.size(), "Race offers every rival level")
	for want in [["theme", "sand"], ["variant", "obstacles"], ["laps", 1], ["tier", 3]]:
		var b: Array = _picks(menu, want[0]).filter(func(x): return x.get_meta("pick")[1] == want[1])
		check(b.size() == 1, "%s %s tile shown" % want)
		if b.size() == 1:
			await pick(menu, b[0])
	check(menu.custom["theme"] == "sand" and menu.custom["variant"] == "obstacles" and menu.custom["laps"] == 1 and menu.custom["tier"] == 3, "all picks taken")

	# START: the race uses every pick
	var go: Button = _find(menu, "custom_start")[0]
	go.pressed.emit()
	for i in 200:
		await process_frame
		if main.race != null and not main.building:
			break
	check(main.race != null, "START starts a run")
	if main.race == null:
		quit(1)
		return
	check(main.free_run, "the run is a free one")
	check(main.race.laps_total == 1, "laps picked (%d)" % main.race.laps_total)
	check(main.rival_tier == 3, "rival level picked (%d)" % main.rival_tier)
	check(main.variant == "obstacles" and main.mode == "race", "layout and mode picked")
	check(main.view.theme_override == "sand", "world picked")
	check(not main.catch_up, "no campaign catch-up")

	# a free run saves nothing: a fast lap, a finish, the results
	Records.reset()
	main.mode = "trial"
	main._trial_lap(main.race.cars[0], 5.0, [])
	var me = main.race.cars[0]
	me.finished = true
	me.finish_time = 5.0
	me.best_lap = 5.0
	main._trial_run(me)
	main._show_results()
	await frames(2)
	check(not Records.any(), "no record or medal saved by a free run")
	check(Records.get_ghost(main.rec_key()).is_empty(), "no ghost saved")
	check(Wallet.coins() == coins0, "no coins paid (%d -> %d)" % [coins0, Wallet.coins()])
	check(main.awards_won.is_empty(), "no awards")
	check(ui.results.visible, "the results show")

	# a Road Trip event after it is scored as before
	main.race = null
	main.phase = "menu"
	main._start_event({ "track": 0, "variant": "standard", "mode": "trial", "humans": 1, "kind": "attack", "idx": 0, "theme": "" })
	for i in 200:
		await process_frame
		if not main.building:
			break
	check(not main.free_run and main.free_laps == 0, "a Special Stage is not free")

	Settings._load().set_value("options", "custom", {})
	Records.reset()
	print("FAILS: ", fails)
	quit(1 if fails else 0)
