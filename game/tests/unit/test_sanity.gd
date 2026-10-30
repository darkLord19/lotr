extends GutTest


func test_sanity() -> void:
	assert_eq(1 + 1, 2)


func test_config_loads() -> void:
	assert_eq(Config.get_value("clock.minutes_per_second"), 0.5)
	assert_eq(Config.get_value("nope.nothing", "dflt"), "dflt")
