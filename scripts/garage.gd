# The Garage: pick the car's paint, livery and rope colour. Visual only.
# A 3D stage shows the car turning on a plinth; below or beside it, three tabs and a
# scrolling grid of swatches. Locked items can be tried on (the stage shows them) but
# not kept; the bar under the stage says what unlocks them, or offers the paid pack.
extends BoxContainer

const Cosmetics = preload("res://scripts/cosmetics.gd")
const Store = preload("res://scripts/store.gd")
const Campaign = preload("res://scripts/campaign.gd")
const WorldView = preload("res://scripts/world_view.gd")
const Art = preload("res://scripts/menu_art.gd")

const C_FG := Color("#f3efe6")
const C_MUTED := Color("#9fb3b0")
const C_POST := Color("#f2b134")
const TAB_NAMES := { "paint": "Paint", "livery": "Livery", "rope": "Rope" }

var menu     # the menu (card style, ui helpers)
var ui
var tab := "paint"
var tally := {}
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
	tally = Cosmetics.tally()
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
	vp.msaa_3d = Viewport.MSAA_4X
	stage.add_child(vp)
	view = WorldView.new()
	vp.add_child(view)
	left.add_child(stage)
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
	for t in ["paint", "livery", "rope"]:
		var b: Button = ui.icon_button(t, TAB_NAMES[t], "card", false, 44)
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
	return trying.get(slot, Cosmetics.equipped(slot))

func _restage() -> void:
	if view.camera == null:
		return
	var w3d: World3D = view.get_viewport().world_3d
	if w3d.environment != view.env:
		w3d.environment = view.env
	view.showroom(Cosmetics.look(shown("paint"), shown("livery"), shown("rope")), Campaign.menu_theme())

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
	_restage()
	_update_status()

func _pick(it: Dictionary) -> void:
	if Cosmetics.unlocked(it, tally):
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
		status.add_theme_color_override("font_color", C_FG)
		return
	status.add_theme_color_override("font_color", C_POST)
	var u: Dictionary = it["unlock"]
	if u.has("product"):
		var pr := Store.product(u["product"])
		status.text = "%s: part of the %s" % [it["name"], pr["name"]]
		var l: Label = buy_btn.get_meta("label")
		l.text = pr["price"] if Store.available() else "Soon"
		buy_btn.disabled = not Store.available()
		buy_btn.visible = true
		return
	var pg := Cosmetics.progress(it, tally)
	status.text = "Trying on %s. Unlock: %s (%d / %d)" % [it["name"], Cosmetics.requirement(it), pg[0], pg[1]]

func _buy() -> void:
	var it := Cosmetics.find(tab, shown(tab))
	var u: Dictionary = it["unlock"]
	if not u.has("product"):
		return
	var res := Store.buy(u["product"])
	if res == "ok" or res == "owned":
		Cosmetics.equip(tab, it["id"])
		trying.erase(tab)
		_show_tab()
		status.text = "%s unlocked. Thank you!" % Store.product(u["product"])["name"]
	else:
		status.text = "The store isn't open yet."

# ---------------------------------------------------------------- tiles
func _tile(it: Dictionary) -> Button:
	var open := Cosmetics.unlocked(it, tally)
	var on: bool = it["id"] == shown(tab)
	var b := Button.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 112 if ui.is_portrait() else 118)
	b.clip_contents = true
	menu._card_style(b, not open)
	if on:
		for st in ["normal", "hover", "pressed", "hover_pressed"]:
			var sb: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
			sb.border_color = C_POST
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
		sub = "Equipped" if it["id"] == Cosmetics.equipped(tab) else ""
		sub_col = C_POST
	elif it["unlock"].has("product"):
		sub = Store.product(it["unlock"]["product"])["price"]
		sub_col = C_POST
	else:
		var pg := Cosmetics.progress(it, tally)
		sub = "%s  %d/%d" % [_short_req(it), pg[0], pg[1]]
	var sl: Label = ui._label(sub, 11, sub_col, ui.f_med)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.autowrap_mode = TextServer.AUTOWRAP_OFF
	sl.clip_text = true
	v.add_child(sl)
	b.add_child(v)
	if not open:
		var lk := Art.Icon.new()
		lk.kind = "lock"
		lk.custom_minimum_size = Vector2(22, 22)
		lk.position = Vector2(6, 6)
		lk.size = Vector2(22, 22)
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lk)
	b.pressed.connect(_pick.bind(it))
	return b

static func _short_req(it: Dictionary) -> String:
	var u: Dictionary = it["unlock"]
	if u.has("medals"): return "Medals"
	if u.has("golds"): return "Golds"
	if u.has("pivots"): return "Pivots"
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
