# Race simulation: cars, tether physics, AI, laps. Ported from the JS prototype
# (v32) with the same tuning so the game feels the same. Pure logic, no nodes:
# the view and the sound read `events` after each update.
extends RefCounted

const TrackData = preload("res://scripts/track.gd")
const Defs = preload("res://scripts/track_defs.gd")
const Rivals = preload("res://scripts/rivals.gd")

# ---------- tuning (same numbers as the prototype) ----------
const HW := TrackData.HW
const CR := TrackData.CR
const MAX := 860.0          # cruise speed
const ACC := 650.0          # throttle
const GRIP := 2.7           # sideways grip once fully recovered (low = icy)
const ICE_TIME := 1.1       # seconds of extra-slippery slide after letting go
const SWING_BOOST := 170.0  # speed gained per second while tethered
const SWING_CAP := 1.28     # max speed multiplier while swinging
const RANGE := 600.0        # hook reach (prototype 520; a little more forgiving)
const RELEASE_KICK := 1.05  # slingshot on release
const JUMP_MIN := 360.0     # slower than this at the ramp and you drop into the gap
const OBS_PEN := 1.0        # seconds per post hit (Obstacles)
const TOKEN_PEN := 0.25     # seconds per gem missed over the whole run (Collect)
# Touching the road edge is punished: a hit keeps WALL_KEEP of the speed (scaled down
# further for head-on hits) and every moment spent rubbing along the rail bleeds speed:
# the throttle cuts out and the car drags.
const WALL_KEEP := 0.82
const WALL_HEADON := 0.18   # extra loss for a square hit (vn ~ speed)
const SCRAPE_DRAG := 0.8    # 1/s speed decay while rubbing the edge (no throttle then)
const PEEL := 0.12          # rad: after a wall contact the car points this far back into the road
const GAP := TrackData.GAP
const SUBSTEPS := 4
# AI rivals: light catch-up (campaign races) and racecraft
const CATCH_RANGE := 1600.0  # track distance to the player at which catch-up is at full strength
const CATCH_AHEAD := 0.05    # a rival that far ahead eases off by up to 5%
const CATCH_BEHIND := 0.03   # ...and one that far behind pushes up to 3% harder
const LANE_LIM := HW - CR - 50.0  # rivals never pick a line closer than this to the edge

class Car:
	var name: String
	var color: Color
	var human := -1
	var skill := 1.0
	var aim := 1.0       # AI: scales the hook timing error
	var blunder := 0.0   # AI: chance per bend of hooking far too late
	var block := 0.0     # AI: how hard it covers a player right behind it
	var pace := 1.0      # catch-up multiplier on the speed cap (1 = none)
	var lane_t := 0.0    # AI: seconds left straightening up after a sidestep
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var h := 0.0
	var hook := -1
	var rope := 0.0
	var swung := 0.0
	var ice := 0.0
	var lap := 0
	var trace: Array = []
	var last_s := 0.0
	var finished := false
	var finish_time := 0.0
	var lap_start := 0.0
	var best_lap := -1.0
	var jitter := 0.0
	var cooldown := 0.0
	var wall_t := 0.0
	var wall_dir := 0.0
	var scrape := 0.0   # > 0 while touching the road edge
	var slip := 0.0
	var used_anchor := -1
	var air := 0.0
	var air_max := 0.0
	var fall := 0.0
	var fall_s := 0.0
	var got := {}
	var gems := 0
	var pen := 0.0
	var seg := 0
	var seg_t := 0.0
	var prog := 0.0
	var turn_sign := 0.0
	var hits := 0
	var clean := true   # no rail or post touched since the last hook (feedback only)
	var streak := 0     # bends in a row taken clean
	var lap_hits := 0
	var last_hits := 0
	var chk_t := 0.0
	var chk_pos = null
	var laps: Array = []
	var missed := 0
	var last_got := 0
	var got_at_lap := 0
	var s := 0.0  # current distance along the track (for 3D height)

	func speed() -> float:
		return vel.length()

