class_name GameDate
extends RefCounted
# Game time is integer minutes since T.A. 3018-01-01 00:00. Dates use the
# Gregorian-equivalent calendar (Appendix B lines up with it); the Shire Reckoning
# is display-only and driven by content/calendar.json.

const EPOCH_YEAR: int = 3018
const MINUTES_PER_DAY: int = 1440
const MIN_YEAR: int = 3018
const MAX_YEAR: int = 3021
# parse() returns this for bad input; never a valid minute count.
const INVALID: int = -9223372036854775808
const CALENDAR_PATH: String = "res://content/calendar.json"
const NIGHT_START_HOUR: int = 21
const NIGHT_END_HOUR: int = 5

# Loaded lazily so the class works before/without content on disk.
static var _calendar: Dictionary = {}
static var _calendar_path: String = CALENDAR_PATH


# Tests point this at a fixture; pass "" to restore the default.
static func use_calendar_file(path: String) -> void:
	_calendar_path = path if path != "" else CALENDAR_PATH
	_calendar = {}


static func _get_calendar() -> Dictionary:
	if _calendar.is_empty() and FileAccess.file_exists(_calendar_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_calendar_path))
		if parsed is Dictionary:
			_calendar = parsed
	return _calendar


# "3018-09-29" or "3018-09-29T20:00" -> minutes. Returns INVALID on bad input.
static func parse(s: String) -> int:
	var parts: PackedStringArray = s.strip_edges().split("T")
	if parts.size() > 2:
		return INVALID
	var d: PackedStringArray = parts[0].split("-")
	if d.size() != 3 or not (d[0].is_valid_int() and d[1].is_valid_int() and d[2].is_valid_int()):
		return INVALID
	var y: int = d[0].to_int()
	var mo: int = d[1].to_int()
	var day: int = d[2].to_int()
	if mo < 1 or mo > 12 or day < 1 or day > _days_in_month(y, mo):
		return INVALID
	var hour: int = 0
	var minute: int = 0
	if parts.size() == 2:
		var t: PackedStringArray = parts[1].split(":")
		if t.size() != 2 or not (t[0].is_valid_int() and t[1].is_valid_int()):
			return INVALID
		hour = t[0].to_int()
		minute = t[1].to_int()
		if hour < 0 or hour > 23 or minute < 0 or minute > 59:
			return INVALID
	var days: int = _days_from_civil(y, mo, day) - _days_from_civil(EPOCH_YEAR, 1, 1)
	return days * MINUTES_PER_DAY + hour * 60 + minute


static func format_iso(m: int) -> String:
	var c: Dictionary = _civil(m)
	return "%04d-%02d-%02dT%02d:%02d" % [c["y"], c["m"], c["d"], hour_of(m), minute_of(m)]


# e.g. "Halimath 22, S.R. 1418"; intercalary days show just their name.
static func format_shire(m: int) -> String:
	var cal: Dictionary = _get_calendar()
	if cal.is_empty():
		return format_iso(m)
	var c: Dictionary = _civil(m)
	var y: int = c["y"]
	var doy0: int = _days_from_civil(y, c["m"], c["d"]) - _days_from_civil(y, 1, 1)
	var sr_year: int = y + int(cal["sr_year_offset"])
	var leap: bool = _is_leap(y)
	if leap and c["m"] == 2 and c["d"] == 29:
		return "%s, S.R. %d" % [cal["leap_day_name"], sr_year]
	if leap and (c["m"] > 2):
		doy0 -= 1
	var index: int = doy0 + int(cal["shire_index_shift"])
	if index >= int(cal["year_rollover_index"]):
		index -= int(cal["days_in_year"])
		sr_year += 1
	for p: Dictionary in cal["periods"]:
		var first: int = int(p["first_index"])
		var length: int = int(p["length"])
		if index >= first and index < first + length:
			if bool(p["intercalary"]) or length == 1:
				return "%s, S.R. %d" % [p["name"], sr_year]
			return "%s %d, S.R. %d" % [p["name"], index - first + 1, sr_year]
	return format_iso(m)


# Floor division so negative minutes (dates before the epoch) still behave.
static func day_of(m: int) -> int:
	return floori(float(m) / MINUTES_PER_DAY)


static func hour_of(m: int) -> int:
	return posmod(m, MINUTES_PER_DAY) / 60


static func minute_of(m: int) -> int:
	return posmod(m, 60)


static func is_night(m: int) -> bool:
	var h: int = hour_of(m)
	return h >= NIGHT_START_HOUR or h < NIGHT_END_HOUR


# --- Gregorian helpers (Hinnant's days_from_civil / civil_from_days) --------

static func _is_leap(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or y % 400 == 0


static func _days_in_month(y: int, mo: int) -> int:
	var table: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	return 29 if (mo == 2 and _is_leap(y)) else table[mo - 1]


static func _days_from_civil(y: int, mo: int, d: int) -> int:
	var yy: int = y - 1 if mo <= 2 else y
	var era: int = floori(float(yy) / 400.0)
	var yoe: int = yy - era * 400
	var mp: int = (mo + 9) % 12
	var doy: int = (153 * mp + 2) / 5 + d - 1
	var doe: int = yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468


static func _civil(m: int) -> Dictionary:
	var z: int = day_of(m) + _days_from_civil(EPOCH_YEAR, 1, 1) + 719468
	var era: int = floori(float(z) / 146097.0)
	var doe: int = z - era * 146097
	var yoe: int = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	var y: int = yoe + era * 400
	var doy: int = doe - (365 * yoe + yoe / 4 - yoe / 100)
	var mp: int = (5 * doy + 2) / 153
	var d: int = doy - (153 * mp + 2) / 5 + 1
	var mo: int = mp + 3 if mp < 10 else mp - 9
	if mo <= 2:
		y += 1
	return {"y": y, "m": mo, "d": d}
