# The things lying on the track: obstacle posts (Obstacles variant) and gems (Collect).
# Each world dresses them its own way; the look only, never the size or the rules
# (a post is still a 32-radius post that costs 1 s and shatters, a gem is still a gem).
#   snow: a snowman (post), an ice crystal (gem)
#   forest: a red toadstool, a golden acorn
#   sand: a terracotta jar, a gold coin
#   rock: a cairn with a painted marker stone, an amethyst cluster
# Meshes are single vertex-coloured ArrayMeshes, one draw call each. Low graphics uses
# fewer facets on every round part.
extends RefCounted

const U := 0.01

# the per-world choice; themes.gd keys "post" and "gem" pick from these
const POSTS := ["snowman", "toadstool", "jar", "cairn"]
const GEMS := ["ice", "acorn", "coin", "amethyst"]

static var _low := false

static func _n(sides: int) -> int:
	return maxi(4, int(sides * 0.6)) if _low else sides

# a ring of quads between two horizontal circles (y0, r0) -> (y1, r1); r can be 0 (a point)
static func _band(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, sides: int, col: Color, rot := 0.0, off := Vector3.ZERO, shade := false) -> void:
	sides = _n(sides)
	for k in sides:
		var a0 := rot + TAU * k / sides
		var a1 := rot + TAU * (k + 1) / sides
		var p0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var p2 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var p3 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var am := (a0 + a1) * 0.5
		var out := Vector3(cos(am), 0.0, sin(am))
		# face normal from the slope of the side
		var dr := r1 - r0
		var dy := y1 - y0
		var nrm := (out * dy - Vector3.UP * dr).normalized()
		if dy < 0.0:
			nrm = -nrm
		if is_zero_approx(dy):
			nrm = Vector3.UP if dr < 0.0 else Vector3.DOWN
		st.set_normal(nrm)
		st.set_color(_lit(col, nrm) if shade else col)
		for v in [p0, p1, p2, p0, p2, p3]:
			st.add_vertex((v + off) * U)

# baked lighting for unshaded objects (gems glow but keep their facets)
static func _lit(c: Color, n: Vector3) -> Color:
	var l := Vector3(-0.4, 0.8, 0.45).normalized()
	var k := 0.7 + 0.45 * maxf(0.0, n.dot(l))
	return Color(minf(1.0, c.r * k), minf(1.0, c.g * k), minf(1.0, c.b * k), c.a)

# a faceted ball, squashed to height ry
static func _ball(st: SurfaceTool, cy: float, r: float, ry: float, col: Color, sides := 10, rot := 0.0, off := Vector3.ZERO) -> void:
	var rings := 3 if _low else 5
	for k in rings:
		var t0 := -PI / 2 + PI * k / rings
		var t1 := -PI / 2 + PI * (k + 1) / rings
		var c := col.darkened(0.08) if k == 0 else col
		_band(st, cy + sin(t0) * ry, cy + sin(t1) * ry, cos(t0) * r, cos(t1) * r, sides, c, rot + k * 0.3, off)

# a cone lying along dir from base (for a carrot nose)
static func _cone_dir(st: SurfaceTool, base: Vector3, dir: Vector3, r: float, length: float, col: Color, sides := 5) -> void:
	sides = _n(sides)
	var d := dir.normalized()
	var a := d.cross(Vector3.UP).normalized()
	var b := a.cross(d)
	var tip := base + d * length
	st.set_color(col)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var p0 := base + (a * cos(a0) + b * sin(a0)) * r
		var p1 := base + (a * cos(a1) + b * sin(a1)) * r
		st.set_normal((p0 + p1 - base * 2.0).normalized())
		for v in [p0, p1, tip]:
			st.add_vertex(v * U)

# ---------------------------------------------------------------- posts
# All posts stand on a 32-radius footprint, about 50-80 high, origin at the ground.
static func post_mesh(kind: String, low := false) -> ArrayMesh:
	_low = low
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"snowman": _snowman(st)
		"toadstool": _toadstool(st)
		"jar": _jar(st)
		"cairn": _cairn(st)
		_: _marker(st)
	_low = false
	return st.commit()

