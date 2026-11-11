# The Garage: pick the vehicle for each world, the paint, livery and rope colour. Visual
# only. A 3D stage shows the car turning on a plinth; below or beside it, four tabs and a
# scrolling grid of swatches. Items not owned yet can be tried on (the stage shows them);
# the bar under the stage offers to buy them with coins, or offers the paid pack.
extends BoxContainer

const Cosmetics = preload("res://scripts/cosmetics.gd")
const Store = preload("res://scripts/store.gd")
const Wallet = preload("res://scripts/wallet.gd")
const Campaign = preload("res://scripts/campaign.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Art = preload("res://scripts/menu_art.gd")

const Paper = preload("res://scripts/paper.gd")
# written on the roadbook paper (see paper.gd)
const C_FG := Paper.INK
const C_MUTED := Paper.INK_SOFT
const C_ACCENT := Paper.ACCENT_INK
const C_COIN := Paper.COIN_INK
const Themes = preload("res://scripts/themes.gd")
const Settings = preload("res://scripts/settings.gd")
const TABS := ["body", "paint", "livery", "rope"]
const TAB_NAMES := { "body": "Vehicle", "paint": "Paint", "livery": "Livery", "rope": "Rope" }
const TAB_ICONS := { "body": "car", "paint": "paint", "livery": "livery", "rope": "rope" }

var menu     # the menu (card style, ui helpers)
var ui
var tab := "body"
var home := ""            # the world whose vehicle is on the stage
var staged := []          # what the stage shows now
var on_coins: Callable    # the menu's coin counter, refreshed after a purchase
var trying := {}          # slot -> id of a locked item being tried on
var scroller              # menu.Scroller holding the grid
var stage: SubViewportContainer
var view: WorldView
var status: Label
var buy_btn: Button
var tab_btns := {}
var grid: GridContainer

func setup(owner_menu, scroller_class) -> void:
	menu = owner_menu
	ui = menu.ui
	var tall: bool = ui.is_portrait()
	vertical = tall
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	# the stage and the status bar under it
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.62 if tall else 1.0
	add_child(left)
	stage = SubViewportContainer.new()
	stage.stretch = true
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.world_3d = World3D.new()   # its own world: the race view behind the menu stays apart
	# the same antialiasing as the race view behind the menu: a different sample count
	# makes the phone compile every material's pipeline again, which stalls the opening
	vp.msaa_3d = Viewport.MSAA_DISABLED if int(Settings.get_opt("quality", Settings.default_quality())) == 0 else Viewport.MSAA_2X
	stage.add_child(vp)
	view = WorldView.new()
	vp.add_child(view)
	# the stage is a photo taped onto the page: a white border, a strip of tape at the top
	var photo := PanelContainer.new()
	var ps := Paper.box(Color("#fdfcf8"), Color.TRANSPARENT, 0, 7)
	ps.set_content_margin_all(10)
	photo.add_theme_stylebox_override("panel", ps)
	photo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	photo.add_child(stage)
	left.add_child(photo)
	photo.draw.connect(func():
		Paper.draw_tape(photo, Vector2(26, 8), 92, 24, -0.6)
		Paper.draw_tape(photo, Vector2(photo.size.x - 26, 8), 92, 24, 0.55))
	# the print lies a little crooked on the page
	photo.rotation = deg_to_rad(-1.2)
	photo.resized.connect(func(): photo.pivot_offset = photo.size * 0.5)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.custom_minimum_size.y = 44
	status = ui._label("", 14, C_FG, ui.f_bold)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(status)
	buy_btn = ui.icon_button("spark", "Buy", "go", false, 44)
	buy_btn.pressed.connect(_buy)
	bar.add_child(buy_btn)
	left.add_child(bar)
	# tabs and the swatch grid
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(right)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	home = Campaign.menu_theme()
	for t in TABS:
		# portrait: icon above the name, so four tabs fit a phone's width
		var b: Button = ui.icon_button(TAB_ICONS[t], TAB_NAMES[t], "card", tall, 52 if tall else 44)
		if tall:
			b.custom_minimum_size.x = 0
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_tab.bind(t))
		tabs.add_child(b)
		tab_btns[t] = b
	right.add_child(tabs)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var list := VBoxContainer.new()
	list.add_child(grid)
	var pad := Control.new()
	pad.custom_minimum_size.y = 8
	list.add_child(pad)
	scroller = scroller_class.new()
	scroller.clip_contents = true
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.hold(list)
	right.add_child(scroller)
	_show_tab.call_deferred()

