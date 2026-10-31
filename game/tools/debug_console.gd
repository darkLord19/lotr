class_name DebugConsole
extends Control
## Developer console (backtick), only in debug builds. Parsing is a pure static function so it is
## unit-tested; execution talks to the autoloads and the player through a small context.
##   tp <poi>   date <iso>   give <item> [n]   flag <key> <value>   mode A|B   speed <x>
## `speed` scales the world clock (WorldClock.time_scale), not the player.

signal command_run(line: String, output: String)

const COMMANDS: Dictionary = {
	"tp": {"min": 1, "max": 1, "usage": "tp <poi>"},
	"date": {"min": 1, "max": 1, "usage": "date <YYYY-MM-DD[THH:MM]>"},
	"give": {"min": 1, "max": 2, "usage": "give <item> [count]"},
	"flag": {"min": 2, "max": 2, "usage": "flag <key> <value>"},
	"mode": {"min": 1, "max": 1, "usage": "mode A|B"},
	"speed": {"min": 1, "max": 1, "usage": "speed <multiplier>"},
	"help": {"min": 0, "max": 0, "usage": "help"},
}

## What commands act on. Tests inject their own; the session sets the real player.
var player: PlayerController
var inventory: Inventory

var _edit: LineEdit
var _log: Label
var _lines: Array[String] = []


# --- pure parsing ---------------------------------------------------------------------------

## {"ok": bool, "cmd": String, "args": Array, "error": String}. Args are already typed:
## give -> [String, int], flag -> [String, Variant], mode -> [StringName], speed -> [float].
static func parse(line: String) -> Dictionary:
	var parts: PackedStringArray = line.strip_edges().split(" ", false)
	if parts.is_empty():
		return _bad("", "empty command")
	var cmd: String = parts[0].to_lower()
	if not COMMANDS.has(cmd):
		return _bad(cmd, "unknown command '%s' (try help)" % cmd)
	var spec: Dictionary = COMMANDS[cmd]
	var raw: Array = Array(parts.slice(1))
	if raw.size() < int(spec["min"]) or raw.size() > int(spec["max"]):
		return _bad(cmd, "usage: %s" % spec["usage"])
	var args: Array = raw
	match cmd:
		"give":
			var count: int = 1
			if raw.size() == 2:
				if not str(raw[1]).is_valid_int() or int(str(raw[1])) <= 0:
					return _bad(cmd, "count must be a positive integer")
				count = int(str(raw[1]))
			args = [str(raw[0]), count]
		"flag":
			args = [str(raw[0]), parse_value(str(raw[1]))]
		"mode":
			var m: String = str(raw[0]).to_upper()
			if m != "A" and m != "B":
				return _bad(cmd, "mode must be A or B")
			args = [StringName(m)]
		"speed":
			if not str(raw[0]).is_valid_float() or float(str(raw[0])) <= 0.0:
				return _bad(cmd, "speed must be a positive number")
			args = [float(str(raw[0]))]
		"date":
			if GameDate.parse(str(raw[0])) == GameDate.INVALID:
				return _bad(cmd, "bad date '%s'" % raw[0])
	return {"ok": true, "cmd": cmd, "args": args, "error": ""}


static func parse_value(text: String) -> Variant:
	var lower: String = text.to_lower()
	if lower == "true":
		return true
	if lower == "false":
		return false
	if text.is_valid_int():
		return int(text)
	if text.is_valid_float():
		return float(text)
	return text


static func _bad(cmd: String, error: String) -> Dictionary:
	return {"ok": false, "cmd": cmd, "args": [], "error": error}


## Console only exists in debug builds; release exports compile it out of the session.
static func available() -> bool:
	return OS.is_debug_build()


# --- execution ------------------------------------------------------------------------------

## Runs one line and returns the text to print.
func run(line: String) -> String:
	var parsed: Dictionary = parse(line)
	if not bool(parsed["ok"]):
		return "error: %s" % parsed["error"]
	var args: Array = parsed["args"]
	match str(parsed["cmd"]):
		"help":
			return "\n".join(COMMANDS.keys().map(func(k: Variant) -> String: return str((COMMANDS[k] as Dictionary)["usage"])))
		"tp":
			return _tp(str(args[0]))
		"date":
			var target: int = GameDate.parse(str(args[0]))
			if target > WorldClock.now:
				WorldClock.advance(target - WorldClock.now)
			else:
				WorldClock.now = target
			return "date -> %s" % GameDate.format_iso(WorldClock.now)
		"give":
			var item: String = str(args[0])
			if not ItemDB.has_item(item):
				return "error: unknown item '%s'" % item
			var inv: Inventory = inventory if inventory != null else Inventory.new(WorldState.PLAYER_ID)
			return "gave %d x %s" % [int(args[1]), item] if inv.add(item, int(args[1])) else "error: cannot carry that"
		"flag":
			WorldState.set_flag(str(args[0]), args[1])
			return "flag %s = %s" % [args[0], str(args[1])]
		"mode":
			WorldClock.set_mode(args[0] as StringName)
			Settings.sync_from_clock()
			return "time mode %s" % args[0]
		"speed":
			WorldClock.time_scale = float(args[0])
			return "clock time_scale = %s" % str(args[0])
	return ""


func _tp(poi: String) -> String:
	if not WorldState.poi_info.has(poi):
		return "error: unknown poi '%s'" % poi
	if player == null:
		return "error: no player"
	var p: Vector3 = (WorldState.poi_info[poi] as Dictionary)["pos"]
	player.place_at(p.x, p.z)
	return "teleported to %s" % poi


# --- UI -----------------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs: int = int(Config.get_value("player.ui.console_font_size", 22))
	var box := VBoxContainer.new()
	add_child(box)
	_log = Label.new()
	_log.add_theme_font_size_override("font_size", fs)
	_log.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))
	box.add_child(_log)
	_edit = LineEdit.new()
	_edit.custom_minimum_size.y = float(Config.get_value("player.ui.console_height_px", 44))
	_edit.add_theme_font_size_override("font_size", fs)
	_edit.placeholder_text = "console (help)"
	_edit.text_submitted.connect(_on_submitted)
	box.add_child(_edit)
	hide()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_console"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		show()
		_edit.grab_focus()


func close() -> void:
	_edit.release_focus()
	hide()


func _on_submitted(line: String) -> void:
	_edit.clear()
	if line.strip_edges().is_empty():
		return
	var out: String = run(line)
	_lines.append("> %s\n%s" % [line, out])
	while _lines.size() > int(Config.get_value("player.ui.console_log_lines", 8)):
		_lines.pop_front()
	_log.text = "\n".join(_lines)
	command_run.emit(line, out)
