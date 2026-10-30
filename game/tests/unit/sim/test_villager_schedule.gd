extends GutTest

const TPL: Dictionary = {"work_start": 480, "work_end": 1020, "inn_start": 1080, "inn_end": 1260}
const V: Dictionary = {"id": "hob", "settlement": "bywater", "home": "bywater", "work": "mill", "inn": "green_dragon"}

var g: RoadGraph


func before_each() -> void:
	g = RoadGraph.new()
	g.load_region()


# Jitter shifts every boundary by a villager-specific amount; shift the probe by the same.
func _stage(minute_of_day: int, v: Dictionary = V) -> int:
	var j: int = VillagerSchedule.jitter_minutes(str(v["id"]), int(Config.get_value("sim.villager_jitter_minutes", 30)))
	return VillagerSchedule.state_at(v, TPL, minute_of_day + j, g)["stage"]


func test_daily_routine_home_work_inn_home() -> void:
	assert_eq(_stage(3 * 60), VillagerSchedule.Stage.HOME)
	assert_eq(_stage(12 * 60), VillagerSchedule.Stage.WORK)
	assert_eq(_stage(17 * 60 + 45), VillagerSchedule.Stage.HOME)  # gap between work and inn
	assert_eq(_stage(19 * 60 + 30), VillagerSchedule.Stage.INN)
	assert_eq(_stage(23 * 60 + 30), VillagerSchedule.Stage.HOME)


func test_positions_are_the_stage_pois() -> void:
	var j: int = VillagerSchedule.jitter_minutes("hob", int(Config.get_value("sim.villager_jitter_minutes", 30)))
	assert_eq(VillagerSchedule.state_at(V, TPL, 12 * 60 + j, g)["poi"], "mill")
	assert_eq(VillagerSchedule.state_at(V, TPL, 12 * 60 + j, g)["pos"], g.poi_pos("mill"))
	assert_eq(VillagerSchedule.state_at(V, TPL, 19 * 60 + 30 + j, g)["poi"], "green_dragon")


func test_transit_interpolates_between_places() -> void:
	var j: int = VillagerSchedule.jitter_minutes("hob", int(Config.get_value("sim.villager_jitter_minutes", 30)))
	var s: Dictionary = VillagerSchedule.state_at(V, TPL, 480 + j + 5, g)
	assert_true(s["moving"])
	var pos: Vector3 = s["pos"]
	var a: Vector3 = g.poi_pos("bywater")
	var b: Vector3 = g.poi_pos("mill")
	assert_almost_eq(pos.distance_to(a) + pos.distance_to(b), a.distance_to(b), 0.01)  # on the segment


func test_pure_and_periodic() -> void:
	var day: int = 1440
	var t0: int = GameDate.parse("3018-09-24T14:10")
	assert_eq(VillagerSchedule.state_at(V, TPL, t0, g), VillagerSchedule.state_at(V, TPL, t0, g))
	assert_eq(VillagerSchedule.state_at(V, TPL, t0, g)["poi"], VillagerSchedule.state_at(V, TPL, t0 + 3 * day, g)["poi"])


func test_villager_without_inn_stays_home() -> void:
	var v: Dictionary = {"id": "homebody", "settlement": "bywater", "home": "bywater", "work": "mill", "inn": ""}
	var j: int = VillagerSchedule.jitter_minutes("homebody", int(Config.get_value("sim.villager_jitter_minutes", 30)))
	assert_eq(VillagerSchedule.state_at(v, TPL, 19 * 60 + 30 + j, g)["poi"], "bywater")


func test_jitter_is_deterministic_and_bounded() -> void:
	for id in ["a", "bb", "hob", "rose_cotton"]:
		var j: int = VillagerSchedule.jitter_minutes(id, 30)
		assert_between(j, -30, 30)
		assert_eq(j, VillagerSchedule.jitter_minutes(id, 30))
	assert_eq(VillagerSchedule.jitter_minutes("x", 0), 0)


func test_only_settlements_near_the_player_are_scheduled() -> void:
	var vs: Array = [V, {"id": "bree_guy", "settlement": "bree", "home": "prancing_pony", "work": "", "inn": ""}]
	var near_bywater: Dictionary = VillagerSchedule.positions_near(vs, g.poi_pos("bywater"), 12 * 60, g)
	assert_true(near_bywater.has("hob"))
	assert_false(near_bywater.has("bree_guy"))
	var near_bree: Dictionary = VillagerSchedule.positions_near(vs, g.poi_pos("prancing_pony"), 12 * 60, g)
	assert_true(near_bree.has("bree_guy"))
	assert_false(near_bree.has("hob"))
	assert_true(VillagerSchedule.positions_near(vs, g.poi_pos("three_farthing_stone") + Vector3(0, 0, 5000), 0, g).is_empty())


func test_template_lookup_falls_back_to_default() -> void:
	assert_true(VillagerSchedule.template_for("bree").has("work_start"))
	assert_true(VillagerSchedule.template_for("no_such_faction").has("inn_end"))
