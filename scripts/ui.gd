# Menus, HUD, big centre text, results and minimap. Built in code so the layout
# adapts to any phone screen; styled after the prototype (dark panels, amber accent).
extends CanvasLayer

const TrackData = preload("res://scripts/track.gd")
const TrackMap = preload("res://scripts/track_map.gd")
const MenuScreens = preload("res://scripts/menu.gd")
const Medals = preload("res://scripts/medals.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Art = preload("res://scripts/menu_art.gd")
const Campaign = preload("res://scripts/campaign.gd")
const MonoLabel = preload("res://scripts/mono_label.gd")

const TIPS := [
	"Hook the tower as you enter the bend, let go when your nose points down the exit.",
	"Rubbing the rail cuts your throttle. Let go a touch earlier to stay off it.",
	"Every bend has its own tower. The rope keeps its length, so grab timing sets your line.",
	"After you let go the car slides a little on the ice. Aim for it.",
	"Beat a medal time to unlock the next campaign event.",
	"In Collect, the gems trace the ideal line. Each one missed costs a quarter second.",
	"Posts shatter when you hit them, and cost you a second.",
]

signal again_pressed
signal menu_pressed
signal next_pressed
signal pause_pressed
signal pause_action(what: String)   # resume | restart | exit
# music_vol / sfx_vol (0..100), ghost / effects (bool)
signal option_changed(key: String, value)

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
var hud_tags := {}   # key -> [tag Label, chip StyleBoxFlat]
var next_btn: Button
var res_again: Button
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
	_build_pause()
	_build_settings()
	_build_loading()

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
	if pause_panel:
		pause_panel.custom_minimum_size.x = minf(440.0, vp.x - 40.0)
	if settings_panel:
		settings_panel.custom_minimum_size.x = minf(440.0, vp.x - 40.0)
	if _load_box:
		_place_loading()

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

# ---------------------------------------------------------------- icon buttons
const C_INK := Color("#1a1408")
const C_TILE := Color(0.05, 0.11, 0.17, 0.82)
const C_FROST := Color(0.86, 0.93, 0.98, 0.55)

# A big touch target with a drawn icon and an optional short label: the label sits under
# the icon (tile) or beside it. look: "go" (amber, the main action) or "card" (frosted).
func icon_button(icon: String, text := "", look := "card", tile := true, h := 64) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(h, h)
	b.tooltip_text = text.capitalize()
	b.set_meta("look", look)
	var box: BoxContainer = VBoxContainer.new() if tile else HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0 if tile else 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Art.Icon.new()
	ic.kind = icon
	var isz := h * (0.46 if tile and text != "" else 0.5)
	ic.custom_minimum_size = Vector2(isz, isz)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	b.set_meta("icon", ic)
	if text != "":
		var big_row := look == "go" and not tile
		var l := _label(text, 22 if big_row else 13, C_FG, f_display if big_row else f_bold)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(l)
		b.set_meta("label", l)
		if not tile:   # wide enough for icon + label
			var w := l.get_minimum_size().x + isz + 10.0 + 28.0
			b.custom_minimum_size.x = maxf(h, w)
	b.add_child(box)
	_tile_look(b, look, false)
	return b

# selected state for a toggle tile (variant picker, Ghost / Effects)
func set_tile_on(b: Button, on: bool) -> void:
	_tile_look(b, b.get_meta("look"), on)

func _tile_look(b: Button, look: String, on: bool) -> void:
	var go := look == "go"
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sbx := StyleBoxFlat.new()
		sbx.set_corner_radius_all(12)
		sbx.shadow_color = Color(0, 0, 0, 0.25)
		sbx.shadow_size = 5
		sbx.shadow_offset = Vector2(0, 2)
		var lit: bool = st.begins_with("hover") or st.contains("pressed")
		if go:
			sbx.bg_color = C_POST.lightened(0.12) if lit else C_POST
			sbx.border_color = Color(1, 1, 1, 0.5)
			sbx.border_width_top = 3
		else:
			sbx.bg_color = C_TILE.lightened(0.07) if lit else C_TILE
			if on:
				sbx.bg_color = Color(0.25, 0.2, 0.08, 0.9)
			sbx.border_color = C_POST if (on or st.contains("pressed")) else Color(C_FROST, 0.4)
			sbx.set_border_width_all(3 if on else 2)
			if not on:
				sbx.border_width_top = 4   # a rim of frost along the top, like the menu cards
		if st == "disabled":
			sbx.bg_color = Color(sbx.bg_color, 0.45)
		b.add_theme_stylebox_override(st, sbx)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := C_INK if go else C_POST
	var ic: Art.Icon = b.get_meta("icon")
	ic.col = ink
	ic.col2 = C_INK.lightened(0.2) if go else Art.C_ICE
	if b.has_meta("label"):
		var l: Label = b.get_meta("label")
		l.add_theme_color_override("font_color", C_INK if go else (C_POST if on else C_FG))

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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var back := icon_button("home", "MENU", "card")
	back.pressed.connect(func(): menu_pressed.emit())
	row.add_child(back)
	res_again = icon_button("retry", "AGAIN", "go")
	res_again.pressed.connect(func(): again_pressed.emit())
	row.add_child(res_again)
	next_btn = icon_button("next", "NEXT", "go")
	next_btn.pressed.connect(func(): next_pressed.emit())
	row.add_child(next_btn)
	for b in row.get_children():
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.visible = false

# ---------------------------------------------------------------- pause
var pause_btn: Button
var pause_ov: Control
var pause_panel: PanelContainer
var _pause_sub: Label
var _pause_o: Dictionary

func _build_pause() -> void:
	var r := _overlay()
	pause_ov = r[0]
	pause_ov.color = Color(0.02, 0.06, 0.1, 0.55)
	pause_panel = r[2]
	_frost_panel(pause_panel)
	var vb: VBoxContainer = r[1]
	_pause_sub = _panel_header(vb, "PAUSED")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	for a in [["exit", "home", "MENU", "card"], ["restart", "retry", "RESTART", "card"], ["resume", "play", "RESUME", "go"]]:
		var b := icon_button(a[1], a[2], a[3])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var what: String = a[0]
		b.pressed.connect(func(): pause_action.emit(what))
		row.add_child(b)
	_pause_o = _make_options()
	vb.add_child(_pause_o["box"])
	vb.add_child(_label("Esc or the back button also resumes.", 12, C_MUTED))
	pause_ov.visible = false

	pause_btn = Button.new()
	pause_btn.custom_minimum_size = Vector2(48, 44)
	pause_btn.tooltip_text = "Pause"
	var pi := Art.Icon.new()
	pi.kind = "pause"
	pi.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pi.offset_left = 12; pi.offset_right = -12; pi.offset_top = 10; pi.offset_bottom = -10
	pi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_btn.add_child(pi)
	var pb := StyleBoxFlat.new()
	pb.bg_color = C_PANEL
	pb.set_corner_radius_all(6)
	pb.border_color = Color(0.86, 0.93, 0.98, 0.35)
	pb.border_width_top = 3
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		pause_btn.add_theme_stylebox_override(st, pb)
	pause_btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.pressed.connect(func(): pause_pressed.emit())

# options: { music_vol, sfx_vol: 0..100, ghost: bool or null when there is no ghost, effects: bool }
func show_pause(sub: String, opts: Dictionary) -> void:
	_pause_sub.text = sub
	set_options(_pause_o, opts)
	pause_ov.visible = true

func set_pause_opts(opts: Dictionary) -> void:
	set_options(_pause_o, opts)

# ---------------------------------------------------------------- shared option controls
# the frosted night-blue panel used by the pause and settings screens
func _frost_panel(panel: PanelContainer) -> void:
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.05, 0.11, 0.17, 0.94)
	ps.set_corner_radius_all(14)
	ps.border_color = Color(0.86, 0.93, 0.98, 0.45)
	ps.set_border_width_all(2)
	ps.border_width_top = 5
	ps.set_content_margin_all(20)
	ps.shadow_color = Color(0, 0, 0, 0.5)
	ps.shadow_size = 24
	panel.add_theme_stylebox_override("panel", ps)

