# Work left for the local (Mac) session

Everything here could not be done in the cloud container (Linux, no GPU, no display, restricted network).
Each entry names the plan task and what to run. Keep this list current as tasks are finished or deferred.

## M0-T09 live LLM checks (needs OPENROUTER_API_KEY, unblocked network)
1. `.venv/bin/python tools/llm/list_models.py`, pick newest Opus-class (key_figure) and Sonnet-class (standard, summariser) slugs, write to `game/config/llm.json`.
2. `LIVE_LLM=1 tools/test.sh` -> the PONG test must pass; record the latency in PROGRESS.md.
3. Confirm `cache_control` part format and `usage: {include: true}` against current OpenRouter docs; HTTPSSETransport has never hit a real server.

## M0-T10 live dialogue probes (needs OPENROUTER_API_KEY)
Run with LIVE_LLM=1 and save outputs to `docs/reports/m0_dialogue.md` (see PLAN M0-T10 Verify):
1. `tools/talk.sh --npc=barliman_butterbur --date=3018-09-29T21:00 --say="Good evening! Any news?"` (Butterbur voice, 3-4 options)
2. same NPC on `--date=3018-09-20`: must NOT know about riders (date filter)
3. `--say` x2 then re-run with `--keep-memory`: memory summary persists; also exercise offline fallback by unsetting the key.
Also M1-T13 live probes (Gaffer 09-24, Butterbur 09-20, Maggot rumour, Strider 09-29, Gandalf).

## M1-T03 Terrain3D (deferred)
Terrain3D release binaries are not downloadable in the cloud container (GitHub release assets blocked) and building it from source was not done here. The cloud session used the PLAN §8 fallback: chunked MeshInstance3D terrain generated from the heightmap (`world/terrain_chunks.gd`). On the Mac: download the Terrain3D release matching your Godot into `game/addons/terrain_3d`, enable it, and import `build/terrain/*` (regenerate with `tools/terrain/build_heightmap.py`) if you prefer it over the fallback.

## Scene/UI follow-ups from logic-only tasks
- M1-T11: scene test (player 10 m off-road crouched in bushes vs on road), vegetation concealment volumes, HUD eye icon, rider screech/heartbeat audio hooks. The scene layer supplies has_line_of_sight, road_distance_m and concealment to RiderPerception.
- M1-T12: Tab inventory UI, trading UI, HUD (hunger, fatigue, eye, date) capture; `place_world.py` must emit forage nodes ({id,item,pos,yield,zone}); wire `Skills.prompt_lines()` into prompt_builder; controller must call Survival.add_exertion and keep a ref to Survival (call detach() on discard).
- Rumour network must resolve the `{player}` placeholder in rumour `player_found_senseless` from flag `rumour_subject.player_found_senseless`.

