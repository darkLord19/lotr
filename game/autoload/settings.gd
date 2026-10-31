extends Node
# Player settings: persisted to user://settings.json and applied live. Values change only through
# set_value() so the clock, the viewport and listeners (the `changed` signal) never disagree.
#
# time_mode and clock_speed are written straight onto WorldClock, which is itself the per-game
# truth for the mode (it is saved with the game). After a load or new game, sync_from_clock()
# makes the menu show what the running game actually uses.

signal changed(key: String, value: Variant)

const KEYS: Array[String] = ["time_mode", "clock_speed", "quality", "mouse_sensitivity", "text_speed", "master_volume"]

var path: String = ""
var values: Dictionary = {}


func _ready() -> void:
	path = str(Config.get_value("settings.file", "user://settings.json"))
	load_file()
	apply_all()


func defaults() -> Dictionary:
	var d: Dictionary = (Config.get_value("settings.defaults", {}) as Dictionary).duplicate()
	# The clock speed default lives with the clock config so there is one number to tune.
	d["clock_speed"] = float(Config.get_value("clock.minutes_per_second", 0.5))
	return d


func load_file() -> void:
	values = defaults()
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	var parsed: Variant = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not (parsed is Dictionary):
		push_warning("Settings: ignoring unreadable %s" % path)
		return
	# Unknown or invalid entries fall back to defaults instead of poisoning the game.
	for key: String in KEYS:
		if (parsed as Dictionary).has(key):
			var v: Variant = _validated(key, (parsed as Dictionary)[key])
			if v != null:
				values[key] = v


func save_file() -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(values, "  ", true, true))
	return OK


func get_value(key: String) -> Variant:
	return values.get(key, defaults().get(key))


func mouse_sensitivity() -> float:
	return float(get_value("mouse_sensitivity"))


func text_speed() -> float:
	return float(get_value("text_speed"))


func quality_names() -> Array[String]:
	var out: Array[String] = []
	out.assign(Config.get_value("settings.quality_order", []))
	return out


func range_of(key: String) -> Vector2:
	var r: Array = Config.get_value("settings.ranges.%s" % key, [0.0, 1.0])
	return Vector2(float(r[0]), float(r[1]))


## Returns false (and changes nothing) if the value is invalid for the key.
func set_value(key: String, value: Variant, persist: bool = true) -> bool:
	var v: Variant = _validated(key, value)
	if v == null:
		return false
	values[key] = v
	_apply(key)
	changed.emit(key, v)
	if persist:
		save_file()
	return true


func reset_to_defaults() -> void:
	values = defaults()
	apply_all()
	for key: String in KEYS:
		changed.emit(key, values[key])
	save_file()


func apply_all() -> void:
	for key: String in KEYS:
		_apply(key)


## Shows the running game's mode/speed in the menu without rewriting the settings file.
func sync_from_clock() -> void:
	values["time_mode"] = String(WorldClock.mode)
	values["clock_speed"] = WorldClock.time_scale
	changed.emit("time_mode", values["time_mode"])
	changed.emit("clock_speed", values["clock_speed"])


# Returns the cleaned value, or null when invalid.
func _validated(key: String, value: Variant) -> Variant:
	match key:
		"time_mode":
			var m: String = str(value)
			return m if m == "A" or m == "B" else null
		"quality":
			var q: String = str(value)
			return q if (Config.get_value("settings.quality_presets", {}) as Dictionary).has(q) else null
		"clock_speed", "mouse_sensitivity", "text_speed", "master_volume":
			if not (value is float or value is int):
				return null
			var r: Vector2 = range_of(key)
			return clampf(float(value), r.x, r.y)
	return null


func _apply(key: String) -> void:
	match key:
		"time_mode":
			WorldClock.set_mode(StringName(str(values[key])))
		"clock_speed":
			WorldClock.time_scale = float(values[key])
		"quality":
			_apply_quality(str(values[key]))
		"master_volume":
			_apply_master_volume(float(values[key]))


func _apply_master_volume(vol: float) -> void:
	var bus_idx: int = AudioServer.get_bus_index("Master")
	if bus_idx >= 0:
		if vol <= 0.001:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			AudioServer.set_bus_volume_db(bus_idx, linear_to_db(vol))


func _apply_quality(preset: String) -> void:
	# No renderer in headless runs; touching the viewport there only adds noise.
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var p: Dictionary = Config.get_value("settings.quality_presets.%s" % preset, {})
	var vp: Viewport = get_viewport()
	vp.scaling_3d_scale = float(p.get("scaling_3d_scale", 1.0))
	vp.msaa_3d = int(p.get("msaa_3d", 0)) as Viewport.MSAA
	RenderingServer.directional_shadow_atlas_set_size(int(p.get("shadow_atlas_size", 4096)), true)
