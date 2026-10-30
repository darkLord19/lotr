extends Node
# Save file = {"version", "clock", "state", "timeline", "extras", "meta"}. Loads never crash on a bad
# file: they return an Error and leave the running game untouched.
#
# "extras" holds one entry per registered participant (key -> its serialise() output), so systems
# that keep state outside WorldState (rumour network, off-screen sim, weather seed, ...) plug in
# with register_participant() and SaveSystem never references them (cross-system comms rule).
# "extras" and "meta" are optional on read, so they did not need a version bump.

signal about_to_save
signal loaded

const SAVE_VERSION: int = 1
const AUTOSAVE_PREFIX: String = "autosave_"
const MANUAL_PREFIX: String = "slot_"

var save_dir: String = "user://saves"
var clock: Node
var state: Node
var timeline: Node
# Autosave only makes sense once a game is running (menus have nothing to save).
var autosave_enabled: bool = false
# from_version (int) -> Callable(Dictionary) -> Dictionary, upgrading one version step.
var migrations: Dictionary = {}

var _hours_since_autosave: int = 0
# key -> {"ser": Callable() -> Dictionary, "deser": Callable(Dictionary)}
var _participants: Dictionary = {}
# Extras loaded for participants that are not registered yet (the world scene is built after a
# load from the main menu); handed over the moment the participant registers.
var _pending_extras: Dictionary = {}


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
	if not EventBus.player_slept.is_connected(_on_player_slept):
		EventBus.player_slept.connect(_on_player_slept)


# --- participants ----------------------------------------------------------

## deserialise is always called on load, with {} when the save has nothing for `key`, so a
## participant resets itself instead of keeping state from the previous game.
func register_participant(key: String, serialise_fn: Callable, deserialise_fn: Callable) -> void:
	_participants[key] = {"ser": serialise_fn, "deser": deserialise_fn}
	if _pending_extras.has(key):
		var d: Dictionary = _pending_extras[key]
		_pending_extras.erase(key)
		deserialise_fn.call(d)


## Only removes the registration if it still belongs to `serialise_fn`, so a replaced
## participant's late tree-exit cannot unregister its successor.
func unregister_participant(key: String, serialise_fn: Callable = Callable()) -> void:
	if not _participants.has(key):
		return
	if serialise_fn.is_null() or (_participants[key] as Dictionary)["ser"] == serialise_fn:
		_participants.erase(key)


func participant_keys() -> Array[String]:
	var out: Array[String] = []
	out.assign(_participants.keys())
	out.sort()
	return out


## A new game must not inherit extras that an earlier load left waiting.
func clear_pending_extras() -> void:
	_pending_extras = {}


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
	# Lets live nodes (e.g. the player body) write their transform into WorldState first.
	about_to_save.emit()
	var extras: Dictionary = {}
	for key: String in participant_keys():
		var ser: Callable = (_participants[key] as Dictionary)["ser"]
		if ser.is_valid():
			extras[key] = ser.call()
	return {
		"version": SAVE_VERSION,
		"clock": clock.serialise(),
		"state": state.serialise(),
		"timeline": timeline.serialise(),
		"extras": extras,
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
	var data: Dictionary = build_save()
	data["meta"] = _make_meta()
	# full_precision: the default 14-digit floats would drift positions and timers on reload.
	f.store_string(JSON.stringify(data, "", false, true))
	f.close()
	return DirAccess.rename_absolute(tmp, path)


# Menu-facing summary. Kept out of build_save() so two builds of the same state are identical.
func _make_meta() -> Dictionary:
	var player: Dictionary = state.get_entity(state.PLAYER_ID)
	return {
		"player": str((player.get("data", {}) as Dictionary).get("name", "")),
		"clock_now": int(clock.now),
		"saved_at": Time.get_unix_time_from_system(),
	}


## {"slot", "player", "clock_now", "saved_at"} for a readable save, {} otherwise.
func slot_info(slot: String) -> Dictionary:
	var r: Dictionary = read_save(slot)
	if r["error"] != OK:
		return {}
	var data: Dictionary = r["data"]
	var meta: Dictionary = data.get("meta", {}) if data.get("meta") is Dictionary else {}
	var saved_at: float = float(meta.get("saved_at", FileAccess.get_modified_time(slot_path(slot))))
	return {
		"slot": slot,
		"player": str(meta.get("player", "")),
		"clock_now": int(meta.get("clock_now", (data["clock"] as Dictionary).get("now", 0))),
		"saved_at": saved_at,
	}


## Newest readable save, manual or auto ("" if none). Continue uses this.
func latest_slot() -> String:
	var best: String = ""
	var best_at: float = -1.0
	for slot in list_slots():
		var info: Dictionary = slot_info(slot)
		if not info.is_empty() and float(info["saved_at"]) > best_at:
			best = slot
			best_at = float(info["saved_at"])
	return best


func manual_slots() -> Array[String]:
	var out: Array[String] = []
	for i in range(1, int(Config.get_value("save.manual_slots", 5)) + 1):
		out.append("%s%d" % [MANUAL_PREFIX, i])
	return out


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
	if data.has("extras") and not (data["extras"] is Dictionary):
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
	var extras: Dictionary = data.get("extras", {})
	_pending_extras = {}
	for key: String in extras:
		if not _participants.has(key):
			_pending_extras[key] = extras[key]
	for key: String in participant_keys():
		var deser: Callable = (_participants[key] as Dictionary)["deser"]
		if deser.is_valid():
			deser.call(extras.get(key, {}))
	_hours_since_autosave = 0
	loaded.emit()
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


# Sleeping is the natural checkpoint: the day's events have just played out.
func _on_player_slept(_hours: float, _place: String) -> void:
	if autosave_enabled:
		autosave()
