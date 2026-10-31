class_name HUD
extends Control
## In-game heads-up display: hunger, fatigue, date/time, Black Rider awareness eye icon,
## and a contextual controls hint bar.

var survival: Survival
var eye_state: RiderPerception.EyeState = RiderPerception.EyeState.HIDDEN

var _eye_panel: PanelContainer
var _eye_label: Label
var _date_label: Label
var _hunger_bar: ProgressBar
var _fatigue_bar: ProgressBar
var _hunger_val_label: Label
var _fatigue_val_label: Label


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build_ui()
	_update_display()


func _process(_delta: float) -> void:
	_update_display()


func set_eye_state(state: RiderPerception.EyeState) -> void:
	eye_state = state
	_update_eye()


func _build_ui() -> void:
	# Top Right: Date & Time in an antique parchment pill
	var date_pill := PanelContainer.new()
	date_pill.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	date_pill.offset_left = -380
	date_pill.offset_top = 18
	date_pill.offset_right = -20
	date_pill.mouse_filter = MOUSE_FILTER_IGNORE

	var date_style := StyleBoxFlat.new()
	date_style.bg_color = Color(0.12, 0.14, 0.10, 0.88)
	date_style.border_color = Color(0.48, 0.44, 0.30, 0.82)
	date_style.border_width_left = 2
	date_style.border_width_top = 2
	date_style.border_width_right = 2
	date_style.border_width_bottom = 2
	date_style.set_corner_radius_all(8)
	date_style.content_margin_left = 16
	date_style.content_margin_right = 16
	date_style.content_margin_top = 8
	date_style.content_margin_bottom = 8
	date_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	date_style.shadow_size = 8
	date_pill.add_theme_stylebox_override("panel", date_style)
	add_child(date_pill)

	_date_label = Label.new()
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_date_label.add_theme_font_size_override("font_size", 18)
	_date_label.add_theme_color_override("font_color", Color(0.94, 0.89, 0.78))
	date_pill.add_child(_date_label)

	# Top Center: Black Rider Awareness Eye Banner
	_eye_panel = PanelContainer.new()
	_eye_panel.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	_eye_panel.offset_top = 22
	_eye_panel.grow_horizontal = GROW_DIRECTION_BOTH
	_eye_panel.mouse_filter = MOUSE_FILTER_IGNORE

	var eye_box_style := StyleBoxFlat.new()
	eye_box_style.bg_color = Color(0.10, 0.08, 0.06, 0.92)
	eye_box_style.border_color = Color(0.95, 0.82, 0.25, 0.9)
	eye_box_style.border_width_left = 2
	eye_box_style.border_width_top = 2
	eye_box_style.border_width_right = 2
	eye_box_style.border_width_bottom = 2
	eye_box_style.set_corner_radius_all(8)
	eye_box_style.content_margin_left = 20
	eye_box_style.content_margin_right = 20
	eye_box_style.content_margin_top = 8
	eye_box_style.content_margin_bottom = 8
	_eye_panel.add_theme_stylebox_override("panel", eye_box_style)
	add_child(_eye_panel)

	_eye_label = Label.new()
	_eye_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eye_label.add_theme_font_size_override("font_size", 20)
	_eye_panel.add_child(_eye_label)
	_update_eye()

	# Bottom Left: Survival Frame (Hunger & Fatigue)
	var survival_panel := PanelContainer.new()
	survival_panel.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	survival_panel.offset_left = 22
	survival_panel.offset_bottom = -22
	survival_panel.offset_right = 290
	survival_panel.offset_top = -140
	survival_panel.mouse_filter = MOUSE_FILTER_IGNORE

	var s_style := StyleBoxFlat.new()
	s_style.bg_color = Color(0.12, 0.14, 0.10, 0.88)
	s_style.border_color = Color(0.48, 0.44, 0.30, 0.82)
	s_style.border_width_left = 2
	s_style.border_width_top = 2
	s_style.border_width_right = 2
	s_style.border_width_bottom = 2
	s_style.set_corner_radius_all(10)
	s_style.content_margin_left = 16
	s_style.content_margin_right = 16
	s_style.content_margin_top = 12
	s_style.content_margin_bottom = 12
	s_style.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	s_style.shadow_size = 10
	survival_panel.add_theme_stylebox_override("panel", s_style)
	add_child(survival_panel)

	var survival_box := VBoxContainer.new()
	survival_box.add_theme_constant_override("separation", 6)
	survival_panel.add_child(survival_box)

	# Shared bar background style
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.07, 0.08, 0.06, 0.95)
	bar_bg.border_color = Color(0.35, 0.32, 0.24, 0.8)
	bar_bg.border_width_left = 1
	bar_bg.border_width_top = 1
	bar_bg.border_width_right = 1
	bar_bg.border_width_bottom = 1
	bar_bg.set_corner_radius_all(4)

	# Hunger Row
	var hunger_row := HBoxContainer.new()
	var hunger_lbl := Label.new()
	hunger_lbl.text = "Sustenance"
	hunger_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	hunger_lbl.add_theme_font_size_override("font_size", 14)
	hunger_lbl.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
	hunger_row.add_child(hunger_lbl)

	_hunger_val_label = Label.new()
	_hunger_val_label.text = "0%"
	_hunger_val_label.add_theme_font_size_override("font_size", 13)
	_hunger_val_label.add_theme_color_override("font_color", Color(0.88, 0.64, 0.24))
	hunger_row.add_child(_hunger_val_label)
	survival_box.add_child(hunger_row)

	_hunger_bar = ProgressBar.new()
	_hunger_bar.min_value = 0.0
	_hunger_bar.max_value = 100.0
	_hunger_bar.custom_minimum_size = Vector2(236, 14)
	_hunger_bar.show_percentage = false
	_hunger_bar.add_theme_stylebox_override("background", bar_bg)
	var hunger_fill := StyleBoxFlat.new()
	hunger_fill.bg_color = Color(0.88, 0.64, 0.22, 0.95)
	hunger_fill.set_corner_radius_all(3)
	_hunger_bar.add_theme_stylebox_override("fill", hunger_fill)
	survival_box.add_child(_hunger_bar)

	# Fatigue Row
	var fatigue_row := HBoxContainer.new()
	var fatigue_lbl := Label.new()
	fatigue_lbl.text = "Fatigue"
	fatigue_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
	fatigue_lbl.add_theme_font_size_override("font_size", 14)
	fatigue_lbl.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
	fatigue_row.add_child(fatigue_lbl)

	_fatigue_val_label = Label.new()
	_fatigue_val_label.text = "0%"
	_fatigue_val_label.add_theme_font_size_override("font_size", 13)
	_fatigue_val_label.add_theme_color_override("font_color", Color(0.40, 0.75, 0.60))
	fatigue_row.add_child(_fatigue_val_label)
	survival_box.add_child(fatigue_row)

	_fatigue_bar = ProgressBar.new()
	_fatigue_bar.min_value = 0.0
	_fatigue_bar.max_value = 100.0
	_fatigue_bar.custom_minimum_size = Vector2(236, 14)
	_fatigue_bar.show_percentage = false
	_fatigue_bar.add_theme_stylebox_override("background", bar_bg)
	var fatigue_fill := StyleBoxFlat.new()
	fatigue_fill.bg_color = Color(0.32, 0.68, 0.52, 0.95)
	fatigue_fill.set_corner_radius_all(3)
	_fatigue_bar.add_theme_stylebox_override("fill", fatigue_fill)
	survival_box.add_child(_fatigue_bar)

	# Bottom Center: Contextual Controls Hint Strip
	var hint_panel := PanelContainer.new()
	hint_panel.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM)
	hint_panel.offset_bottom = -16
	hint_panel.grow_horizontal = GROW_DIRECTION_BOTH
	hint_panel.mouse_filter = MOUSE_FILTER_IGNORE

	var hint_style := StyleBoxFlat.new()
	hint_style.bg_color = Color(0.08, 0.09, 0.07, 0.78)
	hint_style.border_color = Color(0.38, 0.35, 0.25, 0.6)
	hint_style.border_width_left = 1
	hint_style.border_width_top = 1
	hint_style.border_width_right = 1
	hint_style.border_width_bottom = 1
	hint_style.set_corner_radius_all(6)
	hint_style.content_margin_left = 18
	hint_style.content_margin_right = 18
	hint_style.content_margin_top = 6
	hint_style.content_margin_bottom = 6
	hint_panel.add_theme_stylebox_override("panel", hint_style)
	add_child(hint_panel)

	var hint_label := Label.new()
	hint_label.text = "[W,A,S,D] Move   [Shift] Run   [C] Crouch   [Space] Jump   [E] Interact   [Tab] Pack   [M] Map   [J] Journal   [Esc] Pause"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 14)
	hint_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.72, 0.88))
	hint_panel.add_child(hint_label)


