class_name CharCreation
extends Control
## Character creation screen, built from code so the layout stays data-driven
## (origins, traits and appearance come from content). Emits the params
## Dictionary that NewGame.new_game() takes; optionally runs NewGame itself.

signal creation_confirmed(params: Dictionary)
signal game_started(result: Dictionary)

const FONT_SIZE: int = 26
const TITLE_FONT_SIZE: int = 44
const PANEL_WIDTH: float = 1400.0
const SWATCH_SIZE: Vector2 = Vector2(110, 80)
const SWATCH_BORDER: int = 10
const BG_COLOR: Color = Color(0.13, 0.15, 0.11)
const PANEL_COLOR: Color = Color(0.2, 0.22, 0.16)
const ERROR_COLOR: Color = Color(1.0, 0.55, 0.45)
const DEFAULT_NAME: String = "Wanderer"
const RACE_LABELS: Dictionary = {"hobbit": "Hobbit (Shire)", "man": "Man (Bree-land)"}
const MODE_TEXT: Dictionary = {
	"A": "Mode A: the world never waits. Events happen on schedule whether or not you are there.",
	"B": "Mode B: major events wait for you, within a window, so you can reach them in time.",
}

## When true, confirming also calls NewGame; tests turn it off to inspect params only.
var start_game_on_confirm: bool = true

var _origins: Array[Dictionary] = []
var _traits: Array[Dictionary] = []
var _palettes: Array[Dictionary] = []
var _hair_styles: Array[Dictionary] = []
var _races: Array[String] = []
var _shown_origins: Array[Dictionary] = []
var _shown_hair: Array[Dictionary] = []

var _name_edit: LineEdit
var _race_pick: OptionButton
var _origin_pick: OptionButton
var _origin_desc: Label
var _trait_pick: OptionButton
var _trait_desc: Label
var _swatch_row: HBoxContainer
var _swatch_group: ButtonGroup
var _palette_label: Label
var _hair_pick: OptionButton
var _mode_group: ButtonGroup
var _mode_a: CheckBox
var _mode_b: CheckBox
var _mode_desc: Label
var _status: Label
var _begin: Button
var _selected_palette: int = 0


func _ready() -> void:
	_origins = NewGame.load_origins()
	_traits = NewGame.load_traits()
	var look: Dictionary = NewGame.load_appearance()
	_palettes.assign(look["palettes"])
	_hair_styles.assign(look["hair_styles"])
	for o: Dictionary in _origins:
		var race: String = str(o["race"])
		if race not in _races:
			_races.append(race)
	_build()
	_refresh_origins()
	_refresh_hair()
	_refresh_trait()
	_refresh_mode()


## Current choices in the shape NewGame.new_game() expects.
func get_params() -> Dictionary:
	var origin: String = ""
	if _origin_pick.selected >= 0 and _origin_pick.selected < _shown_origins.size():
		origin = str(_shown_origins[_origin_pick.selected]["id"])
	var hair: String = ""
	if _hair_pick.selected >= 0 and _hair_pick.selected < _shown_hair.size():
		hair = str(_shown_hair[_hair_pick.selected]["id"])
	return {
		"name": _name_edit.text.strip_edges(),
		"race": _races[_race_pick.selected] if _race_pick.selected >= 0 else "",
		"origin": origin,
		"background_trait": str(_traits[_trait_pick.selected]["id"]) if _trait_pick.selected >= 0 else "",
		"palette": str(_palettes[_selected_palette]["id"]),
		"hair": hair,
		"mode": "B" if _mode_b.button_pressed else "A",
	}


# --- public setters, used by tests and by any scripted start --------------

func choose_race(race: String) -> void:
	_race_pick.select(_races.find(race))
	_refresh_origins()
	_refresh_hair()


func choose_origin(origin_id: String) -> void:
	for i in _shown_origins.size():
		if str(_shown_origins[i]["id"]) == origin_id:
			_origin_pick.select(i)
	_refresh_origin_desc()


func choose_palette(index: int) -> void:
	_selected_palette = clampi(index, 0, _palettes.size() - 1)
	(_swatch_row.get_child(_selected_palette) as Button).button_pressed = true
	_palette_label.text = str(_palettes[_selected_palette]["name"])


func confirm() -> void:
	_on_begin_pressed()


