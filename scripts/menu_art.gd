# Small hand-drawn pieces that give the menu its own identity: the animated logo
# (a car swinging round a tower on its tether), card icons and the medal cabinet.
extends RefCounted

const Medals = preload("res://scripts/medals.gd")
const Paper = preload("res://scripts/paper.gd")

# The UI has no coloured accent: on dark it is chalk cream (titles, icons, the tower emblem
# and its loading ring), on paper it is ink. The cars keep their amber; gold stays for medals
# and coins only.
const C_ACCENT := Color("#f3efe6")
const C_ACCENT_DIM := Color("#b3ad9f")   # the second word of the logo on dark
const C_AMBER := Color("#f2b134")
const C_ICE := Color("#e6f1f8")
const C_ICE_DIM := Color("#9fc0d6")
const C_TOWER := Color("#2a2f36")
const C_CAR := Color("#f2b134")

# "TETHER RACING" with a tower emblem: a car orbits it on a rope and the rotor turns.
class Logo extends Control:
	var font: Font
	var font_size := 40
	var t := 0.0
	var ink := false   # written on the roadbook's paper: ink and soft ink, no shadow

	func _process(dt: float) -> void:
		if is_visible_in_tree():
			t += dt
			queue_redraw()

	func _draw() -> void:
		var h := size.y
		var c := Vector2(h * 0.5, h * 0.5)
		var R := h * 0.42
		# frosty disc, tower, rotor
		if ink:
			draw_arc(c, R, 0, TAU, 48, Paper.INK, 2.5, true)
			draw_arc(c, R * 0.78, 0, TAU, 48, Paper.INK_FAINT, 1.5, true)
		else:
			draw_circle(c, R, Color(1, 1, 1, 0.08))
			draw_arc(c, R, 0, TAU, 48, Color(C_ICE, 0.35), 2.0, true)
		draw_circle(c, h * 0.13, C_TOWER)
		draw_circle(c, h * 0.1, C_ACCENT)
		for k in 3:
			var a := -t * 3.0 + TAU * k / 3.0
			draw_line(c, c + Vector2.from_angle(a) * h * 0.085, C_TOWER, maxf(2.0, h * 0.03), true)
		# the car on its tether (both in the car amber), nose along the arc
		var a := t * 1.6
		var p := c + Vector2.from_angle(a) * R * 0.78
		draw_line(c, p, Color(C_CAR, 0.9), maxf(1.5, h * 0.025), true)
		var fwd := Vector2.from_angle(a + PI / 2)
		var side := Vector2.from_angle(a)
		var L := h * 0.12; var W := h * 0.07
		var body := PackedVector2Array([p + fwd * L + side * W, p + fwd * L - side * W, p - fwd * L - side * W, p - fwd * L + side * W])
		draw_colored_polygon(body, C_CAR)
		draw_colored_polygon(PackedVector2Array([p + fwd * L * 0.2 + side * W * 0.7, p + fwd * L * 0.2 - side * W * 0.7, p - fwd * L * 0.4 - side * W * 0.7, p - fwd * L * 0.4 + side * W * 0.7]), Color("#1a2330"))
		if font == null:
			return
		# two-tone wordmark with a soft shadow
		var x := h * 1.12
		var base := h * 0.5 + font_size * 0.36
		var w1 := font.get_string_size("TETHER ", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		if ink:
			draw_string(font, Vector2(x, base), "TETHER", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Paper.INK)
			draw_string(font, Vector2(x + w1, base), "RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Paper.INK_SOFT)
			return
		for pass_i in 2:
			var o := Vector2(0, 3) if pass_i == 0 else Vector2.ZERO
			var sh := Color(0, 0, 0, 0.35)
			draw_string(font, Vector2(x, base) + o, "TETHER", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, sh if pass_i == 0 else C_ACCENT)
			draw_string(font, Vector2(x + w1, base) + o, "RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, sh if pass_i == 0 else C_ACCENT_DIM)

	func min_width() -> float:
		var h := maxf(size.y, custom_minimum_size.y)   # size is still 0 before the first layout
		if font == null:
			return h
		return h * 1.12 + font.get_string_size("TETHER RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

# Hand-drawn icons, all in one stroke style so they read as a set.
# Cards: "flag" (campaign), "watch" (time attack), "duel" (two players).
# Buttons: gear, back, prev, next, play, retry, home, check, pause, ghost, spark, music, sound, vibrate.
# Variants: standard, reverse, obstacles, collect.
# Themes: snow, forest, rock, sand, and lock for one not yet unlocked.
class Icon extends Control:
	var kind := "flag":
		set(v):
			kind = v
			queue_redraw()
	var col := C_ACCENT:
		set(v):
			col = v
			queue_redraw()
	var col2 := C_ICE   # second tone (hands of the watch, gem facets...)
	var ink := false    # drawn on paper: holes and flag squares in paper, snowflake in ink

	func _chevron(c: Vector2, s: float, dir: float, lw: float) -> void:
		var d := Vector2(dir, 0)
		draw_polyline(PackedVector2Array([c - d * s * 0.1 + Vector2(0, -s * 0.24), c + d * s * 0.14, c - d * s * 0.1 + Vector2(0, s * 0.24)]), col, lw * 1.3, true)

	func _arrow_head(tip: Vector2, dir: Vector2, s: float) -> void:
		var n := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([tip + dir * s * 0.12, tip - dir * s * 0.08 + n * s * 0.12, tip - dir * s * 0.08 - n * s * 0.12]), col)

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		var c := o + Vector2(s, s) * 0.5
		var lw := maxf(2.0, s * 0.07)
		var hole := Paper.CARD if ink else Color("#0d1a26")
		var pale := Paper.CARD if ink else C_ICE
		var flake := Paper.INK if ink else C_ICE
		match kind:
			"gear":
				var r := s * 0.3
				var pts := PackedVector2Array()
				for k in 48:
					var a := TAU * k / 48.0
					var tooth := fmod(k, 6.0) < 3.0
					pts.append(c + Vector2.from_angle(a) * (r * 1.3 if tooth else r))
				draw_colored_polygon(pts, col)
				draw_circle(c, r * 0.45, hole)
			"back":
				draw_line(c + Vector2(s * 0.28, 0), c - Vector2(s * 0.2, 0), col, lw * 1.2, true)
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.02, -s * 0.22), c - Vector2(s * 0.26, 0), c + Vector2(-s * 0.02, s * 0.22)]), col, lw * 1.2, true)
			"prev":
				_chevron(c, s, -1.0, lw)
			"next":
				_chevron(c, s, 1.0, lw)
			"play":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.28), c + Vector2(s * 0.3, 0), c + Vector2(-s * 0.2, s * 0.28)]), col)
			"pause":
				draw_rect(Rect2(c + Vector2(-s * 0.22, -s * 0.26), Vector2(s * 0.15, s * 0.52)), col)
				draw_rect(Rect2(c + Vector2(s * 0.07, -s * 0.26), Vector2(s * 0.15, s * 0.52)), col)
			"retry":
				var r := s * 0.28
				draw_arc(c, r, deg_to_rad(-60), deg_to_rad(230), 32, col, lw * 1.2, true)
				var a := deg_to_rad(-60)
				_arrow_head(c + Vector2.from_angle(a) * r, Vector2.from_angle(a + PI / 2), s)
			"home":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.34), c + Vector2(s * 0.36, -s * 0.02), c + Vector2(-s * 0.36, -s * 0.02)]), col)
				draw_rect(Rect2(c + Vector2(-s * 0.25, -s * 0.06), Vector2(s * 0.5, s * 0.36)), col)
				draw_rect(Rect2(c + Vector2(-s * 0.07, s * 0.1), Vector2(s * 0.14, s * 0.2)), hole)
			"coin":       # a gold coin with a rim and a notch
				draw_circle(c, s * 0.36, Color("#b8801c"))
				draw_circle(c + Vector2(-s * 0.02, -s * 0.02), s * 0.31, Color("#f2c84a"))
				draw_arc(c, s * 0.21, 0, TAU, 24, Color("#c9922a"), maxf(1.5, s * 0.05), true)
				draw_rect(Rect2(c + Vector2(-s * 0.04, -s * 0.13), Vector2(s * 0.08, s * 0.26)), Color("#c9922a"))
				draw_circle(c + Vector2(-s * 0.14, -s * 0.15), s * 0.05, Color(1, 1, 1, 0.7))
			"trophy":     # a cup on a stand
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.24, -s * 0.32), c + Vector2(s * 0.24, -s * 0.32),
					c + Vector2(s * 0.16, -s * 0.02), c + Vector2(0, s * 0.06), c + Vector2(-s * 0.16, -s * 0.02)]), col)
				for sx in [-1.0, 1.0]:
					draw_arc(c + Vector2(sx * s * 0.25, -s * 0.18), s * 0.1, -PI / 2 if sx > 0 else PI / 2, PI / 2 if sx > 0 else PI * 1.5, 10, col, lw * 0.8, true)
				draw_rect(Rect2(c + Vector2(-s * 0.04, s * 0.04), Vector2(s * 0.08, s * 0.16)), col)
				draw_rect(Rect2(c + Vector2(-s * 0.18, s * 0.2), Vector2(s * 0.36, s * 0.1)), col)
			"check":
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.28, 0), c + Vector2(-s * 0.08, s * 0.2), c + Vector2(s * 0.3, -s * 0.22)]), col, lw * 1.5, true)
			"ghost":
				var top := c + Vector2(0, -s * 0.06)
				var r := s * 0.26
				var pts := PackedVector2Array()
				for k in 17:
					pts.append(top + Vector2.from_angle(PI + PI * k / 16.0) * r)
				var by := c.y + s * 0.3
				for k in 7:
					var x := c.x + r - 2.0 * r * k / 6.0
					pts.append(Vector2(x, by - (s * 0.07 if k % 2 == 1 else 0.0)))
				draw_colored_polygon(pts, Color(col, 0.85))
				draw_circle(top + Vector2(-r * 0.35, 0), s * 0.05, hole)
				draw_circle(top + Vector2(r * 0.35, 0), s * 0.05, hole)
			"spark":      # a four-point sparkle
				var pts := PackedVector2Array()
				for k in 8:
					pts.append(c + Vector2.from_angle(TAU * k / 8.0 - PI / 2) * s * (0.36 if k % 2 == 0 else 0.1))
				draw_colored_polygon(pts, col)
				draw_circle(c + Vector2(s * 0.26, -s * 0.26), s * 0.05, col2)
				draw_circle(c + Vector2(-s * 0.24, s * 0.26), s * 0.04, col2)
			"vibrate":    # a phone with buzz marks either side
				var r := Rect2(c + Vector2(-s * 0.14, -s * 0.3), Vector2(s * 0.28, s * 0.6))
				draw_rect(r, col, false, lw)
				draw_line(c + Vector2(-s * 0.05, s * 0.2), c + Vector2(s * 0.05, s * 0.2), col, lw, true)
				for sd in [-1.0, 1.0]:
					var x: float = c.x + sd * s * 0.26
					draw_polyline(PackedVector2Array([Vector2(x, c.y - s * 0.16), Vector2(x + sd * s * 0.06, c.y - s * 0.06),
						Vector2(x, c.y + s * 0.04), Vector2(x + sd * s * 0.06, c.y + s * 0.14)]), col2, lw * 0.8, true)
			"music":
				var h1 := c + Vector2(-s * 0.12, s * 0.2)
				var h2 := c + Vector2(s * 0.22, s * 0.12)
				draw_circle(h1, s * 0.1, col)
				draw_circle(h2, s * 0.1, col)
				var t1 := h1 + Vector2(s * 0.09, -s * 0.46)
				var t2 := h2 + Vector2(s * 0.09, -s * 0.46)
				draw_line(h1 + Vector2(s * 0.09, 0), t1, col, lw, true)
				draw_line(h2 + Vector2(s * 0.09, 0), t2, col, lw, true)
				draw_line(t1, t2, col, lw * 1.6, true)
			"sound":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.32, -s * 0.1), c + Vector2(-s * 0.18, -s * 0.1), c + Vector2(0, -s * 0.28),
					c + Vector2(0, s * 0.28), c + Vector2(-s * 0.18, s * 0.1), c + Vector2(-s * 0.32, s * 0.1)]), col)
				draw_arc(c + Vector2(s * 0.02, 0), s * 0.16, -0.8, 0.8, 12, col, lw, true)
				draw_arc(c + Vector2(s * 0.02, 0), s * 0.3, -0.8, 0.8, 16, col, lw, true)
			"standard":   # a loop with an arrow: go round
				var r := s * 0.3
				draw_arc(c, r, deg_to_rad(-80), deg_to_rad(250), 36, col, lw * 1.2, true)
				_arrow_head(c + Vector2.from_angle(deg_to_rad(-80)) * r, Vector2.from_angle(deg_to_rad(10)), s)
			"reverse":    # two arrows going opposite ways
				draw_line(c + Vector2(-s * 0.28, -s * 0.13), c + Vector2(s * 0.2, -s * 0.13), col, lw * 1.2, true)
				_arrow_head(c + Vector2(s * 0.22, -s * 0.13), Vector2.RIGHT, s)
				draw_line(c + Vector2(s * 0.28, s * 0.15), c + Vector2(-s * 0.2, s * 0.15), col2, lw * 1.2, true)
				var keep := col
				col = col2
				_arrow_head(c + Vector2(-s * 0.22, s * 0.15), Vector2.LEFT, s)
				col = keep
			"obstacles":  # a striped post
				var r := Rect2(c + Vector2(-s * 0.12, -s * 0.32), Vector2(s * 0.24, s * 0.6))
				draw_rect(r, col)
				for k in 3:
					draw_rect(Rect2(r.position + Vector2(0, s * (0.08 + k * 0.18)), Vector2(r.size.x, s * 0.07)), hole)
				draw_rect(Rect2(c + Vector2(-s * 0.24, s * 0.26), Vector2(s * 0.48, s * 0.07)), col2)
			"collect":    # a gem
				var t := c + Vector2(0, -s * 0.26)
				var pts := PackedVector2Array([c + Vector2(-s * 0.3, -s * 0.08), c + Vector2(-s * 0.16, -s * 0.26), c + Vector2(s * 0.16, -s * 0.26),
					c + Vector2(s * 0.3, -s * 0.08), c + Vector2(0, s * 0.32)])
				draw_colored_polygon(pts, Color("#7fe3d0"))
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.3, -s * 0.08), c + Vector2(s * 0.3, -s * 0.08)]), Color(C_ICE, 0.9), maxf(1.0, lw * 0.5), true)
				draw_polyline(PackedVector2Array([t + Vector2(-s * 0.16, 0), c + Vector2(-s * 0.06, -s * 0.08), c + Vector2(0, s * 0.32), c + Vector2(s * 0.06, -s * 0.08), t + Vector2(s * 0.16, 0)]), Color(C_ICE, 0.7), maxf(1.0, lw * 0.4), true)
			"flag":
				var pole := o + Vector2(s * 0.25, s * 0.08)
				draw_line(pole, pole + Vector2(0, s * 0.86), col, lw, true)
				var cell := s * 0.13
				for gy in 3:
					for gx in 4:
						var r := Rect2(pole + Vector2(lw * 0.5 + gx * cell, gy * cell), Vector2(cell, cell))
						draw_rect(r, col if (gx + gy) % 2 == 0 else Color(pale, 0.9))
			"watch":
				var cw := o + Vector2(s * 0.5, s * 0.56)
				var r := s * 0.38
				draw_arc(cw, r, 0, TAU, 40, col, lw, true)
				draw_rect(Rect2(cw + Vector2(-s * 0.07, -r - s * 0.13), Vector2(s * 0.14, s * 0.08)), col)
				draw_line(cw, cw + Vector2(0, -r * 0.7), col2, lw, true)
				draw_line(cw, cw + Vector2(r * 0.5, r * 0.25), col2, lw, true)
				draw_circle(cw, lw * 0.8, col)
			"snow":
				# a six-armed snowflake with little side branches
				for k in 6:
					var d := Vector2.from_angle(TAU * k / 6.0 - PI / 2)
					draw_line(c, c + d * s * 0.36, flake, lw, true)
					var m := c + d * s * 0.22
					draw_line(m, m + d.rotated(0.8) * s * 0.1, flake, lw * 0.8, true)
					draw_line(m, m + d.rotated(-0.8) * s * 0.1, flake, lw * 0.8, true)
			"forest":
				# a pine: three stacked triangles on a trunk
				var g := Color("#6fbf5a")
				draw_rect(Rect2(c + Vector2(-s * 0.04, s * 0.22), Vector2(s * 0.08, s * 0.14)), Color("#a07a50"))
				for k in 3:
					var y := c.y - s * 0.34 + k * s * 0.16
					var w := s * (0.16 + k * 0.08)
					draw_colored_polygon(PackedVector2Array([Vector2(c.x, y), Vector2(c.x + w, y + s * 0.26), Vector2(c.x - w, y + s * 0.26)]), g.darkened(0.12 * k))
			"rock":
				# two peaks, the near one with a light face
				var base := c.y + s * 0.3
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.06, base), Vector2(c.x + s * 0.18, c.y - s * 0.2), Vector2(c.x + s * 0.4, base)]), Color("#7d8086"))
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.4, base), Vector2(c.x - s * 0.1, c.y - s * 0.34), Vector2(c.x + s * 0.2, base)]), Color("#a6a9ae"))
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.1, c.y - s * 0.34), Vector2(c.x + s * 0.2, base), Vector2(c.x - s * 0.02, base)]), Color("#7d8086"))
			"sand":
				# a sun over two dunes
				draw_circle(c + Vector2(s * 0.12, -s * 0.14), s * 0.15, C_AMBER)
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.4, c.y + s * 0.3), Vector2(c.x - s * 0.12, c.y + s * 0.02), Vector2(c.x + s * 0.18, c.y + s * 0.3)]), Color("#e6c891"))
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.05, c.y + s * 0.3), Vector2(c.x + s * 0.2, c.y + s * 0.1), Vector2(c.x + s * 0.4, c.y + s * 0.3)]), Color("#c99e64"))
			"car":        # the garage: a racer from the side
				var y0 := c.y + s * 0.12
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.42, y0), Vector2(c.x - s * 0.42, y0 - s * 0.16),
					Vector2(c.x - s * 0.16, y0 - s * 0.18), Vector2(c.x - s * 0.06, y0 - s * 0.34), Vector2(c.x + s * 0.14, y0 - s * 0.34),
					Vector2(c.x + s * 0.24, y0 - s * 0.18), Vector2(c.x + s * 0.42, y0 - s * 0.12), Vector2(c.x + s * 0.42, y0)]), col)
				draw_colored_polygon(PackedVector2Array([Vector2(c.x - s * 0.03, y0 - s * 0.29), Vector2(c.x + s * 0.12, y0 - s * 0.29),
					Vector2(c.x + s * 0.18, y0 - s * 0.18), Vector2(c.x - s * 0.09, y0 - s * 0.18)]), Color("#1a2330"))
				draw_rect(Rect2(Vector2(c.x - s * 0.42, y0 - s * 0.12), Vector2(s * 0.84, s * 0.035)), col2)
				for wx in [-0.24, 0.24]:
					draw_circle(Vector2(c.x + s * wx, y0), s * 0.11, Color("#1a2330"))
					draw_circle(Vector2(c.x + s * wx, y0), s * 0.05, col2)
			"paint":      # a paint drop
				var pts := PackedVector2Array()
				for k in 33:
					var a := PI * k / 32.0
					pts.append(c + Vector2(cos(a) * s * 0.26, s * 0.12 + sin(a) * s * 0.26))
				pts.append(c + Vector2(0, -s * 0.38))
				draw_colored_polygon(pts, col)
				draw_circle(c + Vector2(-s * 0.09, s * 0.12), s * 0.06, Color(1, 1, 1, 0.55))
			"livery":     # a car seen from above with two stripes
				var r := Rect2(c - Vector2(s * 0.2, s * 0.38), Vector2(s * 0.4, s * 0.76))
				draw_rect(r, col)
				for sx in [-0.07, 0.04]:
					draw_rect(Rect2(Vector2(c.x + s * sx, r.position.y), Vector2(s * 0.03, r.size.y)), col2)
				draw_rect(Rect2(c + Vector2(-s * 0.15, -s * 0.16), Vector2(s * 0.3, s * 0.14)), Color("#1a2330"))
			"rope":       # a coil of rope
				for k in 3:
					draw_arc(c + Vector2(0, s * (0.06 * k - 0.06)), s * (0.3 - k * 0.07), 0, TAU, 32, col, lw * 0.8, true)
				draw_line(c + Vector2(s * 0.3, 0), c + Vector2(s * 0.42, s * 0.3), col, lw * 0.8, true)
			"lock":
				var body_r := Rect2(c + Vector2(-s * 0.22, -s * 0.04), Vector2(s * 0.44, s * 0.34))
				var lc := col if ink else Color(C_ICE_DIM, 0.8)
				draw_arc(c + Vector2(0, -s * 0.06), s * 0.15, PI, TAU, 16, lc, lw, true)
				draw_rect(body_r, lc)
				draw_circle(c + Vector2(0, s * 0.11), s * 0.04, hole)
			"duel":
				for k in 2:
					var cc := o + Vector2(s * (0.33 + 0.34 * k), s * 0.5)
					var cl: Color = [C_AMBER, Color("#5fd38d")][k]
					draw_rect(Rect2(cc - Vector2(s * 0.11, s * 0.2), Vector2(s * 0.22, s * 0.4)), cl)
					draw_rect(Rect2(cc - Vector2(s * 0.08, s * 0.04), Vector2(s * 0.16, s * 0.12)), Color("#1a2330"))

