class_name PromptBuilder
extends RefCounted
## Builds the OpenRouter message list: cached world + character parts first, then the dynamic block.

const APPROACH_LINE: String = "(The player approaches and you notice them.)"
const ROLE_PLAYER: String = "player"
const ROLE_NPC: String = "npc"


## turns: Array of {role: "player"|"npc", text: String}. For npc turns `text` is the full wire-format reply.
static func build(npc_id: String, card: Dictionary, turns: Array, now: int, opts: Dictionary = {}) -> Array:
	var system_parts: Array = [
		{"type": "text", "text": NPCContent.prompt_text("world_system"), "cache": true},
		{"type": "text", "text": character_block(card), "cache": true},
		{"type": "text", "text": dynamic_block(npc_id, card, now, opts)},
	]
	var messages: Array = [{"role": "system", "content": system_parts}]
	var limit: int = int(Config.get_value("npc.history_turn_limit", 16))
	var recent: Array = turns.slice(maxi(0, turns.size() - limit))
	# Chat APIs want the first turn to be the user's.
	if recent.is_empty() or (recent[0] as Dictionary)["role"] == ROLE_NPC:
		messages.append({"role": "user", "content": APPROACH_LINE})
	for t: Variant in recent:
		var turn: Dictionary = t
		messages.append({"role": "user" if turn["role"] == ROLE_PLAYER else "assistant", "content": turn["text"]})
	return messages


static func character_block(card: Dictionary) -> String:
	var lines: PackedStringArray = []
	lines.append("YOUR CHARACTER: %s (%s, %s)" % [card.get("name", "?"), card.get("race", "?"), card.get("faction", "?")])
	lines.append("Voice: %s" % card.get("voice", ""))
	lines.append("Personality: %s" % ", ".join(PackedStringArray(card.get("personality", []))))
	var samples: Array = card.get("speech_samples", [])
	if not samples.is_empty():
		lines.append("Speech samples:")
		for s: Variant in samples:
			lines.append("- %s" % s)
	var rel: Dictionary = card.get("relationships", {})
	if not rel.is_empty():
		lines.append("Relationships:")
		for who: String in rel:
			lines.append("- %s: %s" % [who, rel[who]])
	var never: Array = card.get("never_knows", [])
	if not never.is_empty():
		lines.append("You never know or speak of: %s" % "; ".join(PackedStringArray(never)))
	return "\n".join(lines)


static func dynamic_block(npc_id: String, card: Dictionary, now: int, opts: Dictionary = {}) -> String:
	var lines: PackedStringArray = []
	var weather: String = str(opts.get("weather", ""))
	lines.append("CURRENT SITUATION")
	lines.append("Date: %s, %s (T.A. %s). %s%s" % [
		GameDate.format_shire(now), _time_of_day(now), GameDate.format_iso(now),
		"Night." if GameDate.is_night(now) else "Daytime.", (" Weather: %s." % weather) if weather != "" else "",
	])
	lines.append("Location: %s" % NPCContent.prettify(NPCFacts.location(npc_id, card)))
	lines.append("Others present: %s" % _present(npc_id, opts))
	lines.append("The player: %s" % _player_traits(card))

	lines.append("")
	lines.append("YOUR KNOWLEDGE (all you know right now; nothing else):")
	var known: Array[Dictionary] = NPCFacts.visible_knowledge(npc_id, card, now)
	if known.is_empty():
		lines.append("- (nothing in particular)")
	for k: Dictionary in known:
		lines.append("- [%s]%s %s" % [k["id"], " (secret)" if k.get("secret", false) else "", k["fact"]])

	var heard: Array[String] = NPCFacts.heard_rumours(npc_id, card)
	lines.append("")
	lines.append("RUMOURS YOU HAVE HEARD:")
	if heard.is_empty():
		lines.append("- (none)")
	for rid: String in heard:
		var text: String = NPCContent.rumour_text(rid)
		lines.append("- [%s] %s" % [rid, text if text != "" else NPCContent.prettify(rid)])

	var mem: Dictionary = WorldState.get_npc_memory(npc_id)
	lines.append("")
	lines.append("YOUR MEMORY OF PAST TALKS WITH THE PLAYER: %s" % (str(mem["summary"]) if str(mem["summary"]) != "" else "You have not spoken with them before."))
	lines.append("Your disposition towards the player: %s (%d, scale %d to %d)" % [
		NPCFacts.band_name("npc.disposition_words", int(mem["disposition"])), int(mem["disposition"]),
		int(Config.get_value("npc.disposition_min", -10)), int(Config.get_value("npc.disposition_max", 10)),
	])

	lines.append("")
	lines.append_array(_intent_lines(npc_id, card, now))
	return "\n".join(lines)


