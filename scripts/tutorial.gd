# First-launch tutorial, played on a real track (Defs.TUTORIAL) with the real physics.
# Pure logic like race.gd: main.gd feeds it every frame, applies the time scale it returns
# (0 = frozen until the player acts) and mirrors `card` / `hint` / `hud` onto the UI.
#
# Lap 1 is guided: the first bend freezes at the moment to hold and again at the moment to
# let go, the second runs in slow motion at those moments, the rest only flash the word.
# Lap 2 is on your own against a target time (two tries, then it moves on anyway).
# Lap 3 adds a few posts by the walls and a line of gems, the extras of the Obstacles and
# Collect variants. Then a summary panel; main.gd marks the tutorial done.
extends RefCounted

const TrackData = preload("res://scripts/track.gd")
const Race = preload("res://scripts/race.gd")

# AI reference lap on Defs.TUTORIAL (tests/tutorial_test.gd prints it); the target is generous
const REF_LAP := 10.0
const TARGET_K := 1.3
const TRIES := 2

var race: Race
var track: TrackData
var car
var target := snappedf(REF_LAP * TARGET_K, 0.5)

var stage := "intro"        # intro, guided, target, extras, done
var wait := ""              # what a freeze waits for: tap, hold, release ("" = running)
var card := {}              # { title, body, footer } or empty; main shows it
var hint := ""              # big word over the track (HOLD / LET GO)
var dirty := true           # card or hint changed since main last looked
var complete := false
var summary: Array = []     # rows for the end panel

var hooks := 0              # bends taken with a hook and a release
var tries := 0
var best := -1.0
var _card_t := 0.0          # > 0: the card hides itself after this many seconds
var _was_hooked := false
var _bend := -1             # bend the car is heading for or turning round
var _bend_hooked := false
var _told_edge := false
var _told_flip := false
var _hint_t := 0.0

func _init(r: Race) -> void:
	race = r
	track = r.track
	car = r.cars[0]
	# alone on the grid: start in the middle of the road, not in a grid slot to one side
	var p0 := track.point_at(car.last_s)
	car.pos = p0["pos"]
	# extras stay hidden until lap 3: posts are "gone", gems already "picked up"
	for o in track.obstacles:
		o["gone"] = true
	for k in track.tokens.size():
		car.got[k] = true
	_show("WELCOME TO TETHER RACING",
		"Your car drives itself. You only need one finger: hold to hook a tower, let go to fly out of the bend. Let's try it on a real track.",
		"TAP TO START", 0.0)
	wait = "tap"

# Which parts of Defs.TUTORIAL do what (indices of its straights / bends): the start sits
# early on a straight so the first bend (the big sweeping one) comes with time to read the
# card; posts go on the long top straight, gems round the bend before it.
const START_STRAIGHT := 1
const START_AT := 0.25
const POST_STRAIGHT := 0
const GEM_BEND := 4

# Moves the start line and places the extras on a fresh TrackData, before the view builds
# it. The extras stay hidden until the last lap.
static func dress(tr: TrackData) -> void:
	var s0: Dictionary = tr.straights[START_STRAIGHT]
	tr.start_s = tr.wrap_s(s0["s0"] + s0["len"] * START_AT)
	var st: Dictionary = tr.straights[POST_STRAIGHT]
	var side := 1.0
	for f in [0.3, 0.55, 0.8]:
		var sv := tr.wrap_s(st["s0"] + st["len"] * f)
		var q := tr.point_at(sv)
		tr.obstacles.append({ "pos": q["pos"] + TrackData.perp(q["dir"]) * side * (TrackData.HW - 38.0), "r": 32.0, "s": sv, "gone": false })
		side = -side
	# gems along the middle of the bend and of the straight after it
	var ar: Dictionary = tr.arcs[GEM_BEND]
	var st2: Dictionary = tr.straights[GEM_BEND]
	var spots: Array = []
	var d := 60.0
	while d < ar["len"] - 30.0:
		spots.append(ar["s0"] + d)
		d += 115.0
	d = 80.0
	while d < st2["len"] - 115.0:
		spots.append(st2["s0"] + d)
		d += 115.0
	for sp in spots:
		var sv := tr.wrap_s(sp)
		var q := tr.point_at(sv)
		tr.tokens.append({ "pos": q["pos"], "lvl": 0, "s": sv })

