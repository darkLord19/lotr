class_name PauseMenu
extends Control
## In-game pause menu (Esc): Resume, Save, Load, Settings, back to the main menu, Quit.
## Opening it holds the world clock under its own pause reason, so it stacks with dialogue pauses.

signal load_requested(slot: String)
signal quit_to_menu_requested
signal quit_requested

const PAUSE_REASON: StringName = &"pause_menu"
const PANEL_WIDTH: float = 620.0

var _panel_root: Control
var _overlay: Control
var _is_open: bool = false


func _ready() -> void:
	# Must keep receiving input while the tree is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuKit.backdrop(self, MenuKit.SCRIM_COLOR)
	_panel_root = Control.new()
	_panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_root)
	var box: VBoxContainer = MenuKit.panel(_panel_root, PANEL_WIDTH)
	box.add_child(MenuKit.heading("Paused"))
	var resume_btn: Button = MenuKit.button("Resume", close)
	box.add_child(resume_btn)
	box.add_child(MenuKit.button("Save Game", func() -> void: _open(SlotPicker.new(SlotPicker.Mode.SAVE))))
	box.add_child(MenuKit.button("Load Game", func() -> void: _open(SlotPicker.new(SlotPicker.Mode.LOAD))))
	box.add_child(MenuKit.button("Settings", func() -> void: _open(SettingsMenu.new())))
	box.add_child(MenuKit.button("Main Menu", func() -> void: quit_to_menu_requested.emit()))
	box.add_child(MenuKit.button("Quit", func() -> void: quit_requested.emit()))
	visible = _is_open


func _exit_tree() -> void:
	if _is_open:
		WorldClock.resume(PAUSE_REASON)
		_is_open = false


func is_open() -> bool:
	return _is_open


func open() -> void:
	if _is_open:
		return
	_is_open = true
	WorldClock.pause(PAUSE_REASON)
	if is_inside_tree():
		get_tree().paused = true
	# PlayerSession stops processing while the tree is paused, so it cannot free the cursor; it re-captures it after close().
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()


func close() -> void:
	if not _is_open:
		return
	_close_overlay()
	_is_open = false
	WorldClock.resume(PAUSE_REASON)
	if is_inside_tree():
		get_tree().paused = false
	hide()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


# Esc opens the menu; with it open, overlays (and then this menu) consume Esc first.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _overlay != null:
		_close_overlay()
	else:
		toggle()


func _open(overlay: Control) -> void:
	_overlay = overlay
	_panel_root.hide()
	overlay.connect("closed", _close_overlay)
	if overlay is SlotPicker:
		var picker: SlotPicker = overlay
		picker.slot_chosen.connect(func(slot: String) -> void:
			if picker.mode == SlotPicker.Mode.LOAD:
				load_requested.emit(slot))
	add_child(overlay)


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
	_panel_root.show()