var track: TrackData
var cars: Array = []
var mode := "trial"
var humans := 1
var laps_total := 3
var clock := 0.0
# armed: this press may still hook. Holding keeps trying until a tower is in reach;
# a tether lost to a wall or a jump needs a fresh press.
var inputs := [{ "held": false, "press_t": -9.0, "armed": false }, { "held": false, "press_t": -9.0, "armed": false }]
var events: Array = []
var catchup := false  # campaign races: rivals ease off ahead of the player, push behind
var focus := -1       # the car rivals measure catch-up and blocking against (first player)

func _init(tr: TrackData, mode_name: String, n_humans: int) -> void:
	track = tr
	mode = mode_name
	humans = 1 if mode == "trial" else n_humans
	laps_total = int(track.def.get("laps", 3))
	var field: Array = []
	if mode == "trial":
		field = [Defs.ROSTER[0]]
	else:
		field = Defs.ROSTER.slice(0, humans) + Defs.ROSTER.slice(2)
		field = field.slice(0, 4)
	# the players (first in the field) start on the front row, inside of the first bend: the shorter line
	var p0 := track.point_at(track.start_s)
	var inner := 1.0
	var bi := -1
	var ba := track.n + 1
	for idx in track.anchors.size():
		var ah := posmod(track.anchors[idx].entry - int(p0["i"]), track.n)
		if ah < ba:
			ba = ah; bi = idx
	if bi >= 0 and (track.anchors[bi].pos - p0["pos"]).dot(TrackData.perp(p0["dir"])) < 0.0:
		inner = -1.0
	for k in field.size():
		var r: Dictionary = field[k]
		var row := k / 2
		var col := -inner if k % 2 else inner
		var back: float = TrackData.GRID_ROWS[row] if row < TrackData.GRID_ROWS.size() else 90.0 + row * 150.0
		var p := track.point_at(track.start_s - back)
		var nrm := TrackData.perp(p["dir"])
		var c := Car.new()
		c.name = r["name"]; c.color = r["color"]; c.skill = r["skill"]
		c.human = k if k < humans else -1
		c.pos = p["pos"] + nrm * col * 70.0
		c.h = p["dir"].angle()
		c.last_s = track.start_s - back
		var nr := track.nearest_raw(c.pos)
		c.seg = nr["i"]; c.seg_t = nr["t"]; c.prog = progress_of(c.last_s)
		c.s = track.s_of(c.seg, c.seg_t)
		cars.append(c)
	focus = 0 if humans > 0 else -1
	set_rivals(Rivals.ATTRACT_TIER if humans == 0 else Rivals.VERSUS_TIER)

# rivals' difficulty tier (Rivals.TIERS) and whether they rubber-band to the player
func set_rivals(tier: int, catch_up: bool = false) -> void:
	catchup = catch_up and focus >= 0
	for c in cars:
		if c.human < 0:
			Rivals.apply(c, tier)

func progress_of(sv: float) -> float:
	return fposmod(sv - track.start_s, track.L)

func on_bridge(i: int) -> int:
	return track.level_of[i]

func blip(f: float, d: float, w: String = "square", v: float = 0.08, sl: float = 0.0) -> void:
	events.append({ "t": "blip", "f": f, "d": d, "w": w, "v": v, "s": sl })

func press(i: int) -> void:
	var p: Dictionary = inputs[i]
	if not p["held"]:
		p["held"] = true
		p["press_t"] = clock
		p["armed"] = true

func release(i: int) -> void:
	inputs[i]["held"] = false

# ---------- hooking ----------
func find_anchor(c: Car) -> int:
	# the tower of the bend the car is on, or of the next bend when it is on a straight
	# (never a nearer tower of another part of the track)
	if c.air > 0.0 or c.fall > 0.0:
		return -1
	var best := -1
	var ba := track.n + 1
	for idx in track.anchors.size():
		var ah := _ahead(c.seg, track.anchors[idx].exit)
		if ah < ba:
			ba = ah
			best = idx
	if best < 0:
		return -1
	var a: TrackData.Anchor = track.anchors[best]
	var dv := a.pos - c.pos
	var d := dv.length()
	var v := c.vel.normalized() if c.vel.length() > 5.0 else Vector2.from_angle(c.h)
	if d < maxf(RANGE, a.r + 200.0) and dv.dot(v) > -0.5 * d:
		return best
	return -1

