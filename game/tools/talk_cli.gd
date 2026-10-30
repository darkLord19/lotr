extends Node
## Headless dialogue harness. Run through tools/talk.sh (scene res://tools/talk_cli.tscn: autoloads are not
## available to a bare `-s` script).
##   --npc=<id>        lore card id (required)
##   --date=<date>     game date, "3018-09-29" or "3018-09-29T21:00" (default: config start date)
##   --say=<text>      one player line; repeat for several turns
##   --interactive     read player lines from stdin (a number picks the last options; /quit ends)
##   --mock            use a MockTransport with a canned in-character reply (works offline)
##   --keep-memory     load/save NPC memory in user://talk_memory.json between runs
##   --flag=<name>     set a world flag before talking (repeatable)
##   --race= --origin= description of the player (defaults hobbit / shire)
##   --show-prompt     print the system prompt blocks of the first request
## With no OPENROUTER_API_KEY (or while the gateway is unavailable) the authored fallback lines are used.

const EXIT_BAD_ARGS: int = 2
const MEMORY_PATH: String = "user://talk_memory.json"
const STDIN_BUFFER: int = 4096
const MOCK_CHUNK_CHARS: int = 14
const MOCK_KEY: String = "mock-key"
const VALUE_FLAGS: Array[String] = ["npc", "date", "say", "flag", "race", "origin"]

var _args: Dictionary = {}  ## flag -> String or Array[String]
var _mock: bool = false
var _mock_phase: String = "talk"
var _last_options: Array = []
var _last_speech: String = ""
var _card: Dictionary = {}


func _ready() -> void:
	_run()


func _run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var npc_id: String = _one("npc")
	if npc_id.is_empty():
		printerr("usage: tools/talk.sh --npc=<id> [--date=<date>] [--say=<text>]... [--interactive] [--mock] [--keep-memory]")
		get_tree().quit(EXIT_BAD_ARGS)
		return
	_card = NPCContent.load_card(npc_id)
	if _card.is_empty():
		printerr("unknown npc '%s' (no lore card)" % npc_id)
		get_tree().quit(EXIT_BAD_ARGS)
		return
	var date: String = _one("date", str(Config.get_value("clock.start_date", "3018-09-22T08:00")))
	var now: int = GameDate.parse(date)
	if now == GameDate.INVALID:
		printerr("bad --date '%s'" % date)
		get_tree().quit(EXIT_BAD_ARGS)
		return
	_mock = _args.has("mock")
	if _mock:
		LLMGateway.api_key_override = MOCK_KEY
		LLMGateway.transport_factory = _make_mock
	LLMGateway.log_enabled = not _mock

	_setup_world(npc_id, now)
	if _args.has("keep-memory"):
		_load_memory()

	print("== Talking to %s on %s (%s)" % [_card["name"], GameDate.format_shire(now), GameDate.format_iso(now)])
	if _mock:
		print("[mock] using a canned MockTransport reply; no network is used")
	elif not LLMGateway.is_available():
		var why: String = "no OPENROUTER_API_KEY set" if not LLMGateway.has_key() else "gateway marked unavailable after failures"
		print("[OFFLINE] LLM unavailable (%s): using authored fallback lines from content/dialogue_fallbacks/" % why)
	if _args.has("show-prompt"):
		_print_prompt(npc_id, now)

	var mind := NPCMind.new(npc_id, _card)
	var lines: Array = _many("say")
	if _args.has("interactive"):
		await _interactive(mind, lines)
	else:
		if lines.is_empty():
			lines = [""]
		for line: String in lines:
			if not await _turn(mind, line):
				break
	await _finish(mind)
	get_tree().quit(0)


func _setup_world(npc_id: String, now: int) -> void:
	WorldState.reset()
	WorldClock.now = now
	var home: String = str(_card.get("home_poi", ""))
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", home, "", {
		"name": "Traveller", "race": _one("race", "hobbit"), "origin": _one("origin", "the Shire"), "introduced": false,
	})
	WorldState.spawn_entity(npc_id, "npc", home)
	for item: Variant in _card.get("inventory_can_give", []):
		WorldState.transfer_item(str(item), "", npc_id)
	for f: String in _many("flag"):
		WorldState.set_flag(f)


# Returns false when the NPC ended the conversation.
func _turn(mind: NPCMind, line: String) -> bool:
	if not line.is_empty():
		print("\n> You: %s" % line)
	else:
		print("\n> (you approach)")
	var state: Array = [false, {}]  ## done, turn
	var started: Array[bool] = [false]
	var on_speech: Callable = func(piece: String) -> void:
		if not started[0]:
			started[0] = true
			printraw("%s: " % _card["name"])
		printraw(piece)
	var on_turn: Callable = func(t: Dictionary) -> void:
		state[0] = true
		state[1] = t
	mind.say(line, on_speech, on_turn)
	while not state[0]:
		await get_tree().process_frame
	var t: Dictionary = state[1]
	if not started[0]:
		print("%s: %s" % [_card["name"], t.get("speech", "")])
	else:
		print("")
	var tag: String = "mock" if _mock and t["source"] == NPCMind.SOURCE_LLM else str(t["source"])
	if t["source"] == NPCMind.SOURCE_FALLBACK:
		print("  [source: fallback (%s)]" % t.get("error", ""))
	else:
		print("  [source: %s%s]" % [tag, "" if t["ok"] else ", stream failed: %s" % t["error"]])
	if not (t["mood"] as String).is_empty():
		print("  mood: %s" % t["mood"])
	_last_options = t["options"]
	_last_speech = str(t.get("speech", ""))
	for i in range(_last_options.size()):
		print("  %d) %s" % [i + 1, _last_options[i]])
	for a: Dictionary in t["applied"]:
		print("  intent applied: %s" % JSON.stringify(a))
	for r: Dictionary in t["rejected"]:
		print("  intent REJECTED (%s): %s" % [r["reason"], JSON.stringify(r["intent"])])
	return not t["end_conversation"]


