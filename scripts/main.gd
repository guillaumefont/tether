# Game flow: menu -> countdown -> race -> finish -> results. Owns the race
# simulation, feeds it touch/keyboard input, and drives the 3D view, UI and sound.
extends Node

const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Records = preload("res://scripts/records.gd")
const Medals = preload("res://scripts/medals.gd")
const WorldView = preload("res://scripts/world_view.gd")
const UI = preload("res://scripts/ui.gd")
const Sfx = preload("res://scripts/sfx.gd")
const Settings = preload("res://scripts/settings.gd")
const Campaign = preload("res://scripts/campaign.gd")
const Rivals = preload("res://scripts/rivals.gd")
const Themes = preload("res://scripts/themes.gd")
const Tutorial = preload("res://scripts/tutorial.gd")
const Cosmetics = preload("res://scripts/cosmetics.gd")
const Haptics = preload("res://scripts/haptics.gd")
const Wallet = preload("res://scripts/wallet.gd")
const Daily = preload("res://scripts/daily.gd")
const Awards = preload("res://scripts/awards.gd")
const WorldUnlock = preload("res://scripts/world_unlock.gd")
const AwardShow = preload("res://scripts/award_show.gd")

var view: WorldView
var ui: UI
var sfx: Sfx

var track_idx := 0
var variant := "standard"
var mode := "trial"          # single player Time Trial is the default
var humans := 1
var rival_tier := Rivals.VERSUS_TIER  # campaign races: the tier of the event's world
var catch_up := false                 # campaign races only
var track: TrackData
var race: Race = null
var phase := "menu"
var countdown := 0.0
var start_tier := 0  # trial medal held when the run started
var rec_before := 0.0  # trial record when the run started (for the results delta)
var medal_targets: Array = []   # trial medal target times, bronze..pivot
var last_beep := 4
var end_timer := 0.0
var ghost: Array = []
var new_record := false
var touch_owner := {}        # touch index -> player
var paused := false
var themes_before: Array = []   # themes unlocked when the race started
var worlds_before: Array = []   # campaign worlds finished when the race started
var awards_won: Array = []      # awards this run earned: their medallions play over the results
var building := false        # a loading screen is building the next track
var tutorial := false        # the run is the tutorial (Defs.TUTORIAL), driven by `tut`
var tut: Tutorial = null
# behind the menu: AI drivers race a snowy track, changing track every ATTRACT_SECS
var attract: Race = null
var attract_t := 0.0
var attract_i := -1
const ATTRACT_SECS := 45.0

func _ready() -> void:
	view = WorldView.new()
	add_child(view)
	sfx = Sfx.new()
	add_child(sfx)
	ui = UI.new()
	add_child(ui)
	sfx.set_volumes(Settings.get_opt("music_vol"), Settings.get_opt("sfx_vol"))
	view.set_quality(Settings.get_opt("quality"))
	sfx.prewarm(_streak_notes() + _reward_notes() + _all_world_notes() + _all_award_notes())
	ui.option_changed.connect(_option_changed)
	ui.reward_popped.connect(_reward_popped)
	ui.menu.settings_pressed.connect(func(): ui.show_settings(_options(true)))
	ui.pause_pressed.connect(_toggle_pause)
	ui.reset_pressed.connect(_reset_progress)
	ui.pause_action.connect(_pause_action)
	ui.menu.start_event.connect(_start_event)
	ui.menu.vehicle_picked.connect(func(id): sfx.rev(id))
	ui.again_pressed.connect(new_race)
	ui.next_pressed.connect(func():
		var nx: Dictionary = ui.menu.next_event()
		if not nx.is_empty():
			ui.menu.ev = nx
			_start_event(nx))
	ui.menu_pressed.connect(func(): _with_loading("", _to_menu))
	ui.awards_pressed.connect(func(): _with_loading("", _to_awards))
	ui.skip_pressed.connect(_leave_tutorial)
	ui.tutorial_pressed.connect(start_tutorial)
	ui.show_loading("")   # picks up from the boot splash, fades out once the menu scene is up
	_to_menu()
	# automation hooks for headless screenshots: --  --demo=<track>,<variant>,<seconds>[,<mode>,<players>,<theme>]
	var scripted := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo="):
			scripted = true
			_run_demo(a.substr(7))
		elif a.begins_with("--promo="):
			scripted = true
			_run_promo(a.substr(8))
		elif a.begins_with("--cine-demo="):
			scripted = true
			_run_cine_demo(a.get_slice("=", 1))
		elif a.begins_with("--tutorial-demo"):
			scripted = true
			_run_tutorial_demo()
	# the very first launch goes straight onto the track for the tutorial
	if not scripted and not Settings.get_opt("tutorial_done") and not Records.any():
		start_tutorial()
	else:
		_fade_in_later()

func rec_key() -> String:
	return Records.key(cur_def()["name"], variant)

func cur_def() -> Dictionary:
	return Defs.TUTORIAL if tutorial else Defs.TRACKS[track_idx]

func _make_track() -> TrackData:
	var tr := TrackData.new(cur_def(), variant)
	if tutorial:
		Tutorial.dress(tr)
	return tr

# ---------------------------------------------------------------- tutorial
func start_tutorial() -> void:
	tutorial = true
	track_idx = 0
	variant = "standard"
	mode = "trial"
	humans = 1
	view.theme_override = "snow"
	_load_race()

# skip button, or leaving from the pause menu: it won't come back on its own
func _leave_tutorial() -> void:
	Settings.set_opt("tutorial_done", true)
	if paused:
		_set_paused(false)
	_with_loading("", _to_menu)

func _fade_in_later() -> void:
	for k in 3:
		await get_tree().process_frame
	ui.hide_loading()

# show the loading screen for a frame, then do the slow track build behind it
func _with_loading(title: String, work: Callable) -> void:
	building = true
	ui.show_loading(title)
	await get_tree().process_frame
	await get_tree().process_frame
	ui.set_loading_progress(0.6)
	building = false
	work.call()
	ui.hide_loading()

# build the race track a step at a time so the loading bar moves with the real work
func _load_race() -> void:
	building = true
	var th: String = view.theme_override if view.theme_override != "" else String(Defs.TRACKS[track_idx].get("theme", "snow"))
	ui.show_loading("Tutorial" if tutorial else Defs.TRACKS[track_idx]["name"], th)   # the art shows the world you're about to race in
	await get_tree().process_frame
	await get_tree().process_frame
	var tr := _make_track()
	ui.set_loading_progress(0.15)
	await get_tree().process_frame
	var steps: Array = view.build_steps(tr)
	for i in steps.size():
		steps[i].call()
		ui.set_loading_progress(0.15 + 0.8 * (i + 1) / steps.size())
		await get_tree().process_frame
	building = false
	new_race(tr)
	ui.hide_loading()

