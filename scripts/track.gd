# Track geometry, ported from buildTrack() in the JS prototype (v32).
# Everything here is in 2D world units (the prototype's coordinates): x right,
# y "south". The 3D view maps (x, y) to (x, height, y) / 100.
extends RefCounted

const HW := 150.0          # track half width
const CR := 36.0           # car collision radius
const TURN_R := 350.0      # centreline radius: inner kerb 200, outer kerb 500
const GAP := 170.0         # length of the gap a jump clears
const GRID_ROWS := [90.0, 240.0]
const BRIDGE_H := 160.0    # visual deck height of a bridge (world units)
const RAMP := 520.0        # visual length of the slope up to a bridge deck

class Anchor:
	var pos: Vector2
	var r: float
	var clear: float
	var entry: int
	var exit: int
	var mid: int
	var exit_dir: Vector2
	var sign: float
	var spin: float
	var omega: float
	var total: float
	var home: int

var def: Dictionary
var variant: String
var P := PackedVector2Array()
var n := 0
var seg_dir := PackedVector2Array()
var seg_len := PackedFloat64Array()
var seg_s0 := PackedFloat64Array()
var L := 0.0
var anchors: Array = []
var straights: Array = []   # {k, s0, len}
var arcs: Array = []
var bridges: Array = []     # {from, to, under, c}
var level_of := PackedInt32Array()
var height_of := PackedFloat32Array()
var bounds := Rect2()
var jumps: Array = []       # {s, pos, dir, lvl}
var start_s := 0.0
var obstacles: Array = []   # {pos, r, s, normal, gone}
var tokens: Array = []      # {pos, lvl, s}

# spatial hash of segments, for fast nearest-point queries
const CELL := 300.0
var _grid := {}

static func perp(v: Vector2) -> Vector2:
	return Vector2(-v.y, v.x)

func wrap_s(v: float) -> float:
	return fposmod(v, L)

func _init(d: Dictionary, var_name: String = "standard") -> void:
	def = d
	variant = var_name
	_build()

