# Menu screens: Home -> Campaign (chapters of event cards) or Time attack (track cards)
# -> one Event screen (miniature, medals, Start). One thing at a time, big touch targets.
# Every screen is a page of the co-driver's roadbook (paper.gd): cream ruled paper with the
# live race showing round its edges, ink text, white index cards, tape and highlighter.
# Track and event lists are one long list: drag it up and down (it keeps gliding after a
# flick), or use the mouse wheel / arrow keys. The Event screen is a carousel: swipe sideways
# to the next track / event. A tap still presses the card under the finger; a drag never does.
extends Control

const TrackData = preload("res://scripts/track.gd")
const TrackMap = preload("res://scripts/track_map.gd")
const MedalStrip = preload("res://scripts/medal_strip.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Themes = preload("res://scripts/themes.gd")
const Records = preload("res://scripts/records.gd")
const Medals = preload("res://scripts/medals.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Rivals = preload("res://scripts/rivals.gd")
const Art = preload("res://scripts/menu_art.gd")
const Garage = preload("res://scripts/garage.gd")
const Cosmetics = preload("res://scripts/cosmetics.gd")
const Wallet = preload("res://scripts/wallet.gd")
const Daily = preload("res://scripts/daily.gd")
const Awards = preload("res://scripts/awards.gd")
const AwardMedal = preload("res://scripts/award_medal.gd")
const Paper = preload("res://scripts/paper.gd")
# world card pictures: the land of each theme, no track (tools/gen_loading_art.gd ART_SCENERY=1)
const WORLD_ART := {
	"snow": preload("res://art/world_snow.jpg"), "forest": preload("res://art/world_forest.jpg"),
	"sand": preload("res://art/world_sand.jpg"), "rock": preload("res://art/world_rock.jpg"),
}

signal start_event(ev: Dictionary)   # { track, variant, mode, humans, kind, idx }
signal settings_pressed
signal vehicle_picked(id: String)   # Garage: a vehicle tapped, rev its engine

# a light night-blue wash over the live race round the page
const C_BG_TOP := Color(0.03, 0.09, 0.15, 0.22)
const C_BG_BOT := Color(0.02, 0.06, 0.10, 0.34)
const C_CARD := Paper.CARD
const C_FG := Paper.INK
const C_MUTED := Paper.INK_SOFT
const C_ACCENT := Paper.INK   # no coloured accent: emphasis is ink (bolder, boxed)
const C_COIN := Paper.COIN_INK       # coin amounts: gold, inked
const MODE_NAMES := { "trial": "Time trial", "race": "Race" }

var ui                      # the UI CanvasLayer (fonts, helpers)
var screen := "home"
var kind := "campaign"      # campaign | attack | versus
var focus := -1            # list item (track or campaign event) to bring into view on the next list
var _list_scroll := {}     # list key -> how far that list was scrolled
var world := -1            # campaign: the world (chapter) whose events are listed, -1 = the world picker
var attack_theme := ""     # Time attack: the theme last picked, kept from track to track
var ev := {}                # the event shown on the Event screen
var _maps := {}             # track index -> TrackData for miniatures
var body: Control
var _pager: Pager          # the swipeable part of the Event screen
var _scroller: Scroller    # the scrolling list on the list screen
var _slide_from := 0       # -1 / +1: the screen being built slides in from that side

# A clipped window onto a tall list; `scroll` is how far down it is, `vel` keeps it gliding
# after a flick and springs it back when dragged past either end.
class Scroller extends Control:
	var content: Control
	var held := false
	var vel := 0.0
	var _bar: Control
	var scroll := 0.0:
		set(v):
			scroll = v
			_place()

	func hold(c: Control) -> void:
		content = c
		add_child(c)
		c.minimum_size_changed.connect(_place)
		_bar = Control.new()
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar.draw.connect(_draw_bar)
		add_child(_bar)
		_place()

	func span() -> float:
		return content.get_combined_minimum_size().y if content else 0.0

	func max_scroll() -> float:
		return maxf(0.0, span() - size.y)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_place()

	func _place() -> void:
		if content == null:
			return
		content.position = Vector2(0, -roundf(scroll))
		content.size = Vector2(size.x - 10.0, span())
		_bar.position = Vector2.ZERO
		_bar.size = size
		_bar.queue_redraw()

	# a thin frosted thumb on the right edge: how long the list is, and where you are
	func _draw_bar() -> void:
		var h := span()
		if h <= size.y + 1.0:
			return
		var bh := maxf(28.0, size.y * size.y / h)
		var y := (size.y - bh) * clampf(scroll / max_scroll(), 0.0, 1.0)
		_bar.draw_rect(Rect2(size.x - 4.0, y, 3.0, bh), Color(0.86, 0.93, 0.98, 0.4))

	func _process(dt: float) -> void:
		if held or content == null:
			return
		var top := 0.0
		var bottom := max_scroll()
		if scroll < top or scroll > bottom:   # past an end: spring back
			vel = 0.0
			var to := clampf(scroll, top, bottom)
			scroll = to if absf(scroll - to) < 0.5 else lerpf(scroll, to, 1.0 - exp(-14.0 * dt))
		elif absf(vel) > 6.0:
			scroll += vel * dt
			vel *= exp(-3.2 * dt)
			if scroll < top - 40.0 or scroll > bottom + 40.0:
				vel = 0.0
		else:
			vel = 0.0

# Holds one page; `shift` (in page widths) moves it sideways while the finger drags.
class Pager extends Control:
	var content: Control
	var shift := 0.0:
		set(v):
			shift = v
			_place()

	func hold(c: Control) -> void:
		content = c
		add_child(c)
		c.minimum_size_changed.connect(update_minimum_size)
		_place()

	func _get_minimum_size() -> Vector2:
		return content.get_combined_minimum_size() if content else Vector2.ZERO

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			_place()

	func _place() -> void:
		if content:
			content.position = Vector2(shift * size.x, 0)
			content.size = size
			modulate.a = 1.0 - clampf(absf(shift), 0.0, 1.0) * 0.6

func setup(owner_ui) -> void:
	ui = owner_ui
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	show_home()

func _draw() -> void:
	# soft vertical gradient behind every menu screen
	# one quad with per-corner colours: no banding between strips
	var mid := C_BG_TOP.lerp(C_BG_BOT, 0.35)
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), Vector2(size.x, size.y * 0.3), Vector2(0, size.y * 0.3)]),
		PackedColorArray([C_BG_TOP, C_BG_TOP, mid, mid]))
	draw_polygon(PackedVector2Array([Vector2(0, size.y * 0.3), Vector2(size.x, size.y * 0.3), Vector2(size.x, size.y), Vector2(0, size.y)]),
		PackedColorArray([mid, mid, C_BG_BOT, C_BG_BOT]))

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()

func _map(i: int) -> TrackData:
	if not _maps.has(i):
		_maps[i] = TrackData.new(Defs.TRACKS[i], "standard")
	return _maps[i]

