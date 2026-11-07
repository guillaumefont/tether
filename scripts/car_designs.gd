extends RefCounted
# Design study: three from-scratch car families, one vehicle per world each.
# build(style, theme, col) returns a car root with the same chassis/body metas as
# WorldView._make_car. Units are the game's (x forward, y up, z across), scaled by U.
const WV = preload("res://scripts/world_view.gd")
const U := 0.01

# ------------------------------------------------------------------ helpers
static func sp(profile: PackedVector2Array, depth: float, r: float, m: Material, z := 0.0) -> MeshInstance3D:
	var mi := WV.soft_prism(profile, depth, r, m, 3, true)
	mi.position.z = z * U
	return mi

# rounded corners, each radius capped so neighbouring curves never overlap
static func rnd(pts: Array, r: float, segs := 4) -> PackedVector2Array:
	var n := pts.size()
	var radii := PackedFloat32Array()
	for i in n:
		var p: Vector2 = pts[i]
		var la := p.distance_to(pts[(i + n - 1) % n])
		var lb := p.distance_to(pts[(i + 1) % n])
		radii.append(minf(r, minf(la, lb) * 0.45))
	return dedupe(WV.rounded(PackedVector2Array(pts), r, segs, radii))

static func dedupe(p: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in p:
		if out.is_empty() or out[out.size() - 1].distance_to(q) > 0.3:
			out.append(q)
	if out.size() > 2 and out[0].distance_to(out[out.size() - 1]) <= 0.3:
		out.remove_at(out.size() - 1)
	return out

static func pv(pts: Array) -> PackedVector2Array:
	return PackedVector2Array(pts)

# a round tube from a to b
static func tube(a: Vector3, b: Vector3, r: float, m: Material, segs := 10) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * U; cm.bottom_radius = r * U
	cm.height = a.distance_to(b) * U
	cm.radial_segments = segs; cm.rings = 1
	cm.material = m
	mi.mesh = cm
	var y := (b - a).normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5 * U)
	return mi

