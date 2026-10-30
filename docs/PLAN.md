# Implementation Plan

Read `docs/DESIGN.md` first. This plan covers **M0 (Foundation)** and **M1 (Shire → Bree vertical slice)** in full
detail. M2–M6 are outlined in §9. Each of them gets its own detailed plan, written with the same template before work starts.

---

## 0. How to work through this plan (read before every session)

1. **Do tasks in order.** Each task lists `Depends on`. Never start a task whose dependencies are not marked done in
   `docs/PROGRESS.md`.
2. **Every task has a `Verify` section. Run all of it.** A task is done only when every item under `Done when` holds.
   Paste the key verification output (test summary line, file paths of captures) into the task's entry in `PROGRESS.md`.
3. **If verification fails**, fix and re-run. After 3 failed attempts at the same problem, use the task's fallback
   (§8 or the task itself) or the simplest workaround that keeps the game playable. Log it in `docs/REVIEW.md`
   (what you tried, exact error output, best hypothesis, what you did instead) and move on.
4. **After each task:** run `tools/verify.sh` (it must pass), update `docs/PROGRESS.md`, then commit with the message
   `<task id>: <short summary>`, e.g. `M0-T06: world clock with modes A/B`.
5. **Never wait for the user.** The user reviews everything at the end. Work autonomously through every task:
   - Steps marked **📝 REVIEW ITEM** are things the user will judge later (art style, voices, canon, audio, playtest).
     Judge them yourself against the task's criteria, make the call, and add an entry to `docs/REVIEW.md`:
     task id, what to look at (file paths, captures, commands to run), what you decided and why, and what's cheap to change later.
   - A manual download, login or browser-only step → try `curl`/`gh`/direct URLs first. If that's impossible, use the
     stated fallback, note it in `REVIEW.md` under **Needs user action**, and continue.
   - `OPENROUTER_API_KEY` missing → build and test everything against `MockTransport` and the offline fallback. Mark the live
     probes **DEFERRED** in PROGRESS.md and `REVIEW.md`, and continue. Run any deferred live probes as soon as the key appears.
   - Low disk space → use the smaller variant (e.g. a quantised mflux `-q 4`, MusicGen `small`), or defer that generation step
     with procedural placeholders, and log it. **Never delete files outside this repo** to make space.
   - A decision in `DESIGN.md` seems to conflict with what you're building → follow DESIGN.md, log the conflict and your
     suggestion in `REVIEW.md`, and continue.
   - Never write secrets to any file.
6. **Look at visual output yourself.** For any task that produces images (captures, renders, generated art), open the
   PNG with the Read tool and check it against the task's visual criteria before you mark it done.
7. **Canon accuracy.** Use *The Lord of the Rings*, Appendix B ("The Tale of Years") and Appendix D (calendars) as the
   authority for dates and events. If you are not sure of a fact, still write it, but add `"verify": true` to that
   content entry. The M1 timeline report lists all such entries for the user to review.
8. **Don't add scope.** Build only what the task says. Ideas go in `docs/IDEAS.md`.

### Code conventions
- GDScript with **static typing everywhere** (`var x: int`, `func f(a: String) -> void`). Files and functions in snake_case,
  classes in PascalCase via `class_name`.
- Cross-system communication goes through the `EventBus` autoload's signals. Systems don't hold references to each other's nodes.
- No magic numbers in gameplay code. Tunables go in `game/config/*.json`, loaded by `Config` (autoload).
- Every core or sim system gets GUT unit tests in `game/tests/unit/` mirroring its path (`core/world_clock.gd` →
  `tests/unit/core/test_world_clock.gd`).
- Python tools: Python 3.11+, typed, run from the repo root with `.venv/bin/python`. Blender scripts run with
  `blender -b -P <script> -- <args>` and must not need the GUI.
- Comments explain *why*, not *what*. Keep them sparse.

### Standard commands (create these in M0. They are referenced everywhere below)
| Purpose | Command |
|---|---|
| All checks | `tools/verify.sh` |
| Unit tests | `tools/test.sh` (→ GUT headless) |
| Content validation | `.venv/bin/python tools/content/validate.py` |
| Screenshot capture | `tools/capture.sh <scene_or_preset> <out.png> [--date=...] [--pos=x,y,z] [--look=yaw,pitch] [--after=sec]` |
| Benchmark | `tools/bench.sh <route_name>` → `build/bench/<route>.csv` + summary |
| Blender script | `tools/blender.sh <script.py> -- <args>` |
| LLM CLI harness | `tools/talk.sh --npc=<id> --date=<date> --say="..."` |

---

## 1. Target repository layout

```
/                         repo root
  CLAUDE.md               points agents to DESIGN/PLAN/PROGRESS
  docs/                   DESIGN.md, PLAN.md, PROGRESS.md, IDEAS.md, reports/, plans/
  tools/                  shell entry points + python tooling
    content/              validate.py, report_timeline.py
    terrain/              control-map → heightmap/splat generation
    blender/              bpy scripts (lib/ for shared helpers)
    art/                  mflux batch scripts + prompts
    audio/                music generation + processing
    llm/                  list_models.py
  assets_src/             raw downloaded sources (Quaternius, CC0 audio). Git-ignored, manifest committed
  build/                  scratch outputs, benchmarks (git-ignored)
  game/                   Godot project root (res://)
    project.godot
    addons/               gut/, terrain_3d/
    autoload/             event_bus.gd, config.gd, world_clock.gd, world_state.gd, timeline.gd, save_system.gd, llm_gateway.gd, capture.gd
    core/                 game_date.gd, ...
    sim/                  offscreen_sim.gd, road_graph.gd, rumour_network.gd, factions.gd
    player/               controller.gd, camera_rig.gd, interaction.gd, survival.gd, skills.gd, inventory.gd
    npc/                  npc_mind.gd, prompt_builder.gd, reply_parser.gd, intent_validator.gd, memory.gd, npc_body.gd, rider_ai.gd
    world/                world_root.tscn, weather_daynight.gd, cell_streamer.gd, poi.gd
    ui/                   dialogue/, char_creation/, hud/, menus/
    audio/                music_director.gd, ambience.gd
    assets/               generated, imported assets (glb, png, ogg). Tracked in Git LFS
    content/              JSON data + schemas/
    config/               game.json, llm.json, controls.json
    tests/                unit/, fixtures/
    tools/                in-engine dev tools: talk_cli.gd, bench_runner.gd, debug_console.gd
```

---

## 2. Prerequisites

Install them **in the task where they first appear**, not upfront.

| Tool | Installed in | Command | Check |
|---|---|---|---|
| Homebrew | already present | — | `brew --version` |
| Git LFS | M0-T01 | `brew install git-lfs && git lfs install` | `git lfs version` |
| Godot 4 (≥ 4.4) | M0-T01 | `brew install --cask godot` | `godot --version` prints `4.x` with x ≥ 4 |
| Blender 4.x | M0-T01 | `brew install --cask blender` | `/Applications/Blender.app/Contents/MacOS/Blender -b --version` |
| Python venv | M0-T01 | `python3 -m venv .venv && .venv/bin/pip install -r tools/requirements.txt` | `.venv/bin/python -c "import numpy, PIL, jsonschema, opensimplex"` |
| GUT (Godot Unit Test, 9.x for Godot 4) | M0-T03 | download the release matching the Godot version from github.com/bitwes/Gut into `game/addons/gut` | the sample test passes |
| Terrain3D | M1-T03 | download the release matching the Godot version from github.com/TokisanGames/Terrain3D into `game/addons/terrain_3d` | plugin enabled, demo terrain renders in a capture |
| Quaternius packs | M1-T07 | Try direct download first. Fallback if impossible: build base humanoids procedurally in Blender (§8) and log under *Needs user action*. Needed: *Universal Base Characters*, *Universal Animation Library*, *Ultimate Nature* (or the current equivalents), into `assets_src/quaternius/<pack>/` | files present, see `assets_src/MANIFEST.md` |
| OpenRouter API key | M0-T09 | user sets `OPENROUTER_API_KEY` in their shell profile. If missing: mock-only, live probes DEFERRED (§0.5) | `test -n "$OPENROUTER_API_KEY"` |
| mflux | M1-T13 | `.venv/bin/pip install mflux` (weights download on first run) | generates a 512×512 test image |
| MusicGen (MLX) | M1-T15 | clone `github.com/ml-explore/mlx-examples` to `~/opt/mlx-examples`, follow `musicgen/README.md` into a separate venv `~/opt/musicgen-venv` | generates a 5 s test clip |
| CC0 sound effects | M1-T15 | Kenney audio packs (direct download) and/or freesound.org CC0. If login is required, use Kenney + procedurally synthesised effects only | files in `assets_src/audio/`, licences in manifest |

