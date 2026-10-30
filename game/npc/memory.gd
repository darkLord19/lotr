class_name NPCMemory
extends RefCounted
## Conversation-end summariser. Calls the `summariser` tier with the previous summary and the
## transcript, stores the result in WorldState.npc_memory and records spreadable facts.

const TIER: String = "summariser"
const LEARNED_FLAG_PREFIX: String = "learned_facts."


## on_done(result: Dictionary) -> {ok, summary, learned: Array[Dictionary], error}
## On any failure the previous summary is kept (only last_talk advances) so nothing is invented.
static func summarise(gateway: Node, npc_id: String, card: Dictionary, turns: Array, now: int, on_done: Callable) -> void:
	var prev: Dictionary = WorldState.get_npc_memory(npc_id)
	if turns.is_empty():
		on_done.call({"ok": false, "summary": prev["summary"], "learned": [], "error": "empty_transcript"})
		return
	var messages: Array = [
		{"role": "system", "content": [{"type": "text", "text": NPCContent.prompt_text("summariser_system"), "cache": true}]},
		{"role": "user", "content": _user_prompt(card, str(prev["summary"]), turns)},
	]
	var finish: Callable = func(res: Dictionary) -> void:
		on_done.call(_finish(res, npc_id, prev, now))
	gateway.request(TIER, messages, Callable(), finish)


static func _user_prompt(card: Dictionary, prev_summary: String, turns: Array) -> String:
	var lines: PackedStringArray = []
	lines.append("Character: %s" % card.get("name", "?"))
	lines.append("Previous memory summary: %s" % (prev_summary if prev_summary != "" else "(none, first meeting)"))
	lines.append("")
	lines.append("Transcript:")
	for t: Variant in turns:
		var turn: Dictionary = t
		var who: String = "Player" if turn["role"] == PromptBuilder.ROLE_PLAYER else str(card.get("name", "NPC"))
		var text: String = str(turn["text"])
		var cut: int = text.find(ReplyParser.MARKER)
		lines.append("%s: %s" % [who, (text.substr(0, cut) if cut >= 0 else text).strip_edges()])
	return "\n".join(lines)


static func _finish(res: Dictionary, npc_id: String, prev: Dictionary, now: int) -> Dictionary:
	var parsed: Dictionary = parse_summary(str(res.get("text", ""))) if res.get("ok", false) else {}
	if parsed.is_empty():
		WorldState.set_npc_memory(npc_id, str(prev["summary"]), now, int(WorldState.get_npc_memory(npc_id)["disposition"]))
		var err: String = str(res.get("error", "")) if not res.get("ok", false) else "bad_summary_json"
		return {"ok": false, "summary": prev["summary"], "learned": [], "error": err}
	var disposition: int = int(WorldState.get_npc_memory(npc_id)["disposition"])
	WorldState.set_npc_memory(npc_id, parsed["summary"], now, disposition)
	_record_learned(npc_id, parsed["learned"])
	return {"ok": true, "summary": parsed["summary"], "learned": parsed["learned"], "error": ""}


## Returns {} when the text has no usable summary, else {summary, learned: Array[Dictionary]}.
static func parse_summary(text: String) -> Dictionary:
	var obj: Variant = ReplyParser.parse_json_object(text)
	if not (obj is Dictionary) or not ((obj as Dictionary).get("summary") is String):
		return {}
	var summary: String = _limit_words(((obj as Dictionary)["summary"] as String).strip_edges(), int(Config.get_value("npc.memory_summary_max_words", 120)))
	if summary.is_empty():
		return {}
	var learned: Array[Dictionary] = []
	var raw: Variant = (obj as Dictionary).get("learned", [])
	if raw is Array:
		for l: Variant in raw:
			if l is Dictionary and (l as Dictionary).get("fact") is String and learned.size() < int(Config.get_value("npc.memory_max_learned", 8)):
				learned.append({"fact": ((l as Dictionary)["fact"] as String).strip_edges(), "spreadable": bool((l as Dictionary).get("spreadable", false))})
	return {"summary": summary, "learned": learned}


# Spreadable facts accumulate under a flag so the M1 rumour network can consume them and saves keep them.
static func _record_learned(npc_id: String, learned: Array) -> void:
	var key: String = LEARNED_FLAG_PREFIX + npc_id
	var facts: Array = (WorldState.get_flag(key, []) as Array).duplicate()
	for l: Variant in learned:
		var d: Dictionary = l
		if d["spreadable"] and str(d["fact"]) != "" and str(d["fact"]) not in facts:
			facts.append(d["fact"])
	var cap: int = int(Config.get_value("npc.learned_facts_cap", 20))
	if facts.size() > cap:
		facts = facts.slice(facts.size() - cap)
	if not facts.is_empty():
		WorldState.set_flag(key, facts)


static func _limit_words(s: String, max_words: int) -> String:
	var words: PackedStringArray = s.split(" ", false)
	if words.size() <= max_words:
		return s
	return " ".join(words.slice(0, max_words))
