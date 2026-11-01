extends SceneTree
# Evaluate one candidate layout: godot --headless --path . --script tools/eval_layout.gd -- '[[x,y,dir,r?],...]'
const Check = preload("res://tools/layout_check.gd")
const TrackData = preload("res://scripts/track.gd")
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var turns = JSON.parse_string(a)
		var d := { "name": "x", "turns": turns }
		var c: Dictionary = Check.check(d)
		var T := TrackData.new(d, "standard")
		printerr("EVAL bad=%d L=%d bridges=%d levels=%s report=%s why=%s" % [c["bad"], c["L"], c["bridges"], str(c["levels"]), T.ramp_report, str(c["why"])])
		var pts := []
		for p in T.P: pts.append([roundi(p.x), roundi(p.y), roundi(T.height_of[pts.size()])])
		var f2 := FileAccess.open("/tmp/layout.json", FileAccess.WRITE)
		f2.store_string(JSON.stringify({ "P": pts, "turns": turns }))
	quit()
