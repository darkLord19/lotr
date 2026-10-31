extends GutTest

var gw: NPCTestHelper.FakeGateway
var mind: NPCMind
var shown: String
var turn: Dictionary
var saved_now: int


func before_each() -> void:
	saved_now = WorldClock.now
	NPCTestHelper.reset_world("3018-09-29T21:00")
	gw = NPCTestHelper.FakeGateway.new()
	add_child_autofree(gw)
	mind = NPCMind.new(NPCTestHelper.NPC)
	mind.gateway = gw
	mind.rng.seed = 3
	shown = ""
	turn = {}


func after_each() -> void:
	WorldState.reset()
	WorldState.poi_info = {}
	WorldClock.now = saved_now


func _say(text: String) -> void:
	turn = {}
	mind.say(text, func(p: String) -> void: shown += p, func(t: Dictionary) -> void: turn = t)


func _reply(speech: String, meta: Dictionary, size: int = 7) -> Array[String]:
	var full: String = NPCTestHelper.wire(speech, meta)
	var out: Array[String] = []
	for i in range(0, full.length(), size):
		out.append(full.substr(i, size))
	return out


func test_streams_speech_only_and_applies_intents() -> void:
	gw.reply_chunks = _reply("Ah, evening to you!", {"options": ["Ask about riders", "Order a pint"], "intents": [
		{"type": "give_item", "item_id": "ale_mug"}, {"type": "give_item", "item_id": "the_one_ring"}, {"type": "disposition_delta", "value": 1}], "mood": "flustered"})
	_say("Good evening!")
	assert_eq(shown, "Ah, evening to you!", "nothing of the META block reaches the UI")
	assert_eq(turn["source"], "llm")
	assert_eq(turn["speech"], "Ah, evening to you!")
	assert_eq(turn["options"], ["Ask about riders", "Order a pint"])
	assert_eq((turn["applied"] as Array).size(), 2)
	assert_eq(turn["rejected"][0]["reason"], "npc_does_not_own_item")
	assert_eq(WorldState.item_count(WorldState.PLAYER_ID, "ale_mug"), 1)
	assert_eq(WorldState.get_npc_memory(NPCTestHelper.NPC)["disposition"], 1)
	assert_eq(gw.requests[0]["tier"], "standard")
	assert_eq(mind.turns.size(), 2)


func test_history_is_sent_on_the_next_request() -> void:
	gw.reply_chunks = _reply("First.", {"options": [], "intents": []})
	_say("One")
	gw.reply_chunks = _reply("Second.", {"options": [], "intents": []})
	_say("Two")
	var msgs: Array = gw.requests[1]["messages"]
	assert_eq(msgs.size(), 4)
	assert_eq(msgs[1]["content"], "One")
	assert_eq(msgs[2]["role"], "assistant")
	assert_true((msgs[2]["content"] as String).contains("---META---"))
	assert_eq(msgs[3]["content"], "Two")


func test_end_conversation_intent_is_reported() -> void:
	gw.reply_chunks = _reply("Out!", {"options": [], "intents": [{"type": "end_conversation"}]})
	_say("Hmph")
	assert_true(turn["end_conversation"])


func test_fallback_when_gateway_unavailable() -> void:
	gw.available = false
	_say("Good evening! Any news?")
	assert_eq(gw.requests.size(), 0, "no request is attempted")
	assert_eq(turn["source"], "fallback")
	assert_eq(turn["options"], ["Ask about news", "Trade", "Farewell"])
	assert_ne(shown, "")
	assert_eq(shown, turn["speech"])


func test_fallback_when_request_fails_before_any_text() -> void:
	gw.reply_chunks = []
	gw.ok = false
	gw.error = "timeout"
	_say("Hello")
	assert_eq(turn["source"], "fallback")
	assert_eq(turn["error"], "timeout")
	assert_ne(turn["speech"], "")


func test_fallback_when_reply_has_no_speech() -> void:
	gw.reply_chunks = _reply("", {"options": ["a"], "intents": []})
	_say("Hello")
	assert_eq(turn["source"], "fallback")


func test_stream_failure_midway_keeps_shown_text_and_drops_intents() -> void:
	gw.reply_chunks = ["Well now, ", "what was"]
	gw.ok = false
	gw.error = "stream_error:boom"
	_say("Hello")
	assert_eq(turn["source"], "llm")
	assert_false(turn["ok"])
	assert_eq(turn["speech"], "Well now, what was")
	assert_eq(turn["options"], ["Ask about news", "Trade", "Farewell"])


func test_missing_meta_still_gives_options() -> void:
	gw.reply_chunks = ["Just words, no META at all."]
	_say("Hello")
	assert_eq(turn["speech"], "Just words, no META at all.")
	assert_eq(shown, "Just words, no META at all.")
	assert_eq(turn["options"].size(), 3)


func test_unknown_npc_fails_cleanly() -> void:
	var ghost := NPCMind.new("no_such_npc")
	ghost.gateway = gw
	var got: Array = []
	ghost.say("hi", Callable(), func(t: Dictionary) -> void: got.append(t))
	assert_eq(got.size(), 1)
	assert_false(got[0]["ok"])


func test_end_conversation_runs_summariser_and_stores_memory() -> void:
	gw.reply_chunks = _reply("Welcome!", {"options": [], "intents": [{"type": "disposition_delta", "value": 2}]})
	_say("Hi, I am a hobbit from the Shire.")
	gw.summary_text = '{"summary": "A hobbit from the Shire came in and was polite.", "learned": [{"fact": "A hobbit is travelling from the Shire.", "spreadable": true}, {"fact": "He likes ale.", "spreadable": false}]}'
	var got: Array = []
	mind.end_conversation(func(r: Dictionary) -> void: got.append(r))
	assert_true(got[0]["ok"])
	var mem: Dictionary = WorldState.get_npc_memory(NPCTestHelper.NPC)
	assert_eq(mem["summary"], "A hobbit from the Shire came in and was polite.")
	assert_eq(mem["last_talk"], WorldClock.now)
	assert_eq(mem["disposition"], 2, "disposition survives the summary write")
	assert_eq(WorldState.get_flag("learned_facts.%s" % NPCTestHelper.NPC), ["A hobbit is travelling from the Shire."], "only spreadable facts are kept")
	var req: Dictionary = gw.requests.back()
	assert_eq(req["tier"], "summariser")
	assert_true((req["messages"][1]["content"] as String).contains("I am a hobbit"))
	assert_false((req["messages"][1]["content"] as String).contains("---META---"), "transcript carries speech only")


func test_end_conversation_after_fallback_only_skips_the_model() -> void:
	gw.available = false
	_say("Hello")
	var got: Array = []
	mind.end_conversation(func(r: Dictionary) -> void: got.append(r))
	assert_false(got[0]["ok"])
	assert_eq(gw.requests.size(), 0)
	assert_eq(WorldState.get_npc_memory(NPCTestHelper.NPC)["last_talk"], WorldClock.now)
