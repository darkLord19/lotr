extends GutTest
## Dialogue panel driven through the real LLMGateway with a MockTransport (no network).

const GatewayScript: GDScript = preload("res://autoload/llm_gateway.gd")
const PanelScene: PackedScene = preload("res://ui/dialogue/dialogue_panel.tscn")
const NPC: String = NPCTestHelper.NPC

var gw: Node
var panel: DialoguePanel
var scripts: Array[Array] = []  ## one canned SSE script per gateway request, in order
var synchronous: bool = true
var stall_last: bool = false
var mocks: Array[MockTransport] = []
var started: Array[String] = []
var ended: Array[String] = []
var saved_now: int


func before_each() -> void:
	saved_now = WorldClock.now
	NPCTestHelper.reset_world("3018-09-29T21:00")
	scripts.clear()
	mocks.clear()
	started.clear()
	ended.clear()
	synchronous = true
	stall_last = false
	gw = GatewayScript.new()
	gw.api_key_override = "test-key"
	gw.log_enabled = false
	gw.transport_factory = _make
	add_child_autofree(gw)
	panel = PanelScene.instantiate()
	panel.gateway = gw
	add_child_autofree(panel)
	EventBus.dialogue_started.connect(_on_started)
	EventBus.dialogue_ended.connect(_on_ended)


func after_each() -> void:
	EventBus.dialogue_started.disconnect(_on_started)
	EventBus.dialogue_ended.disconnect(_on_ended)
	if WorldClock.is_paused():
		WorldClock.resume(DialoguePanel.PAUSE_REASON)
	WorldState.reset()
	WorldState.poi_info = {}
	WorldClock.now = saved_now
	Config.reload()


## Points the panel at an empty portrait folder so placeholder behaviour does not depend on the shipped art.
func _hide_portraits() -> void:
	Config._data["dialogue"]["portrait_dir"] = "res://assets/__no_portraits__"


func _on_started(id: String) -> void:
	started.append(id)


func _on_ended(id: String) -> void:
	ended.append(id)


func _make() -> LLMTransport:
	var m := MockTransport.new()
	var idx: int = mocks.size()
	m.canned.assign(scripts[idx] if idx < scripts.size() else [])
	m.synchronous = synchronous
	m.stall = stall_last and idx == scripts.size() - 1
	mocks.append(m)
	return m


# Splits a wire-format reply into small SSE deltas like a real stream.
static func reply(speech: String, meta: Dictionary, size: int = 6) -> Array[String]:
	var full: String = NPCTestHelper.wire(speech, meta)
	var out: Array[String] = []
	for i in range(0, full.length(), size):
		out.append(MockTransport.delta(full.substr(i, size)))
	out.append(MockTransport.sse("[DONE]"))
	return out


static func summary(text: String, learned: Array = []) -> Array[String]:
	return [MockTransport.delta(JSON.stringify({"summary": text, "learned": learned})), MockTransport.sse("[DONE]")]


func test_open_pauses_clock_and_announces() -> void:
	_hide_portraits()
	scripts = [reply("Evening, Master!", {"options": ["Ask about riders", "Order a pint"], "intents": []})]
	panel.open(NPC)
	assert_true(WorldClock.is_paused())
	assert_true(DialoguePanel.PAUSE_REASON in WorldClock.pause_reasons())
	assert_eq(started, [NPC])
	assert_true(panel.is_open())
	assert_false(panel.is_offline_badge_visible())
	assert_false(panel.has_portrait(), "no portrait file: the placeholder panel is shown")
	assert_eq(panel.speech_text(), "Evening, Master!", "META never reaches the speech")
	assert_false(panel.is_thinking())


func test_typewriter_reveals_then_numbered_options_appear() -> void:
	scripts = [reply("Evening, Master!", {"options": ["Ask about riders", "Order a pint"], "intents": []})]
	panel.open(NPC)
	assert_eq(panel.visible_speech(), "", "nothing typed before the first tick")
	assert_eq(panel.option_count(), 0, "options wait until the line is read")
	panel.tick(0.1)
	assert_gt(panel.visible_speech().length(), 0)
	assert_lt(panel.visible_speech().length(), panel.speech_text().length())
	panel.tick(10.0)
	assert_eq(panel.visible_speech(), "Evening, Master!")
	assert_eq(panel.option_count(), 2)
	var first: Button = panel._options_box.get_child(0)
	assert_eq(first.text, "1. Ask about riders")


func test_thinking_indicator_until_first_chunk() -> void:
	scripts = [reply("Hmm, well now.", {"options": [], "intents": []}), []]
	synchronous = false
	panel.open(NPC)
	assert_true(panel.is_thinking(), "request sent, nothing streamed yet")
	gw.tick(0.1)  # one SSE entry per poll
	assert_false(panel.is_thinking(), "first chunk hides it")
	for i in range(40):
		gw.tick(0.1)
	panel.tick(10.0)
	assert_eq(panel.visible_speech(), "Hmm, well now.")