# the trophy on the results screen: back to the menu, straight onto the Awards screen
func _to_awards() -> void:
	_to_menu()
	ui.menu.show_awards()

func _to_menu() -> void:
	if tutorial:
		Settings.set_opt("tutorial_done", true)
	tutorial = false
	tut = null
	phase = "menu"
	race = null
	sfx.music.play("menu")
	ui.show_menu()
	_start_attract()

# Player 1's car wears the Garage look (paint is also their colour on the HUD and the
# results). A rival whose colour is too close to it swaps to a spare one so cars stay
# easy to tell apart. Looks only: handling is the same whatever the paint.
func _dress(r: Race) -> Dictionary:
	var lk := Cosmetics.player_look()
	var me = r.cars.filter(func(c): return c.human == 0)
	if me.is_empty():
		return {}
	me[0].color = lk["color"]
	var spare := [Color("#f2b134"), Color("#4fc3e8"), Color("#e2574c"), Color("#a98cf0"), Color("#5fd38d"), Color("#eef2f5")]
	var taken: Array = r.cars.map(func(c): return c.color)
	for c in r.cars:
		if c == me[0] or not _close(c.color, lk["color"]):
			continue
		for sc in spare:
			if not taken.any(func(t): return _close(t, sc)):
				c.color = sc
				taken.append(sc)
				break
	return { 0: lk }

static func _close(a: Color, b: Color) -> bool:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length() < 0.22

func _start_attract() -> void:
	attract_i = randi() % Defs.TRACKS.size() if attract_i < 0 else (attract_i + 1) % Defs.TRACKS.size()
	track = TrackData.new(Defs.TRACKS[attract_i], "standard")
	view.theme_override = Campaign.menu_theme()   # the menu wears the latest unlocked world
	view.build(track)
	view.visible = true
	attract = Race.new(track, "race", 0)
	view.setup_cars(attract, false)
	attract_t = 0.0
	view.update_camera(attract, "attract", 0.0, true)

# ---------------------------------------------------------------- pause
func _can_pause() -> bool:
	return race != null and phase in ["count", "race", "done"] and not ui.results.visible

func _toggle_pause() -> void:
	if paused:
		_set_paused(false)
	elif _can_pause():
		_set_paused(true)

func _set_paused(on: bool) -> void:
	paused = on
	if on:
		race.release(0)
		race.release(1)
		touch_owner.clear()
		sfx.set_engine(0.0, false)
		var d: Dictionary = cur_def()
		var what := "Time trial" if mode == "trial" else ("Two for the Road" if humans > 1 else "Race")
		var c0 = race.cars[0]
		if tut:
			ui.show_pause("Tutorial  ·  lap %s" % tut.lap_label().replace("/", " / "), _pause_opts())
		else:
			var sub := "%s  ·  %s  ·  lap %d / %d" % [d["name"], what, clampi(c0.lap, 1, race.laps_total), race.laps_total]
			var rec := Records.get_best(rec_key()) if mode == "trial" else 0.0
			if rec > 0.0:   # the record left the race HUD to keep it small
				sub += "  ·  record %s" % UI.fmt2(rec)
			ui.show_pause(sub, _pause_opts())
	else:
		ui.hide_pause()

func _pause_opts() -> Dictionary:
	return _options(mode == "trial" and not tutorial)

# current option values for the pause / settings screens (no ghost toggle outside time trials)
func _options(with_ghost: bool) -> Dictionary:
	return {
		"music_vol": Settings.get_opt("music_vol"),
		"sfx_vol": Settings.get_opt("sfx_vol"),
		"ghost": Settings.get_opt("ghost") if with_ghost else null,
		"haptics": Settings.get_opt("haptics") if Haptics.available() else null,
		"quality": Settings.get_opt("quality"),
	}

# a slider moved or a toggle flipped, from the pause menu or the settings screen
func _option_changed(key: String, value) -> void:
	Settings.set_opt(key, value)
	match key:
		"music_vol", "sfx_vol":
			sfx.set_volumes(Settings.get_opt("music_vol"), Settings.get_opt("sfx_vol"))
		"quality":
			view.set_quality(value)
		"haptics":
			if value:
				Haptics.hook()   # a tick so you feel it is on

func _pause_action(what: String) -> void:
	match what:
		"resume":
			_set_paused(false)
		"restart":
			_set_paused(false)
			new_race()
		"exit":
			_set_paused(false)
			_with_loading("", _to_menu)   # leaving the tutorial marks it done

# Android back button / Esc: pause or resume a race, step back through the menus
func _go_back() -> void:
	if building:
		return
	if race != null and phase != "menu":
		if ui.pause_settings_open():
			ui.show_pause_settings(false)   # back from the pause Settings page to the pause page
		elif paused or _can_pause():
			_toggle_pause()
		elif ui.results.visible:
			_with_loading("", _to_menu)
		return
	if ui.settings_ov.visible:
		ui.hide_settings()
		return
	if not ui.menu.go_back():
		get_tree().quit()

func _start_event(ev: Dictionary) -> void:
	tutorial = false
	tut = null
	track_idx = ev["track"]
	variant = ev["variant"]
	mode = ev["mode"]
	humans = ev["humans"]
	var camp: bool = ev.get("kind", "") == "campaign"
	rival_tier = Rivals.campaign_tier(Campaign.chapter_of(ev["idx"])) if camp else Rivals.VERSUS_TIER
	catch_up = camp
	view.theme_override = String(ev.get("theme", ""))
	_load_race()

