extends SceneTree
# Regenerates scripts/obstacle_spots.gd: where the posts of the Obstacles variant stand.
# Posts sit off the racing line and on the sloppy ones. On the plain layout the AI drives
#  - good laps: sharp hook timing and its usual release, a few seeds. The lateral band they
#    use along the track (plus the car, the post and a safety gap) is kept clear of posts,
#    so a good line never has to dodge one;
#  - sloppy laps: hooks too early or too late, releases too early or too late.
# Each bend gets at most one post, in the bend or on the link out of it, at the spot the
# most sloppy laps run over while staying clear of the good band.
# Usage: godot --headless --path . --script tools/gen_obstacles.gd [-- --dump=<file.json>]
const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")

const BIN := 20.0          # band resolution along the track
const POST_R := 32.0
# gap between a car on the good band's edge and the post: the widest that still leaves at
# least one post per two bends (a track whose good laps use most of the road gets less)
const CLEARS := [40.0, 30.0, 20.0]
const HW_IN := TrackData.HW - 38.0  # furthest out a post stands (touching the wall)
const SPACING := 420.0     # minimum track distance between two posts
const MIN_SLOPPY := 3      # a post must catch at least this many sloppy laps
# good laps: [hook skill, seed]. 1.0 is sharp; 0.96 still hooks within ~25 units of ideal.
# Seeds 1000-1002 are the runs tools/gen_medals.gd takes its reference laps from, so the
# fastest line the medals are built on is always clear of posts.
const GOOD := [[1.0, 1000], [1.0, 1001], [1.0, 1002], [1.0, 11], [1.0, 12], [1.0, 13], [1.0, 14],
	[1.0, 15], [1.0, 16], [0.98, 17], [0.98, 18], [0.98, 19], [0.96, 20], [0.96, 21], [0.96, 22]]
const N_SLOPPY := 16

# Drives one run; release < -9 = the AI's own release, else release when the velocity is
# that many radians short of the bend's exit direction (picked per bend in [lo, hi]).
func drive(d: Dictionary, skill: float, sd: int, rel: Vector2) -> Array:
	seed(sd)
	# built after seeding, like tools/gen_medals.gd does, so seeds give the same runs there
	var tr := TrackData.new(d, "standard")
	var race := Race.new(tr, "trial", 1)
	var c = race.cars[0]
	c.skill = skill
	var dt := 1.0 / 60.0
	var laps: Array = []   # per lap: [s, lat] samples
	var cur: Array = []
	var target := 0.0
	var was_hooked := false
	while race.clock < 400.0 and not c.finished:
		if rel.x < -9.0 or c.hook < 0:
			race.ai_think(c)
		else:
			var a: TrackData.Anchor = tr.anchors[c.hook]
			var past_mid: bool = posmod(c.seg - a.mid, tr.n) < tr.n / 2
			var rem: float = c.vel.angle_to(a.exit_dir) * c.turn_sign
			if c.swung > a.total + 0.8 or c.vel.length() < 150.0:
				race.detach(c, true)
			elif past_mid and rem <= target:
				race.detach(c, true)
		if c.hook >= 0 and not was_hooked and rel.x > -9.0:  # good runs draw nothing: same RNG as gen_medals
			target = randf_range(rel.x, rel.y)
		was_hooked = c.hook >= 0
		race.inputs[0]["held"] = c.hook >= 0
		var lap0: int = c.lap
		race.update(dt)
		race.events.clear()
		if c.lap != lap0:
			if lap0 >= 1:
				laps.append(cur)
			cur = []
		if c.lap < 1 or c.air > 0.0 or c.fall > 0.0:
			continue
		var nr := tr.nearest(c.pos, c.seg)
		var i: int = nr["i"]
		cur.append(Vector3(tr.s_of(i, nr["t"]), (c.pos - tr.P[i]).dot(TrackData.perp(tr.seg_dir[i])), 1.0 if c.hook >= 0 else 0.0))
		cur.append(c.pos)
	return laps

# per bin lateral [lo, hi] of a set of laps (samples alternate Vector3 info, Vector2 pos)
func band(tr: TrackData, laps: Array, grow: int) -> Array:
	var nb := ceili(tr.L / BIN)
	var lo := PackedFloat32Array(); lo.resize(nb); lo.fill(INF)
	var hi := PackedFloat32Array(); hi.resize(nb); hi.fill(-INF)
	for lap in laps:
		for k in range(0, lap.size(), 2):
			var v: Vector3 = lap[k]
			var b := int(v.x / BIN) % nb
			lo[b] = minf(lo[b], v.y); hi[b] = maxf(hi[b], v.y)
	var lo2 := lo.duplicate(); var hi2 := hi.duplicate()
	for b in nb:
		for k in range(-grow, grow + 1):
			var j := (b + k + nb) % nb
			if lo[j] < INF:
				lo2[b] = minf(lo2[b], lo[j]); hi2[b] = maxf(hi2[b], hi[j])
	return [lo2, hi2]

