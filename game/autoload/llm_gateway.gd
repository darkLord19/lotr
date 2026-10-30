extends Node
## OpenRouter streaming gateway. Never authoritative over game state.
##
## request(tier, messages, on_chunk, on_done) -> int
##   on_chunk: Callable(text: String)         per streamed text delta
##   on_done:  Callable(result: Dictionary)   {ok, text, error, tier, model, usage, latency_ms}
## With a synchronous MockTransport the callbacks fire inside request(), so tests read text immediately.

const DONE_MARKER: String = "[DONE]"
const LOG_PATH: String = "user://logs/llm.jsonl"

var transport_factory: Callable = Callable()  ## returns an LLMTransport; default = real HTTP
var api_key_override: String = ""  ## tests only; the real key comes from the environment
var log_enabled: bool = true

var _available: bool = true
var _consecutive_failures: int = 0
var _since_failure_s: float = 0.0
var _active: Dictionary = {}  ## id -> request state
var _next_id: int = 1


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	tick(delta)


func has_key() -> bool:
	return not _api_key().is_empty()


func is_available() -> bool:
	return has_key() and _available


func request(tier: String, messages: Array, on_chunk: Callable, on_done: Callable) -> int:
	var id: int = _next_id
	_next_id += 1
	var model_cfg: Dictionary = Config.get_value("tiers.%s" % tier, {})
	var st: Dictionary = {
		"id": id, "tier": tier, "model": model_cfg.get("model", ""), "text": "", "usage": {},
		"on_chunk": on_chunk, "on_done": on_done, "elapsed_s": 0.0, "retries_left": int(Config.get_value("retries", 0)),
		"messages": messages, "got_data": false, "error": "", "stream_error": "", "finished": false,
		"start_ms": Time.get_ticks_msec(), "transport": null,
	}
	if model_cfg.is_empty():
		_complete(st, false, "unknown_tier:%s" % tier, false)
		return id
	if not is_available():
		_complete(st, false, "unavailable", false)
		return id
	_active[id] = st
	_start_attempt(st)
	return id


func cancel(id: int) -> void:
	if _active.has(id):
		var st: Dictionary = _active[id]
		(st["transport"] as LLMTransport).cancel()
		_active.erase(id)


# Drives transports and timeouts. Called from _process; tests call it manually with fake deltas.
func tick(delta: float) -> void:
	for id in _active.keys():
		var st: Dictionary = _active.get(id, {})
		if st.is_empty() or st["finished"]:
			continue
		st["elapsed_s"] += delta
		(st["transport"] as LLMTransport).poll()
		if st["finished"]:
			continue
		if st["elapsed_s"] > float(Config.get_value("timeout_s", 25)):
			(st["transport"] as LLMTransport).cancel()
			_on_transport_finished(st, false, "timeout")
	if not _available and has_key():
		_since_failure_s += delta
		if _since_failure_s >= float(Config.get_value("reprobe_s", 300.0)):
			# Let the next request act as the probe; one more failure re-trips the flag at once.
			_consecutive_failures = 1
			_set_available(true)


## Message content may be a String or an Array of parts; parts with cache:true gain cache_control.
static func build_messages(messages: Array) -> Array:
	var out: Array = []
	for m: Variant in messages:
		var msg: Dictionary = (m as Dictionary).duplicate()
		var content: Variant = msg.get("content")
		if content is Array:
			var parts: Array = []
			for p: Variant in content:
				var part: Dictionary = (p as Dictionary).duplicate() if p is Dictionary else {"type": "text", "text": str(p)}
				if part.get("cache", false):
					part["cache_control"] = {"type": "ephemeral"}
				part.erase("cache")
				if not part.has("type"):
					part["type"] = "text"
				parts.append(part)
			msg["content"] = parts
		out.append(msg)
	return out


