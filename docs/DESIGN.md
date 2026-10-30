# Middle-earth: An Open-World Life Simulator — Design

Personal-use project. It will never be published. Canon names, places, quotes and maps are used freely.

This file holds the **settled decisions**. Do not change them while implementing. If one looks wrong,
follow it anyway and log your concern in `docs/REVIEW.md` for the user's end-of-project review. The step-by-step build instructions are in `docs/PLAN.md`.

## 1. Vision

A stylized 3D, third-person open world spanning the War of the Ring (Third Age 3018–3019) across all of
Middle-earth. You live the story as your own character *and* can step into key canon characters at any
time. Code owns the truth (world state, timeline, inventory). An LLM gives NPCs voice, memory and
lore-faithful personality.

## 2. Settled decisions

| Area | Decision |
|---|---|
| Audience | Personal use only |
| Presentation | 3D, stylized (painterly / low-poly), third-person camera |
| Engine | Godot 4 (latest stable ≥ 4.4, native Metal renderer, Jolt physics), GDScript with static typing |
| Target hardware | This Mac only: Apple M5, 16 GB unified memory. Target 60 fps average at 2560×1440 |
| Input | Keyboard + mouse |
| Player identity | Your original character **plus** switching to canon characters at any time |
| Switch roster | Fellowship of nine + Éowyn, Faramir, Théoden, Gollum/Sméagol. Living characters only |
| Off-screen characters | Simulated abstractly on the world clock, following canon itineraries. They deviate only while you control or meet them |
| Canon flexibility | Soft canon: anchor events always happen, but their details and survivors bend to your actions |
| Losing the war | Possible only through the Ring-bearer's corruption or the Ring being lost / captured |
| Time | World clock. Mode chosen at new game and changeable in settings: **A = never waits**, **B = major events wait for the player within a window** |
| World structure | Hybrid: neighbouring regions join seamlessly; long journeys use a travel-map layer (encounters, weather, camps, time passing) |
| Scope | Whole War of the Ring, all of Middle-earth, built milestone by milestone |
| Anchors | Weathertop, Council of Elrond, Moria/Balrog, Amon Hen, Helm's Deep, Fall of Isengard, Pelennor Fields, Black Gate, Mount Doom |
| Ending | Ring destroyed → Scouring of the Shire → Grey Havens → Fourth Age free-roam epilogue |
| Character creation | Race + origin + background. Each origin has its own start location, from late Sept 3018 |
| Progression | No levels. Use-based skills, faction reputation, survival needs, inventory |
| Ring corruption | Mechanic for any bearer: changes what you see, what NPCs say to you, and which choices you get |
| Combat | Light. Mostly avoidance and stealth. Fights are rare and simple or scripted |
| Failure | Soft: wounded, captured, robbed, left for dead (costs time, items, reputation). Death only in telegraphed lethal moments. Manual saves + autosave |
| Dialogue | Pauses the world. Panel with NPC portrait. 3–4 generated options + free-text "say something else". Text only (no voice acting) |
| LLM role | NPC dialogue, narration, memory summaries. **Never authoritative over game state** |
| LLM provider | **OpenRouter** (OpenAI-compatible API). Tiers: `key_figure` (Opus-class), `standard` (Sonnet-class), `summariser` (Sonnet-class or cheaper) |
| Lore fidelity | Curated lore cards with knowledge filtered by date (each NPC only knows what it would know *as of the current game date*). Game state overrides everything |
| NPC memory | Per-NPC memory summary updated after each conversation, plus rumours that spread between settlements over time |
| Offline | Fall back to authored lines from the lore cards. Gameplay never needs the network |
| Assets | All generated locally: Blender scripted from Python in the background + Quaternius CC0 bases + mflux (Flux on MLX) for 2D art |
| Audio | CC0 sound effects + procedural / code-composed music layers + local AI music (MusicGen on MLX) |

## 3. Core rules for the architecture

1. **Single source of truth.** `WorldState` holds every entity, location, flag and inventory. Nothing else stores
   gameplay truth. The save file is a serialisation of `WorldState` + `WorldClock` + `Timeline` + NPC memories.
2. **The LLM proposes, the game decides.** NPC replies contain prose plus *suggested intents* (`give_item`,
   `share_rumour`, ...). Every intent is checked against `WorldState` before it is applied; invalid ones are dropped silently.
3. **Knowledge filtered by date.** Each knowledge entry on a lore card has `known_from` (and an optional `requires_flag`).
   The prompt only contains entries that are true now.
4. **Content is data.** Characters, events, itineraries, regions and fallback lines live in JSON under
   `game/content/`, are validated against JSON Schemas, and are never hard-coded in scripts.
5. **The timeline drives the world.** Canon happens through timeline events and character itineraries on the clock.
   In mode B, events flagged `waits_for_player` hold within their window, and later dependent events shift by the same delay.
6. **On-screen and off-screen are the same character.** A roster character always has an abstract position on the
   road graph. When the player is near, a 3D body is spawned at that position. When the player leaves, the body is
   despawned and the abstract simulation continues.
7. **Generation tools never run alongside the game.** Blender, mflux and MusicGen are offline build tools. Their
   outputs are committed (via Git LFS). The game never calls them.
