class_name Foraging
extends RefCounted
## Forage nodes (mushrooms, berries). Nodes are a plain Array of Dictionaries so place_world.py can
## write them later:
##   {"id": String, "item": String, "pos": [x, y, z], "yield": int (optional), "zone": String (optional)}
## `zone` names an off-limits area from config foraging.zones (e.g. "maggots_fields").
## Regrowth timestamps are WorldState flags so they persist and survive save/load.

const FLAG_PREFIX: String = "forage_ready_at."
const FLAG_CAUGHT_COUNT: String = "forage_caught_count."

var _nodes: Dictionary = {}
var _state: Node
var _clock: Node
var _inventory: Inventory
var _skills: Skills
var _factions: Factions
var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(nodes: Array, inventory: Inventory, skills: Skills = null, factions: Factions = null, state: Node = null, clock: Node = null) -> void:
	_state = state if state != null else WorldState
	_clock = clock if clock != null else WorldClock
	_inventory = inventory
	_skills = skills
	_factions = factions if factions != null else Factions.new(_state)
	for n: Variant in nodes:
		var node: Dictionary = n
		_nodes[str(node["id"])] = node
	rng.randomize()


func node_ids() -> Array:
	return _nodes.keys()


func is_ready(node_id: String) -> bool:
	if not _nodes.has(node_id):
		return false
	return _clock.now >= int(_state.get_flag(FLAG_PREFIX + node_id, 0))


func zone_of(node_id: String) -> String:
	return str((_nodes.get(node_id, {}) as Dictionary).get("zone", ""))


func is_off_limits(node_id: String) -> bool:
	return Tuning.dict("foraging.zones").has(zone_of(node_id))


## Nodes the player may currently pick, optionally within `radius` of `from`.
func ready_nodes(from: Vector3 = Vector3.ZERO, radius: float = INF) -> Array[String]:
	var out: Array[String] = []
	for id: String in _nodes:
		if not is_ready(id):
			continue
		if radius < INF:
			var p: Array = (_nodes[id] as Dictionary).get("pos", [0, 0, 0])
			if from.distance_to(Vector3(p[0], p[1], p[2])) > radius:
				continue
		out.append(id)
	return out


## Chance an owner's dogs/eyes catch the player in an off-limits zone; stealth lowers it.
func caught_chance() -> float:
	var mult: float = _skills.effect("forage_caught_multiplier") if _skills != null else 1.0
	return clampf(Tuning.num("foraging.base_caught_chance") * mult, 0.0, 1.0)


func roll_caught() -> bool:
	return rng.randf() < caught_chance()


## Picks a node. `witnessed` is decided by the caller (dog perception, or roll_caught()).
## Returns {ok, reason, item, count, caught}. A caught player still keeps the haul: the
## penalty is social, not confiscation.
func forage(node_id: String, witnessed: bool = false) -> Dictionary:
	var result: Dictionary = {"ok": false, "reason": "", "item": "", "count": 0, "caught": false}
	if not _nodes.has(node_id):
		result["reason"] = "unknown_node"
		return result
	if not is_ready(node_id):
		result["reason"] = "not_ready"
		return result
	var node: Dictionary = _nodes[node_id]
	var item: String = str(node["item"])
	var count: int = int(node.get("yield", Tuning.integer("foraging.default_yield")))
	if _skills != null:
		count += int(_skills.effect("forage_yield_bonus"))
	if not _inventory.add(item, count):
		result["reason"] = "too_heavy"
		return result
	_state.set_flag(FLAG_PREFIX + node_id, _clock.now + _regrow_minutes())
	if _skills != null:
		_skills.record_action("forage")
	result["ok"] = true
	result["item"] = item
	result["count"] = count
	if witnessed and is_off_limits(node_id):
		_apply_caught(zone_of(node_id))
		result["caught"] = true
	return result


func _regrow_minutes() -> int:
	var days: int = rng.randi_range(Tuning.integer("foraging.regrow_days_min"), Tuning.integer("foraging.regrow_days_max"))
	return days * _clock.MINUTES_PER_DAY


func _apply_caught(zone: String) -> void:
	var def: Dictionary = Tuning.dict("foraging.zones")[zone]
	_factions.change_reputation(str(def["faction"]), -int(def["reputation_loss"]))
	_factions.change_disposition(str(def["owner_npc"]), -int(def["owner_disposition_loss"]))
	_state.set_flag(str(def["flag"]), true)
	var key: String = FLAG_CAUGHT_COUNT + zone
	_state.set_flag(key, int(_state.get_flag(key, 0)) + 1)
