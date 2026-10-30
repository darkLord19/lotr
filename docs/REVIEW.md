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