func attach(c: Car, idx: int) -> void:
	var a: TrackData.Anchor = track.anchors[idx]
	c.hook = idx
	c.rope = c.pos.distance_to(a.pos)
	c.swung = 0.0
	if c.human >= 0:
		blip(1200, 0.05, "square", 0.06)
		events.append({ "t": "hook", "h": c.human })
		# a new bend reached without touching anything since the last hook
		if idx != c.used_anchor and c.used_anchor >= 0:
			c.streak = c.streak + 1 if c.clean else 0
			if c.streak > 0:
				events.append({ "t": "clean", "h": c.human, "n": c.streak })
		c.clean = true
	c.used_anchor = idx

func detach(c: Car, kick: bool) -> void:
	if c.hook < 0:
		return
	c.hook = -1
	c.cooldown = 0.2
	if not kick and c.human >= 0:
		inputs[c.human]["armed"] = false
	if kick:
		c.vel *= RELEASE_KICK
		c.ice = ICE_TIME
		c.h += c.turn_sign * 0.12  # nose stays turned in, so the car slides out on ice
		if c.human >= 0:
			events.append({ "t": "release", "h": c.human })
		if c.human >= 0:
			blip(260, 0.2, "triangle", 0.07, 420)

static func _turn_toward(c: Car, target: float, max_step: float) -> void:
	var d := wrapf(target - c.h, -PI, PI)
	c.h += clampf(d, -max_step, max_step)

