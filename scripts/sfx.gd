# Synthesised sounds, matching the prototype's WebAudio blips: short oscillator
# notes with an exponential pitch slide and fade, plus a mid-sized engine.
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
const RUMBLE_BASE := 80.0  # firing rate (Hz) the engine loop is rendered at
const RUMBLE_IDLE := 60.0  # firing rate at standstill; revs up with speed
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
	# engine: a looping mid-sized engine, re-pitched with the car's speed
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
	_warm()

# One loop of a mid-sized engine: each firing is a short pop (a fast-damped
# 400-550 Hz ring plus a puff of noise) with small random changes in strength and
# pitch (every other firing a touch weaker), over a light tone at the firing rate
# and its second harmonic. Band-limited (~110 Hz-2.2 kHz) so there is neither a
# bass boom nor a nasal buzz. Seeded, so it's the same every run.
static func _rumble() -> PackedByteArray:
	var n := int(RUMBLE_LOOP * RATE)
	var fires := int(RUMBLE_LOOP * RUMBLE_BASE)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ring := int(0.01 * RATE)  # each pop has died away within 10 ms
	for k in fires:
		var start := int((k + rng.randf_range(-0.05, 0.05)) * RATE / RUMBLE_BASE)
		var amp := rng.randf_range(0.8, 1.0) * (1.0 if k % 2 == 0 else 0.9)
		var res := rng.randf_range(400.0, 550.0)
		var nz := 0.0
		for j in ring:
			var t := float(j) / RATE
			nz += (rng.randf_range(-1.0, 1.0) - nz) * 0.35
			var v := (sin(TAU * res * t) + nz * 0.8) * exp(-t * 380.0) * amp
			var i := posmod(start + j, n)
			buf[i] += v
	for i in n:
		var t := float(i) / RATE
		buf[i] += 0.3 * sin(TAU * RUMBLE_BASE * t) + 0.2 * sin(TAU * RUMBLE_BASE * 2.0 * t)
	# high-pass ~110 Hz then two low-passes ~2.2 kHz; second pass over the loop so
	# the filter state wraps cleanly
	var hp_a := exp(-TAU * 110.0 / RATE)
	var lp_a := 1.0 - exp(-TAU * 2200.0 / RATE)
	var hp := 0.0
	var prev := 0.0
	var l1 := 0.0
	var l2 := 0.0
	var out := PackedFloat32Array()
	out.resize(n)
	for pass_i in 2:
		for i in n:
			hp = hp_a * (hp + buf[i] - prev)
			prev = buf[i]
			l1 += (hp - l1) * lp_a
			l2 += (l1 - l2) * lp_a
			out[i] = l2
	var peak := 0.0
	for i in n:
		peak = maxf(peak, absf(out[i]))
	# gentle soft-clip for a little rasp
	for i in n:
		out[i] = tanh(out[i] / peak * 1.6)
	peak = 0.0
	for i in n:
		peak = maxf(peak, absf(out[i]))
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(out[i] / peak * 0.9 * 32000.0))
	return data

# index of a bus; the "SFX" and "Music" buses come from default_bus_layout.tres.
# They must exist at startup: buses added at runtime are wired into a loop on the
# web build (sample playback), cutting Master off from the speakers. The fallback
# below only runs if the layout file is missing.
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

# Every blip the game plays, made when the game starts. Synthesising one on the fly
# took a long GDScript loop on the frame it first played (the lap / finish line), a
# visible hitch on phones and the web. A blip missing from here is still made on demand.
const WARM := [
	[440.0, 0.15, "square", 0.07, 0.0], [880.0, 0.35, "square", 0.07, 0.0],  # countdown
	[1320.0, 0.25, "square", 0.06, 300.0],                                     # new record
	[1200.0, 0.05, "square", 0.06, 0.0], [260.0, 0.2, "triangle", 0.07, 420.0],
	[70.0, 0.15, "sine", 0.15, 0.0], [90.0, 0.15, "sine", 0.15, 0.0],
	[330.0, 0.2, "square", 0.05, -120.0], [330.0, 0.25, "triangle", 0.06, 300.0],
	[220.0, 0.5, "sine", 0.1, -180.0], [1500.0, 0.07, "sine", 0.06, 500.0],
	[660.0, 0.4, "square", 0.07, 400.0], [990.0, 0.08, "square", 0.05, 0.0],    # finish, lap
	[140.0, 0.08, "square", 0.05, 0.0],
]

func _warm() -> void:
	for a in WARM:
		_stream(a[0], a[1], a[2], a[3], a[4])

func _stream(f: float, d: float, kind: String, v: float, slide: float) -> AudioStreamWAV:
	var key := "%s|%s|%s|%s|%s" % [f, d, kind, v, slide]
	if not _cache.has(key):
		var w := _make(f, d, kind, v, slide)
		# web plays sounds as WebAudio samples: hand the data over now, not on first play
		if OS.has_feature("web"):
			AudioServer.register_stream_as_sample(w)
		_cache[key] = w
	return _cache[key]

# exponential pitch slide and fade, stepped by a constant ratio per sample
func _make(f: float, d: float, kind: String, v: float, slide: float) -> AudioStreamWAV:
	var n := int((d + 0.02) * RATE)
	var dn := d * RATE
	var data := PackedByteArray()
	data.resize(n * 2)
	var f1 := maxf(30.0, f + slide)
	var fr := f
	var g := v
	var fr_step := pow(f1 / f, 1.0 / dn) if slide != 0.0 else 1.0
	var g_step := pow(0.0001 / v, 1.0 / dn)
	var ph := 0.0
	for i in n:
		ph += fr / RATE
		var s := clampf(_wave(kind, ph) * g * 2.2, -1.0, 1.0)
		data.encode_s16(i * 2, int(s * 32000.0))
		if i < dn:
			fr *= fr_step
			g *= g_step
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w

# synthesise notes ahead of time so their first play does not hitch a frame
func prewarm(specs: Array) -> void:
	for sp in specs:
		var key := "%s|%s|%s|%s|%s" % sp
		if not _cache.has(key):
			_cache[key] = _make(sp[0], sp[1], sp[2], sp[3], sp[4])

func blip(f: float, d: float, kind := "square", v := 0.08, slide := 0.0) -> void:
	if not enabled:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _stream(f, d, kind, v, slide)
	p.play()

func set_engine(speed: float, on: bool) -> void:
	_freq_target = RUMBLE_IDLE + speed * 0.09  # ~60 Hz idle, ~140 Hz cruising, ~160 Hz at full swing
	_gain_target = 0.035 if (on and enabled) else 0.0

func _process(dt: float) -> void:
	_freq += (_freq_target - _freq) * minf(1.0, dt / 0.05)
	_gain += (_gain_target - _gain) * minf(1.0, dt / 0.1)
	if _gain < 0.001:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.pitch_scale = clampf(_freq / RUMBLE_BASE, 0.5, 3.0)
	_engine.volume_db = linear_to_db(_gain * 7.0)
