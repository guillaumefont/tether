# The Road Trip page has its world's colour (Guillaume, 2026-11-14: "the Road Trip screen
# looks sad next to the others"). Each world's events lie on a page in that world's tint,
# joined to its open tab; medals are stamped in their own metal; the world photos are held
# by tape in the world's colour. On a phone held sideways, every stop's name fits its line
# (they were cut to "LA…", "TW…" in two narrow columns).
#   godot --headless --path . --script tests/road_trip_colour_test.gd
extends SceneTree

const Records = preload("res://scripts/records.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Medals = preload("res://scripts/medals.gd")
const Paper = preload("res://scripts/paper.gd")

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1

func frames(n := 2) -> void:
	for i in n:
		await process_frame

func _init() -> void:
	root.size = Vector2i(1280, 720)
	preload("res://scripts/settings.gd")._load().set_value("options", "tutorial_done", true)
	# snow finished (Gold and Pivot), forest part way with a Bronze and a Silver
	for i in 16:
		var e := Campaign.event(i)
		Records.award_medal(Records.key(e["name"], e["variant"]), e["mode"], Campaign.GOLD + (1 if i % 5 == 0 else 0))
	for i in [16, 17]:
		var e := Campaign.event(i)
		Records.award_medal(Records.key(e["name"], e["variant"]), e["mode"], 1 + i % 2)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(5)
	var ui = main.ui
	var menu = ui.menu
	ui.loading.visible = false
	ui._uh = 450

	for sz in [Vector2i(1280, 720), Vector2i(720, 1280)]:
		root.size = sz
		ui._apply_scale()
		await frames(3)
		var tag := "%dx%d" % [sz.x, sz.y]
		for w in [0, 1]:
			menu.kind = "campaign"
			menu.world = w
			menu.focus = 0
			menu.show_list()
			await frames(4)
			var theme: String = Campaign.CHAPTERS[w]["theme"]
			var pages: Array = menu.body.find_children("*", "PanelContainer", true, false).filter(func(n): return n.has_meta("world_page"))
			check(pages.size() == 1, "%s %s: one world page" % [tag, theme])
			if pages.size() == 1:
				var sb = pages[0].get_theme_stylebox("panel")
				check(sb.bg_color == menu.WORLD_TINT.get(theme), "%s %s: the page is in the world's tint" % [tag, theme])
				check(sb.bg_color.s > 0.05, "%s %s: the tint has some colour" % [tag, theme])
			# medals stamped in their own metal, one colour per medal kind
			var stamps: Array = menu.body.find_children("*", "Control", true, false).filter(func(n): return n is Paper.Stamp and n.text in menu.MEDAL_STAMP)
			check(stamps.size() > 0, "%s %s: medal stamps shown" % [tag, theme])
			for st in stamps:
				var m: int = menu.MEDAL_STAMP.find(st.text) + 1
				var f = st.get("fill")
				check(f is Color and f.a > 0.5 and absf(f.h - Medals.COLORS[m - 1].lightened(0.15).h) < 0.02, "%s %s: %s stamp filled in its metal" % [tag, theme, st.text])
			# every stop's name fits its line
			var cut := []
			for l in menu.body.find_children("*", "Label", true, false):
				if l.clip_text and l.text == l.text.to_upper() and l.text.length() > 2 and l.get_parent() is VBoxContainer and l.get_parent().get_parent() is HBoxContainer:
					var need: float = l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
					if need > l.size.x + 1.0:
						cut.append(l.text)
			check(cut.is_empty(), "%s %s: no stop name cut %s" % [tag, theme, str(cut)])

	# the world select page: an open world's photo is held by tape in that world's colour
	menu.kind = "campaign"
	menu.world = -1
	menu.show_list()
	await frames(4)
	var tapes: Array = menu.body.find_children("*", "Control", true, false).filter(func(n): return n is Paper.Tape)
	check(tapes.size() == 4, "world select: four taped photos")
	check(tapes.size() == 4 and tapes[0].get("col") != null and tapes[0].col != Paper.TAPE and tapes[1].col != Paper.TAPE and tapes[0].col != tapes[1].col, "world select: open worlds' tape in their own colour")
	check(tapes.size() == 4 and tapes[3].get("col") == Paper.TAPE, "world select: a locked world keeps clear tape")

	print("road_trip_colour_test: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
	quit(1 if fails > 0 else 0)
