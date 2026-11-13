# The 3D view. Builds the track meshes from TrackData and mirrors the race state
# (cars, tethers, spinning towers, posts, gems, effects) every frame.
# World mapping: prototype (x, y) with height h -> Vector3(x, h, y) * U.
extends Node3D

const TrackData = preload("res://scripts/track.gd")
const Themes = preload("res://scripts/themes.gd")
const Race = preload("res://scripts/race.gd")
const TrackObjects = preload("res://scripts/track_objects.gd")

const U := 0.01
# Model detail. 1 = the game (light enough for phones). 2 = artwork renders
# (tools/gen_loading_art.gd): rounded, bevelled car and tower parts and twice the facets
# on every round shape, same shapes and sizes.
static var detail := 1
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
	if detail > 1:
		mi.mesh = bevel_box(size, mat(c))
		mi.position = pos * U
		return mi
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
	cm.radial_segments = segs * 3 if detail > 1 and segs != 4 else segs
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
	return [func(): _clear(tr), _build_ground, func(): _build_road(); _build_drifts(); _build_underpasses(), _build_scenery,
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
	_build_relief()
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
	// relief: hollows a little shaded, tops a touch brighter (level ground, height 0,
	// stays exactly as the road shader's bank slope draws it)
	c *= 1.0 + clamp(wp.y * 0.12, -0.26, 0.08);
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
	var mi := MeshInstance3D.new()
	mi.mesh = _relief_mesh()
	mi.material_override = sm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	static_root.add_child(mi)

# ---------------------------------------------------------------- landscape relief
# The land around the track is not flat: gentle rolls everywhere, plus scattered
# hollows and mounds, some shallow, some deep. Purely visual. Everything is derived
# from the track data (road path, towers, start), so new layouts get their own relief:
# the ground stays level (height 0) under the road and its banks and round each tower's
# foot, then the relief grows in quickly over TER_RAMP, so the banks' outer slope still
# meets level ground exactly as before. Extra hollows and mounds are scattered right
# beside the road (between hairpins, inside loops). Far out it levels off again.
const TER_MARGIN := 2400.0   # relief reaches this far past the track bounds
const TER_FLAT := 8.0        # extra level ground past the foot of the bank
const TER_RAMP := 170.0      # distance over which the relief grows to full height
const TER_EDGE := 500.0      # fade back to level ground at the outer border
const TER_COARSE := 40.0     # cell of the distance-to-track field
const TER_LIGHT := 1.7       # slope exaggeration in the lighting
var _ter_org := Vector2.ZERO # prototype-space corner of the height grid
var _ter_cell := 50.0
var _ter_w := 0              # vertices per row
var _ter_h := 0              # rows
var _ter := PackedFloat32Array()   # height (world units) per grid vertex

# Ground height at a prototype-space point (0 off the relief grid).
func ground_h(p: Vector2) -> float:
	if _ter_w < 2:
		return 0.0
	var fx := (p.x - _ter_org.x) / _ter_cell
	var fy := (p.y - _ter_org.y) / _ter_cell
	if fx < 0.0 or fy < 0.0 or fx >= _ter_w - 1 or fy >= _ter_h - 1:
		return 0.0
	var ix := int(fx); var iy := int(fy)
	var tx := fx - ix; var ty := fy - iy
	var k := iy * _ter_w + ix
	return lerpf(lerpf(_ter[k], _ter[k + 1], tx), lerpf(_ter[k + _ter_w], _ter[k + _ter_w + 1], tx), ty)

# Lowest ground under a square footprint (a hut sits into the slope, never floats).
func ground_low(p: Vector2, r: float) -> float:
	var h := ground_h(p)
	for o in [Vector2(r, r), Vector2(-r, r), Vector2(r, -r), Vector2(-r, -r)]:
		h = minf(h, ground_h(p + o))
	return h

func _build_relief() -> void:
	var R := track.bounds.grow(TER_MARGIN)
	# Low graphics: a coarser grid (about a fifth of the triangles)
	_ter_cell = [100.0, 65.0, 50.0][quality]
	_ter_org = R.position
	_ter_w = ceili(R.size.x / _ter_cell) + 1
	_ter_h = ceili(R.size.y / _ter_cell) + 1
	# 1. how far each spot is past the zones that must stay level
	var far := TER_FLAT + TER_RAMP
	var cw := ceili(R.size.x / TER_COARSE) + 2
	var ch := ceili(R.size.y / TER_COARSE) + 2
	var dist := PackedFloat32Array()
	dist.resize(cw * ch)
	dist.fill(far)
	var stamp := func(p: Vector2, r: float) -> void:
		var reach := r + far
		var x0 := maxi(0, floori((p.x - reach - R.position.x) / TER_COARSE))
		var x1 := mini(cw - 1, ceili((p.x + reach - R.position.x) / TER_COARSE))
		var y0 := maxi(0, floori((p.y - reach - R.position.y) / TER_COARSE))
		var y1 := mini(ch - 1, ceili((p.y + reach - R.position.y) / TER_COARSE))
		for gy in range(y0, y1 + 1):
			var row := gy * cw
			var dy := R.position.y + gy * TER_COARSE - p.y
			for gx in range(x0, x1 + 1):
				var dx := R.position.x + gx * TER_COARSE - p.x
				var d := sqrt(dx * dx + dy * dy) - r
				if d < dist[row + gx]:
					dist[row + gx] = d
	var road_r := HW + KERB_W + RAIL_W + BANK_OUT + 6.0   # the foot of the bank
	var s := 0.0
	while s < track.L:
		stamp.call(track.point_at(s)["pos"], road_r)
		s += 40.0
	for a in track.anchors:
		stamp.call(a.pos, 90.0)   # the tower's foot
	# 2. the relief itself: rolling noise whose strength wanders, plus hollows and mounds
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(track.def.get("name", ""))) + 31
	var roll := FastNoiseLite.new()
	roll.seed = rng.randi()
	roll.frequency = 1.0 / 1100.0
	roll.fractal_octaves = 3
	var calm := FastNoiseLite.new()
	calm.seed = rng.randi()
	calm.frequency = 1.0 / 2600.0
	calm.fractal_type = FastNoiseLite.FRACTAL_NONE
	var relief: float = th.get("relief", 1.0)
	_ter = PackedFloat32Array()
	_ter.resize(_ter_w * _ter_h)
	for gy in _ter_h:
		for gx in _ter_w:
			var x := R.position.x + gx * _ter_cell
			var y := R.position.y + gy * _ter_cell
			var amp := lerpf(15.0, 110.0, smoothstep(-0.35, 0.45, calm.get_noise_2d(x, y)))
			_ter[gy * _ter_w + gx] = roll.get_noise_2d(x, y) * amp
	# hollows (a bit more often) and mounds: mostly shallow, about a third deep
	var blobs: Array = []   # [centre, radius, height, deep]
	var n_blobs := int(R.get_area() / (650.0 * 650.0))
	for k in n_blobs:
		var c := Vector2(R.position.x + rng.randf() * R.size.x, R.position.y + rng.randf() * R.size.y)
		var deep := rng.randf() < 0.35
		var r := rng.randf_range(260.0, 620.0) if deep else rng.randf_range(150.0, 420.0)
		var h := rng.randf_range(120.0, 260.0) if deep else rng.randf_range(25.0, 70.0)
		if rng.randf() < 0.6:
			h = -h
		blobs.append([c, r, h, deep])
	# more of them close to the road: beside every bend and between the hairpins
	var n_near := int(track.L / 320.0)
	for k in n_near:
		var q := track.point_at(rng.randf() * track.L)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var r := rng.randf_range(110.0, 300.0)
		var c: Vector2 = q["pos"] + TrackData.perp(q["dir"]) * side * (road_r + rng.randf_range(0.4, 1.2) * r)
		var deep := rng.randf() < 0.45
		var h := rng.randf_range(70.0, 180.0) if deep else rng.randf_range(20.0, 60.0)
		if rng.randf() < 0.55:
			h = -h
		blobs.append([c, r, h, deep])
	for bl in blobs:
		var c: Vector2 = bl[0]; var r: float = bl[1]; var h: float = bl[2]; var deep: bool = bl[3]
		var x0 := maxi(0, floori((c.x - r - R.position.x) / _ter_cell))
		var x1 := mini(_ter_w - 1, ceili((c.x + r - R.position.x) / _ter_cell))
		var y0 := maxi(0, floori((c.y - r - R.position.y) / _ter_cell))
		var y1 := mini(_ter_h - 1, ceili((c.y + r - R.position.y) / _ter_cell))
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				var t := Vector2(R.position.x + gx * _ter_cell, R.position.y + gy * _ter_cell).distance_to(c) / r
				if t < 1.0:
					# deep ones are bowls with steeper sides, shallow ones soft swells
					var f := smoothstep(1.0, 0.15, t) if deep else (1.0 - t * t) * (1.0 - t * t)
					_ter[gy * _ter_w + gx] += h * f
	# 3. level near the track and at the outer border
	for gy in _ter_h:
		var y := gy * _ter_cell
		for gx in _ter_w:
			var x := gx * _ter_cell
			var fx := x / TER_COARSE; var fy := y / TER_COARSE
			var ix := mini(int(fx), cw - 2); var iy := mini(int(fy), ch - 2)
			var tx := fx - ix; var ty := fy - iy
			var k := iy * cw + ix
			var d := lerpf(lerpf(dist[k], dist[k + 1], tx), lerpf(dist[k + cw], dist[k + cw + 1], tx), ty)
			var m := smoothstep(TER_FLAT, TER_FLAT + TER_RAMP, d)
			var edge := minf(minf(x, R.size.x - x), minf(y, R.size.y - y))
			m *= smoothstep(0.0, TER_EDGE, edge)
			_ter[gy * _ter_w + gx] *= m * relief

