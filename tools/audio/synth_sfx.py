"""Procedural sound effects and ambience loops (numpy synthesis -> OGG via ffmpeg).

Run from the repo root:  .venv/bin/python tools/audio/synth_sfx.py [--only name_substring]
Everything is deterministic (fixed seeds) and original: licence CC0 / own work.
"""
from __future__ import annotations

import argparse

import numpy as np
from scipy import signal

import catalog as C
import dsp

SEED = 3018
# Peak targets (dBFS) per effect class; footsteps sit well under one-shots so they never dominate.
FOOTSTEP_PEAK_DB = -12.0
DOOR_PEAK_DB = -6.0
SCREECH_PEAK_DB = -4.0
HEARTBEAT_PEAK_DB = -8.0
# Ambience loudness (LUFS): well below the music stems (-19) so music stays in front.
AMBIENCE_LUFS = {"wind": -30.0, "birds_day": -32.0, "crickets_night": -34.0,
                 "rain": -28.0, "river": -29.0, "inn_murmur": -29.0}


def _stable(name: str) -> int:
    # hash() of str is salted per process; use a stable checksum so renders are reproducible.
    return sum((i + 1) * ord(ch) for i, ch in enumerate(name))


# ----------------------------------------------------------------------------- footsteps

def footstep(surface: str, variant: int) -> np.ndarray:
    sr = C.SFX_RATE
    rng = np.random.default_rng([SEED, _stable(surface), variant])
    n = int(0.35 * sr)
    t = np.arange(n) / sr
    # Each variant is slightly different in pitch and weight so repeated steps don't machine-gun.
    pitch = 1.0 + 0.12 * (variant - 2) + rng.uniform(-0.03, 0.03)
    out = np.zeros(n)

    def thump(freq: float, tau: float, amp: float) -> np.ndarray:
        return amp * np.sin(2 * np.pi * freq * pitch * t) * np.exp(-t / tau)

    if surface == "grass":
        swish = dsp.sos(rng.normal(size=n), "bandpass", (700 * pitch, 4500), sr, 2)
        env = dsp.attack_env(n, sr, 0.012) * np.exp(-t / 0.07)
        out = swish * env + thump(80, 0.05, 0.25)
        out += 0.5 * np.roll(swish * np.exp(-t / 0.05), int(0.045 * sr)) * (t > 0.045)
    elif surface == "dirt":
        base = dsp.sos(rng.normal(size=n), "lowpass", 1600 * pitch, sr, 3) * np.exp(-t / 0.05)
        grit = np.zeros(n)
        for pos in rng.uniform(0.0, 0.09, 18):
            grit[int(pos * sr)] += rng.uniform(0.3, 1.0)
        grit = dsp.sos(grit, "bandpass", (1200, 5000), sr, 2) * 3.0
        out = base + grit * np.exp(-t / 0.05) + thump(95, 0.06, 0.55)
    elif surface == "wood":
        click = dsp.sos(rng.normal(size=n), "bandpass", (1500, 3500), sr, 2) * np.exp(-t / 0.006)
        modes = sum(a * np.sin(2 * np.pi * f * pitch * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
                    for f, tau, a in ((150, 0.11, 0.6), (235, 0.09, 0.45), (415, 0.06, 0.3), (690, 0.04, 0.15)))
        out = click * 0.6 + modes + thump(70, 0.04, 0.4)
    elif surface == "stone":
        click = dsp.sos(rng.normal(size=n), "highpass", 1800, sr, 2) * np.exp(-t / 0.012)
        ping = np.sin(2 * np.pi * 1900 * pitch * t) * np.exp(-t / 0.03) * 0.25
        ring = np.sin(2 * np.pi * 640 * pitch * t) * np.exp(-t / 0.06) * 0.35
        out = click + ping + ring + thump(110, 0.035, 0.3)
    else:
        raise ValueError(surface)
    out *= dsp.release_env(n, sr, 0.03)
    return dsp.normalise_peak(out, FOOTSTEP_PEAK_DB)


# ----------------------------------------------------------------------------- ambience loops

def _periodic_lfo(n: int, sr: int, rng: np.random.Generator, cycles: tuple[int, ...]) -> np.ndarray:
    """Sum of sines with an integer number of cycles per loop, so the modulation is seamless."""
    t = np.arange(n) / n
    lfo = sum(rng.uniform(0.5, 1.0) * np.sin(2 * np.pi * (c * t + rng.uniform())) for c in cycles)
    return lfo / len(cycles)


def wind() -> np.ndarray:
    sr, n = C.AMBIENCE_RATE, int(C.AMBIENCE_LOOP_SECONDS * C.AMBIENCE_RATE)
    rng = np.random.default_rng([SEED, 1])
    low = dsp.fft_shape(rng.normal(size=n), sr, lambda f: 1.0 / (1.0 + (f / 180.0) ** 2) / np.sqrt(f / 60.0 + 1.0))
    mid = dsp.fft_shape(rng.normal(size=n), sr, lambda f: np.exp(-((np.log(f / 550.0)) ** 2) / 0.5))
    gust_a = 0.55 + 0.45 * _periodic_lfo(n, sr, rng, (1, 2, 3))
    gust_b = 0.45 + 0.55 * _periodic_lfo(n, sr, rng, (2, 3, 5))
    low, mid = low / np.std(low), mid / np.std(mid)
    return low * np.clip(gust_a, 0.05, 1.5) + 0.7 * mid * np.clip(gust_b, 0.02, 1.5) ** 2


def _chirp(sr: int, dur: float, f_start: float, f_end: float, curve: float = 1.0, am: float = 0.0) -> np.ndarray:
    n = int(dur * sr)
    u = np.linspace(0.0, 1.0, n) ** curve
    freq = f_start + (f_end - f_start) * u
    phase = 2 * np.pi * np.cumsum(freq) / sr
    env = np.sin(np.pi * np.linspace(0.0, 1.0, n)) ** 0.7
    sig = np.sin(phase) * env
    if am:
        sig *= 1.0 - am + am * np.sin(2 * np.pi * 55 * np.arange(n) / sr)
    return sig


def birds_day() -> np.ndarray:
    sr, n = C.AMBIENCE_RATE, int(C.AMBIENCE_LOOP_SECONDS * C.AMBIENCE_RATE)
    rng = np.random.default_rng([SEED, 2])
    out = 0.02 * dsp.fft_shape(rng.normal(size=n), sr, lambda f: np.exp(-((np.log(f / 3500.0)) ** 2) / 1.5))
    # Three voices: fast tweet runs, a descending warble, and a two-note cuckoo-like call.
    for _ in range(14):
        base = rng.uniform(3200, 5200)
        notes = rng.integers(3, 7)
        pos = rng.uniform(0.0, C.AMBIENCE_LOOP_SECONDS)
        for k in range(notes):
            dsp.add_wrapped(out, rng.uniform(0.3, 0.6) * _chirp(sr, 0.055, base * 1.1, base * 0.85),
                            int((pos + k * 0.085) * sr))
    for _ in range(5):
        base = rng.uniform(2400, 3400)
        dsp.add_wrapped(out, rng.uniform(0.2, 0.4) * _chirp(sr, 0.5, base, base * 1.5, 0.6, 0.35),
                        int(rng.uniform(0.0, C.AMBIENCE_LOOP_SECONDS) * sr))
    for pos in (1.5, 7.2):
        dsp.add_wrapped(out, 0.35 * _chirp(sr, 0.22, 780, 720), int(pos * sr))
        dsp.add_wrapped(out, 0.35 * _chirp(sr, 0.3, 640, 590), int((pos + 0.3) * sr))
    return out


def crickets_night() -> np.ndarray:
    sr, n = C.AMBIENCE_RATE, int(C.AMBIENCE_LOOP_SECONDS * C.AMBIENCE_RATE)
    rng = np.random.default_rng([SEED, 3])
    out = 0.01 * dsp.fft_shape(rng.normal(size=n), sr, lambda f: np.exp(-((np.log(f / 4200.0)) ** 2) / 0.8))
    pulse_len = int(0.011 * sr)
    pt = np.arange(pulse_len) / sr
    for _ in range(6):
        freq = rng.uniform(3900, 4800)
        pulse = np.sin(2 * np.pi * freq * pt) * np.sin(np.pi * np.linspace(0, 1, pulse_len)) ** 2
        gain = rng.uniform(0.2, 0.5)
        period = rng.uniform(0.42, 0.62)
        t0 = rng.uniform(0.0, period)
        while t0 < C.AMBIENCE_LOOP_SECONDS:
            for k in range(rng.integers(3, 5)):
                dsp.add_wrapped(out, gain * pulse, int((t0 + k * 0.028) * sr))
            t0 += period
    return out


def rain() -> np.ndarray:
    sr, n = C.AMBIENCE_RATE, int(C.AMBIENCE_LOOP_SECONDS * C.AMBIENCE_RATE)
    rng = np.random.default_rng([SEED, 4])
    hiss = dsp.fft_shape(rng.normal(size=n), sr,
                         lambda f: np.clip(f / 600.0, 0, 1) / (1.0 + (f / 7000.0) ** 3))
    drops = np.zeros(n)
    idx = rng.integers(0, n, int(sr * 0.05 * C.AMBIENCE_LOOP_SECONDS * 12))
    np.add.at(drops, idx, rng.uniform(0.2, 1.0, len(idx)))
    drops = dsp.fft_shape(drops, sr, lambda f: np.exp(-((np.log(f / 3800.0)) ** 2) / 1.2))
    swell = 0.85 + 0.15 * _periodic_lfo(n, sr, rng, (1, 3))
    return (hiss / np.std(hiss) + 0.6 * drops / np.std(drops)) * swell


def river() -> np.ndarray:
    sr, n = C.AMBIENCE_RATE, int(C.AMBIENCE_LOOP_SECONDS * C.AMBIENCE_RATE)
    rng = np.random.default_rng([SEED, 5])
    body = dsp.fft_shape(rng.normal(size=n), sr, lambda f: 1.0 / (1.0 + (f / 700.0) ** 2) * np.sqrt(f / 100.0 + 1.0))
    flow = 0.7 + 0.3 * _periodic_lfo(n, sr, rng, (2, 5, 9))
    out = body / np.std(body) * flow
    bubbles = np.zeros(n)
    for _ in range(int(C.AMBIENCE_LOOP_SECONDS * 28)):
        f0 = rng.uniform(300, 900)
        dsp.add_wrapped(bubbles, rng.uniform(0.1, 0.4) * _chirp(sr, rng.uniform(0.03, 0.08), f0, f0 * 1.9),
                        int(rng.uniform(0, C.AMBIENCE_LOOP_SECONDS) * sr))
    return out + 0.5 * bubbles / (np.std(bubbles) + 1e-9) * 0.4


# Rough vowel formant pairs (F1, F2) in Hz; murmur only needs the vowel-ish colour, not words.
VOWELS = ((730, 1090), (530, 1840), (270, 2290), (570, 840), (300, 870), (660, 1720))


def _syllable(sr: int, f0: float, formants: tuple[int, int], dur: float, rng: np.random.Generator) -> np.ndarray:
    n = int(dur * sr)
    t = np.arange(n) / sr
    f = f0 * (1.0 + 0.08 * np.sin(2 * np.pi * rng.uniform(1, 3) * t + rng.uniform(0, 6)) + 0.1 * (0.5 - t / dur))
    phase = 2 * np.pi * np.cumsum(f) / sr
    out = np.zeros(n)
    for h in range(1, int(3500 / f0)):
        hf = h * f0
        gain = sum(1.0 / (1.0 + ((hf - fm) / 130.0) ** 2) for fm in formants) / h ** 0.5
        out += gain * np.sin(h * phase)
    return out * np.sin(np.pi * t / dur) ** 1.5


def inn_murmur() -> np.ndarray:
    sr, n = C.AMBIENCE_RATE, int(C.AMBIENCE_LOOP_SECONDS * C.AMBIENCE_RATE)
    rng = np.random.default_rng([SEED, 6])
    out = np.zeros(n)
    for _ in range(9):
        f0 = rng.choice([95, 110, 125, 150, 190, 215, 240]) * rng.uniform(0.95, 1.05)
        pos = rng.uniform(0.0, 1.5)
        while pos < C.AMBIENCE_LOOP_SECONDS:
            for _ in range(rng.integers(3, 8)):
                dur = rng.uniform(0.09, 0.2)
                v = VOWELS[rng.integers(len(VOWELS))]
                dsp.add_wrapped(out, rng.uniform(0.5, 1.0) * _syllable(sr, f0, v, dur, rng), int(pos * sr))
                pos += dur + rng.uniform(0.01, 0.06)
            pos += rng.uniform(0.4, 2.4)
    out = dsp.fft_shape(out, sr, lambda f: 1.0 / (1.0 + (f / 2400.0) ** 2))
    out /= np.std(out)
    room = dsp.fft_shape(rng.normal(size=n), sr, lambda f: 1.0 / (1.0 + (f / 500.0) ** 2))
    out += 0.25 * room / np.std(room)
    # Occasional mug/glass clinks: inharmonic high partials with fast decay.
    for pos in rng.uniform(0.5, C.AMBIENCE_LOOP_SECONDS - 0.5, 4):
        m = int(0.35 * sr)
        mt = np.arange(m) / sr
        f = rng.uniform(2200, 3600)
        clink = sum(a * np.sin(2 * np.pi * f * r * mt) * np.exp(-mt / tau)
                    for r, a, tau in ((1.0, 1.0, 0.08), (2.32, 0.5, 0.05), (4.1, 0.25, 0.03)))
        dsp.add_wrapped(out, 0.45 * clink, int(pos * sr))
    return out


# ----------------------------------------------------------------------------- one-shots

def door() -> np.ndarray:
    sr = C.SFX_RATE
    rng = np.random.default_rng([SEED, 7])
    creak_n = int(0.7 * sr)
    ct = np.arange(creak_n) / sr
    # Stick-slip creak: a sawtooth whose pitch wobbles, chopped by a ragged amplitude pattern.
    f = 150 + 70 * ct / 0.7 + 25 * np.sin(2 * np.pi * 9 * ct)
    saw = signal.sawtooth(2 * np.pi * np.cumsum(f) / sr)
    chop = np.clip(dsp.sos(rng.normal(size=creak_n), "lowpass", 30, sr, 2) * 8.0 + 0.6, 0.0, 1.0)
    creak = dsp.sos(saw * chop, "bandpass", (250, 1400), sr, 2) * np.sin(np.pi * ct / 0.7) ** 0.8
    out = np.zeros(int(1.3 * sr))
    out[:creak_n] += 0.55 * creak
    tstart = int(0.78 * sr)
    m = len(out) - tstart
    mt = np.arange(m) / sr
    thud = np.sin(2 * np.pi * 62 * mt) * np.exp(-mt / 0.09) + 0.5 * np.sin(2 * np.pi * 130 * mt) * np.exp(-mt / 0.05)
    latch = dsp.sos(rng.normal(size=m), "bandpass", (900, 3000), sr, 2) * np.exp(-mt / 0.012)
    out[tstart:] += thud + 0.4 * latch
    out *= dsp.release_env(len(out), sr, 0.05)
    return dsp.normalise_peak(out, DOOR_PEAK_DB)


def rider_screech() -> np.ndarray:
    sr = C.SFX_RATE
    rng = np.random.default_rng([SEED, 8])
    dur = 1.6
    n = int(dur * sr)
    t = np.arange(n) / sr
    # Glide up to a shriek, then sag: wails read as inhuman because of the wide, fast pitch swing.
    f0 = np.interp(t, [0.0, 0.35, 0.9, dur], [520.0, 2300.0, 1700.0, 800.0])
    f0 = f0 * (1.0 + 0.035 * np.sin(2 * np.pi * 7.5 * t)) + 40 * dsp.sos(rng.normal(size=n), "lowpass", 25, sr, 2) * 20
    phase = 2 * np.pi * np.cumsum(f0) / sr
    voice = np.zeros(n)
    for h in range(1, 14):
        # Skip harmonics above Nyquist-ish to avoid aliasing as the pitch peaks.
        voice += np.where(h * f0 < 0.45 * sr, np.sin(h * phase) / h ** 0.8, 0.0)
    breath = dsp.sos(rng.normal(size=n), "bandpass", (1500, 6000), sr, 2)
    src = voice / np.std(voice) + 0.9 * breath / np.std(breath)
    shaped = dsp.sos(src, "bandpass", (700, 4800), sr, 2) + 0.6 * dsp.sos(src, "bandpass", (2400, 3000), sr, 2)
    env = dsp.attack_env(n, sr, 0.06) * np.interp(t, [0.0, 0.9, dur], [1.0, 0.9, 0.0]) ** 1.5
    dist = np.tanh(2.5 * shaped / np.std(shaped)) * env
    wet = dsp.reverb(dist, sr, 2.4, rng, 0.45, predelay=0.02, damp_hz=4500)
    return dsp.normalise_peak(wet, SCREECH_PEAK_DB)


def heartbeat() -> np.ndarray:
    sr = C.SFX_RATE
    n = int(C.HEARTBEAT_SECONDS * sr)
    out = np.zeros(n)
    rng = np.random.default_rng([SEED, 9])
    for start, amp, f in ((0.0, 1.0, 58.0), (0.3, 0.7, 68.0)):
        m = int(0.28 * sr)
        mt = np.arange(m) / sr
        beat = np.sin(2 * np.pi * f * mt * (1.0 - 0.3 * mt / 0.28)) * np.exp(-mt / 0.07)
        beat += 0.3 * dsp.sos(rng.normal(size=m), "lowpass", 200, sr, 2) * np.exp(-mt / 0.04)
        beat *= dsp.attack_env(m, sr, 0.008)
        dsp.add_wrapped(out, amp * beat, int(start * sr))
    return dsp.normalise_peak(out, HEARTBEAT_PEAK_DB)


# ----------------------------------------------------------------------------- driver

def render_all(only: str = "") -> dict[str, int]:
    sizes: dict[str, int] = {}

    def emit(rel: str, x: np.ndarray, sr: int) -> None:
        if only and only not in rel:
            return
        sizes[rel] = dsp.write_ogg(x, sr, C.OUT_ROOT / rel)
        print(f"{rel}: {len(x) / sr:.2f}s, {sizes[rel] / 1024:.0f} KiB")

    for s in C.SURFACES:
        for i in range(1, C.FOOTSTEP_VARIANTS + 1):
            if not only or only in f"sfx/footstep_{s}_{i}.ogg":
                emit(f"sfx/footstep_{s}_{i}.ogg", footstep(s, i), C.SFX_RATE)
    emit("sfx/door.ogg", door(), C.SFX_RATE)
    emit("sfx/rider_screech.ogg", rider_screech(), C.SFX_RATE)
    emit("sfx/heartbeat.ogg", heartbeat(), C.SFX_RATE)
    gens = {"wind": wind, "birds_day": birds_day, "crickets_night": crickets_night,
            "rain": rain, "river": river, "inn_murmur": inn_murmur}
    for name, fn in gens.items():
        if only and only not in f"ambience/{name}.ogg":
            continue
        emit(f"ambience/{name}.ogg", dsp.normalise_lufs(fn(), C.AMBIENCE_RATE, AMBIENCE_LUFS[name]), C.AMBIENCE_RATE)
    return sizes


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="render only files whose id contains this text")
    args = ap.parse_args()
    render_all(args.only)


if __name__ == "__main__":
    main()
