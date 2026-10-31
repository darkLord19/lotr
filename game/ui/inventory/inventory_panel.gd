class_name InventoryPanel
extends Control
## Simple inventory list (Tab). Reads the player's stacks through Inventory; changes nothing.

const TEXT_COLOR: Color = Color(0.93, 0.9, 0.8)

var inventory: Inventory

var _list: VBoxContainer
var _footer: Label


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
		_list.add_child(_label("You are carrying nothing.", MenuKit.DIM_COLOR))
	for r: String in rows_:
		_list.add_child(_label(r, TEXT_COLOR))
	_footer.text = "Weight %.1f / %.1f   Pennies %d" % [inventory.total_weight(), inventory.capacity(), inventory.money()]


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
	box.add_child(MenuKit.heading("Inventory"))
	_list = VBoxContainer.new()
	box.add_child(_list)
	_footer = _label("", MenuKit.ACCENT_COLOR)
	box.add_child(_footer)


func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", MenuKit.FONT_SIZE)
	l.add_theme_color_override("font_color", color)
	return l
