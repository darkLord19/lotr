class_name MapScreen
extends Control
## Region map screen (toggle with M): displays the illustrated parchment map of Western Eriador
## with POI locations and the player's current position. Pauses the world clock while open.

const MAP_TEXTURE_PATH: String = "res://assets/ui/region_map.png"
const REGION_DATA_PATH: String = "res://content/regions/eriador_west.json"
const PAUSE_REASON: StringName = &"map_screen"

const REGION_WIDTH_M: float = 8192.0
const REGION_HEIGHT_M: float = 4096.0
const MAP_CONTAINER_WIDTH: float = 1200.0
const MAP_CONTAINER_HEIGHT: float = 600.0

const COLOR_BACKDROP: Color = Color(0.02, 0.03, 0.02, 0.82)
const COLOR_POI: Color = Color(0.85, 0.78, 0.55, 0.85)
const COLOR_POI_MAJOR: Color = Color(0.95, 0.88, 0.65, 0.95)
const COLOR_PLAYER: Color = Color(0.96, 0.25, 0.2, 1.0)
const COLOR_PLAYER_RING: Color = Color(1.0, 0.85, 0.3, 0.8)
const COLOR_TEXT: Color = Color(0.92, 0.88, 0.78)
const COLOR_MUTED: Color = Color(0.65, 0.62, 0.55)

var pois: Array[Dictionary] = []
var start_visible: bool = false

var _map_rect: TextureRect
var _overlay: Control
var _title_label: Label
var _status_label: Label
var _blink_time: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_pois()
	_build()
	visible = start_visible
	if visible:
		refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"map") or _is_map_key(event):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _is_map_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and not key.echo and key.keycode == KEY_M


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	WorldClock.pause(PAUSE_REASON)
	refresh()
	show()


func close() -> void:
	WorldClock.resume(PAUSE_REASON)
	hide()


func is_open() -> bool:
	return visible


func _process(delta: float) -> void:
	if visible:
		_blink_time += delta
		if _overlay != null:
			_overlay.queue_redraw()


func refresh() -> void:
	if _status_label != null:
		var loc: Dictionary = WorldState.entity_location(WorldState.PLAYER_ID)
		var pos_v: Variant = loc.get("pos", null)
		if pos_v is Vector3:
			var p: Vector3 = pos_v
			_status_label.text = "Position: (%.0f m E, %.0f m S)" % [p.x, p.z]
		else:
			var poi_name: String = str(loc.get("poi", "The Wild"))
			_status_label.text = "Location: %s" % NPCContent.prettify(poi_name)
	if _overlay != null:
		_overlay.queue_redraw()


func _load_pois() -> void:
	pois.clear()
	if not FileAccess.file_exists(REGION_DATA_PATH):
		return
	var text: String = FileAccess.get_file_as_string(REGION_DATA_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and (parsed as Dictionary).has("pois"):
		for entry: Variant in (parsed as Dictionary)["pois"]:
			if entry is Dictionary:
				pois.append(entry as Dictionary)


func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.color = COLOR_BACKDROP
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 12)
	main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(main_vbox)

	var header_hbox := HBoxContainer.new()
	main_vbox.add_child(header_hbox)

	_title_label = Label.new()
	_title_label.text = "Map of Western Eriador"
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.add_theme_color_override("font_color", COLOR_TEXT)
	header_hbox.add_child(_title_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override("font_size", 20)
	_status_label.add_theme_color_override("font_color", COLOR_MUTED)
	header_hbox.add_child(_status_label)

	var map_frame := PanelContainer.new()
	map_frame.custom_minimum_size = Vector2(MAP_CONTAINER_WIDTH, MAP_CONTAINER_HEIGHT)
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.08, 0.08, 0.06, 0.95)
	frame_style.border_color = Color(0.45, 0.38, 0.25, 0.8)
	frame_style.set_border_width_all(3)
	frame_style.set_corner_radius_all(6)
	frame_style.set_content_margin_all(4)
	map_frame.add_theme_stylebox_override("panel", frame_style)
	main_vbox.add_child(map_frame)

	_map_rect = TextureRect.new()
	_map_rect.custom_minimum_size = Vector2(MAP_CONTAINER_WIDTH, MAP_CONTAINER_HEIGHT)
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(MAP_TEXTURE_PATH):
		_map_rect.texture = load(MAP_TEXTURE_PATH) as Texture2D
	map_frame.add_child(_map_rect)

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_on_overlay_draw)
	map_frame.add_child(_overlay)

	var footer := Label.new()
	footer.text = "Press [M] or [Esc] to return"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 18)
	footer.add_theme_color_override("font_color", COLOR_MUTED)
	main_vbox.add_child(footer)


func _on_overlay_draw() -> void:
	if _overlay == null or _map_rect == null:
		return
	var rect_size: Vector2 = _map_rect.size
	if rect_size.x <= 1.0 or rect_size.y <= 1.0:
		return

	# Draw POI markers
	for p: Dictionary in pois:
		var pos_arr: Array = p.get("pos", [])
		if pos_arr.size() < 3:
			continue
		var px: float = float(pos_arr[0])
		var pz: float = float(pos_arr[2])
		var u: float = clampf(px / REGION_WIDTH_M, 0.0, 1.0)
		var v: float = clampf(pz / REGION_HEIGHT_M, 0.0, 1.0)
		var screen_pt := Vector2(u * rect_size.x, v * rect_size.y)
		var kind: String = str(p.get("kind", ""))
		var is_major: bool = kind in ["landmark", "settlement", "inn"]
		var r: float = 4.5 if is_major else 2.5
		var col: Color = COLOR_POI_MAJOR if is_major else COLOR_POI
		_overlay.draw_circle(screen_pt, r, col)
		if is_major and ThemeDB.fallback_font != null:
			var name_str: String = str(p.get("name", NPCContent.prettify(str(p.get("id", "")))))
			_overlay.draw_string(ThemeDB.fallback_font, screen_pt + Vector2(7, 4), name_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_POI_MAJOR)

	# Draw player position marker
	var loc: Dictionary = WorldState.entity_location(WorldState.PLAYER_ID)
	var pos_v: Variant = loc.get("pos", null)
	if pos_v is Vector3:
		var p: Vector3 = pos_v
		var pu: float = clampf(p.x / REGION_WIDTH_M, 0.0, 1.0)
		var pv: float = clampf(p.z / REGION_HEIGHT_M, 0.0, 1.0)
		var player_pt := Vector2(pu * rect_size.x, pv * rect_size.y)

		# Pulsing glow ring
		var pulse: float = 0.5 + 0.5 * sin(_blink_time * 5.0)
		var ring_r: float = 7.0 + pulse * 4.0
		_overlay.draw_arc(player_pt, ring_r, 0.0, TAU, 16, COLOR_PLAYER_RING, 2.0)
		_overlay.draw_circle(player_pt, 5.0, COLOR_PLAYER)
		_overlay.draw_circle(player_pt, 2.0, Color.WHITE)
		if ThemeDB.fallback_font != null:
			_overlay.draw_string(ThemeDB.fallback_font, player_pt + Vector2(10, 4), "You", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.95, 0.7))
