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
var track_grid: GridContainer
var variant_row: GridContainer
var mode_row: GridContainer
var player_row: GridContainer
var players_label: Label
var controls_note: Label
var sound_btn: Button
var res_title: Label
var res_table: GridContainer
var res_note: Label
var hud_vals := {}
var thumbs: Array = []
var track_btns: Array = []
var _thumb_cache := {}

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
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ov.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
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

func _build_menu() -> void:
	var r := _overlay()
	menu = r[0]
	var vb: VBoxContainer = r[1]
	vb.add_child(_label("PIVOT RUSH", 48, C_POST, f_display))
	vb.add_child(_label("Your car only drives straight. Hook a spinning tower, let the tether whip you round the bend, then let go and slide out down the next stretch."))
	vb.add_child(_label("Hold to hook the nearest tower ahead, release to let go. The tether never gets longer than when you grabbed, and it takes up any slack if you swing in closer, so your line is set by when you grab. Hit a jump ramp at speed to clear the gap, or you drop in and restart behind it.", 14, C_MUTED))
	vb.add_child(_caps("Track"))
	track_grid = _grid(4)
	var tg := ButtonGroup.new()
	for i in Defs.TRACKS.size():
		var d: Dictionary = Defs.TRACKS[i]
		var b := Button.new()
		b.toggle_mode = true
		b.button_group = tg
		b.custom_minimum_size = Vector2(120, 168)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.offset_left = 8; box.offset_top = 8; box.offset_right = -8; box.offset_bottom = -8
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var th := TrackMap.new()
		th.custom_minimum_size = Vector2(96, 96)
		th.size_flags_vertical = Control.SIZE_EXPAND_FILL
		th.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(th)
		box.add_child(_label(d["name"], 15, C_FG, f_bold))
		var note := _label(d["note"], 12, C_MUTED)
		box.add_child(note)
		b.add_child(box)
		b.set_meta("note", note)
		b.pressed.connect(func(): track_picked.emit(i))
		track_grid.add_child(b)
		track_btns.append(b)
		thumbs.append(th)
	vb.add_child(track_grid)
	vb.add_child(_caps("Variant"))
	variant_row = _grid(2)
	var vg := ButtonGroup.new()
	for v in Defs.VARIANTS:
		var b := _choice(v[1], v[2], vg)
		b.set_meta("key", v[0])
		b.pressed.connect(func(): variant_picked.emit(v[0]))
		variant_row.add_child(b)
	vb.add_child(variant_row)
	vb.add_child(_caps("Mode"))
	mode_row = _grid(2)
	var mg := ButtonGroup.new()
	for m in [["trial", "Time trial", "solo vs your ghost, sets records"], ["race", "Race", "vs 3 rivals"]]:
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
		var b := _choice("%d player%s" % [n, "s" if n > 1 else ""], "vs 3 rivals" if n == 1 else "vs 2 rivals", pg)
		b.set_meta("key", n)
		b.pressed.connect(func(): players_picked.emit(n))
		player_row.add_child(b)
	vb.add_child(player_row)
	controls_note = _label("", 14, C_MUTED)
	vb.add_child(controls_note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var go := Button.new()
	go.text = "START"
	go.custom_minimum_size = Vector2(0, 52)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_go(go)
	go.pressed.connect(func(): start_pressed.emit())
	row.add_child(go)
	sound_btn = Button.new()
	sound_btn.text = "Sound on"
	sound_btn.toggle_mode = true
	sound_btn.button_pressed = true
	sound_btn.custom_minimum_size = Vector2(130, 52)
	sound_btn.toggled.connect(func(on: bool):
		sound_btn.text = "Sound on" if on else "Sound off"
		sound_toggled.emit(on))
	row.add_child(sound_btn)
	vb.add_child(row)

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
func thumb_track(i: int) -> TrackData:
	if not _thumb_cache.has(i):
		_thumb_cache[i] = TrackData.new(Defs.TRACKS[i], "standard")
	return _thumb_cache[i]

func refresh_menu(track_idx: int, variant: String, mode: String, humans: int, records: Array) -> void:
	var w := root.get_viewport_rect().size.x
	track_grid.columns = 4 if w >= 620 else 3 if w >= 460 else 2
	for i in track_btns.size():
		var b: Button = track_btns[i]
		b.set_pressed_no_signal(i == track_idx)
		var rec: float = records[i]
		(b.get_meta("note") as Label).text = ("Record " + fmt(rec)) if rec > 0.0 else Defs.TRACKS[i]["note"]
		if thumbs[i].track == null:
			thumbs[i].set_track(thumb_track(i))
	for b in variant_row.get_children():
		b.set_pressed_no_signal(b.get_meta("key") == variant)
	for b in mode_row.get_children():
		b.set_pressed_no_signal(b.get_meta("key") == mode)
	for b in player_row.get_children():
		b.set_pressed_no_signal(b.get_meta("key") == humans)
	players_label.visible = mode != "trial"
	player_row.visible = mode != "trial"
	if humans == 1 or mode == "trial":
		controls_note.text = "Touch and hold anywhere to hook, let go to release. Keyboard: hold Space."
	else:
		controls_note.text = "Player 1: left half of the screen or Space. Player 2: right half or Enter. The camera zooms out to keep you both in view."

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
