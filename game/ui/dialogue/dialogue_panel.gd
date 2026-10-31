class_name DialoguePanel
extends Control
## Dialogue panel: portrait slot on the left, streamed NPC speech with a typewriter reveal, a log
## of the conversation, numbered option buttons (keys 1-4), a free-text line and a "thinking"
## indicator until the first chunk arrives. Opening pauses the world clock under the reason
## &"dialogue"; closing (Esc, the Leave button or an end_conversation intent) resumes it and
## summarises the talk into WorldState.npc_memory in the background.
##
## The LLM is never trusted here: NPCMind validates intents; the panel only shows text.

signal turn_finished(turn: Dictionary)
signal closed(npc_id: String)
## Fired when the background memory summary finished (ok or not); WorldState.npc_memory is updated by then.
signal memory_saved(npc_id: String, result: Dictionary)

const PAUSE_REASON: StringName = &"dialogue"
const PORTRAIT_EXT: String = ".png"
const BG_COLOR: Color = Color(0.11, 0.09, 0.07, 0.96)
const PLACEHOLDER_COLOR: Color = Color(0.25, 0.2, 0.15)
const OFFLINE_COLOR: Color = Color(0.85, 0.35, 0.25)
const PLAYER_COLOR: String = "#c9b27a"
const NPC_COLOR: String = "#e9e2d0"
const THINKING_COLOR: Color = Color(0.75, 0.7, 0.55)
const SEPARATION: int = 12

## Injected by tests and tools; defaults to the LLMGateway autoload.
var gateway: Node = null
var npc_id: String = ""
var mind: NPCMind = null
var free_on_close: bool = false

var _open: bool = false
var _busy: bool = false
var _turn_done: bool = false
var _ending: bool = false
var _end_timer: float = 0.0
var _target: String = ""
var _typed: float = 0.0
var _think_t: float = 0.0
var _options_shown: bool = false
var _pending_options: Array = []
var _log_entries: int = 0
var _display_name: String = ""

var _portrait_slot: PanelContainer
var _portrait_tex: TextureRect
var _placeholder: Label
var _name_label: Label
var _badge: Label
var _history: RichTextLabel
var _speech: RichTextLabel
var _thinking: Label
var _options_box: VBoxContainer
var _line: LineEdit
var _leave: Button


func _ready() -> void:
	_build()
	hide()


func _build() -> void:
	if _portrait_slot != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var margin: int = int(Config.get_value("dialogue.panel_margin", 24))
	var fs: int = int(Config.get_value("dialogue.font_size", 26))
	var frame := PanelContainer.new()
	frame.anchor_left = 0.0
	frame.anchor_right = 1.0
	frame.anchor_top = 1.0 - float(Config.get_value("dialogue.panel_height_ratio", 0.52))
	frame.anchor_bottom = 1.0
	frame.offset_left = margin
	frame.offset_right = -margin
	frame.offset_top = 0
	frame.offset_bottom = -margin
	var style := StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.set_content_margin_all(margin)
	style.set_corner_radius_all(8)
	frame.add_theme_stylebox_override("panel", style)
	add_child(frame)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", margin)
	frame.add_child(row)

	var portrait_px: float = float(Config.get_value("dialogue.portrait_size", 320))
	_portrait_slot = PanelContainer.new()
	_portrait_slot.custom_minimum_size = Vector2(portrait_px, portrait_px)
	_portrait_slot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = PLACEHOLDER_COLOR
	pstyle.set_corner_radius_all(6)
	_portrait_slot.add_theme_stylebox_override("panel", pstyle)
	row.add_child(_portrait_slot)
	_portrait_tex = TextureRect.new()
	_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_slot.add_child(_portrait_tex)
	_placeholder = Label.new()
	_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placeholder.add_theme_font_size_override("font_size", fs)
	_portrait_slot.add_child(_placeholder)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", SEPARATION)
	row.add_child(col)

	var head := HBoxContainer.new()
	col.add_child(head)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", int(Config.get_value("journal.title_font_size", 40)))
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name_label)
	_badge = Label.new()
	_badge.text = str(Config.get_value("dialogue.offline_text", "OFFLINE"))
	_badge.add_theme_font_size_override("font_size", fs)
	_badge.add_theme_color_override("font_color", OFFLINE_COLOR)
	head.add_child(_badge)

	_history = RichTextLabel.new()
	_history.bbcode_enabled = true
	_history.scroll_following = true
	_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history.custom_minimum_size.y = fs * 3
	_history.add_theme_font_size_override("normal_font_size", fs - 4)
	_history.add_theme_color_override("default_color", Color(0.7, 0.68, 0.6))
	col.add_child(_history)

	_speech = RichTextLabel.new()
	_speech.fit_content = true
	_speech.scroll_active = false
	_speech.add_theme_font_size_override("normal_font_size", fs)
	_speech.add_theme_color_override("default_color", Color(NPC_COLOR))
	col.add_child(_speech)

	_thinking = Label.new()
	_thinking.add_theme_font_size_override("font_size", fs)
	_thinking.add_theme_color_override("font_color", THINKING_COLOR)
	col.add_child(_thinking)

	_options_box = VBoxContainer.new()
	col.add_child(_options_box)

	var bottom := HBoxContainer.new()
	col.add_child(bottom)
	_line = LineEdit.new()
	_line.placeholder_text = str(Config.get_value("dialogue.say_something_else", "Say something else..."))
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.add_theme_font_size_override("font_size", fs)
	_line.text_submitted.connect(_on_text_submitted)
	bottom.add_child(_line)
	_leave = Button.new()
	_leave.text = "Leave (Esc)"
	_leave.add_theme_font_size_override("font_size", fs)
	_leave.pressed.connect(close)
	bottom.add_child(_leave)


