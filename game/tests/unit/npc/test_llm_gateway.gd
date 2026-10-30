extends GutTest

const GatewayScript: GDScript = preload("res://autoload/llm_gateway.gd")

var gw: Node
var mocks: Array[MockTransport] = []
var scripts: Array = []  ## per-call config: {script, fail_with, stall, synchronous}
var chunks: Array[String] = []
var result: Dictionary = {}
var signals_seen: Array[bool] = []


func before_each() -> void:
	gw = GatewayScript.new()
	gw.api_key_override = "test-key"
	gw.log_enabled = false
	gw.transport_factory = _make
	add_child_autofree(gw)
	mocks.clear()
	scripts.clear()
	chunks.clear()
	result = {}
	signals_seen.clear()
	EventBus.llm_availability_changed.connect(_on_avail)


func after_each() -> void:
	EventBus.llm_availability_changed.disconnect(_on_avail)


func _on_avail(v: bool) -> void:
	signals_seen.append(v)


func _make() -> LLMTransport:
	var m := MockTransport.new()
	var cfg: Dictionary = scripts[mocks.size()] if mocks.size() < scripts.size() else (scripts.back() if not scripts.is_empty() else {})
	var s: Array[String] = []
	s.assign(cfg.get("script", []))
	m.script = s
	m.fail_with = cfg.get("fail_with", "")
	m.stall = cfg.get("stall", false)
	m.synchronous = cfg.get("synchronous", true)
	mocks.append(m)
	return m


func _ask(msgs: Array = [{"role": "user", "content": "hi"}]) -> void:
	gw.request("standard", msgs, func(t: String) -> void: chunks.append(t), func(r: Dictionary) -> void: result = r)


func _good() -> Dictionary:
	return {"script": [MockTransport.delta("Hel"), MockTransport.delta("lo"), MockTransport.sse("[DONE]")]}


func test_chunk_assembly_and_done() -> void:
	scripts = [{"script": [
		": OPENROUTER PROCESSING\n\n",
		MockTransport.delta("Hel"), MockTransport.delta("lo "),
		MockTransport.sse({"choices": [{"delta": {"content": "world"}}], "usage": {"prompt_tokens": 5, "completion_tokens": 2}}),
		MockTransport.sse("[DONE]"),
		MockTransport.delta("IGNORED?"),
	]}]
	_ask()
	assert_true(result["ok"])
	assert_eq(result["text"], "Hello worldIGNORED?", "mock keeps replaying; gateway only stops at stream end")
	assert_eq(chunks.slice(0, 3), ["Hel", "lo ", "world"])
	assert_eq(result["usage"]["completion_tokens"], 2)


func test_split_lines_across_chunks() -> void:
	var raw: String = MockTransport.delta("ab") + MockTransport.delta("cd") + MockTransport.sse("[DONE]")
	scripts = [{"script": [raw.substr(0, 13), raw.substr(13, 20), raw.substr(33)]}]
	_ask()
	assert_eq(result["text"], "abcd")


func test_mid_stream_error() -> void:
	scripts = [{"script": [MockTransport.delta("par"), MockTransport.sse({"error": {"message": "upstream died"}})]}]
	_ask()
	assert_false(result["ok"])
	assert_eq(result["text"], "par")
	assert_string_contains(result["error"], "upstream died")
	assert_eq(mocks.size(), 1, "no retry once data has arrived")


func test_transport_failure_retries_once() -> void:
	scripts = [{"fail_with": "network_error:1"}, _good()]
	_ask()
	assert_eq(mocks.size(), 2)
	assert_true(result["ok"])
	assert_eq(result["text"], "Hello")


func test_timeout() -> void:
	scripts = [{"stall": true, "synchronous": false}]
	gw.request("standard", [], func(_t: String) -> void: pass, func(r: Dictionary) -> void: result = r)
	gw.tick(1.0)
	assert_true(result.is_empty())
	gw.tick(30.0)
	assert_false(result["ok"] if not result.is_empty() else true)
	assert_eq(result.get("error", ""), "timeout")


func test_availability_flag() -> void:
	assert_true(gw.is_available())
	scripts = [{"fail_with": "boom", "script": [MockTransport.delta("x")]}]  # data seen -> no retry
	_ask()
	assert_true(gw.is_available(), "one failure is not enough")
	_ask()
	assert_false(gw.is_available())
	assert_eq(signals_seen, [false])
	# unavailable: requests fail fast without touching the transport
	var n: int = mocks.size()
	_ask()
	assert_eq(result["error"], "unavailable")
	assert_eq(mocks.size(), n)
	# re-probe after 5 minutes
	gw.tick(299.0)
	assert_false(gw.is_available())
	gw.tick(2.0)
	assert_true(gw.is_available())
	assert_eq(signals_seen, [false, true])
	# one more failure re-trips immediately
	_ask()
	assert_false(gw.is_available())
	# success resets
	gw.tick(301.0)
	scripts = [_good()]
	_ask()
	assert_true(result["ok"])
	_ask()
	assert_true(gw.is_available())


func test_no_key_unavailable() -> void:
	gw.api_key_override = ""
	if OS.get_environment("OPENROUTER_API_KEY").is_empty():
		assert_false(gw.is_available())
		_ask()
		assert_false(result["ok"])
		assert_eq(result["error"], "unavailable")
	else:
		pass_test("env key present")


func test_cache_control_parts() -> void:
	scripts = [_good()]
	var msgs: Array = [
		{"role": "system", "content": [
			{"type": "text", "text": "lore", "cache": true},
			{"type": "text", "text": "dynamic"},
		]},
		{"role": "user", "content": "plain"},
	]
	_ask(msgs)
	var body: Dictionary = JSON.parse_string(mocks[0].last_body)
	var parts: Array = body["messages"][0]["content"]
	assert_eq(parts[0]["cache_control"], {"type": "ephemeral"})
	assert_false(parts[0].has("cache"))
	assert_false(parts[1].has("cache_control"))
	assert_eq(body["messages"][1]["content"], "plain")
	assert_true(body["stream"])
	assert_true("Authorization: Bearer test-key" in mocks[0].last_headers)


func test_live_pong() -> void:
	if OS.get_environment("LIVE_LLM") != "1":
		pending("LIVE_LLM=1 not set")
		return
	var live: Node = GatewayScript.new()
	live.log_enabled = false
	add_child_autofree(live)
	var out: Dictionary = {}
	live.request("standard", [{"role": "user", "content": "Reply with exactly: PONG"}], func(_t: String) -> void: pass, func(r: Dictionary) -> void: out = r)
	var waited: float = 0.0
	while out.is_empty() and waited < 40.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	assert_true(out.get("ok", false), str(out))
	assert_string_contains(out.get("text", ""), "PONG")
	gut.p("live latency_ms=%s" % out.get("latency_ms"))
