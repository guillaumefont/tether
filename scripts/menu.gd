# Menu screens: Home -> Campaign (chapters of event cards) or Time attack (track cards)
# -> one Event screen (miniature, medals, Start). One thing at a time, big touch targets.
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
# world card pictures: the land of each theme, no track (tools/gen_loading_art.gd ART_SCENERY=1)
const WORLD_ART := {
	"snow": preload("res://art/world_snow.jpg"), "forest": preload("res://art/world_forest.jpg"),
	"sand": preload("res://art/world_sand.jpg"), "rock": preload("res://art/world_rock.jpg"),
}

signal start_event(ev: Dictionary)   # { track, variant, mode, humans, kind, idx }
signal settings_pressed

# translucent night-blue wash: the live snowy race behind the menu shows through
const C_BG_TOP := Color(0.03, 0.09, 0.15, 0.62)
const C_BG_BOT := Color(0.02, 0.06, 0.10, 0.70)
const C_CARD := Color(0.05, 0.11, 0.17, 0.82)
const C_FROST := Color(0.86, 0.93, 0.98, 0.55)
const C_FG := Color("#f3efe6")
const C_MUTED := Color("#9fb3b0")
const C_ACCENT := Color("#4fb6ff")   # UI accent, same as Art.C_ACCENT
const C_COIN := Color("#f2b134")     # coin amounts stay gold
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
		# wraps instead of widening the page: a long line pushed the whole screen
		# past the right edge in portrait
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		s.border_color = C_ACCENT if st.contains("pressed") else Color(1, 1, 1, 0.08)
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
	# coins, awards and garage: in the top bar on a wide screen; on a phone held upright
	# the title needs that room, so they sit in the medal row under it
	var bh := 44 if tall else 50
	var side: Array = []
	var coins: Button = ui.icon_button("coin", str(Wallet.coins()), "card", false, bh)
	coins.tooltip_text = "Coins: spend them in the Garage"
	coins.pressed.connect(show_garage)
	side.append(coins)
	var cup: Button = ui.icon_button("trophy", "", "card", false, bh)
	cup.tooltip_text = "Awards"
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
	cup.pressed.connect(show_awards)
	side.append(cup)
	var car: Button = ui.icon_button("car", "", "card", false, bh)
	car.tooltip_text = "Garage"
	car.pressed.connect(show_garage)
	side.append(car)
	for b in side:
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not tall:
		for b in side:
			top.add_child(b)
			var sp := Control.new()
			sp.custom_minimum_size.x = 8
			top.add_child(sp)
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
	if tall:
		var mrow := HBoxContainer.new()
		mrow.add_theme_constant_override("separation", 10)
		cab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cab.custom_minimum_size.x = 0
		mrow.add_child(cab)
		for b in side:
			mrow.add_child(b)
		sub.add_child(mrow)
	else:
		sub.add_child(cab)
	vb.add_child(sub)
	vb.add_child(_daily_banner())
	var row: BoxContainer = VBoxContainer.new() if tall else HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(row)
	var cleared := 0
	for i in Campaign.count():
		if Campaign.event_medal(i) > 0: cleared += 1
	row.add_child(_big_choice("flag", "CAMPAIGN", "%d / %d events cleared" % [cleared, Campaign.count()], "Four worlds of hand-picked events. Finish one to unlock its theme.",
		func(): kind = "campaign"; world = -1; _list_scroll.erase(_list_key()); focus = Campaign.chapter_of(_first_open_event()); show_list()))
	row.add_child(_big_choice("watch", "TIME ATTACK", "%d tracks · 4 variants" % Defs.TRACKS.size(), "Any track, any variant. Chase your ghost and the medal times.",
		func(): kind = "attack"; _list_scroll.erase(kind); show_list()))
	row.add_child(_big_choice("duel", "2 PLAYERS", "One phone, two thumbs", "Race a friend on any track.",
		func(): kind = "versus"; _list_scroll.erase(kind); show_list()))

# Track of the day: a slim card under the title; tap it for its Event screen
func _daily_banner() -> Button:
	var p := Daily.current()
	var b := Button.new()
	b.custom_minimum_size.y = 62
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_card_style(b)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 14; hb.offset_right = -14
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Art.Icon.new()
	ic.kind = p["variant"]
	ic.custom_minimum_size = Vector2(34, 34)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(ui._label("TRACK OF THE DAY", 13, C_MUTED, ui.f_bold))
	var name: Label = ui._label("%s  ·  %s" % [p["name"], _variant_name(p["variant"])], 18, C_FG, ui.f_display)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.clip_text = true
	tv.add_child(name)
	hb.add_child(tv)
	var paid := Daily.paid_tier()
	var right := ""
	if paid < 0:
		right = "+%d" % Daily.BASE
	elif paid < Medals.NAMES.size():
		right = "Done · +%d / medal" % Daily.PER_TIER
	else:
		right = "Done"
	var rl: Label = ui._label(right, 16, C_COIN, ui.f_bold)
	rl.autowrap_mode = TextServer.AUTOWRAP_OFF
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(rl)
	if paid < 0:
		var coin := Art.Icon.new()
		coin.kind = "coin"
		coin.custom_minimum_size = Vector2(24, 24)
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(coin)
	b.add_child(hb)
	b.pressed.connect(func():
		ev = { "track": p["track"], "variant": p["variant"], "mode": "trial", "humans": 1, "kind": "daily", "idx": 0,
			"theme": Campaign.track_theme(p["track"]) }
		show_event())
	return b

