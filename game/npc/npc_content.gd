class_name NPCContent
extends RefCounted
## Read-only loaders for the content the NPC mind needs. Results are cached; tests that point
## `root` elsewhere must call clear_cache().

static var root: String = "res://content"
static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache = {}


static func load_card(npc_id: String) -> Dictionary:
	var d: Variant = _json("%s/lore_cards/characters/%s.json" % [root, npc_id])
	return d if d is Dictionary else {}


static func load_fallbacks(npc_id: String) -> Dictionary:
	var d: Variant = _json("%s/dialogue_fallbacks/%s.json" % [root, npc_id])
	return d if d is Dictionary else {}


static func load_template(template_id: String) -> Dictionary:
	var d: Variant = _json("%s/lore_cards/templates/%s.json" % [root, template_id])
	return d if d is Dictionary else {}


static func villager_card(villager: Dictionary) -> Dictionary:
	var tpl_id: String = str(villager.get("template", "shire_hobbit_villager"))
	var tpl: Dictionary = load_template(tpl_id)
	var card: Dictionary = tpl.duplicate(true)
	card["id"] = villager.get("id", "")
	card["name"] = villager.get("name", prettify(str(villager.get("id", ""))))
	card["template"] = tpl_id
	card["home_poi"] = villager.get("home", "")
	card["settlement"] = villager.get("settlement", "")
	return card


static func prompt_text(name: String) -> String:
	var path: String = "%s/prompts/%s.md" % [root, name]
	if not FileAccess.file_exists(path):
		push_warning("NPCContent: missing prompt %s" % path)
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()


# rumour id -> rumour dict, merged from every file in content/rumours/.
static func rumours() -> Dictionary:
	var key: String = "rumours@" + root
	if _cache.has(key):
		return _cache[key]
	var out: Dictionary = {}
	var dir: DirAccess = DirAccess.open("%s/rumours" % root)
	if dir != null:
		for f: String in dir.get_files():
			if not f.ends_with(".json"):
				continue
			var d: Variant = _json("%s/rumours/%s" % [root, f])
			if d is Array:
				for r: Variant in d:
					if r is Dictionary and (r as Dictionary).has("id"):
						out[(r as Dictionary)["id"]] = r
	_cache[key] = out
	return out


# Delegates so learned (dynamic) rumours and the {player} placeholder resolve in one place.
static func rumour_text(rumour_id: String) -> String:
	return RumourNetwork.resolve_text(rumour_id)


static func prettify(id: String) -> String:
	return id.replace("_", " ").capitalize()


static func _json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		var j := JSON.new()
		if j.parse(FileAccess.get_file_as_string(path)) == OK:
			parsed = j.data
		else:
			push_warning("NPCContent: bad JSON in %s: %s" % [path, j.get_error_message()])
	_cache[path] = parsed
	return parsed
