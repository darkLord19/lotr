extends GutTest

const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")
const WorldClockScript: GDScript = preload("res://autoload/world_clock.gd")

var ws: Node
var clock: Node
var survival: Survival


func before_each() -> void:
	ws = autofree(WorldStateScript.new())
	clock = autofree(WorldClockScript.new())
	clock.now = 0
	ws.spawn_entity("player", "player", "bag_end", "", {"race": "man"})
	survival = Survival.new(ws, clock)
	watch_signals(EventBus)


func after_each() -> void:
	survival.detach()


func test_hunger_over_three_days() -> void:
	# A normal day: awake 16 h (fatigue stays under the faint line), then an 8 h night's sleep.
	var per_day: float = Tuning.num("survival.hunger.per_day")
	var day_fraction: float = 16.0 / 24.0 + 8.0 / 24.0 * Tuning.num("survival.hunger.sleep_multiplier")
	var start: float = survival.hunger()
	for day in 3:
		clock.advance(16 * clock.MINUTES_PER_HOUR)
		survival.sleep(8.0, "bed")
	assert_almost_eq(survival.hunger(), start - 3.0 * per_day * day_fraction, 0.05)
	assert_signal_not_emitted(EventBus, "player_failed")


func test_hunger_awake_for_a_day_matches_rate() -> void:
	# Awake all day also exhausts the player, so use a long-lived tweak-free check on 12 hours.
	var start: float = survival.hunger()
	clock.advance(12 * clock.MINUTES_PER_HOUR)
	assert_almost_eq(survival.hunger(), start - Tuning.num("survival.hunger.per_day") / 2.0, 0.05)


func test_hobbits_hunger_faster() -> void:
	ws.entities["player"]["data"]["race"] = "Hobbit"
	var start: float = survival.hunger()
	clock.advance(clock.MINUTES_PER_DAY / 2)
	var expected: float = Tuning.num("survival.hunger.per_day") * Tuning.num("survival.hunger.hobbit_multiplier") / 2.0
	assert_almost_eq(start - survival.hunger(), expected, 0.05)


func test_eating_restores_and_marks_meal() -> void:
	ws.entities["player"]["data"]["race"] = "hobbit"
	ws.transfer_item("bread_loaf", "", "player", 1)
	survival._set_hunger(10.0)
	assert_false(survival.has_mood_bonus())
	assert_true(survival.eat("bread_loaf"))
	assert_gt(survival.hunger(), 10.0)
	assert_true(survival.has_mood_bonus())
	clock.advance(Tuning.integer("survival.hunger.hobbit_meal_interval_minutes") + 1)
	assert_false(survival.has_mood_bonus(), "meal is overdue")
	assert_false(survival.eat("bread_loaf"), "none left")
	assert_false(survival.eat("crickhollow_key"), "not food")


func test_sleep_advances_clock_and_resets_fatigue() -> void:
	survival._set_fatigue(80.0)
	var before: int = clock.now
	survival.sleep(8.0, "bed")
	assert_eq(clock.now - before, 8 * clock.MINUTES_PER_HOUR)
	assert_eq(survival.fatigue(), 0.0)
	assert_false(survival.is_sleeping())


func test_camp_sleep_recovers_less_than_bed() -> void:
	survival._set_fatigue(80.0)
	survival.sleep(4.0, "camp")
	var camp: float = survival.fatigue()
	survival._set_fatigue(80.0)
	survival.sleep(4.0, "bed")
	assert_gt(camp, survival.fatigue())


func test_awake_fatigue_rises_and_running_adds() -> void:
	clock.advance(clock.MINUTES_PER_HOUR)
	assert_almost_eq(survival.fatigue(), Tuning.num("survival.fatigue.per_awake_hour"), 0.01)
	var f: float = survival.fatigue()
	survival.add_exertion(10.0)
	assert_almost_eq(survival.fatigue() - f, 10.0 * Tuning.num("survival.fatigue.per_running_minute"), 0.01)


func test_threshold_effects_tier() -> void:
	assert_eq(survival.move_speed_multiplier(), 1.0)
	assert_eq(survival.stamina_regen_multiplier(), 1.0)
	survival._set_fatigue(Tuning.num("survival.fatigue.slow_regen_above") + 1.0)
	assert_lt(survival.stamina_regen_multiplier(), 1.0)
	assert_eq(survival.move_speed_multiplier(), 1.0, "regen slows before movement")
	survival._set_fatigue(Tuning.num("survival.fatigue.slow_move_above") + 1.0)
	assert_lt(survival.move_speed_multiplier(), 1.0)
	survival._set_fatigue(0.0)
	survival._set_hunger(Tuning.num("survival.hunger.slow_move_below"))
	assert_lt(survival.move_speed_multiplier(), 1.0)


func test_exhaustion_faints_softly() -> void:
	survival._set_fatigue(Tuning.num("survival.fatigue.faint_at") - 0.01)
	var before: int = clock.now
	clock.advance(1)
	assert_signal_emit_count(EventBus, "player_failed", 1)
	var params: Array = get_signal_parameters(EventBus, "player_failed")
	assert_eq(params[0], Survival.KIND_FAINT)
	assert_eq((params[1] as Dictionary)["cause"], Survival.CAUSE_EXHAUSTION)
	assert_gte(clock.now - before, Tuning.integer("survival.fatigue.faint_minutes"))
	assert_lt(survival.fatigue(), Tuning.num("survival.fatigue.faint_at"))


func test_starvation_faints_once_and_recovers_hunger() -> void:
	survival._set_hunger(0.01)
	clock.advance(1)
	assert_signal_emit_count(EventBus, "player_failed", 1)
	assert_gte(survival.hunger(), 0.0)
	assert_gt(survival.hunger(), 0.0)


func test_state_lives_in_world_state() -> void:
	survival._set_hunger(42.0)
	var second := Survival.new(ws, clock)
	assert_eq(second.hunger(), 42.0)
	second.detach()
