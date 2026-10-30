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