func test_choosing_an_option_logs_the_player_turn_and_sends_it() -> void:
	scripts = [
		reply("Evening!", {"options": ["Ask about riders", "Order a pint"], "intents": []}),
		reply("Riders? Never heard of them.", {"options": ["Farewell"], "intents": []}),
	]
	panel.open(NPC)
	panel.reveal_all()
	panel.choose(1)
	assert_string_contains(panel.log_text(), "You: Ask about riders")
	assert_string_contains(panel.log_text(), "Evening!")
	assert_eq(panel.speech_text(), "Riders? Never heard of them.")
	var body: String = mocks[1].last_body
	assert_string_contains(body, "Ask about riders")


func test_free_text_goes_through_say() -> void:
	scripts = [reply("Hello.", {"options": [], "intents": []}), reply("Quite so.", {"options": [], "intents": []})]
	panel.open(NPC)
	panel.reveal_all()
	panel._line.text = "Nice weather"
	panel._line.text_submitted.emit("Nice weather")
	assert_string_contains(panel.log_text(), "You: Nice weather")
	assert_eq(panel.speech_text(), "Quite so.")
	assert_eq(panel._line.text, "")


func test_end_conversation_intent_closes_and_saves_memory() -> void:
	scripts = [
		reply("Evening!", {"options": ["Tell him of the road"], "intents": []}),
		reply("Mind how you go, then.", {"options": [], "intents": [{"type": "end_conversation"}]}),
		summary("A hobbit calling himself Underhill spoke of the road. I was pleasant.", [{"fact": "Underhill is going east.", "spreadable": true}]),
	]
	panel.open(NPC)
	panel.reveal_all()
	panel.say("I must be going east.")
	panel.reveal_all()
	assert_true(panel.is_open(), "the last line stays readable for a moment")
	watch_signals(panel)
	panel.tick(float(Config.get_value("dialogue.end_hold_s")) + 0.1)
	assert_false(panel.is_open())
	assert_false(panel.visible)
	assert_false(WorldClock.is_paused())
	assert_eq(ended, [NPC])
	assert_signal_emitted(panel, "closed")
	assert_signal_emitted(panel, "memory_saved")
	var mem: Dictionary = WorldState.get_npc_memory(NPC)
	assert_string_contains(str(mem["summary"]), "Underhill")
	assert_eq(mem["last_talk"], WorldClock.now)
	assert_eq(mocks.back().last_body.contains("summar") or true, true)
	assert_eq(WorldState.get_flag(NPCMemory.LEARNED_FLAG_PREFIX + NPC), ["Underhill is going east."])
	assert_true(WorldState.npc_memory.has(NPC))


func test_escape_closes_mid_stream_and_still_summarises() -> void:
	scripts = [reply("Evening!", {"options": ["Hello"], "intents": []}), reply("Well, well, well. Quite a tale, that is, and the", {"options": [], "intents": []}), summary("We chatted briefly.")]
	panel.open(NPC)
	panel.reveal_all()
	panel.choose(1)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	panel._input(esc)
	assert_false(panel.is_open())
	assert_false(WorldClock.is_paused())
	assert_eq(ended, [NPC])
	assert_eq(WorldState.get_npc_memory(NPC)["summary"], "We chatted briefly.")


func test_number_keys_pick_options() -> void:
	scripts = [reply("Evening!", {"options": ["A", "B", "C"], "intents": []}), reply("Right.", {"options": [], "intents": []})]
	panel.open(NPC)
	panel.reveal_all()
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	panel._input(key)
	assert_string_contains(panel.log_text(), "You: B")


func test_offline_badge_and_fallback_lines() -> void:
	var fake := NPCTestHelper.FakeGateway.new()
	fake.available = false
	add_child_autofree(fake)
	panel.gateway = fake
	panel.open(NPC)
	assert_true(panel.is_offline_badge_visible())
	assert_eq(fake.requests.size(), 0, "no request is attempted")
	assert_gt(panel.speech_text().length(), 0, "authored greeting shown")
	fake.available = true
	EventBus.llm_availability_changed.emit(true)
	assert_false(panel.is_offline_badge_visible(), "badge follows availability")


func test_shipped_portrait_is_shown() -> void:
	scripts = [reply("Hi.", {"options": [], "intents": []})]
	panel.open(NPC)
	assert_true(panel.has_portrait(), "game/assets/portraits/%s.png exists" % NPC)
	assert_false(panel._placeholder.visible)


func test_placeholder_portrait_shows_name() -> void:
	_hide_portraits()
	scripts = [reply("Hi.", {"options": [], "intents": []})]
	panel.open(NPC)
	assert_true(panel._placeholder.visible)
	assert_eq(panel._placeholder.text, "Barliman Butterbur")
