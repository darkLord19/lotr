class_name NPCTestHelper
extends RefCounted
## Shared fixtures for the NPC tests (not itself a test).

const NPC: String = "barliman_butterbur"


static func reset_world(date: String) -> void:
	WorldState.reset()
	WorldState.poi_info = {}  # reset() keeps world geometry; tests register their own
	WorldClock.now = GameDate.parse(date)
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", "prancing_pony", "", {"race": "hobbit", "origin": "the Shire"})
	WorldState.spawn_entity(NPC, "npc", "prancing_pony")
	for item: Variant in NPCContent.load_card(NPC).get("inventory_can_give", []):
		WorldState.transfer_item(str(item), "", NPC)


static func card() -> Dictionary:
	return NPCContent.load_card(NPC)


static func wire(speech: String, meta: Dictionary) -> String:
	return "%s\n%s\n%s" % [speech, ReplyParser.MARKER, JSON.stringify(meta)]


## Gateway test double: replays `reply_chunks` through on_chunk, then on_done with the given result.
class FakeGateway extends Node:
	var available: bool = true
	var reply_chunks: Array[String] = []
	var ok: bool = true
	var error: String = ""
	var requests: Array[Dictionary] = []
	var summary_text: String = ""

	func is_available() -> bool:
		return available

	func request(tier: String, messages: Array, on_chunk: Callable, on_done: Callable) -> int:
		requests.append({"tier": tier, "messages": messages})
		var text: String = ""
		var chunks: Array[String] = reply_chunks
		if tier == "summariser":
			chunks = [summary_text]
		for c in chunks:
			text += c
			if on_chunk.is_valid():
				on_chunk.call(c)
		on_done.call({"ok": ok, "text": text, "error": error, "tier": tier, "model": "fake", "usage": {}, "latency_ms": 0})
		return requests.size()
