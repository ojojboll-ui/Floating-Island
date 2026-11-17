"""Every sound in Skyholme, synthesised: nothing recorded or downloaded.

  audio/notes/   single notes the music is played from (audio.gd picks and
                 pitches them): music box, harp, a soft bowed pad, a low bell
  audio/nature/  loops: wind, birds, crickets, rain, a brook
  audio/fx/      what the hands do: a click, setting a thing down, earth,
                 water, a brush of paint, taking away, the camera

    python -I tools/make_sounds.py       (numpy only)
"""
import math
import os
import struct
import sys
import wave

import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(sys.argv[0]))
OUT = os.path.join(os.path.dirname(HERE), "audio")
rng = np.random.default_rng(7)


def write(path, x, loop=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * 0.89
    if not loop:
        fade = min(len(x), int(SR * 0.01))
        x[-fade:] *= np.linspace(1, 0, fade)
    data = (np.clip(x, -1, 1) * 32767).astype("<i2").tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


def t_of(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(t, attack, decay):
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / decay)


def lowpass(x, cutoff):
    """One-pole low-pass, run twice (gentle 12 dB)."""
    a = math.exp(-2 * math.pi * cutoff / SR)
    for _ in range(2):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = (1 - a) * v + a * acc
            y[i] = acc
        x = y
    return x


def lowpass_fast(x, cutoff):
    """The same filter through cumulative sums of blocks: fine for noise."""
    a = math.exp(-2 * math.pi * cutoff / SR)
    from numpy.lib.stride_tricks import sliding_window_view  # noqa
    # IIR via scipy is not here; use a short FIR window instead
    n = max(3, int(SR / cutoff / 2))
    k = np.hanning(n)
    k /= k.sum()
    return np.convolve(x, k, mode="same")


def noise(seconds):
    return rng.standard_normal(int(SR * seconds))


# ------------------------------------------------------------------ notes

def music_box(freq, seconds=3.2):
    t = t_of(seconds)
    # a struck tine: the fundamental, an inharmonic upper tone that dies fast
    x = np.sin(2 * np.pi * freq * t) * env(t, 0.002, 1.3)
    x += 0.45 * np.sin(2 * np.pi * freq * 5.4 * t) * env(t, 0.001, 0.18)
    x += 0.25 * np.sin(2 * np.pi * freq * 2.0 * t) * env(t, 0.002, 0.6)
    x += 0.12 * np.sin(2 * np.pi * freq * 8.9 * t) * env(t, 0.0005, 0.05)
    return x


def harp(freq, seconds=3.5):
    """Karplus-Strong: a plucked string."""
    n = int(SR * seconds)
    period = SR / freq
    p = int(period)
    buf = lowpass_fast(rng.uniform(-1, 1, p + 2), freq * 6)[:p]
    out = np.zeros(n)
    frac = period - p
    for i in range(n):
        j = i % p
        out[i] = buf[j]
        nxt = buf[(j + 1) % p]
        buf[j] = 0.4985 * (buf[j] + nxt) * (1 - frac * 0.0) + 0.0
    t = t_of(seconds)
    return out * np.clip(t / 0.004, 0, 1)


def pad(freq, seconds=6.0):
    """A soft bowed chord tone: a few detuned partials, slow swell and fade."""
    t = t_of(seconds)
    x = np.zeros_like(t)
    for k, amp in ((1, 1.0), (2, 0.35), (3, 0.16), (4, 0.06)):
        for det in (-0.25, 0.0, 0.3):
            vib = 0.0015 * np.sin(2 * np.pi * (4.6 + det) * t)
            x += amp * np.sin(2 * np.pi * freq * k * (1 + det / 100 + vib) * t + rng.uniform(0, 6))
    shape = np.clip(t / 1.6, 0, 1) ** 1.5 * np.clip((seconds - t) / 2.2, 0, 1)
    return x * shape


def bell(freq, seconds=5.0):
    t = t_of(seconds)
    x = np.zeros_like(t)
    for ratio, amp, dec in ((0.5, 0.5, 3.2), (1.0, 1.0, 2.4), (1.19, 0.4, 1.6), (1.56, 0.3, 1.1), (2.0, 0.28, 0.9), (2.74, 0.15, 0.5)):
        x += amp * np.sin(2 * np.pi * freq * ratio * t) * env(t, 0.003, dec)
    return x


# ------------------------------------------------------------------ nature

def make_loop(x, cross=1.0):
    """Fold the end over the start so the sound loops without a seam."""
    n = int(SR * cross)
    head, tail = x[:n], x[-n:]
    w = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * w + tail * (1 - w)
    return x


def wind(seconds=24):
    t = t_of(seconds + 2)
    n = noise(seconds + 2)
    low = lowpass_fast(n, 260)
    mid = lowpass_fast(n, 900) - lowpass_fast(n, 400)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / 7.3) * np.sin(2 * np.pi * t / 3.1 + 1.0)
    whistle = np.sin(2 * np.pi * (520 + 40 * np.sin(2 * np.pi * t / 5.0)) * t) * np.clip(gust - 0.7, 0, 1) * 0.04
    return make_loop(low * gust + mid * 0.4 * gust ** 2 + whistle, 2.0)