# The relief grid plus a level apron reaching far past it on every side.
func _relief_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(_ter_w * _ter_h)
	nrms.resize(_ter_w * _ter_h)
	for gy in _ter_h:
		for gx in _ter_w:
			var k := gy * _ter_w + gx
			verts[k] = Vector3(_ter_org.x + gx * _ter_cell, _ter[k], _ter_org.y + gy * _ter_cell) * U
			var hx := _ter[k + 1 if gx + 1 < _ter_w else k] - _ter[k - 1 if gx > 0 else k]
			var hy := _ter[k + _ter_w if gy + 1 < _ter_h else k] - _ter[k - _ter_w if gy > 0 else k]
			# slopes lit a little steeper than they are, so the relief reads from the
			# high camera
			nrms[k] = Vector3(-hx * TER_LIGHT, 2.0 * _ter_cell, -hy * TER_LIGHT).normalized()
	# clockwise seen from above (Godot's front face)
	for gy in _ter_h - 1:
		for gx in _ter_w - 1:
			var k := gy * _ter_w + gx
			idx.append_array([k, k + 1, k + _ter_w, k + 1, k + _ter_w + 1, k + _ter_w])
	var apron := 9000.0
	var x0 := _ter_org.x; var y0 := _ter_org.y
	var x1 := _ter_org.x + (_ter_w - 1) * _ter_cell; var y1 := _ter_org.y + (_ter_h - 1) * _ter_cell
	for r in [[x0 - apron, y0 - apron, x1 + apron, y0], [x0 - apron, y1, x1 + apron, y1 + apron],
			[x0 - apron, y0, x0, y1], [x1, y0, x1 + apron, y1]]:
		var b := verts.size()
		verts.append_array([Vector3(r[0], 0, r[1]) * U, Vector3(r[2], 0, r[1]) * U, Vector3(r[0], 0, r[3]) * U, Vector3(r[2], 0, r[3]) * U])
		nrms.append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrms
	arr[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return am

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
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint: Vector3, road := false, flat := false, uvy := Vector2(1, -1)) -> void:
		var nrm := (b - a).cross(d - a)
		if nrm.length_squared() < 1e-12:
			nrm = (c - b).cross(a - b)
		nrm = nrm.normalized()
		if nrm.dot(hint) < 0.0:
			nrm = -nrm
		st.set_color(col)
		st.set_normal(nrm)
		var uvs := [Vector2(1, uvy.x), Vector2(1, uvy.x), Vector2(1, uvy.y), Vector2(1, uvy.y)] if road else [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
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
	_wins = _window_spans()
	var win_st: SurfaceTool = null
	if not _wins.is_empty():
		win_st = SurfaceTool.new()
		win_st.begin(Mesh.PRIMITIVE_TRIANGLES)
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
		var win := _in_window(smid)
		if not win.is_empty():
			# see-through deck: its own mesh, uv = (s, offset), uv2.x = -1..1 along the window
			var wl: float = (win[1] - win[0]) * 0.5
			var ua := (fposmod(sa - win[2] + track.L * 0.5, track.L) - track.L * 0.5) / wl
			var ub := (fposmod(sb - win[2] + track.L * 0.5, track.L) - track.L * 0.5) / wl
			var ow := HW * 0.5 if underpass.has("slot") else HW + KERB_W
			if underpass.has("slot"):
				# solid lanes either side of a narrower opening
				for sd2: float in [1.0, -1.0]:
					road.quad(P.call(ca, na, HW * sd2, ha), P.call(cb, nb, HW * sd2, hb), P.call(cb, nb, ow * sd2, hb), P.call(ca, na, ow * sd2, ha), th["road"], up, true, false, Vector2(1, ow / HW))
					road.quad(P.call(ca, na, HW * sd2, ha + 0.6), P.call(cb, nb, HW * sd2, hb + 0.6), P.call(cb, nb, (HW + KERB_W) * sd2, hb + 0.6), P.call(ca, na, (HW + KERB_W) * sd2, ha + 0.6), th["verge"], up)
				road.quad(P.call(ca, na, HW + KERB_W + RAIL_W, ha - 22.0), P.call(cb, nb, HW + KERB_W + RAIL_W, hb - 22.0), P.call(cb, nb, ow, hb - 22.0), P.call(ca, na, ow, ha - 22.0), COL_DECK.darkened(0.3), -up)
				road.quad(P.call(ca, na, -ow, ha - 22.0), P.call(cb, nb, -ow, hb - 22.0), P.call(cb, nb, -HW - KERB_W - RAIL_W, hb - 22.0), P.call(ca, na, -HW - KERB_W - RAIL_W, ha - 22.0), COL_DECK.darkened(0.3), -up)
			_win_half = ow
			for v in [[ca, na, ow, ha, sa, ua], [cb, nb, ow, hb, sb, ub], [cb, nb, -ow, hb, sb, ub], [ca, na, ow, ha, sa, ua], [cb, nb, -ow, hb, sb, ub], [ca, na, -ow, ha, sa, ua]]:
				win_st.set_normal(Vector3.UP)
				win_st.set_uv(Vector2(v[4], v[2]))
				win_st.set_uv2(Vector2(v[5], signf(v[2])))
				win_st.add_vertex(P.call(v[0], v[1], v[2], v[3] + 0.3))
		# asphalt
		if win.is_empty(): road.quad(P.call(ca, na, HW, ha), P.call(cb, nb, HW, hb), P.call(cb, nb, -HW, hb), P.call(ca, na, -HW, ha), th["road"], up, true)
		# centre dashes (40 on, 50 off)
		if fposmod(smid, 90.0) < 40.0 and win.is_empty():
			road.quad(P.call(ca, na, 2.5, ha + 0.4), P.call(cb, nb, 2.5, hb + 0.4), P.call(cb, nb, -2.5, hb + 0.4), P.call(ca, na, -2.5, ha + 0.4), Color(COL_CHALK, 1.0).darkened(0.55), up, false, true)
		var elevated: bool = A["h"] > 2.0 or B["h"] > 2.0
		for side: float in [1.0, -1.0]:
			var o0 := HW * side
			var o1 := (HW + KERB_W) * side
			var o2 := (HW + KERB_W + RAIL_W) * side
			var out_hint := Vector3(na.x * side, 0, na.y * side)
			# verge: a strip of packed, blue-shaded snow right at the lane edge
			if win.is_empty(): road.quad(P.call(ca, na, o0, ha + 0.6), P.call(cb, nb, o0, hb + 0.6), P.call(cb, nb, o1, hb + 0.6), P.call(ca, na, o1, ha + 0.6), th["verge"], up)
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
			if win.is_empty(): road.quad(P.call(ca, na, oo, ha - 22.0), P.call(cb, nb, oo, hb - 22.0), P.call(cb, nb, -oo, hb - 22.0), P.call(ca, na, -oo, ha - 22.0), COL_DECK.darkened(0.3), -up)
			pillar_acc += sb - sa
			if pillar_acc > 260.0 and A["h"] > 70.0 and not _near_bridge_center(ca, HW * 2.4):
				pillar_acc = 0.0
				for side: float in [1.0, -1.0]:
					var pp: Vector2 = ca + na * (HW - 20.0) * side
					var pil := box(Vector3(26, A["h"] - 20.0, 26), COL_DECK, Vector3(pp.x, (A["h"] - 20.0) / 2.0, pp.y))
					static_root.add_child(pil)
		else:
			pillar_acc = 260.0
	if win_st != null:
		var wm := MeshInstance3D.new()
		wm.mesh = win_st.commit()
		wm.material_override = _window_mat(String(th["kit"]))
		(wm.material_override as ShaderMaterial).set_shader_parameter("half", _win_half)
		static_root.add_child(wm)
	var mi := MeshInstance3D.new()
	mi.mesh = road.st.commit()
	mi.material_override = _road_mat()
	# the banks are low and soft: their own shadow only drew a dark, striped band
	# along the outer slope
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	static_root.add_child(mi)

# ---------------------------------------------------------------- underpasses
# Where the road passes under a bridge. Visual only. Preview switch (2026-11-13):
#   "shade"  the under road darkens under the deck
#   "portal" a themed tunnel mouth in the bridge's side wall
#   "window" a themed see-through section of the deck right above the lane below
#   "xray"   cars hidden by a bridge show through it as a flat silhouette
var underpass := PackedStringArray()

# one entry per bridge, in prototype units: crossing point, both directions, heights
func _crossings() -> Array:
	var out: Array = []
	if track == null:
		return out
	for B in track.bridges:
		var a: int = B["under"]
		var b: int = (int(B["from"]) + posmod(int(B["to"]) - int(B["from"]), track.n) / 2) % track.n
		var su := track.s_of(a, 0.5)
		var sd := track.s_of(b, 0.5)
		if track.height_at(su) > track.height_at(sd):
			var t := su; su = sd; sd = t
		var pu := track.point_at(su)
		var pd := track.point_at(sd)
		var du: Vector2 = pu["dir"]
		var dd: Vector2 = pd["dir"]
		var cu: Vector2 = pu["pos"]
		var den := du.cross(dd)
		var c := cu
		if absf(den) > 0.2:
			c = cu + du * ((Vector2(pd["pos"]) - cu).cross(dd) / den)
		out.append({ "c": c, "du": du, "dd": dd, "sin": maxf(0.4, absf(den)),
			"hu": track.height_at(su), "hd": track.height_at(sd), "sd": sd + (c - Vector2(pd["pos"])).dot(dd) })
	return out

# stretches of deck (s0, s1, s at the crossing) shown as a see-through section: long enough
# to cover the whole lane below, however slanted the crossing
var _wins: Array = []
var _win_half := HW + KERB_W
func _window_spans() -> Array:
	var out: Array = []
	if not underpass.has("window"):
		return out
	for X in _crossings():
		var cs: float = absf(Vector2(X["du"]).dot(X["dd"]))
		var half: float = (HW + 6.0) / X["sin"] + (HW + KERB_W) * cs / X["sin"]
		out.append([X["sd"] - half, X["sd"] + half, X["sd"]])
	return out

func _in_window(sv: float) -> Array:
	for w in _wins:
		var d := fposmod(sv - w[2] + track.L * 0.5, track.L) - track.L * 0.5
		if absf(d) < (w[1] - w[0]) * 0.5:
			return w
	return []

# point on the plane of a crossing: alpha along the deck, beta along the under road
static func _xp(X: Dictionary, al: float, be: float) -> Vector2:
	return X["c"] + X["dd"] * al + X["du"] * be

func _build_underpasses() -> void:
	var kind: String = th["kit"]
	for X in _crossings():
		var sn: float = X["sin"]
		if underpass.has("shade"):
			_under_shade(X, 0.3 if underpass.has("window") else 0.62)
		if underpass.has("portal"):
			for side: float in [1.0, -1.0]:
				_portal(X, side, kind)

# a dark wash on the lane below, fading out towards both sides of the deck
func _under_shade(X: Dictionary, amt: float) -> void:
	var sn: float = X["sin"]
	var a0 := (HW + KERB_W + 4.0) / sn
	var b0 := (HW + KERB_W + RAIL_W + 30.0) / sn
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y: float = X["hu"] + ROAD_Y + 0.9
	var N := 8
	for j in N:
		var t0 := -1.0 + 2.0 * j / N
		var t1 := -1.0 + 2.0 * (j + 1) / N
		var f0 := amt * clampf((1.0 - absf(t0)) * 2.2, 0.0, 1.0)
		var f1 := amt * clampf((1.0 - absf(t1)) * 2.2, 0.0, 1.0)
		var q := [[-1.0, t0, f0], [1.0, t0, f0], [1.0, t1, f1], [-1.0, t0, f0], [1.0, t1, f1], [-1.0, t1, f1]]
		for v in q:
			st.set_color(Color(0.02, 0.03, 0.06, v[2]))
			st.add_vertex(w3(_xp(X, a0 * v[0], b0 * v[1]), y))
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	static_root.add_child(mi)

const WINDOW_LOOK := {
	# frame, bars (or ice tint), bars 2
	"snow":   [Color("#e8f3f9"), Color("#9fd4ea"), Color("#ffffff")],
	"forest": [Color("#4a3322"), Color("#8a6040"), Color("#74502f")],
	"sand":   [Color("#a8743f"), Color("#d9aa6c"), Color("#c4945a")],
	"rock":   [Color("#3b4046"), Color("#6c737b"), Color("#575e66")],
}
func _window_mat(kind: String) -> ShaderMaterial:
	var lk: Array = WINDOW_LOOK.get(kind, WINDOW_LOOK["rock"])
	var sh := Shader.new()
	var ice := kind == "snow"
	sh.code = """
shader_type spatial;
render_mode cull_disabled%s;
uniform vec3 frame_col : source_color;
uniform vec3 bar_col : source_color;
uniform vec3 bar2_col : source_color;
uniform int kind = 0;
uniform float half = 196.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 q = UV;     // units: along the deck, across the deck
	float fr = max(step(0.93, abs(UV2.x)), step(half - 9.0, abs(UV.y)) * step(half, 150.0));   // frame: beams at both ends (and sides of a slot)
	vec3 c = bar_col;
	float m = 1.0;
	float rough = 0.8;
	if (kind == 0) {
		// clear ice: pale blue, frosted towards the frame, a few cracks
		float edge = smoothstep(0.6, 0.93, max(abs(UV2.x), abs(UV.y) / half));
		// a few long cracks: thin lines along the zero sets of two slow wobbly functions
		float f1 = sin(q.x * 0.011 + sin(q.y * 0.02) * 1.6) * 60.0 + q.y * 0.6;
		float f2 = sin(q.y * 0.03 + q.x * 0.004) * 50.0 - q.x * 0.35;
		float crack = 1.0 - smoothstep(0.6, 1.4, abs(fract(f1 / 140.0 + 0.5) - 0.5) * 140.0);
		crack = max(crack, 1.0 - smoothstep(0.6, 1.4, abs(fract(f2 / 170.0 + 0.5) - 0.5) * 170.0));
		c = mix(bar_col, bar2_col, max(edge * 0.8, crack));
		m = 0.22 + edge * 0.55 + crack * 0.5;
		rough = 0.05;
	} else if (kind == 1) {
		// timber boardwalk: planks across the deck with gaps between
		float f = fract(q.x / 30.0);
		m = step(0.3, f);
		c = mix(bar_col, bar2_col, hash(vec2(floor(q.x / 30.0), 3.0)));
	} else if (kind == 2) {
		// carved sandstone lattice
		float u = fract((q.x + q.y) / 34.0);
		float v = fract((q.x - q.y) / 34.0);
		m = max(step(u, 0.2), step(v, 0.2));
		c = mix(bar_col, bar2_col, step(u, 0.2));
	} else {
		// steel grating
		float u = fract(q.x / 20.0);
		float v = fract(q.y / 20.0);
		m = max(step(u, 0.2), step(v, 0.14));
		c = mix(bar_col, bar2_col, step(u, 0.2));
		rough = 0.45;
	}
	if (fr > 0.5) { c = frame_col; m = 1.0; }
	ALBEDO = c;
	ROUGHNESS = rough;
	%s
}
""" % ([", depth_draw_always", "ALPHA = m;"] if ice else ["", "ALPHA = m; ALPHA_SCISSOR_THRESHOLD = 0.5;"])
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("frame_col", lk[0])
	m.set_shader_parameter("bar_col", lk[1])
	m.set_shader_parameter("bar2_col", lk[2])
	m.set_shader_parameter("kind", ["snow", "forest", "sand", "rock"].find(kind))
	return m

const PORTAL_LOOK := {
	# wall, wall 2 (courses), ring a, ring b
	"snow":   [Color("#dce7ef"), Color("#c9d8e4"), Color("#a9daee"), Color("#e6f4fa")],
	"forest": [Color("#6b4a2f"), Color("#5a3d26"), Color("#3e2a1a"), Color("#4b3220")],
	"sand":   [Color("#c99a62"), Color("#b98a54"), Color("#e2b67c"), Color("#a8743f")],
	"rock":   [Color("#6e747a"), Color("#61676d"), Color("#9aa0a6"), Color("#50565c")],
}
# A tunnel mouth in the deck's side wall: a wall from the ground up to the deck with a
# themed arch over the lane below
func _portal(X: Dictionary, side: float, kind: String) -> void:
	var lk: Array = PORTAL_LOOK.get(kind, PORTAL_LOOK["rock"])
	var dd: Vector2 = X["dd"]
	var du: Vector2 = X["du"]
	var nrm2 := TrackData.perp(dd) * side
	var face := HW + KERB_W + RAIL_W + 1.5
	var hu: float = X["hu"]
	var top: float = X["hd"] + ROAD_Y - 22.0
	var wo := HW + KERB_W + 6.0           # half width of the opening, across the lane below
	var ww := wo + 130.0                  # half width of the wall
	var spring := hu + (top - hu) * 0.42  # where the arch starts curving
	var apex := top - 16.0
	var ring := 24.0
	# the wall's line: d = t * dd + face * side * perp(dd); x = across the lane below
	var base: Vector2 = X["c"] + nrm2 * face
	var dx := du.cross(dd)   # how x changes per unit of t
	if absf(dx) < 0.3:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n3 := Vector3(nrm2.x, 0, nrm2.y)
	var quadv := func(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, nn: Vector3) -> void:
		for v in [a, b, c, a, c, d]:
			st.set_color(col)
			st.set_normal(nn)
			st.add_vertex(v)
	var P := func(x: float, h: float, out := 0.0) -> Vector3:
		var t := (x - du.cross(nrm2 * face)) / dx
		var p: Vector2 = base + dd * t + nrm2 * out
		return w3(p, h)
	var open_h := func(x: float) -> float:
		var r := clampf(x / wo, -1.0, 1.0)
		return spring + (apex - spring) * sqrt(1.0 - r * r)
	var N := 24
	# courses of the wall: horizontal bands
	var course := 22.0
	for j in N:
		var x0 := -ww + 2.0 * ww * j / N
		var x1 := -ww + 2.0 * ww * (j + 1) / N
		var inside := absf((x0 + x1) * 0.5) < wo
		var lo0: float = open_h.call(x0) + ring if inside else hu - 8.0
		var lo1: float = open_h.call(x1) + ring if inside else hu - 8.0
		if absf(x0) < wo and not absf(x1) < wo:
			lo1 = lo0
		elif absf(x1) < wo and not absf(x0) < wo:
			lo0 = lo1
		var h := minf(lo0, lo1)
		# horizontal courses between lo and top
		var hb := floorf(h / course) * course
		while hb < top:
			var a0 := maxf(hb, lo0)
			var a1 := maxf(hb, lo1)
			var b := minf(hb + course, top)
			if b > a0 or b > a1:
				var col: Color = lk[0] if int(hb / course) % 2 == 0 else lk[1]
				quadv.call(P.call(x0, a0), P.call(x1, a1), P.call(x1, maxf(b, a1)), P.call(x0, maxf(b, a0)), col, n3)
			hb += course
	# the ring round the opening: voussoirs (alternating), with a little depth
	var M := 13
	for j in M:
		var x0 := -wo + 2.0 * wo * j / M
		var x1 := -wo + 2.0 * wo * (j + 1) / M
		var h0: float = open_h.call(x0)
		var h1: float = open_h.call(x1)
		var col: Color = lk[2] if j % 2 == 0 else lk[3]
		if j == M / 2:
			col = lk[2].lightened(0.15)
		quadv.call(P.call(x0, h0, 2.0), P.call(x1, h1, 2.0), P.call(x1, h1 + ring + (6.0 if j == M / 2 else 0.0), 2.0), P.call(x0, h0 + ring + (6.0 if j == M / 2 else 0.0), 2.0), col, n3)
		# soffit: the underside of the arch going back into the dark
		quadv.call(P.call(x0, h0, 2.0), P.call(x1, h1, 2.0), P.call(x1, h1, -40.0), P.call(x0, h0, -40.0), col.darkened(0.45), Vector3.DOWN)
		if kind == "snow" and j % 2 == 0 and j > 0:
			# icicles hanging from the arch
			var xm := (x0 + x1) * 0.5
			var hm: float = open_h.call(xm)
			var ln := 10.0 + 9.0 * float((j * 7) % 3)
			for v in [P.call(xm - 4.0, hm, 2.5), P.call(xm + 4.0, hm, 2.5), P.call(xm, hm - ln, 2.5)]:
				st.set_color(Color("#cfefff"))
				st.set_normal(n3)
				st.add_vertex(v)
	# piers either side of the opening, down to the road
	for sx: float in [-1.0, 1.0]:
		var xa := wo * sx
		var xb := (wo + ring) * sx
		quadv.call(P.call(xa, hu - 4.0, 2.0), P.call(xb, hu - 4.0, 2.0), P.call(xb, spring + ring, 2.0), P.call(xa, spring + ring * 0.3, 2.0), lk[3], n3)
	# a cap along the top where the wall meets the deck
	if kind == "snow":
		quadv.call(P.call(-ww, top, 0.0), P.call(ww, top, 0.0), P.call(ww, top, 6.0), P.call(-ww, top, 6.0), Color("#f4f8fb"), Vector3.UP)
	elif kind == "forest":
		quadv.call(P.call(-ww, top - 3.0, 3.0), P.call(ww, top - 3.0, 3.0), P.call(ww, top + 1.0, 3.0), P.call(-ww, top + 1.0, 3.0), Color("#5c8a3a"), n3)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vert_mat
	static_root.add_child(mi)

# A car the player can't see under a bridge shows through it as a flat silhouette
# in its own colour (stencil x-ray: drawn only where something hides it)
static func xray(car: Node3D, col: Color) -> void:
	for mi in car.find_children("*", "MeshInstance3D", true, false):
		var m: Material = (mi as MeshInstance3D).material_override
		if m == null and (mi as MeshInstance3D).mesh != null and (mi as MeshInstance3D).mesh.get_surface_count() > 0:
			m = (mi as MeshInstance3D).mesh.surface_get_material(0)
		if not (m is BaseMaterial3D) or (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var m2 := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
		m2.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY
		m2.stencil_color = Color(col.lightened(0.2), 0.5)
		(mi as MeshInstance3D).material_override = m2

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
	if detail > 1 and sides >= 5:
		sides *= 2
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
		shacks.append(Transform3D(basis_for.call(yaw, 1.35), w3(p, ground_low(p, 90.0))))

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
				var xf := Transform3D(basis_for.call(rng.randf() * TAU, sc), w3(p, ground_h(p) - 3.0))
				var pick_a := rng.randf() < 0.6
				# Low graphics: about half the trees (the same rng draws either way, so the
				# woods keep their shape at every setting)
				if quality > 0 or (int(p.x * 0.37) + int(p.y * 0.53)) % 2 == 0:
					(pines_a if pick_a else pines_b).append(xf)
				mark.call(p, 30.0 * sc, 2)
			elif r < kit["rocks"]:
				var rs := 0.6 + rng.randf() * 0.8
				rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rs * 1.4, rs, rs * 0.85)), w3(p, ground_h(p) - 4.0)))
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

