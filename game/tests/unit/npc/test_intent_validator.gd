extends GutTest

var ctx: Dictionary
var saved_now: int


func before_each() -> void:
	saved_now = WorldClock.now
	NPCTestHelper.reset_world("3018-09-29T21:00")
	ctx = {"npc_id": NPCTestHelper.NPC, "card": NPCTestHelper.card(), "now": WorldClock.now}


func after_each() -> void:
	WorldState.reset()
	WorldState.poi_info = {}
	WorldClock.now = saved_now


func _run(intent: Dictionary) -> Dictionary:
	return IntentValidator.validate_and_apply([intent], ctx)


func test_give_item_rejected_when_npc_does_not_own_it() -> void:
	var r: Dictionary = _run({"type": "give_item", "item_id": "the_one_ring"})
	assert_eq((r["applied"] as Array).size(), 0)
	assert_eq(r["rejected"][0]["reason"], "npc_does_not_own_item")
	assert_eq(WorldState.item_count(WorldState.PLAYER_ID, "the_one_ring"), 0)


func test_give_item_owned_transfers_once() -> void:
	var r: Dictionary = _run({"type": "give_item", "item_id": "ale_mug"})
	assert_eq((r["applied"] as Array).size(), 1)
	assert_eq(WorldState.item_count(WorldState.PLAYER_ID, "ale_mug"), 1)
	assert_eq(WorldState.item_count(NPCTestHelper.NPC, "ale_mug"), 0)
	var again: Dictionary = _run({"type": "give_item", "item_id": "ale_mug"})
	assert_eq(again["rejected"][0]["reason"], "npc_does_not_own_item", "gone after one gift")


func test_disposition_delta_range() -> void:
	var bad: Dictionary = _run({"type": "disposition_delta", "value": 5})
	assert_eq(bad["rejected"][0]["reason"], "value_out_of_range")
	assert_eq(WorldState.get_npc_memory(NPCTestHelper.NPC)["disposition"], 0)
	assert_eq(_run({"type": "disposition_delta", "value": 1.5})["rejected"][0]["reason"], "value_out_of_range")
	assert_eq(_run({"type": "disposition_delta", "value": "2"})["rejected"][0]["reason"], "bad_value")
	var ok: Dictionary = _run({"type": "disposition_delta", "value": -2.0})
	assert_eq(ok["applied"][0]["value"], -2)
	assert_eq(WorldState.get_npc_memory(NPCTestHelper.NPC)["disposition"], -2)


func test_disposition_is_clamped_to_scale() -> void:
	for i in 10:
		IntentValidator.adjust_disposition(NPCTestHelper.NPC, 2)
	assert_eq(WorldState.get_npc_memory(NPCTestHelper.NPC)["disposition"], int(Config.get_value("npc.disposition_max")))


func test_unknown_and_malformed_types() -> void:
	assert_eq(_run({"type": "teleport_player"})["rejected"][0]["reason"], "unknown_intent_type")
	assert_eq(_run({})["rejected"][0]["reason"], "unknown_intent_type")
	assert_eq(_run({"type": "give_item"})["rejected"][0]["reason"], "missing_item_id")


func test_share_knowledge_respects_date() -> void:
	assert_eq((_run({"type": "share_knowledge", "knowledge_id": "gandalf_letter"})["applied"] as Array).size(), 1)
	assert_true(WorldState.has_knowledge(WorldState.PLAYER_ID, "gandalf_letter"))
	WorldClock.now = GameDate.parse("3018-06-01")
	ctx["now"] = WorldClock.now
	assert_eq(_run({"type": "share_knowledge", "knowledge_id": "gandalf_letter"})["rejected"][0]["reason"], "knowledge_not_known")
	assert_eq(_run({"type": "share_knowledge", "knowledge_id": "nonsense"})["rejected"][0]["reason"], "knowledge_not_known")


func test_share_rumour_needs_rumour_at_npc_location() -> void:
	assert_eq(_run({"type": "share_rumour", "rumour_id": "r1"})["rejected"][0]["reason"], "rumour_not_heard")
	WorldState.spread_rumour("r1", "prancing_pony")
	assert_eq((_run({"type": "share_rumour", "rumour_id": "r1"})["applied"] as Array).size(), 1)
	assert_true(WorldState.has_knowledge(WorldState.PLAYER_ID, "rumour:r1"))


func test_share_rumour_via_same_settlement() -> void:
	WorldState.register_poi("prancing_pony", Vector3.ZERO, "bree")
	WorldState.register_poi("west_gate", Vector3.ONE, "bree")
	WorldState.spread_rumour("r2", "west_gate")
	assert_eq((_run({"type": "share_rumour", "rumour_id": "r2"})["applied"] as Array).size(), 1)


func test_reveal_poi_and_end_conversation() -> void:
	assert_eq(_run({"type": "reveal_poi", "poi_id": "mordor"})["rejected"][0]["reason"], "unknown_poi")
	WorldState.register_poi("weathertop", Vector3.ONE)
	_run({"type": "reveal_poi", "poi_id": "weathertop"})
	assert_true(WorldState.get_flag("poi_revealed.weathertop"))
	assert_true(_run({"type": "end_conversation"})["end_conversation"])


func test_duplicates_and_cap() -> void:
	var intents: Array = []
	for i in 6:
		intents.append({"type": "disposition_delta", "value": i % 2})
	var r: Dictionary = IntentValidator.validate_and_apply(intents, ctx)
	assert_eq((r["applied"] as Array).size(), 2, "only two distinct intents")
	var reasons: Array = (r["rejected"] as Array).map(func(x: Dictionary) -> String: return x["reason"])
	assert_true("duplicate" in reasons)
	var many: Array = []
	for i in 6:
		many.append({"type": "reveal_poi", "poi_id": "p%d" % i})
		WorldState.register_poi("p%d" % i, Vector3.ZERO)
	var r2: Dictionary = IntentValidator.validate_and_apply(many, ctx)
	assert_eq((r2["applied"] as Array).size(), int(Config.get_value("npc.max_intents_per_turn")))
