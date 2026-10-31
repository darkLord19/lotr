class_name VillagerSpawner
extends Node
## Spawns villager NPC bodies within 600 m of the player using VillagerSchedule routines.
## Villager routines are a function of (villager, template, clock) and are only evaluated for
## settlements near the player. Far-away villagers cost zero CPU and memory.

const VILLAGERS_PATH: String = "res://content/villagers.json"
const SPAWN_RADIUS_M: float = 600.0
const DESPAWN_RADIUS_M: float = 700.0
const SCAN_INTERVAL_S: float = 0.5

var graph: RoadGraph
var viewer: Node3D
var height_provider: Callable = Callable()

## villager id -> NPCBody
var bodies: Dictionary = {}
var villagers: Array = []

var _scan_timer: float = 0.0


func _ready() -> void:
	if villagers.is_empty():
		villagers = load_villagers()
	if graph == null:
		graph = RoadGraph.new()
		graph.load_region()
	scan()


func _exit_tree() -> void:
	for id: String in bodies.keys():
		_despawn(id)


func _process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL_S:
		_scan_timer = 0.0
		scan()


func scan() -> void:
	if viewer == null or not is_instance_valid(viewer) or graph == null:
		return
	var player_pos: Vector3 = viewer.global_position
	var now: int = WorldClock.now
	var near_states: Dictionary = VillagerSchedule.positions_near(villagers, player_pos, now, graph, SPAWN_RADIUS_M)

	# 1. Despawn any spawned villagers that are no longer in near_states or beyond DESPAWN_RADIUS_M
	var to_despawn: Array[String] = []
	for id: String in bodies:
		var body: NPCBody = bodies[id] as NPCBody
		if not is_instance_valid(body):
			to_despawn.append(id)
			continue
		var flat_dist: float = Vector2(body.global_position.x - player_pos.x, body.global_position.z - player_pos.z).length()
		if not near_states.has(id) and flat_dist > DESPAWN_RADIUS_M:
			to_despawn.append(id)
	for id: String in to_despawn:
		_despawn(id)

	# 2. Spawn and update positions for villagers in near_states
	for v_raw: Variant in villagers:
		var v: Dictionary = v_raw as Dictionary
		var id: String = str(v.get("id", ""))
		if not near_states.has(id):
			continue
		var state: Dictionary = near_states[id] as Dictionary
		var target_pos: Vector3 = state.get("pos", Vector3.ZERO) as Vector3
		if height_provider.is_valid():
			target_pos.y = float(height_provider.call(target_pos.x, target_pos.z))

		var body: NPCBody
		if not bodies.has(id):
			body = _spawn(v, target_pos)
			if body == null:
				continue
		else:
			body = bodies[id] as NPCBody
			_steer(body, target_pos, bool(state.get("moving", false)))


func _spawn(v: Dictionary, pos: Vector3) -> NPCBody:
	var id: String = str(v.get("id", ""))
	var template_id: String = str(v.get("template", "shire_hobbit_villager"))
	var race: String = "hobbit" if "hobbit" in template_id else "man"
	var body := NPCBody.new()
	body.name = "Villager_%s" % id

	var look: Dictionary = NPCBody.roll_look(template_id, id.hash())
	if not body.setup(template_id, look, race):
		body.free()
		return null

	body.height_provider = height_provider
	add_child(body)
	body.global_position = pos

	var name_str: String = str(v.get("name", id.capitalize()))
	var card: Dictionary = NPCContent.villager_card(v)
	var interactable := Interactable.make(Interactable.KIND_NPC, name_str, id, {"card": card, "template": template_id})
	interactable.position.y = 1.0
	body.add_child(interactable)

	bodies[id] = body
	return body


func _despawn(id: String) -> void:
	if bodies.has(id):
		var body: NPCBody = bodies[id] as NPCBody
		bodies.erase(id)
		if is_instance_valid(body):
			body.queue_free()


func _steer(body: NPCBody, target: Vector3, _is_moving: bool) -> void:
	var to: Vector3 = target - body.global_position
	to.y = 0.0
	var dist: float = to.length()
	if dist > 60.0:
		body.stop()
		body.global_position = target
		return
	if dist <= 0.3:
		if body.is_walking():
			body.stop()
	else:
		var spd: float = clampf(dist / 1.0, 1.2, 4.0)
		body.walk_to(target, spd)


static func load_villagers() -> Array:
	if not FileAccess.file_exists(VILLAGERS_PATH):
		return []
	var text: String = FileAccess.get_file_as_string(VILLAGERS_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return parsed as Array
	return []