# Graphics quality (Settings "quality"): 0 Low, 1 Medium, 2 High.
#   Low:    3D drawn at 70% resolution, no shadows, glow, weather, MSAA or release wind, half the trees
#   Medium: 3D at 85% resolution, shadows, glow, weather, 2x MSAA
#   High:   full resolution, everything on, softer shadows
# The UI is always drawn at full resolution. Tree count changes on the next track load.
var quality := 2
var effects_on := true
func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	effects_on = quality > 0
	light.shadow_enabled = quality > 0
	env.glow_enabled = quality > 0
	var vp := get_viewport()
	vp.scaling_3d_scale = [0.7, 0.85, 1.0][quality]
	vp.msaa_3d = Viewport.MSAA_DISABLED if quality == 0 else Viewport.MSAA_2X
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_LOW if quality == 2 else RenderingServer.SHADOW_QUALITY_HARD)

# Speed feel: letting go of the tether sends a moment of wind streaming past the car:
# thin light streaks along its sides and over the roof, left hanging in the air so the
# car pulls away from them (not on Low graphics). wind: human index -> 0..1, decays.
const WIND_MAX := 48
const WIND_LIFE := 0.32
var wind := {}
var _wind_pool: Array = []
var _wind_mats: Array = []     # a few alpha steps, shared (no per-instance colours, see _build_fx)
var _winds: Array = []         # {p: Vector3, dir: Vector3, len, life}
var _wind_acc := {}            # human -> fractional streaks owed
func kick_release(human: int) -> void:
	wind[human] = 1.0

# streaks in the air right now (demo screenshots)
func wind_count() -> int:
	return _winds.size()

func _build_wind() -> void:
	_wind_pool.clear()
	_winds.clear()
	if _wind_mats.is_empty():
		for k in 5:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.93, 0.97, 1.0, 0.16 * (k + 1))
			m.no_depth_test = false
			_wind_mats.append(m)
	var box := BoxMesh.new()
	box.size = Vector3(1, 1, 1)
	for k in WIND_MAX:
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dyn_root.add_child(mi)
		_wind_pool.append(mi)

# called per human car from sync: new streaks while its wind lasts
func _wind_car(c, y: float, dt: float) -> void:
	var a: float = wind.get(c.human, 0.0)
	if a <= 0.0:
		return
	a *= exp(-2.2 * dt)
	wind[c.human] = a if a > 0.03 else 0.0
	var spd: float = c.vel.length()
	if quality == 0 or spd < 150.0 or c.air > 0.0 or c.fall > 0.0:
		return
	var owed: float = _wind_acc.get(c.human, 0.0) + dt * 70.0 * a
	var fwd: Vector2 = c.vel / spd
	var side := Vector2(-fwd.y, fwd.x)
	while owed >= 1.0:
		owed -= 1.0
		if _winds.size() >= WIND_MAX:
			_winds.pop_front()
		# along either flank or just over the roof, from the nose back
		var lat := (randf() * 2.0 - 1.0) * 34.0
		var up := 6.0 + randf() * 22.0 if absf(lat) > 22.0 else 26.0 + randf() * 8.0
		var p2: Vector2 = c.pos + side * lat + fwd * (randf() * 40.0 - 10.0)
		_winds.append({ "p": w3(p2, y + ROAD_Y + up), "dir": Vector3(fwd.x, 0, fwd.y),
			"len": (45.0 + randf() * 50.0) * clampf(spd / 600.0, 0.6, 1.3), "life": WIND_LIFE, "a": a })
	_wind_acc[c.human] = owed

func _update_wind(dt: float) -> void:
	var alive: Array = []
	for w in _winds:
		w["life"] -= dt
		if w["life"] > 0.0:
			alive.append(w)
	_winds = alive
	for k in _wind_pool.size():
		var mi: MeshInstance3D = _wind_pool[k]
		if k >= _winds.size():
			mi.visible = false
			continue
		var w: Dictionary = _winds[k]
		var t: float = w["life"] / WIND_LIFE              # 1 when born, 0 when gone
		var fade := sin(t * PI) * float(w["a"])          # in and out
		mi.material_override = _wind_mats[clampi(int(fade * 5.0), 0, 4)]
		var d: Vector3 = w["dir"]
		var len: float = float(w["len"]) * (0.5 + 0.5 * (1.0 - t)) * U   # stretches as it trails
		var b := Basis.looking_at(d, Vector3.UP) * Basis.from_scale(Vector3(3.0 * U, 1.5 * U, len))
		mi.transform = Transform3D(b, Vector3(w["p"]) - d * len * 0.5)
		mi.visible = fade > 0.03

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
					tip.set_surface_override_material(0, mat(COL_POST, false, 0.6))
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
	# the world's own obstacle (snowman, toadstool, jar, cairn): same 32 footprint everywhere
	var pm := TrackObjects.post_mesh(String(th.get("post", "")), quality == 0)
	for o in track.obstacles:
		var p := MeshInstance3D.new()
		p.mesh = pm
		p.material_override = _vert_mat
		p.position = w3(o["pos"], 0.0)
		p.rotation.y = -Vector2(o["pos"]).angle() * 3.0   # vary which way each one faces
		static_root.add_child(p)
		post_nodes.append(p)

func _build_gems() -> void:
	# the world's own gem, unshaded with its facets baked in so it glows like before
	var gm := StandardMaterial3D.new()
	gm.vertex_color_use_as_albedo = true
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := TrackObjects.gem_mesh(String(th.get("gem", "")), quality == 0)
	for g in track.tokens:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = gm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var h := track.height_at(g["s"])
		mi.position = w3(g["pos"], h + 34.0)
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
	_build_wind()

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
	if detail > 1:
		mi.mesh = bevel_box(size, m)
		mi.position = pos * U
		return mi
	var bm := BoxMesh.new()
	bm.size = size * U
	bm.material = m
	mi.mesh = bm
	mi.position = pos * U
	return mi

