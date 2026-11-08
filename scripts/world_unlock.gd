# "World unlocked": the full-screen moment after the run that finishes a campaign world.
# The race dims, a padlock shakes and springs open, the next world's picture opens out
# from the centre in a growing circle with a burst of sparks in its colour, the title
# lands, then what just opened is listed line by line. A tap (after a short beat) closes it.
# `step` fires at each beat so the game can play a sound and buzz.
extends Control

const Art = preload("res://scripts/menu_art.gd")

signal step(k: int)   # 0 lock shakes, 1 lock opens, 2 title, 3.. a line appears
signal closed

const ACCENT := { "snow": Color("#9fe3ff"), "forest": Color("#9ad13b"), "sand": Color("#f2b134"), "rock": Color("#ff8a4c") }

var _dim: ColorRect
var _pic: TextureRect
var _mat: ShaderMaterial
var _lock: Padlock
var _sparks: Sparks
var _title: Label
var _sub: Label
var _lines: VBoxContainer
var _tap: Label
var _can_close := false
var _tw: Tween

const REVEAL := """
shader_type canvas_item;
uniform float radius = 0.0;     // in units of the half-diagonal
uniform vec4 rim : source_color = vec4(1.0);
uniform float aspect = 1.0;
void fragment() {
	vec2 p = (SCREEN_UV - 0.5) * vec2(aspect, 1.0);
	float d = length(p) / length(vec2(aspect, 1.0) * 0.5);
	vec4 c = texture(TEXTURE, UV);
	float inside = 1.0 - smoothstep(radius - 0.01, radius, d);
	float ring = smoothstep(radius - 0.05, radius - 0.01, d) * inside;
	// the picture is darkened under the text band so the words stay readable
	float band = smoothstep(0.25, 0.75, SCREEN_UV.y) * 0.55;
	c.rgb = mix(c.rgb * (1.0 - band), rim.rgb, ring * 0.9);
	COLOR = vec4(c.rgb, c.a * inside);
}
"""

# ui: the game UI (fonts, safe insets); theme: the world whose picture opens;
# title / sub: the headline and the line under it; lines: what just opened
func setup(ui, pic: Texture2D, theme: String, title: String, sub: String, lines: Array) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var acc: Color = ACCENT.get(theme, Color("#f2b134"))
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.03, 0.05, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_pic = TextureRect.new()
	_pic.texture = pic
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = REVEAL
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("rim", acc)
	_pic.material = _mat
	add_child(_pic)
	_sparks = Sparks.new()
	_sparks.col = acc
	_sparks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sparks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sparks)
	_lock = Padlock.new()
	_lock.col = acc
	_lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lock)
	# the words, low on the screen
	var ins: Dictionary = ui.safe_insets()
	var box := VBoxContainer.new()
	box.anchor_left = 0.0; box.anchor_right = 1.0; box.anchor_top = 1.0; box.anchor_bottom = 1.0
	box.offset_left = 24 + ins["l"]; box.offset_right = -24 - ins["r"]
	box.offset_bottom = -26 - ins["b"]
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_sub = ui._label(sub.to_upper(), 16, Color("#e6f1f8"), ui.f_bold)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.modulate.a = 0.0
	box.add_child(_sub)
	_title = ui._label(title.to_upper(), 46 if ui.is_portrait() else 60, acc, ui.f_display)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_title.add_theme_constant_override("shadow_offset_y", 3)
	_title.modulate.a = 0.0
	box.add_child(_title)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_lines)
	for t in lines:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Art.Icon.new()
		ic.kind = "check"
		ic.col = acc
		ic.custom_minimum_size = Vector2(20, 20)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
		var l: Label = ui._label(t, 16, Color("#f3efe6"), ui.f_bold)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(l)
		row.modulate.a = 0.0
		_lines.add_child(row)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	box.add_child(gap)
	_tap = ui._label("TAP TO CONTINUE", 13, Color("#9fb3b0"), ui.f_bold)
	_tap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tap.modulate.a = 0.0
	box.add_child(_tap)
	_play.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _mat:
		_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
		_place_lock()

func _place_lock() -> void:
	var s := minf(size.x, size.y) * 0.26
	_lock.size = Vector2(s, s)
	_lock.position = Vector2(size.x * 0.5 - s * 0.5, size.y * 0.36 - s * 0.5)
	_lock.pivot_offset = _lock.size * 0.5