func target_text() -> String:
	return "%.1f s" % target

func _show(title: String, body: String, footer := "", secs := 0.0) -> void:
	card = { "title": title, "body": body, "footer": footer }
	_card_t = secs
	dirty = true

func _hide() -> void:
	if not card.is_empty():
		card = {}
		dirty = true

func _set_hint(h: String, secs := 0.0) -> void:
	if hint != h:
		hint = h
		dirty = true
	_hint_t = secs

# a tap while the tutorial waits for one (main swallows that touch)
func tap() -> void:
	if wait != "tap":
		return
	wait = ""
	_hide()
	match stage:
		"intro":
			stage = "guided"
			_show("A TOWER IN EVERY BEND", "Each bend wraps round its own tower. Get ready to grab the first one...")
		"extras":
			_set_hint("GO", 0.8)

func wants_tap() -> bool:
	return wait == "tap"

# the time scale for this frame: 0 while frozen, < 1 in slow motion
func update(dt: float) -> float:
	if complete:
		return 0.0
	if _card_t > 0.0:
		_card_t -= dt
		if _card_t <= 0.0:
			_hide()
	if _hint_t > 0.0:
		_hint_t -= dt
		if _hint_t <= 0.0:
			_set_hint("")
	if wait == "tap":
		return 0.0
	var held: bool = race.inputs[0]["held"]
	var c = car
	var hooked: bool = c.hook >= 0
	# the bend ahead (or the one we are in), as find_anchor sees it
	var k := _next_bend(c)
	if hooked and c.hook == k:
		_bend_hooked = true
	if k != _bend:
		if _bend >= 0 and not _bend_hooked and c.lap >= 1 and stage != "intro":
			_show("MISSED THAT TOWER", "Hold as the bend starts: the ring lights up on the tower when it is in reach.", "", 3.5)
		if _bend >= 0 and not _told_flip and track.anchors[k].sign != track.anchors[_bend].sign and hooks >= 2:
			_told_flip = true
			_show("THIS ONE TURNS THE OTHER WAY", "Same move, and no more slow motion: hold as the bend starts, let go as you point down the road.", "", 4.0)
		_bend = k
		_bend_hooked = hooked and c.hook == k
	# just let go: one more bend done
	if _was_hooked and not hooked:
		hooks += 1
		_set_hint("")
		if hooks == 1:
			_show("NICE SLINGSHOT!", "Letting go flings you out with a little extra speed. The car slides on the ice for a moment, then grips again: aim for it.", "", 4.0)
	if hooked and not _was_hooked:
		_set_hint("")
	if hooked and not _was_hooked and hooks == 0:
		_show("KEEP HOLDING", "The rope keeps its length, so you swing round the tower on a clean arc and pick up speed. The rotor spins with you.")
	_was_hooked = hooked
	# rubbing the road edge, the first time
	if c.scrape > 0.0 and not _told_edge and hooks >= 1 and stage != "intro":
		_told_edge = true
		_show("MIND THE EDGE", "Rubbing the edge brakes you hard and cuts the throttle. Hook as the bend starts and let go on time to stay in the middle.", "", 4.0)

	var guide := stage == "guided"
	var level := 0
	if guide:
		level = 3 if hooks == 0 else (2 if hooks == 1 else 1)
	if level == 0:
		return 1.0
	var a: TrackData.Anchor = track.anchors[k]
	if not hooked:
		if wait == "release":
			wait = ""
		if _hook_moment(c, k) and not held:
			match level:
				3:
					wait = "hold"
					_show("HOLD TO HOOK", "Touch the screen anywhere and keep your finger down. Your tether grabs this bend's tower.", "HOLD")
					_set_hint("HOLD")
					return 0.0
				2:
					_set_hint("HOLD", 0.6)
					return 0.3
				_:
					_set_hint("HOLD", 0.6)
		elif wait == "hold" and held:
			wait = ""
			_hide()
		return 1.0
	# hooked
	if wait == "hold":
		wait = ""
		_set_hint("")
	if _release_moment(c, a, 0.99 if level == 3 else 0.95) and held:
		match level:
			3:
				if wait != "release":
					wait = "release"
					_show("LET GO!", "Lift your finger now, while your nose points down the road.", "LET GO")
					_set_hint("LET GO")
				return 0.0
			2:
				_set_hint("LET GO", 0.6)
				return 0.3
			_:
				_set_hint("LET GO", 0.6)
	return 1.0