def chirp(f0, f1, seconds, warble=0.0):
    t = t_of(seconds)
    f = np.linspace(f0, f1, len(t)) * (1 + warble * np.sin(2 * np.pi * 38 * t))
    ph = np.cumsum(2 * np.pi * f / SR)
    return np.sin(ph) * np.sin(np.pi * t / seconds) ** 2


def birds(seconds=30):
    out = np.zeros(int(SR * seconds))
    k = 0.4
    while k < seconds - 2:
        kind = rng.integers(0, 3)
        start = int(SR * k)
        if kind == 0:     # a little falling phrase
            base = rng.uniform(2600, 3600)
            for j in range(rng.integers(3, 6)):
                c = chirp(base * (1 - j * 0.06), base * (0.9 - j * 0.06), 0.09, 0.02) * 0.6
                s = start + int(SR * j * 0.12)
                out[s:s + len(c)] += c[: len(out) - s]
        elif kind == 1:   # two-note call
            for j, f in enumerate((rng.uniform(3000, 4200), rng.uniform(2200, 2900))):
                c = chirp(f, f * 1.05, 0.18, 0.01) * 0.5
                s = start + int(SR * j * 0.24)
                out[s:s + len(c)] += c[: len(out) - s]
        else:             # trill
            f = rng.uniform(4000, 5200)
            for j in range(rng.integers(6, 12)):
                c = chirp(f, f * 0.92, 0.035) * 0.35
                s = start + int(SR * j * 0.05)
                out[s:s + len(c)] += c[: len(out) - s]
        k += rng.uniform(1.2, 4.5)
    return make_loop(out, 0.5)


def crickets(seconds=20):
    t = t_of(seconds + 1)
    out = np.zeros_like(t)
    for f, rate, ph in ((4300, 2.4, 0.0), (4700, 2.9, 1.3), (4050, 1.7, 2.2)):
        pulses = (np.sin(2 * np.pi * 30 * t) > 0.2).astype(float)
        bursts = (np.sin(2 * np.pi * rate * t + ph) > 0.35).astype(float)
        out += np.sin(2 * np.pi * f * t) * pulses * lowpass_fast(bursts, 60) * 0.3
    return make_loop(out, 1.0)


def rain(seconds=20):
    n = noise(seconds + 1)
    hiss = lowpass_fast(n, 5000) - lowpass_fast(n, 900)
    out = hiss * 0.5
    for _ in range(int(seconds * 40)):
        s = rng.integers(0, len(out) - 2000)
        d = noise(0.02) * np.exp(-t_of(0.02) / 0.004)
        out[s:s + len(d)] += lowpass_fast(d, rng.uniform(1500, 6000)) * rng.uniform(0.3, 1.0)
    return make_loop(out, 1.0)


def brook(seconds=20):
    n = noise(seconds + 1)
    body = lowpass_fast(n, 1400) - lowpass_fast(n, 300)
    out = body * 0.6
    t = t_of(seconds + 1)
    for _ in range(int(seconds * 14)):     # bubbles: little rising sines
        s = rng.integers(0, len(out) - 4000)
        dur = rng.uniform(0.02, 0.06)
        tt = t_of(dur)
        f0 = rng.uniform(500, 1400)
        b = np.sin(2 * np.pi * np.cumsum(f0 * (1 + tt / dur * 0.8)) / SR) * np.exp(-tt / (dur * 0.4))
        out[s:s + len(b)] += b * rng.uniform(0.2, 0.6)
    return make_loop(out, 1.0)


