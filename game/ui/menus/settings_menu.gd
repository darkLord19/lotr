class_name SettingsMenu
extends Control
## Settings screen. Every control writes through Settings.set_value(), which applies it to the
## running game immediately; the file is written when a slider is released and on close.

signal closed

const PANEL_WIDTH: float = 1100.0
const LABEL_WIDTH: float = 360.0
const VALUE_WIDTH: float = 110.0
const SLIDER_STEP: float = 0.05
const CLOCK_STEP: float = 0.1
const MODE_TEXT: Dictionary = {
	"A": "Mode A: the world never waits.",
	"B": "Mode B: major events wait for you, within a window.",
}

var _mode_a: CheckBox
var _mode_b: CheckBox
var _mode_desc: Label
var _quality: OptionButton
var _quality_names: Array[String] = []
var _sliders: Dictionary = {}  # setting key -> HSlider
var _value_labels: Dictionary = {}  # setting key -> Label
var _syncing: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	MenuKit.backdrop(self, MenuKit.SCRIM_COLOR)
	var box: VBoxContainer = MenuKit.panel(self, PANEL_WIDTH)
	box.add_child(MenuKit.heading("Settings"))

	var group := ButtonGroup.new()
	_mode_a = _mode_check("Mode A", "A", group)
	_mode_b = _mode_check("Mode B", "B", group)
	var mode_row := HBoxContainer.new()
	mode_row.add_child(_row_label("Time mode"))
	mode_row.add_child(_mode_a)
	mode_row.add_child(_mode_b)
	box.add_child(mode_row)
	_mode_desc = MenuKit.label("", MenuKit.FONT_SIZE - 4, MenuKit.DIM_COLOR)
	box.add_child(_mode_desc)

	_add_slider(box, "clock_speed", "Clock speed", CLOCK_STEP)
	_add_slider(box, "mouse_sensitivity", "Mouse sensitivity", SLIDER_STEP)
	_add_slider(box, "text_speed", "Text speed", SLIDER_STEP)

	var q_row := HBoxContainer.new()
	q_row.add_child(_row_label("Quality"))
	_quality = OptionButton.new()
	_quality.add_theme_font_size_override("font_size", MenuKit.FONT_SIZE)
	_quality.custom_minimum_size = Vector2(240, 0)
	_quality_names = Settings.quality_names()
	for q in _quality_names:
		_quality.add_item(q.capitalize())
	_quality.item_selected.connect(_on_quality_selected)
	q_row.add_child(_quality)
	box.add_child(q_row)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", MenuKit.SEPARATION)
	row.add_child(MenuKit.button("Defaults", _on_defaults))
	row.add_child(MenuKit.button("Back", close))
	box.add_child(row)

	Settings.changed.connect(_on_setting_changed)
	refresh()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


func close() -> void:
	Settings.save_file()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Pulls every control from Settings (without feeding the change back).
func refresh() -> void:
	_syncing = true
	var mode: String = str(Settings.get_value("time_mode"))
	_mode_a.button_pressed = mode == "A"
	_mode_b.button_pressed = mode == "B"
	_mode_desc.text = str(MODE_TEXT[mode])
	_quality.select(_quality_names.find(str(Settings.get_value("quality"))))
	for key: String in _sliders:
		var v: float = float(Settings.get_value(key))
		(_sliders[key] as HSlider).value = v
		(_value_labels[key] as Label).text = _format(v)
	_syncing = false


func _mode_check(text: String, mode: String, group: ButtonGroup) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_group = group
	c.add_theme_font_size_override("font_size", MenuKit.FONT_SIZE)
	c.toggled.connect(func(on: bool) -> void:
		if on and not _syncing:
			Settings.set_value("time_mode", mode))
	return c


func _row_label(text: String) -> Label:
	var l: Label = MenuKit.label(text)
	l.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	return l


func _add_slider(box: VBoxContainer, key: String, title: String, step: float) -> void:
	var r: Vector2 = Settings.range_of(key)
	var row := HBoxContainer.new()
	row.add_child(_row_label(title))
	var s := HSlider.new()
	s.min_value = r.x
	s.max_value = r.y
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		if not _syncing:
			Settings.set_value(key, v, false))
	s.drag_ended.connect(func(_changed: bool) -> void: Settings.save_file())
	row.add_child(s)
	var value := MenuKit.label("", MenuKit.FONT_SIZE, MenuKit.ACCENT_COLOR)
	value.custom_minimum_size = Vector2(VALUE_WIDTH, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	box.add_child(row)
	_sliders[key] = s
	_value_labels[key] = value


func _format(v: float) -> String:
	return "%.2f" % v


func _on_quality_selected(index: int) -> void:
	if not _syncing:
		Settings.set_value("quality", _quality_names[index])


func _on_defaults() -> void:
	Settings.reset_to_defaults()


func _on_setting_changed(_key: String, _value: Variant) -> void:
	refresh()
