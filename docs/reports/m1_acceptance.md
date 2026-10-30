# M1 acceptance (cloud session, Linux x86_64, no GPU, no audio device, no OpenRouter access)

## Automated suite
`tools/verify.sh` exits 0 (run ~100 s):
- GUT: 346 tests, 345 pass, 1 pending (live LLM PONG probe, needs `LIVE_LLM=1`), 0 fail
- `validate.py`: `CONTENT_OK` (only missing-portrait warnings), `check_region.py`: `REGION_OK`
  (Bag End -> Prancing Pony 7283 m = 86.7 min at 1.4 m/s)
- pytest: content (28), dialogue fallbacks, terrain heightfield, place_world (15), audio assets (59)
- `BUDGET_OK: 106 assets, 6.7 MB`, `CHARACTERS_OK 20 glbs`, boot check prints `BOOT_OK`

## Canon run (mode A, no player interaction, 3018-09-20 -> 10-07)
`game/tests/unit/sim/test_canon_run.gd` (5 tests, real content + Timeline + OffscreenSim): all events fire in time order and none is
left pending, `party_arrives_pony` fires on the evening of 09-29, the raids fall in the small hours of 09-30, `frodo_off_map` fires 09-30 or
later and `weathertop_attack` (rumour only) follows it. Also `test_offscreen_sim.gd`: the Frodo party is within 50 m of the canon POI at
every step time 09-23..09-30, Khamul at bagshot_row 09-23 19:00, and mode B holds the party at `bree_waiting_point` until the player enters Bree.
The 60x real-time-clock canon run through a rendered scene is **not** done (needs the Mac; see LOCAL_TODO).

## What was NOT verified here (see docs/LOCAL_TODO.md for how to finish each)
- Performance: no GPU, so no fps/memory benchmarks (`flyover_full`, `walk_hobbiton_to_bree`, `night_rain_bree`).
- Live LLM behaviour and the 5 dialogue probes; real model slugs; portraits (mflux).
- Audio by ear; real CC0 effects and MusicGen cues.
- Terrain3D (chunked-mesh fallback used instead).
- NPC bodies are not yet spawned from the off-screen sim in the 3D world (logic and `NPCBody` exist), riders have no 3D scene yet,
  HUD (hunger/fatigue/eye icon) and trading UI are not built.
- Captures (software-rendered): docs/reports/m1_terrain, m1_style, m1_characters, m1_player, m1_dialogue, m1_menus, m1_daynight, m1_creation.

## User playtest checklist
1. Create a Bucklander, reach Bree before 09-29, witness the party's arrival, talk to Strider, get sniffed by a rider on the road,
   sleep at the Pony, check that Butterbur remembers you the next day.
2. Create a Breelander in mode B who never goes west: the party waits at the West-gate approach.
3. Save/load mid-journey; relaunch and Continue.
