extends GutTest


func test_summary_uniform_frames() -> void:
	var frames := PackedFloat32Array()
	frames.resize(200)
	frames.fill(10.0)
	var s: Dictionary = BenchRunner.summarise(frames)
	assert_almost_eq(float(s["avg_fps"]), 100.0, 0.01)
	assert_almost_eq(float(s["p1_low_fps"]), 100.0, 0.01)
	assert_eq(int(s["frames"]), 200)


func test_one_percent_low_uses_slowest_tail() -> void:
	var frames := PackedFloat32Array()
	for i in 100:
		frames.append(10.0)
	frames[40] = 50.0
	var s: Dictionary = BenchRunner.summarise(frames)
	assert_almost_eq(float(s["p1_low_fps"]), 20.0, 0.01, "slowest 1% of 100 frames is the single 50 ms frame")
	assert_almost_eq(float(s["worst_ms"]), 50.0, 0.01)


func test_empty_run_fails_targets() -> void:
	var s: Dictionary = BenchRunner.summarise(PackedFloat32Array())
	assert_false(BenchRunner.meets_targets(s, {"avg_fps": 60.0, "p1_low_fps": 45.0}))


func test_targets_check_all_three_limits() -> void:
	var targets: Dictionary = {"avg_fps": 60.0, "p1_low_fps": 45.0, "peak_mem_gb": 6.0}
	var good: Dictionary = {"avg_fps": 90.0, "p1_low_fps": 50.0, "peak_mem_gb": 3.0}
	assert_true(BenchRunner.meets_targets(good, targets))
	assert_false(BenchRunner.meets_targets({"avg_fps": 59.0, "p1_low_fps": 50.0, "peak_mem_gb": 3.0}, targets))
	assert_false(BenchRunner.meets_targets({"avg_fps": 90.0, "p1_low_fps": 44.0, "peak_mem_gb": 3.0}, targets))
	assert_false(BenchRunner.meets_targets({"avg_fps": 90.0, "p1_low_fps": 50.0, "peak_mem_gb": 6.5}, targets))