# ---------------------------------------------------------------- frame
func _frame() -> VBoxContainer:
	if body:
		body.queue_free()
	if _scroller and _scroller.has_meta("list"):
		_list_scroll[_list_key()] = clampf(_scroller.scroll, 0.0, _scroller.max_scroll())
	_pager = null
	_scroller = null
	_drag = false
	if _flip_tween:
		_flip_tween.kill()
	if _slide_in:
		_slide_in.kill()
	var ins: Dictionary = ui.safe_insets()
	var tall: bool = ui.is_portrait()
	body = Control.new()
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body)
	# the page lies on the desk (the live race) with a little tilt. The home page is a smaller
	# sheet so the world shows round it, with its bookmark tabs (Awards, Garage, Settings)
	# sticking out of its right edge and the Track of the day photo beside it.
	var tabs := screen == "home"
	var desk := Control.new()   # the page and its tabs, tilted together
	desk.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(desk)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# the frame round the page covers the whole screen, tabs included: it must let taps
	# through to them (only the page and what is on it take taps)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := (10 if tall else 26) + 0
	m.add_theme_constant_override("margin_left", side + int(ins["l"]))
	m.add_theme_constant_override("margin_right", (TAB_W - 6 if tabs and tall else side) + int(ins["r"]))
	m.add_theme_constant_override("margin_top", (14 if tall else 16) + int(ins["t"]))
	m.add_theme_constant_override("margin_bottom", (12 if tall else 16) + int(ins["b"]))
	if tabs:
		if tall:   # portrait: the page as tall as what it holds, the photo under it
			m.anchor_bottom = 0.0
			m.add_theme_constant_override("margin_top", 60 + int(ins["t"]))
		else:      # landscape: the page on the left, the photo on the right
			m.anchor_right = HOME_PAGE_W
			m.anchor_bottom = 0.0   # as tall as what it holds
			m.add_theme_constant_override("margin_left", 40 + int(ins["l"]))
			m.add_theme_constant_override("margin_right", 0)
			m.add_theme_constant_override("margin_top", (26 if not _short() else 14) + int(ins["t"]))
	_tabs = null
	desk.add_child(m)
	var sheet := Paper.Sheet.new()
	sheet.rule_top = 86.0 if not tall else 70.0
	m.add_child(sheet)
	if tabs:
		# the bookmark tabs stick out of the page's right edge, wherever that edge ends up
		# (a long line can make the page wider than planned on a narrow phone). They lie on
		# top of the page, so nothing can cover them and every tap reaches them.
		_tabs = VBoxContainer.new()
		_tabs.add_theme_constant_override("separation", 6)
		desk.add_child(_tabs)
		var place_tabs := func():
			var r := Rect2(m.position + sheet.position, sheet.size)
			_tabs.position = Vector2(r.end.x - 10.0, r.position.y + (110.0 if tall else 70.0))
			_tabs.size = Vector2(TAB_W + 8, 0)
		sheet.item_rect_changed.connect(place_tabs)
		m.item_rect_changed.connect(place_tabs)
		sheet.margin_x = 26.0
		sheet.clip_x = 200.0 if not tall else 99999.0   # portrait: by the left corner, clear of the title
		sheet.get_theme_stylebox("panel").content_margin_left = 40
	# tilt the page round its own middle
	desk.rotation = deg_to_rad(HOME_TILT if tabs else PAGE_TILT)
	m.resized.connect(func(): desk.pivot_offset = m.position + m.size * 0.5)
	_page = sheet
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	sheet.add_child(vb)
	_land(desk)
	return vb

# a low landscape screen (a phone on its side): the home page packs tighter to fit
func _short() -> bool:
	return not ui.is_portrait() and get_viewport_rect().size.y < 560.0

const HOME_PAGE_W := 0.6      # landscape home: the page's share of the screen width
const HOME_TILT := -1.3       # degrees
const PAGE_TILT := -0.35
var _page: Paper.Sheet
var _last_screen := ""

static func _depth(scr: String) -> int:
	return { "home": 0, "worlds": 1, "list": 2, "garage": 1, "awards": 1, "event": 3 }.get(scr, 1)

# the page slides onto the desk and settles (only when the screen changes, not on a rebuild)
func _land(desk: Control) -> void:
	if screen == _last_screen or not is_inside_tree():
		_last_screen = screen
		return
	# deeper in (home -> list -> event): the new page comes in from the right, like turning
	# a page; going back it comes from the left; first show, it slides up onto the desk
	var dir := signi(_depth(screen) - _depth(_last_screen)) if _last_screen != "" else 0
	_last_screen = screen
	var rot := desk.rotation
	desk.position = Vector2(70.0 * dir, 36.0 if dir == 0 else 0.0)
	desk.rotation = rot + (0.05 * dir if dir != 0 else -0.035)
	desk.modulate.a = 0.0
	var tw := desk.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# slow enough to read as a page being laid down (it never blocks a tap)
	tw.tween_property(desk, "position", Vector2.ZERO, 0.55)
	tw.tween_property(desk, "rotation", rot, 0.7).set_trans(Tween.TRANS_BACK)
	tw.tween_property(desk, "modulate:a", 1.0, 0.3)

const TAB_W := 52
var _tabs: VBoxContainer

# a bookmark tab poking out of the page's right edge, in its own tint of paper
func _bookmark(icon: String, tint: Color, tip: String, cb: Callable) -> Button:
	var b: Button = ui.icon_button(icon, "", "card", false, 50)
	b.custom_minimum_size = Vector2(TAB_W + 8, 50)
	b.tooltip_text = tip
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var sb := Paper.box(tint.darkened(0.06) if st != "normal" else tint, Paper.INK, 0, 4)
		sb.corner_radius_top_left = 0; sb.corner_radius_bottom_left = 0
		sb.corner_radius_top_right = 9; sb.corner_radius_bottom_right = 9
		sb.shadow_offset = Vector2(2, 2)
		sb.content_margin_left = 8
		if st.contains("pressed"):
			sb.border_color = Paper.INK
			sb.border_width_right = 3
		b.add_theme_stylebox_override(st, sb)
	var ic: Art.Icon = b.get_meta("icon")
	ic.offset_left = 8   # clear of the page lying over the inner end
	b.pressed.connect(cb)
	_tabs.add_child(b)
	return b

# a double ink rule under a page's title, like the head of a roadbook sheet
func _rule(vb: VBoxContainer) -> void:
	var r := Control.new()
	r.custom_minimum_size.y = 7
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.draw.connect(func():
		r.draw_line(Vector2(0, 1), Vector2(r.size.x, 1), Paper.INK, 2.0)
		r.draw_line(Vector2(0, 5.5), Vector2(r.size.x, 5.5), Paper.INK, 1.0))
	# the page's ruled lines start under it
	r.item_rect_changed.connect(func():
		var sh := r.get_parent()
		while sh and not (sh is Paper.Sheet):
			sh = sh.get_parent()
		if sh:
			sh.rule_top = r.global_position.y - sh.global_position.y + 30.0
			sh.queue_redraw())
	vb.add_child(r)

# an icon drawn in ink, for the paper
func _icon(kind_: String, sz: float, col := Paper.INK) -> Art.Icon:
	var ic := Art.Icon.new()
	ic.kind = kind_
	ic.ink = true
	ic.col = col
	ic.col2 = Paper.INK
	ic.custom_minimum_size = Vector2(sz, sz)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic

