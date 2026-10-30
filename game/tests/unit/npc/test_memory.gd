extends GutTest

var saved_now: int
var gw: NPCTestHelper.FakeGateway
var turns: Array = [{"role": "player", "text": "Hello"}, {"role": "npc", "text": "Hi!\n---META---\n{}"}]


func before_each() -> void:
	saved_now = WorldClock.now
	NPCTestHelper.reset_world("3018-09-29T21:00")
	gw = NPCTestHelper.FakeGateway.new()
	add_child_autofree(gw)


func after_each() -> void:
	WorldState.reset()
	WorldClock.now = saved_now


func _summarise(text: String, ok: bool = true) -> Dictionary:
	gw.summary_text = text
	gw.ok = ok
	gw.error = "" if ok else "timeout"
	var out: Array = []
	NPCMemory.summarise(gw, NPCTestHelper.NPC, NPCTestHelper.card(), turns, WorldClock.now, func(r: Dictionary) -> void: out.append(r))
	return out[0]


func test_previous_summary_is_sent_and_new_one_stored() -> void:
	WorldState.set_npc_memory(NPCTestHelper.NPC, "Met a rude dwarf.", 1, 0)
	var r: Dictionary = _summarise('{"summary": "Met the hobbit.", "learned": []}')
	assert_true(r["ok"])
	assert_true((gw.requests[0]["messages"][1]["content"] as String).contains("Met a rude dwarf."))
	assert_eq(WorldState.get_npc_memory(NPCTestHelper.NPC)["summary"], "Met the hobbit.")


func test_summary_is_trimmed_to_word_limit() -> void:
	var long_text: String = " ".join(PackedStringArray(Array(range(300)).map(func(i: int) -> String: return "w%d" % i)))
	var r: Dictionary = _summarise(JSON.stringify({"summary": long_text, "learned": []}))
	assert_eq(r["summary"].split(" ").size(), int(Config.get_value("npc.memory_summary_max_words")))


func test_fenced_json_is_accepted() -> void:
	assert_true(_summarise('```json\n{"summary": "ok", "learned": []}\n```')["ok"])


func test_failure_keeps_previous_summary_but_stamps_time() -> void:
	WorldState.set_npc_memory(NPCTestHelper.NPC, "Old memory.", 1, 3)
	var r: Dictionary = _summarise("", false)
	assert_false(r["ok"])
	var mem: Dictionary = WorldState.get_npc_memory(NPCTestHelper.NPC)
	assert_eq(mem["summary"], "Old memory.")
	assert_eq(mem["last_talk"], WorldClock.now)
	assert_eq(mem["disposition"], 3)


func test_garbage_reply_keeps_previous_summary() -> void:
	WorldState.set_npc_memory(NPCTestHelper.NPC, "Old memory.", 1, 0)
	var r: Dictionary = _summarise("Sorry, I cannot do that.")
	assert_false(r["ok"])
	assert_eq(r["error"], "bad_summary_json")
	assert_eq(WorldState.get_npc_memory(NPCTestHelper.NPC)["summary"], "Old memory.")


func test_second_conversation_prompt_contains_first_memory() -> void:
	_summarise('{"summary": "The hobbit asked about riders.", "learned": []}')
	var text: String = PromptBuilder.dynamic_block(NPCTestHelper.NPC, NPCTestHelper.card(), WorldClock.now)
	assert_true(text.contains("The hobbit asked about riders."))


func test_empty_transcript_is_a_noop() -> void:
	var out: Array = []
	NPCMemory.summarise(gw, NPCTestHelper.NPC, NPCTestHelper.card(), [], WorldClock.now, func(r: Dictionary) -> void: out.append(r))
	assert_false(out[0]["ok"])
	assert_eq(gw.requests.size(), 0)
