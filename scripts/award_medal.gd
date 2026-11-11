# One award's medallion: a dark disc whose ring draws itself round, with a little scene that
# tells what was done (three laps ticked off, gems falling into a basket, the car swinging
# round a tower for the Pivot medal...). play() runs it from the start (about two seconds);
# otherwise it rests on its last frame. Everything is drawn in a 100 x 100 box, centre 50,50,
# scaled to the control. `landed` fires when the scene is done and the shine sweeps over it.
extends Control

const F_DISPLAY: Font = preload("res://fonts/Bungee-Regular.ttf")
const F_BODY: Font = preload("res://fonts/ChakraPetch-Bold.ttf")

const AMBER := Color("#f2b134")
const FG := Color("#f3efe6")
const MUTED := Color("#9fb3b0")
const TEAL := Color("#5fe0d0")
const GREEN := Color("#5fd38d")
const BRONZE := Color("#c98a55")
const SILVER := Color("#c9d3d6")
const GOLD := Color("#f2c84a")
const INK := Color("#1a1408")
const DISC := Color("#10283a")
const DISC2 := Color("#0a1a26")
const WORLD := { "snow": Color("#9fe3ff"), "forest": Color("#9ad13b"), "sand": Color("#f2b134"), "rock": Color("#ff8a4c") }

# when each scene is done (the shine sweeps then); the whole show lasts that plus SETTLE
const FINISH := { "clean_laps": 1.45, "streak10": 1.45, "streak25": 1.6, "no_posts": 1.65, "all_gems": 1.5,
	"first_win": 1.35, "runaway": 1.4, "first_pivot": 1.6, "golds10": 1.7, "every_track": 1.7, "dailies7": 1.6,
	"records25": 1.55, "world_snow": 1.6, "world_forest": 1.6, "world_sand": 1.6, "world_rock": 1.6 }
const SETTLE := 0.6

signal landed

var id := "":
	set(v):
		id = v
		queue_redraw()
var t := 99.0
var playing := false
var _landed := true
var _xf := Transform2D()
var _s := 1.0   # pixels per medallion unit

static func accent(award: String) -> Color:
	if award.begins_with("world_"):
		return WORLD.get(award.substr(6), AMBER)
	if award in ["clean_laps", "streak10", "streak25", "no_posts", "all_gems", "first_pivot"]:
		return TEAL
	return AMBER

static func duration(award: String) -> float:
	return float(FINISH.get(award, 1.6)) + SETTLE

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	set_process(playing)

# run the show from the start
func play() -> void:
	t = 0.0
	playing = true
	_landed = false
	set_process(true)
	queue_redraw()

# jump to the last frame
func rest() -> void:
	t = 99.0
	playing = false
	_landed = true
	set_process(false)
	queue_redraw()

func _process(dt: float) -> void:
	t += dt
	if not _landed and t >= float(FINISH.get(id, 1.6)):
		_landed = true
		landed.emit()
	if t >= duration(id) + 1.0 and not _waves():
		playing = false
		set_process(false)
	queue_redraw()

# scenes that keep moving gently after the show (a flag, falling snow...)
func _waves() -> bool:
	return id in ["first_win", "every_track", "world_snow", "world_sand", "world_rock"] and is_visible_in_tree()

# ---------------------------------------------------------------- transform helpers
func _apply() -> void:
	draw_set_transform_matrix(_xf)

func _move(x: float, y: float) -> void:
	_xf = _xf.translated_local(Vector2(x, y))
	_apply()

func _turn(a: float) -> void:
	_xf = _xf.rotated_local(a)
	_apply()

func _grow(k: float) -> void:
	_xf = _xf.scaled_local(Vector2(k, k))
	_apply()

func _put(m: Transform2D) -> void:
	_xf = m
	_apply()

# ---------------------------------------------------------------- easing
static func _seg(x: float, a: float, b: float) -> float:
	return clampf((x - a) / (b - a), 0.0, 1.0)

