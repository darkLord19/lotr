extends Node

const CONFIG_FILES: Array[String] = ["res://config/game.json", "res://config/llm.json", "res://config/npc.json", "res://config/riders.json", "res://config/survival.json", "res://config/sim.json", "res://config/weather.json", "res://config/rumours.json", "res://config/terrain.json", "res://config/world.json", "res://config/style.json", "res://config/audio.json"]

var _data: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	_data = {}
	for path in CONFIG_FILES:
		var parsed: Variant = _read_json(path)
		if parsed is Dictionary:
			_data.merge(parsed, true)


# Dotted path lookup, e.g. get_value("clock.minutes_per_second", 0.5).
func get_value(path: String, default: Variant = null) -> Variant:
	var cur: Variant = _data
	for key in path.split("."):
		if cur is Dictionary and (cur as Dictionary).has(key):
			cur = (cur as Dictionary)[key]
		else:
			return default
	return cur


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		push_warning("Config: bad JSON in %s: %s" % [path, json.get_error_message()])
		return null
	return json.data
