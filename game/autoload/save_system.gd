extends Node
# Save file = {"version", "clock", "state", "timeline"}. Loads never crash on a bad
# file: they return an Error and leave the running game untouched.

const SAVE_VERSION: int = 1
const AUTOSAVE_PREFIX: String = "autosave_"

var save_dir: String = "user://saves"
var clock: Node
var state: Node
var timeline: Node
# Autosave only makes sense once a game is running (menus have nothing to save).
var autosave_enabled: bool = false
# from_version (int) -> Callable(Dictionary) -> Dictionary, upgrading one version step.
var migrations: Dictionary = {}

var _hours_since_autosave: int = 0


func _ready() -> void:
	bind(WorldClock, WorldState, Timeline)


func bind(clock_node: Node, state_node: Node, timeline_node: Node) -> void:
	clock = clock_node
	state = state_node
	timeline = timeline_node
	if not clock.hour_passed.is_connected(_on_hour_passed):
		clock.hour_passed.connect(_on_hour_passed)
	if not EventBus.region_changed.is_connected(_on_region_changed):
		EventBus.region_changed.connect(_on_region_changed)


func slot_path(slot: String) -> String:
	return save_dir.path_join("%s.json" % slot)


func is_valid_slot(slot: String) -> bool:
	return slot != "" and not slot.contains("/") and not slot.contains("\\") and not slot.contains("..")


func list_slots() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(save_dir)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.get_basename())
	out.sort()
	return out


func build_save() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"clock": clock.serialise(),
		"state": state.serialise(),
		"timeline": timeline.serialise(),
	}


func save(slot: String) -> Error:
	if not is_valid_slot(slot):
		return ERR_INVALID_PARAMETER
	DirAccess.make_dir_recursive_absolute(save_dir)
	var path: String = slot_path(slot)
	# Write-then-rename so a crash mid-write can't destroy the previous save.
	var tmp: String = path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(build_save()))
	f.close()
	return DirAccess.rename_absolute(tmp, path)


# Reads and validates without touching live state; apply only if all of it is sane.
func read_save(slot: String) -> Dictionary:
	var result: Dictionary = {"error": OK, "data": {}}
	if not is_valid_slot(slot):
		result["error"] = ERR_INVALID_PARAMETER
		return result
	var path: String = slot_path(slot)
	if not FileAccess.file_exists(path):
		result["error"] = ERR_FILE_NOT_FOUND
		return result
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		push_warning("SaveSystem: corrupt save %s" % path)
		result["error"] = ERR_PARSE_ERROR
		return result
	var data: Dictionary = json.data
	if not data.has("version"):
		result["error"] = ERR_INVALID_DATA
		return result
	var version: int = int(data["version"])
	if version > SAVE_VERSION or version < 1:
		result["error"] = ERR_UNAVAILABLE
		return result
	while version < SAVE_VERSION:
		if not migrations.has(version):
			result["error"] = ERR_UNAVAILABLE
			return result
		data = (migrations[version] as Callable).call(data)
		version += 1
		data["version"] = version
	for key in ["clock", "state", "timeline"]:
		if not (data.get(key) is Dictionary):
			result["error"] = ERR_INVALID_DATA
			return result
	result["data"] = data
	return result


func load_slot(slot: String) -> Error:
	var r: Dictionary = read_save(slot)
	if r["error"] != OK:
		return r["error"]
	var data: Dictionary = r["data"]
	clock.deserialise(data["clock"])
	state.deserialise(data["state"])
	timeline.deserialise(data["timeline"])
	_hours_since_autosave = 0
	return OK


# --- autosave --------------------------------------------------------------

func autosave_slots() -> Array[String]:
	var out: Array[String] = []
	for i in range(1, int(Config.get_value("save.autosave_keep", 3)) + 1):
		out.append("%s%d" % [AUTOSAVE_PREFIX, i])
	return out


# autosave_1 is always the newest. Shift older ones down; the oldest falls off.
func autosave() -> Error:
	var slots: Array[String] = autosave_slots()
	DirAccess.make_dir_recursive_absolute(save_dir)
	for i in range(slots.size() - 1, 0, -1):
		var src: String = slot_path(slots[i - 1])
		if FileAccess.file_exists(src):
			DirAccess.rename_absolute(src, slot_path(slots[i]))
	_hours_since_autosave = 0
	return save(slots[0])


func _on_hour_passed(_now: int) -> void:
	if not autosave_enabled:
		return
	_hours_since_autosave += 1
	if _hours_since_autosave >= int(Config.get_value("save.autosave_game_hours", 6)):
		autosave()


func _on_region_changed(_region_id: String) -> void:
	if autosave_enabled:
		autosave()
