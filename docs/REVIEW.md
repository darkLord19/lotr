# Review log

## Review items
(📝 things for the user to judge)

## Needs user action
- **Environment:** This work was done in a Linux x86_64 cloud container (no GPU, no macOS). Everything needing the M5 Mac, a GPU,
  a window, or large model weights is listed in `docs/LOCAL_TODO.md`.
- `OPENROUTER_API_KEY` was not available and `openrouter.ai` is blocked from the container: live LLM probes are DEFERRED.

## Deferred / fallbacks used
- **M0-T03:** PLAN says autoload stubs get `class_name`; Godot rejects a class_name equal to an autoload name, so autoloads have none and are referenced by their autoload name. Helper classes (GameDate etc.) do use class_name.
- **M0-T09:** `OPENROUTER_API_KEY` missing and openrouter.ai unreachable, so `game/config/llm.json` still holds the PLACEHOLDER slugs (`anthropic/claude-opus-4.5`, `anthropic/claude-sonnet-4.5`). On the Mac: run `.venv/bin/python tools/llm/list_models.py`, re-pick the newest Opus-/Sonnet-class slugs, then run the live probe `LIVE_LLM=1 tools/test.sh` (test_live_pong) and record latency in PROGRESS.md. Also confirm OpenRouter's current `cache_control` part format. Only mock tests were run.
- **M0-T05 calendar leap day:** Feb 29 (3020) is shown as 'Overlithe' and later days shift by one; canon places Overlithe after Midyear's Day. Only affects T.A. 3020. Cheap to fix in calendar.json + validate.shire_date.
- **M0-T05 rumour schema:** plan gave no rumour format; invented `id,text,origin_poi,start,strength,max_hops,hours_per_hop`.
- **M1-T01 canon concern (Gandalf):** PLAN §5 has Gandalf visiting the Gaffer on Sept 29, Crickhollow Sept 30 and leaving Bree Oct 1. Per my recollection of Appendix B (Tale of Years) he is Saruman's prisoner at Orthanc from ~Sept 18 until Oct 3 (and in the book he never appears in the Shire/Bree in this window). Followed the plan as instructed; his cards/events are marked `verify: true`. Suggest checking Appendix B and probably removing or reframing his appearance (e.g. a letter or rumour only).
- **M1-T01 verify markers:** the schema forbids `verify` on a single knowledge entry, so uncertain facts carry a trailing " [verify]" in the fact text plus `verify: true` on the whole card.

## M1-T01 timeline content (events, itineraries, rumours)
- Canon concern: Appendix B has Gandalf imprisoned in Orthanc from Sept 18 until his escape on Oct 3, which conflicts with the PLAN canon note (Gaffer Sept 29, Crickhollow Sept 30, Bree Oct 1). Followed the plan; every Gandalf step/event is `verify: true`. Cheap fix: delete `gandalf.json` itinerary and the `gandalf_visits_gaffer` event.
- Dwarves rumour: plan says "going east"; the book (FotR I.2) may say west. `dwarves_going_east` is `verify: true`.
- No west-edge POI exists for Gildor's company to leave the map; they walk to `woody_end_camp` and stay (`gildor_moves_on`, verify).
- Mode B: the party idles at `bree_west_gate` (step `frodo_at_bree_west_gate`) until `party_arrives_pony` fires; riders and Bill Ferny steps in Bree depend on it.
- **M0-T10:** `godot -s` SceneTree scripts can't see autoloads, so `tools/talk.sh` runs `res://tools/talk_cli.tscn` instead of a -s script. `WorldState.reset()` does not clear `poi_info` (tests must clear it). Knowledge granted by a timeline add_knowledge effect counts as visible regardless of known_from.

## M1-T10 off-screen sim (logic; scene work pending)
- **Speeds are in compressed-map metres per game minute** (`game/config/sim.json`: walk max 12 / run 24, ride 30 / 45). Canon itinerary times on the ~1:25 map imply 0.2-22 m/min; the fastest legs (riders Stock -> Crickhollow 22.6 m/min, Khamul Three-Farthing -> Bagshot Row 14.7) fit the ride cap. A 3D body following the abstract path will look very slow for most legs (e.g. Khamul: 0.64 m/min over 3 days); the spawner should not use these numbers as body walk speed.
- **Abstract origins**: `bombadil_house` is off-graph, so the party "emerges" at the nearest routable POI (`old_forest_edge`) when `frodo_leaves_bombadil` fires and walks the road to the West-gate. Alternative: keep them hidden and let the Timeline place them at the gate.
- **Mode-B hold** is parked at `bree_waiting_point` by the sim (config `sim.hold_points`), not by the content: the itinerary has the party idle at `bree_west_gate`; the sim stops them one node earlier while `party_arrives_pony` would wait for the player.
- **Timeline guard**: an event with a `move_entity` effect cannot fire while its target is on the road (any mode). A character mid-leg for an unrelated trip would block such an event until it arrives.
- Real game starts 09-22 08:00 but itineraries start 09-20: the Timeline fires those 09-20 `stay` steps with a 2-day "delay" on the first minute. Nothing depends on them today, but a `depends_on` on one would shift by 2 days.

