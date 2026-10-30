extends GutTest

const Eye := RiderPerception.EyeState
const ORIGIN: Vector3 = Vector3.ZERO
# Rider looks down -Z; "ahead" targets have negative z.
const FACING: Vector3 = Vector3(0, 0, -1)


func _eye(target: RiderPerception.Target, night: bool = false) -> Eye:
	return RiderPerception.evaluate(ORIGIN, FACING, target, night).eye


# [name, target pos, crouched, concealment, off_road_m, night, expected]
func test_perception_table() -> void:
	var cases: Array = [
		["open road ahead 30m", Vector3(0, 0, -30), false, 0.0, 0.0, false, Eye.SEEN],
		["open road ahead 45m beyond range", Vector3(0, 0, -45), false, 0.0, 0.0, false, Eye.HIDDEN],
		["behind 10m: not in cone but sniffed", Vector3(0, 0, 10), false, 0.0, 0.0, false, Eye.SNIFFED],
		["behind 20m: neither", Vector3(0, 0, 20), false, 0.0, 0.0, false, Eye.HIDDEN],
		["night halves range: 30m ahead unseen", Vector3(0, 0, -30), false, 0.0, 0.0, true, Eye.HIDDEN],
		["night: 18m ahead still seen", Vector3(0, 0, -18), false, 0.0, 0.0, true, Eye.SEEN],
		["night narrows cone: 40 deg off-axis at 10m unseen by sight", Vector3(sin(deg_to_rad(40.0)) * 10.0, 0, -cos(deg_to_rad(40.0)) * 10.0), false, 0.0, 0.0, true, Eye.SNIFFED],
		["day: same 40 deg off-axis seen", Vector3(sin(deg_to_rad(40.0)) * 10.0, 0, -cos(deg_to_rad(40.0)) * 10.0), false, 0.0, 0.0, false, Eye.SEEN],
		["hedge 0.5 standing: range 20, 25m ahead hidden", Vector3(0, 0, -25), false, 0.5, 0.0, false, Eye.HIDDEN],
		["hedge 0.5 crouched: range 10, 14m ahead hidden", Vector3(0, 0, -14), true, 0.5, 0.0, false, Eye.HIDDEN],
		["crouched in cover 10m: sniff radius 7.5 so only seen if range allows", Vector3(0, 0, 10), true, 0.5, 0.0, false, Eye.HIDDEN],
		["standing in cover 10m behind: sniffed (15m)", Vector3(0, 0, 10), false, 0.5, 0.0, false, Eye.SNIFFED],
		["off road 8m halves sniff: 10m behind hidden", Vector3(0, 0, 10), false, 0.0, 8.0, false, Eye.HIDDEN],
		["off road exactly 6m not halved: 10m behind sniffed", Vector3(0, 0, 10), false, 0.0, 6.0, false, Eye.SNIFFED],
		["crouch without cover gives nothing: 10m behind sniffed", Vector3(0, 0, 10), true, 0.0, 0.0, false, Eye.SNIFFED],
		["full concealment: invisible even close ahead, sniffed at 5m", Vector3(0, 0, -5), true, 1.0, 0.0, false, Eye.SNIFFED],
		["full cover but 8m off-road, 10m away: nothing", Vector3(0, 0, -10), true, 1.0, 8.0, false, Eye.HIDDEN],
	]
	for c: Array in cases:
		var t: RiderPerception.Target = RiderPerception.Target.make(c[1], c[2], c[3], c[4])
		assert_eq(_eye(t, c[5]), c[6], c[0])


func test_no_line_of_sight_blocks_vision_but_not_sniff() -> void:
	var t: RiderPerception.Target = RiderPerception.Target.make(Vector3(0, 0, -10), false, 0.0, 0.0, false)
	assert_eq(_eye(t), Eye.SNIFFED)


func test_sniff_halving_does_not_stack() -> void:
	assert_almost_eq(RiderPerception.sniff_radius(true, 20.0), 7.5, 0.001)
	assert_almost_eq(RiderPerception.sniff_radius(false, 0.0), 15.0, 0.001)


func test_combine_concealment_takes_densest() -> void:
	assert_almost_eq(RiderPerception.combine_concealment([0.3, 0.7, 0.5] as Array[float]), 0.7, 0.001)
	assert_almost_eq(RiderPerception.combine_concealment([] as Array[float]), 0.0, 0.001)
	assert_almost_eq(RiderPerception.combine_concealment([1.7] as Array[float]), 1.0, 0.001)


func test_fear_aura() -> void:
	assert_almost_eq(RiderPerception.fear_move_factor(8.0), 1.0, 0.001)
	assert_almost_eq(RiderPerception.fear_move_factor(20.0), 1.0, 0.001)
	assert_almost_eq(RiderPerception.fear_move_factor(0.0), 0.5, 0.001)
	assert_almost_eq(RiderPerception.fear_move_factor(4.0), 0.75, 0.001)
	assert_almost_eq(RiderPerception.fear_desaturation(0.0), 0.8, 0.001)
	assert_almost_eq(RiderPerception.fear_desaturation(8.0), 0.0, 0.001)
	assert_almost_eq(RiderPerception.fear_heartbeat(2.0), 0.75, 0.001)
