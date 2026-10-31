"""Shared DSP helpers for the procedural audio tools (numpy/scipy + ffmpeg for encode/loudness)."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import Callable

import numpy as np
from scipy import signal

FFMPEG = "ffmpeg"
# Ceiling for the pre-encode peak: libvorbis can overshoot the source by a fraction of a dB.
PEAK_CEILING_DB = -1.5
VORBIS_QUALITY = "4"


def db_to_lin(db: float) -> float:
    return 10.0 ** (db / 20.0)


def lin_to_db(x: float) -> float:
    return 20.0 * float(np.log10(max(x, 1e-12)))


def peak_db(x: np.ndarray) -> float:
    return lin_to_db(float(np.max(np.abs(x))))


def exp_decay(n: int, sr: int, tau: float) -> np.ndarray:
    return np.exp(-np.arange(n) / (tau * sr))


def attack_env(n: int, sr: int, attack: float) -> np.ndarray:
    """Raised-sine fade-in over `attack` seconds, then 1; avoids clicks at note starts."""
    env = np.ones(n)
    a = min(n, max(1, int(attack * sr)))
    env[:a] = np.sin(np.linspace(0.0, np.pi / 2, a)) ** 2
    return env


def release_env(n: int, sr: int, release: float) -> np.ndarray:
    env = np.ones(n)
    r = min(n, max(1, int(release * sr)))
    env[n - r:] = np.cos(np.linspace(0.0, np.pi / 2, r)) ** 2
    return env


def sos(x: np.ndarray, kind: str, cutoff: float | tuple[float, float], sr: int, order: int = 4) -> np.ndarray:
    s = signal.butter(order, cutoff, btype=kind, fs=sr, output="sos")
    return signal.sosfilt(s, x)


def fft_shape(white: np.ndarray, sr: int, gain: Callable[[np.ndarray], np.ndarray]) -> np.ndarray:
    """Shape a signal in the frequency domain. The result is exactly periodic over len(white),
    which is how the ambience loops stay seamless without crossfading."""
    spec = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(len(white), 1.0 / sr)
    spec *= gain(np.maximum(freqs, 1.0))
    spec[0] = 0.0
    return np.fft.irfft(spec, len(white))


def add_wrapped(buf: np.ndarray, sig: np.ndarray, start: int) -> None:
    """Add `sig` into `buf` at `start`, wrapping the tail past the end to the start (loops)."""
    n = len(buf)
    idx = (start + np.arange(len(sig))) % n
    np.add.at(buf, idx, sig)


def reverb(x: np.ndarray, sr: int, rt60: float, rng: np.random.Generator, wet: float,
           predelay: float = 0.012, damp_hz: float = 5000.0) -> np.ndarray:
    """Synthetic exponentially-decaying-noise impulse response; darker as it decays."""
    n = int(rt60 * 1.2 * sr)
    t = np.arange(n) / sr
    ir = rng.normal(size=n) * np.exp(-6.9 * t / rt60)
    ir = sos(ir, "lowpass", damp_hz, sr, 2)
    ir[: int(predelay * sr)] = 0.0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    tail = signal.fftconvolve(x, ir)
    dry = np.pad(x, (0, len(tail) - len(x)))
    return (1.0 - wet) * dry + wet * tail


def normalise_peak(x: np.ndarray, target_db: float) -> np.ndarray:
    return x * db_to_lin(target_db) / (np.max(np.abs(x)) + 1e-12)


def measure_lufs(x: np.ndarray, sr: int) -> float:
    """Integrated loudness via ffmpeg's EBU R128 meter (raw float PCM on stdin)."""
    proc = subprocess.run(
        [FFMPEG, "-nostats", "-hide_banner", "-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "-",
         "-af", "ebur128=peak=true", "-f", "null", "-"],
        input=x.astype("<f4").tobytes(), capture_output=True, check=True)
    found = re.findall(r"I:\s+(-?\d+(?:\.\d+)?) LUFS", proc.stderr.decode())
    if not found:
        raise RuntimeError("ebur128 produced no integrated loudness")
    return float(found[-1])


def normalise_lufs(x: np.ndarray, sr: int, target_lufs: float) -> np.ndarray:
    """Scale to the target loudness, but never past the peak ceiling (sparse harp/crackle content
    can hit the ceiling before it reaches the target; it is then just a little quieter)."""
    gain_db = target_lufs - measure_lufs(x, sr)
    y = x * db_to_lin(gain_db)
    if peak_db(y) > PEAK_CEILING_DB:
        y = normalise_peak(y, PEAK_CEILING_DB)
    return y


def write_ogg(x: np.ndarray, sr: int, out: Path) -> int:
    """Encode mono float samples to OGG Vorbis; returns the file size in bytes."""
    out.parent.mkdir(parents=True, exist_ok=True)
    x = np.clip(x, -1.0, 1.0)
    subprocess.run(
        [FFMPEG, "-y", "-nostats", "-hide_banner", "-loglevel", "error",
         "-f", "f32le", "-ar", str(sr), "-ac", "1", "-i", "-",
         "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", VORBIS_QUALITY, str(out)],
        input=x.astype("<f4").tobytes(), check=True)
    return out.stat().st_size
