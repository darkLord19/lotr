extends Node
# The world clock. Game time is integer minutes since T.A. 3018-01-01 (see GameDate).

signal minute_passed(now: int)
signal hour_passed(now: int)
signal day_passed(now: int)

const MINUTES_PER_HOUR: int = 60
const MINUTES_PER_DAY: int = 1440

var now: int = 0
# Game minutes per real second.
var time_scale: float = 0.5
# &"A" = the world never waits; &"B" = major events wait for the player within a window.
var mode: StringName = &"A"

# A stack (not a bool) so dialogue and menus can each pause independently.
var _pause_reasons: Array[StringName] = []
# Fractional minutes carried between frames so low time scales don't lose time.
var _accum: float = 0.0


func _ready() -> void:
	time_scale = float(Config.get_value("clock.minutes_per_second", 0.5))
	var start: int = GameDate.parse(str(Config.get_value("clock.start_date", "3018-09-22T08:00")))
	if start != GameDate.INVALID:
		now = start


func _process(delta: float) -> void:
	if is_paused():
		return
	_accum += delta * time_scale
	var whole: int = int(_accum)
	if whole > 0:
		_accum -= whole
		advance(whole)


func pause(reason: StringName) -> void:
	_pause_reasons.append(reason)


# Removes one instance of the reason; unknown reasons are ignored.
func resume(reason: StringName) -> void:
	var idx: int = _pause_reasons.find(reason)
	if idx >= 0:
		_pause_reasons.remove_at(idx)


func is_paused() -> bool:
	return not _pause_reasons.is_empty()


func pause_reasons() -> Array[StringName]:
	return _pause_reasons.duplicate()


# Steps minute by minute so every intermediate signal fires in order; sleeping or
# waiting must not skip timeline events or hour/day hooks.
func advance(minutes: int) -> void:
	for i in range(maxi(minutes, 0)):
		now += 1
		minute_passed.emit(now)
		if now % MINUTES_PER_HOUR == 0:
			hour_passed.emit(now)
			if now % MINUTES_PER_DAY == 0:
				day_passed.emit(now)


func set_mode(m: StringName) -> void:
	if m == &"A" or m == &"B":
		mode = m
	else:
		push_warning("WorldClock: unknown mode %s" % m)


func serialise() -> Dictionary:
	return {"now": now, "mode": String(mode)}


func deserialise(d: Dictionary) -> void:
	now = int(d.get("now", now))
	set_mode(StringName(str(d.get("mode", "A"))))
	_accum = 0.0