# logo + big amber title + a small subtitle line (returned so it can be set later)
func _panel_header(vb: VBoxContainer, title: String) -> Label:
	var top := HBoxContainer.new()
	var logo := Art.Logo.new()
	logo.custom_minimum_size = Vector2(52, 52)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 12)
	top.add_child(logo)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_theme_constant_override("separation", -2)
	var pt := _label(title, 30, C_POST, f_display)
	pt.autowrap_mode = TextServer.AUTOWRAP_OFF
	tv.add_child(pt)
	var sub := _label("", 13, Art.C_ICE_DIM, f_bold)
	tv.add_child(sub)
	top.add_child(tv)
	vb.add_child(top)
	return sub

static var _knob: Texture2D
static func _knob_tex() -> Texture2D:
	if _knob == null:
		var n := 26
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := (n - 1) / 2.0
		for y in n:
			for x in n:
				var d := Vector2(x - c, y - c).length()
				var a := clampf(c - d + 0.5, 0.0, 1.0)
				var col := Art.C_ICE if d < c - 3.0 else Art.C_AMBER
				img.set_pixel(x, y, Color(col, a))
		_knob = ImageTexture.create_from_image(img)
	return _knob

func _volume_row(key: String, title: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var ic := Art.Icon.new()
	ic.kind = "music" if key == "music_vol" else "sound"
	ic.custom_minimum_size = Vector2(28, 28)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var l := _label(title, 15, C_FG, f_bold)
	l.custom_minimum_size.x = 54
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0
	sl.max_value = 100
	sl.step = 5
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.custom_minimum_size = Vector2(120, 36)
	sl.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.86, 0.93, 0.98, 0.16)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4; track.content_margin_bottom = 4
	var fill := track.duplicate()
	fill.bg_color = Art.C_ICE_DIM
	var fill_hi := track.duplicate()
	fill_hi.bg_color = Art.C_ICE
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	sl.add_theme_icon_override("grabber", _knob_tex())
	sl.add_theme_icon_override("grabber_highlight", _knob_tex())
	row.add_child(sl)
	var v := _label("", 14, Art.C_ICE_DIM, f_bold)
	v.custom_minimum_size.x = 46
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(v)
	sl.value_changed.connect(func(x):
		v.text = "Off" if x <= 0.0 else "%d%%" % int(x)
		option_changed.emit(key, int(x)))
	return [row, sl, v]

