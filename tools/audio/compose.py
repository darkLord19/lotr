"""Procedural music stems: short, seamlessly loopable layers in D and G modes.

Run from the repo root:  .venv/bin/python tools/audio/compose.py [--only stem_name]
All stems share one 24 s loop (8 bars of 3 s) so the in-game director can run them in lock-step
and fade layers in and out. Instruments are plain additive/FM synthesis; licence CC0 / own work.
Notes whose tails pass the loop end wrap around to the start, which is what makes loops seamless.
"""
from __future__ import annotations

import argparse
from typing import Callable

import numpy as np

import catalog as C
import dsp

SR = C.MUSIC_RATE
LOOP_N = int(C.MUSIC_LOOP_SECONDS * SR)
BEAT = 0.75  # 4/4 at 80 BPM
EIGHTH_6_8 = 0.5  # one eighth of the 6/8 jig; bar = 6 * 0.5 = 3 s
# Per-stem loudness (LUFS). Two or three stems summed by the director land near -16 LUFS.
STEM_LUFS = -19.0
SEED = 3018

NOTE_OFFSETS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name: str) -> int:
    """'F#3' -> 54, 'Bb2' -> 46."""
    base = NOTE_OFFSETS[name[0]]
    rest = name[1:]
    if rest[0] == "#":
        base += 1
        rest = rest[1:]
    elif rest[0] == "b":
        base -= 1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + base


def hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def loop_snap(freq: float) -> float:
    """Snap to a whole number of cycles per loop so a sustained tone is phase-continuous at the seam."""
    return max(1.0, round(freq * C.MUSIC_LOOP_SECONDS)) / C.MUSIC_LOOP_SECONDS


def place(buf: np.ndarray, sig: np.ndarray, t0: float) -> None:
    dsp.add_wrapped(buf, sig, int(round(t0 * SR)))


# ----------------------------------------------------------------------------- instruments

def pad_note(freq: float, dur: float, amp: float = 1.0) -> np.ndarray:
    """Soft organ/string pad: a few harmonics, three slightly detuned copies, slow swell."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for detune_cents, phase in ((-4, 0.0), (0, 0.0), (4, 0.0)):
        f = freq * 2 ** (detune_cents / 1200)
        for h, a in enumerate((1.0, 0.5, 0.3, 0.18, 0.1, 0.06), start=1):
            out += a * np.sin(2 * np.pi * f * h * t + phase)
    env = dsp.attack_env(n, SR, 1.6) * dsp.release_env(n, SR, 1.6)
    return amp * out * env / 6.0


def pluck(freq: float, dur: float, vel: float = 1.0, bright: float = 1.0) -> np.ndarray:
    """Harp-like pluck: upper partials die faster than the fundamental, tiny inharmonic stretch."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for h in range(1, 12):
        fh = freq * h * (1.0 + 0.0004 * h * h)
        if fh > 0.45 * SR:
            break
        tau = 1.1 / (1.0 + 0.55 * h)
        out += (1.0 / h ** (1.15 / bright)) * np.sin(2 * np.pi * fh * t) * np.exp(-t / tau)
    out *= dsp.attack_env(n, SR, 0.004) * dsp.release_env(n, SR, 0.05)
    return vel * out


def flute_note(freq: float, dur: float, vel: float, rng: np.random.Generator) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib = 1.0 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - 0.2) / 0.3, 0.0, 1.0)
    phase = 2 * np.pi * np.cumsum(freq * vib) / SR
    tone = np.sin(phase) + 0.22 * np.sin(2 * phase) + 0.07 * np.sin(3 * phase)
    breath = dsp.sos(rng.normal(size=n), "bandpass", (freq * 1.5, freq * 4.0), SR, 2)
    env = dsp.attack_env(n, SR, 0.07) * dsp.release_env(n, SR, 0.12)
    swell = 0.85 + 0.15 * np.sin(np.pi * t / dur)
    return vel * (tone + 0.06 * breath / (np.std(breath) + 1e-9)) * env * swell


