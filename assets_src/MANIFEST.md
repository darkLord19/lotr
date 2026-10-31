# Asset sources manifest

## Audio (M1-T15) — procedurally generated, no third-party material
All files below are synthesised by `tools/audio/synth_sfx.py` and `tools/audio/compose.py` (numpy/scipy,
encoded with ffmpeg libvorbis) with fixed seeds; re-running reproduces them. No samples, packs or AI models
were used, so there is nothing to attribute: licence **CC0 / own work**. Internet CC0 packs and MusicGen were
unreachable from the cloud sandbox; see `docs/LOCAL_TODO.md` for what to add on the Mac.
Checked by `tools/audio/test_audio_assets.py` (each path below must appear here).

| File | Source / tool | Origin | Licence |
|---|---|---|---|
| `game/assets/audio/ambience/birds_day.ogg` | synth_sfx.py (noise/additive synthesis, 12 s seamless loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/ambience/crickets_night.ogg` | synth_sfx.py (noise/additive synthesis, 12 s seamless loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/ambience/inn_murmur.ogg` | synth_sfx.py (noise/additive synthesis, 12 s seamless loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/ambience/rain.ogg` | synth_sfx.py (noise/additive synthesis, 12 s seamless loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/ambience/river.ogg` | synth_sfx.py (noise/additive synthesis, 12 s seamless loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/ambience/wind.ogg` | synth_sfx.py (noise/additive synthesis, 12 s seamless loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/music/fiddle_inn.ogg` | compose.py (additive/FM instrument stem, 24 s loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/music/flute_day.ogg` | compose.py (additive/FM instrument stem, 24 s loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/music/harp_day.ogg` | compose.py (additive/FM instrument stem, 24 s loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/music/harp_night.ogg` | compose.py (additive/FM instrument stem, 24 s loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/music/pad_d.ogg` | compose.py (additive/FM instrument stem, 24 s loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/music/strings_danger.ogg` | compose.py (additive/FM instrument stem, 24 s loop) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/door.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_dirt_1.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_dirt_2.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_dirt_3.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_grass_1.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_grass_2.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_grass_3.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_stone_1.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_stone_2.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_stone_3.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_wood_1.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_wood_2.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/footstep_wood_3.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/heartbeat.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/sfx/rider_screech.ogg` | synth_sfx.py (numpy synthesis) | generated in-repo, seeded | CC0 / own work |
| `game/assets/audio/music/cues/bree_evening.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
| `game/assets/audio/music/cues/dusk_reflective.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
| `game/assets/audio/music/cues/night_lullaby.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
| `game/assets/audio/music/cues/rain_melancholy.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
| `game/assets/audio/music/cues/rider_dread.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
| `game/assets/audio/music/cues/road_travel.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
| `game/assets/audio/music/cues/shire_day.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
| `game/assets/audio/music/cues/shire_morning.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
| `game/assets/audio/music/cues/tavern_jig.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
| `game/assets/audio/music/cues/tension_low.ogg` | tools/audio/musicgen_cues.py (MusicGen-small, facebook/musicgen-small, seeded) | generated locally, 30 s, -16 LUFS target | MusicGen weights are CC-BY-NC 4.0: personal use only |
