extends SceneTree
# Offline layout search used for the 2026-11 rework: moves, adds and removes towers of one
# track to cut long straights (target links of about one lane, ~420 world units) while the
# layout check stays as clean as the current layout, crossings are kept (extra ones welcome),
# jump straights stay 900-1150 long, the start sits well inside a straight and every bend
# really turns. Prints progress; writes the best layout as JSON (copy its turns/jumps into
# scripts/track_defs.gd, then rerun tools/gen_medals.gd and the tests).
# Usage: godot --headless --path . --script tools/tighten_layout.gd -- <track index> <iterations> <seed> <out.json> ['<start turns json>'] ['<start jumps json>']
# Env ADD=<n>: how many towers it may add (default 4). Several seeds give different shapes.
const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Check = preload("res://tools/layout_check.gd")
const SP := TrackData.SPREAD
var base: Dictionary
var d0: Dictionary
var max_add := 4

func info(d: Dictionary) -> Dictionary:
	return Check.check(d)

func cost(d: Dictionary) -> Dictionary:
	var c := info(d)
	var T: TrackData = c["T"]
	var k := 0.0
	k += 1e4 * maxf(0.0, c["bad"] - base["bad"])
	for w in c["why"]:
		k += 2e4 * maxf(0.0, c["why"][w] - base["why"].get(w, 0))
	if c["bridges"] < base["bridges"]: k += 1e5
	k -= 3000.0 * (c["bridges"] - base["bridges"])
	var jk := []
	for j in d.get("jumps", []): jk.append(int(j["k"]))
	var strs := []
	for st in T.straights:
		var l: float = st["len"]
		strs.append(l)
		if st["k"] in jk:
			k += pow(maxf(0.0, 900.0 - l), 2.0) + pow(maxf(0.0, l - 1150.0), 2.0) / 20.0
			continue
		k += pow(maxf(0.0, l - 420.0), 2.0) / 50.0
		k += pow(maxf(0.0, 280.0 - l), 2.0) / 3.0
	# every bend turns properly: no tower the road only grazes
	for a in T.arcs:
		var an = T.anchors[a["k"]]
		var sw: float = a["len"] / an.r
		k += pow(maxf(0.0, 1.0 - sw), 2.0) * 30000.0
	# start straight: the start must sit well inside a straight
	var sk := -1
	for st in T.straights:
		var o := T.wrap_s(T.start_s - st["s0"])
		if o <= st["len"]: sk = st["k"]; k += pow(maxf(0.0, 300.0 - o), 2.0)
	if sk < 0: k += 1e5
	# distinct towers apart
	var ps := []
	for t in d["turns"]:
		var p := Vector2(t[0], t[1]) * SP
		var dup := false
		for q in ps: if q.distance_to(p) < 1.0: dup = true
		if not dup: ps.append(p)
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			k += pow(maxf(0.0, 820.0 - ps[i].distance_to(ps[j])), 2.0) * 2.0
	# lap length band
	var r: float = T.L / base["L"]
	k += pow(maxf(0.0, r - 1.25) * 1e4, 2.0) / 100.0 + pow(maxf(0.0, 0.8 - r) * 1e4, 2.0) / 100.0
	# each tower adds bends but also length; slight cost per tower
	k += 400.0 * d["turns"].size()

	return { "k": k, "c": c, "strs": strs }

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var ti := int(a[0]); var iters := int(a[1]); seed(int(a[2]))
	d0 = Defs.TRACKS[ti].duplicate(true)
	if a.size() > 4 and a[4] != "":
		d0["turns"] = JSON.parse_string(a[4])
		for t in d0["turns"]:
			for q in t.size(): t[q] = int(t[q])
	if a.size() > 5 and a[5] != "": d0["jumps"] = JSON.parse_string(a[5])
	if OS.get_environment("ADD") != "": max_add = int(OS.get_environment("ADD"))
	var orig = Defs.TRACKS[ti]
	base = info(orig)
	TrackData.dfs_budget = 20000
	var n0: int = orig["turns"].size()
	var best := d0
	var bk := cost(best)
	printerr("%s start k=%d strs=%s" % [orig["name"], bk["k"], str(bk["strs"])])
	var cur := best; var ck := bk
	var temp := 3000.0
	var step := 300.0
	for it in iters:
		var cand: Dictionary = cur.duplicate(true)
		var turns: Array = cand["turns"]
		var nt := turns.size()
		var roll := randf()
		if roll < 0.08 and nt < n0 + max_add:
			# insert a tower beside a long straight
			var T: TrackData = ck["c"]["T"]
			var i := randi() % nt
			var jk := []
			for j in cand.get("jumps", []): jk.append(int(j["k"]))
			if i in jk: continue
			var A: Array = turns[i]; var B: Array = turns[(i + 1) % nt]
			var mid := (Vector2(A[0], A[1]) + Vector2(B[0], B[1])) / 2.0
			var dirv := (Vector2(B[0], B[1]) - Vector2(A[0], A[1])).normalized()
			var off := TrackData.perp(dirv) * randf_range(-700, 700) + dirv * randf_range(-200, 200)
			var p := mid + off
			turns.insert(i + 1, [roundi(p.x), roundi(p.y), 1 if randf() < 0.5 else -1])
			for j in cand.get("jumps", []):
				if int(j["k"]) > i: j["k"] = int(j["k"]) + 1
		elif roll < 0.11 and nt > 3:
			var i := randi() % nt
			var jk := []
			for j in cand.get("jumps", []): jk.append(int(j["k"]))
			if i in jk or ((i - 1 + nt) % nt) in jk: continue
			turns.remove_at(i)
			for j in cand.get("jumps", []):
				if int(j["k"]) >= i: j["k"] = int(j["k"]) - 1
		elif roll < 0.14:
			var i := randi() % nt
			turns[i][2] = -turns[i][2]
		else:
			var i := randi() % nt
			var t: Array = turns[i]
			var dx := roundf(randf_range(-step, step)); var dy := roundf(randf_range(-step, step))
			var ox = t[0]; var oy = t[1]
			for u in turns:
				if absf(u[0] - ox) < 1 and absf(u[1] - oy) < 1:
					u[0] += dx; u[1] += dy
		var nk := cost(cand)
		if nk["k"] < ck["k"] or randf() < exp((ck["k"] - nk["k"]) / temp):
			cur = cand; ck = nk
			if nk["k"] < bk["k"]:
				best = cand; bk = nk
		temp *= 0.999
		if it % 400 == 399:
			step = maxf(50.0, step * 0.85)
			printerr("%d it=%d k=%d bad=%d br=%d n=%d strs=%s" % [ti, it, bk["k"], bk["c"]["bad"], bk["c"]["bridges"], best["turns"].size(), str(bk["strs"].map(func(x): return roundi(x)))])
	printerr("%s best k=%d bad=%d (base %d) bridges=%d (base %d) L=%d (base %d)" % [orig["name"], bk["k"], bk["c"]["bad"], base["bad"], bk["c"]["bridges"], base["bridges"], bk["c"]["L"], base["L"]])
	var f := FileAccess.open(a[3], FileAccess.WRITE)
	f.store_string(JSON.stringify({ "turns": best["turns"], "jumps": best.get("jumps", []), "k": bk["k"], "strs": bk["strs"] }))
	quit()