func _process(dt: float) -> void:
	if view and view.showroom_rig:
		view.turn_showroom(dt)

# ---------------------------------------------------------------- state
func shown(slot: String) -> String:
	if slot == "body":
		return trying.get(slot, Cosmetics.equipped_body(home))
	return trying.get(slot, Cosmetics.equipped(slot))

func _restage() -> void:
	if view.camera == null:
		return
	var w3d: World3D = view.get_viewport().world_3d
	if w3d.environment != view.env:
		w3d.environment = view.env
	var key := [shown("paint"), shown("livery"), shown("rope"), shown("body"), home]
	if key == staged:
		return   # same car as on the stage: switching tabs needn't rebuild it
	staged = key
	view.showroom(Cosmetics.look(key[0], key[1], key[2], key[3]), home)

func _set_tab(t: String) -> void:
	tab = t
	scroller.scroll = 0.0
	_show_tab()

func _show_tab() -> void:
	for t in tab_btns:
		ui.set_tile_on(tab_btns[t], t == tab)
	var cols := 3 if ui.is_portrait() else 3
	grid.columns = cols
	for ch in grid.get_children():
		ch.queue_free()
	for it in Cosmetics.items(tab):
		grid.add_child(_tile(it))
	if staged.is_empty():
		await get_tree().process_frame   # first open: show the screen, then build the stage
		if not is_inside_tree():
			return
	_restage()
	_update_status()

func _pick(it: Dictionary) -> void:
	if tab == "body":
		menu.vehicle_picked.emit(it["id"])   # a taste of its engine
	if tab == "body" and it["home"] != home:
		home = it["home"]   # the stage moves to that vehicle's world
		trying.erase("body")
	if Cosmetics.owned(tab, it):
		Cosmetics.equip(tab, it["id"])
		trying.erase(tab)
	else:
		trying[tab] = it["id"]
	_show_tab()

func _update_status() -> void:
	buy_btn.visible = false
	var it := Cosmetics.find(tab, shown(tab))
	if not trying.has(tab):
		status.text = "%s  ·  equipped" % it["name"]
		if tab == "body":
			status.text = "%s  ·  driven in %s" % [it["name"], Themes.get_theme(it["home"])["name"]]
		status.add_theme_color_override("font_color", C_FG)
		return
	status.add_theme_color_override("font_color", C_ACCENT)
	var u: Dictionary = it["unlock"]
	var l: Label = buy_btn.get_meta("label")
	if u.has("product"):
		var pr := Store.product(u["product"])
		status.text = "%s: part of the %s" % [it["name"], pr["name"]]
		buy_btn.get_meta("icon").kind = "spark"
		l.text = pr["price"] if Store.available() else "Soon"
		buy_btn.disabled = not Store.available()
		buy_btn.visible = true
		return
	if not Cosmetics.can_buy_yet(it):
		status.text = "Trying on %s. %s" % [it["name"], Cosmetics.requirement(it)]
		return
	var cost := Cosmetics.price(it)
	var short := cost - Wallet.coins()
	status.text = "Trying on %s" % it["name"] if short <= 0 else "Trying on %s. %d more coins needed" % [it["name"], short]
	l.text = "%d" % cost
	buy_btn.get_meta("icon").kind = "coin"
	buy_btn.disabled = short > 0
	buy_btn.visible = true

func _buy() -> void:
	var it := Cosmetics.find(tab, shown(tab))
	var u: Dictionary = it["unlock"]
	if u.has("product"):
		var res := Store.buy(u["product"])
		if res == "ok" or res == "owned":
			Cosmetics.equip(tab, it["id"])
			trying.erase(tab)
			_show_tab()
			status.text = "%s unlocked. Thank you!" % Store.product(u["product"])["name"]
		else:
			status.text = "The store isn't open yet."
		return
	if Cosmetics.buy(tab, it) == "ok":
		Cosmetics.equip(tab, it["id"])
		trying.erase(tab)
		_show_tab()
		status.text = "%s bought and equipped. %d coins left" % [it["name"], Wallet.coins()]
		if on_coins.is_valid():
			on_coins.call()

