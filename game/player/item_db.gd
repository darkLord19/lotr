class_name ItemDB
extends RefCounted
## Cached loader for content/items/*.json. Items are content, so this never touches WorldState.

static var root: String = "res://content/items"
static var _cache: Dictionary = {}
static var _loaded_root: String = ""


static func clear_cache() -> void:
	_cache = {}
	_loaded_root = ""


static func has_item(item_id: String) -> bool:
	_ensure_loaded()
	return _cache.has(item_id)


## Empty dictionary for unknown ids.
static func get_item(item_id: String) -> Dictionary:
	_ensure_loaded()
	return _cache.get(item_id, {})


static func weight_of(item_id: String) -> float:
	return float(get_item(item_id).get("weight", 0.0))


static func value_of(item_id: String) -> int:
	return int(get_item(item_id).get("value", 0))


static func kind_of(item_id: String) -> String:
	return str(get_item(item_id).get("kind", ""))


static func _ensure_loaded() -> void:
	if _loaded_root == root:
		return
	_cache = {}
	_loaded_root = root
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		push_warning("ItemDB: cannot open %s" % root)
		return
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for f: String in files:
		if not f.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [root, f]))
		if not parsed is Array:
			push_warning("ItemDB: %s is not an array" % f)
			continue
		for entry: Variant in parsed:
			if entry is Dictionary and (entry as Dictionary).has("id"):
				_cache[str((entry as Dictionary)["id"])] = entry