## M1-T03 terrain (engine side)
- **World coordinates = region coordinates** (x east, z SOUTH, origin at the NW corner; z=0 is the north edge). This deviates from PLAN §3.5 ("-Z = north"). A mirror would flip the map's chirality and every authored position (POIs, `road_graph`, itineraries). Consequence: a camera with yaw 0 looks north (-Z); east is yaw -90. `StyleMaterials.sun_direction()` uses compass azimuths accordingly.
- **Terrain3D not used** (binary not downloadable here): chunked `MeshInstance3D` terrain per PLAN §8. `world/terrain_chunks.gd` streams 256 m chunks within `world.terrain.view_radius_m` (2.5 km) of the focus with 5 LODs (4/8/16/32/64 m vertex spacing; the plan's "8 m near" was refined to 4 m for the nearest ring because 14 m wide rivers and 8 m roads vanish at 8 m spacing), skirts hide cracks, `HeightMapShape3D` bodies only within 128 m. Swap in Terrain3D later by replacing `TerrainChunks`; `height_at()` is the only API other code uses.
- **Engine terrain data** is a 4 m decimation committed under `game/assets/terrain/eriador_west/` (Git LFS). Regenerate: `.venv/bin/python tools/terrain/build_heightmap.py && .venv/bin/python tools/terrain/export_engine_terrain.py`. `splat_4m.png` packs R path, G riverbank, B forest floor, A field (grass = remainder); rock is derived from slope in the shader. `splat_4m.png.import` sets `fix_alpha_border=false` (otherwise Godot wipes RGB where alpha is 0): do not let an editor re-import reset it.
- `height_4m.r16` is read with `FileAccess` from `res://`; an exported build must include `*.r16` in the export filter (Export > Resources > filters).
- `Config` now also loads `terrain.json` (top-level keys such as `seed`, `roads`, `rivers`, `hills` are merged flat into the config namespace; no collisions today but generic names), `world.json` (engine terrain/water/camera tunables) and `style.json` (all look parameters).
- Water surface = channel bed (at the river polyline) + 0.6 * depth, smoothed along the river; depth rule shared with `tools/terrain/heightfield.py`.
- The Capture autoload gained `--preset=<name>` (`game/config/capture_presets.json`; `tools/capture.sh - out.png --preset=x`) and calls `capture_prepare()` on the current scene if it has one, so streaming scenes are fully built before the shot.
- **📝 M1-T04 art style (terrain):** look at docs/reports/m1_terrain/capture_*.png. Terrain reads flat with little relief shading; Shire vs Bree palette difference is subtle; distant ridges look flat-topped (data vs 2.5 km streaming cut not verified); small white slab at the river's south end. Cheap to change: all parameters in game/config/style.json and game/config/terrain.json (relief amplitude, ridge shape), no code changes needed.

## M1-T15 audio
- **📝 REVIEW ITEM (listen):** all audio is procedural, never auditioned (no audio device in the cloud). Render with `.venv/bin/python tools/audio/synth_sfx.py && .venv/bin/python tools/audio/compose.py` (files in `game/assets/audio/`; `ffplay` any OGG). Weakest guesses: bird chirps, inn murmur (formant babble), door creak, rider screech. Music: D mixolydian pastoral (flute+harp+pad), G mixolydian 6/8 jig for inns, D phrygian low strings for danger. Cheap to change: constants at the top of each generator, cue mixes and thresholds in `game/config/audio.json`.
- Design: music stems are one 24 s loop length played inside an `AudioStreamSynchronized`, so cue changes are volume crossfades. Rider proximity (<= 60 m) or SNIFF/SEEN -> danger cue; APPROACH/INTERROGATE/SNIFFED -> chase cue; danger holds 8 s after the rider lets go. Loudness: stems ~ -19 LUFS each (two or three summed ~ -16), ambience -28..-34 LUFS.
- PLAN asks for MusicGen cues and CC0 packs plus a `--write-movie` recording; skipped here (see `docs/LOCAL_TODO.md`).
- Observed once (passed on re-run, so intermittent): `tests/unit/flow/test_save_game_flow.gd` failed on a Black Rider track `leg/s` difference (1476.6 vs 1476.0) — not from audio work (menus/save area).

## M1-T16 menus and save integration
- Saves use full-precision JSON; JSON loses int/float distinction, so state is compared canonically (numbers by value). Some ints (flags, entity data) come back as floats; code reads them via int()/float().
- project run/main_scene stays boot.tscn; boot.gd opens world/main.tscn only when not headless and no --scene/--capture/--preset args.
- Main adds WeatherDayNight on top of world_root's Sun/WorldEnvironment (untested visually; 3D capture too slow under software rendering). A new game keeps WeatherModel default seed 3018.
- No player body exists yet (M1-T08): player transform is the WorldState entity (pos + data.yaw); bodies should write it on SaveSystem.about_to_save and read it on SaveSystem.loaded.
- Char creation's time-mode default does not follow Settings yet.