func new_race(built: TrackData = null) -> void:
	paused = false
	ui.hide_pause()
	attract = null
	sfx.music.play(sfx.music.race_track(track_idx))
	if built:
		track = built   # already built by the loading screen
	else:
		track = _make_track()
		view.build(track)
	view.visible = true
	race = Race.new(track, mode, humans)
	race.set_rivals(rival_tier, catch_up)
	themes_before = Themes.ORDER.filter(func(t): return Campaign.theme_unlocked(t))
	worlds_before = range(Campaign.CHAPTERS.size()).filter(func(c): return Campaign.chapter_done(c))
	ghost = Records.get_ghost(rec_key()) if mode == "trial" and not tutorial else []
	view.setup_cars(race, mode == "trial" and not tutorial, _dress(race))
	# your vehicle in this world sets the engine sound
	sfx.set_vehicle(WorldView.body_id(Cosmetics.player_look(), String(view.th["kit"])))
	new_record = false
	rec_before = Records.get_best(rec_key())
	start_tier = Campaign.medal(cur_def()["name"], variant, "trial")
	ui.hide_streak()
	ui.hide_lap_note()
	countdown = 3.2
	last_beep = 4
	end_timer = 0.0
	phase = "count"
	touch_owner.clear()
	ui.set_big("")
	tut = null
	if tutorial:
		# no countdown: the tutorial's first card waits for a tap, then the car rolls
		tut = Tutorial.new(race)
		phase = "race"
		medal_targets = []
		ui.build_hud(race, 0, false, true)
		ui.set_hud("rec", tut.target_text())
		_update_hud()
		_sync_tutorial()
	else:
		medal_targets = Medals.targets(Defs.TRACKS[track_idx]["name"], variant) if mode == "trial" else []
		ui.build_hud(race, track.tokens.size(), medal_targets.any(func(t): return t > 0.0))
		_update_hud()   # zeroes on screen from the countdown on
	ui.minimap.race = race
	ui.minimap.set_track(track)
	view.cine_reset()
	_pick_shot()
	view.update_camera(race, "count", 0.0, true)

# ---------------------------------------------------------------- input
func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_ESCAPE:
		_go_back()
		get_viewport().set_input_as_handled()
		return
	if race == null or paused or building:
		return
	if e is InputEventScreenTouch:
		if e.pressed:
			if phase != "race":
				return
			if ui.pause_btn.is_visible_in_tree() and ui.pause_btn.get_global_rect().grow(8).has_point(e.position):
				return   # the pause button, not a hook
			if ui.skip_btn and is_instance_valid(ui.skip_btn) and ui.skip_btn.is_visible_in_tree() and ui.skip_btn.get_global_rect().grow(8).has_point(e.position):
				return
			if tut and tut.wants_tap():
				tut.tap()   # "tap to continue": not a hook
				_sync_tutorial()
				return
			var w := get_viewport().get_visible_rect().size.x
			var p := 1 if (race.humans > 1 and e.position.x > w / 2.0) else 0
			touch_owner[e.index] = p
			race.press(p)
		elif touch_owner.has(e.index):
			var p: int = touch_owner[e.index]
			touch_owner.erase(e.index)
			if not touch_owner.values().has(p):
				race.release(p)
	elif e is InputEventKey and not e.echo:
		var p := -1
		match e.physical_keycode:
			KEY_SPACE, KEY_Z: p = 0
			KEY_ENTER, KEY_KP_ENTER, KEY_M: p = 1
		if p < 0 or p >= race.humans:
			return
		if e.pressed and phase == "race" and tut and tut.wants_tap():
			tut.tap()
			_sync_tutorial()
		elif e.pressed and phase == "race":
			race.press(p)
		elif not e.pressed:
			race.release(p)
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and race:
		race.release(0)
		race.release(1)
		touch_owner.clear()
		if _can_pause() and not paused and phase == "race":
			_set_paused(true)   # phone call, notification shade, app switch

# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	sfx.music.set_ducked(paused)
	if paused or building:
		return
	var dt := minf(delta, 1.0 / 30.0)
	if track:
		Race.spin_anchors(track, dt)
	match phase:
		"menu":
			if attract:
				attract.update(dt)
				for e in attract.events:
					if e["t"] in ["skid", "wall", "post"]:
						view.handle_event(e)
				attract.events.clear()
				attract_t += dt
				if attract_t > ATTRACT_SECS:
					_start_attract()
		"count":
			countdown -= dt
			var n := ceili(countdown - 0.2)
			if n != last_beep:
				last_beep = n
				sfx.blip(440.0 if n > 0 else 880.0, 0.15 if n > 0 else 0.35, "square", 0.07)
			ui.set_big(str(n) if n > 0 else "GO")
			if countdown <= 0.2:
				phase = "race"
		"race", "done":
			var gdt := dt
			if tut:
				gdt = dt * tut.update(dt)
			race.update(gdt)
			_handle_events()
			if tut:
				_sync_tutorial()
				if tut.complete:
					_show_tutorial_end()
			elif race.clock > 0.7 and phase == "race":
				ui.set_big("")
			var hs: Array = race.cars.filter(func(c): return c.human >= 0)
			if phase == "race" and hs.all(func(c): return c.finished):
				phase = "done"
				end_timer = 0.0
				if mode == "trial" or race.humans > 1:
					ui.set_big("FINISH")
				else:
					ui.set_big(_ordinal(race.standings().find(hs[0]) + 1))
			if phase == "done":
				end_timer += dt
				if end_timer > 1.5:
					ui.set_big("")
				if race.cars.all(func(c): return c.finished) or end_timer > 6.0:
					_show_results()
			if phase != "results":
				_update_hud()
		"results":
			# behind the results the cars drive on (the chase cam follows yours); nothing
			# they do now counts, only the look of it (skids, sparks) is kept
			if race and view.cine_active():
				for c in race.cars:
					if c.human >= 0 and not c.finished:
						race.ai_think(c, dt)
						race.inputs[c.human]["held"] = c.hook >= 0
				race.update(dt)
				for e in race.events:
					if e["t"] in ["skid", "wall", "post"]:
						view.handle_event(e)
				race.events.clear()
	var me = race.cars[0] if race and race.cars.size() else null
	sfx.set_engine(me.vel.length() if me else 0.0, phase == "race")
	if view.track and view.visible:
		if phase == "menu" and attract:
			view.sync(attract, phase, null, {}, dt)
			view.update_camera(attract, "attract", dt)
		else:
			view.sync(race, phase, _ghost_sample(), _aims(), dt)
			_pick_shot(dt)
			view.update_camera(race if phase != "menu" else null, phase, dt)

