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
const PITCH := deg_to_rad(56.0)

const COL_INFIELD := Color("#17393b")
const COL_DOTS := Color("#20494b")
const COL_ASPHALT := Color("#41464f")
const COL_CHALK := Color("#ece6d8")
const COL_KERB := Color("#d4452f")
const COL_RAIL := Color("#d9d2c2")
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

var tower_nodes := {}      # home index -> {spinner, rings: [MeshInstance3D, MeshInstance3D], y}
var car_nodes: Array = []  # per car: {root, body, tether, marker}
var ghost_node: Node3D
var post_nodes: Array = []
var gem_nodes: Array = []

# effects
var parts: Array = []      # {p: Vector3, v: Vector3, life, col}
var parts_mm: MultiMeshInstance3D
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
	light.light_energy = 1.15
	light.shadow_enabled = true
	light.directional_shadow_max_distance = 60.0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(light)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COL_INFIELD.darkened(0.35)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#b9c9d6")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
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
	_build_jumps()
	_build_start()
	_build_towers()
	_build_posts()
	_build_gems()
	_build_fx()

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
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = fract(wp.xz / 0.8);
	float d = step(g.x, 0.05) * step(g.y, 0.05);
	ALBEDO = mix(base_col, dot_col, d);
	ROUGHNESS = 1.0;
}
"""
	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.set_shader_parameter("base_col", COL_INFIELD)
	sm.set_shader_parameter("dot_col", COL_DOTS)
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
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, hint: Vector3) -> void:
		var nrm := (b - a).cross(d - a)
		if nrm.length_squared() < 1e-12:
			nrm = (c - b).cross(a - b)
		nrm = nrm.normalized()
		if nrm.dot(hint) < 0.0:
			nrm = -nrm
		st.set_color(col)
		st.set_normal(nrm)
		for v in [a, b, c, a, c, d]:
			st.add_vertex(v)

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
		road.quad(P.call(ca, na, HW, ha), P.call(cb, nb, HW, hb), P.call(cb, nb, -HW, hb), P.call(ca, na, -HW, ha), COL_ASPHALT, up)
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
	mi.material_override = _vert_mat
	static_root.add_child(mi)

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

func _build_towers() -> void:
	for idx in track.anchors.size():
		var a: TrackData.Anchor = track.anchors[idx]
		if a.home != idx:
			continue
		var t := Node3D.new()
		t.position = w3(a.pos, 0.0)
		t.add_child(cyl(30, TOWER_H, COL_TOWER, Vector3(0, TOWER_H / 2.0, 0), 38))
		t.add_child(cyl(30, 8, COL_TOWER.lightened(0.15), Vector3(0, TOWER_H + 4, 0)))
		var spinner := Node3D.new()
		spinner.position = Vector3(0, TOWER_H + 8, 0) * U
		spinner.add_child(cyl(25, 6, COL_POST, Vector3(0, 3, 0)))
		for k in 3:
			var arm := Node3D.new()
			arm.rotation.y = TAU * k / 3.0
			arm.add_child(box(Vector3(22, 4, 6), Color("#3a2a08"), Vector3(11, 7, 0)))
			spinner.add_child(arm)
		spinner.add_child(cyl(7, 10, COL_CHALK, Vector3(0, 8, 0)))
		t.add_child(spinner)
		var rings: Array = []
		for m in 2:
			var tm := TorusMesh.new()
			tm.inner_radius = (40.0 + m * 10.0) * U
			tm.outer_radius = (45.0 + m * 10.0) * U
			tm.rings = 32
			tm.ring_segments = 6
			var ri := MeshInstance3D.new()
			ri.mesh = tm
			ri.position = Vector3(0, TOWER_H + 8, 0) * U
			ri.visible = false
			ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			t.add_child(ri)
			rings.append(ri)
		static_root.add_child(t)
		tower_nodes[idx] = { "spinner": spinner, "rings": rings }

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
	parts_mm = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var pbox := BoxMesh.new()
	pbox.size = Vector3(7, 7, 7) * U
	var pm := StandardMaterial3D.new()
	pm.vertex_color_use_as_albedo = true
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pbox.material = pm
	mm.mesh = pbox
	mm.instance_count = 400
	mm.visible_instance_count = 0
	parts_mm.multimesh = mm
	parts_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dyn_root.add_child(parts_mm)

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
func _make_car(col: Color, ghost := false) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	var bc := col
	var parts_list: Array = []
	if ghost:
		bc = Color(COL_CHALK, 0.35)
		parts_list.append(box(Vector3(130, 26, 74), bc, Vector3(0, 24, 0)))
		parts_list.append(box(Vector3(46, 20, 56), Color(COL_INFIELD, 0.35), Vector3(-4, 46, 0)))
	else:
		parts_list.append(box(Vector3(130, 24, 74), bc, Vector3(0, 24, 0)))
		parts_list.append(box(Vector3(30, 8, 80), bc.darkened(0.2), Vector3(-58, 40, 0)))  # rear wing
		parts_list.append(box(Vector3(46, 20, 54), Color("#1c2026"), Vector3(-4, 44, 0)))  # cabin
		parts_list.append(box(Vector3(52, 2, 12), Color(1, 1, 1, 1), Vector3(-36, 37, 0)))  # stripe
		parts_list.append(box(Vector3(4, 6, 14), Color("#fff4c8"), Vector3(65, 26, 24)))
		parts_list.append(box(Vector3(4, 6, 14), Color("#fff4c8"), Vector3(65, 26, -24)))
		for wx in [-40.0, 40.0]:
			for wz in [-38.0, 38.0]:
				var w := cyl(14, 12, Color("#111111"), Vector3(wx, 14, wz), -1.0, 12)
				w.rotation.x = PI / 2
				parts_list.append(w)
	for p in parts_list:
		if ghost:
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(p)
	root.set_meta("body", body)
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
		car_nodes.append({ "root": root, "body": root.get_meta("body"), "tether": tether, "marker": marker, "roll": 0.0 })
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
		var home: int = track.anchors[idx].home
		var cols: Array = aims[idx]
		for m in mini(2, cols.size()):
			var ring: MeshInstance3D = tower_nodes[home]["rings"][m]
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
			# lean out of the swing while hooked
			var want_roll := 0.0
			if c.hook >= 0:
				want_roll = -c.turn_sign * 0.10
			elif c.slip > 0.3:
				want_roll = -signf(c.turn_sign) * 0.05 * c.slip
			cn["roll"] = lerpf(cn["roll"], want_roll, minf(1.0, dt * 8.0))
			cn["body"].rotation.x = cn["roll"]
			var pitch := 0.0
			if c.air > 0.0 and c.air_max > 0.0:
				pitch = lerpf(0.18, -0.15, 1.0 - c.air / c.air_max)
			cn["body"].rotation.z = pitch
			if cn["marker"]:
				cn["marker"].visible = phase != "results"
				cn["marker"].position.y = (120.0 + sin(fx_time * 4.0) * 6.0) * U
			# tether: tower top to car
			var tether: MeshInstance3D = cn["tether"]
			if c.hook >= 0:
				var a: TrackData.Anchor = track.anchors[c.hook]
				var dir: Vector2 = (c.pos - a.pos).normalized()
				var from := w3(a.pos + dir * 20.0, TOWER_H + 12.0)
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
	if parts.size() >= 400:
		parts.pop_front()
	parts.append({ "p": p, "v": v, "life": life, "col": col })

func _update_fx(dt: float) -> void:
	if skid_mat:
		skid_mat.set_shader_parameter("now", fx_time)
	if not parts_mm:
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
	var mm := parts_mm.multimesh
	mm.visible_instance_count = parts.size()
	for k in parts.size():
		var p: Dictionary = parts[k]
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * minf(1.0, p["life"] * 2.5)), p["p"]))
		mm.set_instance_color(k, p["col"])
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
	if phase == "menu" or race == null:
		target = Vector3(b.get_center().x, 0, b.get_center().y)
		vis = maxf(b.size.y, b.size.x / aspect) * 0.95
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
		var base := 1450.0 * vp.y / short  # visible height when the short side shows 1450 units
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
	camera.position = focus + off + jitter
	camera.look_at(focus + jitter, Vector3.UP)
	light.directional_shadow_max_distance = clampf(dist * 2.2, 30.0, 200.0)