# ---------- physics ----------
func step_car(c: Car, dt: float) -> void:
	if c.fall > 0.0:  # dropped into a jump gap: wait, then restart before the ramp
		c.fall -= dt
		if c.fall <= 0.0:
			var p := track.point_at(c.fall_s)
			c.pos = p["pos"]; c.h = p["dir"].angle(); c.vel = p["dir"] * 150.0
			c.seg = p["i"]; c.seg_t = 0.0; c.last_s = c.fall_s; c.prog = progress_of(c.fall_s)
			c.wall_t = 0.0; c.ice = 0.0; c.s = c.fall_s
		return
	if c.air > 0.0: c.air -= dt
	if c.cooldown > 0.0: c.cooldown -= dt
	if c.wall_t > 0.0: c.wall_t -= dt
	if c.scrape > 0.0: c.scrape -= dt
	if c.ice > 0.0: c.ice -= dt
	var cap := MAX * c.skill * c.pace
	var sp := c.vel.length()
	if c.hook >= 0:
		var a: TrackData.Anchor = track.anchors[c.hook]
		if sp > 1.0 and sp < cap * SWING_CAP:
			c.vel *= 1.0 + SWING_BOOST * dt / sp
		c.pos += c.vel * dt
		var rv := c.pos - a.pos
		var d := rv.length()
		# ratchet: if the car drifts closer to the pivot the tether takes up the slack;
		# it never pays out again. No speed is added.
		if d < c.rope:
			c.rope = maxf(a.clear + CR, d)
		if d > c.rope:
			var nv := rv / d
			c.pos = a.pos + nv * c.rope
			var vr := c.vel.dot(nv)
			if vr > 0.0:
				c.vel -= vr * nv
		sp = c.vel.length()
		var r := maxf(30.0, c.pos.distance_to(a.pos))
		var rel := c.pos - a.pos
		var sgn := signf(rel.x * c.vel.y - rel.y * c.vel.x)
		if sgn == 0.0: sgn = 1.0
		a.omega = sgn * sp / r  # this curve's rotor turns with the car
		c.swung += sp / r * dt
		# clean arc: heading stays tangent to the circle, no sliding while hooked
		c.h = c.vel.angle()
		c.turn_sign = sgn
		c.slip = 0.0
	else:
		var hd := Vector2.from_angle(c.h)
		var f := c.vel.dot(hd)
		var l := -c.vel.x * hd.y + c.vel.y * hd.x
		var grip := 6.0 if c.wall_t > 0.0 else GRIP * ((0.2 + 0.8 * (1.0 - c.ice / ICE_TIME)) if c.ice > 0.0 else 1.0)
		l *= exp(-grip * dt)
		if c.scrape > 0.0:
			pass  # rubbing the rail: no drive
		elif f < cap:
			f = minf(cap, f + ACC * dt)
		else:
			f -= (f - cap) * 0.9 * dt
		c.vel = Vector2(hd.x * f - hd.y * l, hd.y * f + hd.x * l)
		c.slip = minf(1.0, absf(l) / 120.0)
		c.pos += c.vel * dt
		# turning round when facing the wrong way; no lane keeping, the car holds its own line
		var ahead_dir: Vector2 = track.seg_dir[(c.seg + 2) % track.n]
		var tgt := ahead_dir.angle()
		var diff := absf(wrapf(tgt - c.h, -PI, PI))
		if c.wall_t > 0.0:
			_turn_toward(c, c.wall_dir, 5.0 * dt)
		elif diff > 1.7:
			_turn_toward(c, tgt, 4.0 * dt)
	if c.slip > 0.3 and randf() < 0.7:
		events.append({ "t": "skid", "pos": c.pos, "h": c.h, "a": 0.28 * c.slip, "s": c.s })

	# walls
	var nr := track.nearest(c.pos, c.seg)
	var lim := HW - CR
	if nr["d"] > lim - 1.0:
		var nv: Vector2 = (c.pos - nr["p"]) / maxf(0.001, nr["d"])
		if nr["d"] > lim:
			c.pos = nr["p"] + nv * lim
		var vn := c.vel.dot(nv)
		var fresh := c.scrape <= 0.0  # first touch, not still rubbing from the last step
		# rubbing along the rail: steady speed loss and sparks
		c.vel *= exp(-SCRAPE_DRAG * dt)
		c.scrape = 0.1
		c.clean = false
		var spd := c.vel.length()
		if spd > 250.0 and randf() < 0.25:
			events.append({ "t": "wall", "pos": c.pos + nv * CR, "n": nv, "count": 1, "s": c.s })
		if vn > 0.0:
			c.vel -= 1.35 * vn * nv
			# a real knock costs more the squarer it is; a graze only the old 10%
			if vn > 40.0:
				c.vel *= WALL_KEEP - WALL_HEADON * clampf(vn / maxf(1.0, spd), 0.0, 1.0)
			elif fresh:
				c.vel *= 0.9
			# (sliding on along a curved rail touches it again every substep: that is the
			# rub above, not a new graze, or the 10% would grind the car to a crawl)
			c.wall_t = 0.3
			# slide along the wall in the racing direction
			var fd: Vector2 = track.seg_dir[(int(nr["i"]) + 1) % track.n]
			var tv := Vector2(-nv.y, nv.x)
			if tv.dot(fd) < 0.0:
				tv = -tv
			# ...nosing slightly back into the road so the car peels off the rail and the
			# throttle comes back, instead of gliding along it forever with the engine cut
			c.wall_dir = tv.angle() + PEEL * signf(tv.cross(-nv))
			if c.vel.length() < 80.0:
				c.vel = tv * 80.0
			if c.hook >= 0 and vn > 40.0:
				detach(c, false)
			if vn > 110.0:
				events.append({ "t": "wall", "pos": c.pos + nv * CR, "n": nv, "count": mini(16, int(vn / 18.0)), "s": c.s })
				if c.human >= 0:
					events.append({ "t": "shake", "v": minf(10.0, vn / 40.0) })
					events.append({ "t": "knock", "h": c.human, "v": clampf(vn / 400.0, 0.0, 1.0) })
					blip(70, 0.15, "sine", 0.15)
	# obstacles: static posts. Hit one and it shatters and is gone for the rest of the race;
	# you lose a little speed and pay OBS_PEN seconds (you fly over them in a jump).
	if not c.air > 0.0:
		for k in track.obstacles.size():
			var o: Dictionary = track.obstacles[k]
			if o["gone"]:
				continue
			if c.pos.distance_to(o["pos"]) >= CR + o["r"]:
				continue
			o["gone"] = true
			c.vel *= 0.8
			c.hits += 1
			c.lap_hits += 1
			c.clean = false
			events.append({ "t": "post", "k": k, "pos": o["pos"], "vel": c.vel, "s": o["s"] })
			if c.human >= 0:
				events.append({ "t": "shake", "v": 6.0 })
				events.append({ "t": "smash", "h": c.human })
				blip(90, 0.15, "sine", 0.15)
				blip(330, 0.2, "square", 0.05, -120)
	c.seg = nr["i"]
	c.seg_t = nr["t"]

	# laps
	var s := track.s_of(c.seg, c.seg_t)
	c.s = s

	# wedged somewhere for over a second: put the car back on the road just ahead
	c.chk_t += dt
	if c.chk_t > 1.2:
		if c.chk_pos != null and c.pos.distance_to(c.chk_pos) < 60.0 and not c.finished and c.hook < 0:
			var q := track.point_at(s + 120.0)
			c.pos = q["pos"]; c.h = q["dir"].angle(); c.vel = q["dir"] * 200.0; c.wall_t = 0.0
		c.chk_t = 0.0
		c.chk_pos = c.pos

	# jumps: hit the ramp fast enough and you fly the gap; too slow, or in the gap
	# without having jumped, and you drop in and restart before the ramp
	var lvl := on_bridge(nr["i"])
	for j in track.jumps:
		if j["lvl"] != lvl:
			continue
		var into := fposmod(s - j["s"], track.L)
		if into > GAP:
			continue
		if c.air > 0.0:
			break
		var sp2 := c.vel.length()
		var was := fposmod(c.last_s - j["s"], track.L)
		if sp2 >= JUMP_MIN and (was > track.L - 200.0 or was < 1.0) and into < 60.0:
			c.air = (GAP + 90.0) / sp2
			c.air_max = c.air
			detach(c, false)
			if c.human >= 0:
				blip(330, 0.25, "triangle", 0.06, 300)
		else:
			c.fall = 0.9
			c.clean = false
			c.fall_s = j["s"] - 260.0
			c.vel = Vector2.ZERO
			detach(c, false)
			if c.human >= 0:
				blip(220, 0.5, "sine", 0.1, -180)
				events.append({ "t": "shake", "v": 6.0 })
			return
	# gems (Collect variant)
	for k in track.tokens.size():
		var g: Dictionary = track.tokens[k]
		if g["lvl"] == lvl and not c.got.has(k) and c.pos.distance_to(g["pos"]) < CR + 42.0:
			c.got[k] = true
			c.gems += 1
			if c.human >= 0:
				blip(1500, 0.07, "sine", 0.06, 500)
				events.append({ "t": "gem", "k": k })

	var prog := progress_of(s)
	var last := progress_of(c.last_s)
	if last > track.L * 0.75 and prog < track.L * 0.25:
		if c.lap >= 1:
			c.last_got = c.got.size() - c.got_at_lap
			c.got_at_lap = c.got.size()
			var lt := clock - c.lap_start + c.lap_hits * OBS_PEN
			c.last_hits = c.lap_hits
			c.lap_hits = 0
			if c.best_lap < 0.0 or lt < c.best_lap:
				c.best_lap = lt
			c.laps.append(lt)
			events.append({ "t": "lap", "car": c, "lt": lt, "trace": c.trace.duplicate() })
		c.lap_start = clock
		c.lap += 1
		c.trace = []  # Collect: gems are not refilled, a gem picked up stays gone for the race
		if c.lap > laps_total and not c.finished:
			# Collect: gems count over the whole run; every gem missed adds to the final time
			c.finished = true
			c.missed = track.tokens.size() - c.gems
			c.pen = c.missed * TOKEN_PEN + c.hits * OBS_PEN
			c.finish_time = clock + c.pen
			events.append({ "t": "finish", "car": c })
			if c.human >= 0:
				blip(660, 0.4, "square", 0.07, 400)
		elif c.human >= 0 and c.lap > 1:
			blip(990, 0.08, "square", 0.05)
	elif last < track.L * 0.25 and prog > track.L * 0.75:
		c.lap -= 1
	c.last_s = s
	c.prog = prog