# --- public API ------------------------------------------------------------

func is_open() -> bool:
	return _open


func has_portrait() -> bool:
	return _portrait_tex != null and _portrait_tex.texture != null


func is_thinking() -> bool:
	return _thinking != null and _thinking.visible


func is_offline_badge_visible() -> bool:
	return _badge.visible


func option_count() -> int:
	return _options_box.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion()).size()


func speech_text() -> String:
	return _target


func visible_speech() -> String:
	return _target.substr(0, int(_typed))


func is_typing() -> bool:
	return int(_typed) < _target.length()


func log_text() -> String:
	return _history.get_parsed_text()


## Starts a conversation: pauses the world, shows the portrait and asks for the NPC's greeting.
func open(npc: String, card_override: Dictionary = {}) -> void:
	_build()
	if _open:
		return
	npc_id = npc
	mind = NPCMind.new(npc, card_override)
	if gateway != null:
		mind.gateway = gateway
	else:
		gateway = mind.gateway
	_display_name = str(mind.card.get("name", NPCContent.prettify(npc)))
	_name_label.text = _display_name
	_open = true
	_ending = false
	_log_entries = 0
	_history.clear()
	_target = ""
	_typed = 0.0
	_clear_options()
	_set_portrait()
	_refresh_badge()
	if not EventBus.llm_availability_changed.is_connected(_on_availability):
		EventBus.llm_availability_changed.connect(_on_availability)
	show()
	WorldClock.pause(PAUSE_REASON)
	EventBus.dialogue_started.emit(npc)
	_begin_turn("")


## Option number 1..4 (as shown on the buttons).
func choose(number: int) -> void:
	if not _options_shown or number < 1 or number > _pending_options.size():
		return
	_begin_turn(str(_pending_options[number - 1]))


## Free text typed by the player.
func say(text: String) -> void:
	if _busy or not _open or text.strip_edges().is_empty():
		return
	_begin_turn(text.strip_edges())


## Reveals the whole line at once (also what a click on the speech does).
func reveal_all() -> void:
	_typed = float(_target.length())
	_after_reveal()


func close() -> void:
	if not _open:
		return
	_open = false
	hide()
	WorldClock.resume(PAUSE_REASON)
	var who: String = npc_id
	var m: NPCMind = mind
	# Background: the panel is gone before the summary returns; the callback only touches WorldState.
	m.end_conversation(func(result: Dictionary) -> void:
		memory_saved.emit(who, result)
	)
	EventBus.dialogue_ended.emit(who)
	closed.emit(who)
	if free_on_close:
		queue_free()


## Advances the typewriter and the thinking dots; _process calls this.
func tick(delta: float) -> void:
	if not _open:
		return
	if _thinking.visible:
		_think_t += delta
		var period: float = maxf(float(Config.get_value("dialogue.thinking_dot_period_s", 0.4)), 0.01)
		var dots: int = int(_think_t / period) % int(Config.get_value("dialogue.thinking_dots", 3)) + 1
		_thinking.text = str(Config.get_value("dialogue.thinking_text", "thinking")) + ".".repeat(dots)
	if is_typing():
		_typed = minf(_typed + float(Config.get_value("dialogue.chars_per_second", 70.0)) * Settings.text_speed() * delta, float(_target.length()))
		_speech.visible_characters = int(_typed)
		if not is_typing():
			_after_reveal()
	elif _ending and _turn_done:
		_end_timer -= delta
		if _end_timer <= 0.0:
			close()


