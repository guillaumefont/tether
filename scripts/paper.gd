# The Roadbook look of the menus: a rally co-driver's notebook. Cream ruled paper, navy ink,
# white index cards, an ice-blue highlighter, strips of tape, rubber-stamp medals and
# "tulip" bend diagrams. The race HUD stays dark (it sits over the moving track); every menu,
# panel and overlay is paper.
extends RefCounted

const PAPER := Color("#efe9dc")        # the page
const PAPER_DARK := Color("#e2d9c6")   # a divider, a locked card
const CARD := Color("#fbf8f1")         # an index card / photo border lying on the page
const INK := Color("#15222e")          # text, outlines, the main buttons
const INK_SOFT := Color("#56636e")     # second line of text
const INK_FAINT := Color(0.082, 0.133, 0.18, 0.28)
const RULE := Color(0.082, 0.133, 0.18, 0.08)   # the ruled lines
const ACCENT := Color("#4fb6ff")       # the game's ice blue: highlighter, button shadow, tower cap
const ACCENT_INK := Color("#1d7fc4")   # the same blue dark enough to read as text on paper
const HL := Color(0.31, 0.71, 1.0, 0.5)   # highlighter band behind a word
const TAPE := Color(0.84, 0.89, 0.91, 0.78)
const COIN_INK := Color("#a8730c")     # coin amounts written on paper (gold, darkened to read)
const RED_INK := Color("#c8432f")
const PEN := Color("#1d5fa8")          # ballpoint blue: handwritten notes
const PENCIL := Color("#6b6f73")       # pencilled asides
const MARGIN := Color(0.78, 0.26, 0.18, 0.35)   # the red margin line down a page

static var _hand: Font

# Caveat, the co-driver's handwriting (a variable font, set a little bolder than regular)
static func hand() -> Font:
	if _hand == null:
		var fv := FontVariation.new()
		fv.base_font = load("res://fonts/Caveat.ttf")
		fv.variation_opentype = { TextServerManager.get_primary_interface().name_to_tag("wght"): 600 }
		_hand = fv
	return _hand

# a handwritten note: Caveat in pen blue, a touch crooked
static func note(text: String, size := 22, col := PEN, tilt := -0.02) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", hand())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.rotation = tilt
	return l

# a flat box: paper-like corners (2 px), an optional ink border and a soft drop shadow
static func box(bg: Color, border := Color.TRANSPARENT, bw := 0, shadow := 4, radius := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.border_color = border
		s.set_border_width_all(bw)
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.28)
		s.shadow_size = shadow
		s.shadow_offset = Vector2(0, shadow * 0.5)
	s.anti_aliasing = false
	return s

# the main action: solid ink with an ice-blue block shadow, like a felt-tip box
# (drawn as a border just outside the button's right and bottom edges; `off` = its depth)
static func go_box(lit := false, off := 4) -> StyleBoxFlat:
	var s := box(INK.lightened(0.12) if lit else INK, ACCENT, 0, 0)
	s.expand_margin_right = off
	s.expand_margin_bottom = off
	s.border_width_right = off
	s.border_width_bottom = off
	s.border_color = ACCENT
	return s

