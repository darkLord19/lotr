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

## M1-T05 Blender asset library
- Generators: `tools/blender/{lib,gen}`; build `.venv/bin/python tools/blender/build_all.py` (~6 s, parallel Blender per category), previews `.venv/bin/python tools/blender/preview.py --final` (needs xvfb; ~6 min with software GL), budgets `.venv/bin/python tools/blender/check_budget.py` (in verify.sh). Sheets: `docs/reports/m1_style/*.png`, lineup `asset_lineup.png`.
- LODs are separate files (`<name>_lod1.glb` 40%, `_lod2.glb` 15%) rather than child nodes; collision is `<name>_col-convcolonly`/`-colonly` child nodes. Each category has `manifest.json` (kinds, tris, sizes) used by the budget check and lineup scene.
- Apt Blender has no numpy (glTF exporter needs it): `tools/blender/runner.py` pip-installs a cp312 wheel into `build/blender_pylib`. Not needed on the Mac.
- Nature assets use the Shire palette only (no Bree-tinted variants); tint in the terrain/material shader by region if wanted. Colours come from style.json ramps + role defaults in `lib/style.py` (style.json may override via `style.assets.<region>.<role>`).
- Cheap to change: edit palette/role defaults and re-run build_all. Props are drawn ~2.5x in the lineup scene only.

## M1-T08 player controller
- Walk 1.8 m/s, run 4.0, crouch 0.9 (config/player.json): chosen so 3 s of W gives 3-6 m per plan; feels slow at 1:25 map scale. Cheap to change. Speed is not scaled by race (hobbit is only visually 0.6).
- Placeholder body = capsule + head + nose block; real characters in M1-T07. Crouch has no overhead check (can stand up inside a low ceiling).
- Esc: PauseMenu still reads `ui_cancel`; controls.json rebinds `ui_cancel` itself. Journal now reads the `journal` action (KEY_J fallback before InputSetup runs).
- Player position sync clears the entity's POI (move_entity with Vector3), every 0.5 s when moved >=0.75 m and on about_to_save.
- Debug console `speed <x>` scales the world clock (WorldClock.time_scale), not the player.
- Capture: docs/reports/m1_player/player_behind_bag_end.png (hobbit from behind at Bag End; software render takes ~2.5 min).