# A box with chamfered edges and corners (detail 2): six inset faces, twelve edge strips,
# eight corner triangles. `size` in world units like pbox.
static func bevel_box(size: Vector3, m: Material) -> ArrayMesh:
	var h := size * 0.5
	var e := minf(minf(minf(h.x, h.y), h.z) * 0.4, 4.0)
	# the point of corner (sx, sy, sz) that lies on the face across `axis`
	var pt := func(sg: Vector3, axis: int) -> Vector3:
		var v := Vector3()
		for i in 3:
			v[i] = sg[i] * (h[i] if i == axis else h[i] - e)
		return v * U
	var faces: Array = []
	var signs: Array = []
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				signs.append(Vector3(sx, sy, sz))
	for i in 3:
		var j := (i + 1) % 3
		var k := (i + 2) % 3
		for si: float in [-1.0, 1.0]:
			# main face across axis i
			var q: Array = []
			for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var sg := Vector3()
				sg[i] = si; sg[j] = c.x; sg[k] = c.y
				q.append(pt.call(sg, i))
			faces.append(q)
			# edge strips between face i and face j
			for sj: float in [-1.0, 1.0]:
				var a := Vector3(); a[i] = si; a[j] = sj; a[k] = 1.0
				var b := Vector3(); b[i] = si; b[j] = sj; b[k] = -1.0
				faces.append([pt.call(a, i), pt.call(a, j), pt.call(b, j), pt.call(b, i)])
	for sg: Vector3 in signs:
		faces.append([pt.call(sg, 0), pt.call(sg, 1), pt.call(sg, 2)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for f: Array in faces:
		var ctr := Vector3()
		for v: Vector3 in f:
			ctr += v
		ctr /= f.size()
		var nrm: Vector3 = (f[1] - f[0]).cross(f[2] - f[0]).normalized()
		if nrm.dot(ctr) > 0.0:
			f.reverse()
			nrm = -nrm
		st.set_normal(-nrm)
		for t in range(1, f.size() - 1):
			for v in [f[0], f[t], f[t + 1]]:
				st.add_vertex(v)
	st.set_material(m)
	return st.commit()
# a polygon with each corner cut to a curve of about radius r
static func rounded(poly: PackedVector2Array, r: float, segs := 4, radii := PackedFloat32Array()) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var p := poly[i]
		if i < radii.size():   # per-corner cut, overrides r
			r = radii[i]
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

# A side profile (x, y) extruded across the car (z) with its long edges rounded off
# (radius r), smooth shaded: the artwork's car panels (detail 2).
static func soft_prism(profile: PackedVector2Array, depth: float, r: float, m: Material, segs := 3, smooth := true) -> MeshInstance3D:
	var P := profile.duplicate()
	var n := P.size()
	var area := 0.0
	for i in n:
		area += P[i].cross(P[(i + 1) % n])
	if area < 0.0:
		P.reverse()
	var nrm := PackedVector2Array()
	var ctr2 := Vector2()
	for i in n:
		var e1 := P[i] - P[(i + n - 1) % n]
		var e2 := P[(i + 1) % n] - P[i]
		nrm.append((Vector2(e1.y, -e1.x).normalized() + Vector2(e2.y, -e2.x).normalized()).normalized())
		ctr2 += P[i] / n
	var hz := depth * 0.5
	var rr := minf(r, hz * 0.9)
	var rings: Array = []
	var ring_at := func(side: float, th: float) -> Array:
		var inset := rr * (1.0 - cos(th))
		var z := side * ((hz - rr) + rr * sin(th))
		var ring: Array = []
		for i in n:
			var q := P[i] - nrm[i] * inset
			ring.append(Vector3(q.x, q.y, z))
		return ring
	for k in range(segs, -1, -1):
		rings.append(ring_at.call(-1.0, PI * 0.5 * k / segs))
	for k in range(0, segs + 1):
		rings.append(ring_at.call(1.0, PI * 0.5 * k / segs))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if not smooth:
		st.set_smooth_group(-1)
	var tri := func(a: Vector3, b: Vector3, c: Vector3, out: Vector3) -> void:
		if (b - a).cross(c - a).dot(out) > 0.0:
			var t := b; b = c; c = t
		for v: Vector3 in [a, b, c]:
			st.add_vertex(v * U)
	var ctr := Vector3(ctr2.x, ctr2.y, 0.0)
	for j in rings.size() - 1:
		var r0: Array = rings[j]
		var r1: Array = rings[j + 1]
		for i in n:
			var a: Vector3 = r0[i]; var b: Vector3 = r0[(i + 1) % n]
			var c: Vector3 = r1[(i + 1) % n]; var d: Vector3 = r1[i]
			var mid := (a + c) * 0.5
			var o := Vector3(mid.x - ctr.x, mid.y - ctr.y, 0.0).normalized() + Vector3(0, 0, mid.z / maxf(hz, 0.01)) * 0.5
			tri.call(a, b, c, o)
			tri.call(a, c, d, o)
	# caps: triangulate the profile itself (the inset ring can pinch at tight corners,
	# which makes triangulate_polygon give up) and reuse the indices on the ring
	var idx := Geometry2D.triangulate_polygon(P)
	for cap in [rings[0], rings[rings.size() - 1]]:
		var zc: float = cap[0].z
		for t in range(0, idx.size(), 3):
			tri.call(cap[idx[t]], cap[idx[t + 1]], cap[idx[t + 2]], Vector3(0, 0, signf(zc)))
	if smooth:
		st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	return mi

# a short cylinder along the car's x (lamps) or z (wheel parts) axis
static func pcyl(r: float, h: float, m: Material, pos: Vector3, axis := "z", segs := 32) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * U; cm.bottom_radius = r * U; cm.height = h * U
	cm.radial_segments = segs; cm.rings = 1
	cm.material = m
	mi.mesh = cm
	mi.position = pos * U
	if axis == "z":
		mi.rotation.x = PI / 2
	else:
		mi.rotation.z = PI / 2
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

# ---------------------------------------------------------------- garage
# The garage stage: one car on a snowy (or the theme's) plinth, tethered to a short post,
# turning slowly, photographed out in its own world (its ground and a ring of the world's
# trees, cacti or spires behind). Lives in its own SubViewport; no track is built.
var showroom_rig: Node3D
var showroom_land: Node3D

func showroom(look: Dictionary, theme: String) -> void:
	th = Themes.get_theme(theme)
	if showroom_rig:
		showroom_rig.queue_free()
	if showroom_land:
		showroom_land.queue_free()
	var ground0: Color = th["ground"]
	env.background_color = ground0.lerp(th["ambient"], 0.35)
	env.glow_enabled = false   # in a small SubViewport the glow washes the whole frame
	env.ambient_light_color = th["ambient"]
	env.ambient_light_energy = 0.75
	light.light_color = th["sun"]
	light.rotation = Vector3(deg_to_rad(-50), deg_to_rad(-30), 0)
	var rig := Node3D.new()
	dyn_root.add_child(rig)
	showroom_rig = rig
	var ground: Color = th["ground"]
	var plinth := ground.darkened(0.12) if ground.get_luminance() < 0.6 else ground.darkened(0.42)
	rig.add_child(cyl(205, 8, plinth, Vector3(0, -4.5, -102), 215.0, 48))
	# the land round the plinth: the world's ground, darker spots, and its scenery behind
	var land := Node3D.new()
	dyn_root.add_child(land)
	showroom_land = land
	land.add_child(cyl(4000, 6, ground, Vector3(0, -9, -102), -1.0, 48))
	var kit := _prop_kit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in 26:
		var a := deg_to_rad(-170.0 + 160.0 * k / 25.0) + rng.randf_range(-0.05, 0.05)   # the far half, behind the car
		var r := rng.randf_range(300.0, 620.0)
		var p := Vector2(cos(a), sin(a)) * r + Vector2(0, -102)
		if k % 3 == 0:
			land.add_child(cyl(rng.randf_range(40, 90), 4, th["ground_dots"], Vector3(p.x, -6.5, p.y), -1.0, 10))
		var mi := MeshInstance3D.new()
		mi.mesh = kit["a"] if rng.randf() < 0.65 else kit["b"]
		var sc := rng.randf_range(0.45, 0.75)
		mi.transform = Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc), w3(p, -6.0))
		land.add_child(mi)
	var car := _make_car(look["color"], false, look)
	rig.add_child(car)
	# the rope: from the car's roof out to a little capstan post on the plinth
	var post := cyl(12, 70, Color("#2a2f36"), Vector3(0, 35, -205), -1.0, 12)
	rig.add_child(post)
	rig.add_child(cyl(16, 10, Color("#6b4a2e"), Vector3(0, 66, -205), -1.0, 12))
	var rope := cyl(2.6, 180, look.get("rope", look["color"]), Vector3(0, 62, -112), -1.0, 8)
	rope.set_surface_override_material(0, mat(look.get("rope", look["color"]), true))
	rope.rotation.x = PI / 2
	rig.add_child(rope)
	# turn round the middle of the rope
	rig.position = Vector3(0, 0, -1.02)
	for ch in rig.get_children():
		ch.position.z += 1.02
	camera.fov = 34
	camera.position = Vector3(0, 2.3, 3.2)
	camera.look_at(Vector3(0, 0.1, -1.02))
	rig.rotation.y = showroom_turn

var showroom_turn := 0.9

func turn_showroom(dt: float) -> void:
	showroom_turn = fmod(showroom_turn + dt * 0.35, TAU)
	if showroom_rig:
		showroom_rig.rotation.y = showroom_turn

# a paint finish (Cosmetics): gloss is the plain toy-car paint
static func finish_paint(c: Color, finish: String) -> Material:
	var m := paint(c)
	match finish:
		"metallic":
			m.metallic = 0.55; m.roughness = 0.3; m.metallic_specular = 0.8
			m.albedo_color = c.lightened(0.08)
		"matte":
			m.roughness = 0.85; m.clearcoat_enabled = false; m.rim = 0.15; m.metallic_specular = 0.3
		"pearl":
			m.roughness = 0.22; m.clearcoat = 1.0; m.rim = 0.7; m.rim_tint = 0.1
		"chrome":
			return chrome_paint(c)
		"neon":
			m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.55
			m.roughness = 0.25
	return m