`tools/requirements.txt` (initial): `numpy`, `pillow`, `jsonschema`, `opensimplex`, `scipy`, `requests`.

**Disk:** about 47 GB free at planning time. Before installing anything over 5 GB (Flux weights, MusicGen weights), run
`df -h /`. If less than **30 GB** would remain afterwards, use the smaller variant or defer (§0.5).

---

## 3. Data formats (shared by all tasks)

### 3.1 Game date
- Internally: **integer minutes since T.A. 3018-01-01 00:00**, using the Gregorian-equivalent dates given in Appendix B
  (Tolkien's Appendix B dates line up with our calendar months for the War of the Ring). The type is `GameDate`.
- String form in content: `"3018-09-29T20:00"` (year = T.A.). The date alone (`"3018-09-29"`) means 00:00.
- UI shows Shire Reckoning (e.g. "Halimath 29, S.R. 1418"), converted with a table in `game/content/calendar.json`
  built from Appendix D. T.A. 3018 = S.R. 1418.

### 3.2 Lore card — `game/content/lore_cards/characters/<id>.json`
```json
{
  "id": "barliman_butterbur",
  "name": "Barliman Butterbur",
  "race": "man",
  "faction": "bree",
  "tier": "standard",
  "portrait": "res://assets/portraits/barliman_butterbur.png",
  "home_poi": "prancing_pony",
  "voice": "Bustling, flustered, kind-hearted. Talks fast and in circles, forgets things: 'one thing drives out another'.",
  "personality": ["hospitable", "forgetful", "nervous of strangers and of Rangers", "proud of his beer"],
  "speech_samples": ["Now what was it? ... One thing drives out another, as they say."],
  "knowledge": [
    {"id": "gandalf_letter", "fact": "In summer Gandalf left a letter to be sent to Frodo Baggins in the Shire. Butterbur forgot to send it.", "known_from": "3018-07-01", "secret": true},
    {"id": "riders_at_gate", "fact": "Black-cloaked riders came to the West-gate asking for a Baggins.", "known_from": "3018-09-29T20:00", "requires_flag": null}
  ],
  "never_knows": ["the true nature of the One Ring", "events after the current date"],
  "relationships": {"strider": "wary; thinks him one of the strange Rangers", "nob": "his hobbit servant", "bob": "his hobbit servant"},
  "inventory_can_give": ["ale_mug", "bread_loaf", "bill_the_pony"],
  "verify": false
}
```
Generic NPCs use templates in `lore_cards/templates/` (e.g. `shire_hobbit_villager.json`) with name/personality pools.

### 3.3 Timeline event — `game/content/timeline/events/*.json` (array)
```json
{
  "id": "rider_questions_gaffer",
  "at": "3018-09-23T19:00",
  "type": "world_event",
  "location": "bagshot_row",
  "actors": ["black_rider_khamul", "gaffer_gamgee"],
  "effects": [{"set_flag": "gaffer_met_rider"}, {"add_knowledge": {"npc": "gaffer_gamgee", "knowledge_id": "rider_asked_for_baggins"}}],
  "rumour": {"id": "black_rider_in_hobbiton", "origin_poi": "hobbiton", "strength": 3},
  "waits_for_player": false,
  "window_end": null,
  "depends_on": [],
  "verify": false
}
```
`type` ∈ `world_event`, `itinerary_step` (generated from itineraries), `anchor`. When `waits_for_player` is true
(mode B only), the event holds until the player is inside `trigger_area` or until `window_end`. All events that
transitively `depends_on` it shift by the same delay.

### 3.4 Itinerary — `game/content/timeline/itineraries/<character_id>.json`
```json
{
  "character": "frodo",
  "steps": [
    {"at": "3018-09-23T20:00", "action": "depart", "from": "bag_end", "to": "woody_end_camp", "mode": "walk", "companions": ["sam", "pippin"], "id": "frodo_leaves_bag_end"},
    {"at": "3018-09-24T22:00", "action": "camp", "at_poi": "woody_end_camp", "id": "frodo_meets_gildor", "depends_on": ["frodo_leaves_bag_end"]}
  ]
}
```
Between steps, the character moves along the road graph and arrives by the time of the next step.

### 3.5 Region — `game/content/regions/eriador_west.json`
World units are metres. The origin is the south-west corner of the region. +X = east, -Z = north (Godot forward).
```json
{
  "id": "eriador_west",
  "size_m": [8192, 4096],
  "scale_note": "≈1:25 compression of canon distances",
  "pois": [{"id": "bag_end", "name": "Bag End", "pos": [900, 0, 2100], "kind": "dwelling", "settlement": "hobbiton"}],
  "settlements": [{"id": "hobbiton", "faction": "shire", "center": [950, 2150], "radius": 250}],
  "roads": [{"id": "east_road", "kind": "road", "points": [[0, 2400], [8192, 2300]]}],
  "rivers": [{"id": "brandywine", "width": 40, "points": [[5200, 0], [5300, 4096]]}],
  "hills": [{"id": "the_hill", "center": [900, 2100], "radius": 180, "height": 35}],
  "forests": [{"id": "old_forest", "polygon": [[5400, 2600], [6600, 2600], [6600, 3600], [5400, 3600]], "density": 1.0, "enterable": false}],
  "road_graph": {"nodes": ["bag_end", "bywater", "..."], "edges": [["bag_end", "bywater", "road"]]}
}
```

### 3.6 LLM reply wire format
The model must reply with the NPC's speech as plain text, then a line containing exactly `---META---`, then one JSON object:
```
Ah, Mr. Underhill, was it? Now there's a name...
---META---
{"options": ["Ask about the riders", "Order a pint", "Ask about Strider"], "intents": [{"type": "disposition_delta", "value": 1}], "mood": "flustered"}
```
Speech is streamed to the UI until `---META---` appears. The META part is buffered and parsed. If parsing fails, use
no options and no intents, and log a warning.

M1 intent whitelist: `give_item{item_id}`, `share_rumour{rumour_id}`, `share_knowledge{knowledge_id}`,
`disposition_delta{value ∈ [-2, 2]}`, `reveal_poi{poi_id}`, `end_conversation{}`.

---

## 4. Milestone M0 — Foundation

Exit criteria: toolchain installed. The Godot project boots headless and windowed. Tests, content validation and
captures work. A live in-character conversation with Butterbur through OpenRouter runs from the CLI, respects knowledge
filtered by date, and falls back cleanly when offline.

### M0-T01 — Toolchain
- **Depends on:** —
- **Steps:**
  1. `df -h /` and record free space in PROGRESS.md.
  2. Install Git LFS, Godot and Blender (§2). If `godot` is not on PATH after the cask install, create
     `tools/bin/godot` → `/Applications/Godot.app/Contents/MacOS/Godot`, and likewise `tools/bin/blender`. All
     tool scripts put `tools/bin` first on PATH.
  3. Write `tools/requirements.txt`, create `.venv`, install.
- **Verify:** all the "Check" commands in §2 for these tools succeed. Record the versions in PROGRESS.md.
- **Done when:** the versions are recorded and Godot ≥ 4.4.

### M0-T02 — Repository scaffold
- **Depends on:** M0-T01
- **Steps:**
  1. Create the directory layout from §1 (empty dirs get `.gitkeep`).
  2. `.gitignore`: `game/.godot/`, `.venv/`, `build/`, `assets_src/**` except `assets_src/MANIFEST.md`, `*.import` is **not** ignored, `.DS_Store`.
  3. `.gitattributes` with LFS tracking for `*.glb *.gltf *.png *.jpg *.exr *.r16 *.ogg *.wav *.res` inside `game/assets/**`.
  4. `docs/PROGRESS.md`: one checkbox line per task in this plan, with a space under each for verification notes.
  5. `docs/IDEAS.md` (empty heading). `docs/REVIEW.md` with three sections: **Review items** (📝 things for the user to judge),
     **Needs user action** (downloads, key, disk), and **Deferred / fallbacks used**. `CLAUDE.md` at the root (already present; keep it).
  6. `tools/verify.sh` stub that runs whatever checks exist (it grows over time) and exits non-zero on any failure.
- **Verify:** `git lfs track` lists the patterns. `tools/verify.sh` exits 0. `git status` shows no ignored files that should be committed.
- **Done when:** committed.

### M0-T03 — Godot project and test framework
- **Depends on:** M0-T02
- **Steps:**
  1. Create `game/project.godot` (name "Middle-earth"). Settings: Forward+ renderer, `rendering/rendering_device/driver.macos="metal"`,
     physics engine Jolt, window 2560×1440 (allow resizing), main scene `res://world/boot.tscn` (a placeholder that prints `BOOT_OK` and idles).
  2. Autoload stubs (empty classes with `class_name`, in this order): `Config`, `EventBus`, `WorldClock`, `WorldState`, `Timeline`, `SaveSystem`, `LLMGateway`, `Capture`.
  3. `Config` loads `res://config/game.json` and `res://config/llm.json` and exposes `get_value(path: String, default)`.
  4. Install GUT in `game/addons/gut`. Add `game/tests/unit/test_sanity.gd` with one passing test.
  5. `tools/test.sh`: `godot --headless --path game -s res://addons/gut/gut_cmdln.gd -gdir=res://tests/unit -ginclude_subdirs -gexit`.
     It must exit non-zero on test failure (check GUT's docs for the version installed and confirm by temporarily breaking the test).
  6. `godot --headless --path game --import` (or open the editor headless once) so that `.godot/` is generated.
- **Verify:** `tools/test.sh` passes. Temporarily breaking the sanity test makes it exit non-zero (then revert).
  `godot --headless --path game --quit-after 120` prints `BOOT_OK` with no `ERROR` lines.
- **Done when:** all of the above, and `tools/verify.sh` runs `tools/test.sh`.

### M0-T04 — Capture tool (how the agent sees the game)
- **Depends on:** M0-T03
- **Steps:**
  1. `autoload/capture.gd` parses `OS.get_cmdline_user_args()`: `--capture=<abs path>`, `--after=<sec>` (default 3),
     `--scene=<res path>`, `--pos=x,y,z`, `--look=yaw,pitch`, `--date=<content date>`, `--hide-ui`. It loads the scene, places the
     active camera, waits `after` seconds (rendered frames, not wall time), saves `get_viewport().get_texture().get_image()` as PNG and quits with code 0.
     If the scene fails to load, it quits with code 2.
  2. `tools/capture.sh` wraps `godot --path game --resolution 2560x1440 -- <args>` (windowed, not headless; headless cannot render).
  3. Test scene `res://tests/scenes/capture_test.tscn`: a coloured cube, sun light, environment.
- **Verify:** `tools/capture.sh res://tests/scenes/capture_test.tscn build/cap_test.png` exits 0. Open the PNG and
  check that the cube is visible and lit and the image is 2560×1440.
- **Done when:** the image is confirmed by viewing it.

### M0-T05 — Content schemas and validator
- **Depends on:** M0-T02
- **Steps:**
  1. JSON Schemas in `game/content/schemas/` for: lore card, template card, timeline event, itinerary, region, calendar, item, rumour, origin.
  2. `tools/content/validate.py`: validates every JSON file under `game/content/` against its schema (file location → schema),
     then **cross-reference checks**: every referenced id exists (npc, poi, item, rumour, knowledge, event); itinerary steps
     are in time order; dates parse and fall within 3018-01-01..3021-12-31; `depends_on` has no cycles; `portrait` paths exist
     (warning only until art exists). Prints `CONTENT_OK` or a list of errors with file and JSON path. Exits non-zero on error.
  3. Fixtures `game/tests/fixtures/content_bad/`: one file per error class.
  4. `tools/content/test_validate.py` (pytest or plain asserts): each bad fixture produces the expected error.
  5. Seed content: `calendar.json` (Shire Reckoning months from Appendix D), `lore_cards/characters/barliman_butterbur.json` (§3.2), and `items/core.json` with the 3 items it references.
- **Verify:** `validate.py` prints `CONTENT_OK`. The fixture tests pass. Add both to `tools/verify.sh`.
- **Done when:** all the above.

### M0-T06 — GameDate and WorldClock
- **Depends on:** M0-T03
- **Steps:**
  1. `core/game_date.gd` (`class_name GameDate`, static helpers): `parse(s: String) -> int`, `format_iso(m: int) -> String`,
     `format_shire(m: int) -> String`, `day_of(m)`, `hour_of(m)`, `is_night(m)` (21:00–05:00).
  2. `WorldClock`: `now: int`, `time_scale` (game minutes per real second; default from config `clock.minutes_per_second = 0.5`,
     i.e. 1 game day = 48 real minutes), `paused` (a stack of pause reasons, so dialogue and menus can each pause independently),
     `mode: StringName` (`&"A"`/`&"B"`), `advance(minutes)` (used for sleeping, waiting, soft failure), signals `minute_passed(now)`, `hour_passed`, `day_passed`.
     `advance` must emit every intermediate hour/day signal in order.
- **Verify (GUT tests):** parse/format round-trip for 20 dates. `format_shire("3018-09-22")` = "Halimath 22, S.R. 1418"
  (confirm the mapping against Appendix D; note that Shire months have 30 days, so build the mapping table carefully and
  test the month boundaries). Pause stack. `advance(1500)` emits 25 hour signals and 1 day signal. Mode persists through serialise/deserialise.
- **Done when:** the tests pass.

### M0-T07 — EventBus, WorldState, SaveSystem
- **Depends on:** M0-T06
- **Steps:**
  1. `EventBus` signals (initial): `flag_changed(flag, value)`, `entity_moved(id, poi_or_pos)`, `item_transferred(item, from, to)`,
     `rumour_spread(rumour_id, poi)`, `dialogue_started(npc_id)`, `dialogue_ended(npc_id)`, `player_failed(kind, data)`, `timeline_event_fired(event_id)`.
  2. `WorldState`: dictionaries of `entities` (id → {kind, pos or poi, region, alive, data}), `flags`, `inventories` (owner → {item: count}),
     `reputation` (faction → int −100..100), `npc_memory` (npc → {summary, last_talk, disposition}). Mutations only through methods that emit EventBus signals.
  3. `SaveSystem`: `save(slot: String)` and `load(slot)` to `user://saves/<slot>.json`, with `{"version": 1, "clock": ..., "state": ..., "timeline": ...}`.
     Autosave every in-game 6 hours and on region transitions (config). Keep the last 3 autosaves. Version mismatches go through a `migrations` dict (empty for now).
- **Verify (GUT):** a mutation emits the right signal. Save → load round-trip gives deep equality for a populated state. Corrupt JSON → `load` returns an error without crashing. Autosave rotation keeps 3.
- **Done when:** the tests pass.

### M0-T08 — Timeline engine
- **Depends on:** M0-T07, M0-T05
- **Steps:**
  1. `Timeline` loads all events plus itineraries (itinerary steps become `itinerary_step` events) and sorts them by `at`.
  2. On `minute_passed`, fire every due event in order: apply its `effects` (set_flag, add_knowledge, move_entity, give_item, spread_rumour)
     through WorldState, then emit `timeline_event_fired`.
  3. Mode B: for a due event with `waits_for_player`, check `trigger_area` (poi id + radius, or a settlement) against the player position. If the player
     isn't there, hold it. Track the `delay` = now − at. Once it fires (player arrives or `window_end` is reached), shift every event that transitively
     depends on it by the delay. In mode A, it fires on time, always.
  4. Serialise fired ids + delays for SaveSystem.
- **Verify (GUT):** fixtures with 5 events: order is correct. Mode A fires on time. Mode B holds, then fires when the player is moved into the area,
  and its dependents shift by exactly the delay. `window_end` forces a fire. Save/load mid-hold preserves the held state.
- **Done when:** the tests pass.

### M0-T09 — LLM gateway (OpenRouter)
- **Depends on:** M0-T03
- **Steps:**
  1. Check `test -n "$OPENROUTER_API_KEY"`. If missing, continue mock-only and mark the live steps DEFERRED (§0.5). Never write the key to any file.
  2. `tools/llm/list_models.py`: GET `https://openrouter.ai/api/v1/models` and print Anthropic models with context length and pricing.
     Use it to choose the newest Opus-class model for `key_figure` and the newest Sonnet-class model for `standard` and `summariser`,
     and write them to `game/config/llm.json`:
     ```json
     {"endpoint": "https://openrouter.ai/api/v1/chat/completions",
      "tiers": {"key_figure": {"model": "<slug>", "max_tokens": 600, "temperature": 0.8},
                "standard":   {"model": "<slug>", "max_tokens": 400, "temperature": 0.8},
                "summariser": {"model": "<slug>", "max_tokens": 400, "temperature": 0.2}},
      "timeout_s": 25, "retries": 1, "app_title": "Middle-earth (personal)"}
     ```
  3. `LLMGateway.request(tier, messages, on_chunk: Callable, on_done: Callable)` uses Godot `HTTPClient` (not `HTTPRequest`,
     which can't stream) to POST with `stream: true` and parse the SSE `data:` lines (ignore `: OPENROUTER PROCESSING` comment lines,
     stop at `[DONE]`). Headers: `Authorization: Bearer <env key>`, `Content-Type: application/json`, `X-Title: <app_title>`.
     It reads the key with `OS.get_environment`.
  4. Prompt caching: the gateway accepts messages whose content is an array of parts. Parts flagged `cache: true` are sent with
     `"cache_control": {"type": "ephemeral"}` (the format OpenRouter supports for Anthropic models; confirm in the current OpenRouter docs).
  5. Transport behind an interface (`LLMTransport`) so that tests use `MockTransport`, which replays canned SSE streams.
  6. `is_available()`: false if there's no key, or after 2 consecutive network failures (re-probe every 5 real minutes). Emits `EventBus.llm_availability_changed`.
  7. Log every request (tier, model, token usage from the final chunk if present, latency) to `user://logs/llm.jsonl`.
- **Verify:** GUT with MockTransport covers chunk assembly, `[DONE]` handling, mid-stream error, timeout, and the availability flag.
  Live test (only when `LIVE_LLM=1`): `tools/test.sh` with a test that sends "Reply with exactly: PONG" to the standard tier and asserts that `PONG` is in the reply.
- **Done when:** mock tests pass, the live test passes once (record the latency in PROGRESS.md), and `llm.json` has real slugs.

### M0-T10 — NPC mind (prompt → reply → intents → memory)
- **Depends on:** M0-T09, M0-T08
- **Steps:**
  1. `npc/prompt_builder.gd` builds messages in this order (cached parts first):
     - [cache] **World system prompt** (`content/prompts/world_system.md`, written in this task): you are voicing one character in
       Middle-earth, T.A. 3018. Stay in character. Never mention being an AI. Never reveal facts not in your knowledge. Use the
       reply wire format (§3.6) exactly. 3–4 short options phrased as what the *player* might say or do. Keep speech under 120 words unless asked to tell a story.
     - [cache] **Character block**: voice, personality, speech samples, relationships, `never_knows`.
     - **Dynamic block**: current date (Shire format + time of day + weather), location, who's present, the player's visible traits
       (race, origin, reputation band with this NPC's faction, notable items visible, Ring-corruption cues: none in M1),
       **knowledge entries filtered** by `known_from <= now` and `requires_flag`, rumours this NPC has heard, memory summary
       of past talks with the player, current disposition, and the allowed intents with valid ids (only items the NPC actually has, rumours it knows, and so on).
     - Conversation turns so far.
  2. `npc/reply_parser.gd` splits speech and META. `npc/intent_validator.gd` checks every intent against WorldState and the whitelist and applies the valid ones.
  3. `npc/memory.gd`: when a conversation ends, call the `summariser` tier with the previous summary + the transcript. It must output JSON
     `{"summary": "<≤120 words, from the NPC's point of view>", "learned": [{"fact": "...", "spreadable": true}]}`. Store it in `WorldState.npc_memory`.
     Spreadable facts become player rumours (consumed by the rumour network in M1).
  4. Offline / failure fallback: `content/dialogue_fallbacks/<npc>.json` with `greetings`, `farewells`, `smalltalk` and `rumour_lines` (keyed by rumour id).
     The fallback picks lines filtered by date and offers fixed options ("Ask about news", "Trade", "Farewell").
  5. `game/tools/talk_cli.gd` + `tools/talk.sh`: a headless harness that loads content, sets the date, creates a default player and runs one or more
     turns (`--say` can repeat) or an interactive stdin loop with `--interactive`. It prints speech, options, applied intents, and on exit the new memory.
- **Verify:**
  - GUT: prompt builder excludes a knowledge entry dated after now and includes it once now passes its date. The parser handles a missing META, broken JSON, and META with no speech. The validator rejects `give_item` for an item the NPC doesn't own and a `disposition_delta` of 5. The fallback path is used when the gateway is unavailable.
  - Live (`LIVE_LLM=1`), save the outputs to `docs/reports/m0_dialogue.md`:
    1. `tools/talk.sh --npc=barliman_butterbur --date=3018-09-29T21:00 --say="Good evening! Any news?"` → reply in Butterbur's voice, 3–4 options.
    2. Spoiler probe: `--say="Has Gandalf fallen in Moria?"` → he doesn't know (he's confused or has no idea). It must not confirm the event.
    3. Knowledge probe: `--date=3018-09-29T21:00 --say="Did Gandalf leave anything for a Mr. Baggins?"` → he reacts to the letter (secret, so evasive or remembering), consistent with the card.
    4. Earlier date: `--date=3018-06-01 --say="Did Gandalf leave you anything?"` → no letter yet.
    5. Offline: `OPENROUTER_API_KEY= tools/talk.sh ...` → fallback lines, no crash.
    6. Two separate runs with `--keep-memory` show that the second conversation refers to the first.
  - Check each output yourself against these criteria and note pass/fail per probe in the report.
- **Done when:** all the GUT tests pass, all 6 probes pass. **M0 complete** → 📝 **REVIEW ITEM:** voice quality (`docs/reports/m0_dialogue.md`). Continue to M1.

---

## 5. Milestone M1 — The Shire → Bree (T.A. 3018, Sept 20 – Oct 6)

**Player experience at exit:** create a hobbit (Shire) or a man (Bree). Walk, in real time, through a stylized, continuous
Shire → Buckland → East Road → Bree. Talk to named NPCs voiced by the LLM, who remember you. See Frodo's party travelling on
their canon schedule. Hide from Black Riders on the road. Eat, sleep and forage. Gain reputation. Hear rumours spread. Save and load.
60 fps on this Mac.

**Not in M1:** switching characters, the travel-map layer, Ring corruption, anchors (Weathertop is M2), Elf and Dwarf origins, combat beyond fleeing.

**Canon note:** Gandalf is *not* in the Shire for most of this window. Per Appendix B he visits the Gaffer on Sept 29, reaches Crickhollow on Sept 30,
and leaves Bree on Oct 1. He's a fleeting key-figure encounter, in a hurry, on Shadowfax. Strider at the Prancing Pony is the main key-figure NPC.

### M1-T01 — Canon content pass: timeline and cast
- **Depends on:** M0 complete
- **Steps:**
  1. Write events and itineraries for **3018-09-20 → 3018-10-06** covering: Frodo, Sam, Pippin (from Bag End), Merry and Fatty Bolger (Crickhollow),
     Gandalf (from Sept 29), the Black Riders (as `black_rider_khamul` + `black_riders_group` at Bree and Crickhollow), Strider (Bree, then leaving with the hobbits),
     Bill Ferny, Gildor's company (Woody End, Sept 24), Farmer Maggot (Sept 25), Tom Bombadil and the Barrow-downs (off-map for M1: the party is
     "in the Old Forest / at Bombadil's" as an abstract location that you can't enter, Sept 26–28), the Prancing Pony arrival (Sept 29), the raids on Crickhollow and the inn (Sept 30 early hours),
     and the departure from Bree (Sept 30), then off the east edge of the map (Weathertop on Oct 6 is reported as a rumour only).
  2. Mark the Prancing Pony arrival `waits_for_player: true` with `trigger_area: {"settlement": "bree"}` and `window_end: "3018-10-08"`.
     All later steps of the Frodo party and Strider `depends_on` it.
  3. Lore cards (with knowledge filtered by date) for: Frodo, Sam, Pippin, Merry, Fatty Bolger, Gaffer Gamgee, Farmer Maggot, Mrs Maggot,
     Lobelia Sackville-Baggins, Barliman Butterbur, Nob, Strider (`key_figure`), Gandalf (`key_figure`), Bill Ferny, Gildor Inglorion (`key_figure`).
     Templates: `shire_hobbit_villager`, `bree_villager` (man), `bree_hobbit_villager`.
  4. Rumours (`content/rumours/m1.json`): at least 10 (e.g. "Mr. Frodo sold Bag End to the Sackville-Bagginses", "Black riders asking for Baggins",
     "Strange folk on the East Road", "Dwarves going east"), each with an origin, a start date and how far and fast it travels.
  5. Fallback dialogue files for every named NPC.
  6. `tools/content/report_timeline.py` → `docs/reports/timeline_m1.md`: a chronological table of all events with actors and locations, plus a
     section listing every `"verify": true` entry.
- **Verify:** `validate.py` → `CONTENT_OK`. Open the report yourself and check the ordering against Appendix B. The report exists.
- **Done when:** you've checked the report against Appendix B yourself. 📝 **REVIEW ITEM:** `timeline_m1.md`, especially the verify section.

### M1-T02 — Region layout (control map)
- **Depends on:** M1-T01 (POI ids)
- **Steps:**
  1. Write `content/regions/eriador_west.json` (§3.5). 8192 m × 4096 m, about 1:25 compression. From west to east: Hobbiton (The Hill, Bag End,
     Bagshot Row, the Party Field, the Mill, the Water) → Bywater (Green Dragon inn) → the East Road → the Three-Farthing Stone → Frogmorton (The Floating Log) →
     the Woody End (Gildor's camp, the riders' road) → the Marish (Maggot's farm, Bamfurlong) → Stock (Golden Perch) → Bucklebury Ferry → the Brandywine →
     Buckland (Brandy Hall, Crickhollow, the High Hay, the Hedge gate) → the Old Forest edge (not enterable) → the Brandywine Bridge → the East Road through
     open country with the Barrow-downs on the horizon (not enterable) → Bree-land (Bree-hill, Bree village, the West-gate and South-gate, the Prancing Pony,
     Bill Ferny's house, Staddle and Combe as small hamlets, the Chetwood edge).
     Use Tolkien's map of the Shire for relative placement. Roads and rivers are polylines. Every settlement has a faction.
  2. The road graph covers every POI that a roster character's itinerary uses.
  3. `tools/terrain/render_control_map.py` → `build/maps/eriador_west_control.png` (2048 px wide): roads, rivers, forests, hills, labelled POIs.
- **Verify:** open the PNG and check the geography (the Brandywine runs north–south between the Marish and Buckland, the East Road crosses
  it at the Bridge, the Old Forest is east of the Hedge, Bree is at the far east). Script check: every itinerary POI is reachable in the road graph,
  and walking Bag End → Prancing Pony at 1.4 m/s along the roads takes 60–110 real minutes (print the result).
- **Done when:** the checks pass and the map image is placed in `docs/reports/`.

### M1-T03 — Terrain generation and Terrain3D import
- **Depends on:** M1-T02
- **Steps:**
  1. `tools/terrain/build_heightmap.py`: from the control map, produce a 16-bit heightmap (1 px = 1 m, so 8192×4096; write as EXR or R16, whatever the Terrain3D
     importer accepts): base rolling-hills noise (opensimplex, low amplitude in the Shire, rising towards the Barrow-downs), hills as smooth bumps,
     river channels carved, roads flattened and slightly sunken, a flat bench for each settlement, a raised Bree-hill, and border mountains or ridges
     at the edges to hide the world's end. Also produce splat/control maps: grass, path/dirt, field, riverbank and forest floor.
  2. Install Terrain3D (§2). Import the heightmap and splats with its importer, using its documented scripted or headless import path if available. Otherwise
     write `game/tools/import_terrain.gd`, an `EditorScript` run headless. Save to `game/assets/terrain/eriador_west/`.
  3. Water: a simple stylized water shader on planes or meshes along the rivers, generated from the river polylines.
  4. `world/world_root.tscn`: terrain + sun + WorldEnvironment (sky, fog) + water.
- **Verify:** captures from 4 presets (`hobbiton_overview`, `brandywine_bridge`, `east_road`, `bree_hill`) defined in `game/config/capture_presets.json`.
  Open each one: the terrain matches the control map and the rivers sit in channels. No holes or seams. Roads are visible as dirt.
- **Done when:** the 4 captures pass your own check and saved in `docs/reports/m1_terrain/`.

### M1-T04 — Style frame and art direction
- **Depends on:** M1-T03
- **Steps:**
  1. A stylized look: a toon/painterly terrain shader (banded lighting, colour ramps per splat layer, soft rim), a stylized sky (gradient + clouds),
     warm golden-hour sun, distance fog with an aerial-perspective tint. Palette: Shire = saturated greens and golds; Bree = muted browns and greys.
  2. Blender proof-of-concept assets (§M1-T05 pipeline, but only these): 1 hobbit-hole with a round door, 3 tree variants, 1 bush, 1 fence segment, 1 rock.
  3. Assemble a small set dressing at Bag End and in front of the Prancing Pony.
- **Verify:** 3 captures (Bag End close, Hobbiton overview, Bree gate) in `docs/reports/m1_style/`.
- **Done when:** you judge the 3 captures to be cohesive, readable and clearly "Shire" vs "Bree" (iterate up to 3 rounds yourself). Keep all the style parameters
  (colour ramps, shader values, sky, fog) in one place, `game/config/style.json` + `tools/blender/lib/style.py`, so that changing the look later only means
  re-running the generators. 📝 **REVIEW ITEM:** art style (`docs/reports/m1_style/`).

### M1-T05 — Blender procedural asset library
- **Depends on:** M1-T04
- **Steps:**
  1. `tools/blender/lib/`: shared helpers (materials matching the style frame's colour ramps, low-poly bevel and decimation, LOD generation at 100% / 40% / 15%,
     convex or simple collision meshes with the Godot `-col`/`-colonly` naming convention, glTF export with the correct axes and scale).
  2. Generator scripts, each parametric with a seed and writing several variants:
     - nature: trees (oak, beech, birch, willow, pine × 4 variants each), bushes, hedgerow segments, reeds, rocks, logs, flowers/grass cards
     - Shire: hobbit-hole (door colour, window count, hill size), hobbit cottage (above-ground, Buckland style), mill, inn (Green Dragon / Golden Perch),
       fences, gates, garden plots, wells, bridges (small, plus the Brandywine Bridge), the Bucklebury Ferry raft, the Three-Farthing Stone
     - Bree: stone and timber houses (2-storey, hobbit-sized variants), the Prancing Pony (unique: big courtyard, stables), the Bree gates, the dike and hedge, Bill Ferny's house
     - props: barrels, carts, signposts, lanterns, benches, tables, mugs, food
  3. `tools/blender/build_all.py` builds everything into `game/assets/models/<category>/`. `tools/blender/preview.py` renders a contact sheet per category (Workbench or Eevee) to `build/previews/`.
  4. `tools/blender/check_budget.py`: triangle counts per LOD against `tools/blender/budgets.json` (e.g. tree LOD0 ≤ 3k tris, house LOD0 ≤ 8k, prop ≤ 1k).
- **Verify:** `build_all.py` runs without errors. Budgets pass. Open the contact sheets and check they match the style frame. Godot import of all
  `.glb` files gives zero import errors (`godot --headless --path game --import` output).
- **Done when:** the above, plus one capture of all assets laid out in a test scene.

### M1-T06 — World population
- **Depends on:** M1-T05
- **Steps:**
  1. `tools/terrain/place_world.py`: from the control map, emit `game/content/regions/eriador_west_placements.json` with buildings per settlement (oriented to the roads),
     fields and gardens, fences and hedges along the roads, the Buckland Hedge, forest scatter (Poisson disk, density from the polygons), and the Old Forest edge as an impassable wall of trees.
  2. `world/cell_streamer.gd`: splits the region into 256 m cells. Loads and unloads building and prop scenes within 768 m of the camera. Foliage uses
     MultiMeshInstance3D per cell, with `visibility_range` fade, and impostors or LOD for distant trees. Collision only within 128 m.
  3. Navigation: a NavigationMesh baked per cell, or a navigation region along the roads plus settlement areas, enough for NPCs to walk the road graph.
  4. POI markers (`world/poi.gd`) with interaction volumes for doors, inns and wells.
- **Verify:** captures at all 4 presets + `bag_end_close` + `prancing_pony_yard`: populated and in style. `tools/bench.sh flyover_full` (a camera spline over the whole region at walking height,
  at 1440p): average ≥ 60 fps, 1% low ≥ 45 fps, peak memory under 6 GB (log `Performance` monitors to CSV).
- **Done when:** the benchmark passes. Record the numbers in PROGRESS.md.

### M1-T07 — Characters
- **Depends on:** M1-T04. Quaternius packs present, or the procedural-base fallback (§8)
- **Steps:**
  1. `tools/blender/characters/build_bases.py`: import the Quaternius base humanoids. Make race presets by bone scaling + mesh adjustments: `hobbit` (≈0.6 height,
     larger head:body ratio, big hairy bare feet, curly hair), `man_bree` (1.0, stockier), `dunedain` (1.05, lean). Store them as `tools/blender/characters/races.json`.
  2. Outfits: modular, procedurally modelled clothing pieces (waistcoat, cloak with hood, breeches, apron, jerkin, Ranger cloak, Black Rider robe: tall, hooded, featureless dark).
     Colours per character from `characters/looks.json` (one entry per named NPC + randomised palettes for villagers).
  3. Retarget the Quaternius animation library onto each race skeleton: idle, walk, run, sit, talk-gesture, crouch-walk (stealth), sleep, eat, pick-up, fall/faint.
     Black Riders: idle, walk, sniff (head scan), mounted is out of scope for M1 (riders on foot). Note in IDEAS.md that horses come in M2.
  4. Export one `.glb` per named NPC and one per villager base, with animations, to `game/assets/characters/`.
  5. Godot: `npc/npc_body.gd` + an AnimationTree (locomotion blend by speed, one-shots for gestures).
- **Verify:** Blender renders a contact sheet: every named NPC in a T-pose and in walk frame 10. Check that hobbits are clearly hobbit-like next to a man, and that the riders are menacing.
  A Godot capture of a lineup scene with all characters in idle. A GUT/scene test confirms the AnimationTree changes state as speed changes.
- **Done when:** the contact sheet and lineup pass your own check. 📝 **REVIEW ITEM:** character lineup capture.

### M1-T08 — Player controller and camera
- **Depends on:** M1-T06, M1-T07
- **Steps:**
  1. `player/controller.gd` (CharacterBody3D): WASD relative to the camera, Shift to run, C for stealth crouch, Space for a small hop, E to interact, Tab for inventory, J for the journal (rumours, memories), Esc for the menu. Bindings in `config/controls.json`.
  2. `player/camera_rig.gd`: third-person spring arm with collision, mouse orbit, scroll zoom (1.5–8 m), and over-the-shoulder framing when in dialogue range.
  3. `player/interaction.gd`: shows a prompt for the nearest interactable within 2.5 m (NPC, door, well, bed, food source).
  4. `game/tools/debug_console.gd` (toggle with backtick, dev builds only): `tp <poi>`, `date <iso>`, `give <item>`, `flag <k> <v>`, `mode A|B`, `speed <x>`.
- **Verify:** a scripted-input GUT/scene test: hold W for 3 s → the player moves forward 3–6 m, no falling through the terrain. Running is faster. Stealth is slower and lowers the `noise` value.
  A capture from behind the player at Bag End.
- **Done when:** the tests pass and the capture looks right.

### M1-T09 — Character creation and origins
- **Depends on:** M1-T08
- **Steps:**
  1. `content/origins/m1.json`: Hobbit → *Hobbiton gardener* (start: Bagshot Row, 3018-09-20 08:00), *Bucklander* (Crickhollow lane, 09-20),
     *Tookland lad/lass* (arrives on the East Road near Bywater, 09-20). Man → *Bree-lander, ostler at the Prancing Pony* (Prancing Pony yard, 09-20),
     *Staddle farmer* (Staddle, 09-20). Each origin has starting items, a reputation offset, 1 skill bonus and 2 NPCs who already know you
     (pre-seeded memories, e.g. the Gaffer knows the gardener).
  2. UI `ui/char_creation/`: name, race, origin, background trait (Curious / Cautious / Kind / Proud: affects options and NPC first impressions), appearance (pick from 6 palettes + hair), and the time mode A/B with a one-line explanation.
  3. Starting a new game builds WorldState from the content, applies the origin and places the player.
- **Verify:** GUT: for each origin, `new_game()` gives the right position, date, inventory, reputation and seeded memories. Captures of the creation screen and of the first frame in play for 2 origins.
- **Done when:** the tests pass.

### M1-T10 — Off-screen simulation and roster NPC bodies
- **Depends on:** M1-T09, M0-T08
- **Steps:**
  1. `sim/road_graph.gd`: shortest path on the region road graph, position as edge + t, and conversion to a world position.
  2. `sim/offscreen_sim.gd`: each tick (each game minute) advances every itinerary character along its path so that it arrives at the next step's POI by that step's
     time (speed derived from the distance; clamp to a plausible walking speed, and if that's impossible log a content warning). Camping / staying steps keep them still.
     Characters in `companions` travel as a group.
  3. Spawning: if the player's camera is within 600 m of an abstract position, spawn an `npc_body` there and let it follow the same path with
     NavigationAgent3D. Despawn when they're more than 700 m away. The body's progress writes back to the abstract position (one truth).
  4. Deviation: talking to a roster NPC pauses its travel. Afterwards it continues, and if it's now late, it hurries (run speed) to catch up. If it's late
     for a `waits_for_player` step in mode B, that's handled by the timeline delay. In mode A, a step can't fire before arrival, so the step fires on arrival and its dependents shift. Log the deviation.
  5. Villagers: lightweight daily schedules from templates (home → work → inn in the evening → home) in settlements within 600 m only. Not simulated off-screen.
- **Verify:**
  - GUT headless: run the clock from 09-23 12:00 to 09-30 06:00 with no player near → the Frodo party's abstract positions match their canon POIs at each step time (within 50 m).
    Black Rider Khamûl is at Bagshot Row on 09-23 at 19:00.
  - Mode B: player far from Bree → the party holds outside Bree (at a waiting POI just west of the West-gate), then enters when the player tp's into Bree. Later steps shift.
  - Visual: `tools/capture.sh` with `--date=3018-09-24T16:00` at a POI on the riders' road → the hobbit party is visible walking. Save it in `docs/reports/m1_sim/`.
- **Done when:** the tests and capture pass.

### M1-T11 — Black Riders, stealth and soft failure
- **Depends on:** M1-T10
- **Steps:**
  1. `npc/rider_ai.gd`: the riders follow their timeline events. Between them, they patrol nearby roads. Perception: a vision cone (40 m, narrowed at night),
     sniffing (a 15 m radius that ignores line of sight but is halved if the player is crouched in vegetation or more than 6 m off the road), and a fear aura (8 m: player movement slows, screen desaturates, heartbeat audio hook).
     States: patrol → sniff (stop, head scan, 6 s) → approach → interrogate.
  2. If caught (interrogate): a scripted fearful exchange (not via the LLM, to keep it menacing and reliable), then soft failure:
     the player faints, `WorldClock.advance(120–360)`, the "Black Breath" debuff (stamina −50% for 12 h), a Shire rumour "<player> was found senseless on the road", and in rare cases (non-hobbit origin) robbery.
     Being a hobbit makes the rider's questioning about "Baggins" more intense.
  3. Hiding: vegetation volumes (hedges, forests, reeds) give a `concealment` value. HUD eye icon: hidden / seen / sniffed.
- **Verify:** GUT: the perception maths (concealment, night, crouch, off-road) for 10 table cases. Soft failure applies the time, debuff and rumour. Scene test: put the player 10 m off the road crouched in bushes as a rider passes → not detected; standing on the road → detected.
- **Done when:** the tests pass.

### M1-T12 — Survival, skills, reputation, inventory, foraging
- **Depends on:** M1-T09
- **Steps:**
  1. `player/survival.gd`: `hunger` (0–100, drops ~30 per game day, hobbits faster: "six meals a day" and a mood bonus when fed on time) and `fatigue`
     (rises with time awake and running; sleep in beds, inns or a camp. Sleeping uses `WorldClock.advance`). Effects at thresholds: slower stamina regen, then slower movement, then fainting (soft failure).
  2. `player/skills.gd`: `stealth`, `woodcraft`, `lore`, `persuasion`, `healing`, `swordplay` (unused in M1). 0–100 hidden XP each. Raised by doing (stealth = time hidden near a threat, woodcraft = foraging, lore = talking about history and reading signposts, persuasion = successful requests via intents).
     Thresholds unlock effects (woodcraft 30: spot mushrooms from 2× the distance, etc.) and add "player skill" lines to the NPC prompt.
  3. `player/inventory.gd` + Tab UI: a weight limit, food items, money (silver pennies), gifts. Items are defined in `content/items/`.
  4. Foraging: mushroom and berry nodes placed by `place_world.py` (Maggot's fields are off-limits: his dogs plus reputation loss if you're caught), regrowing after 2–4 days.
  5. `sim/factions.gd`: reputation `shire`, `bree`, plus per-NPC disposition. Changed by intents, theft, helping, and rumours about you.
  6. Trading at inns and farms: a simple buy/sell UI. Prices in `content/items/`.
- **Verify:** GUT covers: hunger over 3 days, sleeping advances the clock and resets fatigue, XP thresholds, weight limit, regrowth timing, and the reputation effect of being caught in Maggot's fields.
- **Done when:** the tests pass. HUD capture showing hunger, fatigue, the eye icon and the date.

### M1-T13 — Dialogue UI, portraits, rumour network
- **Depends on:** M1-T10, M1-T12, M0-T10
- **Steps:**
  1. Install mflux (§2; check disk first). `tools/art/portraits.py`: one portrait per named NPC (and 6 per villager template) in the style frame's style, using a
     fixed style prompt prefix from `tools/art/style.txt` + a per-character description from `characters/looks.json` and the lore card. Fixed seeds, 768×768 → `game/assets/portraits/`.
     The Black Rider portrait is a hood with darkness inside, no face. Also: journal and inventory UI textures, a parchment background, and an illustrated map of the region from the control map (img2img or a styled render).
  2. `ui/dialogue/`: pauses the clock (pause reason `&"dialogue"`), portrait left, streamed speech with a typewriter effect, numbered option buttons (1–4) and a "Say something else…" LineEdit, and a subtle "thinking" indicator until the first chunk.
     The player's turn shows in the log. Esc or an `end_conversation` intent closes it, which triggers the memory summary in the background.
  3. Offline badge plus fallback mode when `LLMGateway.is_available()` is false.
  4. `sim/rumour_network.gd`: rumours have a strength and spread between settlements along the road graph each game day (probability from strength and distance; travellers on the road carry them).
     NPCs in a settlement where a rumour is present get it in their prompt. Spreadable facts from player conversations become rumours with origin = that NPC's settlement.
  5. Journal (J): heard rumours, met NPCs with a one-line memory each, and the current date.
- **Verify:**
  - Contact sheet of all portraits (open it and check the style is consistent and each character recognisable). Regenerate failures with a new seed (max 3 tries, then flag).
  - GUT: the rumour spread simulation over 10 days with a fixed RNG seed reaches Bree from Hobbiton within the expected days. The dialogue UI scene test drives MockTransport and ends with the memory saved.
  - Live scripted session `tools/talk.sh` + an in-game capture of the dialogue panel mid-stream. Probes saved to `docs/reports/m1_dialogue.md`:
    1. Gaffer on 09-24: talks about the rider who asked for Mr. Baggins the night before.
    2. Butterbur on 09-20: has never heard of riders.
    3. Tell Maggot something memorable, then talk to Mrs Maggot two days later in the same farmstead → she has heard it (rumour) or Maggot mentions it.
    4. Strider at the Pony on 09-29: guarded and watchful, doesn't reveal that he's Aragorn to a stranger.
    5. Gandalf (if met on 09-29/30): urgent and brief, asks about Frodo.
- **Done when:** all of the above pass.

### M1-T14 — Day/night, weather, streaming and performance pass
- **Depends on:** M1-T06
- **Steps:**
  1. `world/weather_daynight.gd`: the sun and moon follow `WorldClock` (night is actually dark but readable: moonlight, lanterns in villages, inn windows glowing).
     Weather states (clear, overcast, light rain, fog over the Brandywine at dawn), changed by a seeded schedule per day with smooth transitions. Rain affects concealment (+) and the fear aura (more menace).
  2. Performance: profile with Godot's profiler and monitors. Enable occlusion culling (bake occluders for buildings), check shadow cascade distances, foliage density scaling, and impostors for far trees.
     `config/game.json` quality presets; the default is tuned to hit the target on this Mac.
  3. Benchmarks: `flyover_full`, `walk_hobbiton_to_bree` (accelerated walk along the road at 4× speed), `night_rain_bree`.
- **Verify:** captures at the same spot at 06:00, 12:00, 19:00 and 23:00, plus in rain and fog (open and check). All 3 benchmarks: average ≥ 60 fps, 1% low ≥ 45, memory < 6 GB.
- **Done when:** the benchmarks pass. Record the numbers.

### M1-T15 — Audio
- **Depends on:** M1-T14
- **Steps:**
  1. CC0 effects (§2; record the source + licence of every file in `assets_src/MANIFEST.md`): footsteps per surface (grass, dirt, wood, stone), wind, birds by day, crickets by night, rain, river, inn crowd murmur, door, rider screech (process a CC0 scream/horse sound with pitch and reverb in a Python/SoX pipeline if needed), heartbeat.
  2. `audio/ambience.gd`: layers by location (settlement, field, river, forest edge), time of day and weather.
  3. Procedural music: `tools/audio/compose.py` renders short, loopable layered stems (drone pad, harp arpeggio, flute melody, fiddle for inns, low strings for danger)
     in D/G modal scales, rendered to OGG with numpy synthesis and simple additive/FM instruments. Then install MusicGen (§2; check disk first) and generate
     8–12 cues ("gentle pastoral folk tune, flute and harp, Celtic, peaceful village", "tense low strings, ominous, dark rider approaching", "lively tavern fiddle jig") at 30 s each. Trim to loops, normalise loudness (−16 LUFS), and convert to OGG.
  4. `audio/music_director.gd`: chooses cues by region, settlement, time and threat level (from rider perception states). Crossfades. Rider proximity gives the danger stem a priority override.
- **Verify:** headless GUT for the director state machine (inputs → chosen cue). Audio files are present with licences. Make a 60 s gameplay recording via
  `godot --write-movie build/m1_audio.avi` (or the movie-maker mode in the installed version) along `walk_hobbiton_to_bree`, then use ffmpeg to check that there are no clipping peaks (`ffmpeg -i ... -af volumedetect`): max_volume < 0 dB.
- **Done when:** the tests pass. 📝 **REVIEW ITEM:** listen to `build/m1_audio.avi` (copy it to `docs/reports/m1_audio/`).

### M1-T16 — Menus, save/load integration
- **Depends on:** M1-T13
- **Steps:** a main menu (New, Continue, Load, Settings, Quit). Settings: time mode A/B, clock speed, quality preset, mouse sensitivity, text speed. The pause menu has Save and Load (manual slots), plus autosave on sleep and region-zone change.
  The saved state covers everything: clock, timeline (fired, held, delays), WorldState, NPC memories, rumours, survival, skills, the player transform and the weather seed.
- **Verify:** GUT/scene test: play 2 scripted in-game days (teleport, talk with MockTransport, forage, get caught by a rider), save, quit, load → deep equality of the serialised state, and the next timeline event fires at the same time as in a run with no reload.
- **Done when:** the test passes.

### M1-T17 — M1 acceptance
- **Depends on:** all M1 tasks
- **Steps:**
  1. `docs/reports/m1_acceptance.md`, run by you: the automated suite (`tools/verify.sh`), all benchmarks, and a scripted "canon run" in mode A at 60× clock with no player interaction from 09-20 to 10-06 (timeline events fire in canon order; the party leaves the east edge on 09-30, and so on).
  2. A user playtest checklist (for the user to do): create a Bucklander, reach Bree before 09-29, witness the party's arrival, talk to Strider, get sniffed by a rider on the road, sleep at the Pony, and check that Butterbur remembers you the next day. And a Breelander in mode B who never goes west: the party waits.
- **Done when:** the automated parts pass. Put the user playtest checklist in `REVIEW.md` as a 📝 **REVIEW ITEM**. Then write `docs/plans/M2.md` (§9) and start M2 straight away.

---

## 6. `tools/verify.sh` (final shape by the end of M1)
1. `.venv/bin/python tools/content/validate.py`
2. `.venv/bin/python tools/content/test_validate.py`
3. `tools/test.sh` (GUT, excluding live LLM tests unless `LIVE_LLM=1`)
4. `godot --headless --path game --import` with no `ERROR` lines (grep the output)
5. `godot --headless --path game --quit-after 300` boots the main menu and prints `BOOT_OK`
6. `.venv/bin/python tools/blender/check_budget.py` (only reads the generated assets; it doesn't rebuild them)

Benchmarks and captures are **not** in `verify.sh` (they need a window). Run them in the tasks that require them.

## 7. Performance budget (M1)
| Item | Budget |
|---|---|
| Frame time | ≤ 16.6 ms avg, ≤ 22 ms 1% low at 2560×1440 |
| Memory | < 6 GB process |
| Draw calls | < 3000 in the densest view (Hobbiton overview) |
| Tree LOD0 / house LOD0 / prop / character | ≤ 3k / 8k / 1k / 12k tris |
| Streaming radius | buildings and props 768 m, collision 128 m, NPC bodies 600 m |

## 8. Risks and fallbacks
| Risk | Fallback |
|---|---|
| Terrain3D incompatible with the installed Godot version | Pin Godot to the newest version Terrain3D supports. If impossible, use chunked MeshInstance3D terrain generated from the heightmap by a Python/Blender script |
| Quaternius retargeting looks broken on hobbit proportions | Scale the whole skeleton uniformly for hobbits and only adjust the mesh (head, feet), keeping the animations unchanged |
| mflux results inconsistent | Lock the seed per character, keep a single style prefix, and use img2img from a Blender render of the character's model for consistency |
| LLM latency > 4 s to first token | Show the thinking indicator, shorten the dynamic block, move more content into cached parts, drop the `standard` tier to a faster model in `llm.json` |
| The model breaks the wire format | The parser tolerates it. Add one retry with "Reformat your last reply" for a missing META. Count the failures in the LLM log |
| Quaternius packs can't be downloaded automatically | Build base humanoids procedurally in Blender (metaball/skin-modifier body → remesh → Rigify human metarig → auto-weights). Make the walk/idle/talk animations procedurally (keyframed scripts). Simpler, but rigged and consistent. Swap in Quaternius later by re-running `build_bases.py` |
| 16 GB memory pressure | Never run Blender, mflux or MusicGen while the game runs. Lower the foliage density preset |

## 9. Later milestones (outline: detailed plan written before each starts)

Before starting milestone N, write `docs/plans/M<N>.md` using the same task template (Depends on / Steps / Verify / Done when, with 📝 review items),
then start it. Don't wait for approval. Each must end with an acceptance task like M1-T17.

- **M2 — Into the Wild:** Travel-map layer (Bree → Weathertop → the Last Bridge → the Trollshaws → the Ford of Bruinen → Rivendell) with encounters, camps and weather.
  Character switching (Frodo, Sam, Merry, Pippin, Aragorn): the input and camera handover, and the off-screen sim taking over the vacated character.
  **Ring corruption** (Frodo as bearer: putting the Ring on shows the wraith world; corruption changes perception, NPC prompts and choices). Horses (Bill the pony, the Black Riders mounted).
  The first anchors: **Weathertop** (scripted encounter, variables: who is wounded and how badly) and the **Council of Elrond**. The Rivendell region (seamless). Elf origin (Rivendell)
  and Dwarf origin (arriving with Glóin). Fleeing combat → simple combat (torches and swords against the wraiths).
- **M3 — The Fellowship's Road:** Eregion/Hollin, Caradhras, Moria (interior streaming, darkness), Lothlórien, the Anduin by boat (travel layer), Amon Hen. The rest of the Fellowship on the roster.
  Anchors: Moria/Balrog, Amon Hen. Boromir's corruption arc. Hero creatures (the Watcher, the Balrog), the hardest Blender test; fall back to a stylized silhouette with effects if needed.
- **M4 — Rohan & Isengard:** Rohan origin. Éowyn and Théoden on the roster. Fangorn, Edoras, Helm's Deep, Isengard. Anchors: Helm's Deep (a simple mass battle via crowd impostors + scripted beats), the Fall of Isengard.
- **M5 — Gondor, Ithilien & Mordor:** Gondor origin. Faramir and Gollum/Sméagol on the roster. Minas Tirith, Osgiliath, Ithilien, Cirith Ungol, the Morgul Vale, Mordor. Anchors: Pelennor, the Black Gate, Mount Doom. **Bad endings** (Ring lost, or claimed by the bearer).
- **M6 — Return:** The Scouring of the Shire, driven by accumulated reputation, memories and rumours, then the Grey Havens and the Fourth Age free-roam epilogue.
