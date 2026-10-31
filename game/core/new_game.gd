class_name NewGame
extends RefCounted
## Builds a fresh WorldState from content for a chosen origin. Content is data
## (content/origins, background_traits, appearance); this only applies it.

const ORIGINS_PATH: String = "res://content/origins/m1.json"
const TRAITS_PATH: String = "res://content/background_traits.json"
const APPEARANCE_PATH: String = "res://content/appearance.json"
const MODE_A: StringName = &"A"
const MODE_B: StringName = &"B"
const FLAG_ORIGIN_PREFIX: String = "origin."
const FLAG_TRAIT_PREFIX: String = "trait."

# Injectable so tests can run against private instances; default to the autoloads.
var state: Node = WorldState
var clock: Node = WorldClock
var timeline: Node = Timeline
var saves: Node = SaveSystem


static func load_origins() -> Array[Dictionary]:
	return _dict_array(_read_json(ORIGINS_PATH))


static func load_traits() -> Array[Dictionary]:
	return _dict_array(_read_json(TRAITS_PATH))


## {"palettes": Array[Dictionary], "hair_styles": Array[Dictionary]}
static func load_appearance() -> Dictionary:
	var d: Variant = _read_json(APPEARANCE_PATH)
	return d if d is Dictionary else {"palettes": [], "hair_styles": []}


static func find_by_id(list: Array[Dictionary], id: String) -> Dictionary:
	for entry: Dictionary in list:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


## Params: name, race, origin, background_trait, palette, hair, mode ("A"/"B").
## Returns {"error": Error, "message": String}; on success also "origin" and "player".
func new_game(params: Dictionary) -> Dictionary:
	var checked: Dictionary = _validate(params)
	if int(checked["error"]) != OK:
		return checked
	var origin: Dictionary = checked["origin_data"]
	var trait_data: Dictionary = checked["trait_data"]
	var effects: Dictionary = trait_data["effects"]

	state.reset()
	# Timeline keeps fired/pending state across games, so rebuild it from content.
	timeline.clear()
	timeline.bind(clock, state)
	timeline.load_content_dirs()

	var start: int = GameDate.parse(str(origin["start_date"]))
	clock.now = start
	clock.set_mode(StringName(str(params["mode"])))

	var skills: Dictionary = {}
	var bonus: Dictionary = origin["skill_bonus"]
	_add_skill(skills, str(bonus["skill"]), float(bonus["amount"]))
	for skill: String in (effects["skills"] as Dictionary):
		_add_skill(skills, skill, float(effects["skills"][skill]))

	var player_data: Dictionary = {
		"name": str(params["name"]).strip_edges(),
		"race": str(params["race"]),
		"origin": str(origin["id"]),
		"background_trait": str(trait_data["id"]),
		"appearance": {"palette": str(params["palette"]), "hair": str(params["hair"])},
		"skills": skills,
	}
	state.spawn_entity(state.PLAYER_ID, "player", str(origin["start_poi"]), str(Config.get_value("new_game.region", "")), player_data)
	state.set_flag(FLAG_ORIGIN_PREFIX + str(origin["id"]))
	state.set_flag(FLAG_TRAIT_PREFIX + str(trait_data["id"]))

	for entry: Dictionary in origin["items"]:
		state.transfer_item(str(entry["item"]), "", state.PLAYER_ID, int(entry["count"]))

	_apply_reputation(origin["reputation_offset"])
	_apply_reputation(effects["reputation"])
	_seed_memories(origin["known_by"], int(effects["first_impression"]), start)

	saves.autosave_enabled = true
	return {"error": OK, "message": "", "origin": str(origin["id"]), "player": state.PLAYER_ID}


func _validate(params: Dictionary) -> Dictionary:
	var name: String = str(params.get("name", "")).strip_edges()
	var max_len: int = int(Config.get_value("new_game.name_max_length", 24))
	if name.is_empty() or name.length() > max_len:
		return _fail("Name must be 1-%d characters." % max_len)
	var origin: Dictionary = find_by_id(load_origins(), str(params.get("origin", "")))
	if origin.is_empty():
		return _fail("Unknown origin '%s'." % params.get("origin", ""))
	var race: String = str(params.get("race", ""))
	if race != str(origin["race"]):
		return _fail("Origin '%s' is not open to race '%s'." % [origin["id"], race])
	var trait_data: Dictionary = find_by_id(load_traits(), str(params.get("background_trait", "")))
	if trait_data.is_empty():
		return _fail("Unknown background trait '%s'." % params.get("background_trait", ""))
	var look: Dictionary = load_appearance()
	if find_by_id(_dict_array(look["palettes"]), str(params.get("palette", ""))).is_empty():
		return _fail("Unknown palette '%s'." % params.get("palette", ""))
	var hair: Dictionary = find_by_id(_dict_array(look["hair_styles"]), str(params.get("hair", "")))
	if hair.is_empty() or race not in (hair["races"] as Array):
		return _fail("Hair '%s' is not available to %s." % [params.get("hair", ""), race])
	var mode: String = str(params.get("mode", ""))
	if mode != String(MODE_A) and mode != String(MODE_B):
		return _fail("Time mode must be A or B.")
	return {"error": OK, "message": "", "origin_data": origin, "trait_data": trait_data}


func _fail(message: String) -> Dictionary:
	return {"error": ERR_INVALID_PARAMETER, "message": message}


func _add_skill(skills: Dictionary, skill: String, amount: float) -> void:
	skills[skill] = float(skills.get(skill, 0.0)) + amount


func _apply_reputation(offsets: Dictionary) -> void:
	for faction: String in offsets:
		state.change_reputation(faction, int(offsets[faction]))


# The trait's first impression shifts every seeded NPC's disposition, so a Kind
# character starts warmer with everyone who already knows them.
func _seed_memories(known_by: Array, first_impression: int, start: int) -> void:
	var lo: int = int(Config.get_value("npc.disposition_min", -10))
	var hi: int = int(Config.get_value("npc.disposition_max", 10))
	for raw: Variant in known_by:
		var k: Dictionary = raw
		var disposition: int = clampi(int(k.get("disposition", 0)) + first_impression, lo, hi)
		var last_talk: int = start - int(k.get("days_ago", 0)) * GameDate.MINUTES_PER_DAY
		state.set_npc_memory(str(k["npc"]), str(k["memory"]), last_talk, disposition)


static func _dict_array(v: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if v is Array:
		for e: Variant in v:
			if e is Dictionary:
				out.append(e)
	return out


static func _read_json(path: String) -> Variant:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_warning("NewGame: bad or missing JSON %s" % path)
		return null
	return json.data
