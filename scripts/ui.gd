# Menus, HUD, big centre text, results and minimap. Built in code so the layout
# adapts to any phone screen; styled after the prototype (dark panels, amber accent).
extends CanvasLayer

const TrackData = preload("res://scripts/track.gd")
const TrackMap = preload("res://scripts/track_map.gd")
const MenuScreens = preload("res://scripts/menu.gd")
const Medals = preload("res://scripts/medals.gd")
const Defs = preload("res://scripts/track_defs.gd")

signal again_pressed
signal menu_pressed
signal next_pressed

const MINIMAP := 110.0
const C_PANEL := Color(0.035, 0.075, 0.082, 0.92)
const C_FG := Color("#f3efe6")
const C_MUTED := Color("#9fb3b0")
const C_POST := Color("#f2b134")
const C_ASPHALT := Color("#393e46")

var f_display: Font = preload("res://fonts/Bungee-Regular.ttf")
var f_bold: Font = preload("res://fonts/ChakraPetch-Bold.ttf")
var f_med: Font = preload("res://fonts/ChakraPetch-Medium.ttf")

var root: Control
var menu: MenuScreens
var hud: HBoxContainer
var big: RichTextLabel
var minimap: TrackMap
var results: Control
var res_title: Label
var res_table: GridContainer
var res_note: Label
var hud_vals := {}
var next_btn: Button
var results_panel: PanelContainer

# The UI is laid out for a fixed number of logical pixels across the screen height, so it
# keeps the same physical size: about 450 on a phone (comfortable text and tap targets),
# a little more on tablets, 640 on desktop. --ui-h=<n> forces a value (screenshots).
static func ui_height() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-h="):
			return int(a.substr(7))
	var touch := OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	if not touch:
		return 640
	var h := 450.0
	var px := float(DisplayServer.screen_get_size().y)
	var dpi := float(DisplayServer.screen_get_dpi())
	if OS.has_feature("mobile") and dpi > 0.0 and px > 0.0:
		var inches := minf(px, float(DisplayServer.screen_get_size().x)) / dpi
		h = clampf(450.0 * inches / 2.7, 450.0, 640.0)  # phones are ~2.7 in tall in landscape
	return int(h)

var _uh := 450
var _win_size := Vector2i.ZERO

# The short side of the screen always gets ui_height() logical pixels, in landscape and portrait.
func _apply_scale() -> void:
	var ws := get_tree().root.size
	_win_size = ws
	var long_side := int(_uh * 16.0 / 9.0)
	get_tree().root.content_scale_size = Vector2i(_uh, long_side) if ws.y > ws.x else Vector2i(long_side, _uh)

func is_portrait() -> bool:
	var vp := root.get_viewport_rect().size if root else Vector2(16, 9)
	return vp.y > vp.x

func _ready() -> void:
	_uh = ui_height()
	_apply_scale()
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
	minimap.custom_minimum_size = Vector2(MINIMAP, MINIMAP)
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.visible = false
	root.add_child(minimap)

	menu = MenuScreens.new()
	root.add_child(menu)
	menu.setup(self)
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

func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	return g

var _laid_out_for := Vector2.ZERO

func _process(_dt: float) -> void:
	if get_tree().root.size != _win_size:
		_apply_scale()
	var vp := root.get_viewport_rect().size
	if vp != _laid_out_for:
		_laid_out_for = vp
		layout()
		if menu.visible:
			menu.refresh()

# HUD and minimap clear of notches and rounded corners
func layout() -> void:
	var ins := safe_insets()
	hud.offset_left = 12 + ins["l"]
	hud.offset_right = -12 - ins["r"]
	hud.offset_top = 8 + ins["t"]
	minimap.offset_right = -12 - ins["r"]
	minimap.offset_bottom = -12 - ins["b"]
	minimap.offset_left = minimap.offset_right - MINIMAP
	minimap.offset_top = minimap.offset_bottom - MINIMAP
	var vp := root.get_viewport_rect().size
	results_panel.custom_minimum_size.x = minf(440.0, vp.x - 40.0)

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
	results_panel = r[2]
	results_panel.custom_minimum_size.x = 440
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
	next_btn = Button.new()
	next_btn.text = "NEXT EVENT"
	next_btn.custom_minimum_size = Vector2(0, 50)
	_style_go(next_btn)
	next_btn.pressed.connect(func(): next_pressed.emit())
	vb.add_child(next_btn)
	var back := Button.new()
	back.text = "Back to menu"
	back.custom_minimum_size = Vector2(0, 46)
	back.pressed.connect(func(): menu_pressed.emit())
	vb.add_child(back)
	results.visible = false

# ---------------------------------------------------------------- menu state
func show_menu() -> void:
	menu.visible = true
	menu.refresh()
	results.visible = false
	hud.visible = false
	minimap.visible = false
	big.text = ""

# ---------------------------------------------------------------- HUD
func _chip(label: String, key: String, col: Color) -> void:
	var narrow := is_portrait()
	var pc := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = C_PANEL
	s.set_corner_radius_all(6)
	s.border_width_left = 4
	s.border_color = col
	s.content_margin_left = 10; s.content_margin_right = 10; s.content_margin_top = 4; s.content_margin_bottom = 4
	if narrow:
		s.content_margin_left = 7; s.content_margin_right = 7
	pc.add_theme_stylebox_override("panel", s)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6 if is_portrait() else 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := _label(label.to_upper(), 10 if narrow else 11, C_MUTED, f_bold)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	var v := _label("", 17 if narrow else 20, C_FG, f_bold)
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
		if race.humans == 1 or not is_portrait():  # no room for it between two players in portrait
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
	# shrink long words (FINISH, 2nd...) to fit a narrow portrait screen
	var room := root.get_viewport_rect().size.x * 0.9
	var w := f_display.get_string_size(bb, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if bb != "" and w > room:
		size = int(size * room / w)
	big.add_theme_font_size_override("normal_font_size", size)
	big.text = "[center]" + bb + "[/center]" if bb != "" else ""

# ---------------------------------------------------------------- results
func show_results(title: String, rows: Array, note: String, has_next := false, cols := 3) -> void:
	next_btn.visible = has_next
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
	t = snappedf(t, 0.1)
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%s%.1f" % [m, "0" if s < 9.995 else "", s]

static func fmt2(t: float) -> String:
	t = snappedf(t, 0.01)
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%s%.2f" % [m, "0" if s < 9.995 else "", s]
