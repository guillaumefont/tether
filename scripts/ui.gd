# Menus, HUD, big centre text, results and minimap. Built in code so the layout
# adapts to any phone screen; styled after the prototype (dark panels, amber accent).
extends CanvasLayer

const TrackData = preload("res://scripts/track.gd")
const TrackMap = preload("res://scripts/track_map.gd")
const Defs = preload("res://scripts/track_defs.gd")

signal start_pressed
signal again_pressed
signal menu_pressed
signal track_picked(i: int)
signal variant_picked(v: String)
signal mode_picked(m: String)
signal players_picked(n: int)
signal sound_toggled(on: bool)

const C_PANEL := Color(0.035, 0.075, 0.082, 0.92)
const C_FG := Color("#f3efe6")
const C_MUTED := Color("#9fb3b0")
const C_POST := Color("#f2b134")
const C_ASPHALT := Color("#393e46")

var f_display: Font = preload("res://fonts/Bungee-Regular.ttf")
var f_bold: Font = preload("res://fonts/ChakraPetch-Bold.ttf")
var f_med: Font = preload("res://fonts/ChakraPetch-Medium.ttf")

var root: Control
var menu: Control
var results: Control
var hud: HBoxContainer
var big: RichTextLabel
var minimap: TrackMap
var side: PanelContainer
var swipe_area: Control
var swipe_hint: Label
var track_name: Label
var track_note: Label
var track_count: Label
var track_rec: Label
var cur_track := 0
var _swipe_from := Vector2.ZERO
var _swiping := false
var variant_row: GridContainer
var mode_row: GridContainer
var player_row: GridContainer
var players_label: Label
var sound_btn: Button
var res_title: Label
var res_table: GridContainer
var res_note: Label
var hud_vals := {}

func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)

	hud = HBoxContainer.new()
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = 16; hud.offset_right = -16; hud.offset_top = 10
	hud.add_theme_constant_override("separation", 8)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)

	big = RichTextLabel.new()
	big.set_anchors_preset(Control.PRESET_FULL_RECT)
	big.bbcode_enabled = true
	big.fit_content = false
	big.scroll_active = false
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_override("normal_font", f_display)
	big.add_theme_font_size_override("normal_font_size", 120)
	big.add_theme_color_override("default_color", C_POST)
	big.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	big.add_theme_constant_override("shadow_offset_y", 6)
	big.add_theme_constant_override("shadow_offset_x", 0)
	root.add_child(big)

	minimap = TrackMap.new()
	minimap.bg = true
	minimap.custom_minimum_size = Vector2(140, 140)
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.offset_left = -156; minimap.offset_top = -156; minimap.offset_right = -16; minimap.offset_bottom = -16
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.visible = false
	root.add_child(minimap)

	_build_menu()
	_build_results()

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = f_med
	t.default_font_size = 16
	var sb := func(bg: Color, border := Color.TRANSPARENT, bw := 0) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.set_corner_radius_all(6)
		s.content_margin_left = 12; s.content_margin_right = 12
		s.content_margin_top = 8; s.content_margin_bottom = 8
		if bw > 0:
			s.border_color = border
			s.set_border_width_all(bw)
		return s
	t.set_stylebox("normal", "Button", sb.call(C_ASPHALT, Color.TRANSPARENT, 2))
	t.set_stylebox("hover", "Button", sb.call(C_ASPHALT.lightened(0.08), Color.TRANSPARENT, 2))
	t.set_stylebox("pressed", "Button", sb.call(C_ASPHALT, C_POST, 2))
	t.set_stylebox("hover_pressed", "Button", sb.call(C_ASPHALT.lightened(0.08), C_POST, 2))
	t.set_stylebox("focus", "Button", sb.call(Color.TRANSPARENT, C_FG, 2))
	t.set_font("font", "Button", f_bold)
	t.set_font_size("font_size", "Button", 16)
	t.set_color("font_color", "Button", C_FG)
	t.set_color("font_pressed_color", "Button", C_FG)
	t.set_color("font_hover_color", "Button", C_FG)
	t.set_color("font_hover_pressed_color", "Button", C_FG)
	t.set_color("font_focus_color", "Button", C_FG)
	var panel: StyleBoxFlat = sb.call(C_PANEL)
	panel.set_corner_radius_all(10)
	panel.content_margin_left = 20; panel.content_margin_right = 20
	panel.content_margin_top = 20; panel.content_margin_bottom = 20
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 24
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", C_FG)
	return t

