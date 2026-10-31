"""Single list of every generated audio file, shared by the renderers and the pytest checks."""
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OUT_ROOT = REPO / "game" / "assets" / "audio"

SFX_RATE = 22050
AMBIENCE_RATE = 22050
MUSIC_RATE = 32000

# Music: every stem shares one loop length so the director can run them in lock-step.
# 8 bars of 3 s: 4/4 at 80 BPM (beat 0.75 s) and 6/8 with a 0.5 s eighth both fit exactly.
BAR_SECONDS = 3.0
LOOP_BARS = 8
MUSIC_LOOP_SECONDS = BAR_SECONDS * LOOP_BARS
AMBIENCE_LOOP_SECONDS = 12.0

SURFACES = ("grass", "dirt", "wood", "stone")
FOOTSTEP_VARIANTS = 3

# name -> (kind dir, expected duration seconds or None for one-shots)
AMBIENCE = ("wind", "birds_day", "crickets_night", "rain", "river", "inn_murmur")
MUSIC_STEMS = ("pad_d", "harp_day", "harp_night", "flute_day", "fiddle_inn", "strings_danger")
ONE_SHOTS = ("door", "rider_screech")
HEARTBEAT_SECONDS = 1.0


def all_files() -> dict[str, Path]:
    """Relative id (e.g. 'sfx/door.ogg') -> absolute path."""
    out: dict[str, Path] = {}
    for s in SURFACES:
        for i in range(1, FOOTSTEP_VARIANTS + 1):
            out[f"sfx/footstep_{s}_{i}.ogg"] = OUT_ROOT / "sfx" / f"footstep_{s}_{i}.ogg"
    for n in (*ONE_SHOTS, "heartbeat"):
        out[f"sfx/{n}.ogg"] = OUT_ROOT / "sfx" / f"{n}.ogg"
    for n in AMBIENCE:
        out[f"ambience/{n}.ogg"] = OUT_ROOT / "ambience" / f"{n}.ogg"
    for n in MUSIC_STEMS:
        out[f"music/{n}.ogg"] = OUT_ROOT / "music" / f"{n}.ogg"
    return out