func _header(vb: VBoxContainer, title: String, sub: String, back: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	if back.is_valid():
		var b: Button = ui.icon_button("back", "", "card", false, 50)
		b.tooltip_text = "Back"
		b.pressed.connect(back)
		hb.add_child(b)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t: Label = ui._label(title.to_upper(), 24, C_FG, ui.f_display)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	tv.add_child(Paper.highlight(t))
	if sub != "":
		var s: Label = ui._label(sub, 13, C_MUTED, ui.f_bold)
		# wraps instead of widening the page: a long line pushed the whole screen
		# past the right edge in portrait
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(s)
	hb.add_child(tv)
	vb.add_child(hb)
	_rule(vb)
	return hb

# a white index card lying on the page, outlined in ink; pressed, the outline thickens;
# locked, it is a greyer card pencilled in faintly
func _card_style(b: Button, locked := false) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var down: bool = st.contains("pressed")
		var s := Paper.box(C_CARD.darkened(0.04) if st.begins_with("hover") else C_CARD, Paper.INK, 3 if down else 2, 3)
		if locked:
			s = Paper.box(Paper.PAPER_DARK, Paper.INK_FAINT, 2, 0)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# a photo print lying on the desk: white border, a soft shadow; pressed, an ink edge
func _photo_style(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed"]:
		var s := Paper.box(Color("#fdfcf8") if not st.begins_with("hover") else Color("#f4f1ea"), Paper.INK, 3 if st.contains("pressed") else 0, 8)
		s.shadow_offset = Vector2(2, 5)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# a line of the roadbook: no card, an ink rule under it; pressed, the line is highlighted
func _line_style(b: Button) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Paper.HL if st.contains("pressed") else (Color(Paper.INK, 0.04) if st.begins_with("hover") else Color(0, 0, 0, 0))
		s.border_color = Paper.INK
		s.border_width_bottom = 2
		b.add_theme_stylebox_override(st, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# ---------------------------------------------------------------- home
func show_home() -> void:
	screen = "home"
	var vb := _frame()
	var tall: bool = ui.is_portrait()
	# the head of the page: the wordmark, the coins, then a caption and the medal cabinet
	var top := HBoxContainer.new()
	var logo := Art.Logo.new()
	logo.ink = true
	logo.font = ui.f_display
	logo.font_size = 24 if tall else (28 if _short() else 36)
	logo.custom_minimum_size = Vector2(0, 44 if tall else (46 if _short() else 60))
	logo.custom_minimum_size.x = logo.min_width()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(logo)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	var coins: Button = ui.icon_button("coin", str(Wallet.coins()), "card", false, 40 if tall else 46)
	coins.tooltip_text = "Coins: spend them in the Garage"
	coins.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coins.pressed.connect(show_garage)
	top.add_child(coins)
	vb.add_child(top)
	var sub := HBoxContainer.new()
	var cap: Label = ui._label("ROADBOOK  ·  CO-DRIVER'S NOTES" if not (tall or _short()) else "ROADBOOK", 12, C_MUTED, ui.f_bold)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.add_child(cap)
	var cab := Art.Cabinet.new()
	cab.ink = true
	cab.font = ui.f_bold
	cab.font_size = 14
	cab.counts = Campaign.medal_counts()
	cab.custom_minimum_size = Vector2(230, 24)
	cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_child(cab)
	vb.add_child(sub)
	_rule(vb)
	# bookmark tabs: Awards, Garage, Settings
	var cup := _bookmark("trophy", Color("#e6d9b8"), "Awards", show_awards)
	if Awards.ready_count() > 0:   # awards waiting to be collected: the cup gives a little hop now and then
		var ic: Control = cup.get_meta("icon")
		ic.pivot_offset = ic.custom_minimum_size * 0.5
		ic.resized.connect(func(): ic.pivot_offset = ic.size * 0.5)
		var hop := ic.create_tween().set_loops()
		hop.tween_interval(1.6)
		hop.tween_property(ic, "scale", Vector2.ONE * 1.25, 0.12).set_trans(Tween.TRANS_SINE)
		hop.tween_property(ic, "rotation", 0.25, 0.08)
		hop.tween_property(ic, "rotation", -0.25, 0.12)
		hop.tween_property(ic, "rotation", 0.0, 0.08)
		hop.tween_property(ic, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_bookmark("car", Paper.CARD, "Garage", show_garage)
	_bookmark("gear", Color("#d4d1c9"), "Settings", func(): settings_pressed.emit())
	# the three modes as numbered roadbook lines
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(lines)
	var cleared := 0
	for i in Campaign.count():
		if Campaign.cleared(i): cleared += 1
	var first := _first_open_event()
	var next_name: String = Themes.get_theme(Campaign.CHAPTERS[Campaign.chapter_of(first)]["theme"])["name"]
	lines.add_child(_road_line(1, "flag", "CAMPAIGN", "%d / %d events  ·  next: %s, event %d" % [cleared, Campaign.count(), next_name, first - Campaign.chapter_start(Campaign.chapter_of(first)) + 1],
		func(): kind = "campaign"; world = -1; show_list(), true))
	var n_open := Campaign.attack_tracks().size()
	var ta_sub := "%d tracks  ·  4 variants  ·  chase your ghost" % n_open if n_open == Defs.TRACKS.size() \
		else "%d / %d tracks open  ·  the campaign opens more" % [n_open, Defs.TRACKS.size()]
	lines.add_child(_road_line(2, "watch", "TIME ATTACK", ta_sub,
		func(): kind = "attack"; _list_scroll.erase(kind); show_list()))
	lines.add_child(_road_line(3, "duel", "2 PLAYERS", "One phone, two thumbs",
		func(): kind = "versus"; _list_scroll.erase(kind); show_list()))
	# a line of advice, handwritten under the lines
	var tip := Paper.note("Hook the tower into the bend, let go when the nose points out!", 22 if tall or _short() else 25)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.rotation = 0.0
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_top", 10)
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tm.add_child(tip)
	vb.add_child(tm)
	# a tick in the margin beside the line to play next
	var tick := Paper.note("✓", 34, Paper.PEN, 0.0)
	tick.position = Vector2(-34, 6)
	lines.get_child(0).add_child(tick)
	# the Track of the day: a photo lying on the desk beside (landscape) or under (portrait) the page
	var daily := _daily_banner()
	var ins: Dictionary = ui.safe_insets()
	if tall:
		daily.anchor_left = 0.12; daily.anchor_right = 0.88
		daily.anchor_top = 0.0; daily.anchor_bottom = 1.0
		daily.offset_bottom = -30 - int(ins["b"])
	else:
		daily.anchor_left = 0.0; daily.anchor_right = 1.0
		daily.anchor_top = 0.0; daily.anchor_bottom = 1.0
		daily.offset_right = -40 - int(ins["r"])
		daily.offset_top = 112 + int(ins["t"]); daily.offset_bottom = -110 - int(ins["b"])
	body.add_child(daily)
	# it lies clear of the page and its tabs: under the page (portrait) or right of the
	# tabs (landscape), however big the page turned out
	var page := _page
	var place_daily := func():
		var r := Rect2(page.get_parent().position + page.position, page.size)
		if tall:
			daily.offset_top = r.end.y + 22.0
		else:
			daily.offset_left = r.end.x + TAB_W + 30.0
	page.item_rect_changed.connect(place_daily)
	place_daily.call()
	daily.rotation = deg_to_rad(3.5 if not tall else 2.5)
	daily.resized.connect(func(): daily.pivot_offset = daily.size * 0.5)

# Track of the day: a photo of its world taped onto the page, its name and what it pays;
# tap it for its Event screen
func _daily_banner() -> Button:
	var p := Daily.current()
	var tall: bool = ui.is_portrait()
	var b := Button.new()
	_photo_style(b)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12; box.offset_right = -12; box.offset_top = 12; box.offset_bottom = -12
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.texture = WORLD_ART.get(Campaign.track_theme(p["track"]), WORLD_ART["snow"])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pic.custom_minimum_size.y = 70
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(_icon(p["variant"], 18))
	var hl: Label = ui._label("TRACK OF THE DAY", 12, C_MUTED, ui.f_bold)
	hl.autowrap_mode = TextServer.AUTOWRAP_OFF
	head.add_child(hl)
	tv.add_child(head)
	var name: Label = ui._label(String(p["name"]).to_upper(), 20, C_FG, ui.f_display)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.clip_text = true
	tv.add_child(name)
	var paid := Daily.paid_tier()
	var right := ""
	if paid < 0:
		right = "+%d coins" % Daily.BASE
	elif paid < Medals.NAMES.size():
		right = "Done  ·  +%d / medal" % Daily.PER_TIER
	else:
		right = "Done"
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for t in [_variant_name(p["variant"]), "·"]:
		var fl: Label = ui._label(t, 14, C_MUTED, ui.f_bold)
		fl.autowrap_mode = TextServer.AUTOWRAP_OFF
		foot.add_child(fl)
	var rl: Label = ui._label(right, 14, C_COIN, ui.f_bold)
	rl.autowrap_mode = TextServer.AUTOWRAP_OFF
	foot.add_child(rl)
	tv.add_child(foot)
	box.add_child(tv)
	b.add_child(box)
	# a strip of tape across the top edge holds the photo on the page
	var tape := Paper.Tape.new()
	tape.anchor_left = 0.5; tape.anchor_right = 0.5
	tape.offset_left = -46; tape.offset_right = 46; tape.offset_top = -12; tape.offset_bottom = 12
	b.add_child(tape)
	if paid < 0:   # not played yet today: a note in red pen on the photo
		var today := Paper.note("today!", 28 if not tall else 24, Paper.RED_INK, -0.14)
		today.anchor_left = 1.0; today.anchor_right = 1.0; today.anchor_top = 1.0; today.anchor_bottom = 1.0
		today.offset_left = -96; today.offset_top = -48
		b.add_child(today)
	b.pressed.connect(func():
		ev = { "track": p["track"], "variant": p["variant"], "mode": "trial", "humans": 1, "kind": "daily", "idx": 0,
			"theme": Campaign.track_theme(p["track"]) }
		show_event())
	return b

# one numbered line of the roadbook: number box, a tulip of a bend, the mode's icon and name
# (the next thing to play is highlighted), a line on what it holds, and an arrow
func _road_line(n: int, icon: String, title: String, sub: String, cb: Callable, hl := false) -> Button:
	var tall: bool = ui.is_portrait()
	var b := Button.new()
	_line_style(b)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 84 if tall else (62 if _short() else 80)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 2; h.offset_right = -4
	h.add_theme_constant_override("separation", 12 if tall else 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nb := Paper.NumBox.new()
	nb.text = str(n)
	nb.on = hl
	nb.font = ui.f_display
	nb.custom_minimum_size = Vector2(40, 40) if tall else Vector2(46, 46)
	nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nb)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 8)
	th.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(_icon(icon, 22 if tall else 26))
	var t: Label = ui._label(title, 21 if tall else 26, C_FG, ui.f_display)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	th.add_child(Paper.highlight(t) if hl else t)
	v.add_child(th)
	var sl: Label = ui._label(sub, 13 if tall else 14, C_MUTED, ui.f_bold)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.clip_text = true
	v.add_child(sl)
	h.add_child(v)
	h.add_child(_icon("next", 22))
	b.add_child(h)
	b.pressed.connect(cb)
	return b

static func _variant_name(v: String) -> String:
	for x in Defs.VARIANTS:
		if x[0] == v:
			return x[1]
	return v

func _first_open_event() -> int:
	for i in Campaign.count():
		if Campaign.unlocked(i) and not Campaign.cleared(i):
			return i
	return 0

# ---------------------------------------------------------------- garage
func show_garage() -> void:
	screen = "garage"
	var vb := _frame()
	var gsub := "Looks only, same car" if ui.is_portrait() else "Looks only, same car  ·  earn coins with medals, awards and the Track of the day"
	var hb := _header(vb, "Garage", gsub, func(): go_back())
	var coins: Button = ui.icon_button("coin", str(Wallet.coins()), "card", false, 50)
	coins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(coins)
	var g := Garage.new()
	g.on_coins = func(): coins.get_meta("label").text = str(Wallet.coins())
	vb.add_child(g)
	g.setup(self, Scroller)
	_scroller = g.scroller

# ---------------------------------------------------------------- awards
func show_awards() -> void:
	screen = "awards"
	var vb := _frame()
	var hb := _header(vb, "Awards", _awards_sub(), func(): go_back())
	var coins: Button = ui.icon_button("coin", str(Wallet.coins()), "card", false, 50)
	coins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(coins)
	var tall: bool = ui.is_portrait()
	var g := GridContainer.new()
	g.columns = 2 if tall else 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 10)
	# ready to collect first, then still to earn, then collected
	var order := Awards.LIST.duplicate()
	var rank := func(a): return 0 if Awards.ready(a["id"]) else (2 if Awards.claimed(a["id"]) else 1)
	order.sort_custom(func(x, y): return rank.call(x) < rank.call(y) or (rank.call(x) == rank.call(y) and Awards.LIST.find(x) < Awards.LIST.find(y)))
	for a in order:
		g.add_child(_award_tile(a, hb, coins))
	var list := VBoxContainer.new()
	list.add_child(g)
	var pad := Control.new()
	pad.custom_minimum_size.y = 8
	list.add_child(pad)
	_scroller = Scroller.new()
	_scroller.clip_contents = true
	_scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroller.hold(list)
	vb.add_child(_scroller)

func _awards_sub() -> String:
	var n := Awards.ready_count()
	var sub := "%d / %d earned" % [Awards.earned_count(), Awards.LIST.size()]
	return sub + ("  ·  %d to collect: tap them" % n if n > 0 else "  ·  each one pays coins once")

func _tile_style(b: Control, border: Color, bg: Color, width := 2) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg.lightened(0.05) if st.begins_with("hover") else bg
		sb.set_corner_radius_all(2)
		sb.border_color = border
		sb.set_border_width_all(width)
		sb.shadow_color = Color(0, 0, 0, 0.25)
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(0, 2)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# A rectangular tile: trophy (or lock), name, what to do, and the reward. An earned award
# glows amber with COLLECT +n until tapped.
func _award_tile(a: Dictionary, header: HBoxContainer, coins: Button) -> Button:
	var id: String = a["id"]
	var ready := Awards.ready(id)
	var got := Awards.claimed(id)
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 150 if ui.is_portrait() else 168)
	b.clip_contents = true
	var bg := C_CARD if (ready or got) else Paper.PAPER_DARK
	_tile_style(b, C_ACCENT if ready else (Paper.INK if got else Paper.INK_FAINT), bg, 3 if ready else 2)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10; v.offset_right = -10; v.offset_top = 10; v.offset_bottom = -10
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# an earned award shows its medallion (which plays its scene again when collected)
	var ic: Control
	var medal: AwardMedal = null
	if ready or got:
		medal = AwardMedal.new()
		medal.id = id
		ic = medal
		ic.custom_minimum_size = Vector2(44, 44)
	else:
		var lk := _icon("lock", 36, Paper.INK_FAINT)
		ic = lk
		ic.custom_minimum_size = Vector2(36, 36)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	var name: Label = ui._label(a["name"], 16, C_FG if (ready or got) else C_MUTED, ui.f_bold)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.clip_text = true
	v.add_child(name)
	var desc: Label = ui._label(a["desc"], 12, C_MUTED)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(desc)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fl: Label = ui._label("", 14, C_ACCENT, ui.f_display if ready else ui.f_bold)
	fl.autowrap_mode = TextServer.AUTOWRAP_OFF
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if ready:
		fl.text = "COLLECT +%d" % a["coins"]
		fl.add_theme_font_size_override("font_size", 17)
	elif got:
		fl.text = "Collected"
		fl.add_theme_color_override("font_color", C_MUTED)
	else:
		fl.text = "+%d" % a["coins"]
		fl.add_theme_color_override("font_color", C_FG)
	foot.add_child(fl)
	if not got:
		var coin := Art.Icon.new()
		coin.kind = "coin"
		coin.custom_minimum_size = Vector2(20, 20)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foot.add_child(coin)
	v.add_child(foot)
	b.add_child(v)
	if ready:
		# a slow breath (the card dims and comes back) so earned tiles catch the eye
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "self_modulate", Color(0.88, 0.88, 0.88), 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(b, "self_modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
		b.pressed.connect(func():
			var n := Awards.claim(id)
			if n <= 0:
				return
			ui.reward_popped.emit(1)
			coins.get_meta("label").text = str(Wallet.coins())
			# the tile pops, then the screen is rebuilt in its new order
			b.pivot_offset = b.size * 0.5
			var pop := b.create_tween()
			pop.tween_property(b, "scale", Vector2.ONE * 1.08, 0.08)
			pop.tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			fl.text = "+%d COINS!" % n
			medal.play()
			pop.tween_interval(AwardMedal.duration(id) - 0.2)
			pop.tween_callback(func():
				var keep := _scroller.scroll if _scroller else 0.0
				show_awards()
				_scroller.scroll = keep))
	else:
		b.mouse_filter = Control.MOUSE_FILTER_PASS
	return b

# ---------------------------------------------------------------- lists (one long scrolling list)
func show_list() -> void:
	if kind == "campaign":
		_show_campaign()
		return
	screen = "list"
	var vb := _frame()
	var title := "Time attack" if kind == "attack" else "2-player race"
	var order := _track_order()
	var open := Campaign.attack_tracks()
	var sub := "%d tracks  ·  pick one" % Defs.TRACKS.size()
	if kind == "attack" and open.size() < Defs.TRACKS.size():
		sub = "%d / %d tracks open  ·  the campaign opens the rest" % [open.size(), Defs.TRACKS.size()]
	var tall: bool = ui.is_portrait()
	_header(vb, title, sub, func(): go_back())
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	var cards := []   # in list order (_track_order)
	var grid := func() -> GridContainer:
		var g := GridContainer.new()
		g.columns = 1 if tall else 3   # portrait: one column of cards
		g.add_theme_constant_override("h_separation", 12)
		g.add_theme_constant_override("v_separation", 10 if tall else 12)
		list.add_child(g)
		return g
	var g: GridContainer = grid.call()
	for p in order.size():
		var b := _track_card(order[p], p + 1, kind != "attack" or open.has(order[p]))
		g.add_child(b)
		cards.append(b)
	var card_h := 92.0 if tall else 132.0
	for b in cards:
		b.custom_minimum_size.y = card_h
	var bottom := Control.new()   # breathing room under the last card
	bottom.custom_minimum_size.y = 8
	list.add_child(bottom)
	_scroller = Scroller.new()
	_scroller.clip_contents = true
	_scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroller.hold(list)
	_scroller.set_meta("list", true)
	vb.add_child(_scroller)
	_scroller.scroll = _list_scroll.get(_list_key(), 0.0)
	var fp := order.find(focus)   # focus is a track index here
	if fp >= 0:
		_reveal.call_deferred(_scroller, cards[fp])
	focus = -1

# the tracks of the Time attack / 2-player list, top to bottom: Time attack in the order the
# campaign opens them, so the open ones come first
func _track_order() -> Array:
	if kind == "attack":
		return Campaign.attack_order()
	return range(Defs.TRACKS.size())

# The campaign is one roadbook: a tab per world down the side (across the top in portrait),
# and the open world's 12 events as numbered lines, each with its track's outline and the
# medal stamped on it.
const WORLD_TINT := { "snow": Color("#d8e8f2"), "forest": Color("#d3e6c8"), "sand": Color("#eedcb4"), "rock": Color("#d6d0c6") }

func _show_campaign() -> void:
	if world < 0 or not Campaign.chapter_open(world):
		_show_worlds()
		return
	screen = "list"
	var vb := _frame()
	var tall: bool = ui.is_portrait()
	var cleared := 0
	for i in Campaign.count():
		if Campaign.cleared(i): cleared += 1
	_header(vb, "Campaign", "%d / %d events cleared with Gold  ·  Gold opens the next event" % [cleared, Campaign.count()] if not tall else "%d / %d events cleared" % [cleared, Campaign.count()], func(): go_back())
	var split: BoxContainer = VBoxContainer.new() if tall else HBoxContainer.new()
	split.add_theme_constant_override("separation", 0 if tall else 22)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(split)
	var tabs: BoxContainer = HBoxContainer.new() if tall else VBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4 if tall else 8)
	if not tall:
		tabs.custom_minimum_size.x = 230
	split.add_child(tabs)
	for c in Campaign.CHAPTERS.size():
		tabs.add_child(_world_tab(c, tall))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	split.add_child(right)
	if tall:   # the tabs sit on an ink line, the open one joined to the page under it
		var ln := ColorRect.new()
		ln.color = Paper.INK
		ln.custom_minimum_size.y = 3
		ln.mouse_filter = Control.MOUSE_FILTER_IGNORE
		right.add_child(ln)
	var ch: Dictionary = Campaign.CHAPTERS[world]
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap: Label = ui._label("WORLD %d  ·  %s" % [world + 1, String(ch["name"]).to_upper()], 12, C_MUTED, ui.f_bold)
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	hv.add_child(cap)
	var wt: Label = ui._label(String(Themes.get_theme(ch["theme"])["name"]).to_upper(), 22 if tall else 26, C_FG, ui.f_display)
	wt.autowrap_mode = TextServer.AUTOWRAP_OFF
	hv.add_child(Paper.highlight(wt))
	head.add_child(hv)
	var got := Campaign.chapter_golds(world)
	var hn := Paper.note("%d / %d golds" % [got, Campaign.chapter_size(world)], 22 if tall else 26, Paper.PEN, -0.05)
	hn.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(hn)
	right.add_child(head)
	var g := GridContainer.new()
	g.columns = 1 if tall else 2
	g.add_theme_constant_override("h_separation", 26)
	g.add_theme_constant_override("v_separation", 0)
	var lines := []
	var i0 := Campaign.chapter_start(world)
	if _seen_medal.is_empty():   # first look this session: nothing to stamp
		for i in Campaign.count():
			_seen_medal[i] = Campaign.event_medal(i)
	for k in Campaign.chapter_size(world):
		var b := _event_line(i0 + k, tall)
		g.add_child(b)
		lines.append(b)
		_seen_medal[i0 + k] = Campaign.event_medal(i0 + k)
	var list := VBoxContainer.new()
	list.add_child(g)
	var left := Campaign.chapter_size(world) - got
	if left > 0:
		var foot := Paper.note("%d more Gold%s for the %s stamp" % [left, "s" if left > 1 else "", Themes.get_theme(ch["theme"])["name"]], 21 if tall else 23, Paper.PENCIL, -0.02)
		var fm := MarginContainer.new()
		fm.add_theme_constant_override("margin_top", 8)
		fm.add_theme_constant_override("margin_bottom", 6)
		fm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fm.add_child(foot)
		list.add_child(fm)
	_scroller = Scroller.new()
	_scroller.clip_contents = true
	_scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroller.hold(list)
	_scroller.set_meta("list", true)
	right.add_child(_scroller)
	_scroller.scroll = _list_scroll.get(_list_key(), 0.0)
	if focus >= 0 and focus < lines.size():
		_reveal.call_deferred(_scroller, lines[focus])
	focus = -1

# The first step of the campaign: pick a world. The four worlds are photos taped onto the
# page, a little crooked; a locked one is greyed with a padlock and what opens it, a
# finished one is stamped DONE, and the one in play has a note in pen.
func _show_worlds() -> void:
	screen = "worlds"
	var vb := _frame()
	var tall: bool = ui.is_portrait()
	var cleared := 0
	for i in Campaign.count():
		if Campaign.cleared(i): cleared += 1
	_header(vb, "Campaign", "Pick a world  ·  %d / %d events cleared with Gold" % [cleared, Campaign.count()], func(): go_back())
	var g := GridContainer.new()
	g.columns = 2 if tall else 4
	g.add_theme_constant_override("h_separation", 18 if tall else 26)
	g.add_theme_constant_override("v_separation", 22)
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var wrap := MarginContainer.new()   # room for the tape and the tilt round the photos
	for side in ["left", "right", "top", "bottom"]:
		wrap.add_theme_constant_override("margin_" + side, 14 if side != "top" else 22)
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(g)
	vb.add_child(wrap)
	var playing := Campaign.chapter_of(_first_open_event())
	for c in Campaign.CHAPTERS.size():
		g.add_child(_world_photo(c, c == playing, tall))
	focus = -1

func _world_photo(c: int, playing: bool, tall: bool) -> Button:
	var ch: Dictionary = Campaign.CHAPTERS[c]
	var theme: String = ch["theme"]
	var open := Campaign.chapter_open(c)
	var done := open and Campaign.chapter_done(c)
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.disabled = not open
	_photo_style(b)
	b.add_theme_stylebox_override("disabled", b.get_theme_stylebox("normal"))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10; v.offset_right = -10; v.offset_top = 10; v.offset_bottom = -8
	v.add_theme_constant_override("separation", 4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.texture = WORLD_ART.get(theme, WORLD_ART["snow"])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.custom_minimum_size.y = 60
	pic.modulate = Color.WHITE if open else Color(0.5, 0.5, 0.5)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var cap: Label = ui._label("WORLD %d" % (c + 1), 11, C_MUTED, ui.f_bold)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cap)
	var name: Label = ui._label(String(Themes.get_theme(theme)["name"]).to_upper(), 17 if tall else 20, C_FG if open else C_MUTED, ui.f_display)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.clip_text = true
	v.add_child(name)
	var line := ""
	if not open:
		line = "Finish %s" % Themes.get_theme(Campaign.CHAPTERS[c - 1]["theme"])["name"]
	else:
		line = "%d / %d golds" % [Campaign.chapter_golds(c), Campaign.chapter_size(c)]
	var l2 := Paper.note(line, 19 if tall else 21, Paper.PEN if open else Paper.PENCIL, 0.0)
	v.add_child(l2)
	b.add_child(v)
	# a strip of tape at the top, a padlock on a shut world, a stamp on a finished one
	var tape := Paper.Tape.new()
	tape.tilt = -0.1 if c % 2 == 0 else 0.08
	tape.anchor_left = 0.5; tape.anchor_right = 0.5
	tape.offset_left = -40; tape.offset_right = 40; tape.offset_top = -12; tape.offset_bottom = 12
	b.add_child(tape)
	if not open:
		var lk := _icon("lock", 40, Paper.PAPER)
		lk.anchor_left = 0.5; lk.anchor_right = 0.5; lk.anchor_top = 0.3; lk.anchor_bottom = 0.3
		lk.offset_left = -20; lk.offset_right = 20; lk.offset_top = -20; lk.offset_bottom = 20
		b.add_child(lk)
	elif done:
		var st := Paper.Stamp.new()
		st.text = "DONE"
		st.col = Paper.INK
		st.font = ui.f_display
		st.anchor_left = 1.0; st.anchor_right = 1.0
		st.offset_left = -84; st.offset_right = -12; st.offset_top = 16; st.offset_bottom = 88
		b.add_child(st)
	if playing and not done:
		# a red-pen note on the photo's corner, on a scrap of paper so it reads on any picture
		var nx := Paper.note("you are here", 20 if tall else 23, Paper.RED_INK, 0.0)
		var tag := PanelContainer.new()
		var ts := Paper.box(Color("#fdfcf8"), Color.TRANSPARENT, 0, 3)
		ts.content_margin_left = 6; ts.content_margin_right = 6
		tag.add_theme_stylebox_override("panel", ts)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(nx)
		tag.anchor_left = 1.0; tag.anchor_right = 1.0
		tag.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		tag.offset_right = -4; tag.offset_top = 22
		tag.rotation = 0.1
		b.add_child(tag)
	# lie a little crooked on the page
	b.rotation = deg_to_rad([-2.0, 1.6, -1.2, 2.2][c % 4])
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.pressed.connect(func():
		world = c
		_list_scroll.erase(_list_key())
		var first := _first_open_event()
		focus = first - Campaign.chapter_start(c) if Campaign.chapter_of(first) == c else -1
		_show_campaign())
	return b

# a world's tab: its picture, name and medals; the open one is joined to the page, a locked
# one is greyed and can't be tapped
func _world_tab(c: int, tall: bool) -> Button:
	var theme: String = Campaign.CHAPTERS[c]["theme"]
	var open := Campaign.chapter_open(c)
	var on := c == world
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 52 if tall else 66
	b.disabled = not open
	var tint: Color = WORLD_TINT.get(theme, Paper.PAPER_DARK)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := Paper.box(tint.darkened(0.05) if st.begins_with("hover") else tint, Paper.INK, 0, 0)
		if on:
			sb.border_color = Paper.INK
			if tall:
				sb.border_width_left = 3; sb.border_width_right = 3; sb.border_width_top = 3
			else:   # outlined in ink and sticking out towards the events
				sb.set_border_width_all(3)
				sb.expand_margin_right = 12
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if not open:
		b.modulate.a = 0.6
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 6 if tall else 10; h.offset_right = -4; h.offset_top = 6; h.offset_bottom = -6
	h.add_theme_constant_override("separation", 8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER if tall else BoxContainer.ALIGNMENT_BEGIN
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not tall:
		var pic := TextureRect.new()
		pic.texture = WORLD_ART.get(theme, WORLD_ART["snow"])
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.custom_minimum_size = Vector2(66, 0)
		pic.modulate = Color.WHITE if open else Color(0.6, 0.6, 0.6)
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(pic)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl: Label = ui._label(String(Themes.get_theme(theme)["name"]).to_upper(), 11 if tall else 17, C_FG, ui.f_display)
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	if tall: nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nl)
	var sl: Label = ui._label("%d / %d" % [Campaign.chapter_golds(c), Campaign.chapter_size(c)] if open else "locked", 11 if tall else 14, C_MUTED, ui.f_bold)
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	if tall: sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sl)
	h.add_child(v)
	b.add_child(h)
	if open and Campaign.chapter_done(c) and not tall:
		var st := Paper.Stamp.new()   # a finished world: a small DONE stamp on its tab
		st.text = "DONE"
		st.col = Paper.INK
		st.font = ui.f_display
		st.anchor_left = 1.0; st.anchor_right = 1.0
		st.offset_left = -52; st.offset_right = -6; st.offset_top = 10; st.offset_bottom = 56
		b.add_child(st)
	b.pressed.connect(func():
		if c == world:
			return
		_list_scroll[_list_key()] = _scroller.scroll if _scroller else 0.0
		world = c
		var first := _first_open_event()
		focus = first - Campaign.chapter_start(c) if Campaign.chapter_of(first) == c else -1
		_show_campaign())
	return b

