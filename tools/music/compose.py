#!/usr/bin/env python3
"""Tether Rally soundtrack, composed and synthesised in code.

Every note, sound and effect here is generated from scratch (oscillators, FM,
noise), so the music is fully original and owned by the project. Nothing is
sampled. Each track is rendered to exactly a whole number of bars, and note
tails, delays and reverb wrap around the end, so the files loop seamlessly.

    python3 tools/music/compose.py            # writes music/*.ogg (needs numpy + ffmpeg)
    python3 tools/music/compose.py --wav DIR  # also keep the raw WAVs

Tracks
  menu.ogg      "Frost Lights"   84 BPM, D dorian: soft pads, FM bells, slow arps
  race_a.ogg    "Tether Line"   138 BPM, A minor: driving bass, arps, lead hook
  race_b.ogg    "Whiteout"      146 BPM, E minor: syncopated bass, stabs, pulse lead
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "music")

NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6,
        "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def midi(name):
    """'A3' -> 57, 'C#5' -> 73."""
    i = 2 if len(name) > 2 and name[1] in "#b" else 1
    return 12 * (int(name[i:]) + 1) + NOTE[name[:i]]


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


# ------------------------------------------------------------------ the mix
class Mix:
    """A stereo buffer exactly `bars` long. Sounds that run past the end wrap
    around to the start, so the rendered file loops without a seam."""

    def __init__(self, bpm, bars, beats_per_bar=4):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bar = self.beat * beats_per_bar
        self.n = int(round(bars * self.bar * SR))
        self.buses = {}

    def bus(self, name):
        if name not in self.buses:
            self.buses[name] = np.zeros((2, self.n))
        return self.buses[name]

    def add(self, bus, t, sig, gain=1.0, pan=0.0):
        """Add a mono signal at time t (seconds) to a bus, panned -1..1."""
        b = self.bus(bus)
        start = int(round(t * SR)) % self.n
        l = np.cos((pan + 1) * np.pi / 4) * gain
        r = np.sin((pan + 1) * np.pi / 4) * gain
        pos = 0
        while pos < len(sig):
            seg = min(len(sig) - pos, self.n - start)
            b[0, start:start + seg] += sig[pos:pos + seg] * l
            b[1, start:start + seg] += sig[pos:pos + seg] * r
            pos += seg
            start = 0

    def t(self, bar, beat=0.0):
        return bar * self.bar + beat * self.beat


# ------------------------------------------------------------------ DSP helpers
def env_adsr(n, a, d, s, r, hold):
    """Attack/decay/sustain for `hold` seconds, then release. Lengths in seconds."""
    t = np.arange(n) / SR
    e = np.empty(n)
    a = max(a, 1e-4)
    e[:] = s
    m = t < a
    e[m] = t[m] / a
    m = (t >= a) & (t < a + d)
    e[m] = 1.0 - (1.0 - s) * (t[m] - a) / max(d, 1e-4)
    m = t >= hold
    lvl = np.interp(hold, [0, a, a + d, a + d + 1e9], [0, 1, s, s])
    e[m] = lvl * np.exp(-(t[m] - hold) / max(r / 4.0, 1e-4))
    return e


def additive(f, n, cutoff, shape="saw", detune_cents=0.0, phase0=0.0, res=0.0):
    """Band-limited saw/square built from harmonics, each weighted by a
    low-pass response; `cutoff` may be an array (filter envelope)."""
    t = np.arange(n) / SR
    fr = f * 2.0 ** (detune_cents / 1200.0)
    out = np.zeros(n)
    cut = np.maximum(np.asarray(cutoff, dtype=float), 20.0)
    # harmonics past ~4x the cutoff are under -24 dB: skip them
    kmax = int(min(60, (SR / 2.2) / fr, 4.0 * float(np.max(cut)) / fr + 1))
    for k in range(1, kmax + 1):
        if shape == "square" and k % 2 == 0:
            continue
        x = (k * fr) / cut
        g = 1.0 / np.sqrt(1.0 + x ** 4)              # 2-pole-ish rolloff
        if res > 0:
            g = g * (1.0 + res * np.exp(-((x - 1.0) ** 2) * 12.0))
        if np.isscalar(g) or g.ndim == 0:
            if g < 1e-3:
                continue
        elif g.max() < 1e-3:
            continue
        out += g * np.sin(2 * np.pi * k * fr * t + phase0 * k) / k
    return out * (0.6 if shape == "saw" else 0.75)


def tri(f, n):
    t = np.arange(n) / SR
    ph = (f * t) % 1.0
    return 4.0 * np.abs(ph - 0.5) - 1.0


def noise(n, seed):
    return np.random.default_rng(seed).standard_normal(n)


def fft_filter(x, lo=None, hi=None):
    """Brick-ish band filter in the frequency domain (smooth edges)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1.0)) ** 4)
    if hi:
        g *= 1.0 / np.sqrt(1.0 + (f / hi) ** 4)
    return np.fft.irfft(X * g, len(x))


