class_name RiderManager
extends Node
## Manages Black Rider scene bodies, perception feeds (LOS, road distance, vegetation cover,
## weather bonuses), HUD eye awareness icon, music danger cues, and interrogation flow.

const RIDER_IDS: Array[String] = ["black_rider_khamul", "black_riders_group"]
const SPAWN_RADIUS_M: float = 600.0
const DESPAWN_RADIUS_M: float = 700.0
const SCAN_INTERVAL_S: float = 0.25
const REGION_PATH: String = "res://content/regions/eriador_west.json"

var viewer: Node3D
var weather: WeatherDayNight
var audio: AudioSession
var hud: HUD
var region_data: Dictionary = {}

## rider_id -> RiderAINode
var active_riders: Dictionary = {}

var _scan_timer: float = 0.0


func _ready() -> void:
	if region_data.is_empty():
		region_data = AudioSession.load_default_region()
	scan()


func _process(delta: float) -> void:
	_scan_timer += delta
	if _scan_timer >= SCAN_INTERVAL_S:
		_scan_timer = 0.0
		scan()
	_update_feedback()


func scan() -> void:
	if viewer == null or not is_instance_valid(viewer):
		return
	var player_pos: Vector3 = viewer.global_position

	# Check each canon rider entity
	for id: String in RIDER_IDS:
		var e: Dictionary = WorldState.get_entity(id)
		if e.is_empty() or not bool(e.get("alive", true)):
			if active_riders.has(id):
				_despawn_rider(id)
			continue
		var loc: Dictionary = WorldState.entity_location(id)
		var rpos_var: Variant = loc.get("pos", null)
		if not (rpos_var is Vector3):
			if active_riders.has(id):
				_despawn_rider(id)
			continue
		var rpos: Vector3 = rpos_var as Vector3
		var flat_dist: float = Vector2(rpos.x - player_pos.x, rpos.z - player_pos.z).length()
		var spawned: bool = active_riders.has(id)

		if NPCSpawner.wants_body(flat_dist, spawned, SPAWN_RADIUS_M, DESPAWN_RADIUS_M):
			if not spawned:
				_spawn_rider(id, rpos)
		else:
			if spawned:
				_despawn_rider(id)


func _spawn_rider(id: String, pos: Vector3) -> RiderAINode:
	var node := RiderAINode.new()
	node.name = "Rider_" + id
	node.entity_id = id
	var race: String = "hobbit"
	if viewer is PlayerController:
		race = (viewer as PlayerController).race
	node.player_race = race
	node.target_provider = Callable(self, "_build_target_for").bind(node)
	node.night_provider = Callable(self, "_is_night")
	node.interrogation_started.connect(_on_interrogation_started.bind(node))
	add_child(node)
	node.global_position = pos
	active_riders[id] = node
	return node


func _despawn_rider(id: String) -> void:
	if active_riders.has(id):
		var node: RiderAINode = active_riders[id] as RiderAINode
		active_riders.erase(id)
		if is_instance_valid(node):
			node.queue_free()


func _build_target_for(rider_node: RiderAINode) -> RiderPerception.Target:
	if viewer == null or not is_instance_valid(viewer):
		return RiderPerception.Target.new()
	var player_pos: Vector3 = viewer.global_position
	var crouched: bool = false
	var veg_conceal: float = 0.0
	if viewer is PlayerController:
		var pc: PlayerController = viewer as PlayerController
		crouched = pc.crouched
		veg_conceal = pc.get_vegetation_concealment()
	var weather_conceal: float = weather.get_concealment_bonus() if weather != null else 0.0
	var total_conceal: float = clampf(veg_conceal + weather_conceal, 0.0, 1.0)
	var road_dist: float = road_distance_m(Vector2(player_pos.x, player_pos.z), region_data)
	var los: bool = has_line_of_sight(rider_node.global_position, player_pos)
	return RiderPerception.Target.make(player_pos, crouched, total_conceal, road_dist, los)


func _is_night() -> bool:
	return GameDate.is_night(WorldClock.now)


func _update_feedback() -> void:
	if viewer == null or not is_instance_valid(viewer) or active_riders.is_empty():
		if audio != null:
			audio.clear_rider()
		if hud != null:
			hud.set_eye_state(RiderPerception.EyeState.HIDDEN)
		return

	var nearest_dist: float = INF
	var nearest_rider: RiderAINode = null
	var highest_eye: RiderPerception.EyeState = RiderPerception.EyeState.HIDDEN

	for id: String in active_riders:
		var node: RiderAINode = active_riders[id] as RiderAINode
		if not is_instance_valid(node):
			continue
		var d: float = node.ai.last_result.distance
		if d < nearest_dist:
			nearest_dist = d
			nearest_rider = node
		if node.ai.last_result.eye > highest_eye:
			highest_eye = node.ai.last_result.eye

	if nearest_rider != null:
		if audio != null:
			audio.report_rider(nearest_dist, nearest_rider.ai.state, highest_eye)
		if hud != null:
			hud.set_eye_state(highest_eye)
	else:
		if audio != null:
			audio.clear_rider()
		if hud != null:
			hud.set_eye_state(RiderPerception.EyeState.HIDDEN)


func _on_interrogation_started(_beats: Array[Dictionary], rider_node: RiderAINode) -> void:
	rider_node.finish_interrogation()


static func road_distance_m(pos_2d: Vector2, region: Dictionary) -> float:
	var roads: Array = region.get("roads", []) as Array
	if roads.is_empty():
		return 0.0
	var min_dist: float = INF
	for r: Variant in roads:
		if r is Dictionary:
			var pts: Array = (r as Dictionary).get("points", []) as Array
			for i in range(pts.size() - 1):
				var a := Vector2(float(pts[i][0]), float(pts[i][1]))
				var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(pos_2d, a, b)
				var d: float = pos_2d.distance_to(closest)
				if d < min_dist:
					min_dist = d
	return min_dist if min_dist != INF else 0.0


func has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var vp := get_viewport()
	if vp == null:
		return true
	var w3d: World3D = vp.find_world_3d()
	if w3d == null or w3d.direct_space_state == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(from_pos + Vector3.UP * 1.5, to_pos + Vector3.UP * 1.0)
	query.collision_mask = 1 # Static geometry
	var hit: Dictionary = w3d.direct_space_state.intersect_ray(query)
	return hit.is_empty()
