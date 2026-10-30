class_name MenuKit
extends RefCounted
## Shared look and widget builders for the code-built menus (same palette as character creation),
## so the main, pause, slot and settings screens stay visually consistent.

const BG_COLOR: Color = Color(0.13, 0.15, 0.11)
const SCRIM_COLOR: Color = Color(0.03, 0.04, 0.03, 0.78)
const PANEL_COLOR: Color = Color(0.2, 0.22, 0.16)
const ACCENT_COLOR: Color = Color(0.86, 0.78, 0.5)
const DIM_COLOR: Color = Color(0.7, 0.72, 0.62)
const OK_COLOR: Color = Color(0.6, 0.9, 0.55)
const ERROR_COLOR: Color = Color(1.0, 0.55, 0.45)
const FONT_SIZE: int = 26
const TITLE_FONT_SIZE: int = 56
const HEADING_FONT_SIZE: int = 40
const BUTTON_SIZE: Vector2 = Vector2(460, 64)
const PANEL_MARGIN: int = 36
const SEPARATION: int = 14


## Full-rect colour layer. A translucent colour gives a scrim over the game; opaque is a backdrop.
static func backdrop(parent: Control, color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = color
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks must not reach the screen underneath
	parent.add_child(bg)
	return bg


## Centred panel; returns the VBox to fill.
static func panel(parent: Control, width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.set_content_margin_all(PANEL_MARGIN)
	style.set_corner_radius_all(10)
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


static func button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	b.pressed.connect(on_press)
	return b