func _build() -> void:
	var rev := variant == "reverse"
	var tl: Array = []
	for t in def["turns"]:
		tl.append({ "p": Vector2(t[0], t[1]), "s": float(t[2]), "r": float(t[3]) if t.size() > 3 else TURN_R })
	if rev:
		tl.reverse()
		for t in tl:
			t["s"] = -t["s"]
	var turns := tl
	var nt := turns.size()
	# tangent leaving turn A towards turn B
	var lines: Array = []
	for i in nt:
		var A: Dictionary = turns[i]
		var B: Dictionary = turns[(i + 1) % nt]
		lines.append(_tangent(A["p"], A["s"], A["r"], B["p"], B["s"], B["r"]))
	var spans: Array = []
	for i in nt:
		var A: Dictionary = turns[i]
		var inL: Dictionary = lines[(i - 1 + nt) % nt]
		var outL: Dictionary = lines[i]
		var c: Vector2 = A["p"]
		var r: float = A["r"]
		var sg: float = A["s"]
		var a0: float = (inL["to"] - c).angle()
		var a1: float = (outL["from"] - c).angle()
		var sweep := fposmod((a1 - a0) * sg, TAU)
		var steps := maxi(2, ceili(sweep * r / 30.0))
		var entry := P.size()
		for k in steps:
			var th := a0 + sg * sweep * k / steps
			P.append(c + Vector2(cos(th), sin(th)) * r)
		var exit := P.size()
		var f: Vector2 = outL["from"]
		var to: Vector2 = outL["to"]
		var ls := maxi(1, ceili(f.distance_to(to) / 70.0))
		for k in ls:
			P.append(f + (to - f) * float(k) / ls)
		spans.append({ "entry": entry, "exit": exit, "sweep": sweep, "t": outL["t"] })
	n = P.size()
	var s := 0.0
	seg_dir.resize(n); seg_len.resize(n); seg_s0.resize(n)
	for i in n:
		var a := P[i]
		var b := P[(i + 1) % n]
		var ln := a.distance_to(b)
		if ln <= 0.0:
			ln = 1.0
		seg_dir[i] = (b - a) / ln
		seg_len[i] = ln
		seg_s0[i] = s
		s += ln
	L = s
	_build_grid()

	for i in nt:
		var A: Dictionary = turns[i]
		var an := Anchor.new()
		an.pos = A["p"]; an.r = A["r"]; an.clear = an.r - HW
		an.entry = spans[i]["entry"]; an.exit = spans[i]["exit"]
		an.mid = an.entry + int((an.exit - an.entry) / 2)
		an.exit_dir = spans[i]["t"]; an.sign = A["s"]
		an.spin = randf() * 6.0; an.omega = an.sign * 1.4
		an.total = spans[i]["sweep"]
		anchors.append(an)
	# a tower can carry two curves (an inner and an outer one): those turns share one rotor
	for an in anchors:
		for j in anchors.size():
			if anchors[j].pos.distance_to(an.pos) < 1.0:
				an.home = j
				break
	for k in nt:
		var a: Anchor = anchors[k]
		var nx: Anchor = anchors[(k + 1) % nt]
		var s0 := seg_s0[a.exit]
		straights.append({ "k": k, "s0": s0, "len": wrap_s(seg_s0[nx.entry] - s0) })
		var s1 := seg_s0[a.entry]
		arcs.append({ "k": k, "s0": s1, "len": wrap_s(seg_s0[a.exit] - s1) })

	_find_bridges()
	level_of.resize(n)
	for i in n:
		level_of[i] = _level_slow(i)
	var xs0 := INF; var ys0 := INF; var xs1 := -INF; var ys1 := -INF
	for p in P:
		xs0 = minf(xs0, p.x); ys0 = minf(ys0, p.y); xs1 = maxf(xs1, p.x); ys1 = maxf(ys1, p.y)
	var m := HW + 40.0
	bounds = Rect2(xs0 - m, ys0 - m, xs1 - xs0 + 2 * m, ys1 - ys0 + 2 * m)

	# jumps: a ramp, then a gap across the whole road. In reverse the same straight is used the other way.
	for j in def.get("jumps", []):
		var k: int = (2 * nt - 2 - int(j["k"])) % nt if rev else int(j["k"])
		var f: float = 1.0 - float(j.get("f", 0.5)) if rev else float(j.get("f", 0.5))
		var st: Dictionary = straights[k]
		var sj := wrap_s(st["s0"] + st["len"] * f - GAP / 2.0)
		var q := point_at(sj)
		jumps.append({ "s": sj, "pos": q["pos"], "dir": q["dir"], "lvl": level_of[q["i"]] })

	_place_start()
	if variant == "obstacles":
		_place_obstacles()
	if variant == "collect":
		_place_tokens(turns)
	_build_heights()

static func _tangent(Ap: Vector2, As: float, Ar: float, Bp: Vector2, Bs: float, Br: float) -> Dictionary:
	var D := Bp - Ap
	var D2 := D.length_squared()
	var k := Bs * Br - As * Ar
	var Ln := sqrt(maxf(1.0, D2 - k * k))
	var pd := perp(D)
	var t := (Ln * D - k * pd) / D2
	var pt := perp(t)
	return { "t": t, "from": Ap - As * Ar * pt, "to": Bp - Bs * Br * pt }

# ---------- queries ----------
func point_at(sv: float) -> Dictionary:
	sv = fposmod(sv, L)
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if seg_s0[mid] <= sv:
			lo = mid
		else:
			hi = mid - 1
	var t := sv - seg_s0[lo]
	return { "pos": P[lo] + seg_dir[lo] * t, "dir": seg_dir[lo], "i": lo }

func s_of(i: int, t: float) -> float:
	return seg_s0[i] + t * seg_len[i]

