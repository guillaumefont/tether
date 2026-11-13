extends SceneTree
# The UI has no coloured accent (Guillaume, 2026-11-13, "the Ice Blue case"): the ice blue
# #4fb6ff that replaced amber was taken out of the menus, the HUD, the loading pages and the
# app icon. Menus are ink on paper; on dark the accent is chalk cream. Amber stays the player's
# car and rope, gold stays medals and coins.
const Paper = preload("res://scripts/paper.gd")
const Art = preload("res://scripts/menu_art.gd")
const UI = preload("res://scripts/ui.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

# a bright, saturated blue or cyan: what an accent colour would look like
func _blue(c: Color) -> bool:
	return c.h >= 0.5 and c.h <= 0.7 and c.s > 0.35 and c.v > 0.35 and c.a > 0.1

func _check_colour(c: Color, what: String) -> void:
	if _blue(c):
		fail("%s is blue: %s" % [what, c.to_html(false)])

func _init() -> void:
	# the accent roles the menus and HUD read
	_check_colour(Art.C_ACCENT, "Art.C_ACCENT")
	_check_colour(Art.C_ACCENT_DIM, "Art.C_ACCENT_DIM")
	_check_colour(UI.C_ACCENT, "ui.gd C_ACCENT")
	_check_colour(Paper.SHADE, "Paper.SHADE (go button shadow)")
	_check_colour(Paper.HL, "Paper.HL (marker)")
	_check_colour(Paper.PEN, "Paper.PEN (handwriting)")
	if Art.C_ACCENT != UI.C_ACCENT:
		fail("ui.gd C_ACCENT must mirror Art.C_ACCENT")
	if Art.C_CAR != Color("#f2b134"):
		fail("the player's car stays amber")

	# no leftover ice blue in the UI sources, the icon or the web loading page
	var files := ["res://scripts/paper.gd", "res://scripts/menu.gd", "res://scripts/ui.gd",
		"res://scripts/garage.gd", "res://scripts/menu_art.gd", "res://scripts/track_map.gd",
		"res://scripts/world_unlock.gd", "res://icon.svg", "res://web/shell_template.html",
		"res://web/shell.html", "res://tools/promo/edit.py"]
	for f in files:
		var src := FileAccess.get_file_as_string(f).to_lower()
		for hex in ["4fb6ff", "1d7fc4", "1d5fa8"]:
			if src.contains(hex):
				fail("%s still uses #%s" % [f, hex])

	# the launcher icons and the boot splash: no blue pixels
	for f in ["res://icons/icon-192.png", "res://icons/adaptive-foreground-432.png", "res://icons/splash.png"]:
		var img := Image.load_from_file(f)
		if img == null:
			fail("cannot load " + f)
			continue
		var n := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				if _blue(img.get_pixel(x, y)):
					n += 1
		if n > 0:
			fail("%s has %d blue pixels" % [f, n])

	if bad == 0:
		print("colours_test: OK")
	quit(1 if bad > 0 else 0)
