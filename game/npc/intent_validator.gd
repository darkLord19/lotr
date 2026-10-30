class_name IntentValidator
extends RefCounted
## The LLM proposes, the game decides. Each intent is checked against WorldState and the whitelist;
## valid ones are applied, invalid ones are dropped (and reported so tests and the CLI can show why).

const WHITELIST: Array[String] = [
	"give_item", "share_rumour", "share_knowledge", "disposition_delta", "reveal_poi", "end_conversation",
]
const RUMOUR_KNOWLEDGE_PREFIX: String = "rumour:"
const POI_REVEALED_FLAG_PREFIX: String = "poi_revealed."


## Returns {applied: Array[Dictionary], rejected: Array[{intent, reason}], end_conversation: bool}.
## ctx: {npc_id: String, card: Dictionary, now: int}
static func validate_and_apply(intents: Array, ctx: Dictionary) -> Dictionary:
	var result: Dictionary = {"applied": [], "rejected": [], "end_conversation": false}
	var cap: int = int(Config.get_value("npc.max_intents_per_turn", 4))
	var seen: Array[String] = []
	for raw: Variant in intents:
		var intent: Dictionary = raw if raw is Dictionary else {}
		var reason: String = "too_many_intents" if (result["applied"] as Array).size() >= cap else check(intent, ctx)
		var key: String = JSON.stringify(intent)
		if reason.is_empty() and key in seen:
			reason = "duplicate"
		if not reason.is_empty():
			(result["rejected"] as Array).append({"intent": intent, "reason": reason})
			continue
		seen.append(key)
		if intent["type"] == "disposition_delta":
			intent = {"type": "disposition_delta", "value": int(intent["value"])}  # JSON gives floats
		_apply(intent, ctx, result)
		(result["applied"] as Array).append(intent)
	return result


## Empty string when the intent is acceptable, else a short machine-readable reason.
static func check(intent: Dictionary, ctx: Dictionary) -> String:
	var type: String = str(intent.get("type", ""))
	var npc_id: String = ctx["npc_id"]
	var card: Dictionary = ctx["card"]
	match type:
		"give_item":
			var item: String = _str(intent, "item_id")
			if item.is_empty():
				return "missing_item_id"
			if WorldState.item_count(npc_id, item) < 1:
				return "npc_does_not_own_item"
			return ""
		"share_rumour":
			var rid: String = _str(intent, "rumour_id")
			if rid.is_empty():
				return "missing_rumour_id"
			return "" if rid in NPCFacts.heard_rumours(npc_id, card) else "rumour_not_heard"
		"share_knowledge":
			var kid: String = _str(intent, "knowledge_id")
			if kid.is_empty():
				return "missing_knowledge_id"
			for k: Dictionary in NPCFacts.visible_knowledge(npc_id, card, int(ctx["now"])):
				if k["id"] == kid:
					return ""
			return "knowledge_not_known"
		"disposition_delta":
			var v: Variant = intent.get("value")
			if not (v is int or v is float):
				return "bad_value"
			var limit: int = int(Config.get_value("npc.disposition_delta_max", 2))
			if float(v) != floorf(float(v)) or absi(int(v)) > limit:
				return "value_out_of_range"
			return ""
		"reveal_poi":
			var poi: String = _str(intent, "poi_id")
			if poi.is_empty():
				return "missing_poi_id"
			return "" if WorldState.poi_info.has(poi) else "unknown_poi"
		"end_conversation":
			return ""
	return "unknown_intent_type"


static func _apply(intent: Dictionary, ctx: Dictionary, result: Dictionary) -> void:
	var npc_id: String = ctx["npc_id"]
	match str(intent["type"]):
		"give_item":
			WorldState.transfer_item(_str(intent, "item_id"), npc_id, WorldState.PLAYER_ID)
		"share_rumour":
			WorldState.add_knowledge(WorldState.PLAYER_ID, RUMOUR_KNOWLEDGE_PREFIX + _str(intent, "rumour_id"))
		"share_knowledge":
			WorldState.add_knowledge(WorldState.PLAYER_ID, _str(intent, "knowledge_id"))
		"disposition_delta":
			adjust_disposition(npc_id, int(intent["value"]))
		"reveal_poi":
			WorldState.set_flag(POI_REVEALED_FLAG_PREFIX + _str(intent, "poi_id"))
		"end_conversation":
			result["end_conversation"] = true


## Clamped to the configured range; keeps the stored summary and last_talk.
static func adjust_disposition(npc_id: String, delta: int) -> int:
	var mem: Dictionary = WorldState.get_npc_memory(npc_id)
	var d: int = clampi(int(mem["disposition"]) + delta, int(Config.get_value("npc.disposition_min", -10)), int(Config.get_value("npc.disposition_max", 10)))
	WorldState.set_npc_memory(npc_id, str(mem["summary"]), int(mem["last_talk"]), d)
	return d


static func _str(intent: Dictionary, key: String) -> String:
	var v: Variant = intent.get(key)
	return (v as String) if v is String else ""
