# The awards a run just earned, shown one after the other over the results: the screen dims,
# the award's medallion plays its little scene with the name and the coins waiting under it,
# then it shrinks and flies into the trophy button in the corner (its coins are collected on
# the Awards screen). A tap skips to the flight. `step` fires at each beat so the game can play
# a sound and buzz: 0 the medallion appears, 1 its scene is done, 2 it lands in the cup.
extends Control

const Medal = preload("res://scripts/award_medal.gd")

signal step(k: int)
signal finished

var _ui
var _queue: Array = []
var _cup: Control
var _dim: ColorRect
var _medal: Medal
var _words: VBoxContainer
var _name: Label
var _coins: Label
var _tw: Tween
var _flying := false

# ui: the game UI (fonts, insets); awards: the award entries (id, name, coins); cup: where they fly to
func setup(ui, awards: Array, cup: Control) -> void:
	_ui = ui
	_queue = awards.duplicate()
	_cup = cup
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.03, 0.05, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_medal = Medal.new()
	add_child(_medal)
	_words = VBoxContainer.new()
	_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_words.add_theme_constant_override("separation", 2)
	add_child(_words)
	var kicker: Label = ui._label("NEW AWARD", 14, Color("#5fe0d0"), ui.f_bold)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_words.add_child(kicker)
	_name = ui._label("", 30, Color("#f3efe6"), ui.f_display)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_name.add_theme_constant_override("shadow_offset_y", 2)
	_words.add_child(_name)
	_coins = ui._label("", 16, Color("#f2b134"), ui.f_bold)
	_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_words.add_child(_coins)
	_words.modulate.a = 0.0
	_medal.landed.connect(func(): step.emit(1))
	_next.call_deferred()

func _medal_side() -> float:
	return clampf(minf(size.x, size.y) * 0.42, 150.0, 260.0)

func _place() -> void:
	var s := _medal_side()
	_medal.size = Vector2(s, s)
	_medal.pivot_offset = _medal.size * 0.5
	_medal.position = Vector2(size.x * 0.5 - s * 0.5, size.y * 0.4 - s * 0.5)
	_words.size = Vector2(size.x, 0)
	_words.position = Vector2(0, _medal.position.y + s + 10)

func _next() -> void:
	if _queue.is_empty():
		_end()
		return
	var a: Dictionary = _queue.pop_front()
	var id: String = a["id"]
	_flying = false
	_place()
	_medal.scale = Vector2.ONE
	_medal.modulate.a = 1.0
	_medal.id = id
	_medal.play()
	_name.text = String(a["name"]).to_upper()
	_name.add_theme_font_size_override("font_size", 30 if size.x > 420 else 24)
	_coins.text = "+%d coins to collect" % int(a["coins"])
	step.emit(0)
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_dim, "color:a", 0.62, 0.25)
	_tw.parallel().tween_property(_words, "modulate:a", 1.0, 0.3).set_delay(0.3)
	_tw.tween_interval(Medal.duration(id) + 0.3)
	_tw.tween_callback(_fly)

# shrink into the cup in the corner, then the next award (or the end)
func _fly() -> void:
	if _flying:
		return
	_flying = true
	if _tw:
		_tw.kill()
	_medal.rest()
	var s := _medal.size.x
	var goal := _cup.get_global_rect().get_center() - get_global_rect().position if _cup and _cup.visible else Vector2(size.x - 40, 40)
	var k := clampf(40.0 / s, 0.08, 0.4)
	var start := _medal.position
	var end := goal - _medal.size * 0.5
	_tw = create_tween()
	_tw.tween_property(_words, "modulate:a", 0.0, 0.15)
	var last := _queue.is_empty()
	if last:
		_tw.parallel().tween_property(_dim, "color:a", 0.0, 0.45)
	# a little arc on the way: the medallion lifts while it travels
	var travel := func(u: float) -> void:
		var e := u * u * (3.0 - 2.0 * u)
		_medal.position = start.lerp(end, e) - Vector2(0, sin(e * PI) * 40.0)
		_medal.scale = Vector2.ONE * lerpf(1.0, k, e)
	_tw.parallel().tween_method(travel, 0.0, 1.0, 0.45)
	_tw.tween_callback(func():
		_medal.modulate.a = 0.0
		step.emit(2)
		_bump_cup())
	_tw.tween_interval(0.15)
	_tw.tween_callback(_next)

func _bump_cup() -> void:
	if not _cup:
		return
	_cup.pivot_offset = _cup.size * 0.5
	var tw := _cup.create_tween()
	tw.tween_property(_cup, "scale", Vector2.ONE * 1.3, 0.08)
	tw.tween_property(_cup, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _end() -> void:
	finished.emit()
	queue_free()

func _gui_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed
	if tap:
		accept_event()
		_fly()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _medal and not _flying:
		_place()
