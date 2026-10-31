extends GutTest

const NOON: float = 12.0

var _region: Dictionary = {}


func before_all() -> void:
	_region = AudioSession.load_default_region()


func test_region_loaded() -> void:
	assert_gt(_region.size(), 0)
	assert_eq(_region.get("id"), "eriador_west")


func test_classify_inn_interior() -> void:
	# Prancing Pony is at [7420, 0, 2340] in Bree
	var pos := Vector3(7420, 0, 2340)
	var res: Dictionary = AudioSession.classify(pos, _region)
	assert_eq(res.location, &"inn_interior")
	assert_eq(res.in_inn, true)
	assert_eq(res.settlement, &"bree")
	assert_eq(res.region, &"eriador_west")

	# Slightly offset (within 10 m)
	var res_offset: Dictionary = AudioSession.classify(Vector3(7425, 0, 2344), _region)
	assert_eq(res_offset.location, &"inn_interior")
	assert_eq(res_offset.in_inn, true)


func test_classify_settlement() -> void:
	# Hobbiton center is [950, 2200], radius 300, away from Bag End / inn
	var pos := Vector3(950, 0, 2200)
	var res: Dictionary = AudioSession.classify(pos, _region)
	assert_eq(res.location, &"settlement")
	assert_eq(res.settlement, &"hobbiton")
	assert_eq(res.in_inn, false)


func test_classify_river() -> void:
	# Brandywine point at [5450, 0], width 50 (threshold = 25 + 30 = 55m).
	# At z=200, the river centerline is at x=5390. Test at x=5400 (distance ~10m).
	var pos := Vector3(5400, 0, 200)
	var res: Dictionary = AudioSession.classify(pos, _region)
	assert_eq(res.location, &"river")
	assert_eq(res.in_inn, false)


func test_classify_forest() -> void:
	# Woody End polygon contains [2800, 3100]
	var pos := Vector3(2800, 0, 3100)
	var res: Dictionary = AudioSession.classify(pos, _region)
	assert_eq(res.location, &"forest_edge")
	assert_eq(res.area, &"woody_end")
	assert_eq(res.in_inn, false)

	# 40 m outside Woody End boundary is within the 80 m buffer
	var edge_pos := Vector3(2260, 0, 3250)
	var res_edge: Dictionary = AudioSession.classify(edge_pos, _region)
	assert_eq(res_edge.location, &"forest_edge")
	assert_eq(res_edge.area, &"woody_end")


func test_classify_field() -> void:
	# Open field north of East Road, far from river and forest
	var pos := Vector3(3800, 0, 500)
	var res: Dictionary = AudioSession.classify(pos, _region)
	assert_eq(res.location, &"field")
	assert_eq(res.settlement, &"")
	assert_eq(res.area, &"")
	assert_eq(res.in_inn, false)


func test_audio_session_follows_moving_viewer() -> void:
	var session: AudioSession = AudioSession.new()
	add_child_autofree(session)

	var viewer := Node3D.new()
	add_child_autofree(viewer)
	session.viewer = viewer

	# Start in Hobbiton
	viewer.global_position = Vector3(950, 0, 2200)
	session.update_classification()
	assert_eq(session.ambience.inputs.location, &"settlement")
	assert_eq(session.music_director.inputs.settlement, &"hobbiton")
	assert_eq(session.music_director.inputs.in_inn, false)

	# Move to Green Dragon inn in Bywater [1700, 0, 2390]
	viewer.global_position = Vector3(1700, 0, 2390)
	session.update_classification()
	assert_eq(session.ambience.inputs.location, &"inn_interior")
	assert_eq(session.music_director.inputs.in_inn, true)
	assert_eq(session.music_director.inputs.settlement, &"bywater")

	# Move to Woody End
	viewer.global_position = Vector3(2800, 0, 3100)
	session.update_classification()
	assert_eq(session.ambience.inputs.location, &"forest_edge")
	assert_eq(session.music_director.inputs.area, &"woody_end")


func test_audio_session_weather_and_rider_sync() -> void:
	var session: AudioSession = AudioSession.new()
	add_child_autofree(session)

	var weather := WeatherDayNight.new()
	add_child_autofree(weather)
	session.weather = weather

	# Force weather state
	weather.force(&"light_rain")
	weather.apply(WorldClock.now)
	var viewer := Node3D.new()
	add_child_autofree(viewer)
	session.viewer = viewer
	viewer.global_position = Vector3(3800, 0, 500)

	session.update_classification()
	assert_eq(session.ambience.inputs.weather_state, &"light_rain")
	assert_eq(session.music_director.inputs.weather_state, &"light_rain")

	# Rider reporting
	session.report_rider(30.0, RiderAI.State.APPROACH, RiderPerception.EyeState.SEEN)
	assert_gt(session.ambience.inputs.threat, 0)
	assert_eq(session.music_director.inputs.rider_distance_m, 30.0)

	session.clear_rider()
	assert_eq(session.ambience.inputs.threat, 0)
	assert_eq(session.music_director.inputs.rider_distance_m, INF)
