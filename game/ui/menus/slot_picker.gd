class_name SlotPicker
extends Control
## Save or load slot list. Save mode shows the manual slots (writes straight through SaveSystem);
## load mode also lists the autosaves and emits `slot_chosen` for the caller to perform the load,
## because what a load must reset depends on where it was started (menu or in-game).

enum Mode { SAVE, LOAD }

signal slot_chosen(slot: String)
signal closed

const PANEL_WIDTH: float = 1100.0
const SLOT_BUTTON_SIZE: Vector2 = Vector2(1000, 72)
const EMPTY_TEXT: String = "Empty"

var mode: Mode = Mode.LOAD

var _list: VBoxContainer
var _status: Label


func _init(p_mode: Mode = Mode.LOAD) -> void:
	mode = p_mode


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	MenuKit.backdrop(self, MenuKit.SCRIM_COLOR)
	var box: VBoxContainer = MenuKit.panel(self, PANEL_WIDTH)
	box.add_child(MenuKit.heading("Save Game" if mode == Mode.SAVE else "Load Game"))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", MenuKit.SEPARATION)
	box.add_child(_list)
	_status = MenuKit.label("", MenuKit.FONT_SIZE - 2, MenuKit.DIM_COLOR)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	var back: Button = MenuKit.button("Back", close)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	refresh()


func close() -> void:
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Slots shown in this mode, in display order.
func slots() -> Array[String]:
	var out: Array[String] = SaveSystem.manual_slots()
	if mode == Mode.LOAD:
		out.append_array(SaveSystem.autosave_slots())
	return out


func refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for slot in slots():
		var info: Dictionary = SaveSystem.slot_info(slot)
		var b: Button = MenuKit.button(_describe(slot, info), _on_slot_pressed.bind(slot))
		b.custom_minimum_size = SLOT_BUTTON_SIZE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.name = slot
		# Nothing to load from an empty slot; saving into one is the point.
		b.disabled = info.is_empty() and mode == Mode.LOAD
		_list.add_child(b)


func _describe(slot: String, info: Dictionary) -> String:
	var title: String = slot.replace("_", " ").capitalize()
	if info.is_empty():
		return "%s    %s" % [title, EMPTY_TEXT]
	var who: String = str(info["player"]) if str(info["player"]) != "" else "-"
	return "%s    %s    %s" % [title, who, GameDate.format_iso(int(info["clock_now"]))]


func _on_slot_pressed(slot: String) -> void:
	if mode == Mode.LOAD:
		slot_chosen.emit(slot)
		return
	var err: Error = SaveSystem.save(slot)
	if err == OK:
		_status.add_theme_color_override("font_color", MenuKit.OK_COLOR)
		_status.text = "Saved to %s." % slot.replace("_", " ")
		slot_chosen.emit(slot)
	else:
		_status.add_theme_color_override("font_color", MenuKit.ERROR_COLOR)
		_status.text = "Could not save (%s)." % error_string(err)
	refresh()
