# Menu screens: Home -> Campaign (chapters of event cards) or Time attack (track cards)
# -> one Event screen (miniature, medals, Start). One thing at a time, big touch targets.
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
signal sound_toggled(on: bool)

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
var sound_on := true

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
		var b := _btn("<", 52, 22)
		b.custom_minimum_size = Vector2(52, 46)
		b.add_theme_font_override("font", ui.f_display)
		b.add_theme_color_override("font_color", C_POST)
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

func _btn(text: String, h := 48, fs := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", fs)
	return b

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
	var top := HBoxContainer.new()
	var logo := Art.Logo.new()
	logo.font = ui.f_display
	logo.font_size = 40
	logo.custom_minimum_size = Vector2(0, 72)
	logo.custom_minimum_size.x = logo.min_width()
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(logo)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	var snd := _btn("SOUND ON" if sound_on else "SOUND OFF", 40, 12)
	snd.custom_minimum_size.x = 100
	snd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	snd.pressed.connect(func():
		sound_on = not sound_on
		snd.text = "SOUND ON" if sound_on else "SOUND OFF"
		sound_toggled.emit(sound_on))
	top.add_child(snd)
	vb.add_child(top)
	var sub := HBoxContainer.new()
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
	var row := HBoxContainer.new()
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
	var vs := Button.new()
	vs.custom_minimum_size = Vector2(0, 46)
	_card_style(vs)
	var vh := HBoxContainer.new()
	vh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vh.alignment = BoxContainer.ALIGNMENT_CENTER
	vh.add_theme_constant_override("separation", 10)
	vh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var di := Art.Icon.new()
	di.kind = "duel"
	di.custom_minimum_size = Vector2(30, 30)
	di.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	di.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vh.add_child(di)
	var vl: Label = ui._label("2 players on one phone: race any track", 14, C_FG, ui.f_bold)
	vl.autowrap_mode = TextServer.AUTOWRAP_OFF
	vh.add_child(vl)
	vs.add_child(vh)
	vs.pressed.connect(func(): kind = "versus"; page = 0; show_list())
	vb.add_child(vs)

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
		sub = "Page %d of %d  ·  pick a track" % [page + 1, _pages()]
	var hb := _header(vb, title, sub, func(): show_home())
	var prev := _btn("◀", 46, 18)
	prev.custom_minimum_size.x = 64
	prev.disabled = page == 0
	prev.pressed.connect(func(): page -= 1; show_list())
	hb.add_child(prev)
	var nxt := _btn("▶", 46, 18)
	nxt.custom_minimum_size.x = 64
	nxt.disabled = page >= _pages() - 1
	nxt.pressed.connect(func(): page += 1; show_list())
	hb.add_child(nxt)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	g.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(g)
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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(row)
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
	mpanel.size_flags_stretch_ratio = 0.85
	mpanel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mpanel.add_child(mp)
	row.add_child(mpanel)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	right.add_child(ui._label(d["note"], 15, C_MUTED, ui.f_bold))
	if ev["kind"] != "campaign":
		var g := GridContainer.new()
		g.columns = 4
		g.add_theme_constant_override("h_separation", 6)
		var grp := ButtonGroup.new()
		for v in Defs.VARIANTS:
			var b := _btn(v[1], 44, 13)
			b.toggle_mode = true
			b.button_group = grp
			b.clip_text = true
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.set_pressed_no_signal(v[0] == ev["variant"])
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
	var go := Button.new()
	go.text = "START"
	go.custom_minimum_size = Vector2(0, 56)
	ui._style_go(go)
	go.add_theme_font_size_override("font_size", 26)
	go.pressed.connect(func(): start_event.emit(ev.duplicate()))
	right.add_child(go)

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