# music and sound sliders, then Ghost car / Effects toggles
func _make_options() -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var o := { "box": box, "sliders": {}, "toggles": {} }
	for s in [["music_vol", "Music"], ["sfx_vol", "Sound"]]:
		var r := _volume_row(s[0], s[1])
		box.add_child(r[0])
		o["sliders"][s[0]] = [r[1], r[2]]
	var grid := _grid(2)
	for t in [["ghost", "GHOST", "ghost"], ["effects", "EFFECTS", "spark"]]:
		var b := icon_button(t[2], t[1], "card", false, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var key: String = t[0]
		b.set_meta("name", t[1])
		b.pressed.connect(func():
			var on: bool = not b.get_meta("on")
			_set_toggle(b, on)
			option_changed.emit(key, on))
		grid.add_child(b)
		o["toggles"][key] = b
	box.add_child(grid)
	o["grid"] = grid
	return o

func _set_toggle(b: Button, on: bool) -> void:
	b.set_meta("on", on)
	var l: Label = b.get_meta("label")
	l.text = "%s  %s" % [b.get_meta("name"), "ON" if on else "OFF"]
	set_tile_on(b, on)
	var ic: Art.Icon = b.get_meta("icon")
	ic.col = C_POST if on else Color(C_MUTED, 0.6)

func set_options(o: Dictionary, opts: Dictionary) -> void:
	for key in o["sliders"]:
		var sl: HSlider = o["sliders"][key][0]
		var v: Label = o["sliders"][key][1]
		sl.set_value_no_signal(opts.get(key, 100))
		v.text = "Off" if sl.value <= 0.0 else "%d%%" % int(sl.value)
	var shown := 0
	for key in o["toggles"]:
		var b: Button = o["toggles"][key]
		b.visible = opts.get(key) != null
		if b.visible:
			_set_toggle(b, opts[key])
			shown += 1
	o["grid"].columns = maxi(1, shown)

# ---------------------------------------------------------------- settings (home screen)
var settings_ov: Control
var settings_panel: PanelContainer
var _settings_o: Dictionary

func _build_settings() -> void:
	var r := _overlay()
	settings_ov = r[0]
	settings_ov.color = Color(0.02, 0.06, 0.1, 0.55)
	settings_panel = r[2]
	_frost_panel(settings_panel)
	var vb: VBoxContainer = r[1]
	_panel_header(vb, "SETTINGS").text = "Saved on this device"
	_settings_o = _make_options()
	vb.add_child(_settings_o["box"])
	var done := icon_button("check", "DONE", "go", false, 56)
	done.pressed.connect(hide_settings)
	vb.add_child(done)
	settings_ov.visible = false

func show_settings(opts: Dictionary) -> void:
	set_options(_settings_o, opts)
	settings_ov.visible = true

func hide_settings() -> void:
	settings_ov.visible = false

func hide_pause() -> void:
	pause_ov.visible = false

# ---------------------------------------------------------------- loading screen
var loading: Control
var _load_title: Label
var _load_tip: Label
var _load_tween: Tween
var _load_box: VBoxContainer

var _load_bar
# loading artwork per theme: [landscape, portrait]; the screen wears the menu's theme
const ART := {
	"snow": [preload("res://art/loading_snow_land.jpg"), preload("res://art/loading_snow_port.jpg")],
	"forest": [preload("res://art/loading_forest_land.jpg"), preload("res://art/loading_forest_port.jpg")],
	"rock": [preload("res://art/loading_rock_land.jpg"), preload("res://art/loading_rock_port.jpg")],
	"sand": [preload("res://art/loading_sand_land.jpg"), preload("res://art/loading_sand_port.jpg")],
}
var art_theme := "snow"
var _load_art

# logo near the top, title / tip / bar at the bottom, whatever the screen shape
func _place_loading() -> void:
	var ins := safe_insets()
	_load_box.offset_bottom = -22 - ins["b"]
	_load_box.offset_top = _load_box.offset_bottom - 104
	var pair: Array = ART.get(art_theme, ART["snow"])
	_load_art.bg = pair[1] if is_portrait() else pair[0]

func _build_loading() -> void:
	loading = Control.new()
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.mouse_filter = Control.MOUSE_FILTER_STOP
	var sp := Art.Splash.new()
	sp.font = f_display
	_load_art = sp
	sp.bg = ART["snow"][0]
	sp.emblem_y = 0.15
	sp.emblem_k = 0.7
	sp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading.add_child(sp)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.0; vb.anchor_right = 1.0; vb.anchor_top = 1.0; vb.anchor_bottom = 1.0
	_load_box = vb
	vb.offset_left = 24; vb.offset_right = -24
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	loading.add_child(vb)
	_load_title = _label("", 20, C_POST, f_bold)
	_load_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_load_title)
	_load_tip = _label("", 14, Art.C_ICE, f_med)
	_load_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_tip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_load_tip.add_theme_constant_override("shadow_offset_y", 1)
	vb.add_child(_load_tip)
	var bar_row := CenterContainer.new()
	bar_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_bar = Art.LoadBar.new()
	_load_bar.custom_minimum_size = Vector2(300, 26)
	_load_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_row.add_child(_load_bar)
	vb.add_child(bar_row)
	loading.visible = false
	root.add_child(loading)