func _next_bend(c) -> int:
	var best_i := 0
	var ba := track.n + 1
	for idx in track.anchors.size():
		var ah := posmod(track.anchors[idx].exit - c.seg, track.n)
		if ah < ba:
			ba = ah
			best_i = idx
	return best_i

# the tower of this bend is in reach and alongside (the AI hooks at about this point)
func _hook_moment(c, k: int) -> bool:
	if race.find_anchor(c) != k or c.cooldown > 0.0 or c.vel.length() < 350.0:
		return false   # (off the start line the car is still finding its speed)
	var a: TrackData.Anchor = track.anchors[k]
	var on_arc := posmod(c.seg - a.entry, track.n) <= posmod(a.exit - a.entry, track.n)
	var sp := maxf(1.0, c.vel.length())
	var along: float = (a.pos - c.pos).dot(c.vel) / sp
	return on_arc or along <= 40.0

# past the middle of the bend and pointing down the exit. The freeze waits until the nose is
# almost straight (lets go cleanly, off the edge); a flashed hint comes a touch earlier to
# leave time to react.
func _release_moment(c, a: TrackData.Anchor, th: float) -> bool:
	var sp := maxf(1.0, c.vel.length())
	var hx: float = c.vel.dot(a.exit_dir) / sp
	var past_mid := posmod(c.seg - a.mid, track.n) < track.n / 2
	return past_mid and hx > th

# a lap line crossing; lap = the lap just finished, lt its time (posts included)
func on_lap(lap: int, lt: float) -> void:
	match stage:
		"guided":
			stage = "target"
			_set_hint("")
			_show("NOW ON YOUR OWN", "No more hints. Finish this lap in under %s." % target_text(), "", 4.5)
		"target":
			tries += 1
			best = lt if best < 0.0 or lt < best else best
			if lt <= target:
				_start_extras("TARGET BEATEN!  %.2f s" % lt)
			elif tries >= TRIES:
				_start_extras("%.2f s, ALMOST!" % lt)
			else:
				_show("%.2f s, GO AGAIN!" % lt, "Target %s. Hook as the bend starts, let go as soon as you point down the road, and keep off the edges." % target_text(), "", 5.0)
		"extras":
			stage = "done"
			complete = true
			wait = ""
			_hide()
			_set_hint("")
			summary = [
				["Hold", "hook the tower of the bend"],
				["Let go", "fly out, slide a little"],
				["Edges", "rubbing them brakes you"],
				["Posts", "+1 s for each one hit (%d)" % c_hits()],
				["Gems", "+0.25 s for each one missed (%d/%d)" % [car.gems, track.tokens.size()]],
			]

func c_hits() -> int:
	return car.hits

func _start_extras(title: String) -> void:
	stage = "extras"
	for o in track.obstacles:
		o["gone"] = false
	car.got.clear()
	car.gems = 0
	car.hits = 0
	wait = "tap"
	_show(title, "One more lap with extras. Some events put posts by the walls: hit one and it shatters, +1 s. Collect events lay a line of gems to follow: each one missed costs 0.25 s.", "TAP TO GO")

# rows for the HUD: what lap of the tutorial this is
func lap_label() -> String:
	match stage:
		"intro", "guided": return "1/3"
		"target": return "2/3"
		_: return "3/3"
