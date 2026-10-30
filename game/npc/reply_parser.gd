class_name ReplyParser
extends RefCounted
## Splits the wire format (speech, "---META---", JSON) into a result dictionary.
## Never throws: malformed META degrades to "no options, no intents".

const MARKER: String = "---META---"


## Result: {speech, options: Array[String], intents: Array[Dictionary], mood, has_meta, meta_ok}
static func parse(text: String) -> Dictionary:
	var out: Dictionary = {"speech": "", "options": [], "intents": [], "mood": "", "has_meta": false, "meta_ok": false}
	var idx: int = text.find(MARKER)
	if idx < 0:
		out["speech"] = text.strip_edges()
		return out
	out["has_meta"] = true
	out["speech"] = text.substr(0, idx).strip_edges()
	var meta: Variant = parse_json_object(text.substr(idx + MARKER.length()))
	if not (meta is Dictionary):
		push_warning("ReplyParser: META is not valid JSON; using no options/intents")
		return out
	out["meta_ok"] = true
	var m: Dictionary = meta
	var max_options: int = int(Config.get_value("npc.max_options", 4))
	var options: Array[String] = []
	var raw_options: Variant = m.get("options", [])
	if raw_options is Array:
		for o: Variant in raw_options:
			if o is String and not (o as String).strip_edges().is_empty() and options.size() < max_options:
				options.append((o as String).strip_edges())
	out["options"] = options
	var intents: Array[Dictionary] = []
	var raw_intents: Variant = m.get("intents", [])
	if raw_intents is Array:
		for i: Variant in raw_intents:
			if i is Dictionary and (i as Dictionary).get("type") is String:
				intents.append(i)
	out["intents"] = intents
	out["mood"] = str(m.get("mood", "")) if m.get("mood") is String else ""
	return out


## Extracts the first JSON object from model output, tolerating ``` fences and trailing prose.
static func parse_json_object(raw: String) -> Variant:
	var s: String = raw.strip_edges()
	if s.begins_with("```"):
		var nl: int = s.find("\n")
		s = s.substr(nl + 1) if nl >= 0 else ""
		var end: int = s.rfind("```")
		if end >= 0:
			s = s.substr(0, end)
	var first: int = s.find("{")
	var last: int = s.rfind("}")
	if first < 0 or last <= first:
		return null
	var j := JSON.new()
	if j.parse(s.substr(first, last - first + 1)) != OK:
		return null
	return j.data if j.data is Dictionary else null


## Incremental splitter for streamed text. feed() returns the speech that is safe to show; it
## withholds a possible partial marker and trailing whitespace until the next chunk decides them.
class SpeechStream extends RefCounted:
	var full_text: String = ""
	var meta_seen: bool = false
	var _emitted: int = 0

	func feed(chunk: String) -> String:
		if meta_seen:
			full_text += chunk
			return ""
		full_text += chunk
		var idx: int = full_text.find(MARKER)
		var limit: int
		if idx >= 0:
			meta_seen = true
			limit = idx
		else:
			limit = full_text.length() - _partial_marker_len()
		return _take(limit)

	## Call when the stream ends; releases a held partial marker if no marker ever arrived.
	func finish() -> String:
		if meta_seen:
			return ""
		return _take(full_text.length())

	func _partial_marker_len() -> int:
		var max_k: int = mini(MARKER.length() - 1, full_text.length())
		for k in range(max_k, 0, -1):
			if MARKER.begins_with(full_text.substr(full_text.length() - k)):
				return k
		return 0

	func _take(limit: int) -> String:
		while limit > _emitted and full_text[limit - 1].strip_edges().is_empty():
			limit -= 1
		var start: int = _emitted
		if start == 0:
			while start < limit and full_text[start].strip_edges().is_empty():
				start += 1
		if limit <= start:
			return ""
		_emitted = limit
		return full_text.substr(start, limit - start)