# ---------- AI ----------
func _ahead(from: int, to: int) -> int:
	return posmod(to - from, track.n)

func ai_think(c: Car, dt: float = 1.0 / 60.0) -> void:
	if c.air > 0.0 or c.fall > 0.0:
		return
	if c.hook >= 0:
		var a: TrackData.Anchor = track.anchors[c.hook]
		var sp := c.vel.length()
		if sp <= 0.0: sp = 1.0
		var hx := c.vel.dot(a.exit_dir) / sp
		var past_mid := _ahead(a.mid, c.seg) < track.n / 2
		if c.swung > a.total + 0.8 or sp < 150.0:
			detach(c, true)
			return
		# no dodging: Obstacles posts stand off the racing line (tools/gen_obstacles.gd)
		if past_mid and hx > 0.975:
			detach(c, true)
		return
	if c.human < 0:
		_ai_line(c, dt)
	if c.cooldown > 0.0 or c.vel.length() < 150.0:
		return
	# next anchor whose bend we are entering
	for idx in track.anchors.size():
		var a: TrackData.Anchor = track.anchors[idx]
		if idx == c.used_anchor:
			continue
		var to_mid := _ahead(c.seg, a.mid)
		if to_mid > track.n / 2:
			continue
		if _ahead(a.entry, c.seg) > _ahead(a.entry, a.mid) and _ahead(c.seg, a.entry) > 4:
			continue  # only near the start of the turn
		var d := a.pos.distance_to(c.pos)
		if d > a.clear + HW * 2.1:
			continue  # close enough for a tidy arc
		if d > maxf(RANGE, a.r + 170.0):
			continue
		var sp := c.vel.length()
		if sp <= 0.0: sp = 1.0
		var along := (a.pos - c.pos).dot(c.vel) / sp
		if along <= c.jitter:
			attach(c, idx)
			c.jitter = (randf() - 0.5) * 900.0 * (1.02 - c.skill) * c.aim
			if c.blunder > 0.0 and randf() < c.blunder:
				c.jitter = -200.0 - randf() * 120.0  # next bend: hooks well past the tower
			return

