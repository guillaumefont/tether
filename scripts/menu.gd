# Menu screens: Home -> Campaign (chapters of event cards) or Time attack (track cards)
# -> one Event screen (miniature, medals, Start). One thing at a time, big touch targets.
# Lists and events are carousels: swipe sideways (or press the arrow keys) to flip to the
# next page / track / event; a tap still presses the card under the finger.
extends Control

const TrackData = preload("res://scripts/track.gd")
const TrackMap = preload("res://scripts/track_map.gd")
const MedalStrip = preload("res://scripts/medal_strip.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Records = preload("res://scripts/records.gd")
const Medals = preload("res://scripts/medals.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Art = preload("res://scripts/menu_art.gd")

signal start_event(ev: Dictionary)   # { track, variant, mode, humans, kind, idx }
signal settings_pressed

# translucent night-blue wash: the live snowy race behind the menu shows through
const C_BG_TOP := Color(0.03, 0.09, 0.15, 0.62)
const C_BG_BOT := Color(0.02, 0.06, 0.10, 0.70)
const C_CARD := Color(0.05, 0.11, 0.17, 0.82)
const C_FROST := Color(0.86, 0.93, 0.98, 0.55)
const C_FG := Color("#f3efe6")
const C_MUTED := Color("#9fb3b0")
const C_POST := Color("#f2b134")
const MODE_NAMES := { "trial": "Time trial", "race": "Race" }
const PER_PAGE := 6

var ui                      # the UI CanvasLayer (fonts, helpers)
var screen := "home"
var kind := "campaign"      # campaign | attack | versus
var page := 0
var ev := {}                # the event shown on the Event screen
var _maps := {}             # track index -> TrackData for miniatures
var body: Control
var _pager: Pager          # the swipeable part of the current screen (null on Home)
var _slide_from := 0       # -1 / +1: the screen being built slides in from that side

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
	_pager = null
	_drag = false
	if _flip_tween:
		_flip_tween.kill()
	var ins: Dictionary = ui.safe_insets()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 18 + int(ins["l"]))
	m.add_theme_constant_override("margin_right", 18 + int(ins["r"]))
	m.add_theme_constant_override("margin_top", 12 + int(ins["t"]))
	m.add_theme_constant_override("margin_bottom", 14 + int(ins["b"]))
	add_child(m)
	body = m
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	m.add_child(vb)
	return vb

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
	var t: Label = ui._label(title, 24, C_FG, ui.f_display)
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	t.add_theme_constant_override("shadow_offset_y", 2)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	tv.add_child(t)
	if sub != "":
		var s: Label = ui._label(sub, 13, C_MUTED, ui.f_bold)
		s.autowrap_mode = TextServer.AUTOWRAP_OFF
		tv.add_child(s)
	hb.add_child(tv)
	vb.add_child(hb)
	return hb

func _card_style(b: Button, locked := false) -> void:
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var s := StyleBoxFlat.new()
		s.bg_color = C_CARD.lightened(0.06) if st.begins_with("hover") else C_CARD
		if locked:
			s.bg_color = Color(C_CARD, 0.55)
		s.set_corner_radius_all(12)
		# a rim of frost along the top edge, like snow on a ledge
		s.border_color = C_POST if st.contains("pressed") else Color(1, 1, 1, 0.08)
		s.set_border_width_all(2)
		if not st.contains("pressed") and not locked:
			s.border_color = C_FROST if st.begins_with("hover") else Color(C_FROST, 0.4)
			s.border_width_top = 4
		s.shadow_color = Color(0, 0, 0, 0.25)
		s.shadow_size = 6
		s.shadow_offset = Vector2(0, 3)
		b.add_theme_stylebox_override(st, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# ---------------------------------------------------------------- home
func show_home() -> void:
	screen = "home"
	var vb := _frame()
	var tall: bool = ui.is_portrait()
	var top := HBoxContainer.new()
	var logo := Art.Logo.new()
	logo.font = ui.f_display
	logo.font_size = 27 if tall else 40
	logo.custom_minimum_size = Vector2(0, 56 if tall else 72)
	logo.custom_minimum_size.x = logo.min_width()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(logo)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	var gear: Button = ui.icon_button("gear", "", "card", false, 50)
	gear.tooltip_text = "Settings"
	gear.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gear.pressed.connect(func(): settings_pressed.emit())
	top.add_child(gear)
	vb.add_child(top)
	var sub: BoxContainer = VBoxContainer.new() if tall else HBoxContainer.new()
	var tag: Label = ui._label("Hold to hook the tower, let go to slide out.", 15, Art.C_ICE, ui.f_bold)
	tag.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	tag.add_theme_constant_override("shadow_offset_y", 1)
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.add_child(tag)
	var cab := Art.Cabinet.new()
	cab.font = ui.f_bold
	cab.counts = _medal_counts()
	cab.custom_minimum_size = Vector2(250, 26)
	cab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_child(cab)
	vb.add_child(sub)
	var row: BoxContainer = VBoxContainer.new() if tall else HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(row)
	var cleared := 0
	for i in Campaign.count():
		if Campaign.event_medal(i) > 0: cleared += 1
	row.add_child(_big_choice("flag", "CAMPAIGN", "%d / %d events cleared" % [cleared, Campaign.count()], "Hand-picked events. Earn a medal to unlock the next.",
		func(): kind = "campaign"; page = _first_open_chapter(); show_list()))
	row.add_child(_big_choice("watch", "TIME ATTACK", "%d tracks · 4 variants" % Defs.TRACKS.size(), "Any track, any variant. Chase your ghost and the medal times.",
		func(): kind = "attack"; page = 0; show_list()))
	row.add_child(_big_choice("duel", "2 PLAYERS", "One phone, two thumbs", "Race a friend on any track.",
		func(): kind = "versus"; page = 0; show_list()))

# best medal held on every track and variant (time trial), counted by tier
func _medal_counts() -> Array:
	var n := [0, 0, 0, 0]
	for d in Defs.TRACKS:
		for v in Defs.VARIANTS:
			var m := Campaign.medal(d["name"], v[0], "trial")
			if m > 0:
				n[m - 1] += 1
	return n

func _big_choice(icon: String, title: String, sub: String, desc: String, cb: Callable) -> Button:
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_card_style(b)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 20; v.offset_right = -20; v.offset_top = 16; v.offset_bottom = -16
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Art.Icon.new()
	ic.kind = icon
	ic.custom_minimum_size = Vector2(52, 52)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ic)
	v.add_child(ui._label(title, 30, C_POST, ui.f_display))
	v.add_child(ui._label(sub, 16, C_FG, ui.f_bold))
	v.add_child(ui._label(desc, 13, C_MUTED))
	b.add_child(v)
	b.pressed.connect(cb)
	return b

func _first_open_chapter() -> int:
	var i := 0
	for c in Campaign.CHAPTERS.size():
		for e in Campaign.CHAPTERS[c]["events"].size():
			if Campaign.unlocked(i) and Campaign.event_medal(i) == 0:
				return c
			i += 1
	return 0

# ---------------------------------------------------------------- lists (6 cards a page)
func _pages() -> int:
	if kind == "campaign":
		return Campaign.CHAPTERS.size()
	return ceili(Defs.TRACKS.size() / float(PER_PAGE))

func show_list() -> void:
	screen = "list"
	page = clampi(page, 0, _pages() - 1)
	var vb := _frame()
	var title := "Campaign" if kind == "campaign" else ("Time attack" if kind == "attack" else "2-player race")
	var sub := ""
	if kind == "campaign":
		sub = "Chapter %d of %d  ·  %s" % [page + 1, _pages(), Campaign.CHAPTERS[page]["name"]]
	else:
		sub = "Page %d of %d  ·  swipe for more" % [page + 1, _pages()]
	var tall: bool = ui.is_portrait()
	_header(vb, title, sub, func(): show_home())
	var g := GridContainer.new()
	g.columns = 1 if tall else 3   # portrait: one tall column of six cards
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 10 if tall else 12)
	_carousel(vb, g, page, _pages())
	if kind == "campaign":
		var first := 0
		for c in page:
			first += Campaign.CHAPTERS[c]["events"].size()
		for k in Campaign.CHAPTERS[page]["events"].size():
			g.add_child(_event_card(first + k))
	else:
		for i in range(page * PER_PAGE, mini(Defs.TRACKS.size(), (page + 1) * PER_PAGE)):
			g.add_child(_track_card(i))
	# keep the grid shape on a short last page
	while g.get_child_count() < PER_PAGE:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		g.add_child(sp)