func _update_display() -> void:
	if _date_label != null:
		var now: int = WorldClock.now
		var shire: String = GameDate.format_shire(now)
		var h: int = GameDate.hour_of(now)
		var m: int = GameDate.minute_of(now)
		_date_label.text = "%s   •   %02d:%02d" % [shire, h, m]

	if survival != null:
		var h_val: float = survival.hunger()
		var f_val: float = survival.fatigue()
		if _hunger_bar != null:
			_hunger_bar.value = h_val
		if _fatigue_bar != null:
			_fatigue_bar.value = f_val
		if _hunger_val_label != null:
			_hunger_val_label.text = "%.0f%%" % h_val
		if _fatigue_val_label != null:
			_fatigue_val_label.text = "%.0f%%" % f_val


func _update_eye() -> void:
	if _eye_label == null or _eye_panel == null:
		return
	match eye_state:
		RiderPerception.EyeState.HIDDEN:
			_eye_label.text = ""
			_eye_panel.visible = false
		RiderPerception.EyeState.SEEN:
			_eye_label.text = "👁  A SHADOW WATCHES"
			_eye_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.24))
			var st: StyleBoxFlat = _eye_panel.get_theme_stylebox("panel") as StyleBoxFlat
			if st != null:
				st.border_color = Color(1.0, 0.84, 0.24, 0.9)
			_eye_panel.visible = true
		RiderPerception.EyeState.SNIFFED:
			_eye_label.text = "👁  THE ENEMY HUNTS"
			_eye_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.15))
			var st: StyleBoxFlat = _eye_panel.get_theme_stylebox("panel") as StyleBoxFlat
			if st != null:
				st.border_color = Color(1.0, 0.25, 0.15, 0.95)
			_eye_panel.visible = true
