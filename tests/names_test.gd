extends SceneTree
# Traveller names (Guillaume, 2026-11-13): the game is Tether Rally and the menu speaks the
# roadbook's rally road trip: Road Trip (legs and stops), Special Stages, Two for the Road,
# Daily Detour and the Passport. The old arcade names must not come back in anything a
# player reads: the app name, the wordmark, menu and results text.

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

# the line without its comment (a # outside quotes starts one)
func _code(line: String) -> String:
	var q := false
	for i in line.length():
		if line[i] == "\"":
			q = not q
		elif line[i] == "#" and not q:
			return line.substr(0, i)
	return line

func _init() -> void:
	if ProjectSettings.get_setting("application/config/name") != "Tether Rally":
		fail("project name is %s, want Tether Rally" % ProjectSettings.get_setting("application/config/name"))
	var presets := FileAccess.get_file_as_string("res://export_presets.cfg")
	if presets.contains("Tether Racing"):
		fail("export_presets.cfg still names the app Tether Racing")

	# the quoted text of every script a player reads: old names only in comments or ids
	var old := ["Tether Racing", "TETHER RACING", "\"RACING\"", "Time attack", "Time Attack", "TIME ATTACK",
		"Track of the day", "Tracks of the day", "TRACK OF THE DAY", "2 PLAYERS", "2-player race",
		"\"Campaign\"", "the Campaign", "CAMPAIGN", "\"Awards\"", "Awards screen", "WORLD %d"]
	var dir := DirAccess.open("res://scripts")
	for f in dir.get_files():
		if not f.ends_with(".gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string("res://scripts/" + f).split("\n"):
			n += 1
			var code := _code(line)
			for w in old:
				if code.contains(w) and code.contains("\""):
					fail("scripts/%s:%d still says %s" % [f, n, w])

	for f in ["res://scripts/menu_art.gd", "res://scripts/tutorial.gd"]:
		if not FileAccess.get_file_as_string(f).contains("TETHER RALLY"):
			fail("%s does not write TETHER RALLY" % f)

	if bad == 0:
		print("names_test: ok")
	quit(1 if bad > 0 else 0)
