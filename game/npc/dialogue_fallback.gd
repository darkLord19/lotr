class_name DialogueFallback
extends RefCounted
## Authored-line fallback used whenever the LLM is unavailable or a reply fails.
## Lines come from content/dialogue_fallbacks/<npc>.json and are filtered by date and flag.

const KIND_GREETING: String = "greeting"
const KIND_FAREWELL: String = "farewell"
const KIND_NEWS: String = "news"
const KIND_SMALLTALK: String = "smalltalk"


## Chooses what the player's input means in the absence of a model.
static func classify(player_text: String, first_npc_turn: bool) -> String:
	var t: String = player_text.to_lower()
	if t.strip_edges().is_empty():
		return KIND_GREETING
	if _has_word(t, "npc.farewell_words"):
		return KIND_FAREWELL
	if _has_word(t, "npc.news_words"):
		return KIND_NEWS
	return KIND_GREETING if first_npc_turn else KIND_SMALLTALK


## `used` holds line texts already spoken this conversation (avoids immediate repeats).
## Returns {speech, options, intents, mood, source, kind}.
static func respond(npc_id: String, card: Dictionary, now: int, kind: String, used: Array, rng: RandomNumberGenerator) -> Dictionary:
	var data: Dictionary = NPCContent.load_fallbacks(npc_id)
	var intents: Array[Dictionary] = []
	var speech: String = ""
	var actual: String = kind
	if kind == KIND_NEWS:
		var pick: Dictionary = _pick_rumour_line(npc_id, card, data, now, used, rng)
		if pick.is_empty():
			actual = KIND_SMALLTALK
		else:
			speech = pick["text"]
			intents.append({"type": "share_rumour", "rumour_id": pick["rumour_id"]})
	if speech.is_empty():
		var key: String = {KIND_GREETING: "greetings", KIND_FAREWELL: "farewells"}.get(actual, "smalltalk")
		speech = _pick(data.get(key, []), now, used, rng)
		if speech.is_empty() and actual != KIND_SMALLTALK:
			speech = _pick(data.get("smalltalk", []), now, used, rng)
	if actual == KIND_FAREWELL:
		intents.append({"type": "end_conversation"})
	if speech.is_empty():
		speech = str(Config.get_value("npc.no_fallback_line", ""))
	var options: Array[String] = []
	options.assign(Config.get_value("npc.fallback_options", []))
	return {"speech": speech, "options": options, "intents": intents, "mood": "", "source": "fallback", "kind": actual}


static func _pick_rumour_line(npc_id: String, card: Dictionary, data: Dictionary, now: int, used: Array, rng: RandomNumberGenerator) -> Dictionary:
	var lines: Dictionary = data.get("rumour_lines", {})
	for rid: String in NPCFacts.heard_rumours(npc_id, card):
		var text: String = _pick(lines.get(rid, []), now, used, rng, false)
		if text != "":
			return {"rumour_id": rid, "text": text}
	return {}


## Picks a valid line. With allow_repeat, falls back to already-used lines rather than nothing.
static func _pick(entries: Array, now: int, used: Array, rng: RandomNumberGenerator, allow_repeat: bool = true) -> String:
	var fresh: Array[String] = []
	var repeats: Array[String] = []
	for e: Variant in entries:
		var text: String = _entry_text(e, now)
		if text.is_empty():
			continue
		(repeats if text in used else fresh).append(text)
	var pool: Array[String] = fresh if not fresh.is_empty() or not allow_repeat else repeats
	if pool.is_empty():
		return ""
	var text: String = pool[rng.randi_range(0, pool.size() - 1)]
	used.append(text)
	return text


## "" when the entry is not valid at `now` (before `from`, after `until`, or its flag unset).
static func _entry_text(e: Variant, now: int) -> String:
	if e is String:
		return e
	if not (e is Dictionary):
		return ""
	var d: Dictionary = e
	var from: Variant = d.get("from")
	if from is String and GameDate.parse(from) > now:
		return ""
	var until: Variant = d.get("until")
	if until is String and GameDate.parse(until) != GameDate.INVALID and now >= GameDate.parse(until):
		return ""
	var flag: Variant = d.get("requires_flag")
	if flag is String and not (flag as String).is_empty() and not bool(WorldState.get_flag(flag)):
		return ""
	return str(d.get("text", ""))


static func _has_word(lowered: String, config_path: String) -> bool:
	for w: Variant in Config.get_value(config_path, []):
		if lowered.contains(str(w)):
			return true
	return false
