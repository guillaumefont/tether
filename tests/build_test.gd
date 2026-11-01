extends SceneTree
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
func _init() -> void:
	for d in Defs.TRACKS:
		var out := {}
		for v in ["standard","reverse","obstacles","collect"]:
			var T := TrackData.new(d, v)
			var js := []
			for j in T.jumps: js.append(str(roundi(j["s"])))
			out[v] = "n=%d L=%d br=%d start=%d obs=%d gems=%d jumps=%s" % [T.n, roundi(T.L), T.bridges.size(), roundi(T.start_s), T.obstacles.size(), T.tokens.size(), ",".join(js)]
		print(d["name"], " ", JSON.stringify(out).replace(",\"", ",\""))
	quit()