# The cinematic camera shot for this moment (see WorldView.CINE_SHOTS): low moves on the
# countdown, the finish and the tutorial's pauses; none while the player is racing.
func _pick_shot(dt := 0.0) -> void:
	# the results panel sits in the middle: frame the car beside it
	var side := Vector2.ZERO
	if phase == "results":
		side = Vector2(-0.52, 0.0) if not ui.is_portrait() else Vector2(0.0, 0.5)
	view.cine_side = view.cine_side.lerp(side, 1.0 - exp(-2.5 * dt))
	if race == null or phase == "menu":
		view.cine_reset()
		return
	var hs: Array = race.cars.filter(func(c): return c.human >= 0)
	if hs.is_empty():
		view.cine("")
		return
	var me = hs[0]
	if tut:
		if tut.complete:
			view.cine("win", me)
		elif tut.wait == "tap":
			view.cine("card", me)
		elif tut.wait in ["hold", "release"]:
			view.cine("freeze", me, track.anchors[me.hook if me.hook >= 0 else tut._next_bend(me)].pos)
		else:
			view.cine("")
		return
	match phase:
		"count":
			view.cine("intro", me)
		"done", "results":
			var st := race.standings()
			if race.humans > 1:
				me = st[0] if st[0].human >= 0 else me
			view.cine("win" if _won(st, me) else "finish", me)
		_:
			view.cine("")

# a race won, or a new record / better medal in Time trial: the lower, closer finish shot
func _won(st: Array, me) -> bool:
	if not me.finished:
		return false
	if mode == "trial":
		return new_record or Campaign.medal(cur_def()["name"], variant, "trial") > start_tier
	return st[0] == me

func _aims() -> Dictionary:
	var aims := {}
	if phase != "race" or race == null:
		return aims
	for c in race.cars:
		if c.human >= 0 and c.hook < 0 and not c.finished:
			var p := race.find_anchor(c)
			if p >= 0:
				if not aims.has(p):
					aims[p] = []
				aims[p].append(c.color)
	return aims

func _ghost_sample():
	if ghost.is_empty() or race == null or phase == "menu" or not Settings.get_opt("ghost"):
		return null
	var c0 = race.cars[0]
	var k := int((race.clock - c0.lap_start if c0.lap >= 1 else 0.0) * 30.0)
	return ghost[k] if k < ghost.size() else null

func _handle_events() -> void:
	for e in race.events:
		match e["t"]:
			"blip":
				sfx.blip(e["f"], e["d"], e["w"], e["v"], e["s"])
			"hook":
				Haptics.hook()
			"release":
				view.kick_release(e["h"])
			"knock":
				Haptics.knock(e["v"])
			"smash":
				Haptics.post()
			"clean":
				# a run of bends without touching a rail or post: feedback only, no score
				if e["n"] >= 2 and not tut and race.humans == 1:
					ui.show_streak(e["n"])
					var sp: Array = _streak_notes()[mini(e["n"], 9) - 2]
					sfx.blip(sp[0], sp[1], sp[2], sp[3], sp[4])
			"lap":
				if tut and e["car"].human >= 0:
					tut.on_lap(e["car"].lap - 1, e["lt"])
				elif mode == "trial" and e["car"].human >= 0:
					_trial_lap(e["car"], e["lt"], e["trace"])
			"finish":
				if mode == "trial" and e["car"].human >= 0 and track.tokens.size() > 0:
					_trial_run(e["car"])
			_:
				view.handle_event(e)
	race.events.clear()

# rising little notes for a run of clean bends (2..9+)
static func _streak_notes() -> Array:
	var a: Array = []
	for k in 8:
		a.append([snappedf(660.0 * pow(1.0595, k * 2), 1.0), 0.09, "triangle", 0.05, 0.0])
	return a

# results badges popping in: a bright two-note chime (a step higher for each badge) and a buzz
static func _reward_note(i: int, k: int) -> Array:
	return [snappedf((988.0 if k == 0 else 1319.0) * pow(1.0595, mini(i, 2) * 3), 1.0), 0.12 if k == 0 else 0.22, "triangle", 0.07, 0.0]

static func _reward_notes() -> Array:
	var a: Array = []
	for i in 3:
		for k in 2:
			a.append(_reward_note(i, k))
	return a

func _reward_popped(i: int) -> void:
	var a := _reward_note(i, 0)
	var b := _reward_note(i, 1)
	sfx.blip(a[0], a[1], a[2], a[3], a[4])
	get_tree().create_timer(0.09).timeout.connect(func(): sfx.blip(b[0], b[1], b[2], b[3], b[4]))
	Haptics.reward()

# lap records and ghosts come only from solo Time Trial
func _trial_lap(c, lt: float, trace: Array) -> void:
	var collect := track.tokens.size() > 0
	var prev := Records.get_lap(rec_key()) if collect else Records.get_best(rec_key())
	var has_prev := prev > 0.0
	if not has_prev or lt < prev:
		if collect:
			Records.set_lap(rec_key(), lt)
		else:
			Records.set_best(rec_key(), lt)
			Records.award_medal(rec_key(), "trial", Medals.trial_tier(cur_def()["name"], variant, lt))
			new_record = true
			sfx.blip(1320, 0.25, "square", 0.06, 300)
			Haptics.reward()
		ghost = trace
		Records.set_ghost(rec_key(), ghost)
	var lines := UI.fmt2(lt)
	if has_prev:
		var delta := lt - prev
		lines += "  [font_size=22][color=%s]%s%.2f[/color][/font_size]" % ["#5fd38d" if delta < 0.0 else "#e2574c", "−" if delta < 0.0 else "+", absf(delta)]
	if track.obstacles.size() > 0 and c.last_hits > 0:
		lines += "\n[font_size=16][color=#d4452f]+%d s, %d post%s touched[/color][/font_size]" % [c.last_hits, c.last_hits, "s" if c.last_hits > 1 else ""]
	if collect:
		lines += "\n[font_size=16][color=#7fe3d0]+%d gems this lap, %d/%d in all[/color][/font_size]" % [c.last_got, c.gems, track.tokens.size()]
	ui.show_lap_note(lines)

func _trial_run(c) -> void:
	var prev := Records.get_best(rec_key())
	if prev <= 0.0 or c.finish_time < prev:
		Records.set_best(rec_key(), c.finish_time)
		Records.award_medal(rec_key(), "trial", Medals.trial_tier(cur_def()["name"], variant, c.finish_time))
		new_record = true
		sfx.blip(1320, 0.25, "square", 0.06, 300)
		Haptics.reward()