# the old red and white marker post (fallback)
static func _marker(st: SurfaceTool) -> void:
	_band(st, 0.0, 46.0, 32.0, 32.0, 24, Color("#ece6d8"))
	_band(st, 46.0, 46.0, 32.0, 0.0, 24, Color("#ece6d8"))
	_band(st, 18.0, 34.0, 32.6, 32.6, 24, Color("#d4452f"))

static func _snowman(st: SurfaceTool) -> void:
	var snow := Color("#f2f6fa")
	var shade := Color("#cfdbe6")
	var scarf := Color("#d4452f")
	_band(st, 0.0, 6.0, 34.0, 30.0, 10, shade)               # the drift it stands in
	_ball(st, 26.0, 32.0, 26.0, snow, 10)                     # base
	_ball(st, 64.0, 22.0, 18.0, snow, 10, 0.4)                # body
	_ball(st, 92.0, 15.0, 13.0, snow, 9, 0.2)                 # head
	# a red scarf round the neck, its tail hanging down the front
	_band(st, 77.0, 83.0, 17.5, 16.5, 10, scarf)
	_band(st, 77.0, 77.0, 17.5, 0.0, 10, scarf.darkened(0.15))
	_band(st, 60.0, 78.0, 4.5, 4.5, 4, scarf.darkened(0.08), PI / 4, Vector3(19.0, 0, 7.0))
	# coal buttons, eyes and a carrot nose (all facing +x)
	for y in [56.0, 68.0]:
		_ball(st, y, 3.2, 3.2, Color("#24282d"), 5, 0.0, Vector3(21.5 - (y - 56.0) * 0.12, 0, 0))
	for z in [-5.0, 5.0]:
		_ball(st, 96.0, 2.2, 2.2, Color("#24282d"), 5, 0.0, Vector3(13.0, 0, z))
	_cone_dir(st, Vector3(13.5, 92.0, 0), Vector3(1, -0.15, 0), 3.4, 15.0, Color("#f08a24"), 6)
	# a dusting of snow on the head
	_band(st, 104.0, 106.0, 6.0, 0.0, 6, snow)

static func _toadstool(st: SurfaceTool) -> void:
	var stem := Color("#efe6d2")
	var cap := Color("#d23a2c")
	var spot := Color("#fbf5ea")
	_band(st, 0.0, 5.0, 16.0, 13.0, 8, Color("#4f7d33"))      # tuft of moss at the foot
	_band(st, 3.0, 40.0, 13.0, 10.0, 10, stem)
	_band(st, 26.0, 30.0, 10.8, 15.0, 10, stem.darkened(0.06))  # the ring on the stem
	_band(st, 30.0, 30.5, 15.0, 10.4, 10, stem.darkened(0.06))
	# the cap: dark gills underneath, red dome on top
	_band(st, 38.0, 44.0, 10.0, 33.0, 14, Color("#b99b7a"))
	_band(st, 44.0, 50.0, 33.0, 33.0, 14, cap.darkened(0.1))
	_band(st, 50.0, 62.0, 33.0, 25.0, 14, cap, 0.2)
	_band(st, 62.0, 69.0, 25.0, 12.0, 14, cap.lightened(0.05), 0.4)
	_band(st, 69.0, 71.0, 12.0, 0.0, 14, cap.lightened(0.08), 0.6)
	# white spots: flat lumps sitting on the dome
	var spots := [Vector3(0, 70.5, 0), Vector3(19, 63.5, 6), Vector3(-12, 63.5, 16), Vector3(-10, 63.5, -18),
		Vector3(9, 63.5, -19), Vector3(29, 53, -8), Vector3(-26, 53, 6), Vector3(4, 53, 28)]
	var count := 5 if _low else spots.size()
	for k in count:
		var p: Vector3 = spots[k]
		var r := 5.5 if k == 0 else 4.5
		_band(st, p.y - 1.5, p.y + 1.5, r, r * 0.6, 6, spot, k, Vector3(p.x, 0, p.z))
		_band(st, p.y + 1.5, p.y + 1.5, r * 0.6, 0.0, 6, spot, k, Vector3(p.x, 0, p.z))