# --- internals -------------------------------------------------------------

func _process(delta: float) -> void:
	tick(delta)


func _input(event: InputEvent) -> void:
	if not _open or not (event is InputEventKey) or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	var key: int = (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif key >= KEY_1 and key < KEY_1 + int(Config.get_value("dialogue.max_option_keys", 4)) and not _line.has_focus():
		choose(key - KEY_1 + 1)
		get_viewport().set_input_as_handled()
	elif key == KEY_ENTER and not _line.has_focus():
		_line.grab_focus()
		get_viewport().set_input_as_handled()
	elif key == KEY_SPACE and is_typing() and not _line.has_focus():
		reveal_all()
		get_viewport().set_input_as_handled()


func _on_text_submitted(text: String) -> void:
	_line.clear()
	_line.release_focus()
	say(text)


func _begin_turn(player_text: String) -> void:
	_busy = true
	_turn_done = false
	_clear_options()
	if not _target.is_empty():
		_log_line(_display_name, _target, NPC_COLOR)
	if not player_text.is_empty():
		_log_line("You", player_text, PLAYER_COLOR)
	_target = ""
	_typed = 0.0
	_speech.text = ""
	_speech.visible_characters = 0
	_think_t = 0.0
	_thinking.text = str(Config.get_value("dialogue.thinking_text", "thinking")) + "."
	_thinking.show()
	_refresh_badge()
	mind.say(player_text, _on_speech, _on_turn)


func _on_speech(piece: String) -> void:
	if not _open:
		return
	_thinking.hide()
	_target += piece
	_speech.text = _target
	_speech.visible_characters = int(_typed)


func _on_turn(turn: Dictionary) -> void:
	_busy = false
	_turn_done = true
	if not _open:
		return
	_thinking.hide()
	if _target.is_empty():
		_target = str(Config.get_value("npc.no_fallback_line", "..."))
		_speech.text = _target
		_speech.visible_characters = 0
	_pending_options = turn.get("options", [])
	_ending = bool(turn.get("end_conversation", false))
	_end_timer = float(Config.get_value("dialogue.end_hold_s", 2.5))
	_refresh_badge()
	turn_finished.emit(turn)
	if not is_typing():
		_after_reveal()


func _after_reveal() -> void:
	_speech.visible_characters = -1 if _typed >= _target.length() else int(_typed)
	if _turn_done and not _ending and not _options_shown:
		_show_options()


func _show_options() -> void:
	_options_shown = true
	var fs: int = int(Config.get_value("dialogue.option_font_size", 24))
	var limit: int = int(Config.get_value("dialogue.max_option_keys", 4))
	for i in range(mini(_pending_options.size(), limit)):
		var b := Button.new()
		b.text = "%d. %s" % [i + 1, str(_pending_options[i])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", fs)
		b.focus_mode = Control.FOCUS_NONE
		var number: int = i + 1
		b.pressed.connect(func() -> void: choose(number))
		_options_box.add_child(b)


func _clear_options() -> void:
	_options_shown = false
	for c in _options_box.get_children():
		# Freed at end of frame: a button may be the one whose press led here.
		c.hide()
		c.queue_free()


func _log_line(who: String, text: String, color: String) -> void:
	_log_entries += 1
	_history.append_text("[color=%s][b]%s:[/b] %s[/color]\n" % [color, _esc(who), _esc(text)])


# Square brackets would be read as BBCode tags.
static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _set_portrait() -> void:
	var path: String = "%s/%s%s" % [str(Config.get_value("dialogue.portrait_dir", "res://assets/portraits")), npc_id, PORTRAIT_EXT]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_portrait_tex.texture = tex
	_portrait_tex.visible = tex != null
	_placeholder.visible = tex == null
	_placeholder.text = _display_name
	_placeholder.add_theme_color_override("font_color", THINKING_COLOR)


func _refresh_badge() -> void:
	_badge.visible = gateway == null or not gateway.is_available()


func _on_availability(_available: bool) -> void:
	if _badge != null:
		_refresh_badge()