# nearest point on segment i; returns [d, t, px, py] packed into a Dictionary
func seg_near(i: int, p: Vector2, best: Dictionary) -> Dictionary:
	var a := P[i]
	var dir := seg_dir[i]
	var ln := seg_len[i]
	var t := clampf((p - a).dot(dir) / ln, 0.0, 1.0)
	var q := a + dir * ln * t
	var d := p.distance_to(q)
	if best.is_empty() or d < best["d"]:
		return { "i": i, "t": t, "p": q, "d": d }
	return best

func _build_grid() -> void:
	_grid.clear()
	for i in n:
		var mid := P[i] + seg_dir[i] * seg_len[i] * 0.5
		var key := Vector2i(floori(mid.x / CELL), floori(mid.y / CELL))
		if not _grid.has(key):
			_grid[key] = PackedInt32Array()
		_grid[key].append(i)

func nearest_raw(p: Vector2) -> Dictionary:
	var best := {}
	var cx := floori(p.x / CELL)
	var cy := floori(p.y / CELL)
	for gx in range(cx - 1, cx + 2):
		for gy in range(cy - 1, cy + 2):
			var key := Vector2i(gx, gy)
			if _grid.has(key):
				for i in _grid[key]:
					best = seg_near(i, p, best)
	if not best.is_empty() and best["d"] <= CELL - 40.0:
		return best
	best = {}
	for i in n:
		best = seg_near(i, p, best)
	return best

func nearest(p: Vector2, hint: int) -> Dictionary:
	if hint < 0:
		return nearest_raw(p)
	var b := {}
	for k in range(-14, 15):
		b = seg_near((hint + k + n) % n, p, b)
	if b["d"] > HW * 1.3:
		return nearest_raw(p)
	return b