func _label(text: String, size := 16, col := C_FG, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font:
		l.add_theme_font_override("font", font)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _caps(text: String) -> Label:
	var l := _label(text.to_upper(), 12, C_MUTED, f_bold)
	return l

func _overlay() -> Array:
	var ov := ColorRect.new()
	ov.color = Color(0.024, 0.055, 0.06, 0.5)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(ov)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(center)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	center.add_child(margin)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 560
	margin.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	return [ov, vb, panel]

func _choice(text: String, sub: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = group
	b.text = ""
	b.custom_minimum_size = Vector2(120, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 12; vb.offset_top = 6; vb.offset_right = -12; vb.offset_bottom = -6
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_label(text, 16, C_FG, f_bold))
	vb.add_child(_label(sub, 12, C_MUTED))
	b.add_child(vb)
	return b

func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	return g

# One landscape screen, nothing to scroll: a side panel with every choice and a big
# Start button, and the selected track live in 3D on the right (swipe there to change track).
const PANEL_W := 420.0
const VARIANT_SUBS := {
	"standard": "plain layout", "reverse": "other way round",
	"obstacles": "breakable posts, +1 s", "collect": "gem line, +0.25 s per miss",
}

func _build_menu() -> void:
	menu = Control.new()
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu)
	# swipe catcher over the 3D preview
	swipe_area = Control.new()
	swipe_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	swipe_area.mouse_filter = Control.MOUSE_FILTER_PASS
	swipe_area.gui_input.connect(_on_swipe_input)
	menu.add_child(swipe_area)

	side = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL
	ps.set_corner_radius_all(14)
	ps.content_margin_left = 20; ps.content_margin_right = 20
	ps.content_margin_top = 16; ps.content_margin_bottom = 16
	ps.shadow_color = Color(0, 0, 0, 0.45)
	ps.shadow_size = 24
	side.add_theme_stylebox_override("panel", ps)
	menu.add_child(side)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	side.add_child(vb)

	var title_row := HBoxContainer.new()
	var title := _label("PIVOT RUSH", 40, C_POST, f_display)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	sound_btn = Button.new()
	sound_btn.toggle_mode = true
	sound_btn.button_pressed = true
	sound_btn.text = "SOUND ON"
	sound_btn.custom_minimum_size = Vector2(112, 44)
	sound_btn.add_theme_font_size_override("font_size", 13)
	sound_btn.toggled.connect(func(on: bool):
		sound_btn.text = "SOUND ON" if on else "SOUND OFF"
		sound_toggled.emit(on))
	title_row.add_child(sound_btn)
	vb.add_child(title_row)
	vb.add_child(_label("Hold to hook the tower ahead, let go to slide out.", 14, C_MUTED))

	# track picker: big arrows either side of the name
	var picker := HBoxContainer.new()
	picker.add_theme_constant_override("separation", 8)
	var prev := _arrow("<")
	prev.pressed.connect(func(): track_picked.emit(posmod(cur_track - 1, Defs.TRACKS.size())))
	picker.add_child(prev)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track_count = _label("", 12, C_MUTED, f_bold)
	track_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(track_count)
	track_name = _label("", 26, C_FG, f_bold)
	track_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	track_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(track_name)
	track_note = _label("", 13, C_MUTED)
	track_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(track_note)
	picker.add_child(mid)
	var nxt := _arrow(">")
	nxt.pressed.connect(func(): track_picked.emit(posmod(cur_track + 1, Defs.TRACKS.size())))
	picker.add_child(nxt)
	vb.add_child(picker)
	track_rec = _label("", 15, C_POST, f_bold)
	track_rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(track_rec)

	vb.add_child(_caps("Variant"))
	variant_row = _grid(2)
	var vg := ButtonGroup.new()
	for v in Defs.VARIANTS:
		var b := _choice(v[1], VARIANT_SUBS.get(v[0], v[2]), vg)
		b.set_meta("key", v[0])
		b.pressed.connect(func(): variant_picked.emit(v[0]))
		variant_row.add_child(b)
	vb.add_child(variant_row)
	vb.add_child(_caps("Mode"))
	mode_row = _grid(2)
	var mg := ButtonGroup.new()
	for m in [["trial", "Time trial", "solo vs your ghost"], ["race", "Race", "vs AI rivals"]]:
		var b := _choice(m[1], m[2], mg)
		b.set_meta("key", m[0])
		b.pressed.connect(func(): mode_picked.emit(m[0]))
		mode_row.add_child(b)
	vb.add_child(mode_row)
	players_label = _caps("Players on this device")
	vb.add_child(players_label)
	player_row = _grid(2)
	var pg := ButtonGroup.new()
	for n in [1, 2]:
		var b := _choice("%d player%s" % [n, "s" if n > 1 else ""], "vs 3 rivals" if n == 1 else "split screen halves", pg)
		b.set_meta("key", n)
		b.pressed.connect(func(): players_picked.emit(n))
		player_row.add_child(b)
	vb.add_child(player_row)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(fill)
	var go := Button.new()
	go.text = "START"
	go.custom_minimum_size = Vector2(0, 64)
	_style_go(go)
	go.add_theme_font_size_override("font_size", 28)
	go.pressed.connect(func(): start_pressed.emit())
	vb.add_child(go)

	# swipe hint on the preview side
	swipe_hint = _label("Swipe to change track", 14, Color(C_FG, 0.7), f_bold)
	swipe_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	menu.add_child(swipe_hint)
	layout_menu()

var _laid_out_for := Vector2.ZERO

# re-lay the screen whenever the viewport size changes (rotation, window resize, first frame)
func _process(_dt: float) -> void:
	# also every frame while the menu shows: wrapped labels can briefly report a tall
	# minimum size on the first layout pass, and a Control never shrinks back on its own
	if root.get_viewport_rect().size != _laid_out_for or (menu and menu.visible):
		layout_menu()

func _arrow(t: String) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(64, 64)
	b.add_theme_font_override("font", f_display)
	b.add_theme_font_size_override("font_size", 28)
	b.add_theme_color_override("font_color", C_POST)
	b.add_theme_color_override("font_hover_color", C_POST)
	b.add_theme_color_override("font_pressed_color", C_POST)
	return b

# keep clear of notches / rounded corners
func safe_insets() -> Dictionary:
	var ins := { "l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0 }
	if not OS.has_feature("mobile"):
		return ins
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var vp := root.get_viewport_rect().size
	if win.x <= 0 or win.y <= 0:
		return ins
	var k := vp.x / float(win.x)
	ins["l"] = maxf(0.0, safe.position.x) * k
	ins["t"] = maxf(0.0, safe.position.y) * k
	ins["r"] = maxf(0.0, win.x - safe.end.x) * k
	ins["b"] = maxf(0.0, win.y - safe.end.y) * k
	return ins

func layout_menu() -> void:
	if side == null:
		return
	var vp := root.get_viewport_rect().size
	_laid_out_for = vp
	var ins := safe_insets()
	var m := 16.0
	var w := minf(PANEL_W, vp.x * 0.5)
	side.position = Vector2(m + ins["l"], m + ins["t"])
	side.custom_minimum_size = Vector2(w, 0)
	side.size = Vector2(w, vp.y - 2 * m - ins["t"] - ins["b"])
	var right_x: float = side.position.x + w
	swipe_hint.position = Vector2(right_x + (vp.x - right_x) * 0.5 - 85.0, vp.y - 44.0 - ins["b"])
	hud.offset_left = 16 + ins["l"]
	hud.offset_right = -16 - ins["r"]
	minimap.offset_right = -16 - ins["r"]
	minimap.offset_left = minimap.offset_right - 140

# how many screen pixels on the left the menu covers (the camera frames the track beside it)
func menu_cover_px() -> float:
	if not menu.visible or side == null:
		return 0.0
	return side.position.x + side.size.x

func _on_swipe_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT):
		if e.pressed:
			_swipe_from = e.position
			_swiping = true
		elif _swiping:
			_swiping = false
			var d: Vector2 = e.position - _swipe_from
			if absf(d.x) > 60.0 and absf(d.x) > absf(d.y):
				track_picked.emit(posmod(cur_track + (-1 if d.x > 0 else 1), Defs.TRACKS.size()))

func _style_go(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = C_POST if st == "normal" else C_POST.lightened(0.1)
		s.set_corner_radius_all(6)
		s.content_margin_top = 10; s.content_margin_bottom = 10
		b.add_theme_stylebox_override(st, s)
	b.add_theme_font_override("font", f_display)
	b.add_theme_font_size_override("font_size", 22)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(c, Color("#1a1408"))

func _build_results() -> void:
	var r := _overlay()
	results = r[0]
	var vb: VBoxContainer = r[1]
	(r[2] as PanelContainer).custom_minimum_size.x = 440
	res_title = _label("Finish", 30, C_POST, f_display)
	vb.add_child(res_title)
	res_table = _grid(3)
	res_table.add_theme_constant_override("h_separation", 16)
	vb.add_child(res_table)
	res_note = _label("", 14, C_MUTED)
	vb.add_child(res_note)
	var again := Button.new()
	again.text = "RACE AGAIN"
	again.custom_minimum_size = Vector2(0, 50)
	_style_go(again)
	again.pressed.connect(func(): again_pressed.emit())
	vb.add_child(again)
	var back := Button.new()
	back.text = "Change track or players"
	back.custom_minimum_size = Vector2(0, 46)
	back.pressed.connect(func(): menu_pressed.emit())
	vb.add_child(back)
	results.visible = false

# ---------------------------------------------------------------- menu state
func refresh_menu(track_idx: int, variant: String, mode: String, humans: int, records: Array) -> void:
	cur_track = track_idx
	var d: Dictionary = Defs.TRACKS[track_idx]
	track_count.text = "TRACK %d / %d" % [track_idx + 1, Defs.TRACKS.size()]
	track_name.text = d["name"]
	track_note.text = d["note"]
	var rec: float = records[track_idx]
	track_rec.text = "%d laps  ·  %s" % [int(d.get("laps", 3)), ("record " + fmt2(rec)) if rec > 0.0 else "no record yet"]
	for b in variant_row.get_children():
		b.set_pressed_no_signal(b.get_meta("key") == variant)
	for b in mode_row.get_children():
		b.set_pressed_no_signal(b.get_meta("key") == mode)
	for b in player_row.get_children():
		b.set_pressed_no_signal(b.get_meta("key") == humans)
	players_label.visible = mode != "trial"
	player_row.visible = mode != "trial"
	layout_menu()

func show_menu() -> void:
	menu.visible = true
	results.visible = false
	hud.visible = false
	minimap.visible = false
	big.text = ""

# ---------------------------------------------------------------- HUD
func _chip(label: String, key: String, col: Color) -> void:
	var pc := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = C_PANEL
	s.set_corner_radius_all(6)
	s.border_width_left = 4
	s.border_color = col
	s.content_margin_left = 10; s.content_margin_right = 10; s.content_margin_top = 4; s.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", s)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(label.to_upper(), 11, C_MUTED, f_bold)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	var v := _label("", 20, C_FG, f_bold)
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(v)
	pc.add_child(hb)
	hud.add_child(pc)
	hud_vals[key] = v

func _spacer() -> void:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(c)

func build_hud(race, gems: bool) -> void:
	for ch in hud.get_children():
		ch.queue_free()
	hud_vals.clear()
	if race.mode == "trial":
		_chip("Lap", "lap0", C_POST)
		_chip("Lap time", "time", C_POST)
		if gems:
			_chip("Gems", "gems", Color("#7fe3d0"))
		_spacer()
		_chip("Record", "rec", C_POST)
	else:
		var hs: Array = race.cars.filter(func(c): return c.human >= 0)
		_chip("P1" if race.humans > 1 else "Lap", "lap0", hs[0].color)
		_chip("Pos", "pos0", hs[0].color)
		_spacer()
		_chip("Time", "time", C_POST)
		if gems:
			_chip("Gems", "gems", Color("#7fe3d0"))
		if race.humans > 1:
			_spacer()
			_chip("P2", "lap1", hs[1].color)
			_chip("Pos", "pos1", hs[1].color)
	hud.visible = true
	minimap.visible = true
	menu.visible = false
	results.visible = false

func set_hud(key: String, text: String) -> void:
	if hud_vals.has(key):
		hud_vals[key].text = text

func set_big(bb: String, size := 120) -> void:
	big.add_theme_font_size_override("normal_font_size", size)
	big.text = "[center]" + bb + "[/center]" if bb != "" else ""

# ---------------------------------------------------------------- results
func show_results(title: String, rows: Array, note: String, cols := 3) -> void:
	res_title.text = title
	for ch in res_table.get_children():
		ch.queue_free()
	res_table.columns = cols
	for row in rows:
		var hl: bool = row.get("hl", false)
		var cells: Array = row["cells"]
		for k in cells.size():
			var l := _label(str(cells[k]), 16, C_POST if hl else C_FG, f_bold if hl else f_med)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			if k == cells.size() - 1:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if row.has("color") and k == 1:
				l.add_theme_color_override("font_color", row["color"])
			res_table.add_child(l)
	res_note.text = note
	results.visible = true
	hud.visible = false
	minimap.visible = false
	big.text = ""

static func fmt(t: float) -> String:
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%s%.1f" % [m, "0" if s < 10.0 else "", s]

static func fmt2(t: float) -> String:
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%s%.2f" % [m, "0" if s < 10.0 else "", s]
