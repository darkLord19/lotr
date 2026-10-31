"""Checks on the rendered audio: files present and documented, loop lengths, peaks, size budget."""
from __future__ import annotations

import re
import subprocess

import pytest

import catalog as C

LENGTH_TOLERANCE_S = 0.1
SIZE_BUDGET_BYTES = 25 * 1024 * 1024
MANIFEST = C.REPO / "assets_src" / "MANIFEST.md"
FILES = C.all_files()


def _duration(path) -> float:
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True, check=True).stdout
    return float(out.strip())


def _max_volume_db(path) -> float:
    err = subprocess.run(["ffmpeg", "-nostats", "-i", str(path), "-af", "volumedetect", "-f", "null", "-"],
                         capture_output=True, text=True, check=True).stderr
    m = re.search(r"max_volume:\s*(-?\d+(?:\.\d+)?) dB", err)
    assert m, err[-300:]
    return float(m.group(1))


@pytest.mark.parametrize("rel", sorted(FILES))
def test_file_present_and_documented(rel: str) -> None:
    assert FILES[rel].is_file(), f"missing {rel}; run tools/audio/synth_sfx.py and compose.py"
    assert FILES[rel].read_bytes()[:4] == b"OggS"
    assert rel in MANIFEST.read_text(), f"{rel} has no entry in assets_src/MANIFEST.md"


@pytest.mark.parametrize("rel", sorted(FILES))
def test_peak_below_zero_dbfs(rel: str) -> None:
    peak = _max_volume_db(FILES[rel])
    assert peak < 0.0, f"{rel} clips: max_volume {peak} dB"


def test_music_stems_share_one_loop_length() -> None:
    lengths = {n: _duration(FILES[f"music/{n}.ogg"]) for n in C.MUSIC_STEMS}
    for n, d in lengths.items():
        assert abs(d - C.MUSIC_LOOP_SECONDS) < LENGTH_TOLERANCE_S, (n, d)


def test_ambience_loops_share_one_length() -> None:
    for n in C.AMBIENCE:
        d = _duration(FILES[f"ambience/{n}.ogg"])
        assert abs(d - C.AMBIENCE_LOOP_SECONDS) < LENGTH_TOLERANCE_S, (n, d)


def test_heartbeat_is_one_second_loop() -> None:
    assert abs(_duration(FILES["sfx/heartbeat.ogg"]) - C.HEARTBEAT_SECONDS) < LENGTH_TOLERANCE_S


def test_total_size_within_budget() -> None:
    total = sum(p.stat().st_size for p in FILES.values())
    assert total < SIZE_BUDGET_BYTES, total


def test_config_references_existing_files() -> None:
    import json
    cfg = json.loads((C.REPO / "game" / "config" / "audio.json").read_text())["audio"]
    for name in cfg["music"]["stems"].values():
        assert (C.OUT_ROOT / "music" / name).is_file(), name
    for name in cfg["ambience"]["files"].values():
        assert (C.OUT_ROOT / "ambience" / name).is_file(), name
    assert (C.REPO / "game" / cfg["ambience"]["heartbeat_file"].removeprefix("res://")).is_file()
