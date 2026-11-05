# A one-line label whose digits all take the same width, so a ticking timer never
# shifts or resizes the HUD. The HUD fonts have no tabular figures, so each digit is drawn
# centred in a cell as wide as the widest digit. Its minimum width fits the widest of
# `templates`, so swapping "1st" for "2nd" or "--" for "0:41.20" keeps the chip still.
extends Control

var font: Font
var font_size := 20
var color := Color.WHITE
var templates: Array = []
var text := "":
	set(v):
		if v != text:
			text = v
			_fit()
			queue_redraw()

var _cell := 0.0

func setup(f: Font, size: int, col: Color, tpl: Array) -> void:
	font = f
	font_size = size
	color = col
	templates = tpl
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_cell = 0.0
	for d in "0123456789":
		_cell = maxf(_cell, font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	_fit()

func _char_w(ch: String) -> float:
	if ch >= "0" and ch <= "9":
		return _cell
	return font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

func text_width(s: String) -> float:
	var w := 0.0
	for ch in s:
		w += _char_w(ch)
	return w

func _fit() -> void:
	if font == null:
		return
	var w := text_width(text)
	for t in templates:
		w = maxf(w, text_width(String(t)))
	custom_minimum_size = Vector2(ceilf(w), ceilf(font.get_height(font_size)))

func _draw() -> void:
	if font == null or text == "":
		return
	# right-aligned, like a stopwatch
	var x := size.x - text_width(text)
	var y := (size.y - font.get_height(font_size)) * 0.5 + font.get_ascent(font_size)
	for ch in text:
		var cw := _char_w(ch)
		var gw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		draw_string(font, Vector2(x + (cw - gw) * 0.5, y), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += cw