const MEDAL_STAMP := ["BRZ", "SLV", "GLD", "PVT"]
var _seen_medal := {}   # event -> medal it had when its line was last shown

# one event as a roadbook line: number, the track's outline in ink, its name and kind, then
# its medal stamp (or an arrow on the one to play next, a lock on the ones still shut)
func _event_line(i: int, tall: bool) -> Button:
	var e := Campaign.event(i)
	var locked := not Campaign.unlocked(i)
	var cur := i == _first_open_event()
	var medal := Campaign.event_medal(i)
	var n := i - Campaign.chapter_start(Campaign.chapter_of(i))
	var b := Button.new()
	_line_style(b)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size.y = 62
	b.disabled = locked
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 2; h.offset_right = -6; h.offset_top = 5; h.offset_bottom = -5
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.modulate.a = 0.45 if locked else 1.0
	var nb := Paper.NumBox.new()
	nb.text = str(n + 1)
	nb.on = cur
	nb.font = ui.f_display
	nb.custom_minimum_size = Vector2(36, 36)
	nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nb)
	var mp := TrackMap.new()
	mp.mini = true
	mp.ink = true
	mp.set_track(_map(e["track"]))
	mp.custom_minimum_size = Vector2(64, 0)
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(mp)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", -1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t: Label = ui._label(String(e["name"]).to_upper(), 17, C_FG, ui.f_display)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.clip_text = not cur   # the highlighter needs the word's full width
	v.add_child(Paper.highlight(t) if cur else t)
	var tl: Label = ui._label(_tag(e["variant"], e["mode"]), 13, C_MUTED, ui.f_bold)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.clip_text = true
	v.add_child(tl)
	h.add_child(v)
	if medal > 0:
		var st := Paper.Stamp.new()
		st.text = MEDAL_STAMP[medal - 1]
		st.col = Paper.ink_of(Medals.COLORS[medal - 1])
		st.font = ui.f_display
		st.custom_minimum_size = Vector2(48, 48)
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(st)
		if medal > int(_seen_medal.get(i, medal)):   # won since this list was last shown: stamp it now
			st.thump(0.75)
	elif locked:
		h.add_child(_icon("lock", 20))
	else:
		h.add_child(_icon("next", 24))
	b.add_child(h)
	b.pressed.connect(func():
		ev = { "track": e["track"], "variant": e["variant"], "mode": e["mode"], "humans": 1, "kind": "campaign", "idx": i, "theme": e.get("theme", "") }
		show_event())
	return b

