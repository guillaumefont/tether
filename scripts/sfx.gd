# Synthesised sounds, matching the prototype's WebAudio blips: short oscillator
# notes with an exponential pitch slide and fade, plus the engine of the vehicle being
# driven (each vehicle has its own, see engines.gd).
# Also owns the background music. Effects and music play on their own buses
# ("SFX", "Music"), each with its own volume.
extends Node

const Music = preload("res://scripts/music.gd")
const Engines = preload("res://scripts/engines.gd")

const RATE := 22050
var music: Music
var enabled := true   # false when the sound volume is at zero: skip the work
var _cache := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _engine: AudioStreamPlayer
var _engines := {}   # vehicle id -> its rendered loop (AudioStreamWAV)
var _vehicle := ""
var _prof: Dictionary = Engines.profile("pickup")
var _freq := 60.0
var _freq_target := 60.0
var _gain := 0.0
var _gain_target := 0.0
var _rev_t := -1.0   # Garage rev: seconds into it, < 0 when none is playing
const REV_LEN := 1.6

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
	# engine: a loop re-pitched with the car's speed (a sample loop rather than a
	# generator, so it also plays on the web build); set_vehicle picks which one
	_engine = AudioStreamPlayer.new()
	_engine.bus = "SFX"
	_engine.volume_db = -80.0
	add_child(_engine)
	set_vehicle("pickup")
	_warm()

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

# the vehicle whose engine plays: its loop is rendered the first time (~50 ms on a
# desktop, more on a phone), so call this while a loading screen is up
func set_vehicle(id: String) -> void:
	if not Engines.PROFILES.has(id):
		id = "pickup"
	if id == _vehicle:
		return
	if not _engines.has(id):
		var w := Engines.to_wav(Engines.render(Engines.profile(id)))
		if OS.has_feature("web"):
			AudioServer.register_stream_as_sample(w)
		_engines[id] = w
	_vehicle = id
	_prof = Engines.profile(id)
	var was := _engine.playing
	_engine.stream = _engines[id]
	if was:
		_engine.play()

func set_engine(speed: float, on: bool) -> void:
	if _rev_t >= 0.0:
		return   # a Garage rev is playing
	_freq_target = Engines.freq(_prof, speed)
	_gain_target = 0.035 if (on and enabled) else 0.0

# the Garage's taste of a vehicle: a blip of the throttle, up and back to idle
func rev(id: String) -> void:
	if not enabled:
		return
	set_vehicle(id)
	_rev_t = 0.0
	_freq = Engines.freq(_prof, 0.0)
	_gain = 0.0

func _process(dt: float) -> void:
	if _rev_t >= 0.0:
		_rev_t += dt
		var u := _rev_t / REV_LEN
		# throttle: quick rise, short hold, slow fall back to idle, then fade
		var sp := 1000.0 * (smoothstep(0.0, 0.25, u) - smoothstep(0.45, 0.9, u))
		_freq_target = Engines.freq(_prof, sp)
		_gain_target = 0.0 if u > 0.92 else 0.035
		if _rev_t > REV_LEN + 0.4:
			_rev_t = -1.0
	_freq += (_freq_target - _freq) * minf(1.0, dt / 0.05)
	_gain += (_gain_target - _gain) * minf(1.0, dt / 0.1)
	if _gain < 0.001:
		if _engine.playing:
			_engine.stop()
		return
	if not _engine.playing:
		_engine.play()
	_engine.pitch_scale = clampf(_freq / float(_prof["base"]), 0.4, 3.0)
	_engine.volume_db = linear_to_db(_gain * 7.0 * float(_prof["gain"]))