# --- construction ----------------------------------------------------------

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_content_margin_all(28)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	var title := Label.new()
	title.text = "Begin your tale"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.text = DEFAULT_NAME
	_name_edit.max_length = int(Config.get_value("new_game.name_max_length", 24))
	_style(_name_edit)
	box.add_child(_row("Name", _name_edit))

	_race_pick = OptionButton.new()
	for race in _races:
		_race_pick.add_item(str(RACE_LABELS.get(race, race.capitalize())))
	_race_pick.item_selected.connect(_on_race_selected)
	_style(_race_pick)
	box.add_child(_row("Race", _race_pick))

	_origin_pick = OptionButton.new()
	_origin_pick.item_selected.connect(_on_origin_selected)
	_style(_origin_pick)
	box.add_child(_row("Origin", _origin_pick))
	_origin_desc = _note()
	box.add_child(_origin_desc)

	_trait_pick = OptionButton.new()
	for t in _traits:
		_trait_pick.add_item(str(t["name"]))
	_trait_pick.item_selected.connect(_on_trait_selected)
	_style(_trait_pick)
	box.add_child(_row("Background", _trait_pick))
	_trait_desc = _note()
	box.add_child(_trait_desc)

	_swatch_row = HBoxContainer.new()
	_swatch_row.add_theme_constant_override("separation", 10)
	_swatch_group = ButtonGroup.new()
	for i in _palettes.size():
		_swatch_row.add_child(_make_swatch(i))
	_palette_label = Label.new()
	_style(_palette_label)
	var look_box := HBoxContainer.new()
	look_box.add_theme_constant_override("separation", 16)
	look_box.add_child(_swatch_row)
	look_box.add_child(_palette_label)
	box.add_child(_row("Complexion", look_box))

	_hair_pick = OptionButton.new()
	_style(_hair_pick)
	box.add_child(_row("Hair", _hair_pick))

	_mode_group = ButtonGroup.new()
	_mode_a = _make_mode_button("Mode A")
	_mode_b = _make_mode_button("Mode B")
	_mode_a.button_pressed = true
	var mode_box := HBoxContainer.new()
	mode_box.add_theme_constant_override("separation", 24)
	mode_box.add_child(_mode_a)
	mode_box.add_child(_mode_b)
	box.add_child(_row("Time", mode_box))
	_mode_desc = _note()
	box.add_child(_mode_desc)

	_status = Label.new()
	_status.add_theme_color_override("font_color", ERROR_COLOR)
	_style(_status)
	box.add_child(_status)

	_begin = MenuKit.button("Begin", _on_begin_pressed)
	box.add_child(_begin)
	choose_palette(0)


func _make_swatch(index: int) -> Button:
	var p: Dictionary = _palettes[index]
	var b := Button.new()
	b.toggle_mode = true
	b.button_group = _swatch_group
	b.custom_minimum_size = SWATCH_SIZE
	b.tooltip_text = str(p["name"])
	# Skin is the fill and hair the border so one swatch shows the two colours that differ most.
	for state_name in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color.html(str(p["skin"]))
		sb.border_color = Color.html(str(p["hair"]))
		sb.set_border_width_all(SWATCH_BORDER if state_name == "pressed" else 2)
		sb.set_corner_radius_all(8)
		b.add_theme_stylebox_override(state_name, sb)
	b.pressed.connect(choose_palette.bind(index))
	return b


func _make_mode_button(label: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = label
	c.button_group = _mode_group
	_style(c)
	c.toggled.connect(func(_on: bool) -> void: _refresh_mode())
	return c


func _row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(220, 0)
	_style(l)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _note() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.modulate = Color(0.85, 0.85, 0.75)
	_style(l)
	return l


func _style(c: Control) -> void:
	c.add_theme_font_size_override("font_size", FONT_SIZE)


# --- refresh ---------------------------------------------------------------

func _refresh_origins() -> void:
	_origin_pick.clear()
	_shown_origins.clear()
	var race: String = _races[maxi(_race_pick.selected, 0)]
	for o in _origins:
		if str(o["race"]) == race:
			_shown_origins.append(o)
			_origin_pick.add_item(str(o["name"]))
	if not _shown_origins.is_empty():
		_origin_pick.select(0)
	_refresh_origin_desc()


func _refresh_origin_desc() -> void:
	var i: int = _origin_pick.selected
	_origin_desc.text = str(_shown_origins[i]["description"]) if i >= 0 and i < _shown_origins.size() else ""


func _refresh_hair() -> void:
	_hair_pick.clear()
	_shown_hair.clear()
	var race: String = _races[maxi(_race_pick.selected, 0)]
	for h in _hair_styles:
		if race in (h["races"] as Array):
			_shown_hair.append(h)
			_hair_pick.add_item(str(h["name"]))
	if not _shown_hair.is_empty():
		_hair_pick.select(0)


func _refresh_trait() -> void:
	var i: int = _trait_pick.selected
	_trait_desc.text = str(_traits[i]["description"]) if i >= 0 else ""


func _refresh_mode() -> void:
	if _mode_desc == null:  # toggled fires while the form is still being built
		return
	_mode_desc.text = str(MODE_TEXT["B" if _mode_b.button_pressed else "A"])


func _on_race_selected(_i: int) -> void:
	_refresh_origins()
	_refresh_hair()


func _on_origin_selected(_i: int) -> void:
	_refresh_origin_desc()


func _on_trait_selected(_i: int) -> void:
	_refresh_trait()


func _on_begin_pressed() -> void:
	var params: Dictionary = get_params()
	if start_game_on_confirm:
		var result: Dictionary = NewGame.new().new_game(params)
		if int(result["error"]) != OK:
			_status.text = str(result["message"])
			return
		_status.text = ""
		creation_confirmed.emit(params)
		game_started.emit(result)
	else:
		creation_confirmed.emit(params)
