extends SceneTree
# Regenerates scripts/obstacle_spots.gd: where the posts of the Obstacles variant stand.
# Posts sit off the racing line and on the sloppy ones. On the plain layout the AI drives
#  - good laps: sharp hook timing and its usual release, many seeds, keeping each lap up
#    to its first wall bump (the medal runs in full, so medal times are unaffected). The
#    lateral band they use along the track (plus the car, the post and a safety gap) is
#    kept clear of posts, so a good line never has to dodge one;
#  - sloppy laps: hooks too early or too late, releases too early or too late.
# Each bend gets at most one group of 2-4 posts, in the bend or on the link out of it, at
# the spot the most sloppy laps run over while every post stays clear of the good band.
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
# good laps: 70% sharp runs (skill 1.0), then 0.98 and 0.96 (hooks within ~25 units of ideal).
# Seeds 1000-1002 are the runs tools/gen_medals.gd takes its reference laps from, so the
# fastest line the medals are built on is always clear of posts.
const GOOD_MEDAL := [1000, 1001, 1002]
const N_GOOD := 60   # the AI's line is chaotic: rare variants need many runs to show up
const N_SLOPPY := 16
const VALIDATE_RUNS := 20
const VALIDATE_ROUNDS := 4

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
	# per lap: { pts (all samples), good (samples until the lap's first wall bump), t (lap time) }
	var laps: Array = []
	var cur: Array = []
	var good: Array = []
	var clean := true
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
		for e in race.events:
			if e["t"] == "wall":
				clean = false
		race.events.clear()
		if c.lap != lap0:
			if lap0 >= 1:
				laps.append({ "pts": cur, "good": good, "t": c.laps[-1] if c.laps.size() > 0 else INF })
			cur = []
			good = []
			clean = true
		if c.lap < 1 or c.air > 0.0 or c.fall > 0.0:
			continue
		var nr := tr.nearest(c.pos, c.seg)
		var i: int = nr["i"]
		cur.append(Vector3(tr.s_of(i, nr["t"]), (c.pos - tr.P[i]).dot(TrackData.perp(tr.seg_dir[i])), 1.0 if c.hook >= 0 else 0.0))
		cur.append(c.pos)
		if clean:
			good.append(cur[-2]); good.append(cur[-1])
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

# a group around a base post: a few posts staggered along the road and out towards the wall,
# each one still clear of the good band (offsets: [along, outwards])
const GROUP := [[0.0, 0.0], [75.0, 65.0], [-75.0, 65.0], [0.0, 130.0], [150.0, 0.0], [-150.0, 0.0]]
const GROUP_MAX := 4

func group_at(tr: TrackData, good: Array, s: float, lat: float, clear: float) -> Array:
	var nb: int = good[0].size()
	var b := int(s / BIN) % nb
	var out_sd := 1.0 if lat > (good[0][b] + good[1][b]) * 0.5 else -1.0
	var posts: Array = []
	for g in GROUP:
		var s2 := tr.wrap_s(s + g[0])
		var l2: float = lat + out_sd * g[1]
		if absf(l2) > HW_IN:
			continue
		var pos = post_ok(tr, good, s2, l2, clear)
		if pos != null:
			posts.append({ "s": s2, "lat": l2, "pos": pos })
		if posts.size() >= GROUP_MAX:
			break
	return posts

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
	var out: Array = []   # groups: { s, posts, caught }
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
					if post_ok(tr, good, s, lat, clear) != null:
						var posts := group_at(tr, good, s, lat, clear)
						if posts.size() >= 2:
							var caught := {}
							for p in posts:
								var b0 := int(p["s"] / BIN)
								for db in range(-3, 4):
									for e in by_bin[(b0 + db + nb) % nb]:
										if e[1].distance_to(p["pos"]) < hit_r:
											caught[e[0]] = true
							# most sloppy laps caught; then bigger groups
							var sc := caught.size() * 100.0 + posts.size() * 30.0
							if caught.size() >= MIN_SLOPPY and sc > best_sc:
								best_sc = sc
								best = { "s": s, "posts": posts, "caught": caught.size() }
					lat += 10.0
			sv += BIN
		if best != null:
			out.append(best)
	out.sort_custom(func(a, b): return a["s"] < b["s"])
	return out