func _interactive(mind: NPCMind, queued: Array) -> void:
	var pending: Array = queued.duplicate()
	if pending.is_empty():
		pending.append("")
	var alive: bool = true
	while alive:
		var line: String
		if not pending.is_empty():
			line = pending.pop_front()
		else:
			printraw("\n[you] ")
			var raw: String = OS.read_string_from_stdin(STDIN_BUFFER)
			if raw.is_empty():
				break
			line = raw.strip_edges()
			if line == "/quit" or line == "/q":
				break
			if line.is_valid_int() and line.to_int() >= 1 and line.to_int() <= _last_options.size():
				line = str(_last_options[line.to_int() - 1])
			elif line.is_empty():
				continue
		alive = await _turn(mind, line)


func _finish(mind: NPCMind) -> void:
	_mock_phase = "summary"
	var done: Array = [false, {}]
	mind.end_conversation(func(r: Dictionary) -> void:
		done[0] = true
		done[1] = r)
	while not done[0]:
		await get_tree().process_frame
	var r: Dictionary = done[1]
	var mem: Dictionary = WorldState.get_npc_memory(str(_card["id"]))
	print("\n== Conversation over")
	if r["ok"]:
		print("New memory (summariser): %s" % r["summary"])
		for l: Dictionary in r["learned"]:
			print("  learned%s: %s" % [" (spreadable)" if l["spreadable"] else "", l["fact"]])
	else:
		print("Memory not updated by a summary (%s). Stored summary: %s" % [r["error"], mem["summary"] if mem["summary"] != "" else "(none)"])
	print("Disposition: %d" % mem["disposition"])
	if _args.has("keep-memory"):
		_save_memory()


func _print_prompt(npc_id: String, now: int) -> void:
	var msgs: Array = PromptBuilder.build(npc_id, _card, [], now)
	for p: Dictionary in msgs[0]["content"]:
		print("---- system part%s ----\n%s" % [" (cached)" if p.get("cache", false) else "", p["text"]])


# --- mock -------------------------------------------------------------------

func _make_mock() -> LLMTransport:
	var m := MockTransport.new()
	var reply: String = _mock_reply() if _mock_phase == "talk" else _mock_summary()
	var script: Array[String] = []
	for i in range(0, reply.length(), MOCK_CHUNK_CHARS):
		script.append(MockTransport.delta(reply.substr(i, MOCK_CHUNK_CHARS)))
	script.append(MockTransport.sse("[DONE]"))
	m.canned = script
	return m


func _mock_reply() -> String:
	var samples: Array = _card.get("speech_samples", [])
	var voice: String = str(samples[0]) if not samples.is_empty() else "Well now."
	var speech: String = "%s Well, well, let me see what I can do for you, friend." % voice
	var intents: Array = [{"type": "disposition_delta", "value": 1}, {"type": "give_item", "item_id": "the_one_ring"}]
	var gift: Array[String] = NPCFacts.giftable_items(str(_card["id"]), _card)
	if not gift.is_empty():
		intents.append({"type": "give_item", "item_id": gift[0]})  # shows a valid grant next to the invalid one above
	var meta: Dictionary = {"options": ["Ask about news", "Ask for something to eat or drink", "Say farewell"], "intents": intents, "mood": "flustered"}
	return "%s\n%s\n%s" % [speech, ReplyParser.MARKER, JSON.stringify(meta)]


func _mock_summary() -> String:
	return JSON.stringify({
		"summary": "A traveller spoke with me this evening and was civil enough. We talked a little; I gave what I could.",
		"learned": [{"fact": "A traveller is passing through and asking after news.", "spreadable": true}],
	})


# --- memory persistence ------------------------------------------------------

func _load_memory() -> void:
	if not FileAccess.file_exists(MEMORY_PATH):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(MEMORY_PATH))
	if d is Dictionary:
		for npc: String in d:
			var m: Dictionary = d[npc]
			WorldState.set_npc_memory(npc, str(m.get("summary", "")), int(m.get("last_talk", -1)), int(m.get("disposition", 0)))
		print("[keep-memory] loaded memory from %s" % ProjectSettings.globalize_path(MEMORY_PATH))


func _save_memory() -> void:
	var f: FileAccess = FileAccess.open(MEMORY_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(WorldState.npc_memory))
		print("[keep-memory] saved memory to %s" % ProjectSettings.globalize_path(MEMORY_PATH))


# --- args -------------------------------------------------------------------

# Accepts --flag=value and --flag value for value flags; bare flags map to "true".
func _parse(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	var i: int = 0
	while i < argv.size():
		var a: String = argv[i]
		i += 1
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		var key: String = kv[0]
		var value: String = "true"
		if kv.size() > 1:
			value = kv[1]
		elif key in VALUE_FLAGS and i < argv.size() and not argv[i].begins_with("--"):
			value = argv[i]
			i += 1
		if key in ["say", "flag"]:
			var list: Array = out.get(key, [])
			list.append(value)
			out[key] = list
		else:
			out[key] = value
	return out


func _one(key: String, default: String = "") -> String:
	var v: Variant = _args.get(key, default)
	return str(v) if not (v is Array) else str((v as Array)[0])


func _many(key: String) -> Array:
	return _args.get(key, [])
