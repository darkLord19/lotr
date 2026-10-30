extends GutTest

const FIXTURE_CAL: String = "res://tests/fixtures/calendar_test.json"


func after_each() -> void:
	GameDate.use_calendar_file("")


func test_parse_epoch_and_invalid() -> void:
	assert_eq(GameDate.parse("3018-01-01"), 0)
	assert_eq(GameDate.parse("3018-01-02T01:30"), 1440 + 90)
	for bad in ["", "garbage", "3018-13-01", "3018-02-30", "3018-01-01T25:00", "3018-01-01T10", "3018-1"]:
		assert_eq(GameDate.parse(bad), GameDate.INVALID, bad)


func test_round_trip_20_dates() -> void:
	var dates: Array[String] = [
		"3018-01-01T00:00", "3018-02-28T23:59", "3018-03-01T00:00", "3018-06-15T12:30", "3018-09-22T08:00",
		"3018-09-29T20:00", "3018-10-06T05:05", "3018-12-31T23:59", "3019-01-01T00:00", "3019-03-25T09:00",
		"3019-03-15T18:45", "3019-07-10T07:07", "3019-12-31T00:01", "3020-02-28T10:00", "3020-02-29T10:00",
		"3020-03-01T00:00", "3020-12-31T23:59", "3021-01-01T00:00", "3021-06-30T15:15", "3021-12-31T23:59",
	]
	assert_eq(dates.size(), 20)
	for s in dates:
		var m: int = GameDate.parse(s)
		assert_ne(m, GameDate.INVALID, s)
		assert_eq(GameDate.format_iso(m), s)
	assert_eq(GameDate.parse("3019-01-01") - GameDate.parse("3018-12-31"), 1440)
	assert_eq(GameDate.parse("3021-01-01") - GameDate.parse("3020-01-01"), 366 * 1440)


func test_date_only_is_midnight() -> void:
	assert_eq(GameDate.parse("3018-09-29"), GameDate.parse("3018-09-29T00:00"))


func test_day_hour_night() -> void:
	var m: int = GameDate.parse("3018-01-03T07:15")
	assert_eq(GameDate.day_of(m), 2)
	assert_eq(GameDate.hour_of(m), 7)
	assert_false(GameDate.is_night(GameDate.parse("3018-01-01T12:00")))
	assert_true(GameDate.is_night(GameDate.parse("3018-01-01T21:00")))
	assert_true(GameDate.is_night(GameDate.parse("3018-01-01T04:59")))
	assert_false(GameDate.is_night(GameDate.parse("3018-01-01T05:00")))
	assert_false(GameDate.is_night(GameDate.parse("3018-01-01T20:59")))


func test_format_shire_with_fixture_calendar() -> void:
	GameDate.use_calendar_file(FIXTURE_CAL)
	# Same structure as the real calendar, renamed periods.
	assert_eq(GameDate.format_shire(GameDate.parse("3018-09-22")), "TestMonth9 22, S.R. 1418")
	# Month boundary: 30-day months, so index 30 -> day 30 then next month day 1.
	assert_eq(GameDate.format_shire(GameDate.parse("3018-01-01")), "TestMonth1 1, S.R. 1418")
	assert_eq(GameDate.format_shire(GameDate.parse("3018-12-29")), "TestMonth12 30, S.R. 1418")
	assert_eq(GameDate.format_shire(GameDate.parse("3018-12-30")), "TestYuleB, S.R. 1418")
	assert_eq(GameDate.format_shire(GameDate.parse("3018-12-31")), "TestYuleA, S.R. 1419")
	assert_eq(GameDate.format_shire(GameDate.parse("3020-02-29")), "TestLeapDay, S.R. 1420")


func test_format_shire_real_calendar() -> void:
	GameDate.use_calendar_file("")
	if not FileAccess.file_exists(GameDate.CALENDAR_PATH):
		pending("content/calendar.json not present yet")
		return
	assert_eq(GameDate.format_shire(GameDate.parse("3018-09-22")), "Halimath 22, S.R. 1418")
	assert_eq(GameDate.format_shire(GameDate.parse("3018-09-22T23:59")), "Halimath 22, S.R. 1418")
	assert_eq(GameDate.format_shire(GameDate.parse("3018-09-29")), "Halimath 29, S.R. 1418")
	# Halimath has 30 days; the next day is Winterfilth 1.
	assert_eq(GameDate.format_shire(GameDate.parse("3018-09-30")), "Halimath 30, S.R. 1418")
	assert_eq(GameDate.format_shire(GameDate.parse("3018-10-01")), "Winterfilth 1, S.R. 1418")
	assert_eq(GameDate.format_shire(GameDate.parse("3018-12-31")), "1 Yule, S.R. 1419")
	assert_eq(GameDate.format_shire(GameDate.parse("3019-01-01")), "Afteryule 1, S.R. 1419")
