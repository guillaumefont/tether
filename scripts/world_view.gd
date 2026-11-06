# The 3D view. Builds the track meshes from TrackData and mirrors the race state
# (cars, tethers, spinning towers, posts, gems, effects) every frame.
# World mapping: prototype (x, y) with height h -> Vector3(x, h, y) * U.
extends Node3D

const TrackData = preload("res://scripts/track.gd")
const Themes = preload("res://scripts/themes.gd")
const Race = preload("res://scripts/race.gd")

const U := 0.01
const HW := TrackData.HW
const GAP := TrackData.GAP
const ROAD_Y := 1.0          # road surface lift above ground, world units
const KERB_W := 16.0
const RAIL_W := 12.0
const RAIL_H := 26.0
const TOWER_H := 90.0
const RAMP_LEN := 130.0
const RAMP_H := 28.0
const FOV := 40.0
const PITCH := deg_to_rad(68.0)   # fairly top-down so lines through bends are easy to judge

const COL_INFIELD := Color("#c9d6e0")   # snow
const COL_CHALK := Color("#ece6d8")
const COL_KERB := Color("#d4452f")     # obstacle posts
const BANK_OUT := 70.0    # the bank's outer slope, rolling down into the ground
const BANK_RELIEF := 0.25 # how much the outer slope's tilt shows in its lighting
const BANK_FACE_TOP := 0.3  # bank colour left at the top of the inner face (rest is ground)
const COL_DECK := Color("#7a5a3a")
const COL_DECK_LIGHT := Color("#a07a50")
const COL_POST := Color("#f2b134")
const COL_TOWER := Color("#2a2f36")
const COL_ICE := Color("#bfe6f5")
const COL_ROPE := Color("#c9a66b")
const COL_GEM := Color("#7fe3d0")

var track: TrackData
var th: Dictionary = Themes.get_theme("snow")   # the look of the current track
var theme_override := ""   # forces a theme (previews); otherwise the track's own
var env: Environment
var static_root: Node3D
var dyn_root: Node3D
var camera: Camera3D
var light: DirectionalLight3D

var tower_nodes := {}      # anchor (curve) index -> {spinner, rings: [MeshInstance3D, MeshInstance3D]}
var rotor_h := PackedFloat32Array()  # rotor height of each curve (world units)
var car_nodes: Array = []  # per car: {root, body, tether, marker}
var ghost_node: Node3D
var post_nodes: Array = []
var gem_nodes: Array = []

# effects
var parts: Array = []      # {p: Vector3, v: Vector3, life, col}
const SPARK_MAX := 240
var spark_pool: Array = []
var spark_mats := {}
var skid_mm: MultiMeshInstance3D
var skid_mat: ShaderMaterial
var skid_next := 0
var skid_count := 0
const SKID_MAX := 2400
var fx_time := 0.0
var shake := 0.0