func _update_hud() -> void:
	if tut:
		var c0 = race.cars[0]
		ui.set_hud("lap0", tut.lap_label())
		ui.set_hud("time", UI.fmt_hud(race.clock - c0.lap_start if c0.lap >= 1 else 0.0))
		return
	var gems := track.tokens.size() > 0
	if gems:
		var tot := str(track.tokens.size())
		ui.set_hud("gems", "%s/%s" % [str(race.cars[0].gems).lpad(tot.length(), "0"), tot])
	if mode == "trial":
		var c = race.cars[0]
		var lap_t: float = race.clock if gems else (race.clock - c.lap_start if c.lap >= 1 and not c.finished else 0.0)
		ui.set_hud("lap0", "%d/%d" % [clampi(c.lap, 1, race.laps_total), race.laps_total])
		ui.set_hud("time", UI.fmt_hud(lap_t))
		_update_gap(c, lap_t, gems)
		return
	var st := race.standings()
	for c in race.cars:
		if c.human >= 0:
			ui.set_hud("lap%d" % c.human, "%d/%d" % [clampi(c.lap, 1, race.laps_total), race.laps_total])
			ui.set_hud("pos%d" % c.human, _ordinal(st.find(c) + 1))
	ui.set_hud("time", UI.fmt_hud(race.clock))
	if race.humans == 1:
		var me = race.cars.filter(func(c): return c.human >= 0)[0]
		var t := Medals.race_tier(st.find(me) + 1, 0.0)
		var col: Color = Medals.COLORS[t - 1] if t > 0 else UI.C_MUTED
		ui.set_hud_tag("target", "Medal", col)
		ui.set_hud("target", Medals.NAMES[t - 1].to_upper() if t > 0 else "NONE")
		ui.set_hud_color("target", col)

# Gap to medal pace beside the clock: the best medal whose pace the player is ahead of
# (green, minus), or the bronze pace they are behind (red, plus). Medal pace is the target
# time spread evenly along the lap (or the whole race when gems are scored over the race),
# so it is an estimate between lines and exact at the finish line.
func _update_gap(c, lap_t: float, gems: bool) -> void:
	if medal_targets.is_empty():
		return
	var pace: float = lap_t + (c.hits if gems else c.lap_hits) * Race.OBS_PEN
	var frac := 1.0
	if c.finished:
		pace = c.finish_time if gems else c.best_lap
	elif c.lap < 1:   # before the line on the first lap
		ui.set_hud_tag("gap", "Target", UI.C_MUTED)
		ui.set_hud("gap", "--.--")
		ui.set_hud_color("gap", UI.C_MUTED)
		return
	elif gems:
		frac = ((c.lap - 1) * track.L + c.prog) / (race.laps_total * track.L)
	else:
		frac = c.prog / track.L
	frac = clampf(frac, 0.0, 1.0)
	var tier := -1
	var lowest := -1
	for i in medal_targets.size():
		if medal_targets[i] <= 0.0:
			continue
		if lowest < 0:
			lowest = i
		if pace - medal_targets[i] * frac <= 0.0:
			tier = i
	if lowest < 0:
		return
	var shown := tier if tier >= 0 else lowest
	var gap: float = pace - medal_targets[shown] * frac
	ui.set_hud_tag("gap", Medals.NAMES[shown], Medals.COLORS[shown])
	ui.set_hud("gap", "%s%.2f" % ["-" if gap <= 0.0 else "+", minf(absf(gap), 99.99)])
	ui.set_hud_color("gap", Color("#7be38b") if gap <= 0.0 else Color("#e2574c"))

static func _ordinal(n: int) -> String:
	return Race.ordinal(n)

func _show_results() -> void:
	phase = "results"
	ui.hide_streak()
	ui.hide_lap_note()
	var name: String = Defs.TRACKS[track_idx]["name"]
	if mode == "trial":
		var c = race.cars[0]
		var rec := Records.get_best(rec_key())
		var rows: Array = []
		if c.best_lap > 0.0:   # only the fastest lap, not every lap (it is the one that counts)
			rows.append({ "cells": ["Fastest lap", "", UI.fmt2(c.best_lap)], "hl": true })
		if track.obstacles.size() > 0:
			rows.append({ "cells": ["Posts hit", "", "%d (+%d s)" % [c.hits, c.hits]] })
		if track.tokens.size() > 0:
			rows.append({ "cells": ["Gems", "", "%d/%d" % [c.gems, track.tokens.size()]] })
			rows.append({ "cells": ["Missed", "", "+%.2f s" % c.pen] })
			rows.append({ "cells": ["Score", "", UI.fmt2(c.finish_time)], "hl": true })
		var note := ""
		if rec > 0.0:
			if track.tokens.size() > 0:
				note = "Record on %s (Collect): %s. Score = total time + 0.25 s per gem missed." % [name, UI.fmt2(rec)]
			else:
				note = "Record on %s: %s. Your best lap becomes the ghost you chase next time." % [name, UI.fmt2(rec)]
		var tier := Campaign.medal(name, variant, "trial")
		var rewards: Array = []
		if new_record:
			var gain := rec_before - rec
			rewards.append({ "text": "−%.2f S FASTER" % gain if rec_before > 0.0 and gain > 0.0 else "FIRST RECORD", "col": UI.C_GAIN })
		if tier > start_tier:
			rewards.append({ "text": "%s MEDAL" % Medals.NAMES[tier - 1].to_upper(), "col": Medals.COLORS[tier - 1] })
		elif tier < Medals.NAMES.size():
			var tg: float = Medals.targets(name, variant)[tier]
			if tg > 0.0:
				note += " Next medal (%s): %s." % [Medals.NAMES[tier], UI.fmt2(tg)]
		if new_record:
			Wallet.bump("records")
		var run_val: float = c.finish_time if track.tokens.size() > 0 else c.best_lap
		var run_tier := Medals.trial_tier(name, variant, run_val) if c.finished else 0
		var coins := Wallet.medal_coins(start_tier, run_tier)
		var daily := 0
		if c.finished and Daily.is_today(track_idx, variant):
			daily = Daily.claim(run_tier)
		note = _pay(coins, daily, { "mode": "trial", "variant": variant, "finished": c.finished, "clean_laps": c.best_clean_laps,
			"streak": c.best_streak, "hits": c.hits, "gems_all": track.tokens.size() > 0 and c.gems == track.tokens.size() }, rewards) + note
		ui.show_results("New record" if new_record else "Time trial", rows, _unlock_note() + note, not ui.menu.next_event().is_empty(), 3, rewards)
		_world_moment()
		_award_moment()
		return
	var res := race.result()
	var st: Array = res["standings"]
	var title: String = res["title"]
	var rows2: Array = []
	for k in st.size():
		var c = st[k]
		rows2.append({ "cells": [str(k + 1), c.name, ("best " + UI.fmt(c.best_lap) + "   " if c.best_lap > 0.0 else "") + (UI.fmt(c.finish_time) if c.finished else "DNF")], "hl": c.human >= 0, "color": c.color })
	var rnote := "Race times don't count for records. Lap records come from Time trial."
	var rrewards: Array = []
	if race.humans == 1:
		var me = res["me"]
		var place: int = res["place"]
		var lead: float = res["lead"]
		var won := Campaign.save_race(name, variant, place, lead, me.finished)
		var tier: int = won["tier"]
		if won["new"]:
			rrewards.append({ "text": "%s MEDAL" % Medals.NAMES[tier - 1].to_upper(), "col": Medals.COLORS[tier - 1] })
		rnote = _pay(Wallet.medal_coins(won["held"], tier), 0, { "mode": "race", "variant": variant, "finished": me.finished, "place": place,
			"lead": lead, "clean_laps": me.best_clean_laps, "streak": me.best_streak, "hits": me.hits }, rrewards) + rnote
	ui.show_results(title, rows2, _unlock_note() + rnote, not ui.menu.next_event().is_empty(), 3, rrewards)
	_world_moment()
	_award_moment()

