# Pause menu: the pause page stays short (where you are, Menu / Restart / Resume and one
# Settings button); the volume, graphics and toggle options live on a Settings page one tap
# away, and Back or Esc / the Android back button returns to the pause page without resuming.
#   godot --headless --path . --script tests/pause_test.gd
extends SceneTree

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

# visible buttons in the open pause panel, by their label text
func shown_labels(ui) -> Array:
	var out := []
	for b in ui.pause_panel.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.has_meta("label"):
			out.append(String(b.get_meta("label").text))
	return out

func shown_sliders(ui) -> int:
	return ui.pause_panel.find_children("*", "HSlider", true, false).filter(func(s): return s.is_visible_in_tree()).size()

func button(ui, text: String) -> Button:
	for b in ui.pause_panel.find_children("*", "Button", true, false):
		if b.is_visible_in_tree() and b.has_meta("label") and String(b.get_meta("label").text) == text:
			return b
	return null

func _init() -> void:
	root.size = Vector2i(1280, 720)
	preload("res://scripts/settings.gd")._load().set_value("options", "tutorial_done", true)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	main._start_event({ "track": 0, "variant": "standard", "mode": "trial", "humans": 1, "kind": "attack", "idx": 0, "theme": "" })
	var t0 := Time.get_ticks_msec()
	while not main._can_pause() and Time.get_ticks_msec() - t0 < 60000:
		await frames(1)
	check(main._can_pause(), "a Time trial starts and can be paused")
	var ui = main.ui

	main._toggle_pause()
	await frames(3)
	check(main.paused and ui.pause_ov.visible, "pause opens")
	var labels := shown_labels(ui)
	check(labels == ["MENU", "RESTART", "RESUME", "SETTINGS"], "pause page shows only Menu, Restart, Resume, Settings: %s" % [labels])
	check(shown_sliders(ui) == 0, "no volume sliders on the pause page")
	check(not ui.pause_settings_open(), "pause opens on the short page")

	button(ui, "SETTINGS").pressed.emit()
	await frames(3)
	check(ui.pause_settings_open(), "Settings opens the settings page")
	check(shown_sliders(ui) == 2, "settings page has the Music and Sound sliders")
	labels = shown_labels(ui)
	check(labels.has("GRAPHICS  %s" % main.Settings.QUALITY_NAMES[main.Settings.get_opt("quality")]), "settings page has the Graphics button: %s" % [labels])
	check(labels.any(func(l): return l.begins_with("GHOST")), "Ghost toggle shown in a Time trial")
	check(not labels.has("RESUME"), "race buttons hidden on the settings page")

	button(ui, "BACK").pressed.emit()
	await frames(3)
	check(not ui.pause_settings_open() and main.paused, "Back returns to the pause page, still paused")

	button(ui, "SETTINGS").pressed.emit()
	await frames(2)
	main._go_back()   # Esc / Android back
	await frames(3)
	check(main.paused and ui.pause_ov.visible and not ui.pause_settings_open(), "Esc on settings goes back to the pause page, not into the race")
	main._go_back()
	await frames(3)
	check(not main.paused and not ui.pause_ov.visible, "Esc on the pause page resumes")

	# reopening always lands on the short page, even if it was left on Settings
	main._toggle_pause()
	await frames(2)
	button(ui, "SETTINGS").pressed.emit()
	await frames(2)
	main._toggle_pause()
	await frames(2)
	main._toggle_pause()
	await frames(2)
	check(main.paused and not ui.pause_settings_open(), "pause reopens on the short page")

	if fails > 0:
		printerr("pause_test: %d failure(s)" % fails)
		quit(1)
	else:
		print("pause_test: ok")
		quit(0)