# ------------------------------------------------------------------ fx

def click():
    t = t_of(0.08)
    return (np.sin(2 * np.pi * 1700 * t) * env(t, 0.0005, 0.012) + 0.5 * lowpass_fast(noise(0.08), 3000) * env(t, 0.0003, 0.006))


def place():
    """A soft wooden thump with a little leafy rustle on top."""
    t = t_of(0.45)
    thump = np.sin(2 * np.pi * (140 + 80 * np.exp(-t / 0.02)) * t) * env(t, 0.002, 0.09)
    rustle = (lowpass_fast(noise(0.45), 6000) - lowpass_fast(noise(0.45), 2000)) * env(t, 0.01, 0.08) * 0.25
    return thump + rustle


def earth():
    """Raising or lowering ground: a soft crumbly scrape."""
    t = t_of(0.7)
    n = lowpass_fast(noise(0.7), 1100)
    grains = (rng.random(len(t)) > 0.996).astype(float)
    crumble = lowpass_fast(grains * rng.standard_normal(len(t)), 2500)
    return (n * 0.6 + crumble * 1.6) * np.sin(np.pi * t / 0.7) ** 1.2


def water():
    t = t_of(0.8)
    out = (lowpass_fast(noise(0.8), 2500) - lowpass_fast(noise(0.8), 500)) * 0.4
    for _ in range(18):
        s = rng.integers(0, len(t) - 3000)
        dur = rng.uniform(0.03, 0.07)
        tt = t_of(dur)
        f0 = rng.uniform(400, 1100)
        out[s:s + len(tt)] += np.sin(2 * np.pi * np.cumsum(f0 * (1 + tt / dur)) / SR) * np.exp(-tt / (dur * 0.35)) * 0.6
    return out * np.sin(np.pi * t / 0.8)


def paint():
    t = t_of(0.6)
    n = lowpass_fast(noise(0.6), 4000) - lowpass_fast(noise(0.6), 1200)
    return n * np.sin(np.pi * t / 0.6) ** 2


def remove():
    """A soft puff, falling."""
    t = t_of(0.4)
    n = lowpass_fast(noise(0.4), 1800)
    tone = np.sin(2 * np.pi * np.cumsum(500 * np.exp(-t / 0.15)) / SR) * 0.3
    return (n + tone) * env(t, 0.004, 0.09)


def shutter():
    t = t_of(0.35)
    a = lowpass_fast(noise(0.35), 5000) * env(t, 0.0005, 0.01)
    b = np.roll(lowpass_fast(noise(0.35), 3000) * env(t, 0.0005, 0.015), int(SR * 0.09))
    chime = music_box(1568, 0.35) * 0.0
    return a + b * 0.8 + chime


def chime_up():
    """Done, saved: two music box notes rising."""
    a = music_box(1174.66, 1.4)
    b = music_box(1567.98, 1.2)
    out = np.zeros(int(SR * 1.6))
    out[: len(a)] += a
    s = int(SR * 0.12)
    out[s:s + len(b)] += b
    return out


if __name__ == "__main__":
    notes = os.path.join(OUT, "notes")
    # the notes are recorded at A (music box, harp) or D (pad, bell); the
    # game pitches them to the note it wants
    write(os.path.join(notes, "musicbox_a5.wav"), music_box(880.0))
    write(os.path.join(notes, "harp_a3.wav"), harp(220.0))
    write(os.path.join(notes, "pad_d3.wav"), pad(146.83))
    write(os.path.join(notes, "bell_d4.wav"), bell(293.66))
    nature = os.path.join(OUT, "nature")
    write(os.path.join(nature, "wind.wav"), wind(), loop=True)
    write(os.path.join(nature, "birds.wav"), birds(), loop=True)
    write(os.path.join(nature, "crickets.wav"), crickets(), loop=True)
    write(os.path.join(nature, "rain.wav"), rain(), loop=True)
    write(os.path.join(nature, "brook.wav"), brook(), loop=True)
    fx = os.path.join(OUT, "fx")
    for name, f in (("click", click), ("place", place), ("earth", earth), ("water", water), ("paint", paint), ("remove", remove), ("shutter", shutter), ("chime", chime_up)):
        write(os.path.join(fx, name + ".wav"), f())
    print("sounds written to", OUT)
