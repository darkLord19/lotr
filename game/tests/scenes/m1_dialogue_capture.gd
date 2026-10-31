extends Control
## Capture scene for tools/capture.sh: opens the dialogue panel or the journal against a mock
## gateway (no network). Pick with --stage=mid|done|journal after the `--` separator.
## Example: tools/capture.sh res://tests/scenes/m1_dialogue_capture.tscn out.png --stage=mid --after=2

const GatewayScript: GDScript = preload("res://autoload/llm_gateway.gd")
const NPC: String = "barliman_butterbur"
const BACKDROP_TOP: Color = Color(0.16, 0.2, 0.17)
const BACKDROP_BOTTOM: Color = Color(0.05, 0.06, 0.05)
const STREAM_PIECE_CHARS: int = 5

var _scripts: Array[Array] = []
var _mocks: Array[MockTransport] = []
var _stall_last: bool = false


func _ready() -> void:
	var stage: String = "mid"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stage="):
			stage = a.substr("--stage=".length())
	_backdrop()
	WorldState.reset()
	WorldState.poi_info = {}
	WorldClock.now = GameDate.parse("3018-09-29T21:00")
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", "prancing_pony", "", {"race": "hobbit"})
	WorldState.spawn_entity(NPC, "npc", "prancing_pony")
	if stage == "journal":
		_journal()
	else:
		_dialogue(stage == "mid")


func _backdrop() -> void:
	var g := Gradient.new()
	g.set_color(0, BACKDROP_TOP)
	g.set_color(1, BACKDROP_BOTTOM)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	var rect := TextureRect.new()
	rect.texture = tex
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	add_child(rect)


func _reply(speech: String, meta: Dictionary) -> Array[String]:
	var full: String = "%s\n%s\n%s" % [speech, ReplyParser.MARKER, JSON.stringify(meta)]
	var out: Array[String] = []
	for i in range(0, full.length(), STREAM_PIECE_CHARS):
		out.append(MockTransport.delta(full.substr(i, STREAM_PIECE_CHARS)))
	out.append(MockTransport.sse("[DONE]"))
	return out


func _make() -> LLMTransport:
	var m := MockTransport.new()
	var idx: int = _mocks.size()
	m.canned.assign(_scripts[idx])
	var last: bool = idx == _scripts.size() - 1
	m.synchronous = not (last and _stall_last)
	m.stall = last and _stall_last
	_mocks.append(m)
	return m


func _dialogue(mid_stream: bool) -> void:
	var gw: Node = GatewayScript.new()
	gw.api_key_override = "capture-key"
	gw.log_enabled = false
	gw.transport_factory = _make
	add_child(gw)
	_scripts = [
		_reply("Evening, Master Underhill! Come in, come in, and mind the draught. The common room is full tonight, what with the road so busy these days.",
				{"options": ["Ask about strange riders", "Order a pint of ale", "Ask about a ranger called Strider", "Ask for a quiet room"], "intents": []}),
		_reply("Riders, you say? Well now, I can't say I have seen any, though Nob mentioned some odd travellers by the West-gate, tall and silent, and not a word out of them for two days together, mark my words, and the dogs would not go near them.",
				{"options": ["Ask where they went", "Thank him and leave"], "intents": []}),
	]
	_stall_last = mid_stream
	var panel: DialoguePanel = load("res://ui/dialogue/dialogue_panel.tscn").instantiate()
	panel.gateway = gw
	add_child(panel)
	panel.open(NPC)
	panel.reveal_all()
	panel.choose(1)


func _journal() -> void:
	WorldState.add_knowledge(WorldState.PLAYER_ID, "rumour:black_riders_asking_for_baggins")
	WorldState.add_knowledge(WorldState.PLAYER_ID, "rumour:dwarves_going_east")
	WorldState.add_knowledge(WorldState.PLAYER_ID, "rumour:player_found_senseless")
	WorldState.set_flag("rumour_subject.player_found_senseless", "Hamfast Underhill")
	WorldState.set_npc_memory(NPC, "I poured Mr. Underhill a pint and he asked sharply after riders; I could tell he was frightened of something. I liked him well enough.", GameDate.parse("3018-09-29T20:30"), 1)
	WorldState.set_npc_memory("gaffer_gamgee", "He asked after Mr. Frodo, and I told him of the black-cloaked stranger at Bagshot Row.", GameDate.parse("3018-09-24T09:00"), 0)
	var j: Journal = load("res://ui/journal/journal.tscn").instantiate()
	j.start_visible = true
	add_child(j)
