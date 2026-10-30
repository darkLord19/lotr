class_name MainMenu
extends Control
## Title screen: New Game, Continue (newest save or autosave), Load, Settings, Quit.
## It only reports what the player chose; Main decides what to do about it.

signal new_game_requested
signal continue_requested(slot: String)
signal load_requested(slot: String)
signal quit_requested

const PANEL_WIDTH: float = 620.0

var _box: VBoxContainer
var _panel_root: Control
var _overlay: Control
var _continue: Button
var _load: Button
var _latest: String = ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	MenuKit.backdrop(self, MenuKit.BG_COLOR)
	_panel_root = Control.new()
	_panel_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_root)
	_box = MenuKit.panel(_panel_root, PANEL_WIDTH)
	_box.add_child(MenuKit.heading(str(Config.get_value("menus.title", "Middle-earth")), MenuKit.TITLE_FONT_SIZE))
	var sub: Label = MenuKit.label(str(Config.get_value("menus.subtitle", "")), MenuKit.FONT_SIZE, MenuKit.DIM_COLOR)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(sub)
	_add("New Game", func() -> void: new_game_requested.emit())
	_continue = _add("Continue", func() -> void: continue_requested.emit(_latest))
	_load = _add("Load Game", func() -> void: _open(SlotPicker.new(SlotPicker.Mode.LOAD)))
	_add("Settings", func() -> void: _open(SettingsMenu.new()))
	_add("Quit", func() -> void: quit_requested.emit())
	refresh()


## Re-reads the save folder (called when returning from a game or an overlay).
func refresh() -> void:
	_latest = SaveSystem.latest_slot()
	_continue.disabled = _latest == ""
	_load.disabled = SaveSystem.list_slots().is_empty()
	(_continue if not _continue.disabled else _box.get_child(2) as Button).grab_focus()


func is_overlay_open() -> bool:
	return _overlay != null


func _add(text: String, on_press: Callable) -> Button:
	var b: Button = MenuKit.button(text, on_press)
	_box.add_child(b)
	return b


func _open(overlay: Control) -> void:
	_overlay = overlay
	_panel_root.hide()
	overlay.connect("closed", _close_overlay)
	if overlay is SlotPicker:
		(overlay as SlotPicker).slot_chosen.connect(func(slot: String) -> void: load_requested.emit(slot))
	add_child(overlay)


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_panel_root.show()
	refresh()