def circ_reverb(st, seconds, seed, damp=6000.0, predelay=0.02):
    """Stereo reverb by circular FFT convolution with a decaying noise tail,
    so the tail wraps across the loop point."""
    n = st.shape[1]
    m = int(seconds * SR)
    out = np.zeros_like(st)
    t = np.arange(m) / SR
    for ch in range(2):
        ir = noise(m, seed + ch) * np.exp(-t * 6.9 / seconds)
        ir = fft_filter(ir, lo=180.0, hi=damp)
        ir[: int(predelay * SR)] = 0.0
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
        pad = np.zeros(n)
        pad[: min(m, n)] += ir[: min(m, n)]
        out[ch] = np.fft.irfft(np.fft.rfft(st[(ch + 0) % 2] * 0.5 + st[(ch + 1) % 2] * 0.5) * np.fft.rfft(pad), n)
    return out


def circ_delay(st, seconds, feedback, taps=5, pingpong=True, hi=5000.0):
    out = np.zeros_like(st)
    d = int(seconds * SR)
    src = np.vstack([fft_filter(st[0], lo=200, hi=hi), fft_filter(st[1], lo=200, hi=hi)])
    for k in range(1, taps + 1):
        g = feedback ** k
        if pingpong:
            ch_from = 0 if k % 2 else 1
            out[0] += np.roll(src[ch_from], d * k) * g
            out[1] += np.roll(src[1 - ch_from], d * k) * g
        else:
            out += np.roll(src, d * k, axis=1) * g
    return out


def duck(mix, times, depth, release):
    """Sidechain-style gain dips at kick times (wraps across the loop)."""
    g = np.ones(mix.n)
    rl = int(release * SR * 4)
    shape = 1.0 - depth * np.exp(-np.arange(rl) / (release * SR))
    for t in times:
        s = int(round(t * SR)) % mix.n
        idx = (s + np.arange(rl)) % mix.n
        g[idx] = np.minimum(g[idx], shape)
    return g


# ------------------------------------------------------------------ instruments
def pad(f, dur, bright=1800.0, voices=5, spread=14.0, attack=0.8, release=1.6, seed=0):
    n = int((dur + release * 1.2) * SR)
    rng = np.random.default_rng(seed)
    t = np.arange(n) / SR
    lfo = 1.0 + 0.25 * np.sin(2 * np.pi * 0.17 * t + rng.uniform(0, 6))
    s = np.zeros(n)
    for v in range(voices):
        det = (v - (voices - 1) / 2) / ((voices - 1) / 2 or 1) * spread
        s += additive(f, n, bright * lfo, "saw", det, rng.uniform(0, 6.28))
    s /= voices ** 0.7
    return s * env_adsr(n, attack, 0.5, 0.85, release, dur)


def bell(f, dur, ratio=3.5, index=2.2, decay=1.6):
    n = int((dur + decay * 1.5) * SR)
    t = np.arange(n) / SR
    e = np.exp(-t / decay)
    mod = index * np.exp(-t / (decay * 0.35)) * np.sin(2 * np.pi * f * ratio * t)
    s = np.sin(2 * np.pi * f * t + mod) * e
    s += 0.25 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / (decay * 0.4))
    s[: 64] *= np.linspace(0, 1, 64)
    return s


def pluck(f, dur, cut0=4000.0, cut1=300.0, tau=0.12, shape="saw", detune=8.0, res=0.6):
    n = int((dur + 0.25) * SR)
    t = np.arange(n) / SR
    cut = cut1 + (cut0 - cut1) * np.exp(-t / tau)
    s = additive(f, n, cut, shape, -detune / 2, res=res) + additive(f, n, cut, shape, detune / 2, 1.3, res=res)
    return s * 0.6 * env_adsr(n, 0.003, 0.15, 0.55, 0.12, dur)


