# Engine sounds, one per vehicle (Cosmetics BODIES / WorldView.BODIES). Each is a short
# loop of firings rendered once and re-pitched with the car's speed by Sfx. Every engine
# stays small (a toy-sized car, never a big V8 boom: phone speakers drop everything below
# ~150 Hz anyway); what changes from one to the next is its character:
#   base    firing rate (Hz) the loop is rendered at; LOOP * base firings must be whole
#   idle    firing rate at standstill, rev: added per unit of speed (~1100 at full swing)
#   pat     strength of each firing, cycled (uneven = lumpy idle); lope: timing offsets
#           (fraction of a firing) cycled with it, jitter: random timing
#   res     [lo, hi] ring of each pop (Hz), decay: how fast the pop dies (1/s),
#   noise   puff of noise in each pop, tick: bright diesel clatter at each firing
#   tone    [firing-rate tone, its 2nd harmonic], whine: [ratio to firing rate, level]
#           (turbo, gearbox, supercharger), hp / lp: band (Hz), drive: soft-clip rasp
#   gain    loudness in the game, around 1
extends RefCounted

const RATE := 22050
const LOOP := 2.0   # seconds

const PROFILES := {
	# --- Snowfield
	# snowmobile: a high, raspy two-stroke that revs hard
	"sled": { "base": 120.0, "idle": 85.0, "rev": 0.13, "pat": [1.0, 0.75], "lope": [0.0, 0.0], "jitter": 0.04,
		"res": [900.0, 1200.0], "decay": 700.0, "noise": 1.3, "tick": 0.0, "tone": [0.15, 0.2],
		"whine": [0.0, 0.0], "hp": 260.0, "lp": 4200.0, "drive": 2.6, "gain": 0.8 },
	# snowcat: a slow, labouring diesel with a hydraulic whine from the crawler pods
	"snowcat": { "base": 60.0, "idle": 42.0, "rev": 0.055, "pat": [1.0, 0.85, 0.95, 0.8], "lope": [0.0, 0.0, 0.0, 0.0], "jitter": 0.03,
		"res": [300.0, 380.0], "decay": 300.0, "noise": 0.6, "tick": 0.9, "tone": [0.3, 0.2],
		"whine": [7.5, 0.06], "hp": 140.0, "lp": 3200.0, "drive": 1.8, "gain": 1.0 },
	# arctic van: a smooth, muffled four, the quiet one
	"van": { "base": 80.0, "idle": 55.0, "rev": 0.08, "pat": [1.0, 0.95], "lope": [0.0, 0.0], "jitter": 0.02,
		"res": [330.0, 400.0], "decay": 260.0, "noise": 0.4, "tick": 0.0, "tone": [0.35, 0.25],
		"whine": [0.0, 0.0], "hp": 120.0, "lp": 1500.0, "drive": 1.2, "gain": 0.9 },
	# --- Pinewood
	# pickup: the mid-sized engine the game always had (PR #25)
	"pickup": { "base": 80.0, "idle": 60.0, "rev": 0.09, "pat": [1.0, 0.9], "lope": [0.0, 0.0], "jitter": 0.05,
		"res": [400.0, 550.0], "decay": 380.0, "noise": 0.8, "tick": 0.0, "tone": [0.3, 0.2],
		"whine": [0.0, 0.0], "hp": 110.0, "lp": 2200.0, "drive": 1.6, "gain": 1.0 },
	# open 4x4: a lumpy, uneven old four with a loose exhaust
	"jeep": { "base": 80.0, "idle": 52.0, "rev": 0.085, "pat": [1.0, 0.55, 0.9, 0.45], "lope": [0.0, 0.12, 0.0, -0.08], "jitter": 0.08,
		"res": [380.0, 520.0], "decay": 320.0, "noise": 1.0, "tick": 0.0, "tone": [0.25, 0.15],
		"whine": [0.0, 0.0], "hp": 120.0, "lp": 2400.0, "drive": 2.0, "gain": 1.0 },
	# timber hauler: a working truck diesel, clattering, with a faint turbo
	"hauler": { "base": 60.0, "idle": 44.0, "rev": 0.06, "pat": [1.0, 0.9, 0.95, 0.85, 1.0, 0.9], "lope": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "jitter": 0.03,
		"res": [280.0, 340.0], "decay": 280.0, "noise": 0.6, "tick": 1.1, "tone": [0.3, 0.2],
		"whine": [11.0, 0.05], "hp": 130.0, "lp": 3400.0, "drive": 1.7, "gain": 1.0 },
	# --- Dunes
	# buggy: an air-cooled flat four straight out the back, rattly and eager
	"buggy": { "base": 80.0, "idle": 68.0, "rev": 0.11, "pat": [1.0, 0.7, 0.95, 0.65], "lope": [0.0, 0.06, 0.0, 0.06], "jitter": 0.1,
		"res": [600.0, 820.0], "decay": 480.0, "noise": 1.3, "tick": 0.0, "tone": [0.2, 0.25],
		"whine": [0.0, 0.0], "hp": 200.0, "lp": 3200.0, "drive": 2.2, "gain": 0.9 },
	# rally truck: a sharp turbo four with a whistling turbo
	"rally": { "base": 80.0, "idle": 62.0, "rev": 0.12, "pat": [1.0, 0.85], "lope": [0.0, 0.0], "jitter": 0.03,
		"res": [500.0, 650.0], "decay": 450.0, "noise": 0.9, "tick": 0.0, "tone": [0.25, 0.2],
		"whine": [14.5, 0.09], "hp": 150.0, "lp": 3600.0, "drive": 2.3, "gain": 0.9 },
	# beach bug: a little putt-putt boxer, soft and chuffing
	"bug": { "base": 80.0, "idle": 48.0, "rev": 0.08, "pat": [1.0, 0.4, 0.85, 0.35], "lope": [0.0, 0.18, 0.0, 0.18], "jitter": 0.06,
		"res": [460.0, 560.0], "decay": 220.0, "noise": 0.9, "tick": 0.0, "tone": [0.2, 0.1],
		"whine": [0.0, 0.0], "hp": 160.0, "lp": 1900.0, "drive": 1.5, "gain": 1.0 },
	# --- Highlands
	# monster truck: the deepest of them, a loping eight with a supercharger whine
	"monster": { "base": 60.0, "idle": 40.0, "rev": 0.075, "pat": [1.0, 0.65, 0.9, 0.55, 1.0, 0.7, 0.6, 0.85],
		"lope": [0.0, 0.1, -0.05, 0.12, 0.0, 0.08, 0.1, -0.06], "jitter": 0.04,
		"res": [240.0, 320.0], "decay": 230.0, "noise": 0.9, "tick": 0.0, "tone": [0.35, 0.3],
		"whine": [6.5, 0.07], "hp": 120.0, "lp": 2400.0, "drive": 2.2, "gain": 1.1 },
	# rock crawler: a low, slow-turning engine in a crawler gear that whines
	"crawler": { "base": 60.0, "idle": 38.0, "rev": 0.055, "pat": [1.0, 0.8, 0.9, 0.75], "lope": [0.0, 0.05, 0.0, 0.05], "jitter": 0.05,
		"res": [300.0, 380.0], "decay": 260.0, "noise": 0.7, "tick": 0.0, "tone": [0.3, 0.25],
		"whine": [12.0, 0.12], "hp": 130.0, "lp": 2800.0, "drive": 1.8, "gain": 1.0 },
	# expedition 6x6: a smooth six-cylinder diesel, steady with a light clatter
	"expedition": { "base": 60.0, "idle": 45.0, "rev": 0.065, "pat": [1.0, 0.95, 0.9, 1.0, 0.95, 0.9], "lope": [0.0, 0.0, 0.0, 0.0, 0.0, 0.0], "jitter": 0.02,
		"res": [320.0, 400.0], "decay": 300.0, "noise": 0.5, "tick": 0.6, "tone": [0.3, 0.2],
		"whine": [9.0, 0.04], "hp": 130.0, "lp": 2600.0, "drive": 1.4, "gain": 1.0 },
}

