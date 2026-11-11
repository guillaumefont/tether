# A row of four medals (bronze, silver, gold, pivot) with the target under each.
# Each medal is a small rotor disc like the towers: lit once earned, a dim outline otherwise.
extends Control

const Medals = preload("res://scripts/medals.gd")

var earned := 0              # 0..4
var labels: Array = ["", "", "", ""]
var font: Font
var font_size := 13
var ink := false           # on the roadbook paper: darker outlines and labels
var compact := false       # small dots only, no labels (cards)

func set_state(e: int, l: Array) -> void:
	earned = e
	labels = l
	queue_redraw()

func _draw() -> void:
	var n := 4
	var slot := size.x / n
	var r := minf(slot * 0.22, (size.y - font_size - 6) * 0.5)
	if compact:
		r = size.y * 0.42
		slot = r * 2.6
	for i in n:
		var c := Vector2(slot * (i + 0.5), r + 1)
		if compact:
			c = Vector2(r + 1 + slot * i, size.y * 0.5)
		var col: Color = Medals.COLORS[i]
		var lit := earned > i
		if lit:
			draw_circle(c, r, col.darkened(0.35))
			draw_circle(c, r * 0.8, col)
			# rotor blades, the game's tower motif
			for k in 3:
				var a := TAU * k / 3.0 + 0.4
				draw_line(c, c + Vector2.from_angle(a) * r * 0.62, col.darkened(0.45), maxf(2.0, r * 0.22), true)
			draw_circle(c, r * 0.2, col.lightened(0.4))
		else:
			draw_arc(c, r * 0.9, 0, TAU, 32, Color(col.darkened(0.35), 0.75) if ink else Color(col, 0.45), maxf(1.5, r * 0.12), true)
		if font and not compact:
			var t: String = labels[i]
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			draw_string(font, Vector2(c.x - w * 0.5, r * 2 + 4 + font_size), t, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
				(col.darkened(0.4) if lit else Color("#56636e")) if ink else (col if lit else Color(0.62, 0.7, 0.69)))