func _card(track_i: int, line1: String, line2: String, medal: int, locked: bool) -> Button:
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
	var mp := TrackMap.new()
	mp.mini = true
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
	var l1: Label = ui._label(line1, 17, C_FG if not locked else C_MUTED, ui.f_bold)
	l1.autowrap_mode = TextServer.AUTOWRAP_OFF
	l1.clip_text = true
	v.add_child(l1)
	var l2: Label = ui._label(line2, 12, C_MUTED, ui.f_med)
	v.add_child(l2)
	var ms := MedalStrip.new()
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

func _event_card(i: int) -> Button:
	var e := Campaign.event(i)
	var locked := not Campaign.unlocked(i)
	var b := _card(e["track"], "%d. %s" % [i + 1, e["name"]], "Locked: earn a medal in event %d" % i if locked else _tag(e["variant"], e["mode"]), Campaign.event_medal(i), locked)
	b.disabled = locked
	b.pressed.connect(func():
		ev = { "track": e["track"], "variant": e["variant"], "mode": e["mode"], "humans": 1, "kind": "campaign", "idx": i }
		show_event())
	return b

func _track_card(i: int) -> Button:
	var name: String = Defs.TRACKS[i]["name"]
	var best := -1 if kind == "versus" else 0
	if kind == "attack":
		for v in Defs.VARIANTS:
			best = maxi(best, Campaign.medal(name, v[0], "trial"))
	var b := _card(i, name, Defs.TRACKS[i]["note"], best, false)
	b.pressed.connect(func():
		ev = { "track": i, "variant": "standard", "mode": "trial" if kind == "attack" else "race",
			"humans": 1 if kind == "attack" else 2, "kind": kind, "idx": i }
		show_event())
	return b