def bowed(freq: float, dur: float, vel: float, rng: np.random.Generator, vib_hz: float = 5.5,
          vib_depth: float = 0.007, attack: float = 0.03, bright_hz: float = 2600.0,
          tremolo_hz: float = 0.0) -> np.ndarray:
    """Bowed string: sawtooth-ish additive spectrum with a low-pass tilt, vibrato and bow noise."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    vib = 1.0 + vib_depth * np.sin(2 * np.pi * vib_hz * t) * np.clip((t - 0.08) / 0.2, 0.0, 1.0)
    phase = 2 * np.pi * np.cumsum(freq * vib) / SR
    out = np.zeros(n)
    for h in range(1, 20):
        if freq * h > 0.45 * SR:
            break
        out += np.sin(h * phase) / h / np.sqrt(1.0 + (freq * h / bright_hz) ** 2)
    noise = dsp.sos(rng.normal(size=n), "bandpass", (freq * 2, freq * 8), SR, 2)
    out = out + 0.02 * noise / (np.std(noise) + 1e-9)
    env = dsp.attack_env(n, SR, attack) * dsp.release_env(n, SR, 0.07)
    if tremolo_hz:
        env = env * (0.75 + 0.25 * np.sin(2 * np.pi * tremolo_hz * t))
    return vel * out * env


def thump(freq: float, tau: float, vel: float) -> np.ndarray:
    n = int(6 * tau * SR)
    t = np.arange(n) / SR
    return vel * np.sin(2 * np.pi * freq * t * (1.0 - 0.25 * np.clip(t / tau, 0, 1))) * np.exp(-t / tau) \
        * dsp.attack_env(n, SR, 0.005)


# ----------------------------------------------------------------------------- stems

# I - IV - bVII - I in D mixolydian: the classic folk "open" sound, two bars per chord.
PASTORAL_CHORDS = (
    ("D2", "A2", "D3", "F#3"),   # D
    ("D2", "G2", "D3", "B3"),    # G over the D drone
    ("D2", "G2", "C3", "E3"),    # C over the D drone
    ("D2", "A2", "D3", "F#3"),   # D
)
HARP_CHORD_TONES = (
    ("D3", "A3", "D4", "F#4", "A4", "D5"),
    ("G3", "D4", "G4", "B4", "D5", "G5"),
    ("C4", "G4", "C5", "E5", "G5", "C6"),
    ("D3", "A3", "D4", "F#4", "A4", "D5"),
)
BLOCK_SECONDS = 2 * C.BAR_SECONDS


def stem_pad() -> np.ndarray:
    out = np.zeros(LOOP_N)
    for k, chord in enumerate(PASTORAL_CHORDS):
        for i, name in enumerate(chord):
            f = loop_snap(hz(midi(name)))
            # Overlap each block by the pad's attack/release so chord changes glide.
            place(out, pad_note(f, BLOCK_SECONDS + 3.2, 1.0 if i == 0 else 0.55), k * BLOCK_SECONDS - 1.6)
    return out


def stem_harp_day() -> np.ndarray:
    rng = np.random.default_rng([SEED, 11])
    out = np.zeros(LOOP_N)
    # Eight eighth-notes per bar: rolling up and back over the chord, with a lifted accent each bar.
    pattern = (0, 2, 3, 4, 3, 2, 4, 2)
    eighth = BEAT / 2
    for k, tones in enumerate(HARP_CHORD_TONES):
        for bar in range(2):
            for i, idx in enumerate(pattern):
                t0 = k * BLOCK_SECONDS + bar * C.BAR_SECONDS + i * eighth + rng.uniform(-0.008, 0.008)
                vel = (0.9 if i % 4 == 0 else 0.55) * rng.uniform(0.9, 1.0)
                place(out, pluck(hz(midi(tones[idx])), 2.2, vel), t0)
    return out


def stem_harp_night() -> np.ndarray:
    rng = np.random.default_rng([SEED, 12])
    out = np.zeros(LOOP_N)
    # Sparse lullaby: one soft low note per beat at most, a third of the beats left silent.
    for k, tones in enumerate(HARP_CHORD_TONES):
        for beat in range(8):
            if rng.uniform() < 0.35:
                continue
            idx = int(rng.integers(0, 5))
            t0 = k * BLOCK_SECONDS + beat * BEAT * 1.0
            place(out, pluck(hz(midi(tones[idx])) * 0.5 if idx == 0 else hz(midi(tones[idx])), 3.0,
                             rng.uniform(0.4, 0.7), bright=0.8), t0)
    return out


# (note, beats) phrase for the pastoral flute: eight 4/4 bars; None is a rest.
FLUTE_MELODY: tuple[tuple[str | None, float], ...] = (
    ("A4", 1.5), ("B4", 0.5), ("A4", 1.0), ("F#4", 1.0),
    ("E4", 2.0), ("F#4", 1.0), ("A4", 1.0),
    ("B4", 1.5), ("C5", 0.5), ("B4", 1.0), ("A4", 1.0),
    ("A4", 3.0), (None, 1.0),
    ("D5", 1.5), ("C5", 0.5), ("B4", 1.0), ("A4", 1.0),
    ("G4", 1.0), ("A4", 1.0), ("B4", 1.0), ("A4", 1.0),
    ("G4", 1.5), ("F#4", 0.5), ("E4", 1.0), ("F#4", 1.0),
    ("D4", 3.0), (None, 1.0),
)


def stem_flute_day() -> np.ndarray:
    rng = np.random.default_rng([SEED, 13])
    out = np.zeros(LOOP_N)
    t0 = 0.0
    for name, beats in FLUTE_MELODY:
        dur = beats * BEAT
        if name is not None:
            place(out, flute_note(hz(midi(name)), dur + 0.08, 0.8 if beats >= 1.5 else 0.65, rng), t0)
        t0 += dur
    assert abs(t0 - C.MUSIC_LOOP_SECONDS) < 1e-6, t0
    return out


# G mixolydian jig: scale degree index from G4 (negative goes below), None holds the previous note.
G_MIXO_SEMITONES = (0, 2, 4, 5, 7, 9, 10)  # G A B C D E F


def _g_scale_midi(idx: int) -> int:
    octave, degree = divmod(idx, 7)
    return midi("G4") + 12 * octave + G_MIXO_SEMITONES[degree]


JIG: tuple[tuple[int | None, ...], ...] = (
    (0, 2, 4, 7, 4, 2),
    (3, 5, 7, 5, 3, 1),
    (0, 2, 4, 7, 4, 2),
    (3, 2, 1, 0, None, None),
    (4, 4, 5, 6, 5, 4),
    (4, 5, 7, 8, 7, 5),
    (3, 2, 1, 2, 1, 0),
    (1, 0, -3, 0, None, None),
)


def stem_fiddle_inn() -> np.ndarray:
    rng = np.random.default_rng([SEED, 14])
    out = np.zeros(LOOP_N)
    for bar, notes in enumerate(JIG):
        i = 0
        while i < len(notes):
            idx = notes[i]
            j = i + 1
            while j < len(notes) and notes[j] is None:
                j += 1
            assert idx is not None
            held = (j - i) * EIGHTH_6_8
            # Short notes are detached (bow lifts); held notes ring out fully.
            dur = held * (0.92 if j - i > 1 else 0.82)
            accent = 1.0 if i in (0, 3) else 0.78
            place(out, bowed(hz(_g_scale_midi(idx)), dur + 0.05, 0.8 * accent, rng), bar * C.BAR_SECONDS + i * EIGHTH_6_8)
            i = j
        # Drone double-stop and a foot-stamp on the two main beats of each 6/8 bar.
        for beat in (0, 3):
            t0 = bar * C.BAR_SECONDS + beat * EIGHTH_6_8
            place(out, bowed(hz(midi("G3")), 1.35, 0.22, rng, vib_depth=0.0, attack=0.08, bright_hz=1200.0), t0)
            place(out, bowed(hz(midi("D4")), 1.35, 0.16, rng, vib_depth=0.0, attack=0.08, bright_hz=1200.0), t0)
            place(out, thump(78.0, 0.07, 0.5 if beat == 0 else 0.35), t0)
    return out


# D phrygian: the flat second (Eb) is what makes it sound menacing.
DANGER_BLOCKS = (
    ("D2", "A2"),
    ("Eb2", "Bb2"),
    ("F2", "C3"),
    ("D2", "A2"),
)


def stem_strings_danger() -> np.ndarray:
    rng = np.random.default_rng([SEED, 15])
    out = np.zeros(LOOP_N)
    for k, notes in enumerate(DANGER_BLOCKS):
        for name in notes:
            f = loop_snap(hz(midi(name)))
            # Slow tremolo, snapped to whole cycles per block so it doesn't beat against the seam.
            tremolo = 7.0
            place(out, bowed(f, BLOCK_SECONDS + 1.6, 0.9 if name[0] != "A" else 0.5, rng,
                             vib_depth=0.004, attack=0.5, bright_hz=1100.0, tremolo_hz=tremolo),
                  k * BLOCK_SECONDS - 0.8)
    # A and Bb a semitone apart in the second half: the beating is deliberately uncomfortable.
    for name, start in (("A4", 12.0), ("Bb4", 13.5)):
        n = int(11.0 * SR)
        t = np.arange(n) / SR
        f = hz(midi(name))
        tone = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t)
        env = dsp.attack_env(n, SR, 3.0) * dsp.release_env(n, SR, 3.0)
        place(out, 0.09 * tone * env, start)
    # Low march: a drum-like thump every two beats.
    for k in range(int(C.MUSIC_LOOP_SECONDS / (2 * BEAT))):
        place(out, thump(52.0, 0.16, 0.85 if k % 2 == 0 else 0.6), k * 2 * BEAT)
    return out


STEMS: dict[str, Callable[[], np.ndarray]] = {
    "pad_d": stem_pad,
    "harp_day": stem_harp_day,
    "harp_night": stem_harp_night,
    "flute_day": stem_flute_day,
    "fiddle_inn": stem_fiddle_inn,
    "strings_danger": stem_strings_danger,
}


def render_all(only: str = "") -> None:
    for name, fn in STEMS.items():
        if only and only not in name:
            continue
        x = fn()
        # Remove DC and rumble below hearing/speaker range before measuring loudness.
        x = x - np.mean(x)
        x = dsp.normalise_lufs(x, SR, STEM_LUFS)
        size = dsp.write_ogg(x, SR, C.OUT_ROOT / "music" / f"{name}.ogg")
        print(f"music/{name}.ogg: {len(x) / SR:.1f}s, {size / 1024:.0f} KiB, peak {dsp.peak_db(x):.1f} dB")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    args = ap.parse_args()
    render_all(args.only)


if __name__ == "__main__":
    main()
