# Work left for the local (Mac) session

Everything here could not be done in the cloud container (Linux, no GPU, no display, restricted network).
Each entry names the plan task and what to run. Keep this list current as tasks are finished or deferred.

## M0-T09 live LLM checks (needs OPENROUTER_API_KEY, unblocked network)
1. `.venv/bin/python tools/llm/list_models.py`, pick newest Opus-class (key_figure) and Sonnet-class (standard, summariser) slugs, write to `game/config/llm.json`.
2. `LIVE_LLM=1 tools/test.sh` -> the PONG test must pass; record the latency in PROGRESS.md.
3. Confirm `cache_control` part format and `usage: {include: true}` against current OpenRouter docs; HTTPSSETransport has never hit a real server.