static func _out_back(x: float) -> float:
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(x - 1.0, 3.0) + c * pow(x - 1.0, 2.0)

static func _out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

static func _in_out(x: float) -> float:
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0

# ---------------------------------------------------------------- shapes
func _disc(p: Vector2, r: float, col: Color) -> void:
	if r > 0.01:
		draw_circle(p, r, col, true, -1.0, true)

func _arc(p: Vector2, r: float, a0: float, a1: float, col: Color, w: float) -> void:
	if absf(a1 - a0) > 0.001 and r > 0.01:
		draw_arc(p, r, a0, a1, maxi(6, int(absf(a1 - a0) * 10.0)), col, w, true)

func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, col, w, true)

func _poly(pts: PackedVector2Array, col: Color) -> void:
	if pts.size() >= 3:
		draw_colored_polygon(pts, col)

func _rrect(x: float, y: float, w: float, h: float, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var cs := [Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r), Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
	for k in 4:
		for j in 4:
			var a := -PI / 2.0 + (k + j / 3.0) * PI / 2.0
			pts.append(cs[k] + Vector2.from_angle(a) * r)
	_poly(pts, col)

static func _circle_pts(c: Vector2, r: float, n := 40) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		pts.append(c + Vector2.from_angle(TAU * k / n) * r)
	return pts

static func _quad(p0: Vector2, c: Vector2, p1: Vector2, n := 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in range(1, n + 1):
		var u := float(k) / n
		pts.append(p0 * (1 - u) * (1 - u) + c * 2.0 * u * (1 - u) + p1 * u * u)
	return pts

# a polygon in medallion space cut to the disc
func _fill_in_disc(pts: PackedVector2Array, col: Color) -> void:
	for part in Geometry2D.intersect_polygons(pts, _circle_pts(Vector2(50, 50), 42.5, 48)):
		_poly(part, col)

# centred text, crisp at any size: drawn unscaled at the right pixel size
func _text(txt: String, p: Vector2, sz: float, col: Color, font: Font = F_DISPLAY) -> void:
	var sc := _xf.get_scale().x
	var fs := int(round(sz * sc))
	if fs < 2:
		return
	var keep := _xf
	_put(Transform2D(_xf.get_rotation(), Vector2.ONE, 0.0, _xf * p))
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := (font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	draw_string(font, Vector2(-w * 0.5, base), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	_put(keep)

func _label(txt: String, x: float, y: float, sz: float, col: Color, at: float) -> void:
	var k := _out_back(_seg(t, at, at + 0.3))
	if k <= 0.01:
		return
	var keep := _xf
	_move(x, y)
	_grow(k)
	_text(txt, Vector2.ZERO, sz, col)
	_put(keep)

func _car(x: float, y: float, ang: float, col := AMBER, s := 1.0) -> void:
	var keep := _xf
	_move(x, y)
	_turn(ang)
	_grow(s)
	_rrect(-5, -3, 10, 6, 2, col)
	_rrect(0.5, -2.2, 3, 4.4, 1, Color(0.04, 0.1, 0.15, 0.75))
	_put(keep)

func _tower(x: float, y: float, col := FG) -> void:
	_disc(Vector2(x, y), 3.4, col)
	_arc(Vector2(x, y), 6, 0, TAU, Color(col, 0.35), 1.0)

func _check(x: float, y: float, s: float, p: float, col: Color, w := 2.6) -> void:
	if p <= 0.0:
		return
	var a := Vector2(x - s, y)
	var b := Vector2(x - s * 0.3, y + s * 0.7)
	var c := Vector2(x + s, y - s * 0.7)
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	var d := p * (l1 + l2)
	var pts := PackedVector2Array([a])
	if d <= l1:
		pts.append(a.lerp(b, d / l1))
	else:
		pts.append(b)
		pts.append(b.lerp(c, (d - l1) / l2))
	draw_polyline(pts, col, w, true)

func _gem(x: float, y: float, s: float, col: Color) -> void:
	_poly(PackedVector2Array([Vector2(x, y - s), Vector2(x + s * 0.8, y - s * 0.2), Vector2(x, y + s), Vector2(x - s * 0.8, y - s * 0.2)]), col)
	_poly(PackedVector2Array([Vector2(x, y - s), Vector2(x + s * 0.8, y - s * 0.2), Vector2(x, y - s * 0.1)]), Color(1, 1, 1, 0.45))

func _medal(x: float, y: float, r: float, col: Color, letter := "") -> void:
	if r <= 0.05:
		return
	_disc(Vector2(x, y), r, col)
	_arc(Vector2(x, y), r * 0.72, 0, TAU, Color(INK, 0.35), 1.0)
	if letter != "":
		_text(letter, Vector2(x, y + 0.5), r * 1.1, INK)

# ---------------------------------------------------------------- shared frame and finish
func _frame(acc: Color) -> bool:
	var k := _out_back(_seg(t, 0.0, 0.35))
	if k <= 0.01:
		return false
	var keep := _xf
	_move(50, 50)
	_grow(k)
	_move(-50, -50)
	_disc(Vector2(50, 50), 44, DISC2)
	_disc(Vector2(50, 46), 36, Color(DISC, 0.85))
	var r := _seg(t, 0.1, 0.5)
	_arc(Vector2(50, 50), 44, -PI / 2, -PI / 2 + TAU * r, acc, 3.2)
	_arc(Vector2(50, 50), 39, 0, TAU, Color(FG, 0.12), 1.0)
	_put(keep)
	return true

func _finish(acc: Color, at: float) -> void:
	var s := _seg(t, at, at + 0.45)
	if s > 0.0 and s < 1.0:   # a light sweep across the disc
		var x := -20.0 + s * 140.0
		var rect := PackedVector2Array()
		for p in [Vector2(x - 14, -20), Vector2(x + 14, -20), Vector2(x + 14, 120), Vector2(x - 14, 120)]:
			rect.append(Vector2(50, 50) + (p - Vector2(50, 50)).rotated(-0.5))
		_fill_in_disc(rect, Color(1, 1, 1, 0.22))
	var p2 := _seg(t, at, at + 0.6)
	if p2 > 0.0 and p2 < 1.0:   # and a ring that widens and fades
		_arc(Vector2(50, 50), 44 + p2 * 10, 0, TAU, Color(acc, 1.0 - p2), 2.0)

func _sparks(at: float, col: Color, n := 10, turn0 := 1.0) -> void:
	var p := _seg(t, at, at + 0.7)
	if p <= 0.0 or p >= 1.0:
		return
	for i in n:
		var a := float(i) / n * TAU + turn0
		var d := 8.0 + _out_cubic(p) * (22.0 + (i % 3) * 5.0)
		_disc(Vector2(50, 50) + Vector2.from_angle(a) * d, 1.6 * (1.0 - p) + 0.4, Color(col, 1.0 - p))

# ---------------------------------------------------------------- draw
func _draw() -> void:
	if id == "":
		return
	var side := minf(size.x, size.y)
	_s = side / 100.0
	var base := Transform2D(0.0, Vector2(_s, _s), 0.0, (size - Vector2(side, side)) * 0.5)
	_put(base)
	var acc := accent(id)
	if not _frame(acc):
		return
	var at: float = FINISH.get(id, 1.6)
	match id:
		"clean_laps": _clean_laps(acc)
		"streak10": _streak10(acc)
		"streak25": _streak25(acc)
		"no_posts": _no_posts(acc)
		"all_gems": _all_gems(acc)
		"first_win": _first_win(acc)
		"runaway": _runaway(acc)
		"first_pivot": _first_pivot(acc)
		"golds10": _golds10(acc)
		"every_track": _every_track(acc)
		"dailies7": _dailies7(acc)
		"records25": _records25(acc)
		_:
			if id.begins_with("world_"):
				_world(id.substr(6), acc)
	_put(base)
	_finish(acc, at)
	draw_set_transform_matrix(Transform2D())

# three lap loops drawn one after the other, each ticked off
func _clean_laps(acc: Color) -> void:
	for i in 3:
		var x := 28.0 + i * 22.0
		var p := _in_out(_seg(t, 0.35 + i * 0.32, 0.6 + i * 0.32))
		if p > 0.0:
			var pts := PackedVector2Array()
			var n := maxi(2, int(40 * p))
			for k in n + 1:
				var a := -PI / 2 + TAU * p * k / n
				pts.append(Vector2(x + cos(a) * 9, 46 + sin(a) * 13))
			draw_polyline(pts, acc if p >= 1.0 else FG, 2.4, true)
			if p < 1.0:
				var a2 := -PI / 2 + TAU * p
				_car(x + cos(a2) * 9, 46 + sin(a2) * 13, TAU * p, AMBER, 0.6)
		_check(x, 66, 3.5, _seg(t, 0.6 + i * 0.32, 0.75 + i * 0.32), acc)

# a snaking line of ten chevrons that light up as the car runs through them
func _streak_pt(u: float) -> Vector2:
	return Vector2(16 + u * 68, 52 + sin(u * TAU * 1.5) * 12)

func _streak10(acc: Color) -> void:
	for i in 10:
		var u := (i + 0.5) / 10.0
		var p := _streak_pt(u)
		var on := _seg(t, 0.4 + i * 0.09, 0.45 + i * 0.09)
		var keep := _xf
		_move(p.x, p.y)
		_turn((_streak_pt(u + 0.01) - p).angle())
		if on > 0.0 and on < 1.0:
			_grow(1.4)
		draw_polyline(PackedVector2Array([Vector2(-2.5, -3.5), Vector2(1.5, 0), Vector2(-2.5, 3.5)]), acc if on >= 1.0 else Color(FG, 0.25), 2.2, true)
		_put(keep)
	var u2 := clampf(_seg(t, 0.35, 1.35) * 1.02, 0.0, 1.0)
	if t < 1.4:
		var c := _streak_pt(u2)
		_car(c.x, c.y, (_streak_pt(minf(1.0, u2 + 0.01)) - c).angle(), AMBER, 0.75)
	_label("x10", 50, 28, 12, FG, 1.3)

# 25 ticks fill the dial clockwise, then the number lands
func _streak25(acc: Color) -> void:
	for i in 25:
		var a := -PI / 2 + i / 25.0 * TAU
		var on := _seg(t, 0.35 + i * 0.045, 0.4 + i * 0.045)
		var r2 := 34.0 + (3.0 if on > 0.0 and on < 1.0 else 0.0)
		_line(Vector2(50, 50) + Vector2.from_angle(a) * 28, Vector2(50, 50) + Vector2.from_angle(a) * r2, acc if on > 0.0 else Color(FG, 0.18), 3.0 if on > 0.0 else 2.0)
	_label("25", 50, 50, 20, FG, 1.5)
	_sparks(1.5, acc, 12, 0.3)

# the car slaloms between three posts; each wobbles as it is passed, none falls; a shield closes
func _slalom(u: float) -> Vector2:
	return Vector2(18 + u * 64, 52 - sin(u * TAU * 1.5 + 0.2) * 14)

func _no_posts(acc: Color) -> void:
	var u := _seg(t, 0.35, 1.35)
	var posts := [Vector2(34, 40), Vector2(50, 62), Vector2(66, 40)]
	for i in 3:
		var near := maxf(0.0, 1.0 - absf(u - (i + 0.5) / 3.0) * 8.0)
		var keep := _xf
		_move(posts[i].x, posts[i].y + 6)
		_turn(sin(t * 30.0) * 0.18 * near)
		_rrect(-2.5, -12, 5, 12, 1.5, AMBER)
		draw_rect(Rect2(-2.5, -8, 5, 2), INK)
		_put(keep)
	if u < 1.0:
		var p := _slalom(u)
		_car(p.x, p.y, (_slalom(minf(1.0, u + 0.01)) - p).angle(), FG, 0.75)
	var s := _out_back(_seg(t, 1.35, 1.65))
	if s > 0.01:
		var keep2 := _xf
		_move(50, 50)
		_grow(s)
		var pts := PackedVector2Array([Vector2(0, -16)])
		pts.append_array(_quad(Vector2(0, -16), Vector2(12, -12), Vector2(14, -10)))
		pts.append_array(_quad(Vector2(14, -10), Vector2(13, 8), Vector2(0, 17)))
		pts.append_array(_quad(Vector2(0, 17), Vector2(-13, 8), Vector2(-14, -10)))
		pts.append_array(_quad(Vector2(-14, -10), Vector2(-12, -12), Vector2(0, -16.01), 7))
		_poly(pts, acc)
		_put(keep2)
		_check(50, 50, 6, _seg(t, 1.5, 1.7), INK)

# gems fall one by one into a basket that squashes as each lands
func _all_gems(acc: Color) -> void:
	var cols := [TEAL, Color("#c78bff"), AMBER, Color("#ff7a8a"), TEAL]
	var squash := 0.0
	for i in 5:
		var a := 0.35 + i * 0.17
		var p := _seg(t, a, a + 0.3)
		var x := 50.0 + (i - 2) * 5.5
		var y := 18.0 + 40.0 * p * p
		if p > 0.0:
			_gem(x, minf(y, 56.0 - (i % 2) * 3.0), 5, cols[i])
		if p >= 1.0:
			squash = maxf(squash, 1.0 - _seg(t, a + 0.3, a + 0.45))
	var keep := _xf
	_move(50, 70)
	_xf = _xf.scaled_local(Vector2(1.0 + squash * 0.12, 1.0 - squash * 0.12))
	_apply()
	_poly(PackedVector2Array([Vector2(-17, -10), Vector2(17, -10), Vector2(12, 8), Vector2(-12, 8)]), Color("#7a5634"))
	for i in [-1, 0, 1]:
		_line(Vector2(-15.5, -3 + i * 5), Vector2(15.5, -3 + i * 5), Color("#5a3d22"), 1.4)
	_put(keep)
	_sparks(1.3, acc, 10, 0.6)

# a chequered flag unfurls on its pole and waves, then a P1 disc
func _first_win(acc: Color) -> void:
	var p := _out_cubic(_seg(t, 0.35, 0.9))
	_line(Vector2(34, 76), Vector2(34, 76 - 52 * _out_cubic(_seg(t, 0.25, 0.55))), FG, 2.4)
	var w := 34.0 * p
	if w > 0.5:
		for i in 6:
			for j in 4:
				var x0 := 35.0 + i / 6.0 * w
				var wave := sin(t * 7.0 - i * 0.9) * 2.2 * (i / 6.0)
				draw_rect(Rect2(x0, 26 + j / 4.0 * 22 + wave, w / 6.0 + 0.4, 22 / 4.0 + 0.4), FG if (i + j) % 2 else Color("#16222c"))
	_medal(70, 66, 10 * _out_back(_seg(t, 1.0, 1.3)), acc, "1")

# two cars side by side; ours pulls away and the gap opens to +3 s
func _runaway(_acc: Color) -> void:
	var u := _in_out(_seg(t, 0.35, 1.25))
	_line(Vector2(14, 44), Vector2(86, 44), Color(FG, 0.15), 8)
	_line(Vector2(14, 60), Vector2(86, 60), Color(FG, 0.15), 8)
	var xa := 30.0 + u * 40.0
	var xb := 30.0 + u * 6.0
	for i in range(1, 5):
		draw_rect(Rect2(xa - 6 - i * 6, 43, 4, 2), Color(AMBER, (0.5 - i * 0.1) * (1.0 if u < 1.0 else 0.3)))
	_car(xa, 44, 0, AMBER, 1.1)
	_car(xb, 60, 0, SILVER, 1.1)
	var b := _seg(t, 1.1, 1.3)
	if b > 0.0:
		draw_polyline(PackedVector2Array([Vector2(xb + 6, 70), Vector2(xb + 6, 73), Vector2(xa + 5, 73), Vector2(xa + 5, 70)]), Color(GREEN, b), 1.6, true)
	_label("+3s", 53, 30, 12, GREEN, 1.2)

# the car swings once round a tower on its rope, lets go, and the Pivot medal lands
func _first_pivot(acc: Color) -> void:
	var sw := _seg(t, 0.35, 1.2)
	var r := 22.0
	_tower(50, 50)
	if sw < 1.0:
		var a := -PI / 2 + sw * TAU * 1.1
		var p := Vector2(50, 50) + Vector2.from_angle(a) * r
		_line(Vector2(50, 50), p, acc, 1.4)
		_arc(Vector2(50, 50), r, a - 1.2, a, Color(acc, 0.35), 3.0)
		_car(p.x, p.y, a + PI / 2, AMBER, 0.85)
	else:
		var f := _seg(t, 1.2, 1.45)
		var a1 := -PI / 2 + TAU * 1.1
		if f < 1.0:
			var p2 := Vector2(50, 50) + Vector2.from_angle(a1) * r + Vector2(f * 40, f * 10)
			_car(p2.x, p2.y, a1 + PI / 2, AMBER, 0.85)
	var m := _out_back(_seg(t, 1.25, 1.55))
	if m > 0.01:
		var keep := _xf
		_move(50, 50)
		_grow(m)
		_medal(0, 0, 16, acc, "P")
		_put(keep)
	_sparks(1.3, acc, 12, 0.2)

# ten gold medals drop and stack into a little pile
func _golds10(acc: Color) -> void:
	var rows: Array[int] = [0, 0, 0, 0, 1, 1, 1, 2, 2, 3]
	var in_row: Array[int] = [0, 1, 2, 3, 0, 1, 2, 0, 1, 0]
	var n_row: Array[int] = [4, 3, 2, 1]
	for i in 10:
		var a := 0.35 + i * 0.11
		var p := _seg(t, a, a + 0.22)
		if p <= 0.0:
			continue
		var row: int = rows[i]
		var x: float = 50.0 + (in_row[i] - (n_row[row] - 1) / 2.0) * 13.0
		var y1 := 72.0 - row * 11.0
		_medal(x, 10.0 + (y1 - 10.0) * p * p, 6, acc)
	_label("10", 50, 24, 12, FG, 1.6)

# a medal pin pops round a globe for each of the 17 tracks
func _every_track(_acc: Color) -> void:
	var g := _seg(t, 0.25, 0.5)
	var c := Color(FG, 0.3)
	if g > 0.0:
		_arc(Vector2(50, 50), 22 * g, 0, TAU, c, 1.2)
		var pts := PackedVector2Array()
		for k in 41:
			var a := TAU * k / 40.0
			pts.append(Vector2(50 + cos(a) * 9 * g, 50 + sin(a) * 22 * g))
		draw_polyline(pts, c, 1.2, true)
		_line(Vector2(28, 50), Vector2(28 + 44 * g, 50), c, 1.2)
	var keep := _xf
	_move(50, 50)
	_turn(t * 0.6)
	var cols := [BRONZE, SILVER, AMBER, TEAL]
	for i in 17:
		var p := _out_back(_seg(t, 0.45 + i * 0.065, 0.6 + i * 0.065))
		if p > 0.0:
			_disc(Vector2.from_angle(i / 17.0 * TAU) * 31, 2.8 * p, cols[i % 4])
	_put(keep)
	_label("17/17", 50, 50, 10, FG, 1.6)

# a week strip; each day gets stamped in turn
func _dailies7(acc: Color) -> void:
	_rrect(15, 38, 70, 26, 4, Color(FG, 0.08))
	var days := ["M", "T", "W", "T", "F", "S", "S"]
	for i in 7:
		var x := 20.0 + i * 10.0
		_text(days[i], Vector2(x, 43), 6, MUTED, F_BODY)
		var p := _out_back(_seg(t, 0.4 + i * 0.13, 0.55 + i * 0.13))
		if p > 0.0:
			_disc(Vector2(x, 55), 3.8 * p, acc)
	_label("7", 50, 26, 13, FG, 1.4)
	_check(50, 76, 5, _seg(t, 1.45, 1.65), acc)

# a stopwatch: the hand sweeps fast then snaps, and a green 25 stamp lands
func _records25(_acc: Color) -> void:
	var c := Vector2(50, 54)
	_arc(c, 22, 0, TAU, FG, 2.4)
	_rrect(46, 27, 8, 5, 1.5, FG)
	for i in 12:
		var d := Vector2.from_angle(i / 12.0 * TAU)
		_line(c + d * 18, c + d * 20, FG, 1.0)
	var s := _seg(t, 0.35, 1.2)
	var a := -PI / 2 + _out_cubic(s) * TAU * 3.2
	if s >= 1.0:
		a += sin((t - 1.2) * 40.0) * 0.08 * maxf(0.0, 1.0 - (t - 1.2) * 4.0)
	_line(c, c + Vector2.from_angle(a) * 16, AMBER, 2.2)
	_disc(c, 2.4, AMBER)
	var k := _seg(t, 1.25, 1.45)
	if k > 0.0:
		var keep := _xf
		_move(64, 70)
		_turn(-0.25)
		_grow(1.8 - 0.8 * _out_cubic(k))
		_rrect(-11, -6, 22, 12, 2, Color(GREEN, k))
		_text("25", Vector2(0, 0.5), 8, Color(INK, k))
		_put(keep)

# ---------------------------------------------------------------- world champions
func _world(theme: String, acc: Color) -> void:
	match theme:
		"snow": _snow(acc)
		"forest": _forest(acc)
		"sand": _sand(acc)
		"rock": _rock(acc)
	# a laurel closes round the scene, five leaves a side
	for side in [-1.0, 1.0]:
		for i in 5:
			var p := _out_back(_seg(t, 1.1 + i * 0.07, 1.3 + i * 0.07))
			if p <= 0.01:
				continue
			var a: float = PI / 2 + side * (0.5 + i * 0.42)
			var keep := _xf
			_move(50 + cos(a) * 36, 50 + sin(a) * 36)
			_turn(a + side * 1.2)
			_grow(p)
			var leaf := PackedVector2Array()
			for k in 16:
				var b := TAU * k / 16.0
				leaf.append(Vector2(cos(b) * 2.2, sin(b) * 5))
			_poly(leaf, acc)
			_put(keep)

# a snowflake grows arm by arm while snow drifts down
func _snow(acc: Color) -> void:
	for i in 14:
		var p := Vector2(fmod(i * 37.0, 80.0) + 10.0, fmod(t * 18.0 + i * 23.0, 90.0) + 5.0)
		if p.distance_to(Vector2(50, 50)) < 40.0:
			_disc(p, 1.0, Color(FG, 0.6))
	var keep := _xf
	_move(50, 50)
	_turn(t * 0.4)
	for i in 6:
		var p := _out_cubic(_seg(t, 0.35 + i * 0.08, 0.75 + i * 0.08))
		if p <= 0.0:
			continue
		var d := Vector2.from_angle(-PI / 2 + i / 6.0 * TAU)
		var n := d.orthogonal()
		_line(Vector2.ZERO, d * 20 * p, acc, 2.2)
		if p > 0.5:
			_line(d * 12, d * 17 + n * 5, acc, 2.2)
			_line(d * 12, d * 17 - n * 5, acc, 2.2)
	_put(keep)

# three pines grow out of the ground, the middle one tallest
func _forest(acc: Color) -> void:
	_fill_in_disc(PackedVector2Array([Vector2(0, 70), Vector2(100, 70), Vector2(100, 100), Vector2(0, 100)]), Color("#1f3a22"))
	for tr in [[32.0, 0.8, 0.4], [68.0, 0.8, 0.55], [50.0, 1.1, 0.5]]:
		var p := _out_back(_seg(t, tr[2], tr[2] + 0.5))
		if p <= 0.01:
			continue
		var keep := _xf
		_move(tr[0], 72)
		_grow(tr[1] * p)
		draw_rect(Rect2(-2, -6, 4, 6), Color("#6b4a2b"))
		for k in 3:
			_poly(PackedVector2Array([Vector2(0, -34 + k * 9), Vector2(12 - k, -14 + k * 5), Vector2(-12 + k, -14 + k * 5)]), acc)
		_put(keep)

# the sun rises behind two dunes and its rays turn
func _sand(acc: Color) -> void:
	var sy := 80.0 - _out_cubic(_seg(t, 0.35, 1.0)) * 36.0
	var c := Vector2(50, sy)
	for i in 10:
		var d := Vector2.from_angle(i / 10.0 * TAU + t * 0.5)
		var r2 := 18.0 + 2.0 * sin(t * 6.0 + i)
		if (c + d * r2).distance_to(Vector2(50, 50)) < 41.0:
			_line(c + d * 14, c + d * r2, acc, 2.0)
	_fill_in_disc(_circle_pts(c, 11, 28), acc)
	var d1 := PackedVector2Array([Vector2(0, 100)])
	d1.append_array(_quad(Vector2(0, 100), Vector2(30, 58), Vector2(62, 74), 14))
	d1.append(Vector2(62, 100))
	_fill_in_disc(d1, Color("#c9873a"))
	var d2 := PackedVector2Array([Vector2(30, 100)])
	d2.append_array(_quad(Vector2(30, 100), Vector2(70, 60), Vector2(100, 70), 14))
	d2.append(Vector2(100, 100))
	_fill_in_disc(d2, Color("#a96c2c"))

# peaks rise one after the other, then a flag is planted on the top
func _rock(acc: Color) -> void:
	for m in [[28.0, 0.75, 0.35, Color("#5d6670")], [70.0, 0.8, 0.45, Color("#4c545d")], [50.0, 1.15, 0.55, Color("#737c86")]]:
		var p := _out_cubic(_seg(t, m[2], m[2] + 0.45))
		if p <= 0.0:
			continue
		var x: float = m[0]
		var s: float = m[1]
		var y := 82.0 + (1.0 - p) * 40.0
		_fill_in_disc(PackedVector2Array([Vector2(x - 26 * s, y), Vector2(x, y - 38 * s), Vector2(x + 26 * s, y)]), m[3])
		_fill_in_disc(PackedVector2Array([Vector2(x - 7 * s, y - 27 * s), Vector2(x, y - 38 * s), Vector2(x + 7 * s, y - 27 * s),
			Vector2(x + 2 * s, y - 30 * s), Vector2(x - 2 * s, y - 27 * s)]), FG)
	var f := _seg(t, 1.05, 1.3)
	if f > 0.0:
		var top := 82.0 - 38.0 * 1.15
		var y0 := top - 12.0 * _out_back(f)
		_line(Vector2(50, top), Vector2(50, y0), FG, 1.4)
		_poly(PackedVector2Array([Vector2(50, y0), Vector2(50 + 9 * f, y0 + 2.5 + sin(t * 8.0)), Vector2(50, y0 + 5)]), acc)
