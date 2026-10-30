extends GutTest

const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")

var ws: Node


func before_each() -> void:
	ws = autofree(WorldStateScript.new())
	watch_signals(EventBus)


func test_set_flag_emits_once_per_change() -> void:
	ws.set_flag("met_rider")
	assert_signal_emitted_with_parameters(EventBus, "flag_changed", ["met_rider", true])
	ws.set_flag("met_rider")
	assert_signal_emit_count(EventBus, "flag_changed", 1)
	assert_true(ws.get_flag("met_rider"))
	assert_false(ws.get_flag("other"))


func test_move_entity_emits() -> void:
	ws.spawn_entity("frodo", "npc", "bag_end", "eriador_west")
	ws.move_entity("frodo", "bywater")
	assert_signal_emitted_with_parameters(EventBus, "entity_moved", ["frodo", "bywater"])
	assert_eq(ws.entity_location("frodo")["poi"], "bywater")
	ws.move_entity("frodo", Vector3(1, 2, 3))
	assert_eq(ws.entity_location("frodo")["pos"], Vector3(1, 2, 3))
	assert_false(ws.move_entity("nobody", "x"))


func test_poi_resolves_to_position() -> void:
	ws.register_poi("bag_end", Vector3(900, 0, 2100), "hobbiton")
	ws.spawn_entity("player", "player", "bag_end")
	assert_eq(ws.entity_location("player")["pos"], Vector3(900, 0, 2100))


func test_transfer_item() -> void:
	assert_true(ws.transfer_item("ale_mug", "", "barliman", 2))
	assert_signal_emitted_with_parameters(EventBus, "item_transferred", ["ale_mug", "", "barliman"])
	assert_false(ws.transfer_item("ale_mug", "barliman", "player", 3), "not enough")
	assert_eq(ws.item_count("barliman", "ale_mug"), 2)
	assert_true(ws.transfer_item("ale_mug", "barliman", "player", 2))
	assert_eq(ws.item_count("barliman", "ale_mug"), 0)
	assert_false(ws.inventories.has("barliman"), "empty inventories are dropped")
	assert_eq(ws.item_count("player", "ale_mug"), 2)


func test_reputation_clamped() -> void:
	assert_eq(ws.change_reputation("shire", 150), 100)
	assert_eq(ws.change_reputation("shire", -500), -100)
	assert_signal_emitted(EventBus, "reputation_changed")


func test_knowledge_and_rumours() -> void:
	ws.add_knowledge("gaffer", "k1")
	ws.add_knowledge("gaffer", "k1")
	assert_signal_emit_count(EventBus, "knowledge_added", 1)
	assert_true(ws.has_knowledge("gaffer", "k1"))
	ws.spread_rumour("r1", "hobbiton")
	assert_signal_emitted_with_parameters(EventBus, "rumour_spread", ["r1", "hobbiton"])
	assert_true(ws.rumour_known_at("r1", "hobbiton"))


func test_npc_memory() -> void:
	assert_eq(ws.get_npc_memory("x")["disposition"], 0)
	ws.set_npc_memory("barliman", "Met a Mr Underhill.", 1000, 2)
	assert_signal_emitted_with_parameters(EventBus, "npc_memory_changed", ["barliman"])
	assert_eq(ws.get_npc_memory("barliman")["summary"], "Met a Mr Underhill.")


func test_serialise_round_trip_through_json() -> void:
	populate(ws)
	var before: Dictionary = ws.serialise()
	var other: Node = autofree(WorldStateScript.new())
	other.deserialise(JSON.parse_string(JSON.stringify(before)))
	assert_eq(JSON.stringify(other.serialise(), "", true), JSON.stringify(before, "", true))
	assert_eq(other.item_count("player", "bread_loaf"), 3)
	assert_typeof(other.item_count("player", "bread_loaf"), TYPE_INT)
	assert_eq(other.get_reputation("bree"), -20)
	assert_eq(other.get_npc_memory("barliman")["last_talk"], 1234)


static func populate(w: Node) -> void:
	w.spawn_entity("player", "player", "bag_end", "eriador_west", {"name": "Hamfast"})
	w.spawn_entity("frodo", "npc", Vector3(10.5, 0, 20.25))
	w.set_flag("a", true)
	w.set_flag("quest_stage", "two")
	w.transfer_item("bread_loaf", "", "player", 3)
	w.change_reputation("bree", -20)
	w.set_npc_memory("barliman", "Forgot a letter.", 1234, -1)
	w.add_knowledge("gaffer", "k1")
	w.spread_rumour("r1", "hobbiton")