# scroll just enough to show `card` (once the list has been laid out)
func _reveal(sc: Scroller, card: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(sc) or not is_instance_valid(card) or sc != _scroller:
		return
	var top := card.global_position.y - sc.content.global_position.y
	var bot := top + card.size.y
	if top < sc.scroll + 8.0 or bot > sc.scroll + sc.size.y - 8.0:
		sc.scroll = clampf(top - sc.size.y * 0.2, 0.0, sc.max_scroll())

func _card(track_i: int, line1: String, line2: String, medal: int, locked: bool, num := 0, cur := false) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	_card_style(b, locked)
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8; h.offset_right = -10; h.offset_top = 8; h.offset_bottom = -8
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if num > 0:   # the roadbook line number, filled in on the event to play next
		var nb := Paper.NumBox.new()
		nb.text = str(num)
		nb.on = cur
		nb.font = ui.f_display
		nb.custom_minimum_size = Vector2(34, 34)
		nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nb.modulate.a = 0.45 if locked else 1.0
		h.add_child(nb)
	var mp := TrackMap.new()
	mp.mini = true
	mp.ink = true
	mp.dim = locked
	mp.set_track(_map(track_i))
	mp.custom_minimum_size = Vector2(96, 0)
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.size_flags_stretch_ratio = 0.9
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(mp)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l1: Label = ui._label(line1, 17, C_FG if not locked else C_MUTED, ui.f_display)
	l1.autowrap_mode = TextServer.AUTOWRAP_OFF
	l1.clip_text = true
	v.add_child(l1)
	var l2: Label = ui._label(line2, 12, C_MUTED, ui.f_med)
	v.add_child(l2)
	var ms := MedalStrip.new()
	ms.ink = true
	ms.compact = true
	ms.custom_minimum_size = Vector2(0, 18)
	ms.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ms.set_state(medal, ["", "", "", ""])
	if not locked and medal >= 0:
		v.add_child(ms)
	h.add_child(v)
	b.add_child(h)
	return b

func _tag(variant: String, mode: String) -> String:
	var vn := ""
	for v in Defs.VARIANTS:
		if v[0] == variant: vn = v[1]
	return "%s  ·  %s" % [MODE_NAMES[mode], vn]

func _list_key() -> String:
	return "campaign%d" % world if kind == "campaign" else kind

# a track on the Time attack / 2-player list; in Time attack a track the campaign has not
# opened yet is greyed with a padlock and says which event opens it
func _track_card(i: int, num: int, open := true) -> Button:
	var name: String = Defs.TRACKS[i]["name"]
	var best := -1 if kind == "versus" else 0
	if kind == "attack":
		for v in Defs.VARIANTS:
			best = maxi(best, Campaign.medal(name, v[0], "trial"))
	var note: String = Defs.TRACKS[i]["note"]
	if not open:
		var fe := Campaign.first_event_of(i)
		var c := Campaign.chapter_of(fe)
		note = "Opens with %s, event %d" % [Themes.get_theme(Campaign.CHAPTERS[c]["theme"])["name"], fe - Campaign.chapter_start(c) + 1]
	var b := _card(i, name.to_upper(), note, best, not open, num)
	if not open:
		b.disabled = true
		b.get_child(0).add_child(_icon("lock", 20))
		return b
	b.pressed.connect(func():
		ev = { "track": i, "variant": "standard", "mode": "trial" if kind == "attack" else "race",
			"humans": 1 if kind == "attack" else 2, "kind": kind, "idx": i, "theme": _theme_for(i) }
		show_event())
	return b

# the theme a track opens in outside the campaign: the Time attack pick if it is
# still unlocked, else the track's own (or the menu's while that one is locked)
func _theme_for(track_i: int) -> String:
	if kind == "attack" and attack_theme != "" and Campaign.theme_unlocked(attack_theme):
		return attack_theme
	return Campaign.track_theme(track_i)

# ---------------------------------------------------------------- event
func show_event() -> void:
	screen = "event"
	var vb := _frame()
	var d: Dictionary = Defs.TRACKS[ev["track"]]
	var sub := ""
	match ev["kind"]:
		"campaign":
			var c := Campaign.chapter_of(ev["idx"])
			sub = "%s  ·  event %d of %d  ·  %s" % [Themes.get_theme(Campaign.CHAPTERS[c]["theme"])["name"], ev["idx"] - Campaign.chapter_start(c) + 1, Campaign.chapter_size(c), _tag(ev["variant"], ev["mode"])]
			if ev["mode"] == "race":
				sub += "  ·  %s rivals" % Rivals.tier_name(Rivals.campaign_tier(c))
		"attack": sub = "Time attack  ·  %d laps" % int(d.get("laps", 3))
		"daily":
			var paid := Daily.paid_tier()
			sub = "Track of the day  ·  %s  ·  %s" % [_variant_name(ev["variant"]),
				"+%d coins, +%d per medal" % [Daily.BASE, Daily.PER_TIER] if paid < 0 else "done today, a better medal pays +%d" % Daily.PER_TIER]
		"versus": sub = "2-player race  ·  %d laps" % int(d.get("laps", 3))
	_header(vb, d["name"], sub, func(): go_back())
	var tall: bool = ui.is_portrait()
	var row: BoxContainer = VBoxContainer.new() if tall else HBoxContainer.new()
	row.add_theme_constant_override("separation", 12 if tall else 18)
	_carousel(vb, row)
	var mp := TrackMap.new()
	mp.mini = true
	mp.ink = true
	mp.set_track(TrackData.new(d, ev["variant"]))
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the road drawn in ink on an index card
	var mpanel := PanelContainer.new()
	var ps := Paper.box(C_CARD, Paper.INK, 2, 3)
	ps.set_content_margin_all(12)
	mpanel.add_theme_stylebox_override("panel", ps)
	mpanel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mpanel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mpanel.size_flags_stretch_ratio = 0.85
	mpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mpanel.add_child(mp)
	row.add_child(mpanel)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tall:
		right.size_flags_vertical = Control.SIZE_SHRINK_END
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	right.add_child(ui._label(d["note"], 15, C_MUTED, ui.f_bold))
	if ev["kind"] in ["attack", "versus"]:
		var g := GridContainer.new()
		g.columns = 2 if tall else 4
		g.add_theme_constant_override("h_separation", 8)
		g.add_theme_constant_override("v_separation", 8)
		for v in Defs.VARIANTS:
			# portrait: icon beside the name (2 x 2); landscape: icon over it (one row of 4)
			var b: Button = ui.icon_button(v[0], v[1].to_upper(), "card", not tall, 50 if tall else 62)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ui.set_tile_on(b, v[0] == ev["variant"])
			b.pressed.connect(func(): ev["variant"] = v[0]; show_event())
			g.add_child(b)
		right.add_child(g)
	if ev["kind"] == "attack":
		# theme switcher: the worlds unlocked in the campaign; the rest show a lock
		var tg := GridContainer.new()
		tg.columns = 4
		tg.add_theme_constant_override("h_separation", 8)
		for t in Themes.ORDER:
			var open := Campaign.theme_unlocked(t)
			var tb: Button = ui.icon_button(t if open else "lock", String(Themes.get_theme(t)["name"]).to_upper(), "card", true, 54 if tall else 58)
			tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tb.tooltip_text = Themes.get_theme(t)["name"] if open else "Finish its campaign world to unlock"
			tb.disabled = not open
			ui.set_tile_on(tb, t == ev.get("theme", ""))
			tb.pressed.connect(func(): ev["theme"] = t; attack_theme = t; show_event())
			tg.add_child(tb)
		right.add_child(tg)
	var vdesc := ""
	for v in Defs.VARIANTS:
		if v[0] == ev["variant"]: vdesc = v[2]
	right.add_child(ui._label(vdesc, 13, C_MUTED))
	if ev["kind"] != "versus":
		var key := Records.key(d["name"], ev["variant"])
		var labels: Array = []
		var line := ""
		if ev["mode"] == "trial":
			for t in Medals.targets(d["name"], ev["variant"]):
				labels.append(ui.fmt2(t) if t > 0.0 else "--")
			var rec := Records.get_best(key)
			line = ("Your best %s: %s" % ["score" if ev["variant"] == "collect" else "lap", ui.fmt2(rec)]) if rec > 0.0 else "No time yet. Beat a target to win its medal."
			if gold_to_advance():
				line += " Gold opens the next event."
		else:
			labels = ["3rd", "2nd", "1st", "win +%d s" % int(Medals.RACE_TOP_GAP)]
			line = "Race 3 rivals. Finish on the podium for a medal."
			if gold_to_advance():
				line = "Race 3 rivals. Win for Gold: it opens the next event."
		var ms := MedalStrip.new()
		ms.ink = true
		ms.font = ui.f_bold
		ms.font_size = 13
		ms.custom_minimum_size = Vector2(0, 50)
		ms.set_state(Campaign.medal(d["name"], ev["variant"], ev["mode"]), labels)
		right.add_child(ms)
		right.add_child(ui._label(line, 14, C_ACCENT, ui.f_bold))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	var go: Button = ui.icon_button("play", "START", "go", false, 58)
	go.pressed.connect(func(): start_event.emit(ev.duplicate()))
	# room for its block shadow: the swipe pager clips at its edges
	var gm := MarginContainer.new()
	gm.add_theme_constant_override("margin_right", 5)
	gm.add_theme_constant_override("margin_bottom", 5)
	gm.add_child(go)
	right.add_child(gm)

# where the event screen sits in its carousel: [index, count]
func _event_pos() -> Array:
	if ev["kind"] == "daily":
		return [0, 1]
	if ev["kind"] == "campaign":
		var c := Campaign.chapter_of(ev["idx"])
		return [ev["idx"] - Campaign.chapter_start(c), Campaign.chapter_size(c)]
	var order := _track_order()
	return [order.find(ev["track"]), order.size()]

# ---------------------------------------------------------------- swipe
var _drag := false        # a press landed on the pager
var _dragging := false    # ...and has moved far enough sideways to be a swipe
var _drag_from := Vector2.ZERO
var _drag_ms := 0
var _flip_tween: Tween    # the page sliding out (input waits for it)
var _slide_in: Tween      # the next page sliding in (a press cuts it short)
const DRAG_START := 14.0  # px before a press turns into a swipe (a tap wiggles less)

# put `content` in a pager that fills the rest of the screen
func _carousel(vb: VBoxContainer, content: Control) -> void:
	_pager = Pager.new()
	_pager.clip_contents = true
	_pager.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pager.hold(content)
	vb.add_child(_pager)
	if _slide_from != 0:
		_pager.shift = _slide_from
		_slide_in = create_tween()
		_slide_in.tween_property(_pager, "shift", 0.0, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_slide_from = 0

# can the current screen flip one step that way (+1 next, -1 previous)?
func _can_flip(dir: int) -> bool:
	match screen:
		"event":
			var pos := _event_pos()
			if ev["kind"] in ["attack", "versus"]:
				return _flip_track(dir) >= 0
			var i: int = pos[0] + dir
			if i < 0 or i >= pos[1]:
				return false
			return ev["kind"] != "campaign" or Campaign.unlocked(ev["idx"] + dir)
	return false

func _flip(dir: int) -> void:
	_slide_from = dir
	match screen:
		"event":
			if ev["kind"] == "campaign":
				var e := Campaign.event(ev["idx"] + dir)
				ev = { "track": e["track"], "variant": e["variant"], "mode": e["mode"], "humans": 1, "kind": "campaign", "idx": e["idx"], "theme": e.get("theme", "") }

			else:
				ev["track"] = _flip_track(dir)
				ev["idx"] = ev["track"]
				ev["theme"] = _theme_for(ev["track"])
			show_event()

# the track a swipe that way lands on: the next one down the list (up for -1), skipping
# tracks Time attack has not opened yet; -1 at either end
func _flip_track(dir: int) -> int:
	var order := _track_order()
	var open := Campaign.attack_tracks() if ev["kind"] == "attack" else {}
	var p: int = order.find(ev["track"]) + dir
	while p >= 0 and p < order.size():
		if ev["kind"] != "attack" or open.has(order[p]):
			return order[p]
		p += dir
	return -1

# slide the page out, then build the next one sliding in (or bounce back)
func _settle(dir: int) -> void:
	if _flip_tween:
		_flip_tween.kill()
	if _slide_in:
		_slide_in.kill()
	var go := dir != 0 and _can_flip(dir)
	_flip_tween = create_tween()
	_flip_tween.tween_property(_pager, "shift", -float(dir) if go else 0.0, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN if go else Tween.EASE_OUT)
	# rebuilding also drops the card that saw the press, so it never fires after a swipe
	_flip_tween.tween_callback(func(): _flip(dir) if go else refresh())

func _blocked() -> bool:
	return (ui.settings_ov != null and ui.settings_ov.visible) or (ui.loading != null and ui.loading.visible)

var _samples: Array = []   # recent [ms, y] while dragging the list, for the flick speed
var _scroll_from := 0.0
const OFF := Vector2(-9999, -9999)

func _input(e: InputEvent) -> void:
	if (_pager == null and _scroller == null) or not is_visible_in_tree() or _blocked():
		_drag = false
		return
	if _scroller:
		_list_input(e)
	else:
		_event_input(e)

# the list: vertical drag with a glide, mouse wheel, up / down keys
func _list_input(e: InputEvent) -> void:
	var sc := _scroller
	if e is InputEventKey and e.pressed:
		match e.physical_keycode:
			KEY_UP: sc.vel = minf(sc.vel, 0.0) - 900.0
			KEY_DOWN: sc.vel = maxf(sc.vel, 0.0) + 900.0
			_: return
		get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseButton and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if e.pressed and sc.get_global_rect().has_point(e.position):
			var k := 1.0 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1.0
			sc.vel = (maxf(sc.vel * k, 0.0) + 700.0 * maxf(e.factor, 0.3)) * k
			get_viewport().set_input_as_handled()
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.position == OFF:
			return   # our own release that lets go of the card under the finger
		if e.pressed:
			_drag = sc.get_global_rect().has_point(e.position)
			_dragging = false
			_drag_from = e.position
			_scroll_from = sc.scroll
			if _drag and absf(sc.vel) > 60.0:
				sc.vel = 0.0   # touching a gliding list stops it, and is not a tap
				get_viewport().set_input_as_handled()
				_drag = false
		elif _drag:
			_drag = false
			if _dragging:
				_dragging = false
				sc.held = false
				get_viewport().set_input_as_handled()   # not a tap
				var now := Time.get_ticks_msec()
				var v := 0.0
				for smp in _samples:   # newest first: use the oldest one from the last 100 ms
					if now - smp[0] <= 100:
						v = -(e.position.y - smp[1]) / maxf(0.016, (now - smp[0]) / 1000.0)
				sc.vel = clampf(v, -5000.0, 5000.0)
	elif e is InputEventMouseMotion and _drag and e.position != OFF:
		var d: Vector2 = e.position - _drag_from
		if not _dragging and absf(d.y) > DRAG_START and absf(d.y) > absf(d.x):
			_dragging = true
			sc.held = true
			sc.vel = 0.0
			_samples.clear()
			_drag_from.y += signf(d.y) * DRAG_START   # follow from here, no jump
			_release_press.call_deferred()
		if _dragging:
			get_viewport().set_input_as_handled()
			var y: float = _scroll_from - (e.position.y - _drag_from.y)
			var top := 0.0
			var bottom := sc.max_scroll()
			if y < top:
				y = top - (top - y) * 0.35   # rubber band past the ends
			elif y > bottom:
				y = bottom + (y - bottom) * 0.35
			sc.scroll = y
			_samples.push_front([Time.get_ticks_msec(), e.position.y])
			if _samples.size() > 8:
				_samples.pop_back()

# the card that saw the press lets go off-screen, so it never fires once the list moves
func _release_press() -> void:
	var away := InputEventMouseMotion.new()   # the card sees the finger leave it...
	away.position = OFF
	away.global_position = OFF
	away.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(away, true)
	var up := InputEventMouseButton.new()     # ...and let go out there: no press
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = OFF
	up.global_position = OFF
	get_viewport().push_input(up, true)

# the event screen: sideways swipe to the next / previous track or event
func _event_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		var dir := 0
		match e.physical_keycode:
			KEY_LEFT: dir = -1
			KEY_RIGHT: dir = 1
		if dir != 0:
			get_viewport().set_input_as_handled()
			if _can_flip(dir) and not (_flip_tween and _flip_tween.is_running()):
				_settle(dir)
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			if _flip_tween and _flip_tween.is_running():
				get_viewport().set_input_as_handled()   # mid-flip: ignore
				return
			if _slide_in and _slide_in.is_running():
				_slide_in.kill()   # the page is still coming in: snap it home and take the press
				_pager.shift = 0.0
			_drag = _pager.get_global_rect().has_point(e.position)
			_dragging = false
			_drag_from = e.position
			_drag_ms = Time.get_ticks_msec()
		elif _drag:
			_drag = false
			if _dragging:
				_dragging = false
				get_viewport().set_input_as_handled()   # not a tap
				var f := _pager.shift
				var quick := Time.get_ticks_msec() - _drag_ms < 280 and absf(f) > 0.06
				_settle(-int(signf(f)) if absf(f) > 0.22 or quick else 0)
	elif e is InputEventMouseMotion and _drag:
		var d: Vector2 = e.position - _drag_from
		if not _dragging and absf(d.x) > DRAG_START and absf(d.x) > absf(d.y) * 1.2:
			_dragging = true
			_drag_from.x += signf(d.x) * DRAG_START   # start following from here, no jump
			d = e.position - _drag_from
		if _dragging:
			get_viewport().set_input_as_handled()
			var f := d.x / maxf(1.0, _pager.size.x)
			if not _can_flip(-int(signf(f))):
				f *= 0.25   # nothing that way: rubber band
			_pager.shift = clampf(f, -1.0, 1.0)

# rebuild the current screen (after a race, or when the screen size changes)
func refresh() -> void:
	match screen:
		"home": show_home()
		"list": show_list()
		"worlds": _show_worlds()
		"event": show_event()
		"garage": show_garage()
		"awards": show_awards()

# a campaign event short of Gold, with a next event in its world that Gold would open
func gold_to_advance() -> bool:
	if ev.get("kind", "") != "campaign":
		return false
	var i: int = ev["idx"]
	return not Campaign.cleared(i) and i + 1 < Campaign.count() and Campaign.chapter_of(i + 1) == Campaign.chapter_of(i) \
		and Campaign.event_medal(i + 1) == 0

# next campaign event after ev, if unlocked
func next_event() -> Dictionary:
	if ev.get("kind", "") != "campaign":
		return {}
	var i: int = ev["idx"] + 1
	if i >= Campaign.count() or not Campaign.unlocked(i) or Campaign.chapter_of(i) != Campaign.chapter_of(ev["idx"]):
		return {}
	var e := Campaign.event(i)
	return { "track": e["track"], "variant": e["variant"], "mode": e["mode"], "humans": 1, "kind": "campaign", "idx": i, "theme": e.get("theme", "") }

# back button: event -> list -> home; false on the home screen (the game may then quit)
func go_back() -> bool:
	match screen:
		"garage", "awards":
			show_home()
			return true
		"event":
			if ev["kind"] == "daily":
				show_home()
				return true
			focus = ev["idx"]   # the list comes back with this card in view
			if ev["kind"] == "campaign":
				world = Campaign.chapter_of(ev["idx"])
				focus = ev["idx"] - Campaign.chapter_start(world)
			show_list()
			return true
		"list":
			if kind == "campaign":   # the events of a world -> the world select
				world = -1
				_show_worlds()
			else:
				show_home()
			return true
		"worlds":
			show_home()
			return true
	return false