static func ball(r: float, m: Material, pos: Vector3, squash := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r * U; s.height = r * 2.0 * U
	s.radial_segments = 20; s.rings = 10
	s.material = m
	mi.mesh = s
	mi.position = pos * U
	mi.scale = squash
	return mi

static func ring(r: float, t: float, m: Material, pos: Vector3, upright := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = (r - t) * U; tm.outer_radius = r * U
	tm.rings = 20; tm.ring_segments = 8
	tm.material = m
	mi.mesh = tm
	mi.position = pos * U
	if upright:
		mi.rotation.x = PI / 2
	return mi

# The tether hook: a short post and an upright ring, the rope's anchor on every car
static func hook(parts: Array, x: float, y: float, steel: Material, dark: Material) -> void:
	parts.append(WV.pcyl(3.0, 5.0, dark, Vector3(x, y + 2.0, 0), "y", 12))
	parts.append(ring(4.5, 1.5, steel, Vector3(x, y + 8.0, 0)))

static func mats(col: Color) -> Dictionary:
	var top := WV.paint(col)
	var low := WV.paint(col.darkened(0.38), 0.5)
	var dark := WV.paint(Color("#1d2229"), 0.6)
	var steel := WV.paint(Color("#b9c0c8"), 0.25)
	steel.metallic = 0.75
	var glass := WV.paint(Color("#253b52"), 0.06)
	glass.metallic = 0.5
	var lamp := WV.mat(Color("#fff4c8"), true)
	var tail := WV.mat(Color("#ff4a3a"), false, 1.2)
	var white := WV.paint(Color("#f2f0ea"), 0.35)
	return {"top": top, "low": low, "dark": dark, "steel": steel, "glass": glass,
		"lamp": lamp, "tail": tail, "white": white, "col": col}

# ------------------------------------------------------------------ wheels
# style: road | knob | balloon | crawl
static func wheel(parent: Node3D, x: float, z: float, r: float, w: float, style: String, rim: Material) -> void:
	var tyre := WV.paint(Color("#1c1e21"), 0.88)
	var c := Vector3(x, r, z)
	var out := signf(z)
	parent.add_child(WV.pcyl(r - 2.5, w, tyre, c, "z", 28))
	for s: float in [-1.0, 1.0]:   # rounded shoulders
		var mi := ring(r, 5.0 if style == "balloon" else 3.2, tyre, c + Vector3(0, 0, s * (w * 0.5 - (2.5 if style == "balloon" else 1.6))))
		mi.rotation.x = PI / 2
		parent.add_child(mi)
	var n: int = {"road": 0, "knob": 12, "balloon": 0, "crawl": 10}[style]
	for k in n:   # tread blocks
		var an: float = TAU * (k + 0.5) / n
		var bw: float = (w + 1.0) if style == "crawl" else (w * 0.45)
		for off in ([0.0] if style == "crawl" else [-w * 0.24, w * 0.24]):
			var a2: float = an + (0.0 if off <= 0.0 else PI / n)
			var blk := WV.pbox(Vector3(r * 0.32, 3.0, bw), tyre, c + Vector3(cos(a2), sin(a2), 0) * (r - 0.5) + Vector3(0, 0, off))
			blk.rotation.z = a2 + PI / 2
			parent.add_child(blk)
	if style == "balloon":   # tread grooves
		for k in 3:
			parent.add_child(ring(r + 0.3, 0.8, WV.paint(Color("#3a3833"), 0.9), c + Vector3(0, 0, (k - 1) * w * 0.25)))
	var face := c + Vector3(0, 0, out * (w * 0.5 - 0.4))
	parent.add_child(WV.pcyl(r * 0.58, 1.6, rim, face, "z", 24))
	parent.add_child(WV.pcyl(r * 0.40, 1.9, WV.paint(Color("#121417"), 0.6), face + Vector3(0, 0, out * 0.2), "z", 24))
	parent.add_child(WV.pcyl(r * 0.18, 2.6, rim, face + Vector3(0, 0, out * 0.5), "z", 16))

# Snow: a triangular crawler pod where the wheel would be (flat on the snow, peak at the axle)
static func pod(parent: Node3D, x: float, z: float, r: float, w: float, m: Dictionary) -> void:
	var tread := WV.paint(Color("#22262c"), 0.85)
	var lug := WV.paint(Color("#6a7480"), 0.7)
	var hl := r * 1.45
	var h := r * 1.6
	var prof := WV.rounded(pv([Vector2(x - hl, 0), Vector2(x + hl, 0), Vector2(x, h)]), 6.0, 6)
	parent.add_child(sp(prof, w, 2.0, tread, z))
	for k in 5:
		var lx := x - hl * 0.72 + k * hl * 0.36
		var top := h * (1.0 - absf(lx - x) / hl) - 2.5
		if top > 4.0:
			parent.add_child(WV.pbox(Vector3(3, top, w + 1.0), lug, Vector3(lx, top * 0.5 + 0.5, z)))
	parent.add_child(WV.pcyl(5.0, w + 3.0, m["top"], Vector3(x, h * 0.55, z), "z", 16))   # hub

# ------------------------------------------------------------------ theme kits
# spec: wx (axles), wz, wr, ww, nose (x, y) front face, rack (x, y, z half width)
# for roof gear, tail (x, y), lift (body height above the base)
static func kit(theme: String, chassis: Node3D, parts: Array, s: Dictionary, m: Dictionary) -> void:
	var r: float = s["wr"]
	var w: float = s["ww"]
	var wz: float = s["wz"]
	var nose: Vector2 = s["nose"]
	var rack: Vector3 = s["rack"]
	var tail: Vector2 = s["tail"]
	match theme:
		"snow":
			for wx: float in s["wx"]:
				for sd: float in [1.0, -1.0]:
					pod(chassis, wx, wz * sd, r, w + 1.0, m)
			# a curved steel plough low in front
			var blade := sp(rnd([Vector2(0, 0), Vector2(6, 0), Vector2(10, 14), Vector2(5, 15), Vector2(2, 5)], 1.5), s["plough_w"], 1.0, m["steel"])
			blade.position.x = (nose.x + 2.0) * U
			parts.append(blade)
			for bz in [-14.0, 14.0]:
				parts.append(WV.pbox(Vector3(10, 3, 3), m["dark"], Vector3(nose.x - 2, 9, bz)))
		"forest":
			for wx: float in s["wx"]:
				for sd: float in [1.0, -1.0]:
					wheel(chassis, wx, wz * sd, r + 1.0, w + 1.0, "knob", m["top"])
			var bark := WV.paint(Color("#6b4a2e"), 0.85)
			var cut := WV.paint(Color("#e2bf84"), 0.7)
			for lz in [-rack.z * 0.45, rack.z * 0.45]:
				var lg := WV.pcyl(6.5, s["log_len"], bark, Vector3(rack.x, rack.y + 9.0, lz), "x", 12)
				parts.append(lg)
				parts.append(WV.pcyl(5.4, 0.8, cut, Vector3(rack.x + s["log_len"] * 0.5 + 0.2, rack.y + 9.0, lz), "x", 12))
				parts.append(WV.pcyl(5.4, 0.8, cut, Vector3(rack.x - s["log_len"] * 0.5 - 0.2, rack.y + 9.0, lz), "x", 12))
			for rx in [-s["log_len"] * 0.3, s["log_len"] * 0.3]:   # straps
				parts.append(WV.pbox(Vector3(3, 3, rack.z * 2.0), m["dark"], Vector3(rack.x + rx, rack.y + 1.5, 0)))
				parts.append(WV.pbox(Vector3(2.4, 2, rack.z * 1.6), WV.paint(Color("#d23b2a"), 0.6), Vector3(rack.x + rx, rack.y + 15.8, 0)))
		"sand":
			for wx: float in s["wx"]:
				for sd: float in [1.0, -1.0]:
					wheel(chassis, wx, (wz + 3.0) * sd, r, w + 9.0, "balloon", m["white"])
			parts.append(tube(Vector3(tail.x + 4, tail.y, -rack.z * 0.7), Vector3(tail.x - 4, tail.y + 70, -rack.z * 0.7), 1.0, m["dark"], 6))
			var flag := WV.pprism(pv([Vector2(0, 0), Vector2(18, 4), Vector2(0, 12)]), 1.2, m["top"])
			flag.position = Vector3(tail.x - 3.5, tail.y + 56, -rack.z * 0.7) * U
			parts.append(flag)
			# a sand-coloured air filter by the driver
			parts.append(WV.pcyl(5.0, 12.0, WV.paint(Color("#d9b77c"), 0.9), Vector3(rack.x, rack.y + 5.0, rack.z), "y", 14))
		"rock":
			for wx: float in s["wx"]:
				for sd: float in [1.0, -1.0]:
					wheel(chassis, wx, (wz + 2.0) * sd, r + 5.0, w + 4.0, "crawl", m["dark"])
			for by in [nose.y - 4.0, nose.y + 6.0]:   # bull bar
				parts.append(tube(Vector3(nose.x + 5, by, -24), Vector3(nose.x + 5, by, 24), 1.8, m["steel"]))
			for bz in [-18.0, 18.0]:
				parts.append(tube(Vector3(nose.x - 2, nose.y - 4, bz), Vector3(nose.x + 5, nose.y - 4, bz), 1.8, m["steel"]))
				parts.append(tube(Vector3(nose.x + 5, nose.y - 4, bz), Vector3(nose.x + 5, nose.y + 6, bz), 1.8, m["steel"]))
			parts.append(WV.pbox(Vector3(4, 5, rack.z * 1.6), m["dark"], Vector3(rack.x + 8, rack.y + 3.0, 0)))   # light bar
			for lz in [-rack.z * 0.5, 0.0, rack.z * 0.5]:
				parts.append(WV.pcyl(2.6, 1.2, m["lamp"], Vector3(rack.x + 10.2, rack.y + 3.0, lz), "x", 12))
			parts.append(WV.pbox(Vector3(70, 3, 30), m["steel"], Vector3(0, 10, 0)))   # skid plate

# ------------------------------------------------------------------ the families
static func build(style: String, theme: String, col: Color) -> Node3D:
	var root := Node3D.new()
	var chassis := Node3D.new()
	root.add_child(chassis)
	var body := Node3D.new()
	chassis.add_child(body)
	var shell := Node3D.new()
	body.add_child(shell)
	var parts: Array = []
	var m := mats(col)
	var s: Dictionary
	match style:
		"pebble": s = _pebble(parts, m)
		"arrow": s = _arrow(parts, m)
		"buggy": s = _buggy(parts, m)
	kit(theme, chassis, parts, s, m)
	var lift: float = {"rock": 5.0, "forest": 1.0}.get(theme, 0.0)
	shell.position.y = lift * U
	for p in parts:
		shell.add_child(p)
	root.set_meta("body", body)
	root.set_meta("chassis", chassis)
	return root

# A: "Galet" a round toy coupe: one soft shell, bulging fenders over each wheel, a big
# glass bubble, round lamps.
static func _pebble(parts: Array, m: Dictionary) -> Dictionary:
	var wx := [-38.0, 42.0]
	parts.append(sp(rnd([Vector2(-60, 12), Vector2(64, 12), Vector2(64, 22), Vector2(-60, 22)], 4.0), 50.0, 5.0, m["dark"]))   # under tray
	parts.append(sp(rnd([Vector2(-62, 18), Vector2(66, 18), Vector2(70, 27), Vector2(60, 35), Vector2(28, 39), Vector2(-46, 40), Vector2(-62, 33)], 9.0, 5), 58.0, 7.0, m["top"]))
	for x: float in wx:   # fender blisters
		var arc: Array = []
		for k in 9:
			var a := PI * k / 8.0
			arc.append(Vector2(x + cos(a) * 23.0, 16.0 + sin(a) * 19.0))
		for sd: float in [1.0, -1.0]:
			parts.append(sp(pv(arc), 16.0, 3.0, m["top"], 27.0 * sd))
	parts.append(sp(rnd([Vector2(-36, 36), Vector2(24, 36), Vector2(6, 55), Vector2(-22, 58), Vector2(-38, 48)], 9.0, 5), 46.0, 7.0, m["glass"]))
	parts.append(sp(rnd([Vector2(-26, 56.5), Vector2(0, 55.5), Vector2(-4, 58.5), Vector2(-22, 59.5)], 2.0), 30.0, 1.2, m["top"]))   # roof cap
	hook(parts, -12.0, 58.0, m["steel"], m["dark"])
	for lz in [-19.0, 19.0]:
		parts.append(WV.pcyl(5.5, 2.0, m["white"], Vector3(66.8, 26.5, lz), "x", 20))
		parts.append(WV.pcyl(4.2, 2.4, m["lamp"], Vector3(67.0, 26.5, lz), "x", 20))
		parts.append(WV.pcyl(4.0, 2.0, m["tail"], Vector3(-62.2, 30.0, lz), "x", 16))
	parts.append(sp(rnd([Vector2(64, 18), Vector2(70, 18), Vector2(70, 22), Vector2(64, 22)], 1.5), 40.0, 2.0, m["dark"]))   # bumper
	parts.append(sp(rnd([Vector2(-66, 16), Vector2(-60, 16), Vector2(-60, 21), Vector2(-66, 21)], 1.5), 44.0, 2.0, m["dark"]))
	parts.append(sp(rnd([Vector2(-62, 34), Vector2(-46, 39), Vector2(-48, 44), Vector2(-64, 40)], 2.0), 50.0, 3.0, m["low"]))   # ducktail
	return {"wx": wx, "wz": 31.0, "wr": 15.0, "ww": 13.0, "nose": Vector2(69, 22), "rack": Vector3(-14, 59, 16),
		"tail": Vector2(-54, 40), "log_len": 56.0, "plough_w": 56.0}

# B: "Flèche" an open-wheel arrow: a narrow tub with a pointed nose, side pods,
# the driver's helmet in the open, wings front and back, wheels out in the air.
static func _arrow(parts: Array, m: Dictionary) -> Dictionary:
	var wx := [-40.0, 46.0]
	parts.append(sp(rnd([Vector2(74, 14), Vector2(76, 19), Vector2(40, 28), Vector2(12, 35), Vector2(-42, 35), Vector2(-62, 30), Vector2(-62, 13), Vector2(30, 11)], 4.0), 32.0, 7.0, m["top"]))   # tub
	for sd: float in [1.0, -1.0]:   # side pods
		parts.append(sp(rnd([Vector2(-34, 12), Vector2(16, 12), Vector2(22, 24), Vector2(10, 29), Vector2(-34, 31)], 4.0), 15.0, 5.0, m["top"], 22.0 * sd))
		parts.append(WV.pbox(Vector3(2, 10, 11), m["dark"], Vector3(21.5, 19, 22.0 * sd)))   # intake mouth
	parts.append(sp(rnd([Vector2(-26, 34), Vector2(6, 34), Vector2(2, 37), Vector2(-26, 37)], 1.5), 20.0, 2.0, m["dark"]))   # cockpit hole
	parts.append(ball(9.0, m["white"], Vector3(-12, 42, 0)))   # helmet
	parts.append(sp(rnd([Vector2(-8, 38), Vector2(-3, 39), Vector2(-3, 45), Vector2(-8, 47)], 1.5), 13.0, 3.0, m["glass"]))   # visor
	parts.append(ball(9.2, m["top"], Vector3(-13.5, 44, 0), Vector3(0.9, 0.55, 0.92)))   # helmet stripe crown
	parts.append(sp(rnd([Vector2(8, 34), Vector2(14, 34), Vector2(6, 44), Vector2(2, 44)], 1.0), 22.0, 2.0, m["glass"]))   # screen
	parts.append(sp(rnd([Vector2(-22, 34), Vector2(-28, 54), Vector2(-40, 50), Vector2(-58, 33)], 3.0), 13.0, 4.0, m["low"]))   # air box
	hook(parts, -29.0, 53.0, m["steel"], m["dark"])
	# front wing, end plates
	parts.append(sp(rnd([Vector2(56, 9), Vector2(76, 9), Vector2(76, 12), Vector2(58, 14)], 1.0), 84.0, 1.5, m["low"]))
	for sd: float in [1.0, -1.0]:
		parts.append(sp(rnd([Vector2(55, 7), Vector2(77, 7), Vector2(74, 18), Vector2(58, 18)], 2.0), 2.5, 1.0, m["top"], 42.0 * sd))
	# rear wing on two struts
	parts.append(sp(rnd([Vector2(-70, 50), Vector2(-52, 52), Vector2(-52, 56), Vector2(-70, 56)], 1.5), 70.0, 1.5, m["low"]))
	for sd: float in [1.0, -1.0]:
		parts.append(sp(rnd([Vector2(-72, 40), Vector2(-50, 44), Vector2(-50, 60), Vector2(-72, 60)], 2.0), 2.5, 1.0, m["top"], 35.5 * sd))
		parts.append(WV.pbox(Vector3(4, 22, 3), m["dark"], Vector3(-60, 40, 10.0 * sd)))
	# suspension arms out to each hub
	for x: float in wx:
		for sd: float in [1.0, -1.0]:
			for dy in [-4.0, 4.0]:
				parts.append(tube(Vector3(x - 6, 16 + dy, 14 * sd), Vector3(x, 16 + dy * 0.5, 30 * sd), 1.4, m["dark"], 6))
				parts.append(tube(Vector3(x + 6, 16 + dy, 14 * sd), Vector3(x, 16 + dy * 0.5, 30 * sd), 1.4, m["dark"], 6))
	for lz in [-6.0, 6.0]:
		parts.append(WV.pbox(Vector3(2, 3, 5), m["tail"], Vector3(-63, 22, lz)))
	parts.append(WV.pbox(Vector3(1.5, 3, 10), m["lamp"], Vector3(75.5, 16, 0)))
	return {"wx": wx, "wz": 36.0, "wr": 16.0, "ww": 15.0, "nose": Vector2(76, 16), "rack": Vector3(-40, 36, 14),
		"tail": Vector2(-60, 36), "log_len": 34.0, "plough_w": 70.0}

# C: "Baroudeur" a rally-raid buggy: an open tube cage, a short bonnet, an engine deck
# at the back with the spare wheel, the driver in the open, mudguards over big wheels.
static func _buggy(parts: Array, m: Dictionary) -> Dictionary:
	var wx := [-40.0, 42.0]
	parts.append(sp(rnd([Vector2(-58, 14), Vector2(60, 14), Vector2(60, 22), Vector2(-58, 22)], 3.0), 48.0, 4.0, m["dark"]))   # floor
	parts.append(sp(rnd([Vector2(24, 20), Vector2(64, 20), Vector2(70, 26), Vector2(66, 32), Vector2(24, 38)], 4.0), 50.0, 7.0, m["top"]))   # bonnet
	parts.append(sp(rnd([Vector2(-64, 20), Vector2(-28, 20), Vector2(-28, 38), Vector2(-56, 38), Vector2(-64, 30)], 4.0), 50.0, 7.0, m["top"]))   # engine deck
	for sd: float in [1.0, -1.0]:   # half doors
		parts.append(sp(rnd([Vector2(-30, 20), Vector2(26, 20), Vector2(26, 34), Vector2(-30, 32)], 2.0), 3.0, 1.2, m["low"], 24.0 * sd))
	# seat + driver
	parts.append(WV.pbox(Vector3(6, 18, 18), m["dark"], Vector3(-22, 36, 0)))
	parts.append(WV.pbox(Vector3(14, 6, 16), m["dark"], Vector3(-14, 26, 0)))
	parts.append(WV.pbox(Vector3(12, 12, 16), m["low"], Vector3(-12, 34, 0)))   # torso
	parts.append(ball(8.0, m["white"], Vector3(-10, 47, 0)))
	parts.append(sp(rnd([Vector2(-5, 43), Vector2(-2, 44), Vector2(-2, 50), Vector2(-5, 52)], 1.0), 11.0, 2.5, m["glass"]))
	# cage: A pillars, roof rails, B hoop, cross bars
	var cg: Material = m["dark"]
	for sd: float in [1.0, -1.0]:
		parts.append(tube(Vector3(24, 37, 20 * sd), Vector3(4, 60, 18 * sd), 1.8, cg))
		parts.append(tube(Vector3(4, 60, 18 * sd), Vector3(-30, 60, 18 * sd), 1.8, cg))
		parts.append(tube(Vector3(-30, 60, 18 * sd), Vector3(-34, 38, 21 * sd), 1.8, cg))
		parts.append(tube(Vector3(-30, 60, 18 * sd), Vector3(-56, 38, 18 * sd), 1.6, cg))   # rear stays
	parts.append(tube(Vector3(4, 60, -18), Vector3(4, 60, 18), 1.8, cg))
	parts.append(tube(Vector3(-30, 60, -18), Vector3(-30, 60, 18), 1.8, cg))
	parts.append(sp(rnd([Vector2(-31, 60), Vector2(5, 60), Vector2(3, 62.5), Vector2(-30, 62.5)], 1.0), 37.0, 1.5, m["top"]))   # roof panel
	hook(parts, -13.0, 62.0, m["steel"], m["dark"])
	# spare wheel on the deck
	parts.append(WV.pcyl(11.0, 6.0, WV.paint(Color("#1c1e21"), 0.88), Vector3(-46, 41, 0), "y", 20))
	parts.append(WV.pcyl(6.0, 6.6, m["white"], Vector3(-46, 41, 0), "y", 16))
	# mudguards over each wheel
	for x: float in wx:
		var arc: Array = []
		for k in 9:
			var a := PI * (0.12 + 0.76 * k / 8.0)
			arc.append(Vector2(x + cos(a) * 24.0, 18.0 + sin(a) * 24.0))
		for k in range(8, -1, -1):
			var a := PI * (0.12 + 0.76 * k / 8.0)
			arc.append(Vector2(x + cos(a) * 21.0, 18.0 + sin(a) * 21.0))
		for sd: float in [1.0, -1.0]:
			parts.append(sp(pv(arc), 18.0, 1.0, m["top"], 34.0 * sd))
	for lz in [-15.0, 15.0]:   # round lamps on the cage
		parts.append(WV.pcyl(4.5, 4.0, m["dark"], Vector3(8, 58, lz), "x", 16))
		parts.append(WV.pcyl(3.6, 4.4, m["lamp"], Vector3(8.4, 58, lz), "x", 16))
		parts.append(WV.pcyl(3.5, 2.0, m["lamp"], Vector3(68.5, 27, lz), "x", 16))
		parts.append(WV.pbox(Vector3(2, 4, 8), m["tail"], Vector3(-64.2, 30, lz * 1.3)))
	parts.append(WV.pcyl(2.4, 8.0, m["steel"], Vector3(-64, 18, 12), "x", 10))   # exhaust
	return {"wx": wx, "wz": 34.0, "wr": 17.0, "ww": 15.0, "nose": Vector2(70, 22), "rack": Vector3(-13, 62, 16),
		"tail": Vector2(-58, 38), "log_len": 46.0, "plough_w": 52.0}
