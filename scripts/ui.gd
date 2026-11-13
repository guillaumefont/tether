# Menus, HUD, big centre text, results and minimap. Built in code so the layout
# adapts to any phone screen. Menus, panels and overlays wear the Roadbook look (paper.gd:
# cream paper, navy ink, grey marker); the race HUD stays dark over the track.
extends CanvasLayer

const TrackData = preload("res://scripts/track.gd")
const TrackMap = preload("res://scripts/track_map.gd")
const MenuScreens = preload("res://scripts/menu.gd")
const Medals = preload("res://scripts/medals.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Art = preload("res://scripts/menu_art.gd")
const Campaign = preload("res://scripts/campaign.gd")
const MonoLabel = preload("res://scripts/mono_label.gd")
const Settings = preload("res://scripts/settings.gd")
const Paper = preload("res://scripts/paper.gd")

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
# music_vol / sfx_vol (0..100), quality (0..2), ghost / haptics (bool)
signal option_changed(key: String, value)
signal skip_pressed       # leave the tutorial
signal tutorial_pressed   # replay the tutorial (settings screen)
signal reset_pressed      # erase all progress (settings screen, confirmed with a second tap)
signal reward_popped(i: int)  # a results badge (record, medal) just popped in: sound + buzz
signal awards_pressed         # the trophy on the results screen: open the Awards screen

const MINIMAP := 110.0
const C_PANEL := Color(0.035, 0.075, 0.082, 0.92)
const C_FG := Color("#f3efe6")
const C_MUTED := Color("#9fb3b0")
const C_ACCENT := Color("#f3efe6")   # no coloured accent: chalk cream on dark, same as Art.C_ACCENT
const C_COIN := Color("#f2b134")     # coin amounts stay gold
const C_GAIN := Color("#5fd38d")   # time gained on a record (same green as the lap delta)
const C_ASPHALT := Color("#393e46")

var f_display: Font = preload("res://fonts/Bungee-Regular.ttf")
var f_bold: Font = preload("res://fonts/ChakraPetch-Bold.ttf")
var f_med: Font = preload("res://fonts/ChakraPetch-Medium.ttf")

var root: Control
var menu: MenuScreens
var hud: Control           # top band: corners + centre timer
var hud_left: HBoxContainer
var hud_right: HBoxContainer
var hud_mid: VBoxContainer
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

	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.offset_left = 16; hud.offset_right = -16; hud.offset_top = 10
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	root.add_child(hud)
	# corners hug the edges, the timer column stays centred on the screen whatever they hold
	hud_left = HBoxContainer.new()
	hud_left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud_right = HBoxContainer.new()
	hud_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud_mid = VBoxContainer.new()
	hud_mid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hud_mid.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_mid.alignment = BoxContainer.ALIGNMENT_BEGIN
	hud_mid.add_theme_constant_override("separation", 4)
	hud_left.add_theme_constant_override("separation", 6)
	hud_right.add_theme_constant_override("separation", 6)
	for b in [hud_left, hud_right, hud_mid]:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(b)

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
	big.add_theme_color_override("default_color", C_ACCENT)
	big.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	big.add_theme_constant_override("shadow_offset_y", 6)
	big.add_theme_constant_override("shadow_offset_x", 0)
	root.add_child(big)

	streak = Label.new()
	streak.set_anchors_preset(Control.PRESET_TOP_WIDE)
	streak.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	streak.add_theme_font_override("font", f_display)
	streak.add_theme_font_size_override("font_size", 26)
	streak.add_theme_color_override("font_color", Art.C_ICE)
	streak.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	streak.add_theme_constant_override("shadow_offset_y", 3)
	streak.modulate.a = 0.0
	root.add_child(streak)

	lap_note = RichTextLabel.new()
	lap_note.set_anchors_preset(Control.PRESET_TOP_WIDE)
	lap_note.bbcode_enabled = true
	lap_note.fit_content = true
	lap_note.scroll_active = false
	lap_note.autowrap_mode = TextServer.AUTOWRAP_OFF
	lap_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lap_note.add_theme_font_override("normal_font", f_display)
	lap_note.add_theme_font_size_override("normal_font_size", 30)
	lap_note.add_theme_color_override("default_color", C_ACCENT)
	lap_note.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	lap_note.add_theme_constant_override("shadow_offset_y", 3)
	lap_note.add_theme_constant_override("shadow_offset_x", 0)
	lap_note.add_theme_constant_override("line_separation", -4)
	lap_note.modulate.a = 0.0
	root.add_child(lap_note)

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
	_build_coach()
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
	# roadbook: white index-card buttons outlined in ink, cream paper panels
	t.set_stylebox("normal", "Button", sb.call(Paper.CARD, Paper.INK, 2))
	t.set_stylebox("hover", "Button", sb.call(Paper.CARD.darkened(0.04), Paper.INK, 2))
	t.set_stylebox("pressed", "Button", sb.call(Paper.CARD.darkened(0.04), Paper.INK, 3))
	t.set_stylebox("hover_pressed", "Button", sb.call(Paper.CARD.darkened(0.04), Paper.INK, 3))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		(t.get_stylebox(st, "Button") as StyleBoxFlat).set_corner_radius_all(2)
	t.set_font("font", "Button", f_bold)
	t.set_font_size("font_size", "Button", 16)
	t.set_color("font_color", "Button", Paper.INK)
	t.set_color("font_pressed_color", "Button", Paper.INK)
	t.set_color("font_hover_color", "Button", Paper.INK)
	t.set_color("font_hover_pressed_color", "Button", Paper.INK)
	t.set_color("font_focus_color", "Button", Paper.INK)
	var panel: StyleBoxFlat = Paper.box(Paper.PAPER, Color.TRANSPARENT, 0, 24)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.set_content_margin_all(20)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", Paper.INK)
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
	# results sit to one side (right in landscape, bottom in portrait) with a light veil,
	# so the car the camera follows stays in view
	var rc: Control = results.get_child(0)
	if is_portrait():
		results_panel.custom_minimum_size.x = minf(440.0, vp.x - 40.0)
		rc.anchor_left = 0.0
		rc.anchor_top = 0.42
	else:
		results_panel.custom_minimum_size.x = minf(420.0, vp.x * 0.5)
		rc.anchor_left = 1.0 - (results_panel.custom_minimum_size.x + 40.0) / maxf(1.0, vp.x)
		rc.anchor_top = 0.0
		rc.offset_right = -ins["r"]
	rc.offset_bottom = -ins["b"]
	if res_cup:
		res_cup.offset_right = -14 - ins["r"]
		res_cup.offset_left = res_cup.offset_right - 50
		res_cup.offset_top = 12 + ins["t"]
		res_cup.offset_bottom = res_cup.offset_top + 50
	if pause_panel:
		pause_panel.custom_minimum_size.x = minf(440.0, vp.x - 40.0)
	if settings_panel:
		settings_panel.custom_minimum_size.x = minf(440.0, vp.x - 40.0)
	if _load_box:
		_place_loading()
	if coach:
		_place_coach()

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
const C_INK := Color("#071827")
const C_TILE := Color(0.05, 0.11, 0.17, 0.82)
const C_FROST := Color(0.86, 0.93, 0.98, 0.55)

# A big touch target with a drawn icon and an optional short label: the label sits under
# the icon (tile) or beside it. look: "go" (accent colour, the main action) or "card" (frosted).
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
	# roadbook: "go" is solid ink with a grey block shadow, "card" a white index card
	# outlined in ink, and a selected card is filled in ink like a ticked box
	var go := look == "go"
	var filled := go or on
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var lit: bool = st.begins_with("hover") or st.contains("pressed")
		var down: bool = st.contains("pressed")
		var sbx: StyleBoxFlat
		if filled:
			# pressed into the paper: the shadow closes up
			sbx = Paper.go_box(lit, 1 if down else (4 if go else 3))
		else:
			sbx = Paper.box(Paper.CARD.darkened(0.05) if lit else Paper.CARD, Paper.INK if down else Paper.INK, 3 if down else 2, 3)
		if st == "disabled":
			sbx.bg_color = Color(Paper.PAPER_DARK, 0.7)
			sbx.border_color = Paper.INK_FAINT
			sbx.shadow_size = 0
			sbx.shadow_offset = Vector2.ZERO
		b.add_theme_stylebox_override(st, sbx)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var ink := Paper.CARD if filled else Paper.INK
	var ic: Art.Icon = b.get_meta("icon")
	ic.ink = not filled   # on a filled (ink) button the icon keeps its night-time tones
	ic.col = ink
	ic.col2 = Paper.CARD if filled else Paper.INK
	if b.disabled:
		ic.col = Paper.INK_FAINT
	if b.has_meta("label"):
		var l: Label = b.get_meta("label")
		l.add_theme_color_override("font_color", ink if not b.disabled else Paper.INK_SOFT)

func _build_results() -> void:
	var r := _overlay()
	results = r[0]
	(results as ColorRect).color.a = 0.14   # the car drives on behind: keep it visible
	var vb: VBoxContainer = r[1]
	results_panel = r[2]
	results_panel.custom_minimum_size.x = 440
	vb.add_child(_label("TIME CARD  ·  ROADBOOK", 12, Paper.INK_SOFT, f_bold))
	res_title = _label("Finish", 30, Paper.INK, f_display)
	vb.add_child(res_title)
	res_rewards = HFlowContainer.new()
	res_rewards.add_theme_constant_override("h_separation", 8)
	res_rewards.add_theme_constant_override("v_separation", 8)
	vb.add_child(res_rewards)
	res_table = _grid(3)
	res_table.add_theme_constant_override("h_separation", 16)
	vb.add_child(res_table)
	res_note = _label("", 14, Paper.INK_SOFT)
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
	# the trophy in the corner that new award medallions fly into; shown when there are some
	res_cup = icon_button("trophy", "", "card", false, 50)
	res_cup.tooltip_text = "Awards"
	res_cup.anchor_left = 1.0; res_cup.anchor_right = 1.0
	res_cup.pressed.connect(func(): awards_pressed.emit())
	res_cup.visible = false
	results.add_child(res_cup)
	results.visible = false

# ---------------------------------------------------------------- pause
var pause_btn: Button
var pause_ov: Control
var pause_panel: PanelContainer
var _pause_sub: Label
var _pause_o: Dictionary
var _pause_main: VBoxContainer   # the short page: where you are + Menu / Restart / Resume + Settings
var _pause_set: VBoxContainer    # the Settings page, one tap away, with a Back button

func _build_pause() -> void:
	var r := _overlay()
	pause_ov = r[0]
	pause_ov.color = Color(0.02, 0.06, 0.1, 0.55)
	pause_panel = r[2]
	_frost_panel(pause_panel)
	var vb: VBoxContainer = r[1]
	_pause_main = VBoxContainer.new()
	_pause_main.add_theme_constant_override("separation", 12)
	vb.add_child(_pause_main)
	_pause_sub = _panel_header(_pause_main, "PAUSED")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_pause_main.add_child(row)
	for a in [["exit", "home", "MENU", "card"], ["restart", "retry", "RESTART", "card"], ["resume", "play", "RESUME", "go"]]:
		var b := icon_button(a[1], a[2], a[3])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var what: String = a[0]
		b.pressed.connect(func(): pause_action.emit(what))
		row.add_child(b)
	var set_btn := icon_button("gear", "SETTINGS", "card", false, 50)
	set_btn.focus_mode = Control.FOCUS_NONE
	set_btn.pressed.connect(func(): show_pause_settings(true))
	_pause_main.add_child(set_btn)

	_pause_set = VBoxContainer.new()
	_pause_set.add_theme_constant_override("separation", 12)
	vb.add_child(_pause_set)
	_panel_header(_pause_set, "SETTINGS").text = "Saved on this device"
	_pause_o = _make_options()
	_pause_set.add_child(_pause_o["box"])
	var back := icon_button("back", "BACK", "go", false, 56)
	back.pressed.connect(func(): show_pause_settings(false))
	_pause_set.add_child(back)
	_pause_set.visible = false
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

# options: { music_vol, sfx_vol: 0..100, quality: 0..2, ghost / haptics: bool, or null to hide the toggle }
func show_pause(sub: String, opts: Dictionary) -> void:
	_pause_sub.text = sub
	set_options(_pause_o, opts)
	show_pause_settings(false)   # always opens on the short page
	pause_ov.visible = true

# flip the pause panel between its short page and the Settings page
func show_pause_settings(on: bool) -> void:
	_pause_main.visible = not on
	_pause_set.visible = on

func pause_settings_open() -> bool:
	return pause_ov.visible and _pause_set.visible

func set_pause_opts(opts: Dictionary) -> void:
	set_options(_pause_o, opts)

# ---------------------------------------------------------------- shared option controls
# the frosted night-blue panel used by the pause and settings screens
func _frost_panel(panel: PanelContainer) -> void:
	# a page torn out of the roadbook, with a double ink rule along the top
	var ps := Paper.box(Paper.PAPER, Paper.INK, 0, 24)
	ps.border_width_top = 5
	ps.border_color = Paper.INK
	ps.set_content_margin_all(20)
	ps.shadow_color = Color(0, 0, 0, 0.45)
	panel.add_theme_stylebox_override("panel", ps)

# logo + big amber title + a small subtitle line (returned so it can be set later)
func _panel_header(vb: VBoxContainer, title: String) -> Label:
	var top := HBoxContainer.new()
	var logo := Art.Logo.new()
	logo.ink = true
	logo.custom_minimum_size = Vector2(52, 52)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 12)
	top.add_child(logo)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.add_theme_constant_override("separation", -2)
	var pt := _label(title, 30, Paper.INK, f_display)
	pt.autowrap_mode = TextServer.AUTOWRAP_OFF
	tv.add_child(pt)
	var sub := _label("", 13, Paper.INK_SOFT, f_bold)
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
				var col := Paper.CARD if d < c - 3.0 else Paper.INK
				img.set_pixel(x, y, Color(col, a))
		_knob = ImageTexture.create_from_image(img)
	return _knob

