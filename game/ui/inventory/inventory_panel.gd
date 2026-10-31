class_name InventoryPanel
extends Control
## Inventory pack display (toggle with Tab). Reads the player's stacks through Inventory; changes nothing.

const TEXT_COLOR: Color = Color(0.94, 0.91, 0.82)
const ROW_BG_COLOR: Color = Color(0.12, 0.14, 0.10, 0.6)

var inventory: Inventory

var _list: VBoxContainer
var _footer: Label
var _scroll: ScrollContainer


func _ready() -> void:
	if inventory == null:
		inventory = Inventory.new(WorldState.PLAYER_ID)
	_build()
	hide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	refresh()
	show()


func close() -> void:
	hide()


## Rows as "Name  xN" sorted by name, for the list and for tests.
func rows() -> Array[String]:
	var out: Array[String] = []
	var stacks: Dictionary = inventory.contents()
	for id: String in stacks:
		out.append("%s  x%d" % [str(ItemDB.get_item(id).get("name", id)), int(stacks[id])])
	out.sort()
	return out


func refresh() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var rows_: Array[String] = rows()
	if rows_.is_empty():
		_list.add_child(_label("Your pack is empty.", MenuKit.DIM_COLOR))
	for r: String in rows_:
		var row_panel := PanelContainer.new()
		var r_st := StyleBoxFlat.new()
		r_st.bg_color = ROW_BG_COLOR
		r_st.border_color = Color(0.38, 0.35, 0.25, 0.5)
		r_st.border_width_bottom = 1
		r_st.content_margin_left = 12
		r_st.content_margin_right = 12
		r_st.content_margin_top = 6
		r_st.content_margin_bottom = 6
		r_st.set_corner_radius_all(4)
		row_panel.add_theme_stylebox_override("panel", r_st)
		row_panel.add_child(_label(r, TEXT_COLOR))
		_list.add_child(row_panel)
	_footer.text = "Pennies: %d  •  Weight: %.1f / %.1f" % [inventory.money(), inventory.total_weight(), inventory.capacity()]


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	MenuKit.backdrop(self, MenuKit.SCRIM_COLOR)
	var box: VBoxContainer = MenuKit.panel(self, float(Config.get_value("player.ui.inventory_width", 640.0)))
	if ResourceLoader.exists("res://assets/ui/inventory_panel.png"):
		var tex: Texture2D = load("res://assets/ui/inventory_panel.png") as Texture2D
		if tex != null:
			var pc: PanelContainer = box.get_parent() as PanelContainer
			if pc != null:
				var st := StyleBoxTexture.new()
				st.texture = tex
				st.set_content_margin_all(MenuKit.PANEL_MARGIN)
				pc.add_theme_stylebox_override("panel", st)
	box.add_child(MenuKit.heading("Pack & Inventory"))
	MenuKit.divider(box)

	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 320)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	box.add_child(_scroll)

	MenuKit.divider(box)
	_footer = _label("", MenuKit.ACCENT_COLOR)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_footer)

	var hint := _label("Press [Tab] or [Esc] to close", MenuKit.DIM_COLOR)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	box.add_child(hint)


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", MenuKit.FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	return l