func _play() -> void:
	_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
	_place_lock()
	_sparks.origin = _lock.position + _lock.size * 0.5
	_lock.scale = Vector2.ONE * 0.2
	_lock.modulate.a = 0.0
	_tw = create_tween()
	_tw.tween_property(_dim, "color:a", 0.82, 0.35)
	_tw.parallel().tween_property(_lock, "modulate:a", 1.0, 0.3)
	_tw.parallel().tween_property(_lock, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# the lock rattles...
	_tw.tween_callback(func(): step.emit(0))
	for k in 6:
		_tw.tween_property(_lock, "rotation", 0.16 * (1 if k % 2 == 0 else -1) * (1.0 - k / 7.0), 0.05)
	_tw.tween_property(_lock, "rotation", 0.0, 0.05)
	# ...and springs open: sparks, and the picture opens out from it
	_tw.tween_callback(func(): step.emit(1); _sparks.burst())
	_tw.tween_property(_lock, "open", 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_method(func(r): _mat.set_shader_parameter("radius", r), 0.0, 1.05, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tw.parallel().tween_property(_lock, "scale", Vector2.ONE * 1.25, 0.9)
	_tw.parallel().tween_property(_lock, "modulate:a", 0.0, 0.9).set_delay(0.3)
	# the title lands
	_tw.tween_callback(func(): step.emit(2); _title.pivot_offset = _title.size * 0.5; _title.scale = Vector2.ONE * 1.6)
	_tw.tween_property(_title, "modulate:a", 1.0, 0.18)
	_tw.parallel().tween_property(_title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(_sub, "modulate:a", 1.0, 0.4)
	for i in _lines.get_child_count():
		var row: Control = _lines.get_child(i)
		_tw.tween_interval(0.12)
		_tw.tween_callback(func(): step.emit(3 + i))
		_tw.tween_property(row, "modulate:a", 1.0, 0.2)
	_tw.tween_callback(func(): _can_close = true)
	_tw.tween_property(_tap, "modulate:a", 1.0, 0.3)

func _gui_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed
	if tap:
		accept_event()
		if not _can_close:   # a tap during the show skips to its end
			if _tw:
				_tw.custom_step(30.0)
			return
		_close()

func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and _can_close:
		_close()

func _close() -> void:
	_can_close = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func(): closed.emit(); queue_free())

# A padlock; `open` lifts and swings the shackle (0 shut, 1 open)
class Padlock extends Control:
	var col := Color("#f2b134")
	var open := 0.0:
		set(v):
			open = v
			queue_redraw()

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var lw := s * 0.09
		# the shackle: lifted and turned about its right foot as it opens
		var foot := c + Vector2(s * 0.2, -s * 0.02)
		draw_set_transform(foot + Vector2(0, -s * 0.16 * open), -0.7 * open, Vector2.ONE)
		var pts := PackedVector2Array()
		for k in 21:
			var a := PI + PI * k / 20.0
			pts.append(Vector2(-s * 0.2, -s * 0.16) + Vector2(cos(a), sin(a)) * s * 0.2)
		pts.insert(0, Vector2(-s * 0.4, 0))
		pts.append(Vector2(0, 0))
		draw_polyline(pts, Color("#c9d3d6"), lw, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# the body
		var body := Rect2(c + Vector2(-s * 0.3, -s * 0.06), Vector2(s * 0.6, s * 0.46))
		draw_rect(body.grow(s * 0.02), col.darkened(0.45))
		draw_rect(body, col)
		draw_rect(Rect2(body.position, Vector2(body.size.x, s * 0.06)), col.lightened(0.35))
		draw_circle(c + Vector2(0, s * 0.12), s * 0.06, col.darkened(0.6))
		draw_rect(Rect2(c + Vector2(-s * 0.025, s * 0.13), Vector2(s * 0.05, s * 0.13)), col.darkened(0.6))

# A one-off burst of sparks flying out from `origin`, slowing and fading
class Sparks extends Control:
	var col := Color.WHITE
	var origin := Vector2.ZERO
	var _p: Array = []   # [pos, vel, life, size]

	func burst() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var s := minf(size.x, size.y)
		for k in 70:
			var a := rng.randf() * TAU
			var v := Vector2.from_angle(a) * s * rng.randf_range(0.5, 1.4)
			_p.append([origin, v, rng.randf_range(0.6, 1.2), rng.randf_range(2.0, 5.0)])

	func _process(dt: float) -> void:
		if _p.is_empty():
			return
		for p in _p:
			p[0] += p[1] * dt
			p[1] *= exp(-2.6 * dt)
			p[2] -= dt
		_p = _p.filter(func(p): return p[2] > 0.0)
		queue_redraw()

	func _draw() -> void:
		for p in _p:
			var a := clampf(p[2], 0.0, 1.0)
			draw_circle(p[0], p[3], Color(col, a))
			draw_circle(p[0], p[3] * 0.5, Color(1, 1, 1, a))
