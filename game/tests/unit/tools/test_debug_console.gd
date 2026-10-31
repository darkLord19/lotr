extends GutTest


func test_parses_every_command() -> void:
	var tp: Dictionary = DebugConsole.parse("tp bag_end")
	assert_true(tp["ok"])
	assert_eq(tp["args"], ["bag_end"])
	assert_eq(DebugConsole.parse("date 3018-09-22T08:00")["args"], ["3018-09-22T08:00"])
	assert_eq(DebugConsole.parse("give bread_loaf")["args"], ["bread_loaf", 1])
	assert_eq(DebugConsole.parse("give bread_loaf 3")["args"], ["bread_loaf", 3])
	assert_eq(DebugConsole.parse("flag quest.done true")["args"], ["quest.done", true])
	assert_eq(DebugConsole.parse("flag count 7")["args"], ["count", 7])
	assert_eq(DebugConsole.parse("flag who Sam")["args"], ["who", "Sam"])
	assert_eq(DebugConsole.parse("mode b")["args"], [&"B"])
	assert_eq(DebugConsole.parse("speed 2.5")["args"], [2.5])


func test_rejects_bad_input() -> void:
	for line: String in ["", "   ", "dance", "tp", "tp a b", "give x 0", "give x two", "mode C", "speed 0", "speed fast", "date nonsense", "flag onlykey"]:
		var r: Dictionary = DebugConsole.parse(line)
		assert_false(r["ok"], "'%s' should be rejected" % line)
		assert_ne(str(r["error"]), "")


func test_tolerates_extra_spaces_and_case() -> void:
	var r: Dictionary = DebugConsole.parse("  TP   bag_end  ")
	assert_true(r["ok"])
	assert_eq(r["cmd"], "tp")


func test_parse_value_types() -> void:
	assert_eq(DebugConsole.parse_value("TRUE"), true)
	assert_eq(DebugConsole.parse_value("false"), false)
	assert_eq(DebugConsole.parse_value("12"), 12)
	assert_eq(DebugConsole.parse_value("1.5"), 1.5)
	assert_eq(DebugConsole.parse_value("abc"), "abc")


func test_run_flag_give_and_unknown_poi() -> void:
	WorldState.reset()
	var console: DebugConsole = autofree(DebugConsole.new())
	assert_string_contains(console.run("flag test.debug true"), "test.debug")
	assert_eq(WorldState.get_flag("test.debug"), true)
	assert_string_contains(console.run("tp nowhere"), "unknown poi")
	assert_string_contains(console.run("give not_an_item"), "unknown item")
	WorldState.reset()