# mirror the tutorial's card and big word onto the UI when they change
func _sync_tutorial() -> void:
	if tut == null or not tut.dirty:
		return
	tut.dirty = false
	ui.show_coach(tut.card)
	# the word floats above the car rather than on it
	ui.set_big(tut.hint + "\n\n" if tut.hint != "" else "", 64 if tut.hint.length() > 4 else 80)

func _show_tutorial_end() -> void:
	phase = "results"
	Settings.set_opt("tutorial_done", true)
	var rows: Array = []
	for r in tut.summary:
		rows.append({ "cells": r })
	var bt := tut.best
	var note := "You're ready. The Road Trip starts in Snowfield. Replay this tutorial any time from Settings."
	if bt > 0.0:
		note = "Best lap on your own: %s (target %s). " % [UI.fmt2(bt), tut.target_text()] + note
	ui.show_results("TUTORIAL DONE", rows, note, false, 2)

# a campaign world just finished: say which theme it opened
func _unlock_note() -> String:
	var n := _theme_note()
	if ui.menu.gold_to_advance():
		n += "Win Gold to open the next stop. "
	return n

# One-player run over: pay the medal and Track of the day coins and any awards reached,
# add their badges, and return a line for the results note.
func _pay(medal_coins: int, daily: int, run: Dictionary, rewards: Array) -> String:
	Wallet.add(medal_coins)
	var won := Awards.check(run)
	awards_won = won   # each one gets its own medallion moment after the badges (_award_moment)
	var total := medal_coins + daily
	var txt := ""
	if total > 0:
		rewards.push_front({ "text": "+%d COINS" % total, "col": Color("#f2c84a") })
		var parts: Array = []
		if medal_coins > 0: parts.append("medal %d" % medal_coins)
		if daily > 0: parts.append("Daily Detour %d" % daily)
		txt = "+%d coins (%s): %d in all.  " % [total, ", ".join(parts), Wallet.coins()]
	if not won.is_empty():
		txt += "New award%s: collect %d coins in the Passport.  " % ["s" if won.size() > 1 else "", won.reduce(func(n, a): return n + int(a["coins"]), 0)]
	return txt

# Settings > Reset progress (confirmed there): coins, looks bought, awards, medals,
# records, ghosts and the campaign start over. Options and paid packs stay.
func _reset_progress() -> void:
	Records.reset()
	Wallet.reset()
	Cosmetics.unequip_all()
	ui.hide_settings()
	ui.menu.world = -1
	ui.menu.show_home()

# a campaign world finished on this run: the "world unlocked" show over the results
func _world_moment() -> void:
	for c in Campaign.CHAPTERS.size():
		if Campaign.chapter_done(c) and not worlds_before.has(c):
			worlds_before.append(c)
			show_world_unlock(c)
			return

# the awards this run earned: once the results badges have popped in (and after the
# "world unlocked" show, if there is one), each award's medallion plays and flies into the cup
func _award_moment() -> void:
	var won := awards_won
	awards_won = []
	if won.is_empty():
		return
	for w in ui.root.get_children():
		if w is WorldUnlock:
			w.closed.connect(func(): show_awards_won(won))
			return
	var wait := 0.45 + ui.res_rewards.get_child_count() * 0.52
	get_tree().create_timer(wait).timeout.connect(func(): show_awards_won(won))

func show_awards_won(won: Array) -> void:
	if not ui.results.visible:
		return
	ui.res_cup.visible = true
	var sh := AwardShow.new()
	ui.results.add_child(sh)
	sh.setup(ui, won, ui.res_cup)
	sh.step.connect(_award_step)

# the medallion's beats: a rising pair as it appears, a bright chime when its scene is
# done, a tick as it drops into the cup
func _award_step(k: int) -> void:
	for n in _award_notes(k):
		sfx.blip(n[0], n[1], n[2], n[3], n[4])
	if k == 1:
		Haptics.reward()
	elif k == 2:
		Haptics.buzz(20, 0.4)

static func _award_notes(k: int) -> Array:
	match k:
		0: return [[587.0, 0.12, "triangle", 0.05, 200.0]]
		1: return [[784.0, 0.3, "triangle", 0.05, 0.0], [1175.0, 0.4, "triangle", 0.04, 0.0], [1568.0, 0.5, "sine", 0.04, 0.0]]
	return [[1320.0, 0.06, "square", 0.04, 0.0]]

static func _all_award_notes() -> Array:
	return _award_notes(0) + _award_notes(1) + _award_notes(2)

