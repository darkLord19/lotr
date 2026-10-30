extends Node
# Single source of truth for gameplay state. Mutate only through these methods so
# every change reaches the EventBus; never poke the dictionaries directly.

const PLAYER_ID: String = "player"
const REPUTATION_MIN: int = -100
const REPUTATION_MAX: int = 100

# id -> {kind, poi, pos (Array [x,y,z] or empty), region, alive, data}
var entities: Dictionary = {}
var flags: Dictionary = {}
# owner -> {item_id: count}
var inventories: Dictionary = {}
# faction -> int
var reputation: Dictionary = {}
# npc -> {summary, last_talk, disposition}
var npc_memory: Dictionary = {}
# npc -> Array[knowledge_id]
var knowledge: Dictionary = {}
# rumour_id -> Array[poi]
var rumours: Dictionary = {}

# World geometry registered by the region loader; not saved (it is content, not state).
# poi_id -> {"pos": Vector3, "settlement": String}
var poi_info: Dictionary = {}


func reset() -> void:
	entities = {}
	flags = {}
	inventories = {}
	reputation = {}
	npc_memory = {}
	knowledge = {}
	rumours = {}


func register_poi(poi_id: String, pos: Vector3, settlement: String = "") -> void:
	poi_info[poi_id] = {"pos": pos, "settlement": settlement}


# --- flags -----------------------------------------------------------------

func set_flag(flag: String, value: Variant = true) -> void:
	if flags.has(flag) and flags[flag] == value:
		return
	flags[flag] = value
	EventBus.flag_changed.emit(flag, value)


func get_flag(flag: String, default: Variant = false) -> Variant:
	return flags.get(flag, default)


# --- entities --------------------------------------------------------------

# poi_or_pos: a String poi id or a Vector3 position.
func spawn_entity(id: String, kind: String, poi_or_pos: Variant = "", region: String = "", data: Dictionary = {}) -> void:
	var e: Dictionary = {"kind": kind, "poi": "", "pos": [], "region": region, "alive": true, "data": data.duplicate(true)}
	_set_location(e, poi_or_pos)
	entities[id] = e
	EventBus.entity_moved.emit(id, poi_or_pos)


func has_entity(id: String) -> bool:
	return entities.has(id)


func get_entity(id: String) -> Dictionary:
	return entities.get(id, {})


func move_entity(id: String, poi_or_pos: Variant) -> bool:
	if not entities.has(id):
		push_warning("WorldState.move_entity: unknown entity %s" % id)
		return false
	_set_location(entities[id], poi_or_pos)
	EventBus.entity_moved.emit(id, poi_or_pos)
	return true


func set_alive(id: String, alive: bool) -> void:
	if entities.has(id):
		(entities[id] as Dictionary)["alive"] = alive


# Returns {"poi": String, "pos": Vector3 or null}. pos is resolved from the poi
# registry when the entity only has a poi.
func entity_location(id: String) -> Dictionary:
	var e: Dictionary = entities.get(id, {})
	if e.is_empty():
		return {"poi": "", "pos": null}
	var poi: String = e["poi"]
	var pos: Variant = null
	var arr: Array = e["pos"]
	if arr.size() == 3:
		pos = Vector3(arr[0], arr[1], arr[2])
	elif poi != "" and poi_info.has(poi):
		pos = (poi_info[poi] as Dictionary)["pos"]
	return {"poi": poi, "pos": pos}


func _set_location(e: Dictionary, poi_or_pos: Variant) -> void:
	if poi_or_pos is Vector3:
		var v: Vector3 = poi_or_pos
		e["pos"] = [v.x, v.y, v.z]
		e["poi"] = ""
	else:
		e["poi"] = str(poi_or_pos)
		e["pos"] = []


# --- inventories -----------------------------------------------------------

func item_count(owner: String, item: String) -> int:
	return int((inventories.get(owner, {}) as Dictionary).get(item, 0))