static func _variant_name(v: String) -> String:
	for x in Defs.VARIANTS:
		if x[0] == v:
			return x[1]
	return v

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
	v.add_child(ui._label(title, 30, C_ACCENT, ui.f_display))
	v.add_child(ui._label(sub, 16, C_FG, ui.f_bold))
	v.add_child(ui._label(desc, 13, C_MUTED))
	b.add_child(v)
	b.pressed.connect(cb)
	return b

func _first_open_event() -> int:
	for i in Campaign.count():
		if Campaign.unlocked(i) and Campaign.event_medal(i) == 0:
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
		sb.set_corner_radius_all(14)
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
	var bg := Color(C_CARD, 0.82 if (ready or got) else 0.5)
	_tile_style(b, C_ACCENT if ready else (Color(C_ACCENT, 0.45) if got else Color(1, 1, 1, 0.08)), bg, 3 if ready else 2)
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
		var lk := Art.Icon.new()
		lk.kind = "lock"
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
		fl.add_theme_color_override("font_color", Color(C_ACCENT, 0.6))
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
		# a slow amber breath so earned tiles catch the eye
		var tw := b.create_tween().set_loops()
		tw.tween_property(b, "self_modulate", Color(1.25, 1.15, 0.9), 0.7).set_trans(Tween.TRANS_SINE)
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
	screen = "list"
	var vb := _frame()
	var title := "Campaign" if kind == "campaign" else ("Time attack" if kind == "attack" else "2-player race")
	var sub := ""
	if kind == "campaign" and world < 0:
		sub = "%d worlds  ·  finish one to open the next" % Campaign.CHAPTERS.size()
	elif kind == "campaign":
		var ch: Dictionary = Campaign.CHAPTERS[world]
		title = Themes.get_theme(ch["theme"])["name"]
		sub = "World %d  ·  %s  ·  %d / %d medals" % [world + 1, ch["name"], Campaign.chapter_medals(world), Campaign.chapter_size(world)]
	else:
		sub = "%d tracks  ·  pick one" % Defs.TRACKS.size()
	var tall: bool = ui.is_portrait()
	_header(vb, title, sub, func(): go_back())
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	var cards := []   # by track (attack, versus) or event index (campaign)
	var grid := func() -> GridContainer:
		var g := GridContainer.new()
		g.columns = 1 if tall else 3   # portrait: one column of cards
		g.add_theme_constant_override("h_separation", 12)
		g.add_theme_constant_override("v_separation", 10 if tall else 12)
		list.add_child(g)
		return g
	if kind == "campaign" and world < 0:
		var g: GridContainer = grid.call()
		g.columns = 1 if tall else 2
		for c in Campaign.CHAPTERS.size():
			var b := _world_card(c)
			g.add_child(b)
			cards.append(b)
	elif kind == "campaign":
		var g: GridContainer = grid.call()
		var i0 := Campaign.chapter_start(world)
		for k in Campaign.chapter_size(world):
			var b := _event_card(i0 + k)
			g.add_child(b)
			cards.append(b)
	else:
		var g: GridContainer = grid.call()
		for i in Defs.TRACKS.size():
			var b := _track_card(i)
			g.add_child(b)
			cards.append(b)
	var card_h := 92.0 if tall else 132.0
	if kind == "campaign" and world < 0:
		card_h = 200.0 if tall else 250.0   # world cards carry a picture
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
	if focus >= 0 and focus < cards.size():
		_reveal.call_deferred(_scroller, cards[focus])
	focus = -1

# scroll just enough to show `card` (once the list has been laid out)
func _reveal(sc: Scroller, card: Control) -> void:
	await get_tree().process_frame
	if not is_instance_valid(sc) or not is_instance_valid(card) or sc != _scroller:
		return
	var top := card.global_position.y - sc.content.global_position.y
	var bot := top + card.size.y
	if top < sc.scroll + 8.0 or bot > sc.scroll + sc.size.y - 8.0:
		sc.scroll = clampf(top - sc.size.y * 0.2, 0.0, sc.max_scroll())

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

func _list_key() -> String:
	return "campaign%d" % world if kind == "campaign" else kind