# ---------------------------------------------------------------- event
func show_event() -> void:
	screen = "event"
	var vb := _frame()
	var d: Dictionary = Defs.TRACKS[ev["track"]]
	var sub := ""
	match ev["kind"]:
		"campaign": sub = "Event %d of %d  ·  %s" % [ev["idx"] + 1, Campaign.count(), _tag(ev["variant"], ev["mode"])]
		"attack": sub = "Time attack  ·  %d laps" % int(d.get("laps", 3))
		"versus": sub = "2-player race  ·  %d laps" % int(d.get("laps", 3))
	_header(vb, d["name"], sub, func(): show_list())
	var tall: bool = ui.is_portrait()
	var row: BoxContainer = VBoxContainer.new() if tall else HBoxContainer.new()
	row.add_theme_constant_override("separation", 12 if tall else 18)
	var pos := _event_pos()
	_carousel(vb, row, pos[0], pos[1])
	var mp := TrackMap.new()
	mp.mini = true
	mp.set_track(TrackData.new(d, ev["variant"]))
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# the miniature sits on a frosted card so it never mixes with the live track behind
	var mpanel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_CARD
	ps.set_corner_radius_all(12)
	ps.border_color = Color(C_FROST, 0.4)
	ps.set_border_width_all(2)
	ps.border_width_top = 4
	ps.set_content_margin_all(10)
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
	if ev["kind"] != "campaign":
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
		else:
			labels = ["3rd", "2nd", "1st", "win +%d s" % int(Medals.RACE_TOP_GAP)]
			line = "Race 3 rivals. Finish on the podium for a medal."
		var ms := MedalStrip.new()
		ms.font = ui.f_bold
		ms.font_size = 13
		ms.custom_minimum_size = Vector2(0, 50)
		ms.set_state(Campaign.medal(d["name"], ev["variant"], ev["mode"]), labels)
		right.add_child(ms)
		right.add_child(ui._label(line, 14, C_POST, ui.f_bold))
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(fill)
	var go: Button = ui.icon_button("play", "START", "go", false, 58)
	go.pressed.connect(func(): start_event.emit(ev.duplicate()))
	right.add_child(go)

