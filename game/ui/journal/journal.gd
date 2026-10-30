class_name Journal
extends Control
## Journal (toggle with J): today's date, the rumours the player has heard and the people met,
## each with a one-line memory. Pure view over WorldState; it never changes game state.

const RUMOUR_KNOWLEDGE_PREFIX: String = "rumour:"  ## what IntentValidator stores for a shared rumour
const PAGE_COLOR: Color = Color(0.82, 0.74, 0.58)
const INK_COLOR: Color = Color(0.17, 0.11, 0.07)
const FAINT_INK_COLOR: Color = Color(0.38, 0.3, 0.22)
const BACKDROP_COLOR: Color = Color(0.0, 0.0, 0.0, 0.55)
const PAGE_WIDTH_RATIO: float = 0.72
const PAGE_HEIGHT_RATIO: float = 0.8
const MARGIN: int = 36
const SEPARATION: int = 14
const SENTENCE_END: String = "."
const ELLIPSIS: String = "..."
const ABBREVIATIONS: Array[String] = ["Mr", "Mrs", "Dr", "St", "Mt"]

## Tests and tools turn this on to show the journal as soon as it is in the tree.
var start_visible: bool = false

var _date_label: Label
var _rumours_box: VBoxContainer
var _people_box: VBoxContainer


func _ready() -> void:
	_build()
	visible = start_visible
	if visible:
		refresh()
	EventBus.npc_memory_changed.connect(_on_changed)
	EventBus.knowledge_added.connect(_on_knowledge)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_J:
		toggle()
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and key.keycode == KEY_ESCAPE and visible:
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	refresh()
	show()


func close() -> void:
	hide()


## Rebuilds the three sections from WorldState and the clock.
func refresh() -> void:
	_build()
	_date_label.text = "%s   (%s)" % [GameDate.format_shire(WorldClock.now), GameDate.format_iso(WorldClock.now)]
	_fill(_rumours_box, heard_rumours(), str(Config.get_value("journal.empty_rumours", "")))
	var people: Array[String] = []
	for p: Dictionary in met_people():
		people.append("%s: %s" % [p["name"], p["line"]])
	_fill(_people_box, people, str(Config.get_value("journal.empty_people", "")))


## Rumour texts the player has been told, in the order heard.
static func heard_rumours() -> Array[String]:
	var out: Array[String] = []
	for k: Variant in WorldState.knowledge.get(WorldState.PLAYER_ID, []):
		var id: String = str(k)
		if id.begins_with(RUMOUR_KNOWLEDGE_PREFIX):
			var rid: String = id.substr(RUMOUR_KNOWLEDGE_PREFIX.length())
			var text: String = RumourNetwork.resolve_text(rid)
			out.append(text if text != "" else NPCContent.prettify(rid))
	return out


## [{id, name, line}] for every NPC the player has spoken with, most recent first.
static func met_people() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in WorldState.npc_memory:
		var m: Dictionary = WorldState.npc_memory[id]
		if int(m.get("last_talk", -1)) < 0:
			continue
		var card: Dictionary = NPCContent.load_card(id)
		rows.append({"id": id, "name": str(card.get("name", NPCContent.prettify(id))),
				"line": one_line(str(m.get("summary", ""))), "last_talk": int(m["last_talk"])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["last_talk"]) > int(b["last_talk"]))
	return rows


## First sentence of a memory summary, cut to journal.memory_max_chars.
static func one_line(summary: String) -> String:
	var s: String = summary.strip_edges()
	if s.is_empty():
		return str(Config.get_value("journal.no_summary", ""))
	var end: int = _sentence_end(s)
	if end >= 0:
		s = s.substr(0, end + 1)
	var limit: int = int(Config.get_value("journal.memory_max_chars", 140))
	if s.length() > limit:
		s = s.substr(0, limit - ELLIPSIS.length()).strip_edges() + ELLIPSIS
	return s


# Index of the first full stop that ends a sentence; "Mr." and friends do not count.
static func _sentence_end(s: String) -> int:
	var from: int = 0
	while true:
		var i: int = s.find(SENTENCE_END, from)
		if i < 0:
			return -1
		var word_start: int = s.rfind(" ", i) + 1
		if s.substr(word_start, i - word_start) not in ABBREVIATIONS:
			return i
		from = i + 1
	return -1


func rumour_rows() -> int:
	return _live_children(_rumours_box)


func people_rows() -> int:
	return _live_children(_people_box)


# Old rows are freed at end of frame, so they may still be children right after a refresh.
static func _live_children(box: Control) -> int:
	return box.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion()).size()


func _on_changed(_id: String) -> void:
	if visible:
		refresh()


func _on_knowledge(_id: String, _kid: String) -> void:
	if visible:
		refresh()


func _build() -> void:
	if _date_label != null:
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var fs: int = int(Config.get_value("journal.font_size", 24))
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP_COLOR
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var page := PanelContainer.new()
	page.anchor_left = (1.0 - PAGE_WIDTH_RATIO) / 2.0
	page.anchor_right = 1.0 - page.anchor_left
	page.anchor_top = (1.0 - PAGE_HEIGHT_RATIO) / 2.0
	page.anchor_bottom = 1.0 - page.anchor_top
	var style := StyleBoxFlat.new()
	style.bg_color = PAGE_COLOR
	style.set_content_margin_all(MARGIN)
	style.set_corner_radius_all(6)
	page.add_theme_stylebox_override("panel", style)
	add_child(page)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", SEPARATION)
	page.add_child(col)
	col.add_child(_label("Journal", int(Config.get_value("journal.title_font_size", 40)), INK_COLOR))
	_date_label = _label("", fs, FAINT_INK_COLOR)
	col.add_child(_date_label)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", MARGIN)
	col.add_child(cols)
	_rumours_box = _section(cols, "Rumours heard", fs)
	_people_box = _section(cols, "People met", fs)


func _section(parent: Control, title: String, fs: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", SEPARATION)
	parent.add_child(box)
	box.add_child(_label(title, fs + 4, INK_COLOR))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var items := VBoxContainer.new()
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.add_theme_constant_override("separation", SEPARATION)
	scroll.add_child(items)
	return items


func _fill(box: VBoxContainer, lines: Array[String], empty_text: String) -> void:
	for c in box.get_children():
		c.hide()
		c.queue_free()
	var fs: int = int(Config.get_value("journal.font_size", 24))
	if lines.is_empty():
		box.add_child(_label(empty_text, fs, FAINT_INK_COLOR))
		return
	for line in lines:
		box.add_child(_label(line, fs, INK_COLOR))


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