static func _intent_lines(npc_id: String, card: Dictionary, now: int) -> PackedStringArray:
	var out: PackedStringArray = []
	var limit: int = int(Config.get_value("npc.disposition_delta_max", 2))
	out.append("ALLOWED INTENTS (use only these, with exactly these ids; the game ignores anything else):")
	out.append("- give_item {\"item_id\"}: %s" % _id_list(NPCFacts.giftable_items(npc_id, card)))
	out.append("- share_rumour {\"rumour_id\"}: %s" % _id_list(NPCFacts.heard_rumours(npc_id, card)))
	var kids: Array[String] = []
	for k: Dictionary in NPCFacts.visible_knowledge(npc_id, card, now):
		kids.append(str(k["id"]))
	out.append("- share_knowledge {\"knowledge_id\"}: %s" % _id_list(kids))
	out.append("- disposition_delta {\"value\"}: an integer from %d to %d, how this exchange changed your feelings" % [-limit, limit])
	out.append("- reveal_poi {\"poi_id\"}: %s" % _id_list(NPCFacts.revealable_pois(npc_id, card)))
	out.append("- end_conversation {}: when you would walk away or the talk is over")
	return out


static func _id_list(ids: Array[String]) -> String:
	return "one of [%s]" % ", ".join(PackedStringArray(ids)) if not ids.is_empty() else "none available right now"


static func _time_of_day(now: int) -> String:
	var h: int = GameDate.hour_of(now)
	for slot: Variant in Config.get_value("npc.time_of_day", []):
		if h < int((slot as Dictionary).get("until_hour", 24)):
			return str((slot as Dictionary).get("name", ""))
	return ""


static func _present(npc_id: String, opts: Dictionary) -> String:
	var names: Array = opts.get("present", [])
	if names.is_empty():
		var here: String = str(WorldState.entity_location(npc_id).get("poi", ""))
		for id: String in WorldState.entities:
			var e: Dictionary = WorldState.entities[id]
			if id != npc_id and id != WorldState.PLAYER_ID and here != "" and e["poi"] == here and e["alive"]:
				names.append(NPCContent.prettify(id))
	return ", ".join(PackedStringArray(names)) if not names.is_empty() else "no one of note"


static func _player_traits(card: Dictionary) -> String:
	var data: Dictionary = WorldState.get_entity(WorldState.PLAYER_ID).get("data", {})
	var rep: int = WorldState.get_reputation(str(card.get("faction", "")))
	var parts: PackedStringArray = []
	if data.get("introduced", false):
		parts.append("name %s" % data.get("name", "unknown"))
	parts.append("race %s" % data.get("race", "unknown"))
	parts.append("origin %s" % data.get("origin", "unknown"))
	parts.append("standing with your people (%s): %s" % [card.get("faction", "?"), NPCFacts.band_name("npc.reputation_bands", rep)])
	var items: Array = (WorldState.inventories.get(WorldState.PLAYER_ID, {}) as Dictionary).keys()
	if not items.is_empty():
		parts.append("carrying: %s" % ", ".join(PackedStringArray(items.map(NPCContent.prettify))))
	return "; ".join(parts)