# cover the screen while a track is built; title is e.g. the track name
func show_loading(title: String) -> void:
	if _load_tween:
		_load_tween.kill()
	art_theme = Campaign.menu_theme()
	_place_loading()
	_load_title.text = title.to_upper()
	_load_tip.text = TIPS[randi() % TIPS.size()]
	loading.modulate.a = 1.0
	loading.visible = true
	_load_bar.value = 0.0
	_load_bar.target = 0.08
	_place_loading()

func set_loading_progress(v: float) -> void:
	_load_bar.target = v

func hide_loading() -> void:
	if not loading.visible:
		return
	_load_bar.target = 1.0
	_load_tween = create_tween()
	_load_tween.tween_interval(0.25)   # let the bar reach the end
	_load_tween.tween_property(loading, "modulate:a", 0.0, 0.35)
	_load_tween.tween_callback(func(): loading.visible = false)

# ---------------------------------------------------------------- menu state
func show_menu() -> void:
	pause_ov.visible = false
	settings_ov.visible = false
	menu.visible = true
	menu.refresh()
	results.visible = false
	hud.visible = false
	minimap.visible = false
	big.text = ""

# ---------------------------------------------------------------- HUD
func _chip(label: String, key: String, col: Color, tpl: Array = ["00:00.00"], tags: Array = []) -> void:
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
	for t in tags:   # a tag that changes (medal names) keeps the width of the longest
		l.custom_minimum_size.x = maxf(l.custom_minimum_size.x, f_bold.get_string_size(String(t).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10 if narrow else 11).x)
	hb.add_child(l)
	var v := MonoLabel.new()
	v.setup(f_bold, 17 if narrow else 20, C_FG, tpl)
	hb.add_child(v)
	pc.add_child(hb)
	hud.add_child(pc)
	hud_vals[key] = v
	hud_tags[key] = [l, s]

