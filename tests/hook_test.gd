extends SceneTree
# Holding the button always hooks the tower of the bend the car is on (or of the next
# bend from a straight), never another tower that happens to be nearer.
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")

func _init() -> void:
	var bad := 0
	for d in Defs.TRACKS:
		for v in ["standard", "reverse"]:
			var tr := TrackData.new(d, v)
			var race := Race.new(tr, "trial", 1)
			var c = race.cars[0]
			c.air = 0.0; c.fall = 0.0
			var nt := tr.anchors.size()
			for k in nt:
				var a: TrackData.Anchor = tr.anchors[k]
				var prev: TrackData.Anchor = tr.anchors[(k - 1 + nt) % nt]
				var i := (prev.exit + 1) % tr.n
				var miss := 0
				while true:
					c.seg = i; c.pos = tr.P[i]; c.vel = tr.seg_dir[i] * 600.0; c.h = c.vel.angle()
					var got: int = race.find_anchor(c)
					var on_arc := posmod(i - a.entry, tr.n) <= posmod(a.exit - a.entry, tr.n)
					if got != k and got != -1:
						bad += 1
						printerr("%s %s seg %d: hooked %d, expected %d" % [d["name"], v, i, got, k])
					elif on_arc and got != k:
						miss += 1
					if i == a.exit: break
					i = (i + 1) % tr.n
				if miss > 0:
					bad += 1
					printerr("%s %s bend %d: %d points of the bend cannot hook" % [d["name"], v, k, miss])
	printerr("HOOK BAD: %d" % bad)
	quit(1 if bad > 0 else 0)