func show_world_unlock(c: int) -> void:
	var done: String = Campaign.CHAPTERS[c]["theme"]
	var last := c + 1 >= Campaign.CHAPTERS.size()
	var nxt: String = done if last else String(Campaign.CHAPTERS[c + 1]["theme"])
	var lines: Array = []
	if not last:
		lines.append("Leg %d, %s, open on the Road Trip" % [c + 2, Themes.get_theme(nxt)["name"]])
	if c > 0:
		lines.append("%s theme in Special Stages" % Themes.get_theme(done)["name"])
		lines.append("Menu and loading screen dressed in %s" % Themes.get_theme(done)["name"])
	for it in Cosmetics.PAINTS:
		if it["unlock"].get("world", -1) == c:
			lines.append("%s paint for sale in the Garage" % it["name"])
	var aw := Awards.find("world_" + done)
	if not aw.is_empty():
		lines.append("Award %s: %d coins to collect" % [aw["name"], aw["coins"]])
	var title := "Road Trip done!" if last else "%s unlocked" % Themes.get_theme(nxt)["name"]
	var sub := "%s leg finished" % Themes.get_theme(done)["name"]
	var w := WorldUnlock.new()
	ui.root.add_child(w)
	w.setup(ui, ui.menu.WORLD_ART[nxt], nxt, title, sub, lines)
	w.step.connect(_world_step)

# the show's beats: a rattle, the click open, a rising chord for the title, a tick per line
func _world_step(k: int) -> void:
	for n in _world_notes(k):
		sfx.blip(n[0], n[1], n[2], n[3], n[4])
	if k == 1 or k == 2:
		Haptics.reward()
	elif k == 0:
		Haptics.buzz(30, 0.4)

static func _world_notes(k: int) -> Array:
	match k:
		0: return [[110.0, 0.08, "square", 0.05, 0.0]]
		1: return [[523.0, 0.06, "square", 0.05, 0.0], [1568.0, 0.18, "triangle", 0.06, 0.0]]
		2: return [[523.0, 0.35, "triangle", 0.06, 0.0], [659.0, 0.35, "triangle", 0.05, 0.0], [784.0, 0.45, "triangle", 0.05, 0.0], [1047.0, 0.6, "triangle", 0.05, 0.0]]
	return [[snappedf(880.0 * pow(1.0595, mini(k - 3, 6) * 2), 1.0), 0.07, "triangle", 0.04, 0.0]]

static func _all_world_notes() -> Array:
	var a: Array = []
	for k in 10:
		a += _world_notes(k)
	return a

func _theme_note() -> String:
	for t in Themes.ORDER:
		if Campaign.theme_unlocked(t) and not themes_before.has(t):
			themes_before.append(t)
			return "Leg finished: %s unlocked in Special Stages and the menu!  " % Themes.get_theme(t)["name"]
	return ""

# ---------------------------------------------------------------- demo / screenshots
# Drives the real game with a scripted player so a headless run can capture frames.
func _run_demo(arg: String) -> void:
	var parts := arg.split(",")
	track_idx = int(parts[0])
	variant = parts[1] if parts.size() > 1 else "standard"
	mode = parts[3] if parts.size() > 3 else "trial"
	humans = int(parts[4]) if parts.size() > 4 else 1
	view.theme_override = parts[5] if parts.size() > 5 else ""
	var secs := float(parts[2]) if parts.size() > 2 else 8.0
	var out := OS.get_environment("SHOT_DIR")
	if out == "":
		out = "user://"
	await get_tree().process_frame
	var shots := [["menu_home", func(): ui.loading.visible = false; ui.menu.show_home()],
		["settings", func(): ui.show_settings(_options(true))],
		["menu_home_again", func(): ui.hide_settings()],
		["menu_campaign", func(): ui.menu.kind = "campaign"; ui.menu.world = -1; ui.menu.focus = 0; ui.menu.show_list()],
		["menu_world", func(): ui.menu.kind = "campaign"; ui.menu.world = 0; ui.menu.focus = 0; ui.menu.show_list()],
		["menu_attack", func(): ui.menu.kind = "attack"; ui.menu.focus = 8; ui.menu.show_list()],
		["menu_garage", func(): ui.menu.show_garage()],
		["menu_garage_vehicle", func(): ui.menu.show_garage(); var g = ui.menu.body.find_children("*", "BoxContainer", true, false).filter(func(n): return n.has_method("_set_tab"))[0]; g._pick(Cosmetics.find("body", "rally"))],
		["menu_garage_livery", func(): ui.menu.show_garage(); var g = ui.menu.body.find_children("*", "BoxContainer", true, false).filter(func(n): return n.has_method("_set_tab"))[0]; g._set_tab("livery"); g._pick(Cosmetics.find("livery", "checker"))],
		["menu_awards", func(): ui.menu.show_awards()],
		["menu_daily", func():
			var p := Daily.current()
			ui.menu.ev = { "track": p["track"], "variant": p["variant"], "mode": "trial", "humans": 1, "kind": "daily", "idx": 0, "theme": Campaign.track_theme(p["track"]) }
			ui.menu.show_event()],
		["settings_reset", func(): ui.show_settings(_options(true)); ui._reset_tap()],
		["results_coins", func():
			ui.hide_settings()
			ui.menu.visible = false
			ui.show_results("Time trial", [{ "cells": ["Fastest lap", "", "0:12.10"], "hl": true }], "+400 coins (medal 100, Daily Detour 100, Clean triple 150, Smooth operator 100): 1240 in all.", false, 3,
				[{ "text": "+450 COINS", "col": Color("#f2c84a") }, { "text": "GOLD MEDAL", "col": Medals.COLORS[2] }])],
		["award_play", func(): show_awards_won([Awards.find("clean_laps"), Awards.find("first_pivot")])],
		["award_done", func(): pass],
		["award_fly", func(): pass],
		["world_lock", func(): show_world_unlock(0)],
		["world_open", func(): pass],
		["world_done", func(): pass],
		["world_close", func(): for w in ui.root.get_children(): if w is WorldUnlock: w.queue_free()],
		["menu_back", func(): ui.results.visible = false; ui.menu.visible = true; ui.menu.show_home()],
		["loading", func(): ui.show_loading(Defs.TRACKS[track_idx]["name"], view.theme_override); ui.set_loading_progress(0.6)],
		["menu_event", func():
			ui.loading.visible = false
			ui.menu.kind = "attack" if mode == "trial" else "campaign"
			ui.menu.ev = { "track": track_idx, "variant": variant, "mode": mode, "humans": humans, "kind": ui.menu.kind, "idx": 1, "theme": view.theme_override if view.theme_override != "" else "snow" }
			ui.menu.show_event()],
		["results_pop", func():
			ui.menu.visible = false
			ui.show_results("New record", [{ "cells": ["Fastest lap", "", "0:42.10"], "hl": true }], "Record on this track: 0:42.10.", true, 3,
				[{ "text": "−0.84 S FASTER", "col": UI.C_GAIN }, { "text": "GOLD MEDAL", "col": Medals.COLORS[2] }])],
		["results", func(): pass]]   # same panel once the badges have popped in
	for sh in shots:
		sh[1].call()
		await get_tree().create_timer({ "results": 1.5, "world_open": 1.1, "world_done": 2.6, "award_play": 0.9, "award_done": 1.4 }.get(sh[0], 0.3)).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join(sh[0] + ".png"))
	new_race()
	var t := 0.0
	var shot := 0
	var fx_shots := { "speed": false, "streak": false }
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		_autopilot()
		# one frame of the release wind round the car and one of the clean-bend streak
		if not fx_shots["speed"] and view.wind_count() > 14 and phase == "race":
			fx_shots["speed"] = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("fx_speed.png"))
		if OS.get_environment("SHOT_STREAK") != "" and t > secs * 0.5 and not fx_shots["streak"] and ui.streak.modulate.a < 0.1:
			ui.show_streak(3)   # force one so its place under the HUD can be checked
		if OS.get_environment("SHOT_LAP") != "" and t > secs * 0.5 and not fx_shots.has("lap"):
			fx_shots["lap"] = true   # a lap note as at the end of a lap, with a clean streak under it
			ui.show_lap_note("0:42.10  [font_size=22][color=#5fd38d]−0.84[/color][/font_size]\n[font_size=16][color=#7fe3d0]+6 gems this lap, 12/20 in all[/color][/font_size]", 3.0)
			ui.show_streak(3)
		if not fx_shots["streak"] and ui.streak.modulate.a > 0.9 and ui.streak.text.ends_with("3"):
			fx_shots["streak"] = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("fx_streak.png"))
		if OS.get_environment("SHOT_PAUSE") != "" and shot == 2 and not paused and phase == "race":
			_set_paused(true)
			await get_tree().create_timer(0.2).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("pause.png"))
			ui.show_pause_settings(true)
			await get_tree().create_timer(0.2).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("pause_settings.png"))
			_set_paused(false)
		if t > (shot + 1) * secs / 4.0:
			shot += 1
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("race_%d.png" % shot))
	get_tree().quit()

