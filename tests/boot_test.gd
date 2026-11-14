# Launch goes straight onto the loading screen (Guillaume, 2026-11-14: "Can I arrive directly on
# the loading screen without the static splash screen?"). The engine's boot splash shows no
# picture, only the loading screen's dark colour, and the game draws its loading screen before
# the slow setup (sound synthesis, the menu's track), so nothing static sits in between.
# In the browser the page's own loading screen stays up until the game's one is drawn.
#   godot --headless --path . --script tests/boot_test.gd
extends SceneTree

const MenuArt = preload("res://scripts/menu_art.gd")

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func _init() -> void:
	root.size = Vector2i(1280, 720)
	preload("res://scripts/settings.gd")._load().set_value("options", "tutorial_done", true)
	_run.call_deferred()

func _run() -> void:
	# no static splash picture; the colour shown while the engine starts is the loading screen's
	check(ProjectSettings.get_setting("application/boot_splash/show_image") == false,
		"boot splash shows no picture")
	var bg: Color = ProjectSettings.get_setting("application/boot_splash/bg_color")
	check(Vector3(bg.r, bg.g, bg.b).distance_to(Vector3(MenuArt.C_NIGHT_BOT.r, MenuArt.C_NIGHT_BOT.g, MenuArt.C_NIGHT_BOT.b)) < 0.003, "boot colour is the loading screen's night blue: %s" % bg)

	# launched as the app's scene: the loading screen is up before the menu is built
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	var main: Node = current_scene
	check(main != null and main.booting(), "main knows it is the app starting up")
	check(main.ui.loading.visible and main.ui.loading.modulate.a > 0.99, "first frames show the loading screen")
	check(main.attract == null, "the menu's track is built after the loading screen is drawn, not before")
	var t0 := Time.get_ticks_msec()
	while main.ui.loading.visible and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
	check(not main.ui.loading.visible, "the loading screen fades out onto the menu")
	check(main.attract != null and main.phase == "menu" and main.ui.menu.visible, "menu is up with its live track behind")

	# a test or tool that instantiates main itself still gets it ready synchronously
	var m2: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(m2)
	check(not m2.booting() and m2.attract != null, "instantiated by hand: set up before _ready returns")
	m2.queue_free()

	# browser: the page's loading screen hands over to the game's
	var shell := FileAccess.get_file_as_string("res://web/shell_template.html")
	check(shell.contains("window.tetherReady = function"), "web page waits for the game's loading screen")
	check(not shell.contains("}).then(function () {\n    progress(1);\n    status.style.opacity"),
		"web page no longer drops its loading screen as soon as the engine starts")
	check(FileAccess.get_file_as_string("res://scripts/main.gd").contains("window.tetherReady"), "game calls the hand-over")
	check(FileAccess.get_file_as_string("res://web/shell.html").contains("window.tetherReady = function"),
		"built web/shell.html is regenerated from the template")

	print("boot test: %s" % ("PASS" if fails == 0 else "%d FAIL" % fails))
	quit(1 if fails else 0)