# from_owner "" means the item is created (loot, gifts from the world).
# to_owner "" means it is consumed. Fails (false) if the giver lacks the items.
func transfer_item(item: String, from_owner: String, to_owner: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	if from_owner != "":
		if item_count(from_owner, item) < count:
			return false
		_add_count(from_owner, item, -count)
	if to_owner != "":
		_add_count(to_owner, item, count)
	EventBus.item_transferred.emit(item, from_owner, to_owner)
	return true


func _add_count(owner: String, item: String, delta: int) -> void:
	var inv: Dictionary = inventories.get(owner, {})
	var n: int = int(inv.get(item, 0)) + delta
	if n > 0:
		inv[item] = n
	else:
		inv.erase(item)
	if inv.is_empty():
		inventories.erase(owner)
	else:
		inventories[owner] = inv


# --- reputation ------------------------------------------------------------

func get_reputation(faction: String) -> int:
	return int(reputation.get(faction, 0))


func change_reputation(faction: String, delta: int) -> int:
	var v: int = clampi(get_reputation(faction) + delta, REPUTATION_MIN, REPUTATION_MAX)
	reputation[faction] = v
	EventBus.reputation_changed.emit(faction, v)
	return v


# --- NPC memory / knowledge / rumours --------------------------------------

func get_npc_memory(npc: String) -> Dictionary:
	return (npc_memory.get(npc, {"summary": "", "last_talk": -1, "disposition": 0}) as Dictionary).duplicate()


func set_npc_memory(npc: String, summary: String, last_talk: int, disposition: int) -> void:
	npc_memory[npc] = {"summary": summary, "last_talk": last_talk, "disposition": disposition}
	EventBus.npc_memory_changed.emit(npc)


func add_knowledge(npc: String, knowledge_id: String) -> void:
	var list: Array = knowledge.get(npc, [])
	if knowledge_id in list:
		return
	list.append(knowledge_id)
	knowledge[npc] = list
	EventBus.knowledge_added.emit(npc, knowledge_id)


func has_knowledge(npc: String, knowledge_id: String) -> bool:
	return knowledge_id in (knowledge.get(npc, []) as Array)


func spread_rumour(rumour_id: String, poi: String) -> void:
	var pois: Array = rumours.get(rumour_id, [])
	if poi not in pois:
		pois.append(poi)
		rumours[rumour_id] = pois
	EventBus.rumour_spread.emit(rumour_id, poi)


func rumour_known_at(rumour_id: String, poi: String) -> bool:
	return poi in (rumours.get(rumour_id, []) as Array)


# --- save/load -------------------------------------------------------------

func serialise() -> Dictionary:
	return {
		"entities": entities.duplicate(true),
		"flags": flags.duplicate(true),
		"inventories": inventories.duplicate(true),
		"reputation": reputation.duplicate(true),
		"npc_memory": npc_memory.duplicate(true),
		"knowledge": knowledge.duplicate(true),
		"rumours": rumours.duplicate(true),
	}


# JSON turns ints into floats, so counts are re-coerced to keep round-trips exact.
func deserialise(d: Dictionary) -> void:
	reset()
	entities = (d.get("entities", {}) as Dictionary).duplicate(true)
	flags = (d.get("flags", {}) as Dictionary).duplicate(true)
	knowledge = (d.get("knowledge", {}) as Dictionary).duplicate(true)
	rumours = (d.get("rumours", {}) as Dictionary).duplicate(true)
	for owner: String in (d.get("inventories", {}) as Dictionary):
		var inv: Dictionary = {}
		for item: String in d["inventories"][owner]:
			inv[item] = int(d["inventories"][owner][item])
		inventories[owner] = inv
	for faction: String in (d.get("reputation", {}) as Dictionary):
		reputation[faction] = int(d["reputation"][faction])
	for npc: String in (d.get("npc_memory", {}) as Dictionary):
		var m: Dictionary = (d["npc_memory"][npc] as Dictionary).duplicate()
		m["last_talk"] = int(m.get("last_talk", -1))
		m["disposition"] = int(m.get("disposition", 0))
		npc_memory[npc] = m