# Tutorial screenshots: play the tutorial with a scripted thumb and save a frame every
# time a new card comes up (SHOT_DIR), then the end panel.
func _run_tutorial_demo() -> void:
	var out := OS.get_environment("SHOT_DIR")
	if out == "":
		out = "user://"
	await get_tree().process_frame
	start_tutorial()
	while tut == null:
		await get_tree().process_frame
	var seen := {}
	var n := 0
	var t := 0.0
	while t < 240.0 and phase != "results":
		await get_tree().process_frame
		t += get_process_delta_time()
		if tut == null:
			break
		var title: String = tut.card.get("title", "")
		if title != "" and not seen.has(title):
			seen[title] = true
			await get_tree().create_timer(2.0).timeout   # the camera settles into its shot
			await RenderingServer.frame_post_draw
			n += 1
			get_viewport().get_texture().get_image().save_png(out.path_join("tut_%02d.png" % n))
		match tut.wait:
			"tap":
				tut.tap()
				_sync_tutorial()
			"hold":
				race.press(0)
			"release":
				race.release(0)
			_:
				if tut.hooks >= 1 and phase == "race":
					_autopilot()
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("tut_end.png"))
	get_tree().quit()

# Cinematic camera frames (SHOT_DIR): the countdown intro, then the race on autopilot to
# the finish shot and the results backdrop. --cine-demo=<track>,<variant>,<mode>[,<theme>]
func _run_cine_demo(arg: String) -> void:
	var parts := arg.split(",")
	track_idx = int(parts[0])
	variant = parts[1] if parts.size() > 1 else "standard"
	mode = parts[2] if parts.size() > 2 else "race"
	view.theme_override = parts[3] if parts.size() > 3 else ""
	humans = 1
	var out := OS.get_environment("SHOT_DIR")
	if out == "":
		out = "user://"
	await get_tree().process_frame
	ui.menu.visible = false
	ui.loading.visible = false
	new_race()
	race.laps_total = 1   # a short run: the shots are at the start and the finish
	var marks := [0.05, 0.9, 1.8, 2.5, 3.1]
	var t := 0.0
	var n := 0
	var done_t := -1.0
	var after := [1.5, 3.0, 4.5]
	var res_t := -1.0
	while t < 400.0:
		await get_tree().process_frame
		var d := minf(get_process_delta_time(), 1.0 / 30.0)
		t += d
		_autopilot()
		var save := ""
		if n < marks.size() and t >= marks[n]:
			save = "cine_intro_%d" % n
			n += 1
		if phase in ["done", "results"]:
			if done_t < 0.0:
				done_t = t
			if after.size() and t - done_t >= after[0]:
				save = "cine_finish_%d" % (3 - after.size())
				after.pop_front()
		if phase == "results":
			if res_t < 0.0:
				res_t = t
			elif t - res_t > 1.6 and after.is_empty():
				save = "cine_results"
		if save != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join(save + ".png"))
			if save == "cine_results":
				break
	get_tree().quit()

# the AI drives the human cars, so a recording shows a clean lap with the player's camera
func _autopilot() -> void:
	if phase != "race":
		return
	for c in race.cars:
		if c.human >= 0:
			race.ai_think(c)
			race.inputs[c.human]["held"] = c.hook >= 0
			race.inputs[c.human]["press_t"] = race.clock

# Promo footage: skip the menus, race straight away on autopilot, quit after <seconds>.
# Record with movie mode, e.g. tools/promo/record.sh (see tools/promo/README.md):
#   godot --path . --write-movie out.avi --fixed-fps 30 --resolution 1080x1920 -- --promo=<track>,<variant>,<seconds>[,<mode>]
func _run_promo(arg: String) -> void:
	var parts := arg.split(",")
	track_idx = int(parts[0])
	variant = parts[1] if parts.size() > 1 else "standard"
	var secs := float(parts[2]) if parts.size() > 2 else 20.0
	mode = parts[3] if parts.size() > 3 else "race"
	humans = 1
	# no in-game music: clips get cut together, so the edit lays one continuous track over them
	sfx.set_volumes(0.0, Settings.get_opt("sfx_vol"))
	await get_tree().process_frame
	ui.menu.visible = false
	ui.loading.visible = false
	ui.pause_btn.visible = false
	new_race()
	ui.pause_btn.visible = false
	var t := 0.0
	while t < secs:
		await get_tree().process_frame
		t += get_process_delta_time()
		_autopilot()
	get_tree().quit()
