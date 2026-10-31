class_name MenuKit
extends RefCounted
## Shared look and widget builders for the code-built menus (same palette as character creation),
## so the main, pause, slot and settings screens stay visually consistent.

const BG_COLOR: Color = Color(0.12, 0.14, 0.10)
const SCRIM_COLOR: Color = Color(0.04, 0.05, 0.03, 0.82)
const PANEL_COLOR: Color = Color(0.15, 0.17, 0.12, 0.96)
const ACCENT_COLOR: Color = Color(0.92, 0.84, 0.54)
const DIM_COLOR: Color = Color(0.72, 0.74, 0.64)
const OK_COLOR: Color = Color(0.62, 0.92, 0.58)
const ERROR_COLOR: Color = Color(1.0, 0.55, 0.45)
const FONT_SIZE: int = 24
const TITLE_FONT_SIZE: int = 56
const HEADING_FONT_SIZE: int = 38
const BUTTON_SIZE: Vector2 = Vector2(480, 56)
const PANEL_MARGIN: int = 36
const SEPARATION: int = 14


## Full-rect colour layer. A translucent colour gives a scrim over the game; opaque is a backdrop.
static func backdrop(parent: Control, color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks must not reach the screen underneath
	parent.add_child(bg)
	return bg


## Centred panel; returns the VBox to fill.
static func panel(parent: Control, width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = Color(0.48, 0.42, 0.28, 0.85)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.set_content_margin_all(PANEL_MARGIN)
	style.set_corner_radius_all(12)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.6)
	style.shadow_size = 20
	style.shadow_offset = Vector2(0, 6)
	pc.add_theme_stylebox_override("panel", style)
	center.add_child(pc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", SEPARATION)
	pc.add_child(box)
	return box


static func label(text: String, size: int = FONT_SIZE, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func heading(text: String, size: int = HEADING_FONT_SIZE) -> Label:
	var l: Label = label(text, size, ACCENT_COLOR)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func divider(parent: Control, color: Color = Color(0.48, 0.42, 0.28, 0.6), height: float = 2.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, height)
	parent.add_child(r)
	return r


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.focus_mode = Control.FOCUS_ALL

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.20, 0.15, 0.92)
	normal.border_color = Color(0.44, 0.40, 0.28, 0.85)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 20
	normal.content_margin_right = 20
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10

	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.28, 0.31, 0.22, 0.98)
	hover.border_color = ACCENT_COLOR
	hover.border_width_left = 2
	hover.border_width_top = 2
	hover.border_width_right = 2
	hover.border_width_bottom = 2
	hover.set_corner_radius_all(8)
	hover.content_margin_left = 20
	hover.content_margin_right = 20
	hover.content_margin_top = 10
	hover.content_margin_bottom = 10
	hover.shadow_color = Color(0.92, 0.84, 0.54, 0.25)
	hover.shadow_size = 8

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.12, 0.13, 0.09, 0.98)
	pressed.border_color = Color(0.74, 0.64, 0.36, 1.0)
	pressed.border_width_left = 2
	pressed.border_width_top = 2
	pressed.border_width_right = 2
	pressed.border_width_bottom = 2
	pressed.set_corner_radius_all(8)
	pressed.content_margin_left = 20
	pressed.content_margin_right = 20
	pressed.content_margin_top = 10
	pressed.content_margin_bottom = 10

	var focus := StyleBoxFlat.new()
	focus.bg_color = Color(0.24, 0.27, 0.19, 0.95)
	focus.border_color = ACCENT_COLOR
	focus.border_width_left = 2
	focus.border_width_top = 2
	focus.border_width_right = 2
	focus.border_width_bottom = 2
	focus.set_corner_radius_all(8)
	focus.content_margin_left = 20
	focus.content_margin_right = 20
	focus.content_margin_top = 10
	focus.content_margin_bottom = 10

	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.13, 0.14, 0.11, 0.4)
	disabled.border_color = Color(0.28, 0.28, 0.24, 0.3)
	disabled.border_width_left = 1
	disabled.border_width_top = 1
	disabled.border_width_right = 1
	disabled.border_width_bottom = 1
	disabled.set_corner_radius_all(8)
	disabled.content_margin_left = 20
	disabled.content_margin_right = 20
	disabled.content_margin_top = 10
	disabled.content_margin_bottom = 10

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("disabled", disabled)

	b.add_theme_color_override("font_color", Color(0.93, 0.90, 0.82))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.96, 0.86))
	b.add_theme_color_override("font_pressed_color", Color(0.86, 0.80, 0.68))
	b.add_theme_color_override("font_focus_color", Color(1.0, 0.96, 0.86))
	b.add_theme_color_override("font_disabled_color", Color(0.48, 0.50, 0.44))

	b.pressed.connect(on_press)
	return b
