# Handoff: portraits and UI art (for Antigravity / Gemini)

Local image generation was dropped: FLUX.1-schnell is gated on Hugging Face and the owner has no account; Z-Image-Turbo (mflux) was
started and abandoned. The art is produced with Gemini's image generation instead. This replaces the mflux step of M1-T13 in `docs/PLAN.md`.

Read first: `CLAUDE.md`, `docs/DESIGN.md` (settled, do not change; log concerns in `docs/REVIEW.md`). Never write API keys to files.
Do not touch GDScript, Blender or terrain files. This job only adds images, one generator note and a PROGRESS/LOCAL_TODO update.

## What to produce

All files are PNG, 768x768, opaque, bust/head-and-shoulders, face centred and not cropped (the dialogue panel shows them square at ~320 px with
`STRETCH_KEEP_ASPECT_COVERED`). Put them in `game/assets/portraits/`.

### 1. Named NPC portraits: 17 files, filename = `<id>.png`
The ids are the lore-card ids in `game/content/lore_cards/characters/`; the dialogue panel loads `res://assets/portraits/<npc_id>.png`.
Use each card's `race`, `voice` and `personality` for the face and expression. Costume and colours should match the 3D models: see
`docs/reports/m1_characters/contact_sheet.png` and `lineup.png`.

| id | who |
|---|---|
| frodo, sam, merry, pippin, fatty_bolger | hobbits (Frodo is fifty, thoughtful; Sam is a sturdy gardener; Fatty is round and cheerful) |
| gaffer_gamgee, farmer_maggot, mrs_maggot, lobelia_sackville_baggins, nob | older Shire/Bree hobbits |
| barliman_butterbur, bill_ferny, strider | Men of Bree; Strider is a weathered Ranger in a patched hood, guarded, no hint of royalty |
| gandalf | Gandalf the Grey, grey hat and cloak, bushy brows, urgent expression |
| gildor_inglorion | High Elf, starlight, calm |
| black_rider_khamul, black_riders_group | **no face**: a black hood with only darkness inside, a hint of a pale cold mist; the group version shows several hooded shapes |

### 2. Villager portraits: 18 files
Three templates in `game/content/lore_cards/templates/`: `shire_hobbit_villager`, `bree_hobbit_villager`, `bree_villager`.
Six distinct faces each (mix of age, sex, hair; use the palettes in `game/content/appearance.json`), named `<template_id>_1.png` ... `<template_id>_6.png`.
(Claude will wire the lookup later; the panel currently only knows `<npc_id>.png`.)

### 3. UI textures (optional, after 1 and 2)
`game/assets/ui/parchment.png` (1024x1024 seamless-ish aged parchment, no text), `journal_page.png`, `inventory_panel.png`,
and `game/assets/ui/region_map.png` (illustrated hand-drawn map of the region, 2048x1024, based on `docs/reports/eriador_west_control.png`; keep the
Shire on the left, Bree on the right, East Road across the middle, Brandywine in between).

## Style (use one fixed style prefix for every image and keep it in `tools/art/style.txt`)
Warm, hand-painted storybook illustration, soft cel-shaded shading with a slightly textured paper feel, golden-hour light, muted earthy palette
(greens #5aa832 / #2c6a26, wheat #c2b040, brown #8c6c48, slate for Bree). Cosy, grounded and a little melancholy; not photoreal, not anime, not
glossy fantasy-poster. Plain softly vignetted background (warm for the Shire, cooler and darker for Bree). Fixed framing for all portraits.
Tolkien book-canon looks (not film actors; no likenesses of real people).

Consistency matters more than any single image: generate Frodo first, then pass an approved portrait as a reference image when generating the next,
and keep the prefix word-for-word. Record the exact prompt of every file in `tools/art/prompts.json` (`{ "<filename>": "<prompt>" }`) so a
failed one can be regenerated. Max 3 retries per image; if still bad, keep the best and say so in `docs/REVIEW.md`.

## Check before finishing
1. Build a contact sheet (Pillow; `.venv/bin/python`) of all portraits into `docs/reports/m1_portraits/contact_sheet.png`, open it, and check the set looks like one
   style and each character is recognisable (the Black Rider has no face).
2. `tools/verify.sh` must still pass (except the known `test_place_world` sync failure described in `docs/REVIEW.md`). The content validator's
   "portrait file missing" WARN lines should disappear for the 17 named NPCs.
3. Run `godot --headless --path game --import` so the PNGs get `.import` files, and commit the `.import` files with the images.
4. Tick this off in `docs/PROGRESS.md` (M1-T13 notes) and remove the portraits/UI-texture lines from `docs/LOCAL_TODO.md`.
5. Do not use LFS: `.gitattributes` already exempts `game/assets/**`.
6. Commit with a message like `M1-T13: portraits and UI art`.

## Still blocked / not part of this handoff
Live LLM probes (need `OPENROUTER_API_KEY`), MusicGen cues, audio auditioning and scene wiring remain in `docs/LOCAL_TODO.md`.
The leftover Z-Image weights (6.4 GB) are in `~/.cache/huggingface/hub/models--Tongyi-MAI--Z-Image-Turbo`; safe to delete. `.venv-art/` is
git-ignored and can be deleted too.
