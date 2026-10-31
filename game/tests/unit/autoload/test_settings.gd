extends GutTest

const TEST_PATH: String = "user://test_settings.json"

var saved_path: String
var saved_values: Dictionary
var saved_scale: float
var saved_mode: StringName


func before_each() -> void:
	saved_path = Settings.path
	saved_values = Settings.values.duplicate()
	saved_scale = WorldClock.time_scale
	saved_mode = WorldClock.mode
	Settings.path = TEST_PATH
	DirAccess.remove_absolute(TEST_PATH)
	Settings.load_file()


func after_each() -> void:
	DirAccess.remove_absolute(TEST_PATH)
	Settings.path = saved_path
	Settings.values = saved_values
	WorldClock.time_scale = saved_scale
	WorldClock.set_mode(saved_mode)


func test_defaults_come_from_config() -> void:
	assert_eq(Settings.get_value("time_mode"), "A")
	assert_eq(Settings.get_value("clock_speed"), float(Config.get_value("clock.minutes_per_second")))
	assert_eq(Settings.get_value("quality"), "high")


func test_changes_apply_live() -> void:
	assert_true(Settings.set_value("time_mode", "B"))
	assert_eq(WorldClock.mode, &"B")
	assert_true(Settings.set_value("clock_speed", 4.0))
	assert_eq(WorldClock.time_scale, 4.0)


func test_values_are_validated_and_clamped() -> void:
	assert_false(Settings.set_value("time_mode", "C"))
	assert_false(Settings.set_value("quality", "ludicrous"))
	assert_false(Settings.set_value("nonsense", 1))
	assert_false(Settings.set_value("text_speed", "fast"))
	assert_eq(WorldClock.mode, saved_mode)
	Settings.set_value("mouse_sensitivity", 999.0)
	assert_eq(Settings.mouse_sensitivity(), Settings.range_of("mouse_sensitivity").y)


func test_persists_to_file_and_reloads() -> void:
	Settings.set_value("text_speed", 2.0)
	Settings.set_value("quality", "low")
	Settings.set_value("time_mode", "B")
	Settings.values = {}
	Settings.load_file()
	assert_eq(Settings.text_speed(), 2.0)
	assert_eq(Settings.get_value("quality"), "low")
	assert_eq(Settings.get_value("time_mode"), "B")


func test_bad_file_falls_back_to_defaults() -> void:
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string('{"quality": "nope", "text_speed": "x", "mouse_sensitivity": 2.0}')
	f.close()
	Settings.load_file()
	assert_eq(Settings.get_value("quality"), "high")
	assert_eq(Settings.mouse_sensitivity(), 2.0)
	f = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	Settings.load_file()
	assert_eq(Settings.text_speed(), 1.0)


func test_sync_from_clock_does_not_write_the_file() -> void:
	WorldClock.set_mode(&"B")
	Settings.sync_from_clock()
	assert_eq(Settings.get_value("time_mode"), "B")
	assert_false(FileAccess.file_exists(TEST_PATH))


func test_reset_to_defaults() -> void:
	Settings.set_value("text_speed", 3.0)
	Settings.reset_to_defaults()
	assert_eq(Settings.text_speed(), 1.0)
