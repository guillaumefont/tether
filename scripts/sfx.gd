# Synthesised sounds, matching the prototype's WebAudio blips: short oscillator
# notes with an exponential pitch slide and fade, plus a low sawtooth engine hum.
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
var _freq := 40.0
var _freq_target := 40.0
var _gain := 0.0
var _gain_target := 0.0
const HUM_BASE := 110.0  # the hum loop is one low-passed sawtooth at this pitch

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
	# engine: a looping low-passed sawtooth, re-pitched with the car's speed
	# (a sample loop rather than a generator, so it also plays on the web build)
	var n := int(RATE / HUM_BASE) * 20
	var data := PackedByteArray()
	data.resize(n * 2)
	var a := 1.0 - exp(-TAU * 520.0 * (HUM_BASE / 60.0) / RATE)
	var lp := 0.0
	for pass_i in 2:  # second pass so the filter state wraps cleanly
		for i in n:
			var ph := fposmod(i * HUM_BASE / RATE, 1.0)
			lp += (2.0 * ph - 1.0 - lp) * a
			if pass_i == 1:
				data.encode_s16(i * 2, int(clampf(lp * 0.9, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	_engine = AudioStreamPlayer.new()
	_engine.bus = "SFX"
	_engine.stream = w
	_engine.volume_db = -80.0
	add_child(_engine)
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
	_freq_target = 40.0 + speed * 0.17
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
	_engine.pitch_scale = clampf(_freq / HUM_BASE, 0.1, 4.0)
	_engine.volume_db = linear_to_db(_gain * 3.0)
