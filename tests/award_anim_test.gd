extends SceneTree
# Award medallions: every award has its own scene and timing, and each scene draws from the
# first frame to the last without a script error; the award show and the scripts that use
# it load.
const Awards = preload("res://scripts/awards.gd")
const Medal = preload("res://scripts/award_medal.gd")

var bad := 0

func fail(msg: String) -> void:
	bad += 1
	printerr(msg)

func _init() -> void:
	for a in Awards.LIST:
		if not Medal.FINISH.has(a["id"]):
			fail("award %s has no medallion scene" % a["id"])
	if Medal.FINISH.size() != Awards.LIST.size():
		fail("medallion scenes for awards that do not exist")
	for path in ["res://scripts/award_show.gd", "res://scripts/main.gd", "res://scripts/menu.gd", "res://scripts/ui.gd"]:
		var sc: Script = load(path)
		if sc == null or not sc.can_instantiate():
			fail("%s does not load" % path)
	_draw_all.call_deferred()

func _draw_all() -> void:
	var m: Control = Medal.new()
	m.size = Vector2(160, 160)
	root.add_child(m)
	for a in Awards.LIST:
		m.id = a["id"]
		var t := 0.0
		while t < Medal.duration(a["id"]) + 0.2:
			m.t = t
			m.queue_redraw()
			await process_frame
			t += 0.11
	m.queue_free()
	print("award animations: %s" % ("ok" if bad == 0 else "%d problems" % bad))
	quit(1 if bad > 0 else 0)