func drive_all(d: Dictionary, good_laps: Array, sloppy: Array) -> void:
	# good line = every lap up to its first wall bump, plus the medal runs in full
	for k in N_GOOD:
		var sd: int = GOOD_MEDAL[k] if k < GOOD_MEDAL.size() else 10 + k
		var skill := 1.0 if k < N_GOOD * 7 / 10 else (0.98 if k < N_GOOD * 85 / 100 else 0.96)
		for lp in drive(d, skill, sd, Vector2(-99, -99)):
			good_laps.append(lp["pts"] if k < GOOD_MEDAL.size() else lp["good"])
	for k in N_SLOPPY:
		# half the runs hook badly, half release badly, a few do both
		var skill := 0.8 if k % 2 == 0 or k % 5 == 0 else 1.0
		var rel := Vector2(-0.3, 0.7) if k % 2 == 1 or k % 5 == 0 else Vector2(-99, -99)
		for lp in drive(d, skill, 100 + k, rel):
			sloppy.append(lp["pts"])

func _init() -> void:
	var dump := ""
	var cache := ""  # dir: keeps each track's driven laps, to retune placement without re-driving
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dump="):
			dump = a.substr(7)
		if a.begins_with("--cache="):
			cache = a.substr(8)
	var out := "# Generated by tools/gen_obstacles.gd: Obstacles posts as [track distance, lateral offset\n"
	out += "# (+ = left of the racing direction)], off the AI's racing line and on sloppy ones.\n"
	out += "# Rerun the tool after changing a layout.\nextends RefCounted\n\nconst SPOTS := {\n"
	var js := {}
	for d in Defs.TRACKS:
		var tr := TrackData.new(d, "standard")
		var cf: String = cache.path_join(String(d["name"]).replace(" ", "_") + ".bin") if cache != "" else ""
		var good_laps: Array = []
		var sloppy: Array = []
		if cf != "" and FileAccess.file_exists(cf):
			var fr := FileAccess.open(cf, FileAccess.READ)
			var v: Array = fr.get_var()
			good_laps = v[0]; sloppy = v[1]
		else:
			drive_all(d, good_laps, sloppy)
			if cf != "":
				DirAccess.make_dir_recursive_absolute(cache)
				var fw := FileAccess.open(cf, FileAccess.WRITE)
				fw.store_var([good_laps, sloppy])
		var sp: Array = []
		var used := 0.0
		# place, then check on fresh runs: a clean stretch that comes near a post joins the
		# good band and the posts are placed again (the AI's line has rare variants)
		var vseed := 2000
		for attempt in VALIDATE_ROUNDS + 1:
			var good := band(tr, good_laps, 2)
			for cl in CLEARS:
				used = cl
				sp = spots_of(tr, good, sloppy, cl)
				if sp.size() * 2 >= tr.arcs.size():
					break
			if attempt == VALIDATE_ROUNDS:
				break
			var near := 0
			for k in VALIDATE_RUNS:
				for lp in drive(d, 1.0, vseed, Vector2(-99, -99)):
					var pts: Array = lp["good"]
					var hit := false
					for i in range(1, pts.size(), 2):
						for o in sp:
							for p in o["posts"]:
								if pts[i].distance_to(p["pos"]) < TrackData.CR + POST_R + 10.0:
									hit = true
					if hit:
						near += 1
						good_laps.append(pts)
				vseed += 1
			printerr("  %s round %d: %d clean laps came near a post" % [d["name"], attempt, near])
			if near == 0:
				break
		var row := "\t\"%s\": [" % d["name"]
		for o in sp:
			for p in o["posts"]:
				row += "[%.0f, %.0f], " % [p["s"], p["lat"]]
		out += row + "],\n"
		printerr("%s: clear %d, %d groups, sloppy laps caught %s of %d" % [d["name"], used, sp.size(), str(sp.map(func(o): return o["caught"])), sloppy.size()])
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
				"new": sp.reduce(func(acc, o): return acc + o["posts"].map(func(p): return [p["pos"].x, p["pos"].y]), []),
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