# ---------- bridges ----------
static func _cross(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> bool:
	var d := func(p: Vector2, q: Vector2, r: Vector2) -> float:
		return (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x)
	return d.call(a0, a1, b0) * d.call(a0, a1, b1) < 0.0 and d.call(b0, b1, a0) * d.call(b0, b1, a1) < 0.0

func in_span(i: int, B: Dictionary) -> bool:
	return posmod(i - int(B["from"]), n) <= posmod(int(B["to"]) - int(B["from"]), n)

# wherever the road crosses itself, the later pass goes over on a bridge
# (same scan order as the prototype; a spatial hash only prunes far pairs)
func _find_bridges() -> void:
	for a in n:
		var cands: Array[int] = []
		var ca := Vector2i(floori(P[a].x / CELL), floori(P[a].y / CELL))
		for gx in range(ca.x - 1, ca.x + 2):
			for gy in range(ca.y - 1, ca.y + 2):
				var key := Vector2i(gx, gy)
				if _grid.has(key):
					for b in _grid[key]:
						if b >= a + 30:
							cands.append(b)
		cands.sort()
		for b in cands:
			if n - (b - a) < 30:
				continue
			var skip := false
			for B in bridges:
				if in_span(b, B) or in_span(a, B):
					skip = true
					break
			if skip:
				continue
			if _cross(P[a], P[(a + 1) % n], P[b], P[(b + 1) % n]) or P[a].distance_to(P[b]) < 30.0:
				var span := ceili(HW * 1.9 / seg_len[b])
				bridges.append({ "from": posmod(b - span, n), "to": (b + span) % n, "under": a, "c": P[b] })

func _level_slow(i: int) -> int:
	for k in bridges.size():
		if in_span(i, bridges[k]):
			return k + 1
	return 0

func level(i: int) -> int:
	return level_of[i]

func _hidden(pos: Vector2, i: int) -> bool:
	if level_of[i] != 0:
		return false
	for k in n:
		if level_of[k] != 0 and P[k].distance_to(pos) < HW + 60.0:
			return true
	return false

func _near_crossing(pos: Vector2, m: float) -> bool:
	for B in bridges:
		if pos.distance_to(B["c"]) < HW * 2.0 + m:
			return true
	return false

func near_jump(sv: float, before: float, after: float) -> bool:
	for j in jumps:
		var d := wrap_s(sv - j["s"])
		if d < GAP + after or L - d < before:
			return true
	return false

# ---------- start line: always on a straight, grid visible, never under a deck ----------
func _place_start() -> void:
	var best := -INF
	start_s = 0.0
	for st in straights:
		var stl: float = st["len"]
		var d := minf(stl, 20.0)
		while d <= stl - 10.0:
			var cand := wrap_s(st["s0"] + d)
			var q := point_at(cand)
			if level_of[q["i"]] != 0 or _hidden(q["pos"], q["i"]):
				d += 10.0
				continue
			var score := stl * 0.2 - absf(d - (stl - maxf(40.0, stl * 0.1))) * 0.05
			if near_jump(cand, 450.0, 150.0):
				score -= 3000.0
			for back in GRID_ROWS:
				var g := point_at(cand - back)
				if d - back < 0.0:
					score -= 300.0
				if _hidden(g["pos"], g["i"]) or level_of[g["i"]] != 0:
					score -= 1000.0
				if near_jump(cand - back, 300.0, 150.0):
					score -= 3000.0
			if score > best:
				best = score
				start_s = cand
			d += 10.0

func near_start(sv: float) -> bool:
	var d := wrap_s(sv - start_s)
	return d < 260.0 or L - d < 380.0

func _visible_spot(sv: float, pos: Vector2, i: int) -> bool:
	return not near_start(sv) and not near_jump(sv, 260.0, 120.0) and level_of[i] == 0 \
		and not _hidden(pos, i) and not _near_crossing(pos, 0.0)

# Obstacles variant: small static posts, always against a wall so the middle of the
# road stays clear. Straights alternate sides; long bends get one on the outside wall.
func _place_obstacles() -> void:
	var c := 0
	for st in straights:
		if st["len"] < 200.0:
			continue
		var sv := wrap_s(st["s0"] + st["len"] * 0.5)
		var q := point_at(sv)
		if not _visible_spot(sv, q["pos"], q["i"]):
			continue
		var nrm := perp(q["dir"])
		var off := (1.0 if c % 2 else -1.0) * (HW - 38.0)
		obstacles.append({ "pos": q["pos"] + nrm * off, "r": 32.0, "s": sv, "gone": false })
		c += 1
	for k in arcs.size():
		var ar: Dictionary = arcs[k]
		var sv := wrap_s(ar["s0"] + ar["len"] * 0.5)
		var q := point_at(sv)
		var a: Anchor = anchors[k]
		if ar["len"] < 500.0 or not _visible_spot(sv, q["pos"], q["i"]):
			continue
		var u: Vector2 = (q["pos"] - a.pos) / a.r
		obstacles.append({ "pos": q["pos"] + u * (HW - 38.0), "r": 32.0, "s": sv, "gone": false })

# Collect variant: rows of gems trace one racing line, circling each tower a little
# inside or outside the middle of the road with tangent straights between.
func _place_tokens(turns: Array) -> void:
	var nt := turns.size()
	var offs: Array[float] = []
	for k in nt:
		offs.append(70.0 if k % 2 else -70.0)
	var line_of := func() -> Dictionary:
		var C: Array = []
		for k in nt:
			C.append({ "p": turns[k]["p"], "s": turns[k]["s"], "r": turns[k]["r"] + offs[k] })
		var segs2: Array = []
		for i in nt:
			var A: Dictionary = C[i]
			var B: Dictionary = C[(i + 1) % nt]
			segs2.append(_tangent(A["p"], A["s"], A["r"], B["p"], B["s"], B["r"]))
		var arcs2: Array = []
		for i in nt:
			var A: Dictionary = C[i]
			var inL: Dictionary = segs2[(i - 1 + nt) % nt]
			var outL: Dictionary = segs2[i]
			var a0: float = (inL["to"] - A["p"]).angle()
			var a1: float = (outL["from"] - A["p"]).angle()
			arcs2.append({ "A": A, "a0": a0, "sweep": fposmod((a1 - a0) * A["s"], TAU) })
		return { "segs2": segs2, "arcs2": arcs2 }
	# keep the line inside the road: drop the offset of any turn whose links stray too wide
	for pass_i in 3:
		var segs2: Array = line_of.call()["segs2"]
		for i in segs2.size():
			var g: Dictionary = segs2[i]
			var u := 0.0
			while u <= 1.001:
				var x: Vector2 = g["from"] + (g["to"] - g["from"]) * u
				if nearest_raw(x)["d"] > HW - CR - 15.0:
					offs[i] = 0.0
					offs[(i + 1) % nt] = 0.0
					break
				u += 0.1
	var lo: Dictionary = line_of.call()
	var row := func(pts: Array) -> void:
		for p in pts:
			var nr := nearest_raw(p)
			var sv := s_of(nr["i"], nr["t"])
			if nr["d"] > HW - CR or near_start(sv) or _hidden(p, nr["i"]) or near_jump(sv, 200.0, 60.0):
				continue
			tokens.append({ "pos": p, "lvl": level_of[nr["i"]], "s": sv })
	var SP := 115.0
	for i in nt:
		var ar: Dictionary = lo["arcs2"][i]
		var A: Dictionary = ar["A"]
		var r: float = A["r"]
		var sweep: float = ar["sweep"]
		var ln := sweep * r
		var n2 := mini(9, maxi(3, floori(ln / SP)))
		var mid := sweep / 2.0
		var pts: Array = []
		for k in n2:
			var th: float = ar["a0"] + A["s"] * (mid + (k - (n2 - 1) / 2.0) * SP / r)
			pts.append(A["p"] + Vector2(cos(th), sin(th)) * r)
		row.call(pts)
		var g: Dictionary = lo["segs2"][i]
		var gl: float = (g["to"] - g["from"]).length()
		if gl > 2.0 * SP:
			var n3 := mini(7, floori(gl / SP))
			var pts2: Array = []
			for k in n3:
				var u := 0.5 + (k - (n3 - 1) / 2.0) * SP / gl
				pts2.append(g["from"] + (g["to"] - g["from"]) * u)
			row.call(pts2)

# ---------- visual heights (3D only; gameplay uses the bridge level index) ----------
# Bridge decks sit BRIDGE_H up with smooth ramps either side. A pass that runs under
# another bridge is pinned to the ground there, so packed knots never collide.
func _arc_dist(i: int, B: Dictionary) -> float:
	if in_span(i, B):
		return 0.0
	var s := seg_s0[i]
	var d0 := wrap_s(seg_s0[int(B["from"])] - s)   # ahead to deck start
	var d1 := wrap_s(s - seg_s0[int(B["to"])])     # behind deck end
	return minf(d0, d1)

func _build_heights() -> void:
	height_of.resize(n)
	for i in n:
		var h := 0.0
		for B in bridges:
			var d := _arc_dist(i, B)
			if d < RAMP:
				var u := 1.0 - d / RAMP
				h = maxf(h, BRIDGE_H * u * u * (3.0 - 2.0 * u))
		height_of[i] = h
	# pin under-passes to the ground
	for B in bridges:
		var u_i: int = B["under"]
		var su := seg_s0[u_i]
		for i in n:
			var d := absf(seg_s0[i] - su)
			d = minf(d, L - d)
			if d < HW * 2.2:
				height_of[i] = 0.0
			elif d < HW * 2.2 + RAMP * 0.6:
				var u := (d - HW * 2.2) / (RAMP * 0.6)
				height_of[i] = minf(height_of[i], BRIDGE_H * u * u * (3.0 - 2.0 * u))

func height_at(sv: float) -> float:
	sv = fposmod(sv, L)
	var q := point_at(sv)
	var i: int = q["i"]
	var t := (sv - seg_s0[i]) / seg_len[i]
	return lerpf(height_of[i], height_of[(i + 1) % n], t)
