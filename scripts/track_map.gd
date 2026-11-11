# 2D drawing of a circuit: used for the track picker thumbnails and the in-race minimap.
extends Control

const TrackData = preload("res://scripts/track.gd")

var track: TrackData
var race = null           # when set, car dots are drawn (minimap)
var bg := false
var mini := false          # menu miniature: thicker road, no start line clutter
var dim := false           # locked card
var ink := false           # drawn on the roadbook paper: the road as an ink outline, towers in ice blue

func set_track(t: TrackData) -> void:
	track = t
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _process(_dt: float) -> void:
	if race != null and visible:
		queue_redraw()

func _draw() -> void:
	if track == null:
		return
	var b := track.bounds
	var pad := 6.0
	var sc := minf((size.x - pad * 2) / b.size.x, (size.y - pad * 2) / b.size.y)
	var off := (size - b.size * sc) * 0.5 - b.position * sc
	if bg:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.075, 0.08, 0.78))
	var pts := PackedVector2Array()
	for p in track.P:
		pts.append(p * sc + off)
	pts.append(pts[0])
	var w := maxf(2.0, TrackData.HW * 2 * sc)
	if mini:
		w = maxf(w, 4.0)
	if dim:
		draw_polyline(pts, Color(0.082, 0.133, 0.18, 0.18) if ink else Color(1, 1, 1, 0.16), w, true)
		return
	if ink:
		_draw_ink(pts, sc, off, w)
		return
	if race == null:
		draw_polyline(pts, Color("#d4452f"), (TrackData.HW * 2 + 22) * sc, true)
	draw_polyline(pts, Color("#5d6570"), w, true)
	for B in track.bridges:
		var seg := PackedVector2Array()
		var i: int = B["from"]
		while true:
			seg.append(track.P[i] * sc + off)
			if i == (int(B["to"]) + 1) % track.n:
				break
			i = (i + 1) % track.n
		draw_polyline(seg, Color("#a07a50"), (TrackData.HW * 2 + 26) * sc)
		draw_polyline(seg, Color("#7d848e"), w)
	for j in track.jumps:
		var p: Vector2 = j["pos"] * sc + off
		var d: Vector2 = j["dir"]
		var n := TrackData.perp(d)
		var hw := (TrackData.HW + 12) * sc
		var gl := TrackData.GAP * sc
		draw_colored_polygon(PackedVector2Array([p + n * hw, p + n * hw + d * gl, p - n * hw + d * gl, p - n * hw]), Color("#06100f"))
	if race == null:
		for a in track.anchors:
			draw_circle(a.pos * sc + off, 2.5, Color("#4fb6ff"))
		var st := track.point_at(track.start_s)
		var n2 := TrackData.perp(st["dir"]) * TrackData.HW * sc
		var sp: Vector2 = st["pos"] * sc + off
		draw_line(sp - n2, sp + n2, Color("#ece6d8"), 3.0)
	else:
		for o in track.obstacles:
			if not o["gone"]:
				draw_rect(Rect2(o["pos"] * sc + off - Vector2(1.5, 1.5), Vector2(3, 3)), Color("#d4452f"))
		var cars: Array = race.cars.duplicate()
		cars.reverse()
		for c in cars:
			draw_circle(c.pos * sc + off, 4.5 if c.human >= 0 else 3.0, c.color)

# the roadbook drawing: the road as two ink edges (bridges drawn over with a thicker deck),
# jump gaps left blank, towers as ice-blue dots, the start line as a dash across
func _draw_ink(pts: PackedVector2Array, sc: float, off: Vector2, w: float) -> void:
	const INK := Color("#15222e")
	const PAPER := Color("#fbf8f1")
	var edge := maxf(1.5, w * 0.16)
	draw_polyline(pts, INK, w + edge * 2.0, true)
	draw_polyline(pts, PAPER, w, true)
	for B in track.bridges:
		var seg := PackedVector2Array()
		var i: int = B["from"]
		while true:
			seg.append(track.P[i] * sc + off)
			if i == (int(B["to"]) + 1) % track.n:
				break
			i = (i + 1) % track.n
		draw_polyline(seg, INK, w + edge * 4.0)
		draw_polyline(seg, PAPER, w + edge * 1.0)
	for j in track.jumps:
		var p: Vector2 = j["pos"] * sc + off
		var d: Vector2 = j["dir"]
		var n := TrackData.perp(d)
		var hw := (TrackData.HW + 12) * sc
		var gl := TrackData.GAP * sc
		# the gap of a jump: the road stops, two short ink lips either side
		draw_colored_polygon(PackedVector2Array([p + n * hw, p + n * hw + d * gl, p - n * hw + d * gl, p - n * hw]), PAPER)
		draw_line(p + n * hw, p - n * hw, INK, edge)
		draw_line(p + n * hw + d * gl, p - n * hw + d * gl, INK, edge)
	var tr := clampf(w * 0.24, 2.5, 7.0)
	for a in track.anchors:
		draw_circle(a.pos * sc + off, tr, INK)
		draw_circle(a.pos * sc + off, tr * 0.62, Color("#4fb6ff"))
	var st := track.point_at(track.start_s)
	var n2 := TrackData.perp(st["dir"]) * (TrackData.HW * sc + edge)
	var sp: Vector2 = st["pos"] * sc + off
	draw_line(sp - n2, sp + n2, INK, maxf(3.0, edge * 1.6))
