# Handoff to the cloud session: code-only work

Everything below needs no GPU, API key, download or ears, so the cloud session can do it. The Mac session finished the
art/audio generation (portraits, UI textures, MusicGen cues), the benchmarks, and the roster NPC spawner; this is what remains
between those assets and a playable build. Follow `CLAUDE.md` / `docs/PLAN.md` §0; log concerns in `docs/REVIEW.md`.
After adding a `class_name`, run `godot --headless --path game --import` once or GUT will not find it.

## 1. Audio nodes in the world (M1-T15 item 4)
- Add an `AudioSession` node (`game/audio/audio_session.gd`, new) that owns `Ambience` and `MusicDirector` and is added in `Main._build_session`
  after the weather, with `viewer = _player.controller` and `weather = _weather`.
- Every ~0.5 s: classify the viewer's position and call `Ambience.set_location(loc)` and `MusicDirector.set_place(region, settlement, area, in_inn)`;
  from `WeatherDayNight.current` call `Ambience.set_weather(state, rain_intensity)` and `MusicDirector.set_weather(state)`.
- Classification (pure static function, unit test it against `content/regions/eriador_west.json`): inside an inn POI (`kind == "inn"`, within ~10 m) ->
  `inn_interior`; inside a settlement circle -> `settlement`; within river width/2 + 30 m -> `river`; inside a forest polygon or within ~80 m of it ->
  `forest_edge` and `area = forest id`; else `field`. `region` is the region id.
- Rider hooks (see section 5): `MusicDirector.report_rider(distance, RiderAI.State, RiderPerception.EyeState)` / `clear_rider()`; threat level to `Ambience.set_threat` (3 = heartbeat).
- Verify: GUT for the classifier and for a session that follows a moving viewer; `tools/verify.sh`.

## 2. One-shot sounds nothing plays yet
`game/assets/audio/sfx/`: `footstep_<dirt|grass|stone|wood>_<1-3>.ogg`, `door.ogg`, `rider_screech.ogg`, `heartbeat.ogg`.
- Footsteps from `PlayerController` (and optionally `NPCBody`), surface from the splat map (`TerrainHeights.splat`) or building proximity; cadence from speed.
- Door from `Interactable.KIND_DOOR` activation (`player/interaction.gd`). Screech from the rider's SNIFF -> APPROACH transition.
- Bus offsets live in `config/audio.json` (`bus_db`).

## 3. Whole-cue music (MusicGen files)
10 cues in `game/assets/audio/music/cues/*.ogg` (30 s, -16 LUFS): shire_morning, shire_day, road_travel, bree_evening, tavern_jig, night_lullaby,
tension_low, rider_dread, rain_melancholy, dusk_reflective. `MusicDirector` only plays phase-locked stems (one `AudioStreamSynchronized`), so add a
second player path that crossfades whole cues, driven by the same `MusicLogic.Decision` (extend `music.cues` in `config/audio.json`, keep it data driven,
tests in `tests/unit/audio`). The cues have **not been auditioned** (owner will listen); expect some to be swapped, so keep the mapping in config.

## 4. Villagers and portraits
- Roster NPCs already spawn: `npc/npc_spawner.gd` (600 m spawn / 700 m despawn, follows the sim's abstract position, skips `wraith`). Villagers do not exist:
  write villager definitions content (`{id, settlement, home, work, inn}` per `sim/villager_schedule.gd`, templates in `content/lore_cards/templates/`,
  `sim.villager_templates` in `config/sim.json`), validate them, and spawn them within 600 m of the player in a `VillagerSpawner` (or extend `NPCSpawner`).
  Model via `NPCBody.resolve_model_id`, look via `NPCBody.roll_look(template_id, seed)`.
- Portraits: `game/assets/portraits/` has `<npc_id>.png` for the 17 named NPCs and `<template_id>_<1-6>.png` for each villager template.
  `DialoguePanel._set_portrait` only loads `<npc_id>.png`; for villagers pick `<template>_<1 + hash(id) % 6>.png`. Add a test (see `tests/unit/ui/test_dialogue_panel.gd`).

## 5. Black Riders in the world (M1-T11 scene layer)
Logic exists and is tested: `npc/rider_ai.gd`, `rider_ai_node.gd` (`RiderAINode`, needs `target_provider`, `night_provider`, `soft_failure`), `rider_perception.gd`,
`sim/` soft failure, `content/riders/interrogation.json`, `RiderInterrogation.build(race)`. Models: `assets/characters/black_rider_khamul.glb`, `black_riders_group.glb`.
The scene layer is missing: spawn rider bodies near the player (the `NPCSpawner` skips wraiths on purpose), supply a `RiderPerception.Target`
(`has_line_of_sight`, `road_distance_m`, concealment from crouch/vegetation, plus `WeatherDayNight.get_concealment_bonus()` and `get_fear_aura_multiplier()`),
`night_provider` from the clock, vegetation concealment volumes, the HUD eye icon, music/threat hooks (section 1), the screech (section 2), and
the interrogation flow on `interrogation_started`. Scene test: player 10 m off-road crouched in bushes vs on the road.

## 6. UI using the new textures (`game/assets/ui/`)
`parchment.png`, `journal_page.png`, `inventory_panel.png` (a leather satchel, not a flat panel; use as a backdrop or regenerate on the Mac), `region_map.png`
(text-free; overlay POI names from `content/regions/eriador_west.json`, mark the player). Apply to `ui/journal`, `ui/inventory`, add a map screen and key.
Also from M1-T12: HUD (hunger, fatigue, eye, date), trading UI, `place_world.py` forage nodes, `Skills.prompt_lines()` into `prompt_builder`.

## Rules and traps
- `tools/terrain/place_world.py` output is not bit-stable across OS (libm). Linux output is the canonical committed JSON; do not regenerate it on macOS.
  `test_place_world.py` fails on the Mac for that reason only (see REVIEW.md "Local (Mac) session").
- Do not touch the generated art/audio pipelines (`tools/art`, `tools/audio/musicgen_cues.py`); they need the Mac. `.venv-art` / `.venv-music` are local only.
- Verify the game still boots: `godot --headless --path game --quit-after 300` prints `BOOT_OK`; keep `tools/verify.sh` green (except the known test above).
- Re-run `tools/bench.sh flyover_full|walk_hobbiton_to_bree|night_rain_bree` on the Mac after riders/villagers/HUD land (cloud has no GPU).
