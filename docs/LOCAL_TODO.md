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