func _start_attempt(st: Dictionary) -> void:
	var cfg: Dictionary = Config.get_value("tiers.%s" % st["tier"], {})
	var body: Dictionary = {
		"model": cfg.get("model", ""), "messages": build_messages(st["messages"]), "stream": true,
		"max_tokens": cfg.get("max_tokens", 400), "temperature": cfg.get("temperature", 0.8),
		"usage": {"include": true},
	}
	var headers := PackedStringArray([
		"Authorization: Bearer " + _api_key(),
		"Content-Type: application/json",
		"X-Title: " + str(Config.get_value("app_title", "Middle-earth")),
	])
	var t: LLMTransport = _make_transport()
	st["transport"] = t
	st["elapsed_s"] = 0.0
	st["stream_error"] = ""
	t.data_received.connect(_on_data.bind(st))
	t.finished.connect(_on_transport_finished.bind(st))
	t.start(str(Config.get_value("endpoint", "")), headers, JSON.stringify(body))


func _on_data(payload: String, st: Dictionary) -> void:
	if st["finished"]:
		return
	st["got_data"] = true
	if payload == DONE_MARKER:
		return
	var parsed: Variant = JSON.parse_string(payload)
	if not (parsed is Dictionary):
		return
	var obj: Dictionary = parsed
	if obj.has("error"):
		var e: Variant = obj["error"]
		st["stream_error"] = str((e as Dictionary).get("message", "stream_error")) if e is Dictionary else str(e)
		return
	if obj.get("usage") is Dictionary:
		st["usage"] = obj["usage"]
	var choices: Variant = obj.get("choices")
	if choices is Array and not (choices as Array).is_empty():
		var delta: Variant = (choices as Array)[0].get("delta", {})
		var piece: Variant = (delta as Dictionary).get("content") if delta is Dictionary else null
		if piece is String and not (piece as String).is_empty():
			st["text"] += piece
			var cb: Callable = st["on_chunk"]
			if cb.is_valid():
				cb.call(piece)


func _on_transport_finished(ok: bool, error: String, st: Dictionary) -> void:
	if st["finished"]:
		return
	if ok and not st["stream_error"].is_empty():
		ok = false
		error = "stream_error:" + st["stream_error"]
	if not ok and not st["got_data"] and st["retries_left"] > 0:
		st["retries_left"] -= 1
		_start_attempt(st)
		return
	_complete(st, ok, error, true)


func _complete(st: Dictionary, ok: bool, error: String, counts_for_availability: bool) -> void:
	st["finished"] = true
	_active.erase(st["id"])
	if counts_for_availability:
		if ok:
			_consecutive_failures = 0
			_set_available(true)
		else:
			_consecutive_failures += 1
			if _consecutive_failures >= 2:
				_since_failure_s = 0.0
				_set_available(false)
	var latency: int = Time.get_ticks_msec() - int(st["start_ms"])
	var result: Dictionary = {
		"ok": ok, "text": st["text"], "error": error, "tier": st["tier"], "model": st["model"],
		"usage": st["usage"], "latency_ms": latency,
	}
	_log(result)
	var cb: Callable = st["on_done"]
	if cb.is_valid():
		cb.call(result)


func _set_available(value: bool) -> void:
	if value == _available:
		return
	_available = value
	EventBus.llm_availability_changed.emit(is_available())


func _make_transport() -> LLMTransport:
	if transport_factory.is_valid():
		return transport_factory.call()
	return HTTPSSETransport.new()


func _api_key() -> String:
	return api_key_override if not api_key_override.is_empty() else OS.get_environment("OPENROUTER_API_KEY")


func _log(result: Dictionary) -> void:
	if not log_enabled:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://logs"))
	var f: FileAccess = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if FileAccess.file_exists(LOG_PATH) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	var row: Dictionary = {
		"ts": Time.get_datetime_string_from_system(true), "tier": result["tier"], "model": result["model"],
		"ok": result["ok"], "error": result["error"], "usage": result["usage"], "latency_ms": result["latency_ms"],
		"chars": (result["text"] as String).length(),
	}
	f.store_line(JSON.stringify(row))
	f.close()