func _spacer() -> void:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(c)

func build_hud(race, gems_total: int, medals: bool) -> void:
	var gems := gems_total > 0
	if pause_btn.get_parent():
		pause_btn.get_parent().remove_child(pause_btn)
	for ch in hud.get_children():
		ch.queue_free()
	hud_vals.clear()
	hud_tags.clear()
	var laps := "%d/%d" % [race.laps_total, race.laps_total]
	var n_gems := "%d/%d" % [gems_total, gems_total]
	var places := ["1st", "2nd", "3rd", "4th", "5th", "6th"]
	if race.mode == "trial":
		_chip("Lap", "lap0", C_POST, [laps])
		_chip("Lap time", "time", C_POST)
		if gems:
			_chip("Gems", "gems", Color("#7fe3d0"), [n_gems])
		_spacer()
		if medals:   # target time of the best medal still in reach this lap
			_chip("Target", "target", C_MUTED, ["00:00.00"], ["Target"] + Medals.NAMES)
		_chip("Record", "rec", C_POST)
	else:
		var hs: Array = race.cars.filter(func(c): return c.human >= 0)
		_chip("P1" if race.humans > 1 else "Lap", "lap0", hs[0].color, [laps])
		_chip("Pos", "pos0", hs[0].color, places)
		_spacer()
		if race.humans == 1 or not is_portrait():  # no room for it between two players in portrait
			_chip("Time", "time", C_POST)
		if race.humans == 1:   # the medal the current place would earn
			_chip("Medal", "target", C_MUTED, ["BRONZE", "SILVER", "GOLD", "PIVOT", "NONE"])
		if gems:
			_chip("Gems", "gems", Color("#7fe3d0"), [n_gems])
		if race.humans > 1:
			_spacer()
			_chip("P2", "lap1", hs[1].color, [laps])
			_chip("Pos", "pos1", hs[1].color, places)
	hud.add_child(pause_btn)
	hud.visible = true
	minimap.visible = true
	menu.visible = false
	results.visible = false

func set_hud(key: String, text: String) -> void:
	if hud_vals.has(key):
		hud_vals[key].text = text

func set_hud_color(key: String, col: Color) -> void:
	if hud_vals.has(key) and hud_vals[key].color != col:
		hud_vals[key].color = col
		hud_vals[key].queue_redraw()

# a chip's label and accent colour, e.g. the medal a target time stands for
func set_hud_tag(key: String, label: String, col: Color) -> void:
	if hud_tags.has(key):
		hud_tags[key][0].text = label.to_upper()
		hud_tags[key][0].add_theme_color_override("font_color", col)
		hud_tags[key][1].border_color = col

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
	# with a next event waiting, that is the main action and Again steps back
	res_again.set_meta("look", "card" if has_next else "go")
	set_tile_on(res_again, false)
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

# fixed-width HUD clock, 00:00.00 from the start so the chips never change size
static func fmt_hud(t: float) -> String:
	t = clampf(snappedf(t, 0.01), 0.0, 5999.99)
	var m := int(t / 60.0)
	return "%02d:%05.2f" % [m, t - m * 60.0]

static func fmt2(t: float) -> String:
	t = snappedf(t, 0.01)
	var m := int(t / 60.0)
	var s := t - m * 60.0
	return "%d:%s%.2f" % [m, "0" if s < 9.995 else "", s]