# Chrome without reflection probes (cheap on phones): the reflected view ray picks a
# colour from a made-up studio sky (bright top, a hard dark horizon line, dim ground), so
# the panels get the sharp light/dark bands that read as a mirror finish.
static var _chrome_shader: Shader
static func chrome_paint(c: Color) -> ShaderMaterial:
	if _chrome_shader == null:
		_chrome_shader = Shader.new()
		_chrome_shader.code = """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec3 tint : source_color;
void fragment() {
	vec3 r = reflect(-VIEW, NORMAL);
	vec3 rw = (INV_VIEW_MATRIX * vec4(r, 0.0)).xyz;
	float y = rw.y;
	vec3 sky = mix(vec3(0.62, 0.70, 0.80), vec3(1.0, 1.0, 1.0), smoothstep(0.05, 0.7, y));
	vec3 gnd = mix(vec3(0.42, 0.40, 0.40), vec3(0.16, 0.16, 0.17), smoothstep(0.0, -0.6, y));
	vec3 env = mix(gnd, sky, smoothstep(-0.02, 0.03, y));
	env = mix(env, vec3(0.05), (1.0 - smoothstep(0.0, 0.06, abs(y - 0.02))) * 0.8);
	ALBEDO = vec3(0.0);
	EMISSION = env * tint * 0.95;
	METALLIC = 1.0;
	ROUGHNESS = 0.15;
	SPECULAR = 0.8;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _chrome_shader
	m.set_shader_parameter("tint", c)
	return m

func _make_car(col: Color, ghost := false, look := {}) -> Node3D:
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
		var finish := String(look.get("finish", "gloss"))
		var top := finish_paint(col, finish)
		var low: Material = finish_paint(col.darkened(0.38), "matte" if finish == "matte" else "gloss")
		if finish != "matte":
			(low as StandardMaterial3D).roughness = 0.5
		var glass := paint(Color("#1a2330"), 0.08)
		glass.metallic = 0.4
		var steel := paint(Color("#9aa3ad"), 0.3)
		steel.metallic = 0.6
		var k := { "top": top, "low": low, "glass": glass, "dark": paint(Color("#1d2229"), 0.6),
			"steel": steel, "lamp": mat(Color("#fff4c8"), true), "tail": mat(Color("#ff4a3a"), false, 1.2) }
		var lay := _vehicle(body_id(look, String(th["kit"])), chassis, parts_list, k)
		_livery(parts_list, look, col, lay)
	for p in parts_list:
		if ghost:
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(p)
	root.set_meta("body", body)
	root.set_meta("chassis", chassis)
	return root

# ---------------------------------------------------------------- vehicles
# Each world drives its own kind of vehicle, three to pick from in the Garage (Cosmetics
# BODIES); the first of each world is its default and what the rivals drive. Units as the
# rest of the car: about 128 long (x -60..68, nose +x), y up from the road, z across.
# Each builder returns where a livery can go (see _livery):
#   "side"  [x0, x1, y0, y1, z]   a flat panel on both flanks (at +z and -z)
#   "tops"  [[x0, x1, y at x0, y at x1, width], ...]   flat or sloped upper faces
#   "main"  the top that carries the number roundel, "front" the one the chequers cross
#   "door"  [x, y, r] (optional) where the side roundel goes
const BODIES := ["sled", "snowcat", "van", "pickup", "jeep", "hauler",
	"buggy", "rally", "bug", "monster", "crawler", "expedition"]
const BODY_DEFAULT := { "snow": "sled", "forest": "pickup", "sand": "buggy", "rock": "monster" }

# the vehicle a look drives in a world: an explicit "body" (the Garage stage), else the
# player's pick for that world ("bodies"), else the world's default
static func body_id(look: Dictionary, kit: String) -> String:
	var b := String(look.get("body", ""))
	if b == "":
		b = String(look.get("bodies", {}).get(kit, ""))
	return b if b in BODIES else String(BODY_DEFAULT.get(kit, "sled"))

func _vehicle(id: String, ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	match id:
		"snowcat": return _v_snowcat(ch, P, k)
		"van": return _v_van(ch, P, k)
		"pickup": return _v_pickup(ch, P, k)
		"jeep": return _v_jeep(ch, P, k)
		"hauler": return _v_hauler(ch, P, k)
		"buggy": return _v_buggy(ch, P, k)
		"rally": return _v_rally(ch, P, k)
		"bug": return _v_bug(ch, P, k)
		"monster": return _v_monster(ch, P, k)
		"crawler": return _v_crawler(ch, P, k)
		"expedition": return _v_expedition(ch, P, k)
	return _v_sled(ch, P, k)

func _lamps(P: Array, k: Dictionary, x: float, y: float, zs: Array, size := Vector3(3, 6, 10), rear := false) -> void:
	for z: float in zs:
		P.append(pbox(size, k["tail"] if rear else k["lamp"], Vector3(x, y, z)))

func _four(ch: Node3D, xs: Array, z: float, r: float, w: float, tyre: Material, hub: Material) -> void:
	for x: float in xs:
		for s: float in [-1.0, 1.0]:
			_wheel(ch, x, z * s, r, w, tyre, hub)

# a log lying along the car, with its cut ends showing
func _log(P: Array, len_: float, r: float, pos: Vector3) -> void:
	var lg := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * U; cm.bottom_radius = r * U; cm.height = len_ * U
	cm.radial_segments = 8 if detail == 1 else 24; cm.rings = 1
	cm.material = paint(Color("#6b4a2e"), 0.85)
	lg.mesh = cm
	lg.position = pos * U
	lg.rotation.z = PI / 2
	P.append(lg)
	for e: float in [-1.0, 1.0]:
		P.append(pbox(Vector3(1, r * 1.6, r * 1.6), paint(Color("#d8b47a"), 0.7), pos + Vector3(e * len_ * 0.5, 0, 0)))

# a square tube from a to b (roll cages, struts)
static func _bar(P: Array, a: Vector3, b: Vector3, t: float, m: Material) -> void:
	var mi := pbox(Vector3((b - a).length(), t, t), m, (a + b) * 0.5)
	var d := b - a
	mi.rotation = Vector3(0, -atan2(d.z, d.x), atan2(d.y, Vector2(d.x, d.z).length()))
	P.append(mi)

static func _ski(ch: Node3D, x: float, z: float, l: float, ski: Material) -> void:
	ch.add_child(pbox(Vector3(l, 3, 12), ski, Vector3(x, 1.5, z)))
	var tip := pbox(Vector3(12, 3, 12), ski, Vector3(x + l * 0.5 + 4, 5.0, z))
	tip.rotation.z = 0.6
	ch.add_child(tip)

# --- Snowfield
# snowmobile: two skis up front, one wide track behind, the rider's seat under a glass canopy
func _v_sled(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	var ski := paint(Color("#e9eef2"), 0.4)
	for s: float in [1.0, -1.0]:
		_ski(ch, 44, 30.0 * s, 36, ski)
		_bar(P, Vector3(44, 3, 30.0 * s), Vector3(36, 22, 14.0 * s), 3.0, k["dark"])
	var prof := rounded(PackedVector2Array([Vector2(-60, 0), Vector2(-4, 0), Vector2(4, 14),
			Vector2(-64, 14)]), 4.0, 8)
	ch.add_child(pprism(prof, 40.0, paint(Color("#22262c"), 0.85)))
	_pod_lugs(ch, prof, -30.0, paint(Color("#59636e"), 0.7), 0.0, 40.0, 8)
	P.append(pprism(PackedVector2Array([Vector2(-62, 16), Vector2(20, 16), Vector2(66, 22),
			Vector2(58, 34), Vector2(-62, 34)]), 46.0, k["top"]))   # hull
	P.append(pbox(Vector3(84, 4, 48), k["low"], Vector3(-20, 18, 0)))   # running boards
	P.append(soft_prism(rounded(PackedVector2Array([Vector2(-48, 32), Vector2(30, 34),
			Vector2(10, 52), Vector2(-26, 54), Vector2(-46, 44)]), 5.0, 3), 36.0, 4.0, k["glass"], 2, false))
	P.append(pbox(Vector3(28, 2, 2), k["top"], Vector3(-8, 53.5, 0)))   # spine over the canopy
	P.append(pbox(Vector3(3, 5, 10), k["lamp"], Vector3(62, 28, 0)))
	P.append(pbox(Vector3(3, 4, 14), k["tail"], Vector3(-62.5, 26, 0)))
	return { "side": [-58, 40, 20, 33, 23], "tops": [[-62, -47, 34, 34, 44], [31, 57, 34, 34, 44]],
		"main": 1, "front": 1 }

# snowcat: a tall glass cabin on four crawler pods, beacon on the roof
func _v_snowcat(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	_pods(ch, P, k)
	P.append(pbox(Vector3(124, 8, 58), k["low"], Vector3(4, 18, 0)))
	P.append(pbox(Vector3(124, 12, 62), k["top"], Vector3(4, 28, 0)))
	P.append(pprism(PackedVector2Array([Vector2(-44, 34), Vector2(46, 34), Vector2(38, 62),
			Vector2(-42, 62)]), 54.0, k["glass"]))
	P.append(pbox(Vector3(86, 4, 60), k["top"], Vector3(-2, 64, 0)))
	for px: float in [-42.0, 0.0, 41.0]:
		for pz: float in [-27.5, 27.5]:
			P.append(pbox(Vector3(4, 28, 3), k["top"], Vector3(px, 48, pz)))
	P.append(pbox(Vector3(8, 6, 8), mat(Color("#ff9a2a"), true), Vector3(-36, 69, 0)))   # beacon
	_lamps(P, k, 66.5, 28, [-20.0, 20.0])
	_lamps(P, k, -58.5, 28, [-20.0, 20.0], Vector3(3, 6, 10), true)
	return { "side": [-56, 64, 23, 33, 31],
		"tops": [[-58, -44, 34, 34, 60], [46, 66, 34, 34, 60], [-45, 41, 66, 66, 58]], "main": 2, "front": 1 }

# arctic van: a rounded box on crawler pods, skis on the roof rack
func _v_van(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	_pods(ch, P, k)
	P.append(pbox(Vector3(124, 8, 58), k["low"], Vector3(4, 18, 0)))
	P.append(soft_prism(rounded(PackedVector2Array([Vector2(-60, 22), Vector2(66, 22),
			Vector2(66, 36), Vector2(44, 62), Vector2(-60, 62)]), 6.0, 3), 62.0, 2.0, k["top"], 2, false))
	P.append(pprism(PackedVector2Array([Vector2(48, 37), Vector2(64, 37), Vector2(46, 58),
			Vector2(40, 58)]), 56.0, k["glass"]))   # windscreen
	for wx: float in [-40.0, -14.0, 12.0]:
		for wz: float in [-31.2, 31.2]:
			P.append(pbox(Vector3(20, 12, 0.6), k["glass"], Vector3(wx, 48, wz)))
	for rz: float in [-21.0, 21.0]:
		P.append(pbox(Vector3(90, 3, 3), k["dark"], Vector3(-6, 64, rz)))
	for kz: float in [-19.0, -14.0, 14.0, 19.0]:
		P.append(pbox(Vector3(80, 2, 4), mat(Color("#e8503a")), Vector3(-6, 66.5, kz)))
	_lamps(P, k, 66.5, 30, [-20.0, 20.0])
	_lamps(P, k, -60.5, 40, [-20.0, 20.0], Vector3(3, 6, 8), true)
	return { "side": [-54, 60, 25, 40, 31], "tops": [[-53, 38, 62, 62, 56]], "main": 0, "front": 0 }

# triangular crawler pods at the four corners (snowcat, van), plus a dark lower front and a
# small steel plough under the nose
func _pods(ch: Node3D, P: Array, k: Dictionary) -> void:
	var tread := paint(Color("#22262c"), 0.85)
	var lug := paint(Color("#59636e"), 0.7)
	for px: float in POD_X:
		for side: float in [1.0, -1.0]:
			var z := POD_Z * side
			var prof := _pod_side(px, 3 if detail > 1 else 2)
			var pod: MeshInstance3D
			if detail > 1:
				pod = soft_prism(prof, POD_W, 2.0, tread, 3, false)
			else:
				pod = pprism(prof, POD_W, tread)
			pod.position.z = z * U
			ch.add_child(pod)
			_pod_lugs(ch, prof, px, lug, z)
			ch.add_child(pbox(Vector3(9, 9, 2), k["dark"], Vector3(px, 13, z + (POD_W * 0.5 + 1.0) * side)))   # hub
			ch.add_child(pbox(Vector3(8, 10, 8), k["dark"], Vector3(px, 19, z - 9.0 * side)))   # mount
	P.append(pbox(Vector3(24, 10, 50), k["dark"], Vector3(56, 15, 0)))
	var blade := pbox(Vector3(3, 13, 56), k["steel"], Vector3(71, 9, 0))
	blade.rotation.z = 0.35   # leans back, scoop forward
	P.append(blade)
	for bz in [-16.0, 16.0]:
		P.append(pbox(Vector3(8, 3, 3), k["dark"], Vector3(66, 12, bz)))

const POD_X := [-40.0, 42.0]
const POD_Z := 36.0
const POD_W := 14.0

# --- Pinewood
# pickup truck: bonnet, cab, and logs in the open bed
func _v_pickup(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	_four(ch, [-38.0, 40.0], 36.0, 18.0, 16.0, paint(Color("#1b1d1a"), 0.85), k["top"])
	P.append(pbox(Vector3(128, 8, 58), k["low"], Vector3(2, 20, 0)))
	P.append(pbox(Vector3(42, 12, 60), k["top"], Vector3(5, 30, 0)))   # cab sides
	P.append(pprism(PackedVector2Array([Vector2(26, 24), Vector2(68, 24), Vector2(68, 32),
			Vector2(26, 38)]), 60.0, k["top"]))   # bonnet
	P.append(pprism(PackedVector2Array([Vector2(-16, 36), Vector2(28, 36), Vector2(16, 58),
			Vector2(-14, 58)]), 54.0, k["glass"]))
	P.append(pbox(Vector3(32, 3, 56), k["top"], Vector3(1, 59, 0)))   # cab roof
	P.append(pbox(Vector3(46, 4, 60), k["top"], Vector3(-39, 26, 0)))   # bed floor, walls, tailgate
	for wz: float in [-28.5, 28.5]:
		P.append(pbox(Vector3(46, 14, 3), k["top"], Vector3(-39, 35, wz)))
	P.append(pbox(Vector3(3, 14, 60), k["top"], Vector3(-60.5, 35, 0)))
	for lz: float in [-15.0, 0.0, 15.0]:
		_log(P, 50.0, 7.0, Vector3(-36, 35, lz))
	_log(P, 46.0, 6.0, Vector3(-36, 46, -7.5))
	_log(P, 46.0, 6.0, Vector3(-36, 46, 7.5))
	P.append(pbox(Vector3(1.6, 6, 26), k["dark"], Vector3(68.2, 28, 0)))   # grille
	_lamps(P, k, 68.5, 28, [-21.0, 21.0], Vector3(3, 6, 10))
	_lamps(P, k, -62.5, 36, [-21.0, 21.0], Vector3(3, 6, 8), true)
	return { "side": [-60, 66, 24.5, 31.5, 30], "tops": [[27, 67, 37.86, 32.14, 56], [-15, 17, 60.5, 60.5, 54]],
		"main": 0, "front": 0, "door": [5, 30.5, 5.5] }

# open-top 4x4: flat bonnet, upright screen, roll bar, spare wheel on the tail
func _v_jeep(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	var tyre := paint(Color("#1b1d1a"), 0.85)
	_four(ch, [-38.0, 40.0], 36.0, 18.0, 16.0, tyre, k["top"])
	for gx: float in [40.0, -38.0]:   # flat mudguards over the wheels
		for gz: float in [-30.0, 30.0]:
			P.append(pbox(Vector3(40, 3, 14), k["top"], Vector3(gx, 38, gz)))
	P.append(pbox(Vector3(124, 18, 48), k["top"], Vector3(4, 29, 0)))
	P.append(pbox(Vector3(124, 6, 50), k["low"], Vector3(4, 18, 0)))
	P.append(pbox(Vector3(4, 16, 46), k["glass"], Vector3(20, 46, 0)))   # upright screen
	for sz: float in [-23.0, 23.0]:
		P.append(pbox(Vector3(5, 18, 3), k["dark"], Vector3(20, 46, sz)))
	for cz: float in [-21.0, 21.0]:
		_bar(P, Vector3(-30, 38, cz), Vector3(-30, 62, cz), 3.0, k["dark"])
	_bar(P, Vector3(-30, 62, -21), Vector3(-30, 62, 21), 3.0, k["dark"])
	var seat := paint(Color("#2b3038"), 0.8)
	for sz: float in [-11.0, 11.0]:
		P.append(pbox(Vector3(5, 14, 14), seat, Vector3(-14, 44, sz)))
	var spare := Node3D.new()   # upright on the tail, facing back
	_wheel(spare, 0, 0, 14.0, 9.0, tyre, k["top"])
	spare.rotation.y = PI / 2
	spare.position = Vector3(-63, 20, 0) * U
	P.append(spare)
	P.append(pbox(Vector3(4, 10, 40), k["dark"], Vector3(66.5, 30, 0)))   # grille
	_lamps(P, k, 67, 32, [-17.0, 17.0], Vector3(4, 7, 7))
	_lamps(P, k, -58.5, 32, [-19.0, 19.0], Vector3(3, 5, 6), true)
	return { "side": [-56, 64, 22, 35, 24], "tops": [[23, 65, 38, 38, 40], [-57, -33, 38, 38, 40]],
		"main": 0, "front": 0 }

# timber hauler: a cab-over front and a long bed of logs between stakes
func _v_hauler(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	var tyre := paint(Color("#1b1d1a"), 0.85)
	for wx: float in [-44.0, -24.0, 44.0]:
		for wz: float in [-34.0, 34.0]:
			_wheel(ch, wx, wz, 15.0, 14.0, tyre, k["top"])
	P.append(pbox(Vector3(130, 6, 44), k["dark"], Vector3(0, 20, 0)))   # frame
	P.append(pbox(Vector3(36, 40, 62), k["top"], Vector3(50, 42, 0)))   # cab
	P.append(pbox(Vector3(36, 6, 58), k["low"], Vector3(50, 19, 0)))
	P.append(pprism(PackedVector2Array([Vector2(56, 44), Vector2(68.5, 44), Vector2(68.5, 58),
			Vector2(58, 58)]), 56.0, k["glass"]))
	P.append(pbox(Vector3(10, 6, 50), k["dark"], Vector3(64, 26, 0)))   # bumper
	P.append(pbox(Vector3(84, 4, 60), k["dark"], Vector3(-22, 26, 0)))   # bed
	for sx: float in [-60.0, -36.0, -12.0, 12.0]:
		for sz: float in [-28.0, 28.0]:
			P.append(pbox(Vector3(3, 28, 3), k["dark"], Vector3(sx, 42, sz)))
	for lz: float in [-17.0, 0.0, 17.0]:
		_log(P, 84.0, 8.0, Vector3(-22, 36, lz))
	for lz: float in [-8.5, 8.5]:
		_log(P, 80.0, 8.0, Vector3(-22, 50, lz))
	P.append(pbox(Vector3(3, 4, 30), mat(Color("#ff9a2a"), true), Vector3(34, 64, 0)))   # beacon bar
	_lamps(P, k, 68.5, 34, [-22.0, 22.0])
	_lamps(P, k, -64, 28, [-24.0, 24.0], Vector3(3, 5, 8), true)
	return { "side": [33, 67, 26, 50, 31], "tops": [[33, 67, 62, 62, 60]], "main": 0, "front": 0 }

# --- Dunes
# open-top buggy: a narrow tub with two seats in a roll cage, engine out the back
func _v_buggy(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	_four(ch, [-40.0, 42.0], 38.0, 18.0, 24.0, paint(Color("#2a2622"), 0.9), paint(Color("#e9e2d4"), 0.4))
	P.append(pbox(Vector3(96, 8, 40), k["low"], Vector3(-2, 18, 0)))
	P.append(pbox(Vector3(70, 12, 44), k["top"], Vector3(-12, 28, 0)))   # tub
	P.append(pprism(PackedVector2Array([Vector2(23, 14), Vector2(66, 18), Vector2(66, 24),
			Vector2(23, 34)]), 44.0, k["top"]))   # nose
	var seat := paint(Color("#2b3038"), 0.8)
	for sz: float in [-10.0, 10.0]:
		P.append(pbox(Vector3(5, 16, 14), seat, Vector3(-14, 40, sz)))
		P.append(pbox(Vector3(12, 3, 14), seat, Vector3(-9, 35.5, sz)))
	for cz: float in [-19.0, 19.0]:   # roll cage: main hoop behind the seats, bars down to the dash
		_bar(P, Vector3(-22, 34, cz), Vector3(-22, 62, cz), 3.0, k["dark"])
		_bar(P, Vector3(-22, 62, cz), Vector3(14, 56, cz), 3.0, k["dark"])
		_bar(P, Vector3(14, 56, cz), Vector3(22, 34, cz), 3.0, k["dark"])
	_bar(P, Vector3(-22, 62, -19), Vector3(-22, 62, 19), 3.0, k["dark"])
	_bar(P, Vector3(14, 56, -19), Vector3(14, 56, 19), 3.0, k["dark"])
	P.append(pbox(Vector3(22, 12, 30), k["dark"], Vector3(-38, 39, 0)))   # engine
	for ez: float in [-8.0, 8.0]:
		_bar(P, Vector3(-46, 42, ez), Vector3(-56, 50, ez), 3.0, k["steel"])
	P.append(pbox(Vector3(2, 70, 2), k["dark"], Vector3(-48, 72, 16)))   # whip flag
	P.append(pbox(Vector3(18, 12, 1.5), k["top"], Vector3(-39, 100, 16)))
	_lamps(P, k, 66.5, 21, [-13.0, 13.0], Vector3(3, 5, 8))
	_lamps(P, k, -47.5, 28, [-16.0, 16.0], Vector3(3, 4, 8), true)
	return { "side": [-46, 22, 23, 33, 22], "tops": [[-6, 23, 34, 34, 40], [24, 64, 33.77, 24.47, 40]],
		"main": 1, "front": 1 }

# desert rally truck: a tall cab-over, a cargo box with sand ladders, a roof scoop
func _v_rally(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	_four(ch, [-40.0, 42.0], 36.0, 20.0, 18.0, paint(Color("#2a2622"), 0.9), paint(Color("#e9e2d4"), 0.4))
	P.append(pbox(Vector3(124, 6, 48), k["dark"], Vector3(2, 24, 0)))
	P.append(soft_prism(rounded(PackedVector2Array([Vector2(16, 28), Vector2(68, 28), Vector2(68, 52),
			Vector2(56, 72), Vector2(16, 72)]), 4.0, 3), 62.0, 1.5, k["top"], 2, false))   # cab
	P.append(pprism(PackedVector2Array([Vector2(58, 54), Vector2(67.5, 54), Vector2(57, 70),
			Vector2(50, 70)]), 56.0, k["glass"]))
	P.append(pbox(Vector3(76, 32, 60), k["top"], Vector3(-24, 46, 0)))   # cargo box
	P.append(pbox(Vector3(76, 3, 61), k["low"], Vector3(-24, 31.5, 0)))
	P.append(pbox(Vector3(16, 8, 26), k["dark"], Vector3(26, 76, 0)))   # roof scoop
	for lz: float in [-18.0, 18.0]:   # sand ladders
		P.append(pbox(Vector3(60, 2, 12), mat(Color("#e8503a")), Vector3(-24, 63, lz)))
	_lamps(P, k, 68.5, 40, [-20.0, 0.0, 20.0])
	_lamps(P, k, -62.5, 40, [-22.0, 22.0], Vector3(3, 6, 8), true)
	return { "side": [-60, 12, 35, 59, 30], "tops": [[-61, 13, 62, 62, 60], [18, 54, 72, 72, 56]],
		"main": 0, "front": 1 }

# beach bug: a round little bubble car with a surfboard on the roof rack
func _v_bug(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	_four(ch, [-38.0, 40.0], 36.0, 17.0, 22.0, paint(Color("#2a2622"), 0.9), paint(Color("#e9e2d4"), 0.4))
	P.append(pprism(rounded(PackedVector2Array([Vector2(-58, 16), Vector2(64, 16), Vector2(66, 26),
			Vector2(40, 38), Vector2(20, 56), Vector2(-20, 58), Vector2(-50, 44), Vector2(-60, 28)]), 8.0, 4),
			58.0, k["top"]))
	P.append(pbox(Vector3(118, 5, 54), k["low"], Vector3(4, 16, 0)))
	P.append(pprism(PackedVector2Array([Vector2(-34, 40), Vector2(28, 40), Vector2(16, 54),
			Vector2(-18, 55)]), 60.0, k["glass"]))
	for rz: float in [-18.0, 18.0]:
		P.append(pbox(Vector3(44, 3, 3), k["dark"], Vector3(-2, 62, rz)))
	var board := soft_prism(rounded(PackedVector2Array([Vector2(-40, 0), Vector2(40, 0), Vector2(48, 2),
			Vector2(40, 4), Vector2(-40, 4)]), 1.5, 2), 18.0, 1.0, mat(Color("#2ab0c8")), 2, false)
	board.position = Vector3(0, 64, 0) * U
	P.append(board)
	_lamps(P, k, 62, 30, [-20.0, 20.0], Vector3(4, 8, 8))
	_lamps(P, k, -59, 30, [-18.0, 18.0], Vector3(3, 6, 8), true)
	return { "side": [-48, 40, 20, 36, 29], "tops": [[46, 60, 35.2, 28.8, 48]], "main": 0, "front": 0 }

# --- Highlands
# monster truck: huge tyres, the body lifted high on struts, light bar on the roof
func _v_monster(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	_four(ch, [-42.0, 46.0], 40.0, 26.0, 22.0, paint(Color("#1b1b1d"), 0.9), k["dark"])
	for wx: float in [-42.0, 46.0]:   # suspension struts
		for wz: float in [-24.0, 24.0]:
			_bar(P, Vector3(wx, 26, wz * 1.3), Vector3(wx + 6, 44, wz), 4.0, k["steel"])
	P.append(pbox(Vector3(80, 4, 36), k["dark"], Vector3(2, 26, 0)))   # frame
	P.append(pbox(Vector3(124, 6, 58), k["low"], Vector3(4, 44, 0)))
	P.append(pbox(Vector3(124, 12, 62), k["top"], Vector3(4, 53, 0)))
	P.append(pprism(PackedVector2Array([Vector2(-30, 58), Vector2(26, 58), Vector2(16, 76),
			Vector2(-28, 76)]), 54.0, k["glass"]))
	P.append(pbox(Vector3(46, 4, 58), k["top"], Vector3(-6, 78, 0)))   # roof
	P.append(pbox(Vector3(28, 6, 58), k["top"], Vector3(-44, 62, 0)))   # rear deck cover
	P.append(pbox(Vector3(5, 5, 50), k["dark"], Vector3(12, 82.5, 0)))   # light bar
	_lamps(P, k, 15, 82.5, [-18.0, -6.0, 6.0, 18.0], Vector3(3, 6, 8))
	P.append(pbox(Vector3(3, 4, 56), k["steel"], Vector3(69, 50, 0)))   # bull bar
	P.append(pbox(Vector3(3, 4, 56), k["steel"], Vector3(69, 38, 0)))
	for bz in [-24.0, 24.0]:
		P.append(pbox(Vector3(4, 16, 4), k["steel"], Vector3(69, 44, bz)))
	_lamps(P, k, 66.5, 53, [-20.0, 20.0])
	_lamps(P, k, -58.5, 53, [-20.0, 20.0], Vector3(3, 6, 10), true)
	return { "side": [-56, 64, 48, 58, 31],
		"tops": [[26, 66, 59, 59, 60], [-29, 17, 80, 80, 56], [-58, -30, 65, 65, 56]], "main": 0, "front": 0 }

# rock crawler: a bare tube frame on huge tyres, two seats, a winch on the nose
func _v_crawler(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	_four(ch, [-44.0, 46.0], 38.0, 24.0, 20.0, paint(Color("#1b1b1d"), 0.9), k["dark"])
	P.append(pbox(Vector3(100, 6, 34), k["low"], Vector3(0, 30, 0)))   # belly pan
	for cz: float in [-20.0, 20.0]:
		_bar(P, Vector3(-50, 34, cz), Vector3(56, 34, cz), 4.0, k["top"])
		_bar(P, Vector3(-30, 34, cz), Vector3(-26, 66, cz), 4.0, k["top"])
		_bar(P, Vector3(-26, 66, cz), Vector3(14, 64, cz), 4.0, k["top"])
		_bar(P, Vector3(14, 64, cz), Vector3(40, 36, cz), 4.0, k["top"])
		_bar(P, Vector3(-50, 34, cz), Vector3(-30, 54, cz), 4.0, k["top"])
		P.append(pbox(Vector3(56, 10, 2), k["top"], Vector3(-6, 40, 21.0 * signf(cz))))   # side panel
	_bar(P, Vector3(-26, 66, -20), Vector3(-26, 66, 20), 4.0, k["top"])
	_bar(P, Vector3(14, 64, -20), Vector3(14, 64, 20), 4.0, k["top"])
	P.append(pbox(Vector3(40, 2, 42), k["top"], Vector3(-6, 67, 0)))   # roof panel
	P.append(pbox(Vector3(22, 12, 26), k["dark"], Vector3(36, 40, 0)))   # engine
	P.append(pbox(Vector3(34, 3, 36), k["top"], Vector3(38, 47.5, 0)))   # bonnet over it
	var seat := paint(Color("#2b3038"), 0.8)
	for sz: float in [-9.0, 9.0]:
		P.append(pbox(Vector3(5, 16, 14), seat, Vector3(-16, 42, sz)))
	P.append(pbox(Vector3(8, 8, 20), k["steel"], Vector3(62, 36, 0)))   # winch
	P.append(pbox(Vector3(4, 4, 46), k["dark"], Vector3(16, 70, 0)))
	_lamps(P, k, 18.5, 70, [-15.0, -5.0, 5.0, 15.0], Vector3(3, 5, 7))
	_lamps(P, k, -52, 36, [-14.0, 14.0], Vector3(3, 5, 6), true)
	return { "side": [-32, 20, 36, 44, 22], "tops": [[22, 54, 49, 49, 34], [-25, 13, 68, 68, 40]],
		"main": 0, "front": 0 }

# six-wheel expedition truck: a cab and a boxy camper with a tent on the roof
func _v_expedition(ch: Node3D, P: Array, k: Dictionary) -> Dictionary:
	var tyre := paint(Color("#1b1b1d"), 0.9)
	for wx: float in [-46.0, -20.0, 46.0]:
		for wz: float in [-36.0, 36.0]:
			_wheel(ch, wx, wz, 18.0, 16.0, tyre, k["dark"])
	P.append(pbox(Vector3(130, 6, 46), k["dark"], Vector3(0, 24, 0)))
	P.append(pbox(Vector3(36, 30, 60), k["top"], Vector3(48, 42, 0)))   # cab
	P.append(pprism(PackedVector2Array([Vector2(52, 44), Vector2(66.5, 44), Vector2(62, 56),
			Vector2(52, 56)]), 54.0, k["glass"]))
	P.append(pbox(Vector3(80, 42, 62), k["top"], Vector3(-22, 48, 0)))   # camper
	for wx: float in [-44.0, -8.0]:
		for wz: float in [-31.3, 31.3]:
			P.append(pbox(Vector3(16, 10, 0.6), k["glass"], Vector3(wx, 56, wz)))
	P.append(pbox(Vector3(44, 8, 50), mat(Color("#3f6b3a")), Vector3(-24, 73, 0)))   # roof tent
	for ly: float in [34.0, 44.0, 54.0, 64.0]:
		P.append(pbox(Vector3(1.5, 2, 12), k["steel"], Vector3(-62.5, ly, 18)))
	P.append(pbox(Vector3(3, 4, 56), k["steel"], Vector3(68, 32, 0)))
	_lamps(P, k, 66.5, 36, [-20.0, 20.0])
	_lamps(P, k, -62.5, 34, [-24.0, 24.0], Vector3(3, 6, 8), true)
	return { "side": [-60, 16, 29, 49, 31],
		"tops": [[31, 65, 57, 57, 58], [-61, -47, 69, 69, 60], [-1, 17, 69, 69, 60]], "main": 0, "front": 0 }

# pod side: a triangle with a flat bottom and its peak over the axle, corners rounded
static func _pod_side(px: float, segs: int) -> PackedVector2Array:
	return rounded(PackedVector2Array([Vector2(px - 22, 0), Vector2(px + 22, 0), Vector2(px, 24)]),
			6.0, segs * 2, PackedFloat32Array([6.0, 6.0, 7.0]))

# tread stripes across a pod, each trimmed to the side profile so none pokes out
static func _pod_lugs(chassis: Node3D, prof: PackedVector2Array, px: float, lug: Material, z: float, w := POD_W, n := 5) -> void:
	for k in n:
		var lx := px - (n - 1) * 4.0 + k * 8.0
		var lo := INF
		var hi := -INF
		for i in prof.size():   # where the vertical line x = lx crosses the outline
			var a := prof[i]
			var b := prof[(i + 1) % prof.size()]
			if (a.x - lx) * (b.x - lx) <= 0.0 and a.x != b.x:
				var y := lerpf(a.y, b.y, (lx - a.x) / (b.x - a.x))
				lo = minf(lo, y)
				hi = maxf(hi, y)
		if hi - lo > 4.0:
			chassis.add_child(pbox(Vector3(3, hi - lo + 1.0, w + 1.0), lug, Vector3(lx, (lo + hi) * 0.5, z)))

# artwork wheel (detail 2): a tyre with rounded shoulders and tread blocks, a dished
# rim with five spokes and a hub cap on the outer face
func _wheel_hd(chassis: Node3D, x: float, z: float, r: float, w: float, tyre: Material, hub: Material) -> void:
	var c := Vector3(x, r, z)
	var out := signf(z) if z != 0.0 else 1.0
	var sh := minf(3.5, w * 0.2)
	chassis.add_child(pcyl(r, w - sh * 2.0, tyre, c, "z", 48))
	for s: float in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = (r - sh * 2.0) * U; tm.outer_radius = r * U
		tm.rings = 48; tm.ring_segments = 12
		tm.material = tyre
		mi.mesh = tm
		mi.position = (c + Vector3(0, 0, s * (w * 0.5 - sh))) * U
		mi.rotation.x = PI / 2
		chassis.add_child(mi)
	for k in 16:   # tread blocks round the tyre
		var an := TAU * k / 16.0
		var blk := pbox(Vector3(r * 0.22, 1.6, w - sh * 2.0 - 1.0), tyre, c + Vector3(cos(an), sin(an), 0) * (r + 0.3))
		blk.rotation.z = an + PI / 2
		chassis.add_child(blk)
	var face := c + Vector3(0, 0, out * (w * 0.5 - 0.6))
	chassis.add_child(pcyl(r * 0.64, 1.6, hub, face, "z", 40))
	chassis.add_child(pcyl(r * 0.5, 1.8, paint(Color("#15191f"), 0.6), face + Vector3(0, 0, out * 0.2), "z", 40))
	for k in 5:
		var an := TAU * k / 5.0
		var sp := pbox(Vector3(r * 0.46, 2.2, 1.6), hub, face + Vector3(cos(an), sin(an), 0) * r * 0.25 + Vector3(0, 0, out * 0.5))
		sp.rotation.z = an
		chassis.add_child(sp)
	chassis.add_child(pcyl(r * 0.16, 2.6, hub, face + Vector3(0, 0, out * 0.8), "z", 24))

# a wheel on the chassis: tyre plus a painted hub on the outer face
func _wheel(chassis: Node3D, x: float, z: float, r: float, w: float, tyre: Material, hub: Material) -> void:
	if detail > 1:
		_wheel_hd(chassis, x, z, r, w, tyre, hub)
		return
	for layer in 2:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var rr := r if layer == 0 else r * 0.5
		cm.top_radius = rr * U; cm.bottom_radius = rr * U
		cm.height = (w if layer == 0 else w + 2.0) * U
		cm.radial_segments = 14 if detail == 1 else 40; cm.rings = 1
		cm.material = tyre if layer == 0 else hub
		mi.mesh = cm
		mi.position = Vector3(x, r, z) * U
		mi.rotation.x = PI / 2
		chassis.add_child(mi)

# ---------------------------------------------------------------- liveries
# Thin painted panels laid just proud of the body, fitted to each vehicle's layout (the
# flat flanks and the tops its builder returns; see the vehicles above).

# a thin strip lying on a top face t, from x a to x b along it, centred across at z
static func _strip(t: Array, a: float, b: float, z: float, wz: float, m: Material, h := 0.6) -> MeshInstance3D:
	var s := (float(t[3]) - float(t[2])) / (float(t[1]) - float(t[0]))
	var ang := atan(s)
	var xm := (a + b) * 0.5
	var y := float(t[2]) + (xm - float(t[0])) * s
	var p := pbox(Vector3((b - a) / cos(ang), h, wz), m, Vector3(xm, y + h * 0.5 + 0.05, z))
	p.rotation.z = ang
	return p

static func _top_y(t: Array, x: float) -> float:
	return float(t[2]) + (x - float(t[0])) * (float(t[3]) - float(t[2])) / (float(t[1]) - float(t[0]))

static func _top_angle(t: Array) -> float:
	return atan((float(t[3]) - float(t[2])) / (float(t[1]) - float(t[0])))

func _livery(parts_list: Array, look: Dictionary, col: Color, lay: Dictionary) -> void:
	var lv := String(look.get("livery", "none"))
	if lv == "none" or lv == "":
		return
	var ac: Color = look.get("accent", Color("#f4f1ea"))
	var am := finish_paint(ac, "gloss")
	var sd: Array = lay["side"]
	var tops: Array = lay["tops"]
	var mt: Array = tops[int(lay.get("main", 0))]
	var ft: Array = tops[int(lay.get("front", 0))]
	var x0 := float(sd[0])
	var x1 := float(sd[1])
	var y0 := float(sd[2])
	var y1 := float(sd[3])
	var zs := float(sd[4]) + 0.3
	var L := x1 - x0
	var H := y1 - y0
	var xm := (x0 + x1) * 0.5
	match lv:
		"stripes":   # two stripes nose to tail over every top
			for t: Array in tops:
				var w := float(t[4])
				var off := minf(7.5, w * 0.17)
				for z: float in [-off, off]:
					parts_list.append(_strip(t, float(t[0]) + 0.5, float(t[1]) - 0.5, z, minf(7.0, w * 0.14), am))
		"number":   # a roundel with a number on the main top and on both flanks
			var disc := mat(ac)
			var num := mat(col.darkened(0.2) if ac.get_luminance() > 0.5 else Color("#f4f1ea"))
			var tx := (float(mt[0]) + float(mt[1])) * 0.5
			var r := minf(12.0, minf(float(mt[1]) - float(mt[0]), float(mt[4])) * 0.4)
			var rn := _roundel(Vector3(tx, _top_y(mt, tx) + 0.1, 0), "y", r, disc, num)
			rn.rotation.z = _top_angle(mt)
			parts_list.append(rn)
			var door: Array = lay.get("door", [xm, (y0 + y1) * 0.5, minf(6.2, minf(H * 0.42, L * 0.2))])
			for side: float in [1.0, -1.0]:
				parts_list.append(_roundel(Vector3(door[0], door[1], (zs - 0.2) * side), "z" if side > 0 else "-z",
						float(door[2]), disc, num))
		"flash":   # speed lines down both flanks and a pair along the front top
			var th_ := clampf(H / 14.0, 0.6, 1.4)
			for side: float in [1.0, -1.0]:
				for ln: Array in [[0.78, 0.41, 0.75, 3.0], [0.62, 0.46, 0.46, 1.6], [0.42, 0.54, 0.25, 1.0]]:
					parts_list.append(pbox(Vector3(L * ln[0], ln[3] * th_, 0.6), am,
							Vector3(x0 + L * ln[1], y0 + H * ln[2], zs * side)))
			var fl := float(ft[1]) - float(ft[0])
			for z: float in [-1.0, 1.0]:
				parts_list.append(_strip(ft, float(ft[0]) + fl * 0.15, float(ft[1]) - fl * 0.1,
						z * (float(ft[4]) * 0.5 - 5.0), 3.0, am))
		"twotone":   # the upper half of the flanks and the other tops in the accent colour
			for i in tops.size():
				if i != int(lay.get("main", 0)):
					var t: Array = tops[i]
					parts_list.append(_strip(t, float(t[0]), float(t[1]), 0.0, float(t[4]) + 0.6, am))
			for side: float in [1.0, -1.0]:
				parts_list.append(pbox(Vector3(L, H * 0.45, 0.6), am, Vector3(xm, y1 - H * 0.225, zs * side)))
		"checker":   # a chequered band across the front of the front top
			var wht := finish_paint(Color("#f4f1ea"), "gloss")
			var blk := finish_paint(Color("#1d2229"), "gloss")
			var sq := float(ft[4]) / 8.0
			for r in 2:
				var b := float(ft[1]) - 1.0 - r * sq
				for c in 8:
					var z := -float(ft[4]) * 0.5 + (c + 0.5) * sq
					parts_list.append(_strip(ft, b - sq, b, z, sq, wht if (r + c) % 2 == 0 else blk))
		"bolt":   # a lightning bolt along each flank and one on the main top
			for side: float in [1.0, -1.0]:
				for q: PackedVector2Array in _bolt_quads():
					var mq := PackedVector2Array()
					for p in q:   # drawn for a flank x -56..58, y 25.5..34.5: fit it to this one
						mq.append(Vector2(x0 + 2.0 + (p.x + 56.0) / 114.0 * (L - 4.0), y0 + H * (0.1 + (p.y - 25.5) / 9.0 * 0.8)))
					var bp := pprism(mq, 0.6, am)
					bp.position.z = zs * side * U
					parts_list.append(bp)
			var tx := (float(mt[0]) + float(mt[1])) * 0.5
			var s := minf((float(mt[1]) - float(mt[0]) - 4.0) / 32.0, (float(mt[4]) - 6.0) / 18.0)
			var rb := _flat_bolt(am, clampf(s, 0.3, 1.4))
			rb.position = Vector3(tx, _top_y(mt, tx) + 0.4, 0) * U
			rb.rotation.z = _top_angle(mt)
			parts_list.append(rb)
		"glow":   # neon strips along the flanks' edges and down the main top
			var nc: Color = col if String(look.get("finish", "")) == "neon" else Color("#3ff2ff")
			var nm := mat(nc, true)
			nm.emission_enabled = true
			nm.emission = nc
			nm.emission_energy_multiplier = 2.0
			for side: float in [1.0, -1.0]:
				parts_list.append(pbox(Vector3(L, 1.2, 1.2), nm, Vector3(xm, y1 + 0.2, (zs - 0.2) * side)))
				parts_list.append(pbox(Vector3(L - 6.0, 1.6, 1.2), nm, Vector3(xm, y0 + 0.6, (zs + 0.2) * side)))
			parts_list.append(_strip(mt, float(mt[0]) + 1.0, float(mt[1]) - 1.0, 0.0, 1.4, nm, 1.0))

# a round badge with a number (Label3D) on top of it
func _roundel(pos: Vector3, facing: String, r: float, disc: Material, num: Material) -> Node3D:
	var n := Node3D.new()
	n.position = pos * U
	var d := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r * U; cm.bottom_radius = r * U; cm.height = 0.8 * U
	cm.radial_segments = 24 if detail == 1 else 48; cm.rings = 1
	cm.material = disc
	d.mesh = cm
	n.add_child(d)
	var lb := Label3D.new()
	lb.text = "7"
	lb.font = load("res://fonts/Bungee-Regular.ttf")
	lb.font_size = 96
	lb.outline_size = 0
	lb.pixel_size = r * 1.25 * U / 96.0
	lb.modulate = (num as StandardMaterial3D).albedo_color
	lb.shaded = true
	lb.double_sided = false
	n.add_child(lb)
	match facing:   # the badge is built facing up (+y): turn it onto a door
		"y":   # on the deck: reads from behind the car
			lb.basis = Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0))
			lb.position = Vector3(0, 0.5 * U, 0)
		"z":
			d.rotation.x = PI / 2
			lb.position = Vector3(0, 0, 0.5 * U)
		"-z":
			d.rotation.x = PI / 2
			lb.rotation.y = PI
			lb.position = Vector3(0, 0, -0.5 * U)
	return n

# the side bolt as convex quads (pprism fans each profile), x along the car, y up
static func _bolt_quads() -> Array:
	return [
		PackedVector2Array([Vector2(-56, 34.5), Vector2(-6, 34.5), Vector2(-2, 30.5), Vector2(-56, 31.0)]),
		PackedVector2Array([Vector2(-6, 34.5), Vector2(2, 34.5), Vector2(8, 25.5), Vector2(0, 25.5)]),
		PackedVector2Array([Vector2(0, 25.5), Vector2(4, 30.0), Vector2(58, 27.5), Vector2(58, 25.5)]),
	]

# a bolt lying on the roof, pointing forward
func _flat_bolt(m: Material, s := 1.0) -> Node3D:
	var n := Node3D.new()
	for q: PackedVector2Array in [
			PackedVector2Array([Vector2(-24, -9), Vector2(-2, -3), Vector2(-2, 3), Vector2(-24, -5)]),
			PackedVector2Array([Vector2(-6, -3), Vector2(2, -3), Vector2(-2, 5), Vector2(-10, 5)]),
			PackedVector2Array([Vector2(-2, 3), Vector2(8, 5), Vector2(8, 9), Vector2(-2, 5)])]:
		# profile drawn in (x, z): build it as a thin prism then lay it flat
		var sq := PackedVector2Array()
		for v in q:
			sq.append((v + Vector2(8, 0)) * s)   # centred on the origin
		var p := pprism(sq, 0.6, m)
		p.rotation.x = PI / 2
		n.add_child(p)
	return n

# the AI rivals each wear a livery of their own so the field looks like a team grid
static func rival_look(c) -> Dictionary:
	var lv := { "Vesna": "stripes", "Okoro": "number", "Brandt": "flash" }
	var col: Color = c.color
	return { "livery": lv.get(c.name, "none"), "finish": "gloss",
		"accent": Color("#1d2229") if col.get_luminance() > 0.62 else Color("#f4f1ea") }

# looks: the cosmetic look of each human player's car (by player number); the AI rivals
# wear their own fixed liveries (RIVAL_LIVERIES by roster colour)
func setup_cars(race: Race, has_ghost: bool, looks := {}) -> void:
	wind.clear()
	_winds.clear()
	for cn in car_nodes:
		cn["root"].queue_free()
		cn["tether"].queue_free()
	car_nodes.clear()
	if ghost_node:
		ghost_node.queue_free()
		ghost_node = null
	for c in race.cars:
		var lk: Dictionary = looks.get(c.human, {}) if c.human >= 0 else rival_look(c)
		var root := _make_car(c.color, false, lk)
		dyn_root.add_child(root)
		var tm := CylinderMesh.new()
		tm.top_radius = 3.5 * U
		tm.bottom_radius = 3.5 * U
		tm.height = 1.0
		tm.radial_segments = 6
		tm.rings = 1
		tm.material = mat(lk.get("rope", c.color), true)
		var tether := MeshInstance3D.new()
		tether.mesh = tm
		tether.visible = false
		tether.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		dyn_root.add_child(tether)
		var marker: MeshInstance3D = null
		if c.human >= 0:
			marker = cyl(16, 26, c.color, Vector3(0, 120, 0), 0.0, 3)
			marker.set_surface_override_material(0, mat(c.color, true))
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
				ring.set_surface_override_material(0, mat(cols[m], true))
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
			if c.human >= 0:
				_wind_car(c, y, dt)
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
	_update_wind(dt)

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
				_spark(w3(p + Vector2(cos(an), sin(an)) * 16.0, 30.0), Vector3(v.x, 150 + randf() * 250, v.y) * U, 0.4 + randf() * 0.4, _post_bits(j))
		"shake":
			shake = minf(10.0, maxf(shake, e["v"]))

func _post_bits(j: int) -> Color:
	var bits: Array = th.get("post_bits", [COL_KERB, COL_CHALK])
	return bits[j % 2]

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
	var eye := focus + off + jitter
	var look := focus + jitter
	# a cinematic shot takes over, blended in and out of the gameplay view
	var w := _cine_step(dt, snap)
	if w > 0.0:
		var pose := _cine_pose(dt)
		eye = eye.lerp(pose[0], w)
		look = look.lerp(pose[1], w)
		dist = lerpf(dist, eye.distance_to(look), w)
	_cine_fog(w)
	camera.position = eye
	camera.look_at(look, Vector3.UP)
	light.directional_shadow_max_distance = clampf(dist * 2.2, 30.0, 200.0)

# ---------------------------------------------------------------- cinematic shots
# Low-angle camera moves for the moments nobody is steering: the countdown, the finish and
# the results backdrop, and the tutorial's cards and frozen bends. While the player races,
# the camera stays the fairly top-down gameplay view above. main.gd picks the shot each
# frame with cine(); the camera eases between the two, so a shot can start or end anytime.
#   intro   countdown: low behind the car, a slow drift, then a rise into the gameplay view
#           right on GO (timed on the 3.2 s countdown)
#   finish  low chase cam close behind the car, which drives on by itself (a finish, and the
#           results backdrop)
#   win     lower and closer (a race won, a new record, the tutorial done)
#   card    tutorial card waiting for a tap: a showroom orbit round the car
#   freeze  tutorial bend frozen for HOLD / LET GO: low over the car's shoulder at the tower
const CINE_SHOTS := {
	# pitch (deg) from..to, distance (m) from..to, yaw (deg, 0 = in front of the nose,
	# 180 = behind) at the start, yaw speed (deg/s), ease in / out (s), look height (m)
	"intro":  { "pitch": [22.0, 34.0], "dist": [3.4, 4.4], "yaw": 155.0, "spin": 5.0, "in": 0.01, "out": 0.6, "lift": 0.18 },
	"finish": { "pitch": [17.0, 17.0], "dist": [3.6, 3.6], "yaw": 180.0, "spin": 0.0, "chase": 18.0, "in": 1.0, "out": 0.6, "lift": 0.2 },
	"win":    { "pitch": [13.0, 13.0], "dist": [3.1, 3.1], "yaw": 180.0, "spin": 0.0, "chase": 24.0, "in": 0.9, "out": 0.6, "lift": 0.18 },
	"card":   { "pitch": [13.0, 13.0], "dist": [2.6, 2.6], "yaw": 50.0, "spin": 10.0, "in": 1.0, "out": 0.7, "lift": 0.18 },
	"freeze": { "pitch": [20.0, 20.0], "dist": [4.2, 4.2], "yaw": 160.0, "spin": 0.0, "in": 0.55, "out": 0.45, "lift": 0.0 },
}
const INTRO_HOLD := 1.0   # s the intro stays fully low before rising
const INTRO_RISE := 1.8   # s to blend into the gameplay view (GO comes 3.0 s in)

var cine_shot := ""        # current shot ("" = gameplay)
var cine_t := 0.0          # s since the shot began (real time: runs while the tutorial is frozen)
var cine_k := 0.0          # 0 = gameplay view .. 1 = the shot (eased when used)
var cine_car = null        # the Race car the shot frames
var cine_aim = null        # freeze: the tower (prototype space) to keep in frame
var cine_side := Vector2.ZERO  # where the car sits on screen (-1..1 of the half width / height)
var _cine_last := ""       # shot being blended out
var _cine_yaw := 0.0       # world yaw the orbit started from
var _chase_h := 0.0        # chase cam: smoothed heading it trails
var _cine_lift := 0.0      # m the eye is raised to see over the land / a tower (smoothed)

# Picks the shot; call every frame. car = the Race car to frame, aim = a point to look past.
func cine(shot: String, car = null, aim = null) -> void:
	if shot != "":
		cine_car = car
		cine_aim = aim
	if shot == cine_shot:
		return
	if shot != "":
		_cine_last = shot
		cine_t = 0.0
		_cine_yaw = car.h if car else 0.0
		_chase_h = car.vel.angle() if car and car.vel.length() > 50.0 else _cine_yaw
		# a shot that follows another one picks up from where the camera already is
		if cine_shot != "" and car and shot != "intro":
			_cine_yaw = _cine_cur_yaw() - deg_to_rad(CINE_SHOTS[shot]["yaw"])
	cine_shot = shot

# straight back to the gameplay view (menus, a new track)
func cine_reset() -> void:
	cine_shot = ""
	_cine_last = ""
	cine_car = null
	cine_k = 0.0
	_cine_lift = 0.0
	cine_side = Vector2.ZERO
	if env:
		env.fog_enabled = false

func cine_active() -> bool:
	return cine_k > 0.001

func _cine_cur_yaw() -> float:
	var flat := Vector2(camera.position.x, camera.position.z) - Vector2(cine_car.pos.x, cine_car.pos.y) * U
	return flat.angle()

func _cine_step(dt: float, snap: bool) -> float:
	if cine_car == null or not is_instance_valid(camera):
		cine_k = 0.0
		return 0.0
	cine_t += dt
	var key := cine_shot if cine_shot != "" else _cine_last
	if key == "":
		cine_k = 0.0
		return 0.0
	var sh: Dictionary = CINE_SHOTS[key]
	if cine_shot == "intro":
		# scripted on the countdown clock rather than eased
		cine_k = 1.0 - clampf((cine_t - INTRO_HOLD) / INTRO_RISE, 0.0, 1.0)
	elif cine_shot != "":
		cine_k = 1.0 if snap else minf(1.0, cine_k + dt / float(sh["in"]))
	else:
		cine_k = 0.0 if snap else maxf(0.0, cine_k - dt / float(sh["out"]))
	return smoothstep(0.0, 1.0, cine_k)

# dt >= 0: a frame on screen (the lift over obstacles is smoothed); < 0: the raw pose (tests)
func _cine_pose(dt := -1.0) -> Array:
	var key := cine_shot if cine_shot != "" else _cine_last
	var sh: Dictionary = CINE_SHOTS[key]
	var c = cine_car
	var u := clampf(cine_t / (INTRO_HOLD + INTRO_RISE), 0.0, 1.0) if key == "intro" else 0.0
	u = smoothstep(0.0, 1.0, u)
	var pitch := deg_to_rad(lerpf(sh["pitch"][0], sh["pitch"][1], u))
	var d: float = lerpf(sh["dist"][0], sh["dist"][1], u)
	# portrait: the width is all you get, so step back to keep the car whole
	var vps := get_viewport().get_visible_rect().size
	d *= pow(maxf(1.0, vps.y / maxf(1.0, vps.x)), 0.75)
	d *= 1.0 + cine_side.length() * 0.7   # beside the results panel: a wider shot
	var turn := float(sh["spin"]) * cine_t
	if sh.has("chase"):
		# follow the car: behind it along where it is heading (smoothed on screen), a little
		# off to one side for a three-quarter view
		var head: float = c.vel.angle() if c.vel.length() > 50.0 else c.h
		if dt >= 0.0:
			_chase_h = lerp_angle(_chase_h, head, 1.0 - exp(-2.5 * dt))
			head = _chase_h
		_cine_yaw = head
		turn = float(sh["chase"])
	if sh.has("sweep"):
		# swing to and fro in front of the car instead of circling it: the hero side, and
		# the start gantry the car just passed stays behind it
		var amp: float = sh["sweep"]
		turn = amp * sin(turn / amp)
	var yaw := _cine_yaw + deg_to_rad(float(sh["yaw"]) + turn)
	var y: float = (track.height_at(c.last_s) + ROAD_Y + c.air) * U
	var car3 := Vector3(c.pos.x * U, y, c.pos.y * U)
	var look := car3 + Vector3(0, float(sh["lift"]), 0)
	if sh.has("chase"):
		look += Vector3(cos(_cine_yaw), 0, sin(_cine_yaw)) * 0.5   # a little room ahead of the car
	if key == "freeze" and cine_aim != null:
		# over the car's outside shoulder, the tower beyond it: look between the two
		var a: Vector2 = cine_aim
		var to_a: Vector2 = a - c.pos
		look = car3.lerp(Vector3(a.x * U, y, a.y * U), 0.35)
		yaw = to_a.angle() + PI + deg_to_rad(28.0) * (1.0 if to_a.cross(Vector2.from_angle(c.h)) > 0.0 else -1.0)
		d = maxf(d, to_a.length() * U * 1.3)
	var eye := look + Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch)) * d
	# keep the land (hills, road banks, bridges) out of the lens: lift the eye until the
	# sight line clears it
	var lift := 0.0
	for f in [1.0, 0.8, 0.6, 0.45, 0.3]:
		var q := car3.lerp(eye, f)
		var need := _cine_floor(Vector2(q.x, q.z) / U) + 0.3 - q.y
		lift = maxf(lift, need / f)
	if dt >= 0.0:
		# on screen: rise quickly, settle back slowly, so passing a tower is a crane move, not a cut
		_cine_lift = lerpf(_cine_lift, lift, 1.0 - exp(-(7.0 if lift > _cine_lift else 1.2) * dt))
		lift = _cine_lift
	eye.y += lift
	# results backdrop: slide the car out from behind the panel (left in landscape, up in portrait)
	if cine_side != Vector2.ZERO:
		var fwd := (look - eye).normalized()
		var right := fwd.cross(Vector3.UP).normalized()
		var up := right.cross(fwd)
		var half := tan(deg_to_rad(camera.fov) * 0.5) * eye.distance_to(look)
		var vp := get_viewport().get_visible_rect().size
		var asp := vp.x / maxf(1.0, vp.y)
		var shift := -right * cine_side.x * half * asp - up * cine_side.y * half
		eye += shift
		look += shift
	return [eye, look]

# Highest solid thing under a point (prototype space -> world metres): ground or road + rails.
func _cine_floor(p: Vector2) -> float:
	var h := ground_h(p)
	# every road nearby, not just the nearest: a bridge deck above the car's road counts too
	var cx := floori(p.x / TrackData.CELL)
	var cy := floori(p.y / TrackData.CELL)
	for gx in range(cx - 1, cx + 2):
		for gy in range(cy - 1, cy + 2):
			var key := Vector2i(gx, gy)
			if not track._grid.has(key):
				continue
			for i in track._grid[key]:
				var nr: Dictionary = track.seg_near(i, p, {})
				if nr["d"] < TrackData.HW + BANK_OUT:
					var sv: float = track.seg_s0[i] + nr["t"] * track.seg_len[i]
					h = maxf(h, track.height_at(sv) + ROAD_Y + (RAIL_H if nr["d"] > TrackData.HW - 10.0 else 0.0))
	# start gantry posts (the car often stops just past the line)
	var sq := track.point_at(track.start_s)
	var sd: Vector2 = sq["dir"]
	var span := HW + KERB_W + RAIL_W + 14.0
	for side in [1.0, -1.0]:
		if p.distance_squared_to(sq["pos"] + Vector2(-sd.y, sd.x) * span * side) < 45.0 * 45.0:
			h = maxf(h, track.height_at(track.start_s) + 230.0)
	# towers: see over the top rather than film the column
	for k in track.anchors.size():
		var a: TrackData.Anchor = track.anchors[k]
		if p.distance_squared_to(a.pos) < 80.0 * 80.0:
			var top: float = rotor_h[k] if rotor_h.size() == track.anchors.size() and rotor_h[k] > 0.0 \
				else track.arc_level[k] * TrackData.LEVEL_H + TOWER_H
			h = maxf(h, top + 30.0)
	return h * U

# Low shots see the edge of the world: fade the distance into the sky colour.
func _cine_fog(w: float) -> void:
	env.fog_enabled = w > 0.01
	if env.fog_enabled:
		env.fog_light_color = env.background_color
		env.fog_light_energy = 1.0
		env.fog_sun_scatter = 0.0
		env.fog_density = 0.03 * w
		env.fog_sky_affect = 0.0