# one sheet of the roadbook: cream paper, ruled lines, a shadow onto the world behind
class Sheet extends PanelContainer:
	var ruled := true
	var rule_top := 0.0      # first ruled line (under the title)
	var margin_x := 0.0      # > 0: a red margin line this far in from the left edge
	var clip_x := -1.0       # >= 0: a paper clip over the top edge, this far from the right

	func _init() -> void:
		var s := StyleBoxFlat.new()
		s.bg_color = PAPER
		s.set_corner_radius_all(2)
		s.shadow_color = Color(0, 0, 0, 0.45)
		s.shadow_size = 18
		s.shadow_offset = Vector2(0, 6)
		s.set_content_margin_all(18)
		add_theme_stylebox_override("panel", s)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			queue_redraw()

	# a small tile of paper fibre, drawn repeated over every sheet (made once, no file)
	static var _grain: Texture2D

	static func grain() -> Texture2D:
		if _grain == null:
			var img := Image.create(128, 128, false, Image.FORMAT_LA8)
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for y in 128:
				for x in 128:
					var v := rng.randf()
					# mostly clear, a speckle of darker and lighter fibres
					var a := 0.0
					if v < 0.10: a = 0.10
					elif v < 0.16: a = 0.05
					img.set_pixel(x, y, Color(0.35, 0.35, 0.35, a) if v < 0.13 else Color(1, 1, 1, a))
			_grain = ImageTexture.create_from_image(img)
		return _grain

	# a steel paper clip holding the top of a page (`at` = its top end)
	static func clip(ci: CanvasItem, at: Vector2, angle: float) -> void:
		var col := Color("#8d99a3")
		ci.draw_set_transform(at, angle, Vector2.ONE)
		_round_loop(ci, Rect2(2, 3, 22, 62), Color(0, 0, 0, 0.2), 3.0)   # its shadow
		_round_loop(ci, Rect2(0, 0, 22, 62), col, 3.0)
		_round_loop(ci, Rect2(5, 8, 12, 46), col, 3.0)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	static func _round_loop(ci: CanvasItem, r: Rect2, col: Color, w: float) -> void:
		var rad := r.size.x * 0.5
		var c1 := Vector2(r.position.x + rad, r.position.y + rad)
		var c2 := Vector2(r.position.x + rad, r.end.y - rad)
		ci.draw_arc(c1, rad, PI, TAU, 12, col, w, true)
		ci.draw_arc(c2, rad, 0.0, PI, 12, col, w, true)
		ci.draw_line(Vector2(r.position.x, c1.y), Vector2(r.position.x, c2.y), col, w, true)
		ci.draw_line(Vector2(r.end.x, c1.y), Vector2(r.end.x, c2.y), col, w, true)

	func _draw() -> void:
		draw_texture_rect(grain(), Rect2(Vector2(2, 2), size - Vector2(4, 4)), true)
		if ruled:
			var y := maxf(rule_top, 30.0)
			while y < size.y - 6.0:
				draw_line(Vector2(6, y), Vector2(size.x - 6, y), RULE, 1.0)
				y += 32.0
		if margin_x > 0.0:
			draw_line(Vector2(margin_x, 0), Vector2(margin_x, size.y), MARGIN, 2.0)
		if clip_x >= 0.0:
			clip(self, Vector2(size.x - clip_x, -18), 0.14)

# a strip of tape holding a photo or a note onto the page (child of the thing it holds)
class Tape extends Control:
	var tilt := -0.08

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(84, 22)

	func _draw() -> void:
		paint(self, size * 0.5, size.x, size.y, tilt)

	# torn ends, a little crooked
	static func paint(ci: CanvasItem, c: Vector2, length: float, width: float, angle: float) -> void:
		var w := length * 0.5
		var h := width * 0.5
		var d := Vector2.from_angle(angle)
		var n := d.orthogonal()
		var pts := PackedVector2Array()
		for k in 5:
			pts.append(c - d * (w - (2.0 if k % 2 else 0.0)) + n * lerpf(-h, h, k / 4.0))
		for k in 5:
			pts.append(c + d * (w - (2.0 if k % 2 else 0.0)) + n * lerpf(h, -h, k / 4.0))
		ci.draw_colored_polygon(pts, TAPE)

# a strip of tape, drawn straight onto any canvas item (for containers, which would lay out
# a Tape child)
static func draw_tape(ci: CanvasItem, c: Vector2, length: float, width: float, tilt: float) -> void:
	Tape.paint(ci, c, length, width, tilt)

# a steel paper clip over the top edge of a page (`at` = its top end)
static func draw_clip(ci: CanvasItem, at: Vector2, angle: float) -> void:
	Sheet.clip(ci, at, angle)