## M1-T07 characters (procedural fallback)
- **📝 REVIEW ITEM:** docs/reports/m1_characters/contact_sheet.png (T-pose + walk frame 10, every NPC) and lineup.png (Godot, idle). Rebuild: `.venv/bin/python tools/blender/characters/build_bases.py` (~1.5 min incl. xvfb sheet; `--no-sheet` for glbs only). Looks are data: `tools/blender/characters/looks.json` (colours, hair, hats, pieces), proportions `races.json`; cheap to change.
- Quaternius packs were not downloadable, so bodies, clothes and animations are procedural (PLAN §8 fallback). Look is blocky low-poly: faces are dark box eyes, no fingers, rigid-ish skin on cloaks/skirts (walk shows some stretching on breeches/skirts). A later Quaternius swap re-runs build_bases.py.
- Hobbits are modelled at true size (1.08 m) with the same skeleton rather than a scaled rig; the player hook therefore skips the capsule-visual scaling when a glb is used. Foot sliding is controlled by a time scale from per-race natural speeds (hobbit walk cycle is ~2x sped up at the player's 1.8 m/s).
- Animation names use snake_case (`talk_gesture`, `crouch_walk`, `pick_up`, `faint` = fall/faint). sit/sleep/faint are non-looping holds (last pose stays until `release_hold()`); no sit-transition onto actual furniture, no staff for Gandalf, no mounted riders (horses: IDEAS.md).
- Villager glbs are one base per template; per-spawn variety is colour only (`NPCBody.roll_look`), plus hair style is fixed per base.
- NPCBody reads `res://config/characters.json` directly (not through Config) to avoid touching the shared CONFIG_FILES list while other tasks edit it.
- `tools/verify.sh` currently fails `validate.py`/pytest content tests because `game/content/regions/eriador_west_placements.json` (M1-T06 world population, other agent) lacks the region schema fields; unrelated to characters.

## M1-T06 world population (+ M1-T04 set dressing)
- **📝 REVIEW ITEM (look):** docs/reports/m1_style/{bag_end_close,hobbiton_overview,bree_gate,prancing_pony_yard}.png (2560x1440, software render). Bag End reads as a round-door hole dug into the Hill; Bree reads dark timber/slate vs the Shire's green. Weak: the open Shire is sparse (trees every ~60 m, small buildings from the overview), the terrain's stair-stepped slope shading is visible near the camera (terrain, not placement), Bree West-gate sits in a road cutting so it is hard to frame. Only 4 captures taken (each ~40 s): brandywine_bridge/east_road/bree_hill presets were not re-shot with population.
- Generator: `.venv/bin/python tools/terrain/place_world.py --stats` (~20 s, deterministic; pytest checks the committed JSON equals a fresh run). Tunables are constants at the top of place_world.py (spacings, tolerances, RECIPES per settlement) and `game/config/population.json` (radii, LOD ranges, budgets).
- **Navigation decision:** no NavigationMesh. NPC bodies follow RoadGraph polylines (sim/road_graph.gd) snapped to terrain height; roads are kept clear of trees/buildings by the generator. Reason in cell_streamer.gd header. Revisit if NPCs must path inside settlements.
- **Interiors do not exist** (house models are solid shells), so beds and inn food are Interactables placed outside next to the door/table (bed 1.8 m beside the door). Food is free (payload item/count only; no price yet).
- Berries are not an item; forage uses mushrooms, apple (garden plots), potatoes. Maggot's fields: mushrooms+potatoes flagged `maggots_fields`.
- Foliage LOD uses Godot visibility ranges, measured to each MultiMesh's AABB centre, so ranges are wide and overlap (population.json `foliage.tier_ranges_m`); popping/over-detail at cell borders must be judged on the Mac. LOD tiers are created lazily per cell (resident MultiMeshes ~ drawn ones).
- Budget (counter based, no renderer): worst focus over a 256 m grid = 11.3k resident foliage instances, ~1.6M estimated foliage triangles, ~1160 MultiMeshes, 127 objects (Old Forest, 6528,3200). Budgets in population.json were set with headroom over these measurements. **Real fps/memory benchmark (`tools/bench.sh flyover_full`) is deferred to the Mac** (LOCAL_TODO).
- Dubious: Old Forest wall is unbroken, so tom_path dead-ends into it (and the sim's "party emerges at old_forest_edge" is on the wrong side of a solid wall for a 3D body); the Barrow-downs are `enterable:false` hills but have no barrier; Brandy Hall is hobbit_hole_3 scaled x1.9; Floating Log reuses the Green Dragon model; the Pony faces the Bree South road, not the East Road; ferry raft and bridges are scaled to fit, bridge colliders are pre-scaled; foliage on far terrain LODs (16-64 m vertex spacing) may float/sink slightly.
- Far-LOD terrain vs placement height: placements snap to the 4 m engine heights; terrain LOD0 matches, coarser rings do not.

- **📝 M1-T17 playtest checklist (for you):** see docs/reports/m1_acceptance.md (Bucklander reaches Bree before 09-29 and meets Strider; Breelander in mode B who never goes west makes the party wait; save/load).
- **📝 M1-T06 captures:** docs/reports/m1_style/{bag_end_close,hobbiton_overview,bree_gate,prancing_pony_yard}.png. Bree reads well (timber, lit windows); Bag End's hobbit-hole is dark and hard to pick out; open Shire is sparse; terrain shows stair-stepped shading near the camera.

## Local (Mac) session
- **place_world is not bit-reproducible across platforms.** `pytest tools/terrain/test_place_world.py::test_deterministic_and_in_sync_with_committed_file` fails on the Mac: libm differences in `cos/sin` change the Poisson-disk sampling and the trees diverge (25,491 vs 25,523 foliage, 370 vs 371 objects). The committed JSON (generated in the Linux container) is the canonical world; I did not regenerate it. Regenerating on the Mac would be fine visually but changes the placements every cloud/other-OS run is compared against. Options: (a) regenerate on the Mac and treat the Mac as canonical from now on, (b) make the sync test compare stats/tolerances instead of bytes. Left open.
- `build_heightmap.py` is stable across platforms to within 5 mm (max 0.0049 m vs the committed engine copy), so I reverted the regenerated terrain files and reports.
- A fresh clone has no `game/.godot` class cache: `tools/test.sh` fails with "Identifier GameDate not declared" until `godot --headless --path game --import` has run once. Run that after cloning.
- Mac toolchain: Godot 4.7.2 and Blender 5.2.3 via `brew install --cask`; symlinks in `tools/bin`; `.venv` from Homebrew Python 3.15 (all tools/ tests pass on it).

- **📝 REVIEW ITEM (look): portraits** docs/reports/m1_portraits/contact_sheet.png. Consistent gouache storybook style. Weak spots: Gildor reads feminine; Mrs Maggot and Nob are very similar plain faces; Frodo looks young (canon: 50 but unageing). Regenerate any one with `.venv-art/bin/python tools/art/portraits.py --retry <id>` after editing tools/art/looks.json.
- FLUX.1-schnell is gated on Hugging Face and the owner has no account, so the ungated Z-Image-Turbo is used (Apache-2.0, 6B).

## Cloud session (Audio, World & UI Integration, Traversal & Atmosphere Fixes)
- **Spawn Origin Fix**: In `Main._build_session`, `RoadGraph` is now loaded and registers all POIs into `WorldState.poi_info` *before* `PlayerSession` is instantiated. Previously, `PlayerController.read_state()` found empty `poi_info`, left `pos` as null, and defaulted to `(0, 0, 0)` at the far northwest corner of the map. The player now correctly spawns at their starting POI (e.g., Bagshot Row, Hobbiton).
- **Arrow Keys & Input**: Added `"Up"`, `"Down"`, `"Left"`, `"Right"` bindings in `game/config/controls.json` alongside WASD, plus added the `"map": ["M"]` binding.
- **Player Speed & Traversal**: Increased walk speed from 1.8 m/s to 2.8 m/s, run speed from 4.0 m/s to 6.5 m/s, crouch to 1.4 m/s in `game/config/player.json`. Animation cycle speed dynamically scales with stride velocity via `_time_scale`, making movement feel brisk and responsive across the 1:25 scale landscape.
- **Visual Realism & Fantasy Atmosphere**:
  - `game/world/shaders/terrain_toon.gdshader`: Added high-frequency organic microdetail noise (`n_micro`) to break up flat uniform ground with natural soil/grass tuft grain.
  - `game/config/style.json`: Softer toon lighting band transitions (`band_softness`: 0.38), warm golden rim highlights (`rim_strength`: 0.18, `rim_color`: `[1.0, 0.88, 0.68]`), richer sun energy (1.25, golden elevation), deeper aerial perspective fog (0.52), and sky reflection on water bodies.
- **Audio Integration**:
  - `AudioSession` (`game/audio/audio_session.gd`) classifies terrain (inn POI, settlement radius, river channel, forest polygon, field) and drives `Ambience` and `MusicDirector`.
  - SFX: Added footsteps tied to splat map surface detection (`dirt`, `grass`, `stone`, `wood`), door opening SFX on door interaction, rider screech on SNIFF -> APPROACH.
  - Music: Integrated dual-player crossfade path (`use_whole_cues` in `MusicDirector`) for whole-cue MusicGen files.
- **Villagers & Portraits**:
  - `game/content/villagers.json` defines 24 villagers across 9 settlements (Hobbiton, Bywater, Frogmorton, Marish, Stock, Buckland, Bree, Staddle, Combe).
  - `VillagerSpawner` (`game/npc/villager_spawner.gd`) spawns/despawns villagers dynamically within 600m/700m using `VillagerSchedule` and randomized palette overrides.
  - `DialoguePanel` resolves portrait paths with `<template>_<1 + hash(id) % 6>.png` for villager templates.
- **Black Riders Scene Layer**:
  - `RiderManager` (`game/npc/rider_manager.gd`) manages active riders (`black_rider_khamul`, `black_riders_group`), computes distance, raycast LOS, vegetation and weather concealment, drives fear aura, audio threat levels, and triggers interrogation dialogues.
  - `ConcealmentVolume` (`game/world/concealment_volume.gd`) and `HUD` (`game/ui/hud/hud.gd`) with eye awareness (`HIDDEN`, `SEEN`, `SNIFFED`), Shire calendar time, and survival bars.
- **UI Textures, Map Screen & Skills**:
  - Applied `parchment.png` and `journal_page.png` backdrops to `Journal`.
  - Applied `inventory_panel.png` backdrop to `InventoryPanel`.
  - Created `MapScreen` (`game/ui/map/map_screen.gd`) on M key / action map: displays Western Eriador parchment map, overlays all POI markers, live pulsing player marker, and pauses the world clock while open.
  - Created `TradingPanel` (`game/ui/trading/trading_panel.gd`): buy/sell merchant UI with faction reputation price multipliers, stock, and weight/capacity tracking.
  - Wired `Skills.prompt_lines()` into `PromptBuilder.dynamic_block`.
- **Verification**: 380/380 GUT tests passing across 50 scripts (6,734 asserts), Python content/terrain/audio checks green, and headless boot confirmed with `BOOT_OK`.