static func _jar(st: SurfaceTool) -> void:
	var clay := Color("#b8643a")
	var dark := Color("#8a4428")
	var band := Color("#f0d9a8")
	_band(st, 0.0, 4.0, 20.0, 24.0, 12, dark)               # foot
	_band(st, 4.0, 22.0, 24.0, 32.0, 12, clay)
	_band(st, 22.0, 30.0, 32.0, 32.0, 12, band)              # painted band
	_band(st, 26.0, 26.0, 32.2, 32.2, 12, band)
	_band(st, 30.0, 33.0, 32.0, 31.0, 12, Color("#2b211b"))  # thin dark line under the shoulder
	_band(st, 33.0, 46.0, 31.0, 22.0, 12, clay.lightened(0.04))
	_band(st, 46.0, 56.0, 22.0, 14.0, 12, clay)
	_band(st, 56.0, 64.0, 14.0, 13.0, 12, clay.darkened(0.05))  # neck
	_band(st, 64.0, 68.0, 13.0, 17.0, 12, clay.lightened(0.08)) # lip
	_band(st, 68.0, 68.0, 17.0, 12.0, 12, clay.lightened(0.1))
	_band(st, 68.0, 60.0, 12.0, 10.0, 12, Color("#3a2316"))     # the dark mouth
	_band(st, 60.0, 60.0, 10.0, 0.0, 12, Color("#2a1810"))
	# a little sand piled against the foot
	_band(st, 0.0, 5.0, 34.0, 24.0, 9, Color("#e3c48d"), 0.3)

static func _cairn(st: SurfaceTool) -> void:
	var stone := Color("#5f615e")
	# four flat stones, each smaller and a bit off-centre, the top one painted orange
	var y := 0.0
	var specs := [[33.0, 15.0, Vector3(0, 0, 0)], [27.0, 13.0, Vector3(2, 0, -2)],
		[21.0, 12.0, Vector3(-2, 0, 1)], [15.0, 11.0, Vector3(1, 0, 2)]]
	for k in specs.size():
		var r: float = specs[k][0]
		var h: float = specs[k][1]
		var o: Vector3 = specs[k][2]
		var c := stone.darkened(0.12) if k % 2 else stone
		if k == specs.size() - 1:
			c = Color("#e8792e")
		var rot := k * 0.9
		_band(st, y, y + h * 0.25, r * 0.86, r, 7, c.darkened(0.12), rot, o)
		_band(st, y + h * 0.25, y + h * 0.7, r, r * 0.9, 7, c, rot, o)
		_band(st, y + h * 0.7, y + h, r * 0.9, r * 0.55, 7, c.lightened(0.08), rot, o)
		_band(st, y + h, y + h, r * 0.55, 0.0, 7, c.lightened(0.12), rot, o)
		y += h * 0.92
	# a white stripe round the marker stone so it reads from above
	_band(st, y - 6.5, y - 4.0, 13.9, 13.0, 7, Color("#f4f1ea"), 2.7, Vector3(1, 0, 2))

# ---------------------------------------------------------------- gems
# Each gem fits roughly a 30-unit box around its centre (origin), like the old cube.
static func gem_mesh(kind: String, low := false) -> ArrayMesh:
	_low = low
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match kind:
		"ice": _ice(st)
		"acorn": _acorn(st)
		"coin": _coin(st)
		"amethyst": _amethyst(st)
		_: _cube(st)
	_low = false
	return st.commit()

static func _cube(st: SurfaceTool) -> void:
	_band(st, -13.0, 13.0, 21.0, 21.0, 4, Color("#6fcfbd"), PI / 4, Vector3.ZERO, true)

# an elongated six-sided ice crystal, two points
static func _ice(st: SurfaceTool) -> void:
	var c := Color("#5fd4f5")
	_band(st, -22.0, -8.0, 0.0, 12.0, 6, c.darkened(0.1), 0.0, Vector3.ZERO, true)
	_band(st, -8.0, 8.0, 12.0, 12.0, 6, c, 0.0, Vector3.ZERO, true)
	_band(st, 8.0, 22.0, 12.0, 0.0, 6, Color("#e4f8ff"), 0.0, Vector3.ZERO, true)

