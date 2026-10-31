class_name HUD
extends Control
## In-game heads-up display: hunger, fatigue, date/time, and the Black Rider awareness eye icon.

var survival: Survival
var eye_state: RiderPerception.EyeState = RiderPerception.EyeState.HIDDEN

var _eye_label: Label
var _date_label: Label
var _hunger_bar: ProgressBar
var _fatigue_bar: ProgressBar


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
	# Top Right: Date & Time
	_date_label = Label.new()
	_date_label.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	_date_label.offset_left = -340
	_date_label.offset_top = 20
	_date_label.offset_right = -20
	_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_date_label.add_theme_font_size_override("font_size", 18)
	_date_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
	add_child(_date_label)

	# Top Center: Black Rider Awareness Eye Icon
	_eye_label = Label.new()
	_eye_label.set_anchors_and_offsets_preset(PRESET_CENTER_TOP)
	_eye_label.offset_top = 24
	_eye_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eye_label.add_theme_font_size_override("font_size", 28)
	add_child(_eye_label)
	_update_eye()

	# Bottom Left: Survival bars (Hunger & Fatigue)
	var survival_box := VBoxContainer.new()
	survival_box.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	survival_box.offset_left = 24
	survival_box.offset_bottom = -24
	survival_box.offset_right = 224
	survival_box.offset_top = -100
	survival_box.add_theme_constant_override("separation", 6)
	add_child(survival_box)

	var hunger_lbl := Label.new()
	hunger_lbl.text = "Hunger"
	hunger_lbl.add_theme_font_size_override("font_size", 14)
	survival_box.add_child(hunger_lbl)

	_hunger_bar = ProgressBar.new()
	_hunger_bar.min_value = 0.0
	_hunger_bar.max_value = 100.0
	_hunger_bar.custom_minimum_size = Vector2(200, 14)
	_hunger_bar.show_percentage = false
	survival_box.add_child(_hunger_bar)

	var fatigue_lbl := Label.new()
	fatigue_lbl.text = "Fatigue"
	fatigue_lbl.add_theme_font_size_override("font_size", 14)
	survival_box.add_child(fatigue_lbl)

	_fatigue_bar = ProgressBar.new()
	_fatigue_bar.min_value = 0.0
	_fatigue_bar.max_value = 100.0
	_fatigue_bar.custom_minimum_size = Vector2(200, 14)
	_fatigue_bar.show_percentage = false
	survival_box.add_child(_fatigue_bar)


func _update_display() -> void:
	if _date_label != null:
		var now: int = WorldClock.now
		var shire: String = GameDate.format_shire(now)
		var h: int = GameDate.hour_of(now)
		var m: int = GameDate.minute_of(now)
		_date_label.text = "%s  %02d:%02d" % [shire, h, m]

	if survival != null:
		if _hunger_bar != null:
			_hunger_bar.value = survival.hunger()
		if _fatigue_bar != null:
			_fatigue_bar.value = survival.fatigue()


func _update_eye() -> void:
	if _eye_label == null:
		return
	match eye_state:
		RiderPerception.EyeState.HIDDEN:
			_eye_label.text = ""
			_eye_label.visible = false
		RiderPerception.EyeState.SEEN:
			_eye_label.text = "👁 SEEN"
			_eye_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
			_eye_label.visible = true
		RiderPerception.EyeState.SNIFFED:
			_eye_label.text = "👁 HUNTED"
			_eye_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1))
			_eye_label.visible = true