def bass(f, dur, cut0=1400.0, cut1=180.0, tau=0.09, res=0.9):
    n = int((dur + 0.12) * SR)
    t = np.arange(n) / SR
    cut = cut1 + (cut0 - cut1) * np.exp(-t / tau)
    s = additive(f, n, cut, "saw", res=res) * 0.8 + np.sin(2 * np.pi * f * t) * 0.55
    return s * env_adsr(n, 0.004, 0.1, 0.8, 0.05, dur)


def lead(f, dur, cutoff=3200.0, vib=0.0, shape="saw"):
    n = int((dur + 0.3) * SR)
    t = np.arange(n) / SR
    # vibrato (about +-10 cents) fades in after 0.25 s
    vamt = vib * np.clip((t - 0.25) / 0.3, 0, 1)
    wobble = 1.0 + vamt * 0.006 * np.sin(2 * np.pi * 5.5 * t)
    s = np.zeros(n)
    for det in (-7.0, 7.0):
        fr = f * 2 ** (det / 1200)
        ph = 2 * np.pi * np.cumsum(fr * wobble) / SR
        kmax = int(min(40, SR / 2.2 / fr))
        for k in range(1, kmax + 1):
            if shape == "square" and k % 2 == 0:
                continue
            g = 1.0 / np.sqrt(1.0 + ((k * fr) / cutoff) ** 4)
            if g < 1e-3:
                break
            s += g * np.sin(k * ph) / k
    s *= 0.32
    return s * env_adsr(n, 0.01, 0.2, 0.75, 0.18, dur)


def kick(seed=0, punch=1.0):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 48 + 110 * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) * np.exp(-t / 0.22)
    click = fft_filter(noise(n, seed), lo=2000) * np.exp(-t / 0.004) * 0.25
    return np.tanh((s + click) * 1.6 * punch) * 0.9


def snare(seed=1):
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * (185 + 60 * np.exp(-t / 0.02)) * t) * np.exp(-t / 0.06) * 0.6
    nz = fft_filter(noise(n, seed), lo=900, hi=9000) * np.exp(-t / 0.11) * 0.5
    return body + nz


def clap(seed=2):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    nz = fft_filter(noise(n, seed), lo=1000, hi=6000)
    e = np.zeros(n)
    for o in (0.0, 0.011, 0.022):
        m = t >= o
        e[m] += np.exp(-(t[m] - o) / (0.012 if o < 0.02 else 0.13))
    return nz * e * 0.45


