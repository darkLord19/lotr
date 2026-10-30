extends GutTest

var saved_now: int


func before_each() -> void:
	saved_now = WorldClock.now


func after_each() -> void:
	WorldState.reset()
	WorldClock.now = saved_now


func _ids(date: String) -> Array:
	NPCTestHelper.reset_world(date)
	var ids: Array = []
	for k: Dictionary in NPCFacts.visible_knowledge(NPCTestHelper.NPC, NPCTestHelper.card(), GameDate.parse(date)):
		ids.append(k["id"])
	return ids


func _dynamic(date: String) -> String:
	NPCTestHelper.reset_world(date)
	return PromptBuilder.dynamic_block(NPCTestHelper.NPC, NPCTestHelper.card(), GameDate.parse(date))


func test_knowledge_filtered_by_date() -> void:
	assert_eq(_ids("3018-06-01"), [], "letter not yet left")
	assert_eq(_ids("3018-07-01"), ["gandalf_letter"])
	assert_eq(_ids("3018-09-29T19:59"), ["gandalf_letter"])
	assert_eq(_ids("3018-09-29T20:00"), ["gandalf_letter", "riders_at_gate"], "included once now passes the date")


func test_prompt_text_excludes_future_entry_then_includes_it() -> void:
	var before: String = _dynamic("3018-09-29T19:00")
	assert_false(before.contains("Black-cloaked riders"))
	assert_true(before.contains("Gandalf left a letter"))
	var after: String = _dynamic("3018-09-29T21:00")
	assert_true(after.contains("Black-cloaked riders"))
	assert_true(after.contains("(secret)"))


func test_requires_flag_gates_entry() -> void:
	var card: Dictionary = {"id": "x", "knowledge": [{"id": "k", "fact": "F", "known_from": "3018-01-01", "requires_flag": "met_x"}]}
	WorldState.reset()
	assert_eq(NPCFacts.visible_knowledge("x", card, GameDate.parse("3018-05-01")).size(), 0)
	WorldState.set_flag("met_x")
	assert_eq(NPCFacts.visible_knowledge("x", card, GameDate.parse("3018-05-01")).size(), 1)


func test_timeline_granted_knowledge_is_visible_early() -> void:
	var card: Dictionary = {"id": "x", "knowledge": [{"id": "k", "fact": "F", "known_from": "3019-01-01"}]}
	WorldState.reset()
	assert_eq(NPCFacts.visible_knowledge("x", card, GameDate.parse("3018-05-01")).size(), 0)
	WorldState.add_knowledge("x", "k")
	assert_eq(NPCFacts.visible_knowledge("x", card, GameDate.parse("3018-05-01")).size(), 1)


func test_message_layout_and_cache_flags() -> void:
	NPCTestHelper.reset_world("3018-09-29T21:00")
	var turns: Array = [{"role": "player", "text": "Any news?"}]
	var msgs: Array = PromptBuilder.build(NPCTestHelper.NPC, NPCTestHelper.card(), turns, WorldClock.now)
	assert_eq(msgs[0]["role"], "system")
	var parts: Array = msgs[0]["content"]
	assert_eq(parts.size(), 3)
	assert_true(parts[0]["cache"])
	assert_true(parts[1]["cache"])
	assert_false(parts[2].get("cache", false), "dynamic block must not be cached")
	assert_true((parts[0]["text"] as String).contains("---META---"))
	assert_true((parts[1]["text"] as String).contains("Barliman Butterbur"))
	assert_eq(msgs.back(), {"role": "user", "content": "Any news?"})
	var wire: Array = LLMGateway.build_messages(msgs)
	assert_eq(wire[0]["content"][0]["cache_control"], {"type": "ephemeral"})
	assert_false(wire[0]["content"][2].has("cache_control"))


func test_first_message_is_always_from_user() -> void:
	NPCTestHelper.reset_world("3018-09-29T21:00")
	var npc_first: Array = [{"role": "npc", "text": "Welcome!"}, {"role": "player", "text": "Hi"}]
	var msgs: Array = PromptBuilder.build(NPCTestHelper.NPC, NPCTestHelper.card(), npc_first, WorldClock.now)
	assert_eq(msgs[1]["role"], "user")
	assert_eq(msgs[1]["content"], PromptBuilder.APPROACH_LINE)
	assert_eq(msgs[2]["role"], "assistant")
	assert_eq(PromptBuilder.build(NPCTestHelper.NPC, NPCTestHelper.card(), [], WorldClock.now)[1]["content"], PromptBuilder.APPROACH_LINE)


func test_allowed_intents_list_only_real_ids() -> void:
	NPCTestHelper.reset_world("3018-09-29T21:00")
	WorldState.transfer_item("ale_mug", NPCTestHelper.NPC, "", 1)  # NPC no longer has an ale mug
	WorldState.spread_rumour("some_rumour", "prancing_pony")
	WorldState.register_poi("west_gate", Vector3.ONE)
	var text: String = PromptBuilder.dynamic_block(NPCTestHelper.NPC, NPCTestHelper.card(), WorldClock.now)
	assert_true(text.contains("one of [bread_loaf, bill_the_pony]"))
	assert_false(text.contains("ale_mug"))
	assert_true(text.contains("one of [some_rumour]"))
	assert_true(text.contains("one of [west_gate]"))
	assert_true(text.contains("from -2 to 2"))


func test_memory_disposition_and_player_traits_appear() -> void:
	NPCTestHelper.reset_world("3018-09-29T21:00")
	WorldState.set_npc_memory(NPCTestHelper.NPC, "The hobbit paid well.", 5, 4)
	WorldState.change_reputation("bree", 35)
	var text: String = PromptBuilder.dynamic_block(NPCTestHelper.NPC, NPCTestHelper.card(), WorldClock.now)
	assert_true(text.contains("The hobbit paid well."))
	assert_true(text.contains("friendly"))
	assert_true(text.contains("race hobbit"))
	assert_true(text.contains("well regarded"))
	assert_false(text.contains("name "), "the player has not given a name")