## M1-T10 scene work still to do
Register OffscreenSim as an autoload (bind(WorldClock, WorldState, Timeline, graph), load_tracks() after content), npc_body spawner (600 m spawn / 700 m despawn, NavigationAgent3D; use set_body_driven/report_body_progress), terrain height for y, villager spawner + villager definitions content, wire OffscreenSim.serialise/deserialise into SaveSystem, capture to docs/reports/m1_sim/ (--date=3018-09-24T16:00 at the riders' road).

## M1-T13 remaining (needs Mac/GPU/key)
1. Portraits via mflux (FLUX schnell is gated and there is no HF account, so use ungated `mflux-generate-z-image-turbo`; install mflux into `.venv-art`, Python 3.12, because sentencepiece does not build on 3.15): `pip install mflux` into .venv (check disk, `df -h`, >= 30 GB must remain; use `-q 4` if tight), write tools/art/style.txt + tools/art/portraits.py (one per named NPC, 6 per villager template, 768x768 fixed seeds -> game/assets/portraits/<id>.png; Black Rider = hood with darkness, no face). Contact sheet check; max 3 retries per failure. Also journal/inventory UI textures, parchment, illustrated map.
2. Live dialogue probes -> docs/reports/m1_dialogue.md (Gaffer 09-24, Butterbur 09-20, Maggot/Mrs Maggot rumour, Strider 09-29, Gandalf).
3. World scene must instantiate RumourNetwork, DialoguePanel and Journal (not autoloads yet).

## Git LFS note
The cloud sandbox cannot reach the Git LFS server, so `game/assets/terrain/**` is exempted from LFS in `.gitattributes` (small files committed as plain objects). Any further generated assets committed from the cloud (models, portraits) need the same treatment or must be generated on the Mac. When ready, remove that line and run `git lfs migrate import --include="game/assets/**"`.

## M1-T14 remaining
Benchmarks are done and pass (see above), so profiling/occlusion/impostors are optional polish. Still open: quality presets in config/game.json, lanterns/inn window glow at night, river mist volumes (WeatherModel.river_mist), wire WeatherDayNight.serialise into SaveSystem and its concealment/fear multipliers into RiderPerception callers. Re-run final daynight captures at 2560x1440.

## M1-T15 Audio (cloud used procedural fallback)
The cloud sandbox cannot download CC0 packs (Kenney, freesound) or MusicGen weights, so every sound is synthesised
(`tools/audio/synth_sfx.py`, `tools/audio/compose.py`; outputs in `game/assets/audio/{sfx,music,ambience}`, plain git
objects because the sandbox cannot reach LFS; `.gitattributes` already exempts `game/assets/**`). To finish on the Mac:
1. Listen to everything (nothing was auditioned; there is no audio device in the cloud). Retune synth constants or swap in real CC0 recordings
   for footsteps, birds, river, door and crowd murmur (record source + licence of each in `assets_src/MANIFEST.md`; keep the filenames or edit `config/audio.json`).
2. MusicGen (MLX, `small` if disk is tight): generate 8-12 cues (pastoral folk flute/harp, tense low strings, tavern fiddle jig, night lullaby, ...) at 30 s,
   trim to loops, loudnorm to -16 LUFS, OGG into `game/assets/audio/music/`, then add them as new cues/stems in `config/audio.json` (`music.cues`) — the director is data driven.
   The current stems are 24 s phase-locked loops of one shared length; whole-cue MusicGen files would need a second player path (or be cut into the same length).
3. Record the 60 s gameplay audio check: `godot --write-movie build/m1_audio.avi` along `walk_hobbiton_to_bree`, then
   `ffmpeg -i build/m1_audio.avi -af volumedetect -f null -` (max_volume < 0 dB) and copy to `docs/reports/m1_audio/`. Skipped in the cloud (no audio device).
4. Scene wiring (world/ was off limits): add `Ambience` and `MusicDirector` nodes to the world scene; call `set_location` (settlement/field/river/forest_edge/inn_interior)
   and `set_weather(state, rain_intensity)` from `WeatherModel.Snapshot`; call `MusicDirector.set_place(region, settlement, area, in_inn)`, `set_weather`, and each frame
   `report_rider(distance, RiderAI.State, RiderPerception.EyeState)` / `clear_rider()` for the nearest rider; forward `MusicLogic` threat to `Ambience.set_threat` (3 = heartbeat).
   Footstep/door/screech one-shots are not yet played by anything (player controller / door / rider nodes should pick `sfx/footstep_<surface>_<1-3>.ogg`).
   Create Music/Ambience audio buses if wanted (currently Master with a per-class dB offset in `config/audio.json` `bus_db`).
5. Verify on the Mac that `AudioStreamSynchronized` stems stay loop-aligned and that the OGG loops are gap-free (Vorbis encoder padding).

## Benchmarks (DONE on the Mac, 2026-10-31)
`tools/bench.sh flyover_full|walk_hobbiton_to_bree|night_rain_bree` all pass with large headroom (results in PROGRESS.md, CSVs in docs/reports/m1_bench/). Re-run after NPC bodies / riders / HUD / lanterns land (BENCH_UNCAPPED=1 shows headroom over the 120 Hz cap). `--max-seconds=30` gives a quick smoke run.

## Mac setup status (2026-10-31)
Done: Godot 4.7.2 + Blender 5.2.3 installed, tools/bin symlinks, `.venv` populated, `godot --headless --path game --import` run, `tools/verify.sh` passes except the place_world sync pytest (platform float differences, see REVIEW.md "Local (Mac) session"). Still no OPENROUTER_API_KEY in the environment, so the live LLM items above are blocked until it is exported. Free disk is ~47 GB, so mflux/MusicGen need the `-q 4` / `small` options to keep 30 GB free.

## Recommended order for the local (Mac) session
1. `brew install --cask godot blender`; symlink into tools/bin; `.venv` + `pip install -r tools/requirements.txt`; run `tools/verify.sh` (should pass; the Python terrain tests and Blender build need the venv/Blender).
2. Regenerate terrain data: `.venv/bin/python tools/terrain/build_heightmap.py && .venv/bin/python tools/terrain/export_engine_terrain.py` (committed engine copy already exists).
3. OPENROUTER_API_KEY live work (M0-T09/T10, M1-T13 probes). 4. Run the game windowed: `godot --path game`; judge captures/look; run benchmarks (write tools/bench.sh + bench_runner.gd) and tune population/quality.
5. mflux portraits, MusicGen cues, CC0 audio; optional Terrain3D and Quaternius swap-in; NPC body spawner, rider scene, HUD/trading UI; write docs/plans/M2.md and start M2.