func post_ok(tr: TrackData, good: Array, sv: float, lat: float, clear: float):
	var nb: int = good[0].size()
	var need := TrackData.CR + POST_R + clear
	for k in range(-4, 5):
		var b := (int(sv / BIN) + k + nb) % nb
		if good[0][b] == INF:
			return null
		if lat < good[1][b] + need and lat > good[0][b] - need:
			return null
	var q := tr.point_at(sv)
	var pos: Vector2 = q["pos"] + TrackData.perp(q["dir"]) * lat
	if not tr._visible_spot(sv, pos, q["i"]):
		return null
	# never on another road (shared towers, close links)
	var nr := tr.nearest_raw(pos)
	if absf(tr.wrap_s(tr.s_of(nr["i"], nr["t"]) - sv + 300.0) - 300.0) > 60.0:
		return null
	return pos

func sdist(tr: TrackData, a: float, b: float) -> float:
	return absf(tr.wrap_s(a - b + tr.L / 2.0) - tr.L / 2.0)

func spots_of(tr: TrackData, good: Array, sloppy: Array, clear: float) -> Array:
	# sloppy laps indexed by bin for counting
	var nb: int = good[0].size()
	var by_bin: Array = []
	by_bin.resize(nb)
	for b in nb:
		by_bin[b] = []
	for li in sloppy.size():
		var lap: Array = sloppy[li]
		for k in range(0, lap.size(), 2):
			by_bin[int(lap[k].x / BIN) % nb].append([li, lap[k + 1]])
	var hit_r := TrackData.CR + POST_R
	var out: Array = []
	for k in tr.arcs.size():
		var s0: float = tr.arcs[k]["s0"]
		var ln := tr.wrap_s(tr.arcs[(k + 1) % tr.arcs.size()]["s0"] - s0)
		var best = null
		var best_sc := -INF
		var sv := 0.0
		while sv < ln:
			var s := tr.wrap_s(s0 + sv)
			var far := INF
			for o in out:
				far = minf(far, sdist(tr, s, o["s"]))
			if far >= SPACING:
				var lat := -HW_IN
				while lat <= HW_IN:
					var pos = post_ok(tr, good, s, lat, clear)
					if pos != null:
						var caught := {}
						var b0 := int(s / BIN)
						for db in range(-3, 4):
							for e in by_bin[(b0 + db + nb) % nb]:
								if e[1].distance_to(pos) < hit_r:
									caught[e[0]] = true
						# most sloppy laps caught; then closer to the wall (reads as roadside)
						var sc := caught.size() * 100.0 + absf(lat) * 0.1
						if caught.size() >= MIN_SLOPPY and sc > best_sc:
							best_sc = sc
							best = { "s": s, "lat": lat, "pos": pos, "caught": caught.size() }
					lat += 10.0
			sv += BIN
		if best != null:
			out.append(best)
	out.sort_custom(func(a, b): return a["s"] < b["s"])
	return out

func _init() -> void:
	var dump := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dump="):
			dump = a.substr(7)
	var out := "# Generated by tools/gen_obstacles.gd: Obstacles posts as [track distance, lateral offset\n"
	out += "# (+ = left of the racing direction)], off the AI's racing line and on sloppy ones.\n"
	out += "# Rerun the tool after changing a layout.\nextends RefCounted\n\nconst SPOTS := {\n"
	var js := {}
	for d in Defs.TRACKS:
		var tr := TrackData.new(d, "standard")
		var good_laps: Array = []
		for r in GOOD:
			good_laps += drive(d, r[0], r[1], Vector2(-99, -99))
		var sloppy: Array = []
		for k in N_SLOPPY:
			# half the runs hook badly, half release badly, a few do both
			var skill := 0.8 if k % 2 == 0 or k % 5 == 0 else 1.0
			var rel := Vector2(-0.3, 0.7) if k % 2 == 1 or k % 5 == 0 else Vector2(-99, -99)
			sloppy += drive(d, skill, 100 + k, rel)
		var good := band(tr, good_laps, 2)
		var sp: Array = []
		var used := 0.0
		for cl in CLEARS:
			used = cl
			sp = spots_of(tr, good, sloppy, cl)
			if sp.size() * 2 >= tr.arcs.size():
				break
		var row := "\t\"%s\": [" % d["name"]
		for o in sp:
			row += "[%.0f, %.0f], " % [o["s"], o["lat"]]
		out += row + "],\n"
		printerr("%s: clear %d, %d posts, sloppy laps caught %s of %d" % [d["name"], used, sp.size(), str(sp.map(func(o): return o["caught"])), sloppy.size()])
		if dump != "":
			var old := TrackData.new(d, "obstacles")
			var pts := func(laps: Array, n: int) -> Array:
				var res: Array = []
				for lap in laps.slice(0, n):
					var l2: Array = []
					for k in range(1, lap.size(), 4):
						l2.append([lap[k].x, lap[k].y])
					res.append(l2)
				return res
			js[d["name"]] = {
				"P": Array(tr.P).map(func(p): return [p.x, p.y]),
				"lvl": Array(tr.level_of),
				"towers": tr.anchors.map(func(a): return [a.pos.x, a.pos.y]),
				"old": old.obstacles.map(func(o): return [o["pos"].x, o["pos"].y]),
				"new": sp.map(func(o): return [o["pos"].x, o["pos"].y]),
				"good": pts.call(good_laps, 6),
				"sloppy": pts.call(sloppy, 12),
			}
	out += "}\n"
	var f := FileAccess.open("res://scripts/obstacle_spots.gd", FileAccess.WRITE)
	f.store_string(out)
	f.close()
	if dump != "":
		var g := FileAccess.open(dump, FileAccess.WRITE)
		g.store_string(JSON.stringify(js))
		g.close()
	quit()