func _volume_row(key: String, title: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var ic := Art.Icon.new()
	ic.kind = "music" if key == "music_vol" else "sound"
	ic.col = Paper.INK
	ic.custom_minimum_size = Vector2(28, 28)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var l := _label(title, 15, Paper.INK, f_bold)
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
	track.bg_color = Paper.INK_FAINT
	track.set_corner_radius_all(4)
	track.content_margin_top = 4; track.content_margin_bottom = 4
	var fill := track.duplicate()
	fill.bg_color = Paper.INK
	var fill_hi := track.duplicate()
	fill_hi.bg_color = Paper.INK
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	sl.add_theme_icon_override("grabber", _knob_tex())
	sl.add_theme_icon_override("grabber_highlight", _knob_tex())
	row.add_child(sl)
	var v := _label("", 14, Paper.INK_SOFT, f_bold)
	v.custom_minimum_size.x = 46
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(v)
	sl.value_changed.connect(func(x):
		v.text = "Off" if x <= 0.0 else "%d%%" % int(x)
		option_changed.emit(key, int(x)))
	return [row, sl, v]

# music and sound sliders, the Graphics quality button, then Ghost car / Vibration toggles
func _make_options() -> Dictionary:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var o := { "box": box, "sliders": {}, "toggles": {} }
	for s in [["music_vol", "Music"], ["sfx_vol", "Sound"]]:
		var r := _volume_row(s[0], s[1])
		box.add_child(r[0])
		o["sliders"][s[0]] = [r[1], r[2]]
	# one tap steps Low -> Medium -> High -> Low
	var q := icon_button("spark", "GRAPHICS  MEDIUM", "card", false, 50)
	q.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	q.focus_mode = Control.FOCUS_NONE
	q.tooltip_text = "Lower it if the game stutters or the phone gets warm"
	q.set_meta("q", 1)
	q.pressed.connect(func():
		var v: int = (int(q.get_meta("q")) + 1) % Settings.QUALITY_NAMES.size()
		_set_quality_btn(q, v)
		option_changed.emit("quality", v))
	box.add_child(q)
	o["quality"] = q
	var grid := _grid(2)
	for t in [["ghost", "GHOST", "ghost"], ["haptics", "VIBRATION", "vibrate"]]:
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
	ic.col = Paper.CARD if on else Paper.INK_FAINT

func _set_quality_btn(b: Button, v: int) -> void:
	b.set_meta("q", v)
	var l: Label = b.get_meta("label")
	l.text = "GRAPHICS  %s" % Settings.QUALITY_NAMES[v]
	var ic: Art.Icon = b.get_meta("icon")
	ic.col = Paper.INK if v > 0 else Paper.INK_FAINT

func set_options(o: Dictionary, opts: Dictionary) -> void:
	_set_quality_btn(o["quality"], int(opts.get("quality", 1)))
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
	o["grid"].visible = shown > 0

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
	var tut := icon_button("play", "PLAY THE TUTORIAL", "card", false, 50)
	tut.focus_mode = Control.FOCUS_NONE
	tut.pressed.connect(func():
		hide_settings()
		tutorial_pressed.emit())
	vb.add_child(tut)
	# a second tap within a few seconds confirms; anything else puts the button back
	_reset_btn = icon_button("retry", "RESET PROGRESS", "card", false, 50)
	_reset_btn.focus_mode = Control.FOCUS_NONE
	_reset_btn.pressed.connect(_reset_tap)
	vb.add_child(_reset_btn)
	var done := icon_button("check", "DONE", "go", false, 56)
	done.pressed.connect(hide_settings)
	vb.add_child(done)
	settings_ov.visible = false

func show_settings(opts: Dictionary) -> void:
	set_options(_settings_o, opts)
	_reset_arm(false)
	settings_ov.visible = true

func hide_settings() -> void:
	_reset_arm(false)
	settings_ov.visible = false

var _reset_btn: Button
var _reset_armed_ms := -1

func _reset_tap() -> void:
	if _reset_armed_ms >= 0 and Time.get_ticks_msec() - _reset_armed_ms < 5000:
		_reset_arm(false)
		reset_pressed.emit()
		return
	_reset_arm(true)
	get_tree().create_timer(5.0).timeout.connect(func():
		if _reset_armed_ms >= 0 and Time.get_ticks_msec() - _reset_armed_ms >= 4900:
			_reset_arm(false))

# armed: the button turns red and asks for the second tap
func _reset_arm(on: bool) -> void:
	if _reset_btn == null:
		return
	_reset_armed_ms = Time.get_ticks_msec() if on else -1
	var l: Label = _reset_btn.get_meta("label")
	l.text = "TAP AGAIN TO ERASE ALL PROGRESS" if on else "RESET PROGRESS"
	l.add_theme_color_override("font_color", Paper.RED_INK if on else Paper.INK)

func hide_pause() -> void:
	pause_ov.visible = false

# ---------------------------------------------------------------- loading screen
var loading: Control
var _load_title: Label
var _load_tip: Label
var _load_tween: Tween
var _load_box: VBoxContainer
# loading artwork per theme: [landscape, portrait]. Menu loads wear the menu's theme;
# a race load wears the world of the track being built.
# Loaded on demand (load() caches) so only the pictures in use sit in memory.
const ART := {
	"snow": ["res://art/loading_snow_land.jpg", "res://art/loading_snow_port.jpg"],
	"forest": ["res://art/loading_forest_land.jpg", "res://art/loading_forest_port.jpg"],
	"rock": ["res://art/loading_rock_land.jpg", "res://art/loading_rock_port.jpg"],
	"sand": ["res://art/loading_sand_land.jpg", "res://art/loading_sand_port.jpg"],
}
var art_theme := "snow"
var _load_art

# logo near the top (its ring is the progress indicator), title and tip at the bottom
func _place_loading() -> void:
	var ins := safe_insets()
	_load_box.offset_bottom = -22 - ins["b"]
	_load_box.offset_top = _load_box.offset_bottom - 70
	var pair: Array = ART.get(art_theme, ART["snow"])
	_load_art.bg = load(pair[1] if is_portrait() else pair[0])

func _build_loading() -> void:
	loading = Control.new()
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.mouse_filter = Control.MOUSE_FILTER_STOP
	var sp := Art.Splash.new()
	sp.font = f_display
	_load_art = sp
	sp.bg = load(ART["snow"][0])
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
	_load_title = _label("", 20, C_ACCENT, f_bold)
	_load_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_load_title)
	_load_tip = _label("", 14, Art.C_ICE, f_med)
	_load_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_tip.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_load_tip.add_theme_constant_override("shadow_offset_y", 1)
	vb.add_child(_load_tip)
	loading.visible = false
	root.add_child(loading)

