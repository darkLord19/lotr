class_name NPCMind
extends RefCounted
## One conversation with one NPC. Runs a turn end to end:
## prompt -> LLMGateway (speech streamed until ---META---) -> parse META -> validate+apply intents,
## falling back to authored lines when the gateway is unavailable or the reply fails.
##
##   var mind := NPCMind.new("barliman_butterbur")
##   mind.say("Any news?", on_speech, on_turn)      # on_speech(piece: String), on_turn(turn: Dictionary)
##   mind.end_conversation(on_memory)               # on_memory(result: Dictionary)
##
## Turn dictionary: {ok, source: "llm"|"fallback", speech, options, mood, applied, rejected,
## end_conversation, error}.

const SOURCE_LLM: String = "llm"
const SOURCE_FALLBACK: String = "fallback"

var npc_id: String
var card: Dictionary
var turns: Array = []  ## {role, text}; npc text is the wire-format reply
var gateway: Node  ## LLMGateway autoload unless a test injects another
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var prompt_opts: Dictionary = {}  ## optional {weather, present}
var ended: bool = false

var _used_lines: Array = []
var _npc_turns: int = 0
var _busy: bool = false


func _init(npc: String, card_override: Dictionary = {}) -> void:
	npc_id = npc
	card = card_override if not card_override.is_empty() else NPCContent.load_card(npc)
	gateway = Engine.get_main_loop().root.get_node_or_null("LLMGateway") if Engine.get_main_loop() is SceneTree else null


func is_busy() -> bool:
	return _busy


## player_text may be empty for the opening greeting.
func say(player_text: String, on_speech: Callable, on_turn: Callable) -> void:
	if _busy or ended:
		return
	_busy = true
	if card.is_empty():
		_finish_turn({"ok": false, "source": SOURCE_FALLBACK, "speech": "", "options": [], "intents": [], "mood": "", "error": "unknown_npc:%s" % npc_id}, on_turn)
		return
	var text: String = player_text.strip_edges()
	if not text.is_empty():
		turns.append({"role": PromptBuilder.ROLE_PLAYER, "text": text})
	if gateway == null or not gateway.is_available():
		_use_fallback(text, "unavailable", on_speech, on_turn)
		return
	var stream := ReplyParser.SpeechStream.new()
	var shown: Array[String] = [""]  ## speech already pushed to the UI
	var on_chunk: Callable = func(piece: String) -> void:
		var out: String = stream.feed(piece)
		if not out.is_empty():
			shown[0] += out
			if on_speech.is_valid():
				on_speech.call(out)
	var on_done: Callable = func(res: Dictionary) -> void:
		var tail: String = stream.finish()
		if not tail.is_empty():
			shown[0] += tail
			if on_speech.is_valid():
				on_speech.call(tail)
		_on_llm_done(res, text, shown[0], on_speech, on_turn)
	var messages: Array = PromptBuilder.build(npc_id, card, turns, WorldClock.now, prompt_opts)
	gateway.request(str(card.get("tier", "standard")), messages, on_chunk, on_done)


## Summarises into WorldState.npc_memory. on_done(result: {ok, summary, learned, error}).
func end_conversation(on_done: Callable) -> void:
	if ended:
		return
	ended = true
	var finish: Callable = func(r: Dictionary) -> void:
		if on_done.is_valid():
			on_done.call(r)
	# Only worth a model call when the player actually said something and the model was involved.
	var had_llm: bool = false
	for t: Dictionary in turns:
		if t.get("llm", false):
			had_llm = true
	if not had_llm or gateway == null:
		var mem: Dictionary = WorldState.get_npc_memory(npc_id)
		if not turns.is_empty():
			WorldState.set_npc_memory(npc_id, str(mem["summary"]), WorldClock.now, int(mem["disposition"]))
		finish.call({"ok": false, "summary": mem["summary"], "learned": [], "error": "no_llm_turns"})
		return
	NPCMemory.summarise(gateway, npc_id, card, turns, WorldClock.now, finish)


func _on_llm_done(res: Dictionary, player_text: String, shown: String, on_speech: Callable, on_turn: Callable) -> void:
	var parsed: Dictionary = ReplyParser.parse(str(res.get("text", "")))
	var speech: String = str(parsed["speech"])
	if not res.get("ok", false) and shown.is_empty():
		_use_fallback(player_text, str(res.get("error", "failed")), on_speech, on_turn)
		return
	if speech.is_empty():
		_use_fallback(player_text, "empty_speech", on_speech, on_turn)
		return
	var options: Array = parsed["options"]
	if not res.get("ok", false):
		# Stream died after the player already read part of it: keep that text, no intents.
		var partial: Array[String] = []
		partial.assign(Config.get_value("npc.fallback_options", []))
		options = partial
		parsed["intents"] = []
	elif not parsed["meta_ok"] and options.is_empty():
		options = Config.get_value("npc.fallback_options", [])
	var turn: Dictionary = {
		"ok": res.get("ok", false), "source": SOURCE_LLM, "speech": speech, "options": options,
		"mood": parsed["mood"], "intents": parsed["intents"], "error": str(res.get("error", "")),
		"raw": str(res.get("text", "")),
	}
	_finish_turn(turn, on_turn)


func _use_fallback(player_text: String, why: String, on_speech: Callable, on_turn: Callable) -> void:
	var kind: String = DialogueFallback.classify(player_text, _npc_turns == 0)
	var fb: Dictionary = DialogueFallback.respond(npc_id, card, WorldClock.now, kind, _used_lines, rng)
	if on_speech.is_valid():
		on_speech.call(fb["speech"])
	fb["ok"] = true
	fb["error"] = why
	_finish_turn(fb, on_turn)


func _finish_turn(turn: Dictionary, on_turn: Callable) -> void:
	var ctx: Dictionary = {"npc_id": npc_id, "card": card, "now": WorldClock.now}
	var res: Dictionary = IntentValidator.validate_and_apply(turn.get("intents", []), ctx)
	turn["applied"] = res["applied"]
	turn["rejected"] = res["rejected"]
	turn["end_conversation"] = res["end_conversation"]
	turn.erase("intents")
	if not (turn.get("speech", "") as String).is_empty():
		var raw: String = turn.get("raw", "")
		if raw.is_empty():
			raw = "%s\n%s\n%s" % [turn["speech"], ReplyParser.MARKER, JSON.stringify({"options": turn["options"], "intents": [], "mood": turn.get("mood", "")})]
		turns.append({"role": PromptBuilder.ROLE_NPC, "text": raw, "llm": turn.get("source") == SOURCE_LLM})
		_npc_turns += 1
	_busy = false
	if on_turn.is_valid():
		on_turn.call(turn)