# where the event screen sits in its carousel: [index, count]
func _event_pos() -> Array:
	if ev["kind"] == "campaign":
		return [ev["idx"], Campaign.count()]
	return [ev["track"], Defs.TRACKS.size()]

# ---------------------------------------------------------------- swipe
var _drag := false        # a press landed on the pager
var _dragging := false    # ...and has moved far enough sideways to be a swipe
var _drag_from := Vector2.ZERO
var _drag_ms := 0
var _flip_tween: Tween
const DRAG_START := 14.0  # px before a press turns into a swipe (a tap wiggles less)

# put `content` in a pager that fills the rest of the screen, with page dots below
func _carousel(vb: VBoxContainer, content: Control, idx: int, count: int) -> void:
	_pager = Pager.new()
	_pager.clip_contents = true
	_pager.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pager.hold(content)
	vb.add_child(_pager)
	if count > 1:
		var dots := Art.Dots.new()
		dots.count = count
		dots.current = idx
		dots.custom_minimum_size = Vector2(0, 10)
		dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(dots)
	if _slide_from != 0:
		_pager.shift = _slide_from
		_flip_tween = create_tween()
		_flip_tween.tween_property(_pager, "shift", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_slide_from = 0

# can the current screen flip one step that way (+1 next, -1 previous)?
func _can_flip(dir: int) -> bool:
	match screen:
		"list":
			return page + dir >= 0 and page + dir < _pages()
		"event":
			var pos := _event_pos()
			var i: int = pos[0] + dir
			if i < 0 or i >= pos[1]:
				return false
			return ev["kind"] != "campaign" or Campaign.unlocked(i)
	return false

func _flip(dir: int) -> void:
	_slide_from = dir
	match screen:
		"list":
			page += dir
			show_list()
		"event":
			if ev["kind"] == "campaign":
				var e := Campaign.event(ev["idx"] + dir)
				ev = { "track": e["track"], "variant": e["variant"], "mode": e["mode"], "humans": 1, "kind": "campaign", "idx": e["idx"] }
				page = e["chapter"]   # Back returns to this event's chapter
			else:
				ev["track"] += dir
				ev["idx"] = ev["track"]
				page = ev["track"] / PER_PAGE
			show_event()

# slide the page out, then build the next one sliding in (or bounce back)
func _settle(dir: int) -> void:
	if _flip_tween:
		_flip_tween.kill()
	var go := dir != 0 and _can_flip(dir)
	_flip_tween = create_tween()
	_flip_tween.tween_property(_pager, "shift", -float(dir) if go else 0.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN if go else Tween.EASE_OUT)
	# rebuilding also drops the card that saw the press, so it never fires after a swipe
	_flip_tween.tween_callback(func(): _flip(dir) if go else refresh())

func _blocked() -> bool:
	return (ui.settings_ov != null and ui.settings_ov.visible) or (ui.loading != null and ui.loading.visible)

func _input(e: InputEvent) -> void:
	if _pager == null or not is_visible_in_tree() or _blocked():
		_drag = false
		return
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
		"event": show_event()

# next campaign event after ev, if unlocked
func next_event() -> Dictionary:
	if ev.get("kind", "") != "campaign":
		return {}
	var i: int = ev["idx"] + 1
	if i >= Campaign.count() or not Campaign.unlocked(i):
		return {}
	var e := Campaign.event(i)
	return { "track": e["track"], "variant": e["variant"], "mode": e["mode"], "humans": 1, "kind": "campaign", "idx": i }

# back button: event -> list -> home; false on the home screen (the game may then quit)
func go_back() -> bool:
	match screen:
		"event":
			show_list()
			return true
		"list":
			show_home()
			return true
	return false
