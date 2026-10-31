class_name RiderInterrogation
extends RefCounted
## Scripted (never LLM-generated) rider exchange: menacing and reliable. Data lives in
## content/riders/interrogation.json; hobbits get the more intense Baggins questioning.


## Returns Array of {speaker: String, text: String} beats in order.
static func build(player_race: String, path: String = "") -> Array[Dictionary]:
	var data: Dictionary = _load(path)
	var hobbit: bool = player_race == str(Config.get_value("soft_failure.hobbit_race", "hobbit"))
	var out: Array[Dictionary] = []
	for section: String in ["opening", "baggins_hobbit" if hobbit else "baggins_default", "closing"]:
		for beat: Variant in data.get(section, []):
			if beat is Dictionary:
				out.append((beat as Dictionary).duplicate())
	return out


static func _load(path: String) -> Dictionary:
	var p: String = path if path != "" else str(Config.get_value("riders.interrogation_content", ""))
	if p == "" or not FileAccess.file_exists(p):
		push_warning("RiderInterrogation: missing content %s" % p)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if parsed is Dictionary else {}