static func _acorn(st: SurfaceTool) -> void:
	var nut := Color("#ffd04a")
	var cap := Color("#b9782c")
	_band(st, -18.0, -14.0, 0.0, 7.0, 8, nut.darkened(0.08), 0.0, Vector3.ZERO, true)
	_band(st, -14.0, -4.0, 7.0, 13.0, 8, nut, 0.0, Vector3.ZERO, true)
	_band(st, -4.0, 4.0, 13.0, 13.5, 8, nut.lightened(0.08), 0.0, Vector3.ZERO, true)
	# the scaly cap, a bit wider than the nut, and its stalk
	_band(st, 3.0, 6.0, 13.5, 15.5, 8, cap, 0.0, Vector3.ZERO, true)
	_band(st, 6.0, 13.0, 15.5, 9.0, 8, cap.lightened(0.1), 0.2, Vector3.ZERO, true)
	_band(st, 13.0, 14.0, 9.0, 2.5, 8, cap.lightened(0.15), 0.2, Vector3.ZERO, true)
	_band(st, 14.0, 21.0, 2.5, 2.0, 4, cap.darkened(0.1), 0.0, Vector3.ZERO, true)

# a thick gold coin standing on its edge (it spins round y like every gem)
static func _coin(st: SurfaceTool) -> void:
	var gold := Color("#ffc83a")
	var sides := _n(16)
	var r := 17.0
	var t := 4.0
	var rim_in := 12.5
	var faces := func(pts: Array, col: Color, n: Vector3) -> void:
		st.set_normal(n)
		st.set_color(_lit(col, n))
		for k in range(1, pts.size() - 1):
			for v in [pts[0], pts[k], pts[k + 1]]:
				st.add_vertex(v * U)
	for k in sides:
		var a0 := TAU * k / sides
		var a1 := TAU * (k + 1) / sides
		var c0 := Vector2(cos(a0), sin(a0))
		var c1 := Vector2(cos(a1), sin(a1))
		var nm := Vector2(cos((a0 + a1) * 0.5), sin((a0 + a1) * 0.5))
		var en := Vector3(nm.x, nm.y, 0)
		# the milled edge
		faces.call([Vector3(c0.x * r, c0.y * r, -t), Vector3(c1.x * r, c1.y * r, -t),
			Vector3(c1.x * r, c1.y * r, t), Vector3(c0.x * r, c0.y * r, t)], gold.darkened(0.15), en)
		for s: float in [1.0, -1.0]:
			var fz := t * s
			var n := Vector3(0, 0, s)
			# raised rim, then a slightly sunk face, then a raised star in the middle
			faces.call([Vector3(c0.x * r, c0.y * r, fz), Vector3(c0.x * rim_in, c0.y * rim_in, fz),
				Vector3(c1.x * rim_in, c1.y * rim_in, fz), Vector3(c1.x * r, c1.y * r, fz)], gold.lightened(0.1), n)
			var star := 4.0 + (5.5 if k % 2 == 0 else 0.0)
			var tip := Vector3(c0.x * star, c0.y * star, fz * 0.85)
			faces.call([Vector3(c0.x * rim_in, c0.y * rim_in, fz * 0.75), tip,
				Vector3(c1.x * rim_in, c1.y * rim_in, fz * 0.75)], gold.darkened(0.05), n)
			faces.call([tip, Vector3(0, 0, fz * 1.05), Vector3(c1.x * 4.0, c1.y * 4.0, fz * 0.85)], Color("#fff1b0"), n)
			faces.call([Vector3(c1.x * rim_in, c1.y * rim_in, fz * 0.75), tip, Vector3(c1.x * 4.0, c1.y * 4.0, fz * 0.85)], gold, n)

# three purple crystals growing from a little rock
static func _amethyst(st: SurfaceTool) -> void:
	var c := Color("#b77cf2")
	_band(st, -18.0, -12.0, 9.0, 12.0, 6, Color("#6a625a"), 0.0, Vector3.ZERO, true)
	_band(st, -12.0, -10.0, 12.0, 0.0, 6, Color("#7d746b"), 0.0, Vector3.ZERO, true)
	var specs := [[Vector3(0, 0, 0), 6.5, 30.0, 0.0], [Vector3(-7, 0, 4), 4.5, 20.0, 0.5], [Vector3(6, 0, 5), 4.0, 17.0, 1.0]]
	for sp in specs:
		var o: Vector3 = sp[0]
		var r: float = sp[1]
		var h: float = sp[2]
		var rot: float = sp[3]
		_band(st, -12.0, -12.0 + h * 0.72, r, r, 6, c.darkened(0.05), rot, o, true)
		_band(st, -12.0 + h * 0.72, -12.0 + h, r, 0.0, 6, Color("#e6c9ff"), rot, o, true)