# camera state (world units, prototype space)
var cam_t := Vector3.ZERO     # target (x, h, y)
var cam_vis := 1450.0         # visible height in world units
var menu_cover_px := 0.0      # screen pixels on the left hidden by the menu panel
var _vert_mat: StandardMaterial3D

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.5
	camera.far = 400.0
	add_child(camera)
	camera.current = true

	light = DirectionalLight3D.new()
	light.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-35), 0)
	light.light_energy = 1.0
	light.light_color = Color("#fff3e4")
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 60.0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(light)

	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COL_INFIELD.darkened(0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a9c2dc")
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
	env.glow_enabled = true      # soft bloom on the emissive rotors and gems
	env.glow_intensity = 0.35
	env.glow_hdr_threshold = 1.3  # high enough that sunlit snow does not bloom
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_vert_mat = StandardMaterial3D.new()
	_vert_mat.vertex_color_use_as_albedo = true
	_vert_mat.roughness = 0.92
	_vert_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	static_root = Node3D.new()
	add_child(static_root)
	dyn_root = Node3D.new()
	add_child(dyn_root)

static func w3(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x * U, h * U, p.y * U)

static func mat(c: Color, unshaded := false, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emission
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m

static func box(size: Vector3, c: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size * U
	bm.material = mat(c)
	mi.mesh = bm
	mi.position = pos * U
	return mi

static func cyl(r: float, h: float, c: Color, pos := Vector3.ZERO, r_bottom := -1.0, segs := 24) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * U
	cm.bottom_radius = (r if r_bottom < 0.0 else r_bottom) * U
	cm.height = h * U
	cm.radial_segments = segs
	cm.rings = 1
	cm.material = mat(c)
	mi.mesh = cm
	mi.position = pos * U
	return mi

# ---------------------------------------------------------------- track build
func build(tr: TrackData) -> void:
	for step in build_steps(tr):
		step.call()

# The build cut into a few steps so a loading screen can draw its bar between them.
func build_steps(tr: TrackData) -> Array:
	return [func(): _clear(tr), _build_ground, func(): _build_road(); _build_drifts(), _build_scenery,
		func(): _build_jumps(); _build_start(); _build_towers(),
		func(): _build_posts(); _build_gems(); _build_fx(); _build_weather()]

func _clear(tr: TrackData) -> void:
	track = tr
	th = Themes.get_theme(theme_override if theme_override != "" else String(tr.def.get("theme", "snow")))
	env.background_color = (th["ground"] as Color).darkened(0.1)
	env.ambient_light_color = th["ambient"]
	light.light_color = th["sun"]
	for ch in static_root.get_children():
		ch.queue_free()
	for ch in dyn_root.get_children():
		ch.queue_free()
	tower_nodes.clear()
	car_nodes.clear()
	post_nodes.clear()
	gem_nodes.clear()
	ghost_node = null
	parts.clear()

func _build_ground() -> void:
	var b := track.bounds
	var pm := PlaneMesh.new()
	var margin := 9000.0
	pm.size = Vector2(b.size.x + margin * 2, b.size.y + margin * 2) * U
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 base_col : source_color;
uniform vec3 dot_col : source_color;
uniform vec3 far_col : source_color;
uniform vec3 near_col : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	// soft wind-blown drifts plus a faint sparkle
	float n = vnoise(wp.xz * 0.35) * 0.65 + vnoise(wp.xz * 1.3) * 0.35;
	float d = smoothstep(0.4, 0.8, n) + step(0.985, hash(floor(wp.xz * 9.0))) * 0.25;
	// soft gradient: lighter towards the bottom-centre of the screen, darker at the far edge
	vec2 uv = SCREEN_UV;
	float v = clamp(uv.y * 0.9 + 0.1, 0.0, 1.0);
	vec3 grad = mix(far_col, near_col, v);
	float vig = smoothstep(0.95, 0.25, length((uv - vec2(0.5, 0.62)) * vec2(1.0, 1.25)));
	vec3 c = mix(base_col * 0.72, grad, 0.35 + 0.65 * vig);
	ALBEDO = mix(c, c + (dot_col - base_col), d);
	ROUGHNESS = 1.0;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	var gc: Color = th["ground"]
	sm.set_shader_parameter("base_col", gc)
	sm.set_shader_parameter("dot_col", th["ground_dots"])
	sm.set_shader_parameter("far_col", gc.darkened(0.25))
	sm.set_shader_parameter("near_col", gc.lightened(0.12))
	pm.material = sm
	var mi := MeshInstance3D.new()
	mi.mesh = pm
	mi.position = w3(b.get_center(), 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	static_root.add_child(mi)

class Strip:
	var st := SurfaceTool.new()
	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Godot draws clockwise triangles as front faces, and lights a back face (cull is
	# off) with its normal flipped, so each quad is wound to face its own normal
	static func _order(a: Vector3, b: Vector3, d: Vector3, nrm: Vector3) -> Array:
		return [0, 2, 1, 0, 3, 2] if (b - a).cross(d - a).dot(nrm) > 0.0 else [0, 1, 2, 0, 2, 3]
	# quad with its own colour and normal at each corner (smooth shading); a colour's
	# alpha below 1 blends that corner into the ground's own shading (1 - alpha)
	func quad_smooth(v: Array, cols: Array, nrms: Array) -> void:
		var avg: Vector3 = nrms[0] + nrms[1] + nrms[2] + nrms[3]
		for k in _order(v[0], v[1], v[3], avg):
			st.set_color(cols[k])
			st.set_normal(nrms[k])
			st.set_uv(Vector2.ZERO)
			st.add_vertex(v[k])
	# quad a-b-c-d (in order round the edge), flat normal pointing towards `hint`
	# uv.x = 1 marks the asphalt (the road shader adds ice and snowy edges there),
	# uv.y = side of the lane (+1 / -1)
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint: Vector3, road := false, flat := false) -> void:
		var nrm := (b - a).cross(d - a)
		if nrm.length_squared() < 1e-12:
			nrm = (c - b).cross(a - b)
		nrm = nrm.normalized()
		if nrm.dot(hint) < 0.0:
			nrm = -nrm
		st.set_color(col)
		st.set_normal(nrm)
		var uvs := [Vector2(1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(1, -1)] if road else [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		# the asphalt and its dashes (`flat`) keep their old back-facing winding: their
		# dark, matt look and the theme road colours were tuned with it
		for k in ([0, 1, 2, 0, 2, 3] if road or flat else _order(a, b, d, nrm)):
			st.set_uv(uvs[k])
			st.add_vertex([a, b, c, d][k])

func _road_samples() -> Array:
	# uniform samples plus exact jump-gap boundaries
	var ss: Array[float] = []
	var N := ceili(track.L / 20.0)
	for k in N:
		ss.append(track.L * k / N)
	for j in track.jumps:
		ss.append(fposmod(j["s"], track.L))
		ss.append(fposmod(j["s"] + GAP, track.L))
	ss.sort()
	var out: Array = []
	for s in ss:
		var q := track.point_at(s)
		var a := track.point_at(s - 10.0)["pos"] as Vector2
		var b := track.point_at(s + 10.0)["pos"] as Vector2
		var t := (b - a).normalized()
		out.append({ "s": s, "c": q["pos"], "n": TrackData.perp(t), "h": track.height_at(s), "i": q["i"] })
	return out

func _in_gap(s: float) -> bool:
	for j in track.jumps:
		if fposmod(s - j["s"], track.L) < GAP:
			return true
	return false

func _near_bridge_center(p: Vector2, m: float) -> bool:
	for B in track.bridges:
		if p.distance_to(B["c"]) < m:
			return true
	return false

func _build_road() -> void:
	var smp := _road_samples()
	var road := Strip.new()
	var up := Vector3.UP
	var cnt := smp.size()
	var pillar_acc := 0.0
	for k in cnt:
		var A: Dictionary = smp[k]
		var B: Dictionary = smp[(k + 1) % cnt]
		var sa: float = A["s"]
		var sb: float = B["s"] if k + 1 < cnt else track.L
		var smid := (sa + sb) * 0.5
		if _in_gap(smid):
			continue
		var ca: Vector2 = A["c"]; var cb: Vector2 = B["c"]
		var na: Vector2 = A["n"]; var nb: Vector2 = B["n"]
		var ha: float = A["h"] + ROAD_Y; var hb: float = B["h"] + ROAD_Y
		var P := func(c: Vector2, n: Vector2, off: float, h: float) -> Vector3:
			return w3(c + n * off, h)
		# asphalt
		road.quad(P.call(ca, na, HW, ha), P.call(cb, nb, HW, hb), P.call(cb, nb, -HW, hb), P.call(ca, na, -HW, ha), th["road"], up, true)
		# centre dashes (40 on, 50 off)
		if fposmod(smid, 90.0) < 40.0:
			road.quad(P.call(ca, na, 2.5, ha + 0.4), P.call(cb, nb, 2.5, hb + 0.4), P.call(cb, nb, -2.5, hb + 0.4), P.call(ca, na, -2.5, ha + 0.4), Color(COL_CHALK, 1.0).darkened(0.55), up, false, true)
		var elevated: bool = A["h"] > 2.0 or B["h"] > 2.0
		for side: float in [1.0, -1.0]:
			var o0 := HW * side
			var o1 := (HW + KERB_W) * side
			var o2 := (HW + KERB_W + RAIL_W) * side
			var out_hint := Vector3(na.x * side, 0, na.y * side)
			# verge: a strip of packed, blue-shaded snow right at the lane edge
			road.quad(P.call(ca, na, o0, ha + 0.6), P.call(cb, nb, o0, hb + 0.6), P.call(cb, nb, o1, hb + 0.6), P.call(ca, na, o1, ha + 0.6), th["verge"], up)
			if elevated:
				# bridge: wooden rail with snow lying on top
				var rh := RAIL_H + 10.0
				road.quad(P.call(ca, na, o1, ha), P.call(cb, nb, o1, hb), P.call(cb, nb, o1, hb + rh), P.call(ca, na, o1, ha + rh), COL_DECK_LIGHT.darkened(0.12), -out_hint)
				road.quad(P.call(ca, na, o1, ha + rh), P.call(cb, nb, o1, hb + rh), P.call(cb, nb, o2, hb + rh), P.call(ca, na, o2, ha + rh), th["rail_top"], up)
				road.quad(P.call(ca, na, o2, ha - 22.0), P.call(cb, nb, o2, hb - 22.0), P.call(cb, nb, o2, hb + rh), P.call(ca, na, o2, ha + rh), COL_DECK_LIGHT.darkened(0.25), out_hint)
			else:
				# snowbank: a steep shaded inner face, a rounded white crest and a long
				# gentle slope out into the snowfield
				var jag: float = th["bank_jag"]
				var bh: float = th["bank_h"] * (0.92 + 0.08 * sin(smid * 0.021 + side) + jag * 0.18 * sin(smid * 0.11 + side * 2.0) * sin(smid * 0.037))
				var ob := (HW + KERB_W + 5.0) * side
				var oc := (HW + KERB_W + RAIL_W) * side
				var oo := (HW + KERB_W + RAIL_W + BANK_OUT) * side
				# The bank is the landscape itself rising up beside the road: crest and
				# outer slope are drawn with the ground's own shading (vertex alpha 0),
				# so there is no colour change at all between landscape and bank. Only
				# the inner face keeps the theme's bank colour, fading into the ground
				# towards the crest.
				var face_lo: Color = th["bank_face"]
				var face_hi := Color(face_lo, BANK_FACE_TOP)
				var nf := (-out_hint + up * 0.4).normalized()
				var nf_hi := (-out_hint * 0.5 + up).normalized()
				road.quad_smooth([P.call(ca, na, o1, ha), P.call(cb, nb, o1, hb), P.call(cb, nb, ob, hb + bh), P.call(ca, na, ob, ha + bh)],
					[face_lo, face_lo, face_hi, face_hi], [nf, nf, nf_hi, nf_hi])
				var gnd := Color(face_lo, 0.0)
				road.quad_smooth([P.call(ca, na, ob, ha + bh), P.call(cb, nb, ob, hb + bh), P.call(cb, nb, oc, hb + bh), P.call(ca, na, oc, ha + bh)],
					[gnd, gnd, gnd, gnd], [up, up, up, up])
				# outer slope: an S-shaped roll from the crest down to the ground. Its
				# light only hints at the shape (BANK_RELIEF), so the sunny and shady
				# sides never read as a band; at the foot it is level and lit exactly
				# like the ground plane it meets.
				var segs := 6
				var wide := absf(oo - oc)
				for m in segs:
					var t0 := float(m) / segs
					var t1 := float(m + 1) / segs
					var vs: Array = []
					var ns: Array = []
					for corner in [[ca, na, ha, t0], [cb, nb, hb, t0], [cb, nb, hb, t1], [ca, na, ha, t1]]:
						var t: float = corner[3]
						var nn: Vector2 = corner[1]
						var hh: float = bh * 0.5 * (1.0 + cos(PI * t))
						var base: float = corner[2] * (1.0 - t)   # meets the ground (height 0) at the foot
						vs.append(P.call(corner[0], nn, lerpf(oc, oo, t), base + hh))
						var slope := bh * PI * 0.5 * sin(PI * t) / wide * BANK_RELIEF
						ns.append((Vector3(nn.x * side, 0, nn.y * side) * slope + up).normalized())
					road.quad_smooth(vs, [gnd, gnd, gnd, gnd], ns)
		if elevated:
			# deck underside
			var oo := HW + KERB_W + RAIL_W
			road.quad(P.call(ca, na, oo, ha - 22.0), P.call(cb, nb, oo, hb - 22.0), P.call(cb, nb, -oo, hb - 22.0), P.call(ca, na, -oo, ha - 22.0), COL_DECK.darkened(0.3), -up)
			pillar_acc += sb - sa
			if pillar_acc > 260.0 and A["h"] > 70.0 and not _near_bridge_center(ca, HW * 2.4):
				pillar_acc = 0.0
				for side: float in [1.0, -1.0]:
					var pp: Vector2 = ca + na * (HW - 20.0) * side
					var pil := box(Vector3(26, A["h"] - 20.0, 26), COL_DECK, Vector3(pp.x, (A["h"] - 20.0) / 2.0, pp.y))
					static_root.add_child(pil)
		else:
			pillar_acc = 260.0
	var mi := MeshInstance3D.new()
	mi.mesh = road.st.commit()
	mi.material_override = _road_mat()
	# the banks are low and soft: their own shadow only drew a dark, striped band
	# along the outer slope
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	static_root.add_child(mi)

# Loose stuff heaped along both lane edges, half on the verge and half spilling onto
# the lane, so a car rubbing the edge visibly ploughs into it: fresh powder, forest
# undergrowth, scree or soft sand. Purely visual (the edge penalty is in race.gd).
func _build_drifts() -> void:
	var meshes := _drift_meshes()
	var lots: Array = [[], []]
	# a heap never rises above the bank behind it: whatever reaches past the inner
	# face stays buried in the bank instead of drawing a line along its crest
	var cap: float = th["bank_h"] * 0.8
	var tops := [(meshes[0] as Mesh).get_aabb().end.y / U, (meshes[1] as Mesh).get_aabb().end.y / U]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(track.def.get("name", ""))) + 7
	var s := 0.0
	while s < track.L:
		var here := s
		s += 16.0 + rng.randf() * 12.0
		if track.height_at(here) > 2.0 or _near_jump(here):
			continue
		var q := track.point_at(here)
		var t: Vector2 = q["dir"]
		var n := TrackData.perp(t)
		var h := track.height_at(here) + ROAD_Y
		for side: float in [1.0, -1.0]:
			var off := HW + 6.0 + rng.randf() * 10.0
			var p: Vector2 = q["pos"] + n * off * side + t * (rng.randf() - 0.5) * 6.0
			var yaw := -t.angle() + (rng.randf() - 0.5) * 0.5
			var sc := Vector3(1.7 + rng.randf() * 1.0, 1.2 + rng.randf() * 0.8, 1.25 + rng.randf() * 0.4)
			var which := 0 if rng.randf() < 0.65 else 1
			sc.y = minf(sc.y, cap / maxf(tops[which], 1.0))
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(sc), w3(p, h))
			lots[which].append(xf)
	_multi(meshes[0], lots[0])
	_multi(meshes[1], lots[1])

func _near_jump(s: float) -> bool:
	for j in track.jumps:
		var d := fposmod(s - j["s"] + RAMP_LEN + 20.0, track.L)
		if d < RAMP_LEN + GAP + 60.0:
			return true
	return false

# two drift pieces per theme, built about 32 long (x, along the road) and 30 deep
func _drift_meshes() -> Array:
	var a: Color = th["drift_a"]
	var b: Color = th["drift_b"]
	var m1 := SurfaceTool.new()
	var m2 := SurfaceTool.new()
	m1.begin(Mesh.PRIMITIVE_TRIANGLES)
	m2.begin(Mesh.PRIMITIVE_TRIANGLES)
	match String(th["drift"]):
		"brush":
			# low leafy clumps with a little bracken, and a heap of leaf litter and mud
			_band(m1, 0.0, 4.0, 16.0, 15.0, 6, b.darkened(0.15))
			_blob(m1, 7.0, 11.0, a, 0.3, Vector3(-5, 0, 2))
			_blob(m1, 6.0, 8.0, a.lightened(0.1), 1.1, Vector3(7, 0, -3))
			_blob(m1, 4.0, 6.0, a.darkened(0.12), 0.6, Vector3(1, 0, 8))
			_band(m2, 0.0, 3.5, 17.0, 12.0, 7, b.darkened(0.1))
			_band(m2, 3.5, 6.0, 12.0, 0.0, 7, b, 0.4)
			_blob(m2, 4.0, 5.0, a, 0.2, Vector3(-8, 0, -4))
			_blob(m2, 3.5, 4.0, Color("#b0782e"), 0.9, Vector3(7, 0, 5))
		"scree":
			# a scatter of angular stones, and a heap of gravel with a few big ones
			for k in 4:
				var o := Vector3(cos(k * 2.3) * 9.0, 0, sin(k * 1.7) * 8.0)
				var r := 8.0 - k * 1.2
				var c := a.darkened(0.06 * k) if k % 2 == 0 else b.lightened(0.05 * k)
				_band(m1, 0.0, r * 0.7, r, r * 0.65, 5, c, k * 0.9, o)
				_band(m1, r * 0.7, r * 1.0, r * 0.65, 0.0, 5, c.lightened(0.12), k * 0.9, o)
			_band(m2, 0.0, 4.0, 16.0, 11.0, 6, b)
			_band(m2, 4.0, 6.5, 11.0, 0.0, 6, b.lightened(0.08), 0.5)
			for k in 3:
				var o := Vector3(cos(k * 2.1 + 1.0) * 9.0, 2.0, sin(k * 2.1 + 1.0) * 7.0)
				_band(m2, 0.0, 6.0, 6.0 - k, 3.5 - k * 0.5, 5, a.darkened(0.05 * k), k, o)
				_band(m2, 6.0, 8.0, 3.5 - k * 0.5, 0.0, 5, a.lightened(0.1), k, o)
		"sand":
			# a soft drift with a sharp lit crest, and a lower rippled tongue
			_band(m1, 0.0, 3.0, 17.0, 14.0, 8, b)
			_band(m1, 3.0, 7.0, 14.0, 7.0, 8, a, 0.2)
			_band(m1, 7.0, 8.5, 7.0, 0.0, 8, a.lightened(0.08), 0.2)
			_band(m2, 0.0, 2.5, 16.0, 13.0, 7, b.lightened(0.05))
			_band(m2, 2.5, 4.5, 13.0, 0.0, 7, a, 0.3)
			_band(m2, 0.0, 3.5, 7.0, 0.0, 6, a.lightened(0.06), 0.0, Vector3(-11, 0, 6))
		_:
			# fresh powder: a fat soft mound, and a pair of smaller lumps
			_band(m1, 0.0, 3.0, 17.0, 16.0, 7, b)
			_band(m1, 3.0, 7.0, 16.0, 10.0, 7, b.lerp(a, 0.55), 0.2)
			_band(m1, 7.0, 10.0, 10.0, 0.0, 7, a, 0.2)
			_blob(m1, 6.0, 7.0, a, 0.7, Vector3(10, 0, -6))
			_blob(m1, 5.0, 6.0, b.lerp(a, 0.7), 1.3, Vector3(-11, 0, 5))
			_band(m2, 0.0, 2.5, 12.0, 11.0, 7, b)
			_band(m2, 2.5, 7.0, 11.0, 0.0, 7, a, 0.4)
			_band(m2, 0.0, 2.0, 9.0, 8.0, 7, b, 0.0, Vector3(13, 0, 6))
			_band(m2, 2.0, 6.0, 8.0, 0.0, 7, a.darkened(0.02), 0.0, Vector3(13, 0, 6))
	return [m1.commit(), m2.commit()]

# Icy asphalt: glossy ice patches from a cheap value noise, and a ragged band of loose
# snow (dirt, gravel, sand) creeping in from both edges where the edge costs speed.
var _road_m: ShaderMaterial
func _road_mat() -> ShaderMaterial:
	if _road_m == null:
		_make_road_mat()
	for k in ["patch", "streak", "edge"]:
		_road_m.set_shader_parameter(k + "_col", th[k])
	for k in ["patch_amt", "patch_rough", "road_rough"]:
		_road_m.set_shader_parameter(k, th[k])
	var gc: Color = th["ground"]
	_road_m.set_shader_parameter("base_col", gc)
	_road_m.set_shader_parameter("dot_col", th["ground_dots"])
	_road_m.set_shader_parameter("far_col", gc.darkened(0.25))
	_road_m.set_shader_parameter("near_col", gc.lightened(0.12))
	return _road_m

func _make_road_mat() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 patch_col : source_color;
uniform vec3 streak_col : source_color;
uniform vec3 edge_col : source_color;
uniform float patch_amt = 0.5;
uniform float patch_rough = 0.25;
uniform float road_rough = 0.8;
uniform vec3 base_col : source_color;
uniform vec3 dot_col : source_color;
uniform vec3 far_col : source_color;
uniform vec3 near_col : source_color;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec3 c = COLOR.rgb;
	float rough = 0.9;
	if (UV.x > 0.5) {
		vec2 q = wp.xz;
		float n = vnoise(q * 0.6) * 0.7 + vnoise(q * 2.0) * 0.3;
		float ice = smoothstep(0.52, 0.66, n);
		// long polished streaks inside the patches
		float streak = smoothstep(0.7, 0.95, vnoise(vec2(q.x * 3.0 + q.y * 0.4, q.y * 3.0 - q.x * 0.4)));
		c = mix(c, patch_col, ice * patch_amt);
		c = mix(c, streak_col, ice * streak * 0.25);
		// ragged band of loose stuff: a lumpy inner border plus flecks scattered
		// further in, so the edge reads as rough ground rather than a painted line
		float edge = abs(UV.y) + (vnoise(q * 0.9) - 0.5) * 0.10 + (vnoise(q * 4.0) - 0.5) * 0.10;
		float snow = smoothstep(0.84, 0.9, edge);
		float fleck = smoothstep(0.62, 0.72, vnoise(q * 7.0)) * smoothstep(0.66, 0.86, abs(UV.y));
		snow = max(snow, fleck * 0.85);
		c = mix(c, edge_col, snow);
		rough = mix(mix(road_rough, patch_rough, ice), 0.95, snow);
	}
	// the bank's outer slope fades into the ground: same colour formula as the ground plane
	float g = 1.0 - COLOR.a;
	if (g > 0.0) {
		float n = vnoise(wp.xz * 0.35) * 0.65 + vnoise(wp.xz * 1.3) * 0.35;
		float dd = smoothstep(0.4, 0.8, n) + step(0.985, hash(floor(wp.xz * 9.0))) * 0.25;
		vec2 uv = SCREEN_UV;
		float v = clamp(uv.y * 0.9 + 0.1, 0.0, 1.0);
		vec3 grad = mix(far_col, near_col, v);
		float vig = smoothstep(0.95, 0.25, length((uv - vec2(0.5, 0.62)) * vec2(1.0, 1.25)));
		vec3 gc = mix(base_col * 0.72, grad, 0.35 + 0.65 * vig);
		gc = mix(gc, gc + (dot_col - base_col), dd);
		c = mix(c, gc, g);
		rough = mix(rough, 1.0, g);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
"""
	_road_m = ShaderMaterial.new()
	_road_m.shader = sh

# ---------------------------------------------------------------- winter scenery
# Low-poly snowy pines, shacks and rocks, all instanced (one draw call per kind) and
# placed off the road from a seeded generator so each track always looks the same.
const SCN_CELL := 40.0
const SCN_MARGIN := 2000.0
const COL_PINE := Color("#2f5a4a")
const COL_PINE_DARK := Color("#244538")
const COL_SNOW := Color("#eef3f7")
const COL_TRUNK := Color("#5b4636")
const COL_WOOD := Color("#7d5a3e")
const COL_ROCK := Color("#7d8791")

# one flat-shaded cone frustum band, `sides` faces
static func _band(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, sides: int, col: Color, rot := 0.0, off := Vector3.ZERO) -> void:
	for k in sides:
		var a0 := rot + TAU * k / sides
		var a1 := rot + TAU * (k + 1) / sides
		var p0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var p2 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		var p3 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var nrm := (p1 - p0).cross(p3 - p0) if r1 > 0.001 else (p1 - p0).cross(p2 - p0)
		nrm = -nrm.normalized()
		if nrm.dot(Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))) < 0.0:
			nrm = -nrm
		st.set_color(col)
		st.set_normal(nrm)
		for v in [p0, p1, p2, p0, p2, p3]:
			st.add_vertex((v + off) * U)

# a pine: trunk and stacked tiers, each tier green below and snow-capped on top
static func _pine_mesh(tiers: int, h: float, r: float, snowy := true) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(st, 0.0, h * 0.2, r * 0.16, r * 0.13, 5, COL_TRUNK)
	var y := h * 0.14
	var th := (h - y) / tiers * 1.35
	for t in tiers:
		var rr := r * (1.0 - 0.22 * t)
		var y_top := y + th
		var rot := 0.5 * t
		var snow_y := y + th * 0.55
		var r_mid := rr * 0.45
		var green := COL_PINE if t % 2 == 0 else COL_PINE_DARK
		if snowy:
			_band(st, y, snow_y, rr, r_mid, 7, green, rot)
			_band(st, snow_y - 0.01, y_top, r_mid * 1.06, 0.0, 7, COL_SNOW, rot)
			# a white snow rim on the lower edge of each tier
			_band(st, y + th * 0.02, y - th * 0.06, rr * 0.9, rr * 1.04, 7, COL_SNOW.darkened(0.05), rot)
		else:
			_band(st, y, y_top, rr, 0.0, 7, green.lightened(0.08), rot)
		y += th * 0.62
	return st.commit()

# a log shack: walls, snow-laden gable roof, door, window, chimney. Long side along x.
static func _shack_mesh(wood := COL_WOOD, roof_top := COL_SNOW, shingle := Color("#6e3f2c")) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := 70.0; var hz := 50.0; var wall := 55.0; var ridge := 100.0; var eave := 14.0
	var faces := func(pts: Array, col: Color) -> void:
		var a: Vector3 = pts[0]; var b: Vector3 = pts[1]; var c: Vector3 = pts[2]
		var nrm := (b - a).cross(c - a).normalized()
		st.set_color(col)
		st.set_normal(nrm)
		for k in range(1, pts.size() - 1):
			for v in [pts[0], pts[k], pts[k + 1]]:
				st.add_vertex(v * U)
	# walls (counter-clockwise seen from outside)
	faces.call([Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, wall, hz), Vector3(-hx, wall, hz)], wood)
	faces.call([Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), Vector3(-hx, wall, -hz), Vector3(hx, wall, -hz)], wood.darkened(0.15))
	faces.call([Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(hx, wall, -hz), Vector3(hx, ridge - 4, 0), Vector3(hx, wall, hz)], wood.darkened(0.08))
	faces.call([Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(-hx, wall, hz), Vector3(-hx, ridge - 4, 0), Vector3(-hx, wall, -hz)], wood.darkened(0.2))
	# door and window on the front
	faces.call([Vector3(-20, 0, hz + 0.5), Vector3(4, 0, hz + 0.5), Vector3(4, 38, hz + 0.5), Vector3(-20, 38, hz + 0.5)], Color("#a8342a"))
	faces.call([Vector3(22, 22, hz + 0.5), Vector3(48, 22, hz + 0.5), Vector3(48, 42, hz + 0.5), Vector3(22, 42, hz + 0.5)], Color("#ffd98a"))
	# roof: snow on top, dark wood edge under the eaves
	var ex := hx + eave; var ez := hz + eave
	for side: float in [1.0, -1.0]:
		var lo := Vector3(0, wall - 8, ez * side)
		var mid := lo.lerp(Vector3(0, ridge, 0), 0.3)
		var x0 := -ex * side; var x1 := ex * side
		# bare shingles along the eave, snow above
		faces.call([Vector3(x0, lo.y, lo.z), Vector3(x1, lo.y, lo.z), Vector3(x1, mid.y, mid.z), Vector3(x0, mid.y, mid.z)], shingle)
		faces.call([Vector3(x0, mid.y + 0.5, mid.z), Vector3(x1, mid.y + 0.5, mid.z), Vector3(x1, ridge + 1, 0), Vector3(x0, ridge + 1, 0)], roof_top)
		faces.call([Vector3(x1, lo.y - 6, lo.z), Vector3(x0, lo.y - 6, lo.z), Vector3(x0, lo.y, lo.z), Vector3(x1, lo.y, lo.z)], Color("#3b281c"))
	# chimney with a snow cap
	_band(st, wall + 20, ridge + 22, 9.0, 9.0, 4, Color("#6b6f75"), PI / 4)
	_band(st, ridge + 22, ridge + 26, 11.0, 0.0, 4, roof_top, PI / 4)
	return st.commit()

# a snow-topped boulder: a squashed low-poly dome
static func _rock_mesh(stone := COL_ROCK, top := COL_SNOW) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(st, -4.0, 16.0, 40.0, 33.0, 5, stone)
	_band(st, 16.0, 28.0, 33.0, 16.0, 5, stone.lightened(0.12), 0.3)
	_band(st, 27.0, 33.0, 17.0, 0.0, 5, top, 0.3)
	return st.commit()

# a faceted ball (three bands), for leafy crowns and shrubs
static func _blob(st: SurfaceTool, cy: float, r: float, col: Color, rot := 0.0, off := Vector3.ZERO) -> void:
	_band(st, cy - r, cy - r * 0.35, r * 0.25, r * 0.95, 6, col.darkened(0.1), rot, off)
	_band(st, cy - r * 0.35, cy + r * 0.35, r * 0.95, r * 0.85, 6, col, rot + 0.5, off)
	_band(st, cy + r * 0.35, cy + r, r * 0.85, 0.0, 6, col.lightened(0.08), rot + 0.5, off)

const COL_LEAF := Color("#4f8a3a")
const COL_LEAF_DARK := Color("#3d7030")
const COL_MOSS := Color("#5c8a3a")

# forest: a round broadleaf tree, two or three leafy balls on a trunk
static func _leafy_mesh(h: float, r: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(st, 0.0, h * 0.45, r * 0.16, r * 0.12, 5, COL_TRUNK)
	_blob(st, h * 0.55, r, col)
	_blob(st, h * 0.78, r * 0.7, col.lightened(0.06), 0.8, Vector3(r * 0.25, 0, -r * 0.2))
	return st.commit()

# rock: a stack of tilted stone slabs narrowing to a flat top
static func _spire_mesh(h: float, r: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.0
	var rr := r
	for k in 4:
		var hh := h * (0.34 - k * 0.05)
		var c := col.lightened(0.05 * k) if k % 2 == 0 else col.darkened(0.08)
		var o := Vector3(sin(k * 2.1) * r * 0.12, 0, cos(k * 1.7) * r * 0.12)
		_band(st, y, y + hh, rr, rr * 0.82, 6, c, k * 0.7, o)
		_band(st, y + hh, y + hh + 0.5, rr * 0.82, 0.0, 6, c.lightened(0.1), k * 0.7, o)
		y += hh
		rr *= 0.74
	return st.commit()

static func _shrub_mesh(r: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_blob(st, r * 0.6, r, col)
	_blob(st, r * 0.5, r * 0.7, col.darkened(0.1), 1.0, Vector3(r * 0.7, 0, r * 0.3))
	return st.commit()

# sand: a saguaro-style cactus, a trunk with two bent arms
static func _cactus_mesh(h: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := h * 0.09
	_band(st, 0.0, h, r, r * 0.9, 6, col)
	_band(st, h, h + r * 0.7, r * 0.9, 0.0, 6, col.lightened(0.08))
	for side: float in [1.0, -1.0]:
		var ay := h * (0.4 if side > 0 else 0.55)
		var ax := r * 2.1 * side
		var ar := r * 0.65
		# the elbow and the upright part of the arm
		_band(st, ay - ar, ay + ar, ar, ar, 6, col.darkened(0.05), 0.0, Vector3(ax * 0.6, 0, 0))
		_band(st, ay, ay + h * 0.32, ar, ar * 0.9, 6, col, 0.0, Vector3(ax, 0, 0))
		_band(st, ay + h * 0.32, ay + h * 0.32 + ar * 0.7, ar * 0.9, 0.0, 6, col.lightened(0.08), 0.0, Vector3(ax, 0, 0))
	return st.commit()

# sand: a palm with a leaning trunk and a crown of drooping fronds
static func _palm_mesh(h: float, col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 5
	for k in segs:
		var y0 := h * k / segs
		var lean := Vector3(pow(float(k) / segs, 2.0) * h * 0.18, 0, 0)
		_band(st, y0, y0 + h / segs, 8.0 - k * 0.6, 7.4 - k * 0.6, 5, Color("#8a6a48").darkened(0.08 * (k % 2)), k * 0.4, lean)
	var top := Vector3(h * 0.18, 0, 0)
	_band(st, h - 6.0, h + 10.0, 50.0, 0.0, 7, col, 0.2, top)
	_band(st, h - 14.0, h - 4.0, 62.0, 46.0, 7, col.darkened(0.15), 0.65, top)
	return st.commit()

# a flat-roofed hut (adobe or dry stone), door on the front (+z)
static func _hut_mesh(wall: Color, roof: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(st, 0.0, 58.0, 72.0, 70.0, 4, wall, PI / 4)
	_band(st, 58.0, 66.0, 76.0, 76.0, 4, roof, PI / 4)
	_band(st, 66.0, 66.5, 76.0, 0.0, 4, roof.lightened(0.08), PI / 4)
	# door and a small window as thin dark slabs on the front wall
	_band(st, 0.0, 36.0, 10.0, 10.0, 4, Color("#3b281c"), PI / 4, Vector3(-14, 0, 47))
	_band(st, 30.0, 44.0, 8.0, 8.0, 4, Color("#ffd98a"), PI / 4, Vector3(24, 0, 47))
	return st.commit()

# instances go into ~16 m tiles so the camera only draws (and shadows) the nearby ones
func _multi(mesh: Mesh, xforms: Array) -> void:
	var tiles := {}
	for xf: Transform3D in xforms:
		var key := Vector2i(floori(xf.origin.x / 16.0), floori(xf.origin.z / 16.0))
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(xf)
	for key in tiles:
		_multi_tile(mesh, tiles[key])

func _multi_tile(mesh: Mesh, xforms: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _vert_mat
	static_root.add_child(mi)

func _build_scenery() -> void:
	var b := track.bounds.grow(SCN_MARGIN)
	var gw := ceili(b.size.x / SCN_CELL)
	var gh := ceili(b.size.y / SCN_CELL)
	# occupancy: 1 = keep clear (road, rails, tower infields), 2 = taken by a prop
	var occ := PackedByteArray()
	occ.resize(gw * gh)
	var mark := func(p: Vector2, r: float, v: int) -> void:
		var x0 := maxi(0, floori((p.x - r - b.position.x) / SCN_CELL))
		var x1 := mini(gw - 1, floori((p.x + r - b.position.x) / SCN_CELL))
		var y0 := maxi(0, floori((p.y - r - b.position.y) / SCN_CELL))
		var y1 := mini(gh - 1, floori((p.y + r - b.position.y) / SCN_CELL))
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				var cc := b.position + Vector2(gx + 0.5, gy + 0.5) * SCN_CELL
				if cc.distance_squared_to(p) <= r * r and occ[gy * gw + gx] < v:
					occ[gy * gw + gx] = v
	var free := func(p: Vector2) -> bool:
		var gx := floori((p.x - b.position.x) / SCN_CELL)
		var gy := floori((p.y - b.position.y) / SCN_CELL)
		return gx >= 0 and gy >= 0 and gx < gw and gy < gh and occ[gy * gw + gx] == 0
	var clear_r := HW + KERB_W + RAIL_W + BANK_OUT + 10.0
	var s := 0.0
	while s < track.L:
		mark.call(track.point_at(s)["pos"], clear_r, 1)
		s += 30.0
	for a in track.anchors:
		mark.call(a.pos, TrackData.TURN_R + TrackData.WIDEN + 10.0, 1)   # keep the infield under the tethers clear
	var q0 := track.point_at(track.start_s)
	mark.call(q0["pos"], 320.0, 1)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(track.def.get("name", "")))
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.0011
	var pines_a: Array = []
	var pines_b: Array = []
	var shacks: Array = []
	var rocks: Array = []
	var basis_for := func(yaw: float, sc: float) -> Basis:
		return Basis(Vector3.UP, yaw).scaled(Vector3.ONE * sc)

	var kit := _prop_kit()
	# huts first, a few along the outside of the road, facing it
	var n_shacks := clampi(int(track.L / 2600.0), 2, 6)
	var tries := 0
	while shacks.size() < n_shacks and tries < 60:
		tries += 1
		var q := track.point_at(rng.randf() * track.L)
		var nrm := TrackData.perp(q["dir"]) * (1.0 if rng.randf() < 0.5 else -1.0)
		var p: Vector2 = q["pos"] + nrm * (clear_r + 130.0 + rng.randf() * 120.0)
		var ok := true
		for o in [Vector2.ZERO, Vector2(120, 0), Vector2(-120, 0), Vector2(0, 120), Vector2(0, -120)]:
			if not free.call(p + o):
				ok = false
		if not ok:
			continue
		mark.call(p, 170.0, 2)
		# front (+z) faces the road
		var yaw := -(-nrm).angle() + PI / 2
		shacks.append(Transform3D(basis_for.call(yaw, 1.35), w3(p)))

	# forest: jittered grid, kept where the noise says "woods", thinner far out
	var step := 120.0
	var y := b.position.y
	while y < b.end.y:
		var x := b.position.x
		while x < b.end.x:
			var p := Vector2(x + rng.randf() * step, y + rng.randf() * step)
			x += step
			if not free.call(p):
				continue
			var n := noise.get_noise_2d(p.x, p.y)
			var r := rng.randf()
			if n > 0.05 and r < kit["density"] + n:
				var sc := 0.75 + rng.randf() * 0.6
				var xf := Transform3D(basis_for.call(rng.randf() * TAU, sc), w3(p))
				(pines_a if rng.randf() < 0.6 else pines_b).append(xf)
				mark.call(p, 30.0 * sc, 2)
			elif r < kit["rocks"]:
				var rs := 0.6 + rng.randf() * 0.8
				rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rs * 1.4, rs, rs * 0.85)), w3(p)))
				mark.call(p, 40.0, 2)
		y += step
	_multi(kit["a"], pines_a)
	_multi(kit["b"], pines_b)
	_multi(kit["hut"], shacks)
	_multi(kit["rock"], rocks)

# the scenery of each theme: two kinds of "tree", a hut, a rock, and how dense
func _prop_kit() -> Dictionary:
	match String(th["props"]):
		"forest":
			return { "a": _leafy_mesh(170.0, 52.0, COL_LEAF), "b": _pine_mesh(4, 210.0, 56.0, false),
				"hut": _shack_mesh(COL_WOOD, COL_MOSS, Color("#4a3a2a")), "rock": _rock_mesh(COL_ROCK, COL_MOSS),
				"density": 0.6, "rocks": 0.04 }
		"rock":
			return { "a": _spire_mesh(260.0, 60.0, Color("#6a6b6a")), "b": _shrub_mesh(26.0, Color("#6f8a48")),
				"hut": _hut_mesh(Color("#8a8a84"), Color("#4f5258")), "rock": _rock_mesh(Color("#7d8078"), Color("#6f8a48")),
				"density": 0.12, "rocks": 0.11 }
		"sand":
			return { "a": _cactus_mesh(140.0, Color("#5f8f4a")), "b": _palm_mesh(220.0, Color("#5f9a3e")),
				"hut": _hut_mesh(Color("#d9a874"), Color("#b98858")), "rock": _rock_mesh(Color("#c08a58"), Color("#d9a874")),
				"density": 0.06, "rocks": 0.05 }
	return { "a": _pine_mesh(3, 150.0, 48.0), "b": _pine_mesh(4, 210.0, 56.0),
		"hut": _shack_mesh(), "rock": _rock_mesh(), "density": 0.35, "rocks": 0.035 }

# "Snow & shadows" option: off saves battery on slower phones
var effects_on := true
func set_effects(on: bool) -> void:
	effects_on = on
	light.shadow_enabled = on

# light weather round the camera focus, one CPU particle system of tiny quads:
# snowfall, falling leaves, drifting dust or blowing sand
var snowfall: CPUParticles3D
func _build_weather() -> void:
	snowfall = CPUParticles3D.new()
	var kind := String(th["weather"])
	var col := Color(1, 1, 1, 0.85)
	var size := 0.1
	snowfall.amount = 150
	snowfall.lifetime = 4.5
	snowfall.direction = Vector3(0.35, -1.0, 0.15)
	snowfall.spread = 12.0
	snowfall.initial_velocity_min = 0.9
	snowfall.initial_velocity_max = 1.5
	snowfall.gravity = Vector3(0, -0.3, 0)
	match kind:
		"leaves":
			snowfall.amount = 45
			snowfall.lifetime = 6.0
			snowfall.direction = Vector3(0.5, -1.0, 0.2)
			snowfall.spread = 30.0
			snowfall.initial_velocity_min = 0.5
			snowfall.initial_velocity_max = 0.9
			snowfall.gravity = Vector3(0.1, -0.15, 0)
			size = 0.16
			var g := Gradient.new()
			g.set_color(0, Color("#d98a2b"))
			g.set_color(1, Color("#e8c34a"))
			g.add_point(0.5, Color("#9cb84a"))
			snowfall.color_initial_ramp = g
			col = Color(1, 1, 1, 1)
		"dust":
			snowfall.amount = 40
			snowfall.lifetime = 5.0
			snowfall.direction = Vector3(1.0, -0.15, 0.2)
			snowfall.initial_velocity_min = 0.6
			snowfall.initial_velocity_max = 1.1
			snowfall.gravity = Vector3(0, -0.05, 0)
			col = Color("#e8dccb", 0.55)
			size = 0.12
		"sand":
			snowfall.amount = 120
			snowfall.lifetime = 2.5
			snowfall.direction = Vector3(1.0, -0.08, 0.3)
			snowfall.spread = 6.0
			snowfall.initial_velocity_min = 3.0
			snowfall.initial_velocity_max = 4.5
			snowfall.gravity = Vector3(0, -0.2, 0)
			col = Color("#f3dcaa", 0.6)
			size = 0.07
	snowfall.preprocess = snowfall.lifetime
	snowfall.local_coords = false
	snowfall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snowfall.emission_box_extents = Vector3(14, 0.2, 9)
	snowfall.scale_amount_min = 0.6
	snowfall.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(size, size * (0.6 if kind == "leaves" else 1.0))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	snowfall.mesh = q
	snowfall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dyn_root.add_child(snowfall)

func _build_jumps() -> void:
	for j in track.jumps:
		var s0: float = j["s"]
		var st := Strip.new()
		var up := Vector3.UP
		# an icy crevasse under the gap, with glowing ice lips either side
		var steps := 6
		for k in steps:
			var sa := s0 + GAP * k / steps
			var sb := s0 + GAP * (k + 1) / steps
			var qa := track.point_at(sa); var qb := track.point_at(sb)
			var na := TrackData.perp(qa["dir"]); var nb := TrackData.perp(qb["dir"])
			var w := HW + KERB_W + RAIL_W
			st.quad(w3(qa["pos"] + na * w, 0.6), w3(qb["pos"] + nb * w, 0.6), w3(qb["pos"] - nb * w, 0.6), w3(qa["pos"] - na * w, 0.6), (th["gap_edge"] as Color).lerp(th["gap_mid"], 0.5 - 0.5 * cos(TAU * (k + 0.5) / steps)), up)
		for edge in [s0, s0 + GAP]:
			var q := track.point_at(edge)
			var n := TrackData.perp(q["dir"]) as Vector2
			var d: Vector2 = q["dir"]
			var h := track.height_at(edge) + ROAD_Y
			var w := HW + KERB_W
			st.quad(w3(q["pos"] + n * w - d * 8, h + 1), w3(q["pos"] + n * w + d * 8, h + 1), w3(q["pos"] - n * w + d * 8, h + 1), w3(q["pos"] - n * w - d * 8, h + 1), th["lip"], up)
		# packed-snow kicker with ice-blue chevrons
		var rs := 8
		for k in rs:
			var sa := s0 - RAMP_LEN + RAMP_LEN * k / rs
			var sb := s0 - RAMP_LEN + RAMP_LEN * (k + 1) / rs
			var qa := track.point_at(sa); var qb := track.point_at(sb)
			var na := TrackData.perp(qa["dir"]); var nb := TrackData.perp(qb["dir"])
			var ha := track.height_at(sa) + ROAD_Y + RAMP_H * float(k) / rs
			var hb := track.height_at(sb) + ROAD_Y + RAMP_H * float(k + 1) / rs
			var col: Color = th["ramp_a"] if k % 2 == 0 else th["ramp_b"]
			st.quad(w3(qa["pos"] + na * HW, ha), w3(qb["pos"] + nb * HW, hb), w3(qb["pos"] - nb * HW, hb), w3(qa["pos"] - na * HW, ha), col, up)
		var q_end := track.point_at(s0)
		var ne := TrackData.perp(q_end["dir"]) as Vector2
		var he := track.height_at(s0) + ROAD_Y
		st.quad(w3(q_end["pos"] + ne * HW, he), w3(q_end["pos"] + ne * HW, he + RAMP_H), w3(q_end["pos"] - ne * HW, he + RAMP_H), w3(q_end["pos"] - ne * HW, he), th["bank_face"], -Vector3(q_end["dir"].x, 0, q_end["dir"].y))
		var mi := MeshInstance3D.new()
		mi.mesh = st.st.commit()
		mi.material_override = _vert_mat
		static_root.add_child(mi)

func _checker_tex(w: int, h: int) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	for x in w:
		for y in h:
			img.set_pixel(x, y, COL_CHALK if (x + y) % 2 else Color("#151515"))
	return ImageTexture.create_from_image(img)

func _build_start() -> void:
	var q := track.point_at(track.start_s)
	var d: Vector2 = q["dir"]
	var h := track.height_at(track.start_s) + ROAD_Y + 0.8
	var cell := HW / 8.0
	var m := StandardMaterial3D.new()
	m.albedo_texture = _checker_tex(2, 16)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.8
	var qm := QuadMesh.new()
	qm.size = Vector2(cell * 2, HW * 2) * U
	qm.orientation = PlaneMesh.FACE_Y
	qm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	mi.position = w3(q["pos"], h)
	mi.rotation.y = -d.angle()
	static_root.add_child(mi)
	# start gantry
	var g := Node3D.new()
	g.position = w3(q["pos"], track.height_at(track.start_s))
	g.rotation.y = -d.angle()
	var span := HW + KERB_W + RAIL_W + 14.0
	for side: float in [1.0, -1.0]:
		g.add_child(box(Vector3(14, 190, 14), COL_TOWER, Vector3(0, 95, span * side)))
	var beam := box(Vector3(20, 34, span * 2 + 14), COL_TOWER, Vector3(0, 190, 0))
	g.add_child(beam)
	var bm := StandardMaterial3D.new()
	bm.albedo_texture = _checker_tex(16, 2)
	bm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	for face in [1.0, -1.0]:
		var bq := QuadMesh.new()
		bq.size = Vector2(span * 2, 28) * U
		bq.material = bm
		var bqi := MeshInstance3D.new()
		bqi.mesh = bq
		bqi.position = Vector3(11 * face, 190, 0) * U
		bqi.rotation.y = PI / 2 * face
		g.add_child(bqi)
	static_root.add_child(g)

# One rotor per curve, at the height of its (flat) bend. A tower that carries two curves
# shows both rotors stacked: the lower one wide, the upper one narrower, each turning
# with its own curve.
func _build_towers() -> void:
	rotor_h.resize(track.anchors.size())
	var homes := {}
	for idx in track.anchors.size():
		var h: int = track.anchors[idx].home
		if not homes.has(h):
			homes[h] = []
		homes[h].append(idx)
	for h in homes:
		var curves: Array = homes[h]
		# lower bend first; on the same level the wider curve goes below
		curves.sort_custom(func(x, y):
			var lx: int = track.arc_level[x]; var ly: int = track.arc_level[y]
			if lx != ly: return lx < ly
			return track.anchors[x].r > track.anchors[y].r)
		var a0: TrackData.Anchor = track.anchors[h]
		var t := Node3D.new()
		t.position = w3(a0.pos, 0.0)
		var y_prev := 0.0
		for m in curves.size():
			var idx: int = curves[m]
			var road_h: float = track.arc_level[idx] * TrackData.LEVEL_H
			var y := maxf(road_h + TOWER_H, y_prev + 70.0)
			rotor_h[idx] = y
			var wide := 1.0 if m == 0 else 0.68
			# six-sided slate column up to this rotor, narrowing above the first one,
			# with a drift of snow round its foot
			var col_r := 32.0 * wide
			if m == 0:
				t.add_child(cyl(52, 12, th["foot"], Vector3(0, 6, 0), 66, 12))
			t.add_child(cyl(col_r, y - y_prev, th["column"], Vector3(0, y_prev + (y - y_prev) / 2.0, 0), col_r + (6.0 if m == 0 else 2.0), 6))
			# snow cap with a ring of icicles under its lip
			t.add_child(cyl(col_r + 7.0, 9, th["cap"], Vector3(0, y + 3.5, 0), col_r + 9.0, 6))
			for k in (6 if th["icicles"] else 0):
				var an := TAU * (k + 0.5) / 6.0
				var ln := 12.0 + 7.0 * float((k * 5 + m) % 3)
				var rr := (col_r + 6.0) * 0.92
				var ic := cyl(3.2, ln, COL_ICE, Vector3(cos(an) * rr, y - 1.0 - ln / 2.0, sin(an) * rr), 0.0, 5)
				ic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				t.add_child(ic)
			var spinner := Node3D.new()
			spinner.position = Vector3(0, y + 8, 0) * U
			# a wooden capstan that winds the tether: rope coiled round a drum, four
			# handles to show which way it turns (one lit amber), snow on the top
			var dr := 21.0 * wide
			spinner.add_child(cyl(dr, 18, COL_WOOD, Vector3(0, 9, 0), dr + 2.0, 12))
			for b in 3:
				spinner.add_child(cyl(dr + 1.5, 3, COL_ROPE, Vector3(0, 4.0 + b * 4.5, 0), dr + 1.5, 12))
			spinner.add_child(cyl(dr + 3.0, 3, COL_WOOD.darkened(0.45), Vector3(0, 19.5, 0), dr + 3.0, 12))
			for k in 4:
				var arm := Node3D.new()
				arm.rotation.y = TAU * k / 4.0
				var reach := 36.0 * wide
				arm.add_child(box(Vector3(reach - dr + 4.0, 5, 5), COL_WOOD.darkened(0.15), Vector3((reach + dr) * 0.5, 16, 0)))
				var tip := box(Vector3(11, 10, 11) if k == 0 else Vector3(8, 8, 8), COL_POST if k == 0 else th["hub"], Vector3(reach, 16, 0))
				if k == 0:
					tip.mesh.material = mat(COL_POST, false, 0.6)
				arm.add_child(tip)
				spinner.add_child(arm)
			spinner.add_child(cyl(dr * 0.4, 4, th["hub"], Vector3(0, 22.5, 0), dr * 0.62, 10))
			t.add_child(spinner)
			var rings: Array = []
			for r in 2:
				var tm := TorusMesh.new()
				tm.inner_radius = (40.0 * wide + 6.0 + r * 10.0) * U
				tm.outer_radius = (45.0 * wide + 6.0 + r * 10.0) * U
				tm.rings = 32
				tm.ring_segments = 6
				var ri := MeshInstance3D.new()
				ri.mesh = tm
				ri.position = Vector3(0, y + 8, 0) * U
				ri.visible = false
				ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				t.add_child(ri)
				rings.append(ri)
			tower_nodes[idx] = { "spinner": spinner, "rings": rings }
			y_prev = y + 8.0
		static_root.add_child(t)

func _build_posts() -> void:
	for o in track.obstacles:
		var p := Node3D.new()
		var r: float = o["r"]
		p.position = w3(o["pos"], 0.0)
		p.add_child(cyl(r, 46, COL_CHALK, Vector3(0, 23, 0)))
		p.add_child(cyl(r + 0.6, 16, COL_KERB, Vector3(0, 26, 0)))
		p.add_child(cyl(r * 0.4, 4, COL_KERB, Vector3(0, 47, 0)))
		static_root.add_child(p)
		post_nodes.append(p)

func _build_gems() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(30, 30, 30) * U
	bm.material = mat(COL_GEM.darkened(0.1), true)
	for g in track.tokens:
		var mi := MeshInstance3D.new()
		mi.mesh = bm
		var h := track.height_at(g["s"])
		mi.position = w3(g["pos"], h + 34.0)
		mi.rotation = Vector3(PI / 4, 0, PI / 4)
		mi.set_meta("base_y", mi.position.y)
		dyn_root.add_child(mi)
		gem_nodes.append(mi)

func _build_fx() -> void:
	# sparks: a small pool of plain boxes with one shared unshaded material per colour
	# (no per-instance colours, which some mobile GPUs rendered as a stray green cube)
	spark_pool.clear()
	spark_mats.clear()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(7, 7, 7) * U
	for k in SPARK_MAX:
		var mi := MeshInstance3D.new()
		mi.mesh = pbox
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dyn_root.add_child(mi)
		spark_pool.append(mi)

	skid_mm = MultiMeshInstance3D.new()
	var sm := MultiMesh.new()
	sm.transform_format = MultiMesh.TRANSFORM_3D
	sm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(14, 14) * U
	q.orientation = PlaneMesh.FACE_Y
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float now;
varying float a;
void vertex() { a = clamp(INSTANCE_CUSTOM.y - (now - INSTANCE_CUSTOM.x) * 0.05, 0.0, 1.0); }
void fragment() { ALBEDO = vec3(0.04, 0.05, 0.06); ALPHA = a; }
"""
	skid_mat = ShaderMaterial.new()
	skid_mat.shader = sh
	q.material = skid_mat
	sm.mesh = q
	sm.instance_count = SKID_MAX
	sm.visible_instance_count = 0
	skid_mm.multimesh = sm
	skid_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	skid_next = 0
	skid_count = 0
	dyn_root.add_child(skid_mm)

# ---------------------------------------------------------------- cars
# glossy toy-car paint: low roughness, a clear coat and a rim light so the body reads
# as shaded rather than flat
static func paint(c: Color, rough := 0.32) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = 0.05
	m.metallic_specular = 0.6
	m.rim_enabled = true
	m.rim = 0.35
	m.rim_tint = 0.6
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.2
	return m

static func pbox(size: Vector3, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size * U
	bm.material = m
	mi.mesh = bm
	mi.position = pos * U
	return mi

# a polygon with each corner cut to a curve of about radius r
static func rounded(poly: PackedVector2Array, r: float, segs := 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var a := p + (poly[(i + n - 1) % n] - p).normalized() * r
		var b := p + (poly[(i + 1) % n] - p).normalized() * r
		for k in segs + 1:   # quadratic curve a -> p -> b
			var t := float(k) / segs
			out.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
	return out

# a prism: a side profile (x, y) extruded across the car (z), centred on z = 0
static func pprism(profile: PackedVector2Array, depth: float, m: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat faces
	var hz := depth * 0.5
	var n := profile.size()
	for side: float in [1.0, -1.0]:   # the two flat sides
		for i in range(1, n - 1):
			var tri := [profile[0], profile[i], profile[i + 1]]
			if side > 0.0:
				tri.reverse()
			for v: Vector2 in tri:
				st.add_vertex(Vector3(v.x, v.y, hz * side) * U)
	for i in n:   # the faces around the profile
		var a := profile[i]
		var b := profile[(i + 1) % n]
		for v: Vector3 in [Vector3(a.x, a.y, -hz), Vector3(b.x, b.y, hz), Vector3(b.x, b.y, -hz),
				Vector3(a.x, a.y, -hz), Vector3(a.x, a.y, hz), Vector3(b.x, b.y, hz)]:
			st.add_vertex(v * U)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	return mi

var _blob_tex: Texture2D

func _blob_shadow() -> MeshInstance3D:
	if _blob_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.55))
		g.set_color(1, Color(0, 0, 0, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_blob_tex = gt
	var m := StandardMaterial3D.new()
	m.albedo_texture = _blob_tex
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var q := QuadMesh.new()
	q.size = Vector2(175, 115) * U
	q.orientation = PlaneMesh.FACE_Y
	q.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = Vector3(0, 1.2, 0) * U
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _make_car(col: Color, ghost := false) -> Node3D:
	var root := Node3D.new()
	var chassis := Node3D.new()   # follows the road slope
	root.add_child(chassis)
	var body := Node3D.new()      # sprung: pitch, roll, heave
	chassis.add_child(body)
	var parts_list: Array = []
	if ghost:
		var gc := Color(COL_CHALK, 0.35)
		parts_list.append(box(Vector3(130, 26, 74), gc, Vector3(0, 24, 0)))
		parts_list.append(box(Vector3(46, 20, 56), Color(COL_INFIELD, 0.35), Vector3(-4, 46, 0)))
	else:
		chassis.add_child(_blob_shadow())
	if not ghost:
		var top := paint(col)
		var low := paint(col.darkened(0.38), 0.5)
		var glass := paint(Color("#1a2330"), 0.08)
		glass.metallic = 0.4
		# a low painted racer body with a bubble cab; the theme kit adds the rest
		var dark := paint(Color("#1d2229"), 0.6)
		parts_list.append(pbox(Vector3(104, 10, 54), low, Vector3(-6, 17, 0)))     # belly
		parts_list.append(pbox(Vector3(92, 14, 60), top, Vector3(-12, 29, 0)))     # body
		# nose: the bonnet slopes down from the windscreen to the lamps
		parts_list.append(pprism(PackedVector2Array([Vector2(30, 20), Vector2(67, 20),
				Vector2(67, 28), Vector2(30, 36)]), 54.0, top))
		# one tinted glasshouse: the windscreen is its sloped front face
		parts_list.append(pprism(PackedVector2Array([Vector2(-26, 35), Vector2(30, 35),
				Vector2(12, 51), Vector2(-26, 51)]), 50.0, glass))
		parts_list.append(pbox(Vector3(36, 3, 50), top, Vector3(-8, 52, 0)))      # roof
		parts_list.append(pbox(Vector3(14, 5, 66), low, Vector3(-56, 41, 0)))     # rear spoiler
		parts_list.append(pbox(Vector3(5, 6, 5), low, Vector3(-56, 36, 22)))
		parts_list.append(pbox(Vector3(5, 6, 5), low, Vector3(-56, 36, -22)))
		var lamp := mat(Color("#fff4c8"), true)
		for lz in [-17.0, 17.0]:
			parts_list.append(pbox(Vector3(3, 5, 12), lamp, Vector3(67.5, 25, lz)))
		var tail := mat(Color("#ff4a3a"), false, 1.2)
		parts_list.append(pbox(Vector3(3, 5, 12), tail, Vector3(-59, 28, 22)))
		parts_list.append(pbox(Vector3(3, 5, 12), tail, Vector3(-59, 28, -22)))
		match String(th["kit"]):
			"forest": _car_kit_forest(chassis, parts_list, top, dark)
			"rock": _car_kit_rock(chassis, parts_list, top, dark)
			"sand": _car_kit_sand(chassis, parts_list, top, dark)
			"snow": _car_kit_snow(chassis, parts_list, top, dark)
	for p in parts_list:
		if ghost:
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(p)
	root.set_meta("body", body)
	root.set_meta("chassis", chassis)
	return root

# Snow: a short ski on each front corner and a crawler track on each back corner, in the
# spots where the other kits put their wheels, between the road (y 0) and the belly.
func _car_kit_snow(chassis: Node3D, parts_list: Array, top: Material, dark: Material) -> void:
	var ski := paint(Color("#e9eef2"), 0.4)
	var tread := paint(Color("#22262c"), 0.85)
	var lug := paint(Color("#59636e"), 0.7)
	for side: float in [1.0, -1.0]:
		var z := 33.0 * side
		chassis.add_child(pbox(Vector3(38, 3, 13), ski, Vector3(44, 1.5, z)))
		var tip := pbox(Vector3(14, 3, 13), ski, Vector3(66, 5.0, z))   # up-turned tip
		tip.rotation.z = 0.6
		chassis.add_child(tip)
		chassis.add_child(pbox(Vector3(8, 12, 6), dark, Vector3(42, 9, z * 0.85)))
		# crawler track: a trapezoid side (long top, short bottom, ends at 45°), rounded corners
		var trk := pprism(rounded(PackedVector2Array([Vector2(-44, 0), Vector2(-24, 0),
				Vector2(-4, 20), Vector2(-64, 20)]), 5.0), 16.0, tread)
		trk.position.z = z * U
		chassis.add_child(trk)
		for k in 6:   # tread stripes, trimmed to the sloped ends
			var lx := -54.0 + k * 8.0
			var y0 := maxf(0.0, maxf(-44.0 - lx, lx + 24.0)) + 0.5
			chassis.add_child(pbox(Vector3(3, 20.5 - y0 + 0.5, 17), lug, Vector3(lx, (y0 + 20.5) * 0.5, z)))

# a wheel on the chassis: tyre plus a painted hub on the outer face
func _wheel(chassis: Node3D, x: float, z: float, r: float, w: float, tyre: Material, hub: Material) -> void:
	for layer in 2:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var rr := r if layer == 0 else r * 0.5
		cm.top_radius = rr * U; cm.bottom_radius = rr * U
		cm.height = (w if layer == 0 else w + 2.0) * U
		cm.radial_segments = 14; cm.rings = 1
		cm.material = tyre if layer == 0 else hub
		mi.mesh = cm
		mi.position = Vector3(x, r, z) * U
		mi.rotation.x = PI / 2
		chassis.add_child(mi)

# Forest: chunky knobbly wheels and a couple of logs strapped on the roof
func _car_kit_forest(chassis: Node3D, parts_list: Array, top: Material, dark: Material) -> void:
	var tyre := paint(Color("#1b1d1a"), 0.85)
	for wx in [-38.0, 40.0]:
		for wz in [-36.0, 36.0]:
			_wheel(chassis, wx, wz, 17.0, 16.0, tyre, top)
	var bark := paint(Color("#6b4a2e"), 0.85)
	var cut := paint(Color("#d8b47a"), 0.7)
	for lz in [-10.0, 10.0]:
		var lg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 7.0 * U; cm.bottom_radius = 7.0 * U; cm.height = 70.0 * U
		cm.radial_segments = 8; cm.rings = 1
		cm.material = bark
		lg.mesh = cm
		lg.position = Vector3(-10, 61, lz) * U
		lg.rotation.z = PI / 2
		parts_list.append(lg)
		parts_list.append(pbox(Vector3(1, 11, 11), cut, Vector3(25.5, 61, lz)))
	parts_list.append(pbox(Vector3(4, 4, 34), dark, Vector3(-30, 55, 0)))
	parts_list.append(pbox(Vector3(4, 4, 34), dark, Vector3(10, 55, 0)))

# Rock: big crawler tyres, a bull bar and roof spotlights
func _car_kit_rock(chassis: Node3D, parts_list: Array, top: Material, dark: Material) -> void:
	var tyre := paint(Color("#1b1b1d"), 0.9)
	for wx in [-40.0, 44.0]:
		for wz in [-38.0, 38.0]:
			_wheel(chassis, wx, wz, 21.0, 19.0, tyre, dark)
	var steel := paint(Color("#9aa0a6"), 0.35)
	steel.metallic = 0.6
	parts_list.append(pbox(Vector3(3, 4, 54), steel, Vector3(71, 33, 0)))   # bull bar
	parts_list.append(pbox(Vector3(3, 4, 54), steel, Vector3(71, 22, 0)))
	for bz in [-24.0, 24.0]:
		parts_list.append(pbox(Vector3(4, 15, 4), steel, Vector3(71, 27.5, bz)))
	parts_list.append(pbox(Vector3(60, 3, 8), dark, Vector3(0, 12, 0)))       # skid plate
	var lamp := mat(Color("#fff4c8"), true)
	parts_list.append(pbox(Vector3(5, 5, 44), dark, Vector3(8, 56, 0)))
	for lz in [-14.0, 0.0, 14.0]:
		parts_list.append(pbox(Vector3(3, 6, 9), lamp, Vector3(11, 56, lz)))

# Sand: wide balloon tyres, a roll bar and a whip flag in the car's colour
func _car_kit_sand(chassis: Node3D, parts_list: Array, top: Material, dark: Material) -> void:
	var tyre := paint(Color("#2a2622"), 0.9)
	var rim := paint(Color("#e9e2d4"), 0.4)
	for wx in [-40.0, 42.0]:
		for wz in [-38.0, 38.0]:
			_wheel(chassis, wx, wz, 17.0, 24.0, tyre, rim)
	parts_list.append(pbox(Vector3(5, 26, 5), dark, Vector3(-30, 50, 26)))
	parts_list.append(pbox(Vector3(5, 26, 5), dark, Vector3(-30, 50, -26)))
	parts_list.append(pbox(Vector3(5, 5, 57), dark, Vector3(-30, 62, 0)))
	parts_list.append(pbox(Vector3(2, 70, 2), dark, Vector3(-52, 72, -24)))  # whip
	parts_list.append(pbox(Vector3(18, 12, 1.5), top, Vector3(-43, 100, -24)))  # flag
	var sand := pbox(Vector3(22, 3, 40), paint(Color("#e6c891"), 0.95), Vector3(46, 32.5, 4))  # sand on the bonnet
	sand.rotation.z = -0.21   # follows the bonnet slope
	parts_list.append(sand)

func setup_cars(race: Race, has_ghost: bool) -> void:
	for cn in car_nodes:
		cn["root"].queue_free()
		cn["tether"].queue_free()
	car_nodes.clear()
	if ghost_node:
		ghost_node.queue_free()
		ghost_node = null
	for c in race.cars:
		var root := _make_car(c.color)
		dyn_root.add_child(root)
		var tm := CylinderMesh.new()
		tm.top_radius = 3.5 * U
		tm.bottom_radius = 3.5 * U
		tm.height = 1.0
		tm.radial_segments = 6
		tm.rings = 1
		tm.material = mat(c.color, true)
		var tether := MeshInstance3D.new()
		tether.mesh = tm
		tether.visible = false
		tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		dyn_root.add_child(tether)
		var marker: MeshInstance3D = null
		if c.human >= 0:
			marker = cyl(16, 26, c.color, Vector3(0, 120, 0), 0.0, 3)
			marker.mesh.material = mat(c.color, true)
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(marker)
		car_nodes.append({ "root": root, "body": root.get_meta("body"), "chassis": root.get_meta("chassis"), "tether": tether, "marker": marker,
			"roll": 0.0, "roll_v": 0.0, "pitch": 0.0, "pitch_v": 0.0, "heave": 0.0, "heave_v": 0.0,
			"slope": 0.0, "was_air": false, "prev_vel": c.vel })
	if has_ghost:
		ghost_node = _make_car(COL_CHALK, true)
		ghost_node.visible = false
		dyn_root.add_child(ghost_node)

func car_height(race: Race, c) -> float:
	var base := track.height_at(c.s)
	if c.fall > 0.0:
		return base - (0.9 - c.fall) * 260.0
	if c.air > 0.0 and c.air_max > 0.0:
		var t: float = 1.0 - c.air / c.air_max
		return base + RAMP_H * (1.0 - t) + 70.0 * sin(PI * t)
	for j in track.jumps:  # rolling up the ramp
		var into := fposmod(c.s - j["s"], track.L) - track.L
		if into > -RAMP_LEN and into <= 0.0:
			return base + RAMP_H * (1.0 + into / RAMP_LEN)
	return base

# ---------------------------------------------------------------- per frame
func sync(race: Race, phase: String, ghost_sample, aims: Dictionary, dt: float) -> void:
	fx_time += dt
	# rotors
	for idx in tower_nodes:
		var tn: Dictionary = tower_nodes[idx]
		var a: TrackData.Anchor = track.anchors[idx]
		tn["spinner"].rotation.y = -a.spin
		for m in 2:
			tn["rings"][m].visible = false
	for idx in aims:
		var cols: Array = aims[idx]
		for m in mini(2, cols.size()):
			var ring: MeshInstance3D = tower_nodes[idx]["rings"][m]
			ring.visible = true
			if ring.get_meta("col", Color.BLACK) != cols[m]:
				ring.mesh.material = mat(cols[m], true)
				ring.set_meta("col", cols[m])
	# posts
	for k in post_nodes.size():
		post_nodes[k].visible = not track.obstacles[k]["gone"]
	# gems: hidden once player 1 has them
	if race and race.cars.size():
		var me = race.cars[0]
		for k in gem_nodes.size():
			var g: MeshInstance3D = gem_nodes[k]
			g.visible = not me.got.has(k)
			g.rotation.y = fx_time * 1.8 + k
			g.position.y = g.get_meta("base_y") + sin(fx_time * 3.0 + k) * 0.06
	if race:
		for k in race.cars.size():
			var c = race.cars[k]
			var cn: Dictionary = car_nodes[k]
			var root: Node3D = cn["root"]
			var y := car_height(race, c)
			root.position = w3(c.pos, y + ROAD_Y)
			var spin: float = (0.9 - c.fall) * 3.0 if c.fall > 0.0 else 0.0
			root.rotation = Vector3(0, -(c.h + spin), 0)
			var sc := maxf(0.05, c.fall / 0.9) * 0.8 if c.fall > 0.0 else 1.0
			root.scale = Vector3.ONE * sc
			_suspension(c, cn, dt)
			_plough(c, cn, y, dt)
			if cn["marker"]:
				cn["marker"].visible = phase != "results"
				cn["marker"].position.y = (120.0 + sin(fx_time * 4.0) * 6.0) * U
			# tether: tower top to car
			var tether: MeshInstance3D = cn["tether"]
			if c.hook >= 0:
				var a: TrackData.Anchor = track.anchors[c.hook]
				var dir: Vector2 = (c.pos - a.pos).normalized()
				var from := w3(a.pos + dir * 20.0, rotor_h[c.hook] + 12.0)
				var to := w3(c.pos, y + ROAD_Y + 34.0)
				var mid := (from + to) * 0.5
				var len := from.distance_to(to)
				tether.visible = true
				var yax := (to - from).normalized()
				var xax := yax.cross(Vector3.FORWARD if absf(yax.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
				var zax := xax.cross(yax)
				tether.transform = Transform3D(Basis(xax, yax * len, zax), mid)
			else:
				tether.visible = false
		if ghost_node:
			if ghost_sample != null and phase != "menu":
				ghost_node.visible = true
				var gp := Vector2(ghost_sample.x, ghost_sample.y)
				var nr := track.nearest_raw(gp)
				var gh := track.height_at(track.s_of(nr["i"], nr["t"]))
				ghost_node.position = w3(gp, gh + ROAD_Y)
				ghost_node.rotation = Vector3(0, -ghost_sample.z, 0)
			else:
				ghost_node.visible = false
	_update_fx(dt)

# Visual suspension (gameplay physics untouched). The chassis follows the road slope;
# the body sits on springs: it rolls out of the swing and the drift, squats when
# accelerating, dives when slowed, and bounces on landings and wall hits.
const SUSP_K := 140.0      # spring stiffness (1/s^2)
const SUSP_C := 13.0       # damping (1/s): a little under critical, so it settles with one wobble
const ROLL_PER_ACC := 6.5e-5
const PITCH_PER_ACC := 5.0e-5

func _spring(cn: Dictionary, key: String, target: float, dt: float) -> float:
	var x: float = cn[key]
	var v: float = cn[key + "_v"]
	v += (SUSP_K * (target - x) - SUSP_C * v) * dt
	x += v * dt
	cn[key] = x
	cn[key + "_v"] = v
	return x

func _suspension(c, cn: Dictionary, dt: float) -> void:
	if dt <= 0.0:
		return
	var body: Node3D = cn["body"]
	var chassis: Node3D = cn["chassis"]
	var hd := Vector2.from_angle(c.h)
	var acc: Vector2 = (c.vel - cn["prev_vel"]) / dt
	cn["prev_vel"] = c.vel
	var a_fwd := acc.dot(hd)
	var a_side := acc.dot(TrackData.perp(hd))
	# road slope under the car, signed along the car's heading
	var dir_sign := 1.0
	var td: Vector2 = track.seg_dir[c.seg]
	if td.dot(hd) < 0.0:
		dir_sign = -1.0
	var dh := track.height_at(c.s + 45.0) - track.height_at(c.s - 45.0)
	var slope := atan2(dh * dir_sign, 90.0)
	if c.air > 0.0 and c.air_max > 0.0:
		slope = lerpf(0.2, -0.16, 1.0 - c.air / c.air_max)  # nose up off the ramp, down for the landing
	cn["slope"] = lerpf(cn["slope"], slope, minf(1.0, dt * 12.0))
	chassis.rotation = Vector3(0, 0, cn["slope"])
	# landing and wall knocks
	var airborne: bool = c.air > 0.0
	if cn["was_air"] and not airborne:
		cn["heave_v"] -= 260.0
		cn["pitch_v"] -= 1.6
	cn["was_air"] = airborne
	var roll_t := clampf(-a_side * ROLL_PER_ACC, -0.16, 0.16)
	var pitch_t := clampf(a_fwd * PITCH_PER_ACC, -0.12, 0.12)
	if airborne:
		roll_t = 0.0
		pitch_t = 0.0
	var roll := _spring(cn, "roll", roll_t, dt)
	var pitch := _spring(cn, "pitch", pitch_t, dt)
	var heave := _spring(cn, "heave", 0.0, dt)
	body.rotation = Vector3(roll, 0, pitch)
	body.position = Vector3(0, clampf(heave, -10.0, 10.0) * U, 0)

# Rubbing the edge throws up whatever lies there (powder, leaves, grit, sand), a
# steady plume to the outside that grows with speed.
func _plough(c, cn: Dictionary, y: float, dt: float) -> void:
	var sp: float = c.vel.length()
	if c.scrape <= 0.0 or c.air > 0.0 or c.fall > 0.0 or sp < 60.0:
		cn["plough"] = 0.0
		return
	cn["plough"] = float(cn.get("plough", 0.0)) + dt * (16.0 + sp / 10.0)
	var nr := track.nearest(c.pos, c.seg)
	var nv: Vector2 = (c.pos - nr["p"]) / maxf(0.001, nr["d"])
	var fwd: Vector2 = c.vel / sp
	var cols: Array = th["spray"]
	while cn["plough"] >= 1.0:
		cn["plough"] -= 1.0
		var at: Vector2 = c.pos + nv * (TrackData.CR - 6.0) + fwd * (randf() - 0.3) * 40.0
		var v: Vector2 = nv * (60.0 + randf() * 200.0) + c.vel * (0.2 + randf() * 0.45) + fwd.orthogonal() * (randf() - 0.5) * 80.0
		var col: Color = cols[0] if randf() < 0.55 else cols[1]
		_spark(w3(at, y + ROAD_Y + 4.0 + randf() * 8.0), Vector3(v.x, 110.0 + randf() * 230.0, v.y) * U, 0.35 + randf() * 0.4, col, 2.2 + randf() * 2.0)

func handle_event(e: Dictionary) -> void:
	match e["t"]:
		"skid":
			var p: Vector2 = e["pos"]
			var h: float = e["h"]
			var y := track.height_at(e["s"]) + ROAD_Y + 0.5
			var side := Vector2(-sin(h), cos(h)) * 30.0
			for off in [side, -side]:
				var tf := Transform3D(Basis(Vector3.UP, -h), w3(p + off, y))
				skid_mm.multimesh.set_instance_transform(skid_next, tf)
				skid_mm.multimesh.set_instance_custom_data(skid_next, Color(fx_time, e["a"], 0, 0))
				skid_next = (skid_next + 1) % SKID_MAX
				skid_count = mini(SKID_MAX, skid_count + 1)
				skid_mm.multimesh.visible_instance_count = skid_count
		"wall":
			var p: Vector2 = e["pos"]
			var n: Vector2 = e["n"]
			var y := track.height_at(e["s"]) + 20.0
			for k in int(e["count"]):
				var v := Vector2(randf() - 0.5, randf() - 0.5) * 300.0 - n * 140.0
				_spark(w3(p, y), Vector3(v.x, 120 + randf() * 200, v.y) * U, 0.35 + randf() * 0.3, th["spray"][0] if k % 3 else th["spray"][1])
		"post":
			var p: Vector2 = e["pos"]
			var cv: Vector2 = e["vel"]
			for j in 22:
				var an := randf() * TAU
				var sp := 80.0 + randf() * 260.0
				var v := Vector2(cos(an), sin(an)) * sp + cv * 0.5
				_spark(w3(p + Vector2(cos(an), sin(an)) * 16.0, 30.0), Vector3(v.x, 150 + randf() * 250, v.y) * U, 0.4 + randf() * 0.4, COL_KERB if j % 2 else COL_CHALK)
		"shake":
			shake = minf(10.0, maxf(shake, e["v"]))

func _spark(p: Vector3, v: Vector3, life: float, col: Color, sz := 1.0) -> void:
	if parts.size() >= SPARK_MAX:
		parts.pop_front()
	parts.append({ "p": p, "v": v, "life": life, "col": col, "sz": sz })

func _update_fx(dt: float) -> void:
	if skid_mat:
		skid_mat.set_shader_parameter("now", fx_time)
	if spark_pool.is_empty():
		return
	var alive: Array = []
	for p in parts:
		p["life"] -= dt
		if p["life"] <= 0.0:
			continue
		p["v"].y -= 9.0 * dt
		p["p"] += p["v"] * dt
		if p["p"].y < 0.01:
			p["p"].y = 0.01
			p["v"] *= 0.5
		alive.append(p)
	parts = alive
	for k in SPARK_MAX:
		var mi: MeshInstance3D = spark_pool[k]
		if k >= parts.size():
			mi.visible = false
			continue
		var p: Dictionary = parts[k]
		var col: Color = p["col"]
		if not spark_mats.has(col):
			spark_mats[col] = mat(col, true)
		mi.material_override = spark_mats[col]
		mi.position = p["p"]
		mi.scale = Vector3.ONE * maxf(0.05, minf(1.0, p["life"] * 2.5)) * float(p["sz"])
		mi.visible = true
	shake *= pow(0.02, dt)

# ---------------------------------------------------------------- camera
# Same framing rule as the prototype: about 1450 world units across the short side
# of the screen, zooming out to keep two local players in view.
func update_camera(race: Race, phase: String, dt: float, snap := false) -> void:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(1.0, vp.y)
	var target: Vector3
	var vis: float
	var b := track.bounds
	if phase == "attract" and race != null and race.cars.size() > 0:
		# menu backdrop: drift along with an AI car, a little zoomed out
		var lead = race.cars[0]   # the quickest AI, so the view rarely loses the pack
		var p: Vector2 = lead.pos + lead.vel * 0.5
		target = Vector3(p.x, track.height_at(lead.s), p.y)
		vis = 1650.0 * vp.y / minf(vp.x, vp.y)
	elif phase == "menu" or race == null:
		# frame the track in the part of the screen the menu panel leaves free
		var free_w := maxf(200.0, vp.x - menu_cover_px)
		vis = maxf(b.size.y, b.size.x / (free_w / maxf(1.0, vp.y))) * 1.02
		var upp := vis / maxf(1.0, vp.y)
		target = Vector3(b.get_center().x - menu_cover_px * 0.5 * upp, 0, b.get_center().y)
	else:
		var hs: Array = []
		for c in race.cars:
			if c.human >= 0:
				hs.append(c)
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		var hy := 0.0
		for c in hs:
			var p: Vector2 = c.pos + c.vel * 0.35
			mn = mn.min(p)
			mx = mx.max(p)
			hy += track.height_at(c.s)
		hy /= maxf(1.0, hs.size())
		var mid := (mn + mx) * 0.5
		target = Vector3(mid.x, hy, mid.y)
		var short := minf(vp.x, vp.y)
		# the short side shows 1450 units (1550 in portrait, where the width is all you get)
		var base := (1550.0 if vp.y > vp.x else 1450.0) * vp.y / short
		var span := mx - mn + Vector2(500, 500)
		vis = maxf(base, maxf(span.y, span.x / aspect))
		vis = minf(vis, vp.y / 0.14)
	var k := 1.0 if snap else 1.0 - exp(-(3.7 if phase == "menu" else 7.6) * dt)
	cam_t = cam_t.lerp(target, k)
	cam_vis = lerpf(cam_vis, vis, 1.0 if snap else 1.0 - exp(-3.7 * dt))
	var dist := cam_vis * U * 0.5 / tan(deg_to_rad(FOV) * 0.5) * 0.92
	var focus := Vector3(cam_t.x, cam_t.y, cam_t.z) * U
	var off := Vector3(0, sin(PITCH), cos(PITCH)) * dist
	var jitter := Vector3((randf() - 0.5), 0, (randf() - 0.5)) * shake * 2.0 * U
	if snowfall:
		snowfall.emitting = phase != "menu" and effects_on
		snowfall.visible = snowfall.emitting
		snowfall.position = focus + Vector3(0, 5.0 if th["weather"] in ["snow", "leaves"] else 1.2, 0)
		snowfall.emission_box_extents = Vector3(cam_vis * U * 1.1, 0.2, cam_vis * U * 0.7)
	camera.position = focus + off + jitter
	camera.look_at(focus + jitter, Vector3.UP)
	light.directional_shadow_max_distance = clampf(dist * 2.2, 30.0, 200.0)
