class_name Survival
extends RefCounted
## Hunger and fatigue. Both live in the player entity's data (WorldState) so they are saved with
## the world; this object only applies the rules. Time passes through WorldClock, so sleeping
## and waiting fire the same minute/hour hooks as anything else.

const DATA_KEY: String = "survival"
const KIND_FAINT: String = "fainted"
const CAUSE_EXHAUSTION: String = "exhaustion"
const CAUSE_HUNGER: String = "hunger"
const RACE_HOBBIT: String = "hobbit"
const NO_MEAL: int = -1

var _state: Node
var _clock: Node
var _sleeping: bool = false
var _sleep_place: String = "bed"
# advance() inside a faint re-enters the minute handler; this stops a second faint stacking on it.
var _fainting: bool = false


func _init(state: Node = null, clock: Node = null) -> void:
	_state = state if state != null else WorldState
	_clock = clock if clock != null else WorldClock
	_clock.minute_passed.connect(_on_minute)


func detach() -> void:
	if _clock.minute_passed.is_connected(_on_minute):
		_clock.minute_passed.disconnect(_on_minute)


# --- state -----------------------------------------------------------------

func hunger() -> float:
	return float(_store().get("hunger", Tuning.num("survival.hunger.start")))


func fatigue() -> float:
	return float(_store().get("fatigue", 0.0))


func is_hobbit() -> bool:
	var data: Dictionary = _player_data()
	return str(data.get("race", "")).to_lower() == RACE_HOBBIT


func is_sleeping() -> bool:
	return _sleeping


## Hobbits get a mood bonus while meals keep coming on schedule ("six meals a day").
func has_mood_bonus() -> bool:
	if not is_hobbit():
		return false
	var last: int = int(_store().get("last_meal", NO_MEAL))
	if last == NO_MEAL:
		return false
	return _clock.now - last <= Tuning.integer("survival.hunger.hobbit_meal_interval_minutes")


# --- effects ---------------------------------------------------------------

func stamina_regen_multiplier() -> float:
	var slow: bool = hunger() <= Tuning.num("survival.hunger.slow_regen_below") \
			or fatigue() >= Tuning.num("survival.fatigue.slow_regen_above")
	return Tuning.num("survival.effects.slow_regen_multiplier") if slow else 1.0


func move_speed_multiplier() -> float:
	var slow: bool = hunger() <= Tuning.num("survival.hunger.slow_move_below") \
			or fatigue() >= Tuning.num("survival.fatigue.slow_move_above")
	return Tuning.num("survival.effects.slow_move_multiplier") if slow else 1.0


# --- actions ---------------------------------------------------------------

## Called by the controller with the real minutes spent running this frame.
func add_exertion(running_minutes: float) -> void:
	_set_fatigue(fatigue() + running_minutes * Tuning.num("survival.fatigue.per_running_minute"))
	_check_faint()


## Eats one unit of a food/drink item from the player's inventory. Restore scales with the item's
## value so new foods need no extra data.
func eat(item_id: String) -> bool:
	var kind: String = ItemDB.kind_of(item_id)
	var per_value: Dictionary = Tuning.dict("survival.hunger.restore_per_value")
	if not per_value.has(kind):
		return false
	if not _state.transfer_item(item_id, WorldState.PLAYER_ID, ""):
		return false
	_set_hunger(hunger() + float(per_value[kind]) * ItemDB.value_of(item_id))
	_store()["last_meal"] = _clock.now
	return true


## Sleeps through WorldClock.advance. Recovery runs in the minute handler so interruptions by
## timeline events during the advance still see a consistent (partly rested) player.
func sleep(hours: float, place: String = "bed") -> void:
	if hours <= 0.0 or _sleeping:
		return
	_sleeping = true
	_sleep_place = place
	_clock.advance(int(hours * _clock.MINUTES_PER_HOUR))
	_sleeping = false


# --- internals -------------------------------------------------------------

func _on_minute(_now: int) -> void:
	var per_minute: float = Tuning.num("survival.hunger.per_day") / _clock.MINUTES_PER_DAY
	if is_hobbit():
		per_minute *= Tuning.num("survival.hunger.hobbit_multiplier")
	if _sleeping:
		var recovery: Dictionary = Tuning.dict("survival.fatigue.sleep_recovery_per_hour")
		var per_hour: float = float(recovery.get(_sleep_place, recovery.get("camp", 0.0)))
		_set_fatigue(fatigue() - per_hour / _clock.MINUTES_PER_HOUR)
		_set_hunger(hunger() - per_minute * Tuning.num("survival.hunger.sleep_multiplier"))
		return
	_set_fatigue(fatigue() + Tuning.num("survival.fatigue.per_awake_hour") / _clock.MINUTES_PER_HOUR)
	_set_hunger(hunger() - per_minute)
	_check_faint()


func _check_faint() -> void:
	if _fainting or _sleeping:
		return
	if fatigue() >= Tuning.num("survival.fatigue.faint_at"):
		_faint(CAUSE_EXHAUSTION)
	elif hunger() <= Tuning.num("survival.hunger.faint_at"):
		_faint(CAUSE_HUNGER)


## Soft failure: lose time, wake partly recovered (someone found and fed you), never die.
func _faint(cause: String) -> void:
	_fainting = true
	var minutes: int = Tuning.integer("survival.fatigue.faint_minutes")
	_set_fatigue(minf(fatigue(), Tuning.num("survival.fatigue.faint_restore_to")))
	_set_hunger(maxf(hunger(), Tuning.num("survival.hunger.faint_restore")))
	EventBus.player_failed.emit(KIND_FAINT, {"cause": cause, "minutes": minutes})
	_clock.advance(minutes)
	_fainting = false


func _set_hunger(v: float) -> void:
	_store()["hunger"] = clampf(v, 0.0, Tuning.num("survival.hunger.max"))


func _set_fatigue(v: float) -> void:
	_store()["fatigue"] = clampf(v, 0.0, Tuning.num("survival.fatigue.max"))


func _player_data() -> Dictionary:
	if not _state.has_entity(WorldState.PLAYER_ID):
		_state.spawn_entity(WorldState.PLAYER_ID, "player")
	return (_state.entities[WorldState.PLAYER_ID] as Dictionary)["data"]


func _store() -> Dictionary:
	var data: Dictionary = _player_data()
	if not data.has(DATA_KEY):
		data[DATA_KEY] = {}
	return data[DATA_KEY]