# The player's medal cabinet: one rotor disc per tier with how many they hold.
class Cabinet extends Control:
	var counts := [0, 0, 0, 0]
	var ink := false
	var font: Font
	var font_size := 15

	func _draw() -> void:
		var r := size.y * 0.36
		var x := r + 2
		for i in 4:
			var c := Vector2(x, size.y * 0.5)
			var col: Color = Medals.COLORS[i]
			var lit: bool = counts[i] > 0
			if lit:
				draw_circle(c, r, col.darkened(0.35))
				draw_circle(c, r * 0.8, col)
				for k in 3:
					draw_line(c, c + Vector2.from_angle(TAU * k / 3.0 + 0.4) * r * 0.62, col.darkened(0.45), maxf(2.0, r * 0.22), true)
			else:
				draw_arc(c, r * 0.9, 0, TAU, 28, Color(col.darkened(0.35), 0.7) if ink else Color(col, 0.45), maxf(1.5, r * 0.12), true)
			var txt := "x%d" % counts[i]
			if font:
				var tc: Color = (col.darkened(0.4) if lit else Paper.INK_SOFT) if ink else (col if lit else Color(C_ICE_DIM, 0.7))
				draw_string(font, Vector2(x + r + 5, size.y * 0.5 + font_size * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tc)
			x += r * 2 + 12 + (font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font else 20)

# The title card shared by the boot splash (tools/gen_splash.gd renders it to a PNG) and the
# in-game loading screen: a snowy night, a row of pines, the tower emblem and the wordmark.
# The emblem is also the game's only loading indicator: set `progress` (0..1) and an amber ring
# fills around it while the car keeps lapping the tower; `spinner` runs an endless chasing arc
# instead (web/shell_template.html draws the same emblem in SVG for the browser loader).
const C_NIGHT_TOP := Color("#0d2233")
const C_NIGHT_BOT := Color("#06121b")

class Splash extends Control:
	var font: Font
	var t := 0.6               # logo animation time (frozen for the PNG)
	var animate := true
	var snow_seed := 7
	var lift := 0.0            # 0..1 moves the emblem up to leave room for text below
	var flat := false          # boot PNG: plain background so it blends into any screen shape
	var clear_bg := false      # with flat: no background at all (web page logo)
	var bg: Texture2D          # loading screen artwork, cropped to cover the screen
	var emblem_y := 0.38       # emblem centre, fraction of the height
	var emblem_k := 1.0        # emblem and wordmark scale
	var show_emblem := true    # false: wordmark only (the web page draws its own animated emblem)
	var progress := -1.0       # loading progress target 0..1; below 0 the ring is not drawn
	var shown := 0.0           # progress as drawn, eases towards `progress`
	var spinner := false       # no known progress: an arc chases round the ring

	func _process(dt: float) -> void:
		if animate and is_visible_in_tree():
			t += dt
			if progress >= 0.0:
				shown = lerpf(shown, progress, 1.0 - exp(-10.0 * dt))
			queue_redraw()

	func _draw() -> void:
		var w := size.x; var h := size.y
		var u := minf(w, h)
		if flat:
			if not clear_bg:
				draw_rect(Rect2(Vector2.ZERO, size), C_NIGHT_BOT)
			_emblem(w, h, u)
			return
		if bg:
			_draw_art(w, h)
			_snow(w, h)
			_emblem(w, h, u)
			return
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([C_NIGHT_TOP, C_NIGHT_TOP, C_NIGHT_BOT, C_NIGHT_BOT]))
		_snow(w, h)
		var rng := RandomNumberGenerator.new()
		# snow bank and pines along the bottom
		var gy := h * 0.9
		var bank := PackedVector2Array([Vector2(0, h), Vector2(0, gy)])
		for k in 8:
			bank.append(Vector2(w * (k + 0.5) / 8.0, gy + sin(k * 1.7) * u * 0.012))
		bank.append(Vector2(w, gy)); bank.append(Vector2(w, h))
		draw_colored_polygon(bank, Color("#c9d6e0"))
		rng.seed = snow_seed + 1
		var x0 := -u * 0.05
		while x0 < w + u * 0.05:
			var th := u * (0.05 + rng.randf() * 0.06)
			var bw := th * 0.42
			var by := gy + u * 0.01
			for tier in 3:
				var tw := bw * (1.0 - tier * 0.25)
				var ty := by - th * tier * 0.3
				draw_colored_polygon(PackedVector2Array([Vector2(x0 - tw, ty), Vector2(x0 + tw, ty), Vector2(x0, ty - th * 0.5)]), Color("#1f4438"))
				draw_colored_polygon(PackedVector2Array([Vector2(x0 - tw * 0.35, ty - th * 0.33), Vector2(x0 + tw * 0.35, ty - th * 0.33), Vector2(x0, ty - th * 0.5)]), Color("#e6eef4"))
			x0 += u * (0.05 + rng.randf() * 0.09)
		_emblem(w, h, u)

	func _snow(w: float, h: float) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = snow_seed
		for k in 90:
			var x := fposmod(rng.randf() * w + sin(t * 0.7 + k) * 8.0, w)
			var y := fposmod(rng.randf() * h + t * (18.0 + rng.randf() * 22.0), h)
			draw_circle(Vector2(x, y), 1.0 + rng.randf() * 1.8, Color(1, 1, 1, 0.25 + rng.randf() * 0.4))

	# the artwork scaled to cover the screen, with a slow drift, and night-blue shading
	# at the top (under the logo) and the bottom (under the text and the bar)
	func _draw_art(w: float, h: float) -> void:
		var ts := bg.get_size()
		var k := maxf(w / ts.x, h / ts.y) * 1.06
		var sz := ts * k
		var drift := Vector2(sin(t * 0.12), cos(t * 0.09)) * minf(w, h) * 0.015
		# crop mostly from the bottom so the dusk sky stays behind the logo
		var pos := Vector2((w - sz.x) * 0.5, (h - sz.y) * 0.12) + drift
		draw_texture_rect(bg, Rect2(pos, sz), false)
		var top := Color(C_NIGHT_TOP, 0.82); var clear := Color(C_NIGHT_TOP, 0.0)
		var bot := Color(C_NIGHT_BOT, 0.9); var clear2 := Color(C_NIGHT_BOT, 0.0)
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h * 0.5), Vector2(0, h * 0.5)]),
			PackedColorArray([top, top, clear, clear]))
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.55), Vector2(w, h * 0.55), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([clear2, clear2, bot, bot]))

	func _emblem(w: float, h: float, u: float) -> void:
		# emblem: tower, rotor, car on its tether
		var c := Vector2(w * 0.5, h * (emblem_y - 0.08 * lift))
		var R := u * 0.15 * emblem_k
		if show_emblem:
			draw_emblem(self, c, R, t, shown if progress >= 0.0 else -1.0, spinner, bg != null)
		if font == null:
			return
		var fs := int(u * 0.085 * emblem_k)
		var w1 := font.get_string_size("TETHER ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var wt := font.get_string_size("TETHER RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := c.y + R * 1.08 + u * 0.05 + fs * 0.8
		var x := (w - wt) * 0.5
		draw_string(font, Vector2(x, base + u * 0.006), "TETHER", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.4))
		draw_string(font, Vector2(x + w1, base + u * 0.006), "RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.4))
		draw_string(font, Vector2(x, base), "TETHER", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_ACCENT)
		draw_string(font, Vector2(x + w1, base), "RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_ACCENT_DIM)

	# the emblem: tower with its spinning rotor, the car lapping it on its tether, and the ring
	# round them that doubles as the loading indicator. `prog` 0..1 fills the ring in amber from
	# the top, clockwise (below 0: no ring); `spin` instead runs a short arc round and round.
	static func draw_emblem(ci: CanvasItem, c: Vector2, R: float, t: float, prog := -1.0, spin := false, dark := true) -> void:
		var u := R / 0.15
		ci.draw_circle(c, R * 1.08, Color(C_NIGHT_BOT, 0.55) if dark else Color(1, 1, 1, 0.05))
		ci.draw_arc(c, R * 1.08, 0, TAU, 64, Color(C_ICE, 0.3), maxf(2.0, u * 0.004), true)
		ci.draw_arc(c, R * 0.78, 0, TAU, 64, Color(C_ICE, 0.12), maxf(1.0, u * 0.003), true)
		var rw := maxf(3.0, R * 0.07)
		if spin:
			var a0 := t * 4.2 - PI / 2
			var a1 := a0 + PI * (0.35 + 0.25 * sin(t * 2.1))
			ci.draw_arc(c, R * 1.08, a0, a1, 32, C_ACCENT, rw, true)
			ci.draw_circle(c + Vector2.from_angle(a1) * R * 1.08, rw * 0.5, C_ACCENT)
			ci.draw_circle(c + Vector2.from_angle(a0) * R * 1.08, rw * 0.5, C_ACCENT)
		elif prog >= 0.0:
			var p := clampf(prog, 0.0, 1.0)
			var a1 := -PI / 2 + TAU * p
			ci.draw_arc(c, R * 1.08, -PI / 2, a1, maxi(4, int(64 * p)), C_ACCENT, rw, true)
			ci.draw_circle(c + Vector2.from_angle(-PI / 2) * R * 1.08, rw * 0.5, C_ACCENT)
			var head := c + Vector2.from_angle(a1) * R * 1.08
			ci.draw_circle(head, rw * 0.95, Color(C_ACCENT, 0.35 + 0.15 * sin(t * 8.0)))
			ci.draw_circle(head, rw * 0.6, Color("#e6f1f8"))
		ci.draw_circle(c, R * 0.3, C_TOWER)
		ci.draw_circle(c, R * 0.23, C_ACCENT)
		for k in 3:
			var ra := -t * 3.0 + TAU * k / 3.0
			ci.draw_line(c, c + Vector2.from_angle(ra) * R * 0.2, C_TOWER, maxf(2.0, R * 0.06), true)
		var a := t * 1.6
		var p := c + Vector2.from_angle(a) * R * 0.78
		ci.draw_line(c, p, C_CAR, maxf(2.0, R * 0.045), true)
		var fwd := Vector2.from_angle(a + PI / 2)
		var side := Vector2.from_angle(a)
		var L := R * 0.24; var W := R * 0.14
		ci.draw_colored_polygon(PackedVector2Array([p + fwd * L + side * W, p + fwd * L - side * W, p - fwd * L - side * W, p - fwd * L + side * W]), C_CAR)
		ci.draw_colored_polygon(PackedVector2Array([p + fwd * L * 0.2 + side * W * 0.7, p + fwd * L * 0.2 - side * W * 0.7, p - fwd * L * 0.4 - side * W * 0.7, p - fwd * L * 0.4 + side * W * 0.7]), Color("#1a2330"))