# ---------------------------------------------------------------- tiles
func _tile(it: Dictionary) -> Button:
	var open := Cosmetics.owned(tab, it)
	var on: bool = it["id"] == shown(tab)
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 112 if ui.is_portrait() else 118)
	b.clip_contents = true
	menu._card_style(b, not open)
	if on:
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
			sb.border_color = C_ACCENT
			sb.set_border_width_all(3)
			b.add_theme_stylebox_override(st, sb)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 6; v.offset_right = -6; v.offset_top = 8; v.offset_bottom = -6
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sw := Swatch.new()
	sw.slot = tab
	sw.item = it
	sw.body = Cosmetics.find("paint", shown("paint"))["color"]
	sw.dim = not open
	sw.custom_minimum_size = Vector2(0, 52)
	sw.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sw)
	var name: Label = ui._label(it["name"], 13, C_FG if open else C_MUTED, ui.f_bold)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.clip_text = true
	v.add_child(name)
	var sub := ""
	var sub_col := C_MUTED
	if open:
		sub = "Equipped" if Cosmetics.is_equipped(tab, it) else ""
		sub_col = C_ACCENT
		if tab == "body" and sub == "":
			sub = Themes.get_theme(it["home"])["name"]
			sub_col = C_MUTED
	elif it["unlock"].has("product"):
		sub = Store.product(it["unlock"]["product"])["price"]
		sub_col = C_ACCENT
	elif not Cosmetics.can_buy_yet(it):
		sub = _short_req(it)
	else:
		sub = "%d coins" % Cosmetics.price(it)
		sub_col = C_COIN if Cosmetics.price(it) <= Wallet.coins() else C_MUTED
	var sl: Label = ui._label(sub, 11, sub_col, ui.f_med)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.clip_text = true
	v.add_child(sl)
	b.add_child(v)
	if not open:
		var lk := Art.Icon.new()
		lk.ink = true
		lk.col = Paper.INK_SOFT
		lk.kind = "lock" if not Cosmetics.can_buy_yet(it) or it["unlock"].has("product") else "coin"
		lk.custom_minimum_size = Vector2(22, 22)
		lk.position = Vector2(6, 6)
		lk.size = Vector2(22, 22)
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lk)
	b.pressed.connect(_pick.bind(it))
	return b

static func _short_req(it: Dictionary) -> String:
	var u: Dictionary = it["unlock"]
	if u.has("world"): return String(Campaign.CHAPTERS[u["world"]]["theme"]).capitalize() + " world"
	return ""

