# Synthesised sounds, matching the prototype's WebAudio blips: short oscillator
# notes with an exponential pitch slide and fade, plus a low engine rumble.
# Also owns the background music. Effects and music play on their own buses
# ("SFX", "Music"), each with its own volume.
extends Node

const Music = preload("res://scripts/music.gd")

const RATE := 22050
var music: Music
var enabled := true   # false when the sound volume is at zero: skip the work
var _cache := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _engine: AudioStreamPlayer
var _freq := RUMBLE_IDLE
var _freq_target := RUMBLE_IDLE
var _gain := 0.0
var _gain_target := 0.0
const RUMBLE_BASE := 40.0  # firing rate (Hz) the rumble loop is rendered at
const RUMBLE_IDLE := 30.0  # firing rate at standstill; rises gently with speed
const RUMBLE_LOOP := 2.0   # seconds; a whole number of firings so it loops seamlessly

func _ready() -> void:
	_bus("SFX")
	_bus("Music")
	music = Music.new()
	add_child(music)
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	# engine: a looping low rumble, re-pitched with the car's speed
	# (a sample loop rather than a generator, so it also plays on the web build)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = _rumble()
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = w.data.size() / 2
	_engine = AudioStreamPlayer.new()
	_engine.bus = "SFX"
	_engine.stream = w
	_engine.volume_db = -80.0
	add_child(_engine)

# One loop of a low, slightly uneven engine rumble: each firing is a soft thump
# (a fast-damped low resonance plus a puff of filtered noise) with small random
# changes in strength and pitch, over a sub-bass sine at the firing rate and a
# half-rate "lope". Low-passed so nothing buzzes. Seeded, so it's the same every run.
static func _rumble() -> PackedByteArray:
	var n := int(RUMBLE_LOOP * RATE)
	var fires := int(RUMBLE_LOOP * RUMBLE_BASE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ring := int(0.03 * RATE)  # each thump has died away well within 30 ms
	for k in fires:
		var start := int((k + rng.randf_range(-0.06, 0.06)) * RATE / RUMBLE_BASE)
		var amp := rng.randf_range(0.7, 1.0) * (1.0 if k % 2 == 0 else 0.8)
		var res := rng.randf_range(105.0, 140.0)
		var lp := 0.0
		for j in ring:
			var t := float(j) / RATE
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.08
			var v := (sin(TAU * res * t) + lp * 1.5) * exp(-t * 140.0) * amp
			var i := posmod(start + j, n)
			buf[i] += v
	var peak := 0.0
	for i in n:
		var t := float(i) / RATE
		buf[i] += 0.2 * sin(TAU * RUMBLE_BASE * t) + 0.12 * sin(TAU * RUMBLE_BASE * 0.5 * t)
	# two one-pole low-passes (~300 Hz); second pass over the loop so the filter wraps cleanly
	var a := 1.0 - exp(-TAU * 300.0 / RATE)
	var l1 := 0.0
	var l2 := 0.0
	var out := PackedFloat32Array()
	out.resize(n)
	for pass_i in 2:
		for i in n:
			l1 += (buf[i] - l1) * a
			l2 += (l1 - l2) * a
			out[i] = l2
	for i in n:
		peak = maxf(peak, absf(out[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(out[i] / peak * 0.9 * 32000.0))
	return data

# create a bus routed to Master if it doesn't exist yet; returns its index
static func _bus(name: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	return i

# slider 0..100 -> bus gain; squared so the middle of the slider sounds like the middle
static func _set_bus_volume(name: String, pct: float) -> void:
	var i := _bus(name)
	var g := pow(clampf(pct / 100.0, 0.0, 1.0), 2.0)
	AudioServer.set_bus_mute(i, g <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(g, 0.0001)))

func set_volumes(music_pct: float, sfx_pct: float) -> void:
	_set_bus_volume("Music", music_pct)
	_set_bus_volume("SFX", sfx_pct)
	music.enabled = music_pct > 0.0
	enabled = sfx_pct > 0.0

static func _wave(kind: String, ph: float) -> float:
	var x := fposmod(ph, 1.0)
	match kind:
		"square":
			return 1.0 if x < 0.5 else -1.0
		"triangle":
			return 4.0 * absf(x - 0.5) - 1.0
		"sawtooth":
			return 2.0 * x - 1.0
		_:
			return sin(TAU * x)

func _make(f: float, d: float, kind: String, v: float, slide: float) -> AudioStreamWAV:
	var n := int((d + 0.02) * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var f1 := maxf(30.0, f + slide)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := minf(1.0, t / d)
		var fr := f * pow(f1 / f, u) if slide != 0.0 else f
		ph += fr / RATE
		var g := v * pow(0.0001 / v, u)
		var s := clampf(_wave(kind, ph) * g * 2.2, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

func blip(f: float, d: float, kind := "square", v := 0.08, slide := 0.0) -> void:
	if not enabled:
		return
	var key := "%s|%s|%s|%s|%s" % [f, d, kind, v, slide]
	if not _cache.has(key):
		_cache[key] = _make(f, d, kind, v, slide)
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _cache[key]
	p.play()

func set_engine(speed: float, on: bool) -> void:
	_freq_target = RUMBLE_IDLE + speed * 0.025  # ~30 Hz idle, ~55 Hz at full swing
	_gain_target = (0.03 + minf(speed, 1100.0) * 0.00001) if (on and enabled) else 0.0

func _process(dt: float) -> void:
	_freq += (_freq_target - _freq) * minf(1.0, dt / 0.05)
	_gain += (_gain_target - _gain) * minf(1.0, dt / 0.1)
	if _gain < 0.001:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.pitch_scale = clampf(_freq / RUMBLE_BASE, 0.5, 2.0)
	_engine.volume_db = linear_to_db(_gain * 3.0)
