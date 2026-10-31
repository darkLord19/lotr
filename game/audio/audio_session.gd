class_name AudioSession
extends Node
## Owns Ambience and MusicDirector. Periodically classifies the viewer's position against the
## region map and feeds location/area/settlement to Ambience and MusicDirector, keeping weather
## and threat levels in sync.

const CLASSIFY_INTERVAL: float = 0.5
const REGION_PATH: String = "res://content/regions/eriador_west.json"

var viewer: Node3D
var weather: WeatherDayNight
var region_data: Dictionary = {}

var ambience: Ambience
var music_director: MusicDirector

var _time_since_classify: float = 0.0
var _current_classification: Dictionary = {}


func _ready() -> void:
	if region_data.is_empty():
		region_data = load_default_region()
	if ambience == null:
		ambience = Ambience.new()
		ambience.name = "Ambience"
		add_child(ambience)
	if music_director == null:
		music_director = MusicDirector.new()
		music_director.name = "MusicDirector"
		add_child(music_director)
	update_classification()


func _process(delta: float) -> void:
	_time_since_classify += delta
	if _time_since_classify >= CLASSIFY_INTERVAL:
		_time_since_classify = 0.0
		update_classification()
	if music_director != null and ambience != null and music_director.decision != null:
		ambience.set_threat(music_director.decision.threat)


func update_classification() -> Dictionary:
	if viewer == null:
		return _current_classification
	var pos: Vector3 = viewer.global_position
	return classify_and_apply(pos)


func classify_and_apply(pos: Vector3) -> Dictionary:
	var res: Dictionary = classify(pos, region_data)
	_current_classification = res
	if ambience != null:
		ambience.set_location(res.location)
	if music_director != null:
		music_director.set_place(res.region, res.settlement, res.area, res.in_inn)
	if weather != null and weather.current != null:
		if ambience != null:
			ambience.set_weather(weather.current.state, weather.current.rain_intensity)
		if music_director != null:
			music_director.set_weather(weather.current.state)
	return res


func report_rider(distance_m: float, state: int, eye: int) -> void:
	if music_director != null:
		music_director.report_rider(distance_m, state, eye)
		var cfg: Dictionary = music_director.logic.cfg if music_director.logic != null else {}
		var threat: int = MusicLogic.threat_level(music_director.inputs, cfg)
		if ambience != null:
			ambience.set_threat(threat)


func clear_rider() -> void:
	if music_director != null:
		music_director.clear_rider()
	if ambience != null:
		ambience.set_threat(0)


# --- static helpers -------------------------------------------------------------

static func load_default_region() -> Dictionary:
	if not FileAccess.file_exists(REGION_PATH):
		return {}
	var file := FileAccess.open(REGION_PATH, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		return json.data as Dictionary
	return {}


static func classify(pos: Variant, region: Dictionary) -> Dictionary:
	var region_id: StringName = StringName(str(region.get("id", "eriador_west")))
	var p2: Vector2
	if pos is Vector3:
		p2 = Vector2(pos.x, pos.z)
	elif pos is Vector2:
		p2 = pos
	else:
		p2 = Vector2.ZERO

	# 1. Inn POI (within ~10 m)
	var pois: Array = region.get("pois", []) as Array
	for p in pois:
		if p is Dictionary and str(p.get("kind", "")) == "inn":
			var p_pos: Array = p.get("pos", [0, 0, 0]) as Array
			var inn_pos := Vector2(float(p_pos[0]), float(p_pos[2]))
			if p2.distance_to(inn_pos) <= 10.0:
				return {
					"location": &"inn_interior",
					"region": region_id,
					"settlement": StringName(str(p.get("settlement", ""))),
					"area": &"",
					"in_inn": true
				}

	# 2. Inside a settlement circle
	var settlements: Array = region.get("settlements", []) as Array
	for s in settlements:
		if s is Dictionary:
			var c: Array = s.get("center", [0, 0]) as Array
			var center := Vector2(float(c[0]), float(c[1]))
			var radius: float = float(s.get("radius", 0.0))
			if p2.distance_to(center) <= radius:
				return {
					"location": &"settlement",
					"region": region_id,
					"settlement": StringName(str(s.get("id", ""))),
					"area": &"",
					"in_inn": false
				}

	# 3. Within river width / 2 + 30 m
	var rivers: Array = region.get("rivers", []) as Array
	for r in rivers:
		if r is Dictionary:
			var width: float = float(r.get("width", 10.0))
			var threshold: float = (width * 0.5) + 30.0
			var pts: Array = r.get("points", []) as Array
			for i in range(pts.size() - 1):
				var a := Vector2(float(pts[i][0]), float(pts[i][1]))
				var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p2, a, b)
				if p2.distance_to(closest) <= threshold:
					return {
						"location": &"river",
						"region": region_id,
						"settlement": &"",
						"area": &"",
						"in_inn": false
					}

	# 4. Inside a forest polygon or within ~80 m of it
	var forests: Array = region.get("forests", []) as Array
	for f in forests:
		if f is Dictionary:
			var poly_pts_raw: Array = f.get("polygon", []) as Array
			if poly_pts_raw.size() >= 3:
				var poly := PackedVector2Array()
				for pt in poly_pts_raw:
					poly.append(Vector2(float(pt[0]), float(pt[1])))
				if Geometry2D.is_point_in_polygon(p2, poly):
					return {
						"location": &"forest_edge",
						"region": region_id,
						"settlement": &"",
						"area": StringName(str(f.get("id", ""))),
						"in_inn": false
					}
				var n: int = poly.size()
				for i in range(n):
					var a: Vector2 = poly[i]
					var b: Vector2 = poly[(i + 1) % n]
					var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p2, a, b)
					if p2.distance_to(closest) <= 80.0:
						return {
							"location": &"forest_edge",
							"region": region_id,
							"settlement": &"",
							"area": StringName(str(f.get("id", ""))),
							"in_inn": false
						}

	# 5. Else field
	return {
		"location": &"field",
		"region": region_id,
		"settlement": &"",
		"area": &"",
		"in_inn": false
	}