static func profile(id: String) -> Dictionary:
	return PROFILES.get(id, PROFILES["pickup"])

# the firing rate a car at this speed runs at
static func freq(p: Dictionary, speed: float) -> float:
	return float(p["idle"]) + speed * float(p["rev"])

# One loop of the engine: each firing is a short pop (a fast-damped ring plus a puff of
# noise, and for diesels a bright click) with small random changes in strength and pitch,
# over a light tone at the firing rate and its 2nd harmonic, plus any whine. Band-limited
# and soft-clipped. Seeded, so it is the same every run. Samples in -1..1.
static func render(p: Dictionary) -> PackedFloat32Array:
	var base: float = p["base"]
	var n := int(LOOP * RATE)
	var fires := int(round(LOOP * base))
	var pat: Array = p["pat"]
	var lope: Array = p["lope"]
	var res: Array = p["res"]
	var tone: Array = p["tone"]
	var whine: Array = p["whine"]
	var decay: float = p["decay"]
	var noise: float = p["noise"]
	var tick: float = p["tick"]
	var jit: float = p["jitter"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ring := int(minf(0.04, 3.8 / decay) * RATE)   # each pop has died away (~2%)
	for k in fires:
		var start := int((k + float(lope[k % lope.size()]) + rng.randf_range(-jit, jit)) * RATE / base)
		var amp: float = rng.randf_range(0.8, 1.0) * float(pat[k % pat.size()])
		var fr := rng.randf_range(res[0], res[1])
		var nz := 0.0
		var cl := 0.0
		var cl_prev := 0.0
		for j in ring:
			var t := float(j) / RATE
			nz += (rng.randf_range(-1.0, 1.0) - nz) * 0.35
			var v := (sin(TAU * fr * t) + nz * noise) * exp(-t * decay) * amp
			if tick > 0.0 and j < 120:
				var w := rng.randf_range(-1.0, 1.0)
				cl = w - cl_prev   # crude high-pass: a bright click
				cl_prev = w
				v += cl * tick * exp(-t * 2500.0) * amp
			var i := posmod(start + j, n)
			buf[i] += v
	var wf: float = float(whine[0]) * base
	for i in n:
		var t := float(i) / RATE
		buf[i] += float(tone[0]) * sin(TAU * base * t) + float(tone[1]) * sin(TAU * base * 2.0 * t)
		if float(whine[1]) > 0.0:
			buf[i] += float(whine[1]) * 4.0 * sin(TAU * wf * t)
	# high-pass then two low-passes; a second pass over the loop so the filter state
	# wraps cleanly
	var hp_a := exp(-TAU * float(p["hp"]) / RATE)
	var lp_a := 1.0 - exp(-TAU * float(p["lp"]) / RATE)
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
	var drive: float = p["drive"]
	for i in n:
		out[i] = tanh(out[i] / peak * drive)
	# same loudness for every engine (RMS), without clipping
	peak = 0.0
	var sq := 0.0
	for i in n:
		peak = maxf(peak, absf(out[i]))
		sq += out[i] * out[i]
	var rms := sqrt(sq / n)
	var s := minf(0.3 / rms, 0.95 / peak)
	for i in n:
		out[i] *= s
	return out

static func to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = samples.size()
	return w