# A small drawing of an item: a paint blob with its finish, a car from above wearing a
# livery, or a length of rope.
class Swatch extends Control:
	var slot := "paint"
	var item := {}
	var body := Color("#f2b134")
	var dim := false

	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y)
		var a := 0.55 if dim else 1.0
		match slot:
			"paint":
				var col: Color = item["color"]
				var r := s * 0.42
				draw_circle(c, r, Color(col.darkened(0.35), a))
				draw_circle(c - Vector2(r, r) * 0.08, r * 0.86, Color(col, a))
				match String(item["finish"]):
					"gloss", "pearl":
						draw_circle(c + Vector2(-r * 0.35, -r * 0.35), r * 0.18, Color(1, 1, 1, 0.55 * a))
						if item["finish"] == "pearl":
							draw_arc(c, r * 0.7, -2.6, -0.6, 16, Color(1, 1, 1, 0.35 * a), r * 0.12, true)
					"metallic":
						for k in 6:
							var p := c + Vector2.from_angle(k * 2.1) * r * (0.2 + 0.1 * k)
							draw_circle(p, r * 0.05, Color(1, 1, 1, 0.5 * a))
					"chrome":
						draw_rect(Rect2(c + Vector2(-r * 0.75, -r * 0.1), Vector2(r * 1.5, r * 0.12)), Color(0.05, 0.05, 0.06, 0.7 * a))
						draw_circle(c + Vector2(-r * 0.3, -r * 0.45), r * 0.15, Color(1, 1, 1, 0.8 * a))
					"neon":
						draw_arc(c, r * 1.06, 0, TAU, 40, Color(col, 0.5 * a), r * 0.14, true)
			"body":
				_draw_vehicle(String(item["id"]), a)
			"rope":
				var col: Color = item["color"]
				if col.a == 0.0:
					col = body
				var pts := PackedVector2Array()
				for k in 25:
					var t := k / 24.0
					pts.append(Vector2(lerpf(size.x * 0.12, size.x * 0.88, t), c.y + sin(t * TAU) * s * 0.12))
				draw_polyline(pts, Color(col, a), maxf(4.0, s * 0.1), true)
			"livery":
				# the car from above, nose to the right
				var w := minf(size.x * 0.8, s * 2.0)
				var h := w * 0.48
				var r := Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
				var acc := Color("#1d2229") if body.get_luminance() > 0.62 else Color("#f4f1ea")
				draw_rect(r, Color(body, a))
				var x0 := r.position.x
				var y0 := r.position.y
				var lv := String(item["id"])
				match lv:
					"stripes":
						for z in [0.36, 0.56]:
							draw_rect(Rect2(Vector2(x0, y0 + h * z), Vector2(w, h * 0.09)), Color(acc, a))
					"number":
						draw_circle(Vector2(x0 + w * 0.17, c.y), h * 0.28, Color(acc, a))
					"flash":
						for k in 3:
							draw_rect(Rect2(Vector2(x0 + w * (0.1 + k * 0.08), y0 + h * (0.05 + k * 0.05)), Vector2(w * 0.6, h * 0.04)), Color(acc, a))
							draw_rect(Rect2(Vector2(x0 + w * (0.1 + k * 0.08), y0 + h * (0.91 - k * 0.05)), Vector2(w * 0.6, h * 0.04)), Color(acc, a))
					"twotone":
						draw_rect(Rect2(Vector2(x0, y0), Vector2(w * 0.53, h)), Color(acc, a))
					"checker":
						var sq := h / 6.0
						for row in 6:
							for k in 2:
								if (row + k) % 2 == 0:
									draw_rect(Rect2(Vector2(x0 + w * 0.8 + k * sq, y0 + row * sq), Vector2(sq, sq)), Color(Color("#1d2229"), a))
								else:
									draw_rect(Rect2(Vector2(x0 + w * 0.8 + k * sq, y0 + row * sq), Vector2(sq, sq)), Color(Color("#f4f1ea"), a))
					"bolt":
						draw_colored_polygon(PackedVector2Array([Vector2(x0 + w * 0.2, y0 + h * 0.3), Vector2(x0 + w * 0.55, y0 + h * 0.42),
							Vector2(x0 + w * 0.5, y0 + h * 0.55), Vector2(x0 + w * 0.8, y0 + h * 0.7), Vector2(x0 + w * 0.42, y0 + h * 0.6),
							Vector2(x0 + w * 0.47, y0 + h * 0.47)]), Color(acc, a))
					"glow":
						draw_rect(r.grow(2.0), Color(Color("#3ff2ff"), 0.9 * a), false, 3.0)
				# the glasshouse on top
				draw_rect(Rect2(Vector2(x0 + w * 0.3, y0 + h * 0.12), Vector2(w * 0.42, h * 0.76)), Color(Color("#1a2330"), a))
				if lv == "twotone":
					draw_rect(Rect2(Vector2(x0 + w * 0.3, y0 + h * 0.2), Vector2(w * 0.23, h * 0.6)), Color(acc, a))
				elif lv == "stripes":
					for z in [0.36, 0.56]:
						draw_rect(Rect2(Vector2(x0 + w * 0.3, y0 + h * z), Vector2(w * 0.23, h * 0.09)), Color(acc, a))

	# The vehicles from the side, nose to the right, in the car's own units (WorldView):
	# [kind, points] with kind body (the paint), low (darker paint), glass, dark, light,
	# wood, accent (a fixed colour given as the third entry); a wheel is ["wheel", x, r] and
	# a tube is ["line", points].
	const SIDES := {
		"sled": [["dark", [Vector2(-60, 0), Vector2(-4, 0), Vector2(4, 14), Vector2(-64, 14)]],
			["light", [Vector2(24, 0), Vector2(62, 0), Vector2(70, 9), Vector2(64, 9), Vector2(60, 3), Vector2(24, 3)]],
			["line", [Vector2(44, 3), Vector2(36, 22)]],
			["body", [Vector2(-62, 16), Vector2(20, 16), Vector2(66, 22), Vector2(58, 34), Vector2(-62, 34)]],
			["glass", [Vector2(-48, 33), Vector2(30, 34), Vector2(10, 52), Vector2(-26, 54), Vector2(-46, 44)]]],
		"snowcat": [["dark", [Vector2(-62, 0), Vector2(-18, 0), Vector2(-40, 24)]],
			["dark", [Vector2(20, 0), Vector2(64, 0), Vector2(42, 24)]],
			["body", [Vector2(-58, 16), Vector2(66, 16), Vector2(66, 34), Vector2(-58, 34)]],
			["glass", [Vector2(-44, 34), Vector2(46, 34), Vector2(38, 62), Vector2(-42, 62)]],
			["body", [Vector2(-45, 62), Vector2(41, 62), Vector2(41, 66), Vector2(-45, 66)]],
			["accent", [Vector2(-40, 66), Vector2(-32, 66), Vector2(-32, 72), Vector2(-40, 72)], Color("#ff9a2a")]],
		"van": [["dark", [Vector2(-62, 0), Vector2(-18, 0), Vector2(-40, 24)]],
			["dark", [Vector2(20, 0), Vector2(64, 0), Vector2(42, 24)]],
			["body", [Vector2(-60, 16), Vector2(66, 16), Vector2(66, 36), Vector2(44, 62), Vector2(-60, 62)]],
			["glass", [Vector2(-50, 42), Vector2(22, 42), Vector2(22, 54), Vector2(-50, 54)]],
			["glass", [Vector2(46, 40), Vector2(62, 40), Vector2(46, 58)]],
			["accent", [Vector2(-46, 65), Vector2(34, 65), Vector2(34, 68), Vector2(-46, 68)], Color("#e8503a")]],
		"pickup": [["wheel", -38, 18], ["wheel", 40, 18],
			["low", [Vector2(-62, 16), Vector2(66, 16), Vector2(66, 24), Vector2(-62, 24)]],
			["wood", [Vector2(-60, 28), Vector2(-12, 28), Vector2(-12, 52), Vector2(-60, 52)]],
			["body", [Vector2(-62, 24), Vector2(-16, 24), Vector2(-16, 42), Vector2(-62, 42)]],
			["body", [Vector2(-16, 24), Vector2(26, 24), Vector2(26, 36), Vector2(-16, 36)]],
			["body", [Vector2(26, 24), Vector2(68, 24), Vector2(68, 32), Vector2(26, 38)]],
			["glass", [Vector2(-16, 36), Vector2(28, 36), Vector2(16, 58), Vector2(-14, 58)]],
			["body", [Vector2(-15, 58), Vector2(17, 58), Vector2(17, 61), Vector2(-15, 61)]]],
		"jeep": [["wheel", -38, 18], ["wheel", 40, 18],
			["dark", [Vector2(-67, 20), Vector2(-58, 20), Vector2(-58, 48), Vector2(-67, 48)]],
			["low", [Vector2(-58, 15), Vector2(66, 15), Vector2(66, 21), Vector2(-58, 21)]],
			["body", [Vector2(-58, 20), Vector2(66, 20), Vector2(66, 38), Vector2(-58, 38)]],
			["body", [Vector2(-58, 36), Vector2(-18, 36), Vector2(-18, 40), Vector2(-58, 40)]],
			["body", [Vector2(20, 36), Vector2(60, 36), Vector2(60, 40), Vector2(20, 40)]],
			["dark", [Vector2(-17, 38), Vector2(-11, 38), Vector2(-11, 51), Vector2(-17, 51)]],
			["glass", [Vector2(18, 38), Vector2(22, 38), Vector2(22, 54), Vector2(18, 54)]],
			["line", [Vector2(-30, 38), Vector2(-30, 62)]]],
		"hauler": [["wheel", -44, 15], ["wheel", -24, 15], ["wheel", 44, 15],
			["dark", [Vector2(-65, 17), Vector2(65, 17), Vector2(65, 28), Vector2(-65, 28)]],
			["wood", [Vector2(-64, 28), Vector2(20, 28), Vector2(20, 58), Vector2(-64, 58)]],
			["line", [Vector2(-60, 28), Vector2(-60, 56)]], ["line", [Vector2(-12, 28), Vector2(-12, 56)]],
			["body", [Vector2(32, 22), Vector2(68, 22), Vector2(68, 62), Vector2(32, 62)]],
			["glass", [Vector2(56, 44), Vector2(68.5, 44), Vector2(68.5, 58), Vector2(58, 58)]]],
		"buggy": [["wheel", -40, 18], ["wheel", 42, 18],
			["line", [Vector2(-48, 37), Vector2(-48, 107)]],
			["body", [Vector2(-48, 94), Vector2(-30, 94), Vector2(-30, 106), Vector2(-48, 106)]],
			["low", [Vector2(-50, 14), Vector2(46, 14), Vector2(46, 22), Vector2(-50, 22)]],
			["dark", [Vector2(-49, 33), Vector2(-27, 33), Vector2(-27, 45), Vector2(-49, 45)]],
			["dark", [Vector2(-17, 32), Vector2(-11, 32), Vector2(-11, 48), Vector2(-17, 48)]],
			["body", [Vector2(-47, 22), Vector2(23, 22), Vector2(23, 34), Vector2(-47, 34)]],
			["body", [Vector2(23, 14), Vector2(66, 18), Vector2(66, 24), Vector2(23, 34)]],
			["line", [Vector2(-22, 34), Vector2(-22, 62), Vector2(14, 56), Vector2(22, 34)]]],
		"rally": [["wheel", -40, 20], ["wheel", 42, 20],
			["dark", [Vector2(-60, 21), Vector2(64, 21), Vector2(64, 30), Vector2(-60, 30)]],
			["body", [Vector2(16, 28), Vector2(68, 28), Vector2(68, 52), Vector2(56, 72), Vector2(16, 72)]],
			["glass", [Vector2(58, 54), Vector2(67.5, 54), Vector2(57, 70), Vector2(50, 70)]],
			["body", [Vector2(-62, 30), Vector2(14, 30), Vector2(14, 62), Vector2(-62, 62)]],
			["accent", [Vector2(-54, 62), Vector2(6, 62), Vector2(6, 64), Vector2(-54, 64)], Color("#e8503a")],
			["dark", [Vector2(18, 72), Vector2(34, 72), Vector2(34, 80), Vector2(18, 80)]]],
		"bug": [["wheel", -38, 17], ["wheel", 40, 17],
			["body", [Vector2(-58, 16), Vector2(64, 16), Vector2(66, 26), Vector2(40, 38), Vector2(20, 56),
				Vector2(-20, 58), Vector2(-50, 44), Vector2(-60, 28)]],
			["glass", [Vector2(-34, 40), Vector2(28, 40), Vector2(16, 54), Vector2(-18, 55)]],
			["line", [Vector2(-24, 58), Vector2(-24, 63)]], ["line", [Vector2(20, 56), Vector2(20, 63)]],
			["accent", [Vector2(-40, 63), Vector2(40, 63), Vector2(48, 65), Vector2(40, 67), Vector2(-40, 67)], Color("#2ab0c8")]],
		"monster": [["wheel", -42, 26], ["wheel", 46, 26],
			["line", [Vector2(-42, 26), Vector2(-36, 44)]], ["line", [Vector2(46, 26), Vector2(52, 44)]],
			["low", [Vector2(-58, 41), Vector2(66, 41), Vector2(66, 47), Vector2(-58, 47)]],
			["body", [Vector2(-58, 47), Vector2(66, 47), Vector2(66, 59), Vector2(-58, 59)]],
			["body", [Vector2(-58, 59), Vector2(-30, 59), Vector2(-30, 65), Vector2(-58, 65)]],
			["glass", [Vector2(-30, 58), Vector2(26, 58), Vector2(16, 76), Vector2(-28, 76)]],
			["body", [Vector2(-29, 76), Vector2(17, 76), Vector2(17, 80), Vector2(-29, 80)]],
			["dark", [Vector2(9, 80), Vector2(15, 80), Vector2(15, 85), Vector2(9, 85)]]],
		"crawler": [["wheel", -44, 24], ["wheel", 46, 24],
			["low", [Vector2(-50, 27), Vector2(50, 27), Vector2(50, 33), Vector2(-50, 33)]],
			["dark", [Vector2(25, 34), Vector2(47, 34), Vector2(47, 46), Vector2(25, 46)]],
			["body", [Vector2(21, 46), Vector2(55, 46), Vector2(55, 49), Vector2(21, 49)]],
			["dark", [Vector2(-19, 34), Vector2(-13, 34), Vector2(-13, 50), Vector2(-19, 50)]],
			["body", [Vector2(-34, 35), Vector2(22, 35), Vector2(22, 45), Vector2(-34, 45)]],
			["body", [Vector2(-26, 66), Vector2(14, 66), Vector2(14, 68), Vector2(-26, 68)]],
			["paint", [Vector2(-50, 34), Vector2(56, 34)]],
			["paint", [Vector2(-50, 34), Vector2(-30, 54)]],
			["paint", [Vector2(-30, 34), Vector2(-26, 66), Vector2(14, 64), Vector2(40, 36)]]],
		"expedition": [["wheel", -46, 18], ["wheel", -20, 18], ["wheel", 46, 18],
			["dark", [Vector2(-65, 21), Vector2(65, 21), Vector2(65, 27), Vector2(-65, 27)]],
			["body", [Vector2(30, 27), Vector2(66, 27), Vector2(66, 57), Vector2(30, 57)]],
			["glass", [Vector2(52, 44), Vector2(66.5, 44), Vector2(62, 56), Vector2(52, 56)]],
			["body", [Vector2(-62, 27), Vector2(18, 27), Vector2(18, 69), Vector2(-62, 69)]],
			["glass", [Vector2(-52, 51), Vector2(-36, 51), Vector2(-36, 61), Vector2(-52, 61)]],
			["glass", [Vector2(-16, 51), Vector2(0, 51), Vector2(0, 61), Vector2(-16, 61)]],
			["accent", [Vector2(-46, 69), Vector2(-2, 69), Vector2(-2, 77), Vector2(-46, 77)], Color("#3f6b3a")]],
	}

	func _draw_vehicle(id: String, a: float) -> void:
		var parts: Array = SIDES.get(id, SIDES["sled"])
		var top := 0.0
		for p in parts:
			if p[0] == "wheel":
				top = maxf(top, float(p[2]) * 2.0)
			else:
				for v: Vector2 in p[1]:
					top = maxf(top, v.y)
		top = minf(top, 86.0)   # the buggy's whip flag may poke out of the tile
		var k := minf(size.x * 0.9 / 140.0, size.y * 0.9 / top)
		var base := Vector2(size.x * 0.5 - 2.0 * k, size.y * 0.5 + top * k * 0.5)
		var to := func(v: Vector2) -> Vector2: return base + Vector2(v.x, -v.y) * k
		var cols := { "body": body, "paint": body, "low": body.darkened(0.38), "glass": Color("#6d93ab"),
			"dark": Color("#3b424c"), "light": Color("#e9eef2"), "wood": Color("#6b4a2e") }
		draw_line(to.call(Vector2(-70, 0)), to.call(Vector2(72, 0)), Color(0, 0, 0, 0.25 * a), maxf(2.0, k * 3.0))
		for p in parts:
			match String(p[0]):
				"wheel":
					var c: Vector2 = to.call(Vector2(p[1], p[2]))
					draw_circle(c, float(p[2]) * k, Color(Color("#3b424c"), a))
					draw_circle(c, float(p[2]) * k * 0.5, Color(body.lightened(0.2), a))
				"line", "paint":
					var pts := PackedVector2Array()
					for v: Vector2 in p[1]:
						pts.append(to.call(v))
					var lc: Color = body if p[0] == "paint" else Color("#3b424c")
					draw_polyline(pts, Color(lc, a), maxf(1.5, k * 3.5), true)
				_:
					var pts := PackedVector2Array()
					for v: Vector2 in p[1]:
						pts.append(to.call(v))
					var fc: Color = p[2] if p[0] == "accent" else cols[p[0]]
					draw_colored_polygon(pts, Color(fc, a))