# a rubber stamp: a double ring with a word across it, slightly crooked
class Stamp extends Control:
	var text := "GOLD":
		set(v):
			text = v
			queue_redraw()
	var col := Color("#c99a14"):
		set(v):
			col = v
			queue_redraw()
	var font: Font
	var tilt := -0.21

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	# stamped on as it appears: down big and fast, then still (after `delay` seconds)
	func thump(delay := 0.25) -> void:
		modulate.a = 0.0
		var tw := create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func():
			pivot_offset = size * 0.5
			scale = Vector2.ONE * 2.0
			modulate.a = 1.0)
		tw.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(self, "scale", Vector2.ONE * 1.06, 0.05)
		tw.tween_property(self, "scale", Vector2.ONE, 0.12)

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 2.0
		draw_circle(c, r, Color(col, 0.1))
		draw_arc(c, r, 0, TAU, 48, col, maxf(2.0, r * 0.07), true)
		draw_arc(c, r * 0.82, 0, TAU, 48, Color(col, 0.7), maxf(1.0, r * 0.03), true)
		if font == null:
			return
		var fs := int(r * (0.62 if text.length() <= 4 else 0.42))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_set_transform(c, tilt, Vector2.ONE)
		draw_string(font, Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# A roadbook "tulip": how a bend is drawn in rally notes. You come in from the bottom dot,
# the ice-blue tower sits inside the bend, the arrow points to the exit. `seed` varies it.
class Tulip extends Control:
	var seed := 0
	var col := INK

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var turns := [-60.0, 60.0, -120.0, 120.0, -90.0, 90.0, -150.0, 150.0]
		var ang := deg_to_rad(turns[seed % turns.size()])
		var lw := maxf(2.5, s * 0.08)
		var entry := c + Vector2(0, s * 0.42)
		var mid := c + Vector2(0, s * 0.02)
		var dir := Vector2(sin(ang), -cos(ang))
		var exit := mid + dir * s * 0.38
		draw_line(entry, mid, col, lw, true)
		draw_line(mid, exit, col, lw, true)
		draw_circle(mid, lw * 0.5, col)
		draw_circle(entry, lw * 0.9, col)
		var tip := exit + dir * s * 0.06
		var n := dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([tip + dir * s * 0.08, tip - dir * s * 0.06 + n * s * 0.1, tip - dir * s * 0.06 - n * s * 0.1]), col)
		# the tower on the inside of the bend
		var side := -1.0 if ang > 0.0 else 1.0
		var tw := mid + Vector2(side * s * 0.22, -s * 0.02)
		draw_circle(tw, s * 0.1, col)
		draw_circle(tw, s * 0.065, ACCENT)

# a word with a highlighter stroke behind it: put the label inside, the band is drawn first
static func highlight(l: Label) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	m.add_theme_constant_override("margin_left", 3)
	m.add_theme_constant_override("margin_right", 3)
	m.add_child(l)
	# the stroke is drawn on when the word appears, left to right, like a real highlighter
	m.set_meta("t", 0.0)
	m.draw.connect(func():
		var h := m.size.y
		m.draw_rect(Rect2(0, h * 0.42, m.size.x * float(m.get_meta("t")), h * 0.46), HL))
	m.tree_entered.connect(func():
		var tw := m.create_tween()
		tw.tween_interval(0.18)
		tw.tween_method(func(v: float): m.set_meta("t", v); m.queue_redraw(), 0.0, 1.0, 0.32).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT), CONNECT_ONE_SHOT)
	return m

# a numbered box down the left of a roadbook line (filled in ink on the current one)
class NumBox extends Control:
	var text := "1"
	var on := false
	var font: Font

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var r := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
		var lw := maxf(2.0, s * 0.07)
		if on:
			draw_rect(r, INK)
		else:
			draw_rect(r.grow(-lw * 0.5), INK, false, lw)
		if font:
			var fs := int(s * (0.5 if text.length() < 3 else 0.36))
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, r.get_center() + Vector2(-w * 0.5, fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PAPER if on else INK)

# a colour made for the dark HUD (gold, green, ice) inked dark enough to read on paper
static func ink_of(c: Color) -> Color:
	var lum := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	return c.darkened(clampf((lum - 0.35) / 0.65, 0.0, 0.6))
