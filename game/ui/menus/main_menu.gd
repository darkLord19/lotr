class_name MainMenu
extends Control
## Title screen: New Game, Continue (newest save or autosave), Load, Settings, Quit.
## It only reports what the player chose; Main decides what to do about it.

signal new_game_requested
signal continue_requested(slot: String)
signal load_requested(slot: String)
signal quit_requested

const PANEL_WIDTH: float = 640.0
const MAP_TEXTURE_PATH: String = "res://assets/ui/region_map.png"

var _box: VBoxContainer
var _panel_root: Control
var _overlay: Control
var _new_game: Button
var _continue: Button
var _load: Button
var _latest: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	MenuKit.backdrop(self, MenuKit.BG_COLOR)

	# Atmospheric illustrated map backdrop with dark vignette scrim
	if ResourceLoader.exists(MAP_TEXTURE_PATH):
		var map_tex: Texture2D = load(MAP_TEXTURE_PATH) as Texture2D
		if map_tex != null:
			var bg_tex := TextureRect.new()
			bg_tex.texture = map_tex
			bg_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bg_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			bg_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			bg_tex.modulate = Color(0.42, 0.40, 0.35, 0.48)
			bg_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(bg_tex)

	var scrim := ColorRect.new()
	scrim.color = Color(0.06, 0.07, 0.05, 0.62)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_panel_root = Control.new()
	_panel_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_root)

	_box = MenuKit.panel(_panel_root, PANEL_WIDTH)
	_box.add_child(MenuKit.heading(str(Config.get_value("menus.title", "Middle-earth")), MenuKit.TITLE_FONT_SIZE))
	var sub: Label = MenuKit.label(str(Config.get_value("menus.subtitle", "— The War of the Ring —")), MenuKit.FONT_SIZE - 2, MenuKit.DIM_COLOR)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(sub)

	_new_game = _add("New Game", func() -> void: new_game_requested.emit())
	_continue = _add("Continue", func() -> void: continue_requested.emit(_latest))
	_load = _add("Load Game", func() -> void: _open(SlotPicker.new(SlotPicker.Mode.LOAD)))
	_add("Settings", func() -> void: _open(SettingsMenu.new()))
	_add("Quit", func() -> void: quit_requested.emit())

	# Subtle ambient footer
	var footer := Label.new()
	footer.text = "Third Age 3018  •  Western Eriador  •  Tolkien Lore Simulation"
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_bottom = -16
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", Color(0.55, 0.58, 0.50, 0.75))
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel_root.add_child(footer)

	refresh()


## Re-reads the save folder (called when returning from a game or an overlay).
func refresh() -> void:
	_latest = SaveSystem.latest_slot()
	_continue.disabled = _latest == ""
	_load.disabled = SaveSystem.list_slots().is_empty()
	if not _continue.disabled:
		_continue.grab_focus()
	elif _new_game != null:
		_new_game.grab_focus()
	elif _box.get_child_count() > 2 and _box.get_child(2) is Button:
		(_box.get_child(2) as Button).grab_focus()


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