# signed distance of p from the centre line of segment i (+ = left of the racing direction)
func _lateral(p: Vector2, i: int) -> float:
	return (p - track.P[i]).dot(TrackData.perp(track.seg_dir[i]))

# signed track distance from car a to car b (+ = b is ahead), within half a lap
func _gap(a: Car, b: Car) -> float:
	return wrapf(b.s - a.s, -track.L * 0.5, track.L * 0.5)

# Racecraft on the links between bends: a faster rival pulls out to pass the car in front,
# and a rival with the player right on its tail drifts across to cover their line. Both are
# gentle (a few degrees of steering) and stop well before the next bend so the hook is clean.
func _ai_line(c: Car, dt: float) -> void:
	if c.wall_t > 0.0 or c.finished:
		c.lane_t = 0.0
		return
	# only on a link, with room before the next bend
	var room := INF
	for a in track.anchors:
		if _ahead(a.entry, c.seg) <= _ahead(a.entry, a.exit):
			return  # in a bend
		room = minf(room, fposmod(track.seg_s0[a.entry] - c.s, track.L))
	if room < 320.0:
		c.lane_t = 0.0
		return
	var lat := _lateral(c.pos, c.seg)
	var sp := c.vel.length()
	var lvl := on_bridge(c.seg)
	var target := INF
	var strength := 0.0
	for o in cars:
		if o == c or o.air > 0.0 or o.fall > 0.0 or on_bridge(o.seg) != lvl:
			continue
		var ds := _gap(c, o)
		var olat := _lateral(o.pos, o.seg)
		if ds > CR and ds < 320.0 and sp > o.vel.length() + 30.0 and absf(olat - lat) < CR * 2.4:
			# passing: take the side of the car ahead with more road
			var side := -1.0 if olat > 0.0 else 1.0
			target = clampf(olat + side * CR * 2.6, -LANE_LIM, LANE_LIM)
			strength = 1.0
			break
		if c.block > 0.0 and o.human >= 0 and ds < -CR and ds > -380.0 and o.vel.length() > sp - 40.0:
			target = clampf(olat, -LANE_LIM, LANE_LIM)
			strength = c.block
	if target == INF:
		if c.lane_t <= 0.0:
			return
		c.lane_t -= dt
		target = lat  # straighten up on the line it moved to
		strength = 1.0
	else:
		c.lane_t = 0.5
	var dir: Vector2 = track.seg_dir[(c.seg + 2) % track.n]
	var lim := 0.05 + 0.07 * minf(1.0, strength)
	var want := dir.angle() + clampf((target - lat) * 0.003, -lim, lim)
	_turn_toward(c, want, (0.4 + 0.6 * minf(1.0, strength)) * dt)