# a world of the campaign: a picture of its theme, its name, progress, and what opens it
func _world_card(c: int) -> Button:
	var ch: Dictionary = Campaign.CHAPTERS[c]
	var theme: String = ch["theme"]
	var th: Dictionary = Themes.get_theme(theme)
	var open := Campaign.chapter_open(c)
	var line2 := ""
	if not open:
		line2 = "Locked: finish %s" % Themes.get_theme(Campaign.CHAPTERS[c - 1]["theme"])["name"]
	elif Campaign.chapter_medals(c) == Campaign.chapter_size(c):
		line2 = "%s  ·  done, theme unlocked" % ch["name"]
	elif Campaign.chapter_done(c):   # finished in an earlier, shorter version of the world
		line2 = "%s  ·  %d / %d medals  ·  theme unlocked" % [ch["name"], Campaign.chapter_medals(c), Campaign.chapter_size(c)]
	else:
		line2 = "%s  ·  %d / %d medals" % [ch["name"], Campaign.chapter_medals(c), Campaign.chapter_size(c)]
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.clip_contents = true
	_card_style(b, not open)
	b.disabled = not open
	# the world's loading artwork, cropped to fill the card; greyed out while locked
	var pic := TextureRect.new()
	pic.texture = WORLD_ART.get(theme, WORLD_ART["snow"])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pic.offset_left = 3; pic.offset_top = 4; pic.offset_right = -3; pic.offset_bottom = -3
	pic.modulate = Color.WHITE if open else Color(0.42, 0.45, 0.5)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(pic)
	# dark fade along the bottom so the name reads on any picture
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.05, 0.08, 0.0))
	g.set_color(1, Color(0.02, 0.05, 0.08, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0.35)
	gt.fill_to = Vector2(0, 1)
	var fade := TextureRect.new()
	fade.texture = gt
	fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fade.stretch_mode = TextureRect.STRETCH_SCALE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(fade)
	var row := HBoxContainer.new()
	row.anchor_left = 0.0; row.anchor_right = 1.0; row.anchor_top = 1.0; row.anchor_bottom = 1.0
	row.offset_left = 14; row.offset_right = -14; row.offset_bottom = -10; row.offset_top = -60
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := Art.Icon.new()
	ic.kind = theme if open else "lock"
	ic.custom_minimum_size = Vector2(40, 40)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l1: Label = ui._label("%d · %s" % [c + 1, String(th["name"]).to_upper()], 22, C_FG if open else C_MUTED, ui.f_display)
	l1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l1.add_theme_constant_override("shadow_offset_y", 2)
	v.add_child(l1)
	var l2: Label = ui._label(line2, 13, C_ACCENT if open else C_MUTED, ui.f_bold)
	l2.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l2.add_theme_constant_override("shadow_offset_y", 1)
	v.add_child(l2)
	row.add_child(v)
	b.add_child(row)
	b.pressed.connect(func():
		world = c
		_list_scroll.erase(_list_key())
		var first := _first_open_event()
		focus = first - Campaign.chapter_start(c) if Campaign.chapter_of(first) == c else 0
		show_list())
	return b

func _event_card(i: int) -> Button:
	var e := Campaign.event(i)
	var locked := not Campaign.unlocked(i)
	var n := i - Campaign.chapter_start(Campaign.chapter_of(i))
	var b := _card(e["track"], "%d. %s" % [n + 1, e["name"]], "Locked: earn a medal in event %d" % n if locked else _tag(e["variant"], e["mode"]), Campaign.event_medal(i), locked)
	b.disabled = locked
	b.pressed.connect(func():
		ev = { "track": e["track"], "variant": e["variant"], "mode": e["mode"], "humans": 1, "kind": "campaign", "idx": i, "theme": e.get("theme", "") }
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
		else:
			labels = ["3rd", "2nd", "1st", "win +%d s" % int(Medals.RACE_TOP_GAP)]
			line = "Race 3 rivals. Finish on the podium for a medal."
		var ms := MedalStrip.new()
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
	right.add_child(go)

# where the event screen sits in its carousel: [index, count]
func _event_pos() -> Array:
	if ev["kind"] == "daily":
		return [0, 1]
	if ev["kind"] == "campaign":
		var c := Campaign.chapter_of(ev["idx"])
		return [ev["idx"] - Campaign.chapter_start(c), Campaign.chapter_size(c)]
	return [ev["track"], Defs.TRACKS.size()]

# ---------------------------------------------------------------- swipe
var _drag := false        # a press landed on the pager
var _dragging := false    # ...and has moved far enough sideways to be a swipe
var _drag_from := Vector2.ZERO
var _drag_ms := 0
var _flip_tween: Tween
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
		_flip_tween = create_tween()
		_flip_tween.tween_property(_pager, "shift", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_slide_from = 0

# can the current screen flip one step that way (+1 next, -1 previous)?
func _can_flip(dir: int) -> bool:
	match screen:
		"event":
			var pos := _event_pos()
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
				ev["track"] += dir
				ev["idx"] = ev["track"]
				ev["theme"] = _theme_for(ev["track"])
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
		"garage": show_garage()
		"awards": show_awards()

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
			if kind == "campaign" and world >= 0:
				focus = world
				world = -1
				show_list()
			else:
				show_home()
			return true
	return false
