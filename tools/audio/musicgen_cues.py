#!/usr/bin/env python3
"""Generates whole-cue music with MusicGen-small (transformers, Apple GPU) into game/assets/audio/music/cues/.
Each cue is 30 s, loudness-normalised to -16 LUFS, OGG. Run with .venv-music:
  .venv-music/bin/python tools/audio/musicgen_cues.py [name ...]
Cues are NOT yet referenced by config/audio.json: the director plays phase-locked stems, a whole-cue
player path still has to be added. Licence note: MusicGen weights are CC-BY-NC 4.0 (fine for this personal-use game only).
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game/assets/audio/music/cues"
SECONDS = 30
TOKENS_PER_SECOND = 50
CUES = {
    "shire_morning": "gentle pastoral folk, tin whistle and acoustic guitar, bright, peaceful countryside morning, warm, no drums",
    "shire_day": "cheerful pastoral folk melody, wooden flute, fiddle and light hand drum, relaxed, sunny village",
    "road_travel": "steady walking tempo folk, soft strings and flute, hopeful journey, gentle wandering, no drums",
    "bree_evening": "warm medieval tavern folk, lute and low whistle, cosy evening, mellow",
    "tavern_jig": "lively fiddle jig, bodhran and tin whistle, folk dance, tavern, upbeat",
    "night_lullaby": "soft harp lullaby, slow, quiet starlit night, tender, minimal, sparse",
    "tension_low": "tense low strings, slow ominous drone, creeping unease, sparse, dark, no melody",
    "rider_dread": "dread, deep cello and double bass tremolo, cold dissonant drones, menacing, sustained, cinematic horror",
    "rain_melancholy": "melancholic solo cello and soft piano, rainy grey day, slow, wistful",
    "dusk_reflective": "slow reflective acoustic guitar and flute, golden dusk, bittersweet, calm",
}


def main() -> int:
    import scipy.io.wavfile as wav
    import soundfile as sf
    import torch
    from transformers import AutoProcessor, MusicgenForConditionalGeneration

    names = sys.argv[1:] or list(CUES)
    OUT.mkdir(parents=True, exist_ok=True)
    dev = "mps" if torch.backends.mps.is_available() else "cpu"
    proc = AutoProcessor.from_pretrained("facebook/musicgen-small")
    model = MusicgenForConditionalGeneration.from_pretrained("facebook/musicgen-small").to(dev)
    for name in names:
        torch.manual_seed(1000 + list(CUES).index(name))
        inp = proc(text=[CUES[name]], padding=True, return_tensors="pt").to(dev)
        audio = model.generate(**inp, do_sample=True, guidance_scale=3, max_new_tokens=SECONDS * TOKENS_PER_SECOND)
        with tempfile.TemporaryDirectory() as td:
            raw = Path(td) / f"{name}.wav"
            wav.write(raw, model.config.audio_encoder.sampling_rate, audio[0, 0].cpu().numpy())
            norm = Path(td) / f"{name}_norm.wav"
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(raw), "-af", "loudnorm=I=-16:TP=-1.5:LRA=11",
                            "-ar", "44100", str(norm)], check=True)
            dest = OUT / f"{name}.ogg"
            data, sr = sf.read(norm)  # Homebrew's ffmpeg has no libvorbis encoder; libsndfile writes the OGG
            sf.write(dest, data, sr, format="OGG", subtype="VORBIS")
        print("wrote", dest, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
