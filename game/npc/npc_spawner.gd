class_name NPCSpawner
extends Node
## Gives roster NPCs a 3D body while the player is close (spawn 600 m, despawn 700 m). The
## off-screen simulation stays the single truth: bodies only follow the entity's abstract
## position (WorldState / OffscreenSim) and never write back. NPCs without an entity yet rest at
## their lore card's home_poi. Wraiths are skipped: riders get their own AI nodes.

var graph: RoadGraph
var viewer: Node3D
var height_provider: Callable = Callable()
## npc id -> NPCBody for everyone currently spawned.
var bodies: Dictionary = {}

var _cards: Dictionary = {}
var _scan_t: float = 0.0


static func cfg() -> Dictionary:
	return NPCBody.cfg().get("spawner", {})


## Spawn when inside `spawn_r`, despawn only beyond `despawn_r`, so a body at the edge does not flicker.
static func wants_body(dist: float, spawned: bool, spawn_r: float, despawn_r: float) -> bool:
	return dist <= (despawn_r if spawned else spawn_r)


## Stable spot near a resting place, so everyone at a POI does not stand on the same point.
static func rest_offset(id: String, min_m: float, max_m: float) -> Vector2:
	var h: int = id.hash()
	var ang: float = float(h & 0xFFFF) / 65535.0 * TAU
	var r: float = min_m + float((h >> 16) & 0xFFFF) / 65535.0 * (max_m - min_m)
	return Vector2(cos(ang), sin(ang)) * r


## Speed that closes `dist` in about `chase_s`, capped; 0 when already there.
static func chase_speed(dist: float, stop_m: float, chase_s: float, max_speed: float) -> float:
	return 0.0 if dist <= stop_m else minf(dist / maxf(chase_s, 0.01), max_speed)


func _ready() -> void:
	_load_cards()
	if not EventBus.dialogue_started.is_connected(_on_dialogue_started):
		EventBus.dialogue_started.connect(_on_dialogue_started)


func _exit_tree() -> void:
	if EventBus.dialogue_started.is_connected(_on_dialogue_started):
		EventBus.dialogue_started.disconnect(_on_dialogue_started)


func _process(delta: float) -> void:
	_scan_t += delta
	if _scan_t < float(cfg().get("scan_interval_s", 0.25)):
		return
	_scan_t = 0.0
	scan()


## One pass: spawn, despawn and steer every body toward its NPC's current position.
func scan() -> void:
	if viewer == null or not is_instance_valid(viewer):
		return
	var c: Dictionary = cfg()
	var spawn_r: float = float(c.get("spawn_radius_m", 600.0))
	var despawn_r: float = float(c.get("despawn_radius_m", 700.0))
	var here: Vector3 = viewer.global_position
	for id: String in _cards:
		var target: Variant = target_position(id)
		var spawned: bool = bodies.has(id)
		if not target is Vector3:
			if spawned:
				_despawn(id)
			continue
		var flat: float = Vector2((target as Vector3).x - here.x, (target as Vector3).z - here.z).length()
		if not wants_body(flat, spawned, spawn_r, despawn_r):
			if spawned:
				_despawn(id)
			continue
		if not spawned and not _spawn(id, target as Vector3):
			continue
		_steer(bodies[id] as NPCBody, target as Vector3, c)


## Where `id` should stand right now, or null if unknown / dead.
func target_position(id: String) -> Variant:
	var e: Dictionary = WorldState.get_entity(id)
	var pos: Vector3
	var resting: bool = false
	if not e.is_empty():
		if not bool(e.get("alive", true)):
			return null
		var loc: Dictionary = WorldState.entity_location(id)
		if not loc["pos"] is Vector3:
			return null
		pos = loc["pos"]
		resting = str(loc["poi"]) != ""
	else:
		var home: String = str((_cards[id] as Dictionary).get("home_poi", ""))
		if home.is_empty() or graph == null or not graph.has_poi(home):
			return null
		pos = graph.poi_pos(home)
		resting = true
	if resting:
		var c: Dictionary = cfg()
		var range_m: Array = c.get("rest_offset_m", [2.5, 6.0])
		var off: Vector2 = rest_offset(id, float(range_m[0]), float(range_m[1]))
		pos += Vector3(off.x, 0.0, off.y)
	if height_provider.is_valid():
		pos.y = float(height_provider.call(pos.x, pos.z))
	return pos


func _load_cards() -> void:
	_cards = {}
	var skip: Array = cfg().get("skip_races", [])
	var dir: DirAccess = DirAccess.open("%s/lore_cards/characters" % NPCContent.root)
	if dir == null:
		return
	for f: String in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var card: Dictionary = NPCContent.load_card(f.get_basename())
		if card.is_empty() or str(card.get("race", "")) in skip:
			continue
		_cards[str(card.get("id", f.get_basename()))] = card


func _spawn(id: String, pos: Vector3) -> bool:
	var card: Dictionary = _cards[id]
	var body := NPCBody.new()
	body.name = "NPC_%s" % id
	if not body.setup(id, {}, str(card.get("race", ""))):
		body.free()
		_cards.erase(id)  # no model for this one; do not retry every scan
		return false
	body.height_provider = height_provider
	add_child(body)
	body.global_position = pos
	var talk: Interactable = Interactable.make(Interactable.KIND_NPC, str(card.get("name", NPCContent.prettify(id))), id)
	talk.position.y = 1.0
	body.add_child(talk)
	bodies[id] = body
	return true


func _despawn(id: String) -> void:
	var body: NPCBody = bodies[id]
	bodies.erase(id)
	body.queue_free()


func _steer(body: NPCBody, target: Vector3, c: Dictionary) -> void:
	var to: Vector3 = target - body.global_position
	to.y = 0.0
	var dist: float = to.length()
	if dist > float(c.get("teleport_m", 60.0)):
		body.stop()
		body.global_position = target
		return
	var spd: float = chase_speed(dist, float(c.get("stop_distance_m", 0.3)), float(c.get("chase_time_s", 1.0)), float(c.get("max_chase_speed", 7.0)))
	if spd <= 0.0:
		if body.is_walking():
			body.stop()
	else:
		body.walk_to(target, spd)


func _on_dialogue_started(npc_id: String) -> void:
	if bodies.has(npc_id) and viewer != null:
		var body: NPCBody = bodies[npc_id]
		body.stop()
		body.face_direction(viewer.global_position - body.global_position)