# campaign races: rivals well ahead of the player ease off a touch, rivals well behind push
# a touch harder, so the pack stays in reach without anyone being handed the race
func _catch_up(dt: float) -> void:
	var f: Car = cars[focus] if catchup and focus >= 0 and focus < cars.size() else null
	for c in cars:
		if c.human >= 0 or c == f:
			continue
		var want := 1.0
		if f != null and not f.finished and not c.finished:
			var g := clampf(((c.lap - f.lap) * track.L + c.prog - f.prog) / CATCH_RANGE, -1.0, 1.0)
			want = 1.0 - CATCH_AHEAD * g if g > 0.0 else 1.0 - CATCH_BEHIND * g
		c.pace += (want - c.pace) * minf(1.0, dt * 0.8)

func collide_cars() -> void:
	for i in cars.size():
		for j in range(i + 1, cars.size()):
			var a: Car = cars[i]
			var b: Car = cars[j]
			if on_bridge(a.seg) != on_bridge(b.seg) or a.air > 0.0 or b.air > 0.0 or a.fall > 0.0 or b.fall > 0.0:
				continue
			var dv := b.pos - a.pos
			var d := dv.length()
			if d > 0.0 and d < CR * 2.0:
				var nv := dv / d
				var push := (CR * 2.0 - d) / 2.0
				a.pos -= nv * push
				b.pos += nv * push
				var an := a.vel.dot(nv)
				var bn := b.vel.dot(nv)
				if an - bn > 0.0:
					var imp := (an - bn) * 0.6
					a.vel -= imp * nv
					b.vel += imp * nv
					if (a.human >= 0 or b.human >= 0) and imp > 60.0:
						blip(140, 0.08, "square", 0.05)

func standings() -> Array:
	var arr := cars.duplicate()
	arr.sort_custom(func(a: Car, b: Car) -> bool:
		if a.finished and b.finished:
			return a.finish_time < b.finish_time
		if a.finished != b.finished:
			return a.finished
		return (a.lap * track.L + a.prog) > (b.lap * track.L + b.prog))
	return arr

# the rotors keep turning in every phase (menu included)
static func spin_anchors(tr: TrackData, dt: float) -> void:
	for a in tr.anchors:
		a.spin += a.omega * dt
		a.omega += (a.sign * 1.4 - a.omega) * minf(1.0, dt * 1.5)

# one frame of racing
func update(dt: float) -> void:
	clock += dt
	for c in cars:
		if c.human >= 0 and not c.finished:
			var inp: Dictionary = inputs[c.human]
			if inp["held"] and inp["armed"] and c.hook < 0 and c.cooldown <= 0.0:
				var p := find_anchor(c)
				if p >= 0:
					attach(c, p)
			if not inp["held"] and c.hook >= 0:
				detach(c, true)
		else:
			ai_think(c, dt)
	_catch_up(dt)
	var hstep := dt / SUBSTEPS
	for k in SUBSTEPS:
		for c in cars:
			step_car(c, hstep)
		collide_cars()
	if mode == "trial":  # record this lap for a future ghost (30 samples a second)
		for c in cars:
			if c.lap >= 1 and c.trace.size() <= (clock - c.lap_start) * 30.0:
				c.trace.append(Vector3(roundf(c.pos.x), roundf(c.pos.y), snappedf(c.h, 0.01)))