# cover the screen while a track is built; title is e.g. the track name
func show_loading(title: String, theme := "") -> void:
	if _load_tween:
		_load_tween.kill()
	art_theme = theme if ART.has(theme) else Campaign.menu_theme()
	_place_loading()
	_load_title.text = title.to_upper()
	_load_tip.text = TIPS[randi() % TIPS.size()]
	loading.modulate.a = 1.0
	loading.visible = true
	_load_art.shown = 0.0
	_load_art.progress = 0.08
	_place_loading()

func set_loading_progress(v: float) -> void:
	_load_art.progress = v

func hide_loading() -> void:
	if not loading.visible:
		return
	_load_art.progress = 1.0
	_load_tween = create_tween()
	_load_tween.tween_interval(0.25)   # let the ring close
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
	hide_coach()
	big.text = ""
	hide_lap_note()

# ---------------------------------------------------------------- HUD
func _panel(col := Color(0, 0, 0, 0), radius := 6) -> PanelContainer:
	var pc := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = C_PANEL
	s.set_corner_radius_all(radius)
	s.border_color = col
	if col.a > 0.0:
		s.border_width_left = 4
	s.content_margin_left = 10; s.content_margin_right = 10; s.content_margin_top = 4; s.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", s)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pc

# a labelled readout: small tag, fixed-width value
func _chip(parent: Control, label: String, key: String, col: Color, tpl: Array = ["00:00.00"], tags: Array = [], size := 0) -> PanelContainer:
	var narrow := is_portrait()
	var pc := _panel(col)
	var s: StyleBoxFlat = pc.get_theme_stylebox("panel")
	if narrow:
		s.content_margin_left = 7; s.content_margin_right = 7
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ts := 10 if narrow else 11
	var l := _label(label.to_upper(), ts, C_MUTED, f_bold)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for t in tags:   # a tag that changes (medal names) keeps the width of the longest
		l.custom_minimum_size.x = maxf(l.custom_minimum_size.x, f_bold.get_string_size(String(t).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x)
	hb.add_child(l)
	var v := MonoLabel.new()
	v.setup(f_bold, size if size > 0 else (17 if narrow else 20), C_FG, tpl)
	hb.add_child(v)
	pc.add_child(hb)
	parent.add_child(pc)
	hud_vals[key] = v
	hud_tags[key] = [l, s]
	return pc

# the big centred clock
func _timer(key: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pc := _panel(Color(0, 0, 0, 0), 9)
	var s: StyleBoxFlat = pc.get_theme_stylebox("panel")
	s.content_margin_left = 14; s.content_margin_right = 14; s.content_margin_top = 1; s.content_margin_bottom = 2
	var v := MonoLabel.new()
	v.setup(f_bold, 26 if is_portrait() else 30, C_FG, ["00:00.00"])
	pc.add_child(v)
	row.add_child(pc)
	hud_mid.add_child(row)
	hud_vals[key] = v
	return row

# the small line under the clock: tag + value pairs in one slim panel
func _subline(items: Array) -> void:
	var pc := _panel(Color(0, 0, 0, 0))
	var s: StyleBoxFlat = pc.get_theme_stylebox("panel")
	s.content_margin_top = 2; s.content_margin_bottom = 2
	pc.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in items:   # [tag, key, colour, templates]
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 5)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := _label(String(it[0]).to_upper(), 11, it[2], f_bold)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pair.add_child(l)
		var v := MonoLabel.new()
		v.setup(f_bold, 15, C_FG, it[3])
		pair.add_child(v)
		hb.add_child(pair)
		hud_vals[it[1]] = v
	pc.add_child(hb)
	hud_mid.add_child(pc)

func build_hud(race, gems_total: int, medals: bool, tutorial := false) -> void:
	var gems := gems_total > 0
	if pause_btn.get_parent():
		pause_btn.get_parent().remove_child(pause_btn)
	for box in [hud_left, hud_right, hud_mid]:
		for ch in box.get_children():
			ch.queue_free()
	hud_vals.clear()
	hud_tags.clear()
	hide_coach()
	var laps := "%d/%d" % [race.laps_total, race.laps_total]
	var n_gems := "%d/%d" % [gems_total, gems_total]
	var places := ["1st", "2nd", "3rd", "4th", "5th", "6th"]
	var gem_col := Color("#7fe3d0")
	if tutorial:
		_timer("time")   # alone: the corner holds SKIP and pause
		_subline([["Lap", "lap0", C_MUTED, ["3/3"]], ["Target", "rec", C_ACCENT, ["00.0 s"]]])
		# icon only in portrait, where the corner has no room for the word
		skip_btn = icon_button("next", "" if is_portrait() else "SKIP", "card", false, 44)
		skip_btn.focus_mode = Control.FOCUS_NONE
		skip_btn.tooltip_text = "Skip the tutorial"
		skip_btn.pressed.connect(func(): skip_pressed.emit())
		hud_right.add_child(skip_btn)
	elif race.mode == "trial":
		var row := _timer("time")
		if medals:   # ahead of (-) or behind (+) the pace of the best medal in reach
			_chip(row, "Gold", "gap", Medals.COLORS[2], ["+00.00"], ["Target"] + Medals.NAMES, 15)
		var sub := [["Lap", "lap0", C_MUTED, [laps]]]
		if gems:
			sub.append(["Gems", "gems", gem_col, [n_gems]])
		_subline(sub)
	else:
		var hs: Array = race.cars.filter(func(c): return c.human >= 0)
		if race.humans > 1:
			# one corner per player, the shared clock in the middle when there is room
			for k in 2:
				var col: VBoxContainer = VBoxContainer.new()
				col.add_theme_constant_override("separation", 4)
				col.mouse_filter = Control.MOUSE_FILTER_IGNORE
				_chip(col, "P%d" % (k + 1), "lap%d" % k, hs[k].color, [laps])
				_chip(col, "Pos", "pos%d" % k, hs[k].color, places)
				(hud_left if k == 0 else hud_right).add_child(col)
			if not is_portrait():
				_timer("time")
			if gems:
				_subline([["Gems", "gems", gem_col, [n_gems]]])
		else:
			var row := _timer("time")
			_chip(row, "Pos", "pos0", hs[0].color, places, [], 15)
			var sub := [["Lap", "lap0", C_MUTED, [laps]], ["Medal", "target", C_MUTED, ["BRONZE", "SILVER", "GOLD", "PIVOT", "NONE"]]]
			if gems:
				sub.append(["Gems", "gems", gem_col, [n_gems]])
			_subline(sub)
	hud_right.add_child(pause_btn)
	if hud_right.get_child_count() > 1:
		hud_right.move_child(pause_btn, hud_right.get_child_count() - 1)
	pause_btn.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
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

# "CLEAN x3" under the HUD after bends taken without touching a rail or a post
var streak: Label
var _streak_tw: Tween
func _under_hud() -> float:
	return maxf(72.0, hud.position.y + hud_mid.position.y + hud_mid.size.y + 6.0)

func show_streak(n: int) -> void:
	# just under the centre timer column (timer + medal gap), or under the lap time while it shows
	streak.offset_top = _under_hud()
	if lap_note.modulate.a > 0.05:
		streak.offset_top += lap_note.get_content_height() + 4.0
	streak.offset_bottom = streak.offset_top + 40.0
	streak.text = "CLEAN  ×%d" % n
	# brighter and bigger as the run of clean bends grows
	var col: Color = Color(C_ACCENT, 0.75).lerp(C_ACCENT, clampf((n - 2) / 6.0, 0.0, 1.0))
	streak.add_theme_color_override("font_color", col)
	streak.pivot_offset = Vector2(streak.size.x * 0.5, 20.0)
	if _streak_tw:
		_streak_tw.kill()
	streak.modulate.a = 1.0
	streak.scale = Vector2.ONE * 1.35
	_streak_tw = create_tween()
	_streak_tw.tween_property(streak, "scale", Vector2.ONE * minf(1.25, 1.0 + n * 0.03), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_streak_tw.tween_interval(0.8)
	_streak_tw.tween_property(streak, "modulate:a", 0.0, 0.4)

func hide_streak() -> void:
	if _streak_tw:
		_streak_tw.kill()
	streak.modulate.a = 0.0

# The lap time (and its gap to the record) at the end of each lap: a small line under the
# centre timer, out of the way of the track, that fades after a moment.
var lap_note: RichTextLabel
var _lap_tw: Tween
func show_lap_note(bb: String, secs := 1.6) -> void:
	lap_note.offset_top = _under_hud()
	lap_note.text = "[center]" + bb + "[/center]"
	if _lap_tw:
		_lap_tw.kill()
	lap_note.modulate.a = 1.0
	_lap_tw = create_tween()
	_lap_tw.tween_interval(secs)
	_lap_tw.tween_property(lap_note, "modulate:a", 0.0, 0.4)

func hide_lap_note() -> void:
	if _lap_tw:
		_lap_tw.kill()
	lap_note.modulate.a = 0.0

func set_big(bb: String, size := 120) -> void:
	# shrink long words (FINISH, 2nd...) to fit a narrow portrait screen
	var room := root.get_viewport_rect().size.x * 0.9
	var w := f_display.get_string_size(bb, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if bb != "" and w > room:
		size = int(size * room / w)
	big.add_theme_font_size_override("normal_font_size", size)
	big.text = "[center]" + bb + "[/center]" if bb != "" else ""

# ---------------------------------------------------------------- tutorial coach card
# A frosted card low on the screen with the current lesson; the footer names what to do
# (TAP TO START, HOLD, LET GO). The SKIP button in the tutorial's HUD is made by build_hud.
var coach: PanelContainer
var _coach_box: VBoxContainer   # full screen, stacks the card at the bottom
var skip_btn: Button
var _coach_title: Label
var _coach_body: Label
var _coach_foot: Label
var _coach_tween: Tween

func _build_coach() -> void:
	coach = PanelContainer.new()
	_frost_panel(coach)
	var ps: StyleBoxFlat = coach.get_theme_stylebox("panel").duplicate()
	ps.set_content_margin_all(14)
	ps.content_margin_left = 18; ps.content_margin_right = 18
	coach.add_theme_stylebox_override("panel", ps)
	coach.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coach.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_coach_box = VBoxContainer.new()
	_coach_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_coach_box.alignment = BoxContainer.ALIGNMENT_END
	_coach_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coach_box.add_child(coach)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coach.add_child(vb)
	_coach_title = _label("", 20, Paper.INK, f_display)
	vb.add_child(_coach_title)
	_coach_body = _label("", 15, Paper.INK, f_med)
	vb.add_child(_coach_body)
	_coach_foot = _label("", 14, Paper.INK, f_bold)
	_coach_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_coach_foot)
	coach.visible = false
	root.add_child(_coach_box)
	root.move_child(_coach_box, big.get_index())   # under the big HOLD / LET GO word


# bottom centre, above the minimap in portrait (it would sit under the card)
func _place_coach() -> void:
	var ins := safe_insets()
	var vp := root.get_viewport_rect().size
	var w := minf(520.0, vp.x - 32.0 - ins["l"] - ins["r"])
	coach.custom_minimum_size.x = w
	var lift := MINIMAP + 12.0 if is_portrait() else 0.0
	_coach_box.offset_bottom = -14.0 - ins["b"] - lift

# card: { title, body, footer }; empty hides it
func show_coach(card: Dictionary) -> void:
	if card.is_empty():
		hide_coach()
		return
	_coach_title.text = card["title"]
	_coach_body.text = card["body"]
	_coach_foot.text = card.get("footer", "")
	_coach_foot.visible = _coach_foot.text != ""
	_place_coach()
	if _coach_tween:
		_coach_tween.kill()
	if not coach.visible:
		coach.modulate.a = 0.0
		coach.visible = true
	_coach_tween = create_tween()
	_coach_tween.tween_property(coach, "modulate:a", 1.0, 0.18)
	if _coach_foot.visible:   # the call to action breathes
		_coach_tween.tween_callback(func():
			var t := create_tween().set_loops()
			_coach_tween = t
			t.tween_property(_coach_foot, "modulate:a", 0.45, 0.5)
			t.tween_property(_coach_foot, "modulate:a", 1.0, 0.5))
	else:
		_coach_foot.modulate.a = 1.0

func hide_coach() -> void:
	if _coach_tween:
		_coach_tween.kill()
		_coach_tween = null
	if coach:
		coach.visible = false
		_coach_foot.modulate.a = 1.0

# ---------------------------------------------------------------- results
# rewards: [{ text, col }], badges that pop in one after the other under the title
# (new record, medal earned); the title bounces when there is any
var res_rewards: HFlowContainer
var res_cup: Button
var _res_tw: Tween
func show_results(title: String, rows: Array, note: String, has_next := false, cols := 3, rewards: Array = []) -> void:
	_show_rewards(rewards)
	res_cup.visible = false
	for ch in results.get_children():
		if ch.has_signal("finished"):   # an award show left from the last results
			ch.queue_free()
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
			var l := _label(str(cells[k]), 16, Paper.INK if hl else Paper.INK, f_bold if hl else f_med)
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			if k == cells.size() - 1:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if row.has("color") and k == 1:
				l.add_theme_color_override("font_color", Paper.ink_of(row["color"]))
			res_table.add_child(l)
	res_note.text = note
	results.visible = true
	hide_coach()
	hud.visible = false
	minimap.visible = false
	big.text = ""

func _show_rewards(rewards: Array) -> void:
	for ch in res_rewards.get_children():
		ch.queue_free()
	res_rewards.visible = not rewards.is_empty()
	if _res_tw:
		_res_tw.kill()
	res_title.scale = Vector2.ONE
	if rewards.is_empty():
		return
	_res_tw = create_tween()
	_res_tw.tween_interval(0.25)
	for i in rewards.size():
		var r: Dictionary = rewards[i]
		var b := _reward_badge(String(r["text"]), r["col"])
		b.modulate.a = 0.0
		res_rewards.add_child(b)
		# stamped onto the time card: it comes down big and fast, lands a little crooked,
		# and the card gives a small jolt
		var tilt := -0.05 if i % 2 == 0 else 0.04
		_res_tw.tween_callback(func():
			b.pivot_offset = b.size * 0.5
			b.scale = Vector2.ONE * 1.9
			b.rotation = tilt - 0.2
			b.modulate.a = 1.0
			reward_popped.emit(i))
		_res_tw.tween_property(b, "scale", Vector2.ONE, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_res_tw.parallel().tween_property(b, "rotation", tilt, 0.13)
		_res_tw.tween_property(results_panel, "position:y", results_panel.position.y + 3.0, 0.04)
		_res_tw.tween_property(results_panel, "position:y", results_panel.position.y, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if i == 0:   # the title answers the first badge with a little bounce
			_res_tw.parallel().tween_callback(func(): res_title.pivot_offset = Vector2(0, res_title.size.y * 0.5))
			_res_tw.parallel().tween_property(res_title, "scale", Vector2.ONE * 1.12, 0.12)
			_res_tw.tween_property(res_title, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_res_tw.tween_interval(0.2)

# a pill with a lit medal disc and a word in the reward colour
func _reward_badge(text: String, col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# a rubber stamp on the time card: the reward colour, inked dark enough to read on paper
	var inkc := Paper.ink_of(col)
	sb.bg_color = Color(col, 0.14)
	sb.border_color = inkc
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10; sb.content_margin_right = 14
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var disc := Control.new()
	disc.custom_minimum_size = Vector2(22, 22)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.draw.connect(func():
		var c := disc.size * 0.5
		disc.draw_circle(c, 10.0, col)
		disc.draw_circle(c, 6.0, col.lightened(0.45))
		disc.draw_circle(c + Vector2(-2.5, -2.5), 2.0, Color(1, 1, 1, 0.8)))
	hb.add_child(disc)
	var l := _label(text, 17, inkc, f_display)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	hb.add_child(l)
	p.add_child(hb)
	return p

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