def hat(open_=False, seed=3):
    n = int((0.35 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    nz = fft_filter(noise(n, seed), lo=7000, hi=15000)
    return nz * np.exp(-t / (0.12 if open_ else 0.018)) * 0.35


def shaker(seed=4):
    n = int(0.09 * SR)
    t = np.arange(n) / SR
    nz = fft_filter(noise(n, seed), lo=4500, hi=11000)
    e = (1 - np.exp(-t / 0.01)) * np.exp(-t / 0.03)
    return nz * e * 0.3


def riser(dur, seed=5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    nz = noise(n, seed)
    # sweep a band upward by mixing progressively brighter filtered copies
    lo = fft_filter(nz, lo=300, hi=1500)
    hi = fft_filter(nz, lo=2500, hi=12000)
    u = t / dur
    return (lo * (1 - u) + hi * u) * u ** 2 * 0.35


def sub_drop(seed=6):
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    f = 30 + 70 * np.exp(-t / 0.3)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.45) * 0.7


# ------------------------------------------------------------------ cache (instruments are deterministic)
_cache = {}


def cached(fn, *args, **kw):
    key = (fn.__name__, args, tuple(sorted(kw.items())))
    if key not in _cache:
        _cache[key] = fn(*args, **kw)
    return _cache[key]


def chord_notes(spec):
    return [midi(x) for x in spec.split()]


# ------------------------------------------------------------------ track: menu
def compose_menu():
    """"Frost Lights": calm, open, wintry. D dorian, 84 BPM, 24 bars."""
    m = Mix(84, 24)
    prog = [  # 2 bars each; (pad voicing, bass root)
        ("D3 A3 C4 E4 F4", "D2"),   # Dm9
        ("Bb2 F3 A3 C4 D4", "Bb1"),  # Bbmaj9(no3)/add6
        ("F3 C4 E4 G4 A4", "F2"),   # Fmaj9
        ("C3 G3 D4 E4 G4", "C2"),   # Cadd9
        ("G2 D3 A3 Bb3 F4", "G1"),  # Gm9(no3)
        ("A2 E3 G3 C4 E4", "A1"),   # Am7
    ]
    for rep in range(2):
        for i, (ch, root) in enumerate(prog):
            bar = rep * 12 + i * 2
            for j, nn in enumerate(chord_notes(ch)):
                s = cached(pad, hz(nn), m.bar * 2 - 0.1, 1500.0 if rep == 0 else 2300.0, 5, 12.0, 1.4, 2.2, 7 + j)
                m.add("pad", m.t(bar), s, 0.11, pan=(j - 2) * 0.28)
            b = cached(pad, hz(midi(root)), m.bar * 2 - 0.2, 380.0, 3, 6.0, 0.4, 1.0, 50)
            m.add("bass", m.t(bar), b, 0.34)
            # sub sine
            n = int(m.bar * 2 * SR)
            tt = np.arange(n) / SR
            sub = np.sin(2 * np.pi * hz(midi(root)) * tt) * env_adsr(n, 0.3, 0.2, 1, 0.8, m.bar * 2 - 0.6)
            m.add("bass", m.t(bar), sub, 0.18)

    # bell arpeggio: 8th notes cycling chord tones up an octave, gentle randomness
    rng = np.random.default_rng(11)
    for rep in range(2):
        for i, (ch, _) in enumerate(prog):
            tones = sorted(set(n + 12 for n in chord_notes(ch)[1:]))
            pattern = [0, 2, 1, 3, 2, 4, 3, 1]
            for k in range(16):  # 2 bars of 8ths
                if rep == 0 and i < 2 and k % 2:
                    continue  # sparser opening
                if rng.random() < 0.18:
                    continue
                nn = tones[pattern[k % 8] % len(tones)]
                vel = 0.10 if k % 4 == 0 else 0.065
                s = cached(bell, hz(nn), 0.3, 3.5, 1.8, 1.4)
                m.add("bells", m.t(rep * 12 + i * 2, k * 0.5), s, vel, pan=np.sin(k * 0.9) * 0.6)

    # melody on second pass: slow, singing, original line (scale degrees of D dorian)
    mel = [  # (bar, beat, note, beats)
        (12, 0, "A4", 1.5), (12, 1.5, "C5", 0.5), (12, 2, "D5", 2), (13, 0, "E5", 1), (13, 1, "D5", 1), (13, 2, "A4", 2),
        (14, 0, "F4", 1.5), (14, 1.5, "G4", 0.5), (14, 2, "A4", 2), (15, 0, "C5", 1), (15, 1, "Bb4", 1), (15, 2, "A4", 2),
        (16, 0, "G4", 1.5), (16, 1.5, "A4", 0.5), (16, 2, "C5", 2), (17, 0, "E5", 2), (17, 2, "D5", 2),
        (18, 0, "C5", 1.5), (18, 1.5, "D5", 0.5), (18, 2, "E5", 1), (18, 3, "G5", 1), (19, 0, "F5", 2), (19, 2, "E5", 1), (19, 3, "D5", 1),
        (20, 0, "D5", 3), (20, 3, "C5", 1), (21, 0, "Bb4", 2), (21, 2, "A4", 2),
        (22, 0, "A4", 1), (22, 1, "C5", 1), (22, 2, "E5", 2), (23, 0, "D5", 4),
    ]
    for bar, beat, nn, beats in mel:
        f = hz(midi(nn))
        d = beats * m.beat
        s = bell(f, d, ratio=2.0, index=1.2, decay=0.9 + beats * 0.3)
        s2 = lead(f, d * 0.95, cutoff=1400.0, vib=1.0, shape="square") * 0.6
        m.add("lead", m.t(bar, beat), s, 0.11, pan=-0.1)
        m.add("lead", m.t(bar, beat), s2, 0.10, pan=0.1)

    # soft pulse: shaker + muted kick from bar 6, brushing the back half
    k = cached(kick, 0, 0.6)
    sh = cached(shaker, 4)
    for bar in range(24):
        if 6 <= bar < 22:
            m.add("drums", m.t(bar, 0), k, 0.22)
            m.add("drums", m.t(bar, 2.5), k, 0.13)
        if bar >= 4:
            for e in range(8):
                m.add("drums", m.t(bar, e * 0.5), sh, 0.22 if e % 2 else 0.12, pan=0.3)

    # sparkle: high bell glints every 4 bars
    for bar in range(0, 24, 4):
        m.add("bells", m.t(bar, 3.5), bell(hz(midi("A6")), 0.2, 4.1, 1.5, 2.5), 0.04, pan=0.7)
        m.add("bells", m.t(bar + 2, 1.5), bell(hz(midi("E6")), 0.2, 4.1, 1.5, 2.5), 0.035, pan=-0.7)

    B = m.buses
    dry = B["pad"] + B["bass"] * 1.0 + B["bells"] + B["lead"] + B["drums"]
    wet = circ_reverb(B["pad"] * 0.6 + B["bells"] + B["lead"] * 0.9 + B["drums"] * 0.2, 4.5, 100, damp=5000)
    dly = circ_delay(B["bells"] + B["lead"] * 0.6, m.beat * 0.75, 0.42, 6)
    return master(dry + wet * 0.55 + dly * 0.32, -1.5, MENU_EQ)


# ------------------------------------------------------------------ track: race A
def compose_race_a():
    """"Tether Line": driving and bright. A minor, 138 BPM, 32 bars.
    Form: intro 4 | A 8 | B 8 (hook) | break 4 | B' 8 (hook + full)."""
    m = Mix(138, 32)
    # chords per bar (4-bar cycle): Am | F | C | G  then variant Am | F | Dm | E
    cyc1 = [("A", ["A3", "C4", "E4"]), ("F", ["F3", "A3", "C4"]), ("C", ["G3", "C4", "E4"]), ("G", ["G3", "B3", "D4"])]
    cyc2 = [("A", ["A3", "C4", "E4"]), ("F", ["F3", "A3", "C4"]), ("D", ["F3", "A3", "D4"]), ("E", ["G#3", "B3", "E4"])]
    roots = {"A": "A1", "F": "F1", "C": "C2", "G": "G1", "D": "D2", "E": "E2"}

    def chords(bar):
        return (cyc1 if (bar // 4) % 2 == 0 else cyc2)[bar % 4]

    sec = lambda b: "intro" if b < 4 else "A" if b < 12 else "B" if b < 20 else "brk" if b < 24 else "B2"
    K, S, C = cached(kick, 0, 1.0), cached(snare, 1), cached(clap, 2)
    H, OH = cached(hat, False, 3), cached(hat, True, 8)
    kicks = []
    for bar in range(32):
        s = sec(bar)
        root_name, triad = chords(bar)
        root = midi(roots[root_name])
        # ---- drums
        if s != "brk":
            for b in range(4):
                m.add("drums", m.t(bar, b), K, 0.55)
                kicks.append(m.t(bar, b))
            if s != "intro":
                m.add("drums", m.t(bar, 1), S, 0.32, 0.05)
                m.add("drums", m.t(bar, 3), S, 0.32, 0.05)
                m.add("drums", m.t(bar, 1), C, 0.22, -0.1)
                m.add("drums", m.t(bar, 3), C, 0.22, -0.1)
            for e in range(8):
                if e % 2:
                    m.add("drums", m.t(bar, e * 0.5), OH if s in ("B", "B2") else H, 0.16 if s in ("B", "B2") else 0.22, 0.25)
            if s in ("A", "B", "B2"):
                for e in range(16):
                    if e % 4 in (1, 3):
                        m.add("drums", m.t(bar, e * 0.25), H, 0.1, -0.3)
            if bar % 8 == 7:  # fill
                for e in range(4):
                    m.add("drums", m.t(bar, 3 + e * 0.25), S, 0.12 + e * 0.05, 0.1)
        else:
            if bar >= 22:
                for e in range(4 if bar == 22 else 8):
                    step = 1.0 if bar == 22 else 0.5
                    m.add("drums", m.t(bar, e * step), S, 0.08 + 0.03 * e, 0.0)
        # ---- bass: off-beat 8ths rolling, octave pops
        if s != "brk" or bar >= 22:
            pat = [0, 0, 12, 0, 0, 12, 0, 7] if s != "intro" else [0, 0, 0, 0, 0, 0, 0, 0]
            for e in range(8):
                if s == "intro" and e % 2 == 0:
                    continue
                if bar >= 22 and s == "brk" and e % 2 == 0:
                    continue
                f = hz(root + 12 + pat[e]) if pat[e] else hz(root + 12)
                b = cached(bass, f, m.beat * 0.42, 1600.0 if s in ("B", "B2") else 1100.0)
                m.add("bass", m.t(bar, e * 0.5), b, 0.30)
        else:
            m.add("bass", m.t(bar, 0), cached(sub_drop, 6), 0.5 if bar == 20 else 0.0)
        # ---- pad (sidechained)
        for j, nn in enumerate(triad):
            p = cached(pad, hz(midi(nn)), m.bar - 0.05, 2600.0 if s in ("B", "B2", "brk") else 1500.0, 4, 16.0, 0.05, 0.4, 20 + j)
            m.add("pad", m.t(bar), p, 0.085, (j - 1) * 0.5)
        # ---- arp: 16ths over chord tones, two octaves
        if s in ("A", "B", "B2", "brk"):
            tones = [midi(x) + 12 for x in triad] + [midi(x) + 24 for x in triad]
            order = [0, 1, 2, 3, 2, 1, 4, 3, 0, 2, 1, 3, 5, 4, 2, 1]
            for e in range(16):
                nn = tones[order[e] % len(tones)]
                cut0 = 2200.0 + 2600.0 * ((bar % 8) / 7.0)  # filter opens over each 8 bars
                pl = cached(pluck, hz(nn), m.beat * 0.2, round(cut0, -2), 350.0, 0.06, "square", 6.0, 0.4)
                m.add("arp", m.t(bar, e * 0.25), pl, 0.075 if e % 4 else 0.1, pan=0.45 if e % 2 else -0.45)
    # ---- lead hook (B and B2), 8 bars, an original line in A minor
    hook = [  # (bar offset, beat, note, beats)
        (0, 0, "E5", 0.75), (0, 0.75, "D5", 0.25), (0, 1, "C5", 0.5), (0, 1.5, "E5", 1), (0, 2.5, "A5", 1.5),
        (1, 0, "G5", 0.5), (1, 0.5, "F5", 0.5), (1, 1, "E5", 0.5), (1, 1.5, "C5", 1.5), (1, 3, "D5", 1),
        (2, 0, "E5", 0.75), (2, 0.75, "G5", 0.75), (2, 1.5, "C6", 1), (2, 2.5, "B5", 0.5), (2, 3, "G5", 1),
        (3, 0, "D5", 1.5), (3, 1.5, "E5", 0.5), (3, 2, "D5", 0.5), (3, 2.5, "B4", 1.5),
        (4, 0, "E5", 0.75), (4, 0.75, "D5", 0.25), (4, 1, "C5", 0.5), (4, 1.5, "E5", 1), (4, 2.5, "A5", 1.5),
        (5, 0, "C6", 0.5), (5, 0.5, "B5", 0.5), (5, 1, "A5", 0.5), (5, 1.5, "F5", 1.5), (5, 3, "E5", 1),
        (6, 0, "F5", 0.75), (6, 0.75, "E5", 0.75), (6, 1.5, "D5", 1), (6, 2.5, "F5", 1.5),
        (7, 0, "E5", 1.5), (7, 1.5, "G#5", 1), (7, 2.5, "B5", 1.5),
    ]
    for start, oct_ in ((12, 0), (24, 0)):
        for bo, beat, nn, beats in hook:
            f = hz(midi(nn) + oct_)
            s = lead(f, beats * m.beat * 0.92, cutoff=3600.0, vib=1.0)
            m.add("lead", m.t(start + bo, beat), s, 0.16, -0.05)
            if start == 24:  # doubled an octave down in the last section
                m.add("lead", m.t(start + bo, beat), lead(f / 2, beats * m.beat * 0.92, 2000.0, 1.0, "square"), 0.09, 0.15)
    # ---- risers into sections
    for bar in (11, 19, 23, 31):
        r = cached(riser, m.bar, 5)
        m.add("fx", m.t(bar), r, 0.5 if bar != 31 else 0.3)
    for bar in (12, 24):
        m.add("fx", m.t(bar), bell(hz(midi("A6")), 0.1, 4.0, 2.5, 1.2), 0.06, 0.5)

    B = m.buses
    sc = duck(m, kicks, 0.65, 0.09)
    pad_ = B["pad"] * sc
    arp = B["arp"] * (0.5 + 0.5 * sc)
    dry = B["drums"] + B["bass"] + pad_ + arp + B["lead"] + B["fx"]
    wet = circ_reverb(pad_ * 0.5 + arp * 0.5 + B["lead"] * 0.7 + B["drums"] * 0.08, 2.4, 200, damp=6500)
    dly = circ_delay(B["lead"] + arp * 0.3, m.beat * 0.75, 0.35, 5)
    return master(dry + wet * 0.35 + dly * 0.22, -1.0, RACE_EQ)


# ------------------------------------------------------------------ track: race B
def compose_race_b():
    """"Whiteout": tense and syncopated. E minor, 146 BPM, 32 bars.
    Form: intro 4 | A 8 | B 8 | break 4 | A' 8."""
    m = Mix(146, 32)
    prog = [("E", ["E3", "G3", "B3", "D4"]), ("C", ["E3", "G3", "C4", "D4"]),
            ("D", ["F#3", "A3", "D4", "E4"]), ("B", ["F#3", "A3", "B3", "D#4"])]
    progB = [("A", ["E3", "A3", "C4", "E4"]), ("C", ["E3", "G3", "C4", "E4"]),
             ("G", ["D3", "G3", "B3", "D4"]), ("B", ["F#3", "A3", "B3", "D#4"])]
    roots = {"E": "E1", "C": "C2", "D": "D2", "B": "B1", "A": "A1", "G": "G1"}
    sec = lambda b: "intro" if b < 4 else "A" if b < 12 else "B" if b < 20 else "brk" if b < 24 else "A2"
    K, S, C = cached(kick, 10, 1.1), cached(snare, 11), cached(clap, 12)
    H, OH = cached(hat, False, 13), cached(hat, True, 14)
    kicks = []
    # 16-step bass pattern (1 = note, 2 = octave up), syncopated
    bpat = [1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 2, 0, 1, 0]
    kpat = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0]
    for bar in range(32):
        s = sec(bar)
        rn, voicing = (progB if s == "B" else prog)[bar % 4]
        root = midi(roots[rn])
        if s != "brk":
            for e in range(16):
                if kpat[e] or (s != "intro" and e in (4, 12) and False):
                    m.add("drums", m.t(bar, e * 0.25), K, 0.56)
                    kicks.append(m.t(bar, e * 0.25))
            if s != "intro":
                m.add("drums", m.t(bar, 1), S, 0.3)
                m.add("drums", m.t(bar, 3), S, 0.3)
                m.add("drums", m.t(bar, 3), C, 0.18)
            for e in range(16):
                acc = e % 4 == 2
                m.add("drums", m.t(bar, e * 0.25), OH if acc and s == "B" else H, 0.2 if acc else 0.09, 0.3 if e % 2 else -0.2)
            if bar % 4 == 3 and s != "intro":
                m.add("drums", m.t(bar, 3.75), S, 0.18)
        elif bar == 23:
            for e in range(16):
                m.add("drums", m.t(bar, e * 0.25), S, 0.04 + 0.016 * e)
        # bass
        if s != "brk":
            for e in range(16):
                if bpat[e]:
                    nn = root + 12 + (12 if bpat[e] == 2 else 0)
                    b = cached(bass, hz(nn), m.beat * 0.22, 1800.0 if s == "B" else 1300.0, 160.0, 0.07, 1.2)
                    m.add("bass", m.t(bar, e * 0.25), b, 0.32)
        elif bar == 20:
            m.add("bass", m.t(bar), cached(sub_drop, 16), 0.5)
        # stabs on the off-beats ("and" of 2 and 4) in A/A2, held pad in B and break
        if s in ("A", "A2"):
            for beat in (1.5, 3.5) if s == "A" else (0.75, 1.5, 3.0, 3.5):
                for j, nn in enumerate(voicing):
                    st = cached(pluck, hz(midi(nn) + 12), m.beat * 0.18, 5200.0, 600.0, 0.05, "saw", 14.0, 0.5)
                    m.add("stab", m.t(bar, beat), st, 0.05, (j - 1.5) * 0.35)
        if s in ("B", "brk", "intro"):
            for j, nn in enumerate(voicing):
                p = cached(pad, hz(midi(nn)), m.bar - 0.05, 2400.0 if s == "B" else 1200.0, 4, 18.0, 0.08 if s == "B" else 0.6, 0.5, 30 + j)
                m.add("pad", m.t(bar), p, 0.08, (j - 1.5) * 0.4)
        # pulse arp in B and break: 16ths alternating root/fifth/octave
        if s in ("B", "brk", "A2"):
            tones = [midi(voicing[0]) + 24, midi(voicing[2]) + 12, midi(voicing[1]) + 24, midi(voicing[3]) + 12]
            for e in range(16):
                pl = cached(pluck, hz(tones[e % 4]), m.beat * 0.16, 3200.0, 500.0, 0.04, "square", 4.0, 0.3)
                m.add("arp", m.t(bar, e * 0.25), pl, 0.055 if e % 4 else 0.08, 0.5 if e % 2 else -0.5)
    # lead: call-and-response motif in B, echoed in A2
    motif = [
        (0, 0, "B4", 0.5), (0, 0.5, "E5", 0.5), (0, 1, "F#5", 0.5), (0, 1.5, "G5", 1.0), (0, 2.5, "F#5", 0.5), (0, 3, "E5", 1),
        (1, 0.5, "D5", 0.5), (1, 1, "E5", 0.5), (1, 1.5, "B4", 2.5),
        (2, 0, "G5", 0.5), (2, 0.5, "A5", 0.5), (2, 1, "B5", 1), (2, 2, "D6", 0.75), (2, 2.75, "B5", 1.25),
        (3, 0, "A5", 0.5), (3, 0.5, "G5", 0.5), (3, 1, "F#5", 1.5), (3, 2.5, "D#5", 1.5),
    ]
    for start in (12, 16, 24, 28):
        last = start in (16, 28)
        for bo, beat, nn, beats in motif:
            nmid = midi(nn)
            if last and bo >= 2:   # second half answers lower
                nmid -= 5 if nn not in ("D#5",) else 0
            f = hz(nmid)
            m.add("lead", m.t(start + bo, beat), lead(f, beats * m.beat * 0.9, 3000.0, 1.0, "square"), 0.14, 0.0)
    for bar in (11, 19, 23, 31):
        m.add("fx", m.t(bar), cached(riser, m.bar, 15), 0.45)

    B = m.buses
    sc = duck(m, kicks, 0.6, 0.08)
    pad_ = B["pad"] * sc
    dry = B["drums"] + B["bass"] + pad_ + B["stab"] + B["arp"] * (0.6 + 0.4 * sc) + B["lead"] + B["fx"]
    wet = circ_reverb(pad_ * 0.6 + B["stab"] + B["arp"] * 0.4 + B["lead"] * 0.6 + B["drums"] * 0.06, 2.0, 300, damp=6000)
    dly = circ_delay(B["lead"] + B["stab"] * 0.5, m.beat * 0.5, 0.33, 5)
    return master(dry + wet * 0.32 + dly * 0.2, -1.0, RACE_EQ)


# ------------------------------------------------------------------ master + output
MENU_EQ = (-3.0, 2.0)
RACE_EQ = (-6.0, 4.0)


def phone_eq(st, low_cut_db, presence_db):
    """Tone shaping for small speakers: trim the sub-bass, lift 1-5 kHz.
    Done in the frequency domain over the whole loop (so it stays seamless)."""
    f = np.fft.rfftfreq(st.shape[1], 1.0 / SR)
    lf = np.log2(np.maximum(f, 1.0))
    low = low_cut_db / (1.0 + (np.maximum(f, 1.0) / 90.0) ** 2)     # shelf under ~90 Hz
    pres = presence_db * np.exp(-((lf - np.log2(2500.0)) ** 2) / (2 * 1.1 ** 2))
    g = 10 ** ((low + pres) / 20)
    return np.vstack([np.fft.irfft(np.fft.rfft(c) * g, st.shape[1]) for c in st])


def master(st, peak_db, eq=(0.0, 0.0)):
    st = st - st.mean(axis=1, keepdims=True)
    # gentle glue: soft-knee saturation then normalise
    pk = np.max(np.abs(st)) + 1e-9
    st = st / pk * 1.4
    st = np.tanh(st) / np.tanh(1.4)
    if eq != (0.0, 0.0):
        st = phone_eq(st, *eq)
    st *= 10 ** (peak_db / 20) / (np.max(np.abs(st)) + 1e-9)
    return st


def write_wav(path, st):
    data = (np.clip(st.T, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def main():
    keep = None
    if "--wav" in sys.argv:
        keep = sys.argv[sys.argv.index("--wav") + 1]
        os.makedirs(keep, exist_ok=True)
    only = [a for a in sys.argv[1:] if not a.startswith("--") and a != keep]
    os.makedirs(OUT, exist_ok=True)
    tracks = {"menu": compose_menu, "race_a": compose_race_a, "race_b": compose_race_b}
    for name, fn in tracks.items():
        if only and name not in only:
            continue
        print("composing", name, "...", flush=True)
        _cache.clear()
        st = fn()
        tmp = os.path.join(keep or tempfile.gettempdir(), name + ".wav")
        write_wav(tmp, st)
        ogg = os.path.join(OUT, name + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", "4", ogg], check=True)
        if not keep:
            os.remove(tmp)
        print("  %s  %.1f s  %d KB" % (ogg, st.shape[1] / SR, os.path.getsize(ogg) // 1024))


if __name__ == "__main__":
    main()
