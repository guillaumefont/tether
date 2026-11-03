# The 3D view. Builds the track meshes from TrackData and mirrors the race state
# (cars, tethers, spinning towers, posts, gems, effects) every frame.
# World mapping: prototype (x, y) with height h -> Vector3(x, h, y) * U.
extends Node3D

const TrackData = preload("res://scripts/track.gd")
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
const COL_DOTS := Color("#b4c4d1")      # drift shading in the snow
const COL_ASPHALT := Color("#353e49")   # cold, icy asphalt
const COL_CHALK := Color("#ece6d8")
const COL_KERB := Color("#d4452f")
const COL_RAIL := Color("#e6edf2")
const COL_DECK := Color("#7a5a3a")
const COL_DECK_LIGHT := Color("#a07a50")
const COL_POST := Color("#f2b134")
const COL_TOWER := Color("#2a2f36")
const COL_GEM := Color("#7fe3d0")
const COL_PIT := Color("#06100f")

var track: TrackData
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
const SPARK_MAX := 160
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

	var env := Environment.new()
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
	track = tr
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
	_build_ground()
	_build_road()
	_build_scenery()
	_build_jumps()
	_build_start()
	_build_towers()
	_build_posts()
	_build_gems()
	_build_fx()
	_build_snowfall()

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
	sm.set_shader_parameter("base_col", COL_INFIELD)
	sm.set_shader_parameter("dot_col", COL_DOTS)
	sm.set_shader_parameter("far_col", COL_INFIELD.darkened(0.25))
	sm.set_shader_parameter("near_col", COL_INFIELD.lightened(0.12))
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
	# quad a-b-c-d (in order round the edge), flat normal pointing towards `hint`
	# uv.x = 1 marks the asphalt (the road shader adds ice and snowy edges there),
	# uv.y = side of the lane (+1 / -1)
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint: Vector3, road := false) -> void:
		var nrm := (b - a).cross(d - a)
		if nrm.length_squared() < 1e-12:
			nrm = (c - b).cross(a - b)
		nrm = nrm.normalized()
		if nrm.dot(hint) < 0.0:
			nrm = -nrm
		st.set_color(col)
		st.set_normal(nrm)
		var uvs := [Vector2(1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(1, -1)] if road else [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		for k in [0, 1, 2, 0, 2, 3]:
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
		road.quad(P.call(ca, na, HW, ha), P.call(cb, nb, HW, hb), P.call(cb, nb, -HW, hb), P.call(ca, na, -HW, ha), COL_ASPHALT, up, true)
		# centre dashes (40 on, 50 off)
		if fposmod(smid, 90.0) < 40.0:
			road.quad(P.call(ca, na, 2.5, ha + 0.4), P.call(cb, nb, 2.5, hb + 0.4), P.call(cb, nb, -2.5, hb + 0.4), P.call(ca, na, -2.5, ha + 0.4), Color(COL_CHALK, 1.0).darkened(0.55), up)
		var kc := COL_KERB if int(floor(smid / 30.0)) % 2 == 0 else COL_CHALK
		var elevated: bool = A["h"] > 2.0 or B["h"] > 2.0
		for side: float in [1.0, -1.0]:
			var o0 := HW * side
			var o1 := (HW + KERB_W) * side
			var o2 := (HW + KERB_W + RAIL_W) * side
			var out_hint := Vector3(na.x * side, 0, na.y * side)
			# kerb
			road.quad(P.call(ca, na, o0, ha + 0.6), P.call(cb, nb, o0, hb + 0.6), P.call(cb, nb, o1, hb + 0.6), P.call(ca, na, o1, ha + 0.6), kc, up)
			# rail: inner face, top, outer face
			var rh := RAIL_H + (10.0 if elevated else 0.0)
			var rcol := COL_DECK_LIGHT if elevated else COL_RAIL
			road.quad(P.call(ca, na, o1, ha), P.call(cb, nb, o1, hb), P.call(cb, nb, o1, hb + rh), P.call(ca, na, o1, ha + rh), rcol.darkened(0.12), -out_hint)
			road.quad(P.call(ca, na, o1, ha + rh), P.call(cb, nb, o1, hb + rh), P.call(cb, nb, o2, hb + rh), P.call(ca, na, o2, ha + rh), rcol, up)
			var base_a := (ha - 22.0) if elevated else 0.0
			var base_b := (hb - 22.0) if elevated else 0.0
			road.quad(P.call(ca, na, o2, base_a), P.call(cb, nb, o2, base_b), P.call(cb, nb, o2, hb + rh), P.call(ca, na, o2, ha + rh), rcol.darkened(0.25), out_hint)
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
	static_root.add_child(mi)

# Icy asphalt: glossy ice patches from a cheap value noise, and packed snow creeping
# in from both edges (it marks where the rail starts to cost speed).
var _road_m: ShaderMaterial
func _road_mat() -> ShaderMaterial:
	if _road_m:
		return _road_m
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
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
		c = mix(c, vec3(0.48, 0.60, 0.70), ice * 0.5);
		c = mix(c, vec3(0.75, 0.84, 0.92), ice * streak * 0.25);
		float edge = abs(UV.y) + (vnoise(q * 3.0) - 0.5) * 0.12;
		float snow = smoothstep(0.82, 0.95, edge);
		c = mix(c, vec3(0.86, 0.91, 0.95), snow);
		rough = mix(mix(0.8, 0.25, ice), 0.95, snow);
	}
	ALBEDO = c;
	ROUGHNESS = rough;
	SPECULAR = 0.5;
}
"""
	_road_m = ShaderMaterial.new()
	_road_m.shader = sh
	return _road_m

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
static func _band(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, sides: int, col: Color, rot := 0.0) -> void:
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
			st.add_vertex(v * U)

# a pine: trunk and stacked tiers, each tier green below and snow-capped on top
static func _pine_mesh(tiers: int, h: float, r: float) -> ArrayMesh:
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
		_band(st, y, snow_y, rr, r_mid, 7, COL_PINE if t % 2 == 0 else COL_PINE_DARK, rot)
		_band(st, snow_y - 0.01, y_top, r_mid * 1.06, 0.0, 7, COL_SNOW, rot)
		# a white snow rim on the lower edge of each tier
		_band(st, y + th * 0.02, y - th * 0.06, rr * 0.9, rr * 1.04, 7, COL_SNOW.darkened(0.05), rot)
		y += th * 0.62
	return st.commit()

# a log shack: walls, snow-laden gable roof, door, window, chimney. Long side along x.
static func _shack_mesh() -> ArrayMesh:
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
	faces.call([Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3(hx, wall, hz), Vector3(-hx, wall, hz)], COL_WOOD)
	faces.call([Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), Vector3(-hx, wall, -hz), Vector3(hx, wall, -hz)], COL_WOOD.darkened(0.15))
	faces.call([Vector3(hx, 0, hz), Vector3(hx, 0, -hz), Vector3(hx, wall, -hz), Vector3(hx, ridge - 4, 0), Vector3(hx, wall, hz)], COL_WOOD.darkened(0.08))
	faces.call([Vector3(-hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(-hx, wall, hz), Vector3(-hx, ridge - 4, 0), Vector3(-hx, wall, -hz)], COL_WOOD.darkened(0.2))
	# door and window on the front
	faces.call([Vector3(-20, 0, hz + 0.5), Vector3(4, 0, hz + 0.5), Vector3(4, 38, hz + 0.5), Vector3(-20, 38, hz + 0.5)], Color("#a8342a"))
	faces.call([Vector3(22, 22, hz + 0.5), Vector3(48, 22, hz + 0.5), Vector3(48, 42, hz + 0.5), Vector3(22, 42, hz + 0.5)], Color("#ffd98a"))
	# roof: snow on top, dark wood edge under the eaves
	var ex := hx + eave; var ez := hz + eave
	var shingle := Color("#6e3f2c")
	for side: float in [1.0, -1.0]:
		var lo := Vector3(0, wall - 8, ez * side)
		var mid := lo.lerp(Vector3(0, ridge, 0), 0.3)
		var x0 := -ex * side; var x1 := ex * side
		# bare shingles along the eave, snow above
		faces.call([Vector3(x0, lo.y, lo.z), Vector3(x1, lo.y, lo.z), Vector3(x1, mid.y, mid.z), Vector3(x0, mid.y, mid.z)], shingle)
		faces.call([Vector3(x0, mid.y + 0.5, mid.z), Vector3(x1, mid.y + 0.5, mid.z), Vector3(x1, ridge + 1, 0), Vector3(x0, ridge + 1, 0)], COL_SNOW)
		faces.call([Vector3(x1, lo.y - 6, lo.z), Vector3(x0, lo.y - 6, lo.z), Vector3(x0, lo.y, lo.z), Vector3(x1, lo.y, lo.z)], Color("#3b281c"))
	# chimney with a snow cap
	_band(st, wall + 20, ridge + 22, 9.0, 9.0, 4, Color("#6b6f75"), PI / 4)
	st.set_color(COL_SNOW)
	_band(st, ridge + 22, ridge + 26, 11.0, 0.0, 4, COL_SNOW, PI / 4)
	return st.commit()

# a snow-topped boulder: a squashed low-poly dome
static func _rock_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band(st, -4.0, 16.0, 40.0, 33.0, 5, COL_ROCK)
	_band(st, 16.0, 28.0, 33.0, 16.0, 5, COL_ROCK.lightened(0.12), 0.3)
	_band(st, 27.0, 33.0, 17.0, 0.0, 5, COL_SNOW, 0.3)
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
	var clear_r := HW + KERB_W + RAIL_W + 45.0
	var s := 0.0
	while s < track.L:
		mark.call(track.point_at(s)["pos"], clear_r, 1)
		s += 30.0
	for a in track.anchors:
		mark.call(a.pos, TrackData.TURN_R + 10.0, 1)   # keep the infield under the tethers clear
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

	# shacks first, a few along the outside of the road, facing it
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
			if n > 0.05 and r < 0.35 + n:
				var sc := 0.75 + rng.randf() * 0.6
				var xf := Transform3D(basis_for.call(rng.randf() * TAU, sc), w3(p))
				(pines_a if rng.randf() < 0.6 else pines_b).append(xf)
				mark.call(p, 30.0 * sc, 2)
			elif r < 0.035:
				var rs := 0.6 + rng.randf() * 0.8
				rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rs * 1.4, rs, rs * 0.85)), w3(p)))
				mark.call(p, 40.0, 2)
		y += step
	_multi(_pine_mesh(3, 150.0, 48.0), pines_a)
	_multi(_pine_mesh(4, 210.0, 56.0), pines_b)
	_multi(_shack_mesh(), shacks)
	_multi(_rock_mesh(), rocks)

# light snowfall around the camera focus: one CPU particle system, ~150 tiny quads
var snowfall: CPUParticles3D
func _build_snowfall() -> void:
	snowfall = CPUParticles3D.new()
	snowfall.amount = 150
	snowfall.lifetime = 4.5
	snowfall.preprocess = 4.5
	snowfall.local_coords = false
	snowfall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snowfall.emission_box_extents = Vector3(14, 0.2, 9)
	snowfall.direction = Vector3(0.35, -1.0, 0.15)
	snowfall.spread = 12.0
	snowfall.initial_velocity_min = 0.9
	snowfall.initial_velocity_max = 1.5
	snowfall.gravity = Vector3(0, -0.3, 0)
	snowfall.scale_amount_min = 0.6
	snowfall.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = Color(1, 1, 1, 0.85)
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
		# the pit under the gap, and red lips either side
		var steps := 6
		for k in steps:
			var sa := s0 + GAP * k / steps
			var sb := s0 + GAP * (k + 1) / steps
			var qa := track.point_at(sa); var qb := track.point_at(sb)
			var na := TrackData.perp(qa["dir"]); var nb := TrackData.perp(qb["dir"])
			var w := HW + KERB_W + RAIL_W
			st.quad(w3(qa["pos"] + na * w, 0.6), w3(qb["pos"] + nb * w, 0.6), w3(qb["pos"] - nb * w, 0.6), w3(qa["pos"] - na * w, 0.6), COL_PIT, up)
		for edge in [s0, s0 + GAP]:
			var q := track.point_at(edge)
			var n := TrackData.perp(q["dir"]) as Vector2
			var d: Vector2 = q["dir"]
			var h := track.height_at(edge) + ROAD_Y
			var w := HW + KERB_W
			st.quad(w3(q["pos"] + n * w - d * 8, h + 1), w3(q["pos"] + n * w + d * 8, h + 1), w3(q["pos"] - n * w + d * 8, h + 1), w3(q["pos"] - n * w - d * 8, h + 1), COL_KERB, up)
		# ramp wedge with chevrons
		var rs := 8
		for k in rs:
			var sa := s0 - RAMP_LEN + RAMP_LEN * k / rs
			var sb := s0 - RAMP_LEN + RAMP_LEN * (k + 1) / rs
			var qa := track.point_at(sa); var qb := track.point_at(sb)
			var na := TrackData.perp(qa["dir"]); var nb := TrackData.perp(qb["dir"])
			var ha := track.height_at(sa) + ROAD_Y + RAMP_H * float(k) / rs
			var hb := track.height_at(sb) + ROAD_Y + RAMP_H * float(k + 1) / rs
			var col := COL_POST if k % 2 == 0 else Color("#3a2a08")
			st.quad(w3(qa["pos"] + na * HW, ha), w3(qb["pos"] + nb * HW, hb), w3(qb["pos"] - nb * HW, hb), w3(qa["pos"] - na * HW, ha), col, up)
		var q_end := track.point_at(s0)
		var ne := TrackData.perp(q_end["dir"]) as Vector2
		var he := track.height_at(s0) + ROAD_Y
		st.quad(w3(q_end["pos"] + ne * HW, he), w3(q_end["pos"] + ne * HW, he + RAMP_H), w3(q_end["pos"] - ne * HW, he + RAMP_H), w3(q_end["pos"] - ne * HW, he), Color("#2a2f36"), -Vector3(q_end["dir"].x, 0, q_end["dir"].y))
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
			# column up to this rotor, narrowing above the first one
			var col_r := 32.0 * wide
			t.add_child(cyl(col_r, y - y_prev, COL_TOWER, Vector3(0, y_prev + (y - y_prev) / 2.0, 0), col_r + (6.0 if m == 0 else 2.0)))
			t.add_child(cyl(col_r, 8, COL_TOWER.lightened(0.15), Vector3(0, y + 4, 0)))
			var spinner := Node3D.new()
			spinner.position = Vector3(0, y + 8, 0) * U
			var disc := cyl(27 * wide, 6, COL_POST, Vector3(0, 3, 0))
			disc.mesh.material = mat(COL_POST, false, 0.35)
			spinner.add_child(disc)
			for k in 3:
				var arm := Node3D.new()
				arm.rotation.y = TAU * k / 3.0
				arm.add_child(box(Vector3(24 * wide, 4, 6), Color("#3a2a08"), Vector3(12 * wide, 7, 0)))
				spinner.add_child(arm)
			spinner.add_child(cyl(7, 10, COL_CHALK, Vector3(0, 8, 0)))
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
		var top := paint(col)
		var low := paint(col.darkened(0.38), 0.5)
		var glass := paint(Color("#1a2330"), 0.08)
		glass.metallic = 0.4
		# two-tone body: darker sill, painted upper body, slimmer nose
		parts_list.append(pbox(Vector3(126, 12, 72), low, Vector3(0, 16, 0)))
		parts_list.append(pbox(Vector3(118, 16, 70), top, Vector3(-2, 29, 0)))
		parts_list.append(pbox(Vector3(22, 10, 60), top, Vector3(64, 24, 0)))
		parts_list.append(pbox(Vector3(48, 18, 54), glass, Vector3(-6, 45, 0)))   # cabin
		parts_list.append(pbox(Vector3(40, 3, 50), top, Vector3(-8, 55, 0)))      # roof
		parts_list.append(pbox(Vector3(22, 6, 80), low, Vector3(-58, 44, 0)))     # rear wing
		parts_list.append(pbox(Vector3(6, 10, 6), low, Vector3(-58, 37, 26)))
		parts_list.append(pbox(Vector3(6, 10, 6), low, Vector3(-58, 37, -26)))
		parts_list.append(pbox(Vector3(54, 1.5, 12), paint(Color(1, 1, 1)), Vector3(-30, 38, 0)))  # stripe
		var lamp := mat(Color("#fff4c8"), true)
		parts_list.append(pbox(Vector3(3, 5, 14), lamp, Vector3(75, 25, 22)))
		parts_list.append(pbox(Vector3(3, 5, 14), lamp, Vector3(75, 25, -22)))
		var tail := mat(Color("#ff4a3a"), false, 1.2)
		parts_list.append(pbox(Vector3(3, 5, 12), tail, Vector3(-62, 28, 24)))
		parts_list.append(pbox(Vector3(3, 5, 12), tail, Vector3(-62, 28, -24)))
		var tyre := paint(Color("#16181c"), 0.8)
		for wx in [-40.0, 42.0]:
			for wz in [-37.0, 37.0]:
				var w := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 14 * U; cm.bottom_radius = 14 * U; cm.height = 12 * U
				cm.radial_segments = 14; cm.rings = 1
				cm.material = tyre
				w.mesh = cm
				w.position = Vector3(wx, 14, wz) * U
				w.rotation.x = PI / 2
				chassis.add_child(w)   # wheels stay on the road; the body moves above them
	for p in parts_list:
		if ghost:
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(p)
	root.set_meta("body", body)
	root.set_meta("chassis", chassis)
	return root

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
				_spark(w3(p, y), Vector3(v.x, 120 + randf() * 200, v.y) * U, 0.35 + randf() * 0.3, Color("#ffd36b"))
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

func _spark(p: Vector3, v: Vector3, life: float, col: Color) -> void:
	if parts.size() >= SPARK_MAX:
		parts.pop_front()
	parts.append({ "p": p, "v": v, "life": life, "col": col })

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
		mi.scale = Vector3.ONE * maxf(0.05, minf(1.0, p["life"] * 2.5))
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
		snowfall.emitting = phase != "menu"
		snowfall.visible = phase != "menu"
		snowfall.position = focus + Vector3(0, 5.0, 0)
		snowfall.emission_box_extents = Vector3(cam_vis * U * 1.1, 0.2, cam_vis * U * 0.7)
	camera.position = focus + off + jitter
	camera.look_at(focus + jitter, Vector3.UP)
	light.directional_shadow_max_distance = clampf(dist * 2.2, 30.0, 200.0)
