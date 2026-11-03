# Small hand-drawn pieces that give the menu its own identity: the animated logo
# (a car swinging round a tower on its tether), card icons and the medal cabinet.
extends RefCounted

const Medals = preload("res://scripts/medals.gd")

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

	func _process(dt: float) -> void:
		if is_visible_in_tree():
			t += dt
			queue_redraw()

	func _draw() -> void:
		var h := size.y
		var c := Vector2(h * 0.5, h * 0.5)
		var R := h * 0.42
		# frosty disc, tower, rotor
		draw_circle(c, R, Color(1, 1, 1, 0.08))
		draw_arc(c, R, 0, TAU, 48, Color(C_ICE, 0.35), 2.0, true)
		draw_circle(c, h * 0.13, C_TOWER)
		draw_circle(c, h * 0.1, C_AMBER)
		for k in 3:
			var a := -t * 3.0 + TAU * k / 3.0
			draw_line(c, c + Vector2.from_angle(a) * h * 0.085, C_TOWER, maxf(2.0, h * 0.03), true)
		# the car on its tether, nose along the arc
		var a := t * 1.6
		var p := c + Vector2.from_angle(a) * R * 0.78
		draw_line(c, p, Color(C_AMBER, 0.9), maxf(1.5, h * 0.025), true)
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
		for pass_i in 2:
			var o := Vector2(0, 3) if pass_i == 0 else Vector2.ZERO
			var sh := Color(0, 0, 0, 0.35)
			draw_string(font, Vector2(x, base) + o, "TETHER", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, sh if pass_i == 0 else C_AMBER)
			draw_string(font, Vector2(x + w1, base) + o, "RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, sh if pass_i == 0 else C_ICE)

	func min_width() -> float:
		if font == null:
			return size.y
		return size.y * 1.12 + font.get_string_size("TETHER RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

# Card icons: "flag" (campaign), "watch" (time attack), "duel" (two players)
class Icon extends Control:
	var kind := "flag"
	var col := C_AMBER

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var o := (size - Vector2(s, s)) * 0.5
		var lw := maxf(2.0, s * 0.07)
		match kind:
			"flag":
				var pole := o + Vector2(s * 0.25, s * 0.08)
				draw_line(pole, pole + Vector2(0, s * 0.86), col, lw, true)
				var cell := s * 0.13
				for gy in 3:
					for gx in 4:
						var r := Rect2(pole + Vector2(lw * 0.5 + gx * cell, gy * cell), Vector2(cell, cell))
						draw_rect(r, col if (gx + gy) % 2 == 0 else Color(C_ICE, 0.9))
			"watch":
				var c := o + Vector2(s * 0.5, s * 0.56)
				var r := s * 0.38
				draw_arc(c, r, 0, TAU, 40, col, lw, true)
				draw_rect(Rect2(c + Vector2(-s * 0.07, -r - s * 0.13), Vector2(s * 0.14, s * 0.08)), col)
				draw_line(c, c + Vector2(0, -r * 0.7), C_ICE, lw, true)
				draw_line(c, c + Vector2(r * 0.5, r * 0.25), C_ICE, lw, true)
				draw_circle(c, lw * 0.8, col)
			"duel":
				for k in 2:
					var cc := o + Vector2(s * (0.33 + 0.34 * k), s * 0.5)
					var cl: Color = [C_AMBER, Color("#5fd38d")][k]
					draw_rect(Rect2(cc - Vector2(s * 0.11, s * 0.2), Vector2(s * 0.22, s * 0.4)), cl)
					draw_rect(Rect2(cc - Vector2(s * 0.08, s * 0.04), Vector2(s * 0.16, s * 0.12)), Color("#1a2330"))

# The player's medal cabinet: one rotor disc per tier with how many they hold.
class Cabinet extends Control:
	var counts := [0, 0, 0, 0]
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
				draw_arc(c, r * 0.9, 0, TAU, 28, Color(col, 0.45), maxf(1.5, r * 0.12), true)
			var txt := "x%d" % counts[i]
			if font:
				draw_string(font, Vector2(x + r + 5, size.y * 0.5 + font_size * 0.36), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col if lit else Color(C_ICE_DIM, 0.7))
			x += r * 2 + 12 + (font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font else 20)

# The title card shared by the boot splash (tools/gen_splash.gd renders it to a PNG) and the
# in-game loading screen: a snowy night, a row of pines, the tower emblem and the wordmark.
const C_NIGHT_TOP := Color("#0d2233")
const C_NIGHT_BOT := Color("#06121b")

class Splash extends Control:
	var font: Font
	var t := 0.6               # logo animation time (frozen for the PNG)
	var animate := true
	var snow_seed := 7
	var lift := 0.0            # 0..1 moves the emblem up to leave room for text below
	var flat := false          # boot PNG: plain background so it blends into any screen shape

	func _process(dt: float) -> void:
		if animate and is_visible_in_tree():
			t += dt
			queue_redraw()

	func _draw() -> void:
		var w := size.x; var h := size.y
		var u := minf(w, h)
		if flat:
			draw_rect(Rect2(Vector2.ZERO, size), C_NIGHT_BOT)
			_emblem(w, h, u)
			return
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([C_NIGHT_TOP, C_NIGHT_TOP, C_NIGHT_BOT, C_NIGHT_BOT]))
		# falling snow
		var rng := RandomNumberGenerator.new()
		rng.seed = snow_seed
		for k in 90:
			var x := fposmod(rng.randf() * w + sin(t * 0.7 + k) * 8.0, w)
			var y := fposmod(rng.randf() * h + t * (18.0 + rng.randf() * 22.0), h)
			draw_circle(Vector2(x, y), 1.0 + rng.randf() * 1.8, Color(1, 1, 1, 0.25 + rng.randf() * 0.4))
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

	func _emblem(w: float, h: float, u: float) -> void:
		# emblem: tower, rotor, car on its tether
		var c := Vector2(w * 0.5, h * (0.38 - 0.08 * lift))
		var R := u * 0.15
		draw_circle(c, R * 1.08, Color(1, 1, 1, 0.05))
		draw_arc(c, R * 1.08, 0, TAU, 64, Color(C_ICE, 0.3), maxf(2.0, u * 0.004), true)
		draw_arc(c, R * 0.78, 0, TAU, 64, Color(C_ICE, 0.12), maxf(1.0, u * 0.003), true)
		draw_circle(c, R * 0.3, C_TOWER)
		draw_circle(c, R * 0.23, C_AMBER)
		for k in 3:
			var ra := -t * 3.0 + TAU * k / 3.0
			draw_line(c, c + Vector2.from_angle(ra) * R * 0.2, C_TOWER, maxf(2.0, R * 0.06), true)
		var a := t * 1.6
		var p := c + Vector2.from_angle(a) * R * 0.78
		draw_line(c, p, C_AMBER, maxf(2.0, R * 0.045), true)
		var fwd := Vector2.from_angle(a + PI / 2)
		var side := Vector2.from_angle(a)
		var L := R * 0.24; var W := R * 0.14
		draw_colored_polygon(PackedVector2Array([p + fwd * L + side * W, p + fwd * L - side * W, p - fwd * L - side * W, p - fwd * L + side * W]), C_CAR)
		draw_colored_polygon(PackedVector2Array([p + fwd * L * 0.2 + side * W * 0.7, p + fwd * L * 0.2 - side * W * 0.7, p - fwd * L * 0.4 - side * W * 0.7, p - fwd * L * 0.4 + side * W * 0.7]), Color("#1a2330"))
		if font == null:
			return
		var fs := int(u * 0.085)
		var w1 := font.get_string_size("TETHER ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var wt := font.get_string_size("TETHER RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := c.y + R * 1.08 + u * 0.05 + fs * 0.8
		var x := (w - wt) * 0.5
		draw_string(font, Vector2(x, base + u * 0.006), "TETHER", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.4))
		draw_string(font, Vector2(x + w1, base + u * 0.006), "RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.4))
		draw_string(font, Vector2(x, base), "TETHER", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_AMBER)
		draw_string(font, Vector2(x + w1, base), "RACING", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_ICE)
