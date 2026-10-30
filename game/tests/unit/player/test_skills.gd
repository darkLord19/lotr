extends GutTest

const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")

var ws: Node
var skills: Skills


func before_each() -> void:
	ws = autofree(WorldStateScript.new())
	skills = Skills.new(ws)
	watch_signals(EventBus)


func test_thresholds_unlock_tiers() -> void:
	var ts: Array = Tuning.list("skills.thresholds")
	assert_eq(skills.tier("woodcraft"), 0)
	skills.add_xp("woodcraft", float(ts[0]) - 1.0)
	assert_eq(skills.tier("woodcraft"), 0)
	assert_eq(skills.add_xp("woodcraft", 1.0), 1)
	assert_eq(skills.tier("woodcraft"), 1)
	assert_signal_emitted_with_parameters(EventBus, "skill_unlocked", ["woodcraft", 1])
	skills.add_xp("woodcraft", 1000.0)
	assert_eq(skills.tier("woodcraft"), ts.size())
	assert_eq(skills.xp("woodcraft"), Tuning.num("skills.xp_max"), "xp is capped")


func test_unknown_skill_and_nonpositive_ignored() -> void:
	assert_eq(skills.add_xp("juggling", 50.0), 0)
	assert_eq(skills.add_xp("stealth", -5.0), 0)
	assert_eq(skills.xp("stealth"), 0.0)


func test_record_action_awards_configured_xp() -> void:
	assert_true(skills.record_action("forage"))
	assert_almost_eq(skills.xp("woodcraft"), float(Tuning.dict("skills.actions")["forage"]["xp"]), 0.001)
	assert_false(skills.record_action("nonsense"))


func test_effects_merge() -> void:
	assert_eq(skills.effect("forage_spot_range_multiplier"), 1.0)
	assert_eq(skills.effect("forage_yield_bonus"), 0.0)
	skills.add_xp("woodcraft", 30.0)
	assert_eq(skills.effect("forage_spot_range_multiplier"), 2.0, "woodcraft 30 spots mushrooms from twice as far")
	skills.add_xp("woodcraft", 60.0)
	assert_eq(skills.effect("forage_yield_bonus"), 3.0, "bonuses from tiers 2 and 3 add")


func test_prompt_lines_only_for_trained_skills_without_numbers() -> void:
	assert_eq(skills.prompt_lines().size(), 0)
	skills.add_xp("persuasion", 35.0)
	var lines: Array[String] = skills.prompt_lines()
	assert_eq(lines.size(), 1)
	assert_true(lines[0].begins_with("Player skill (persuasion):"))
	assert_false("35" in lines[0])
	skills.add_xp("persuasion", 30.0)
	assert_ne(skills.prompt_lines()[0], lines[0], "line follows the highest tier")


func test_xp_persists_in_world_state_roundtrip() -> void:
	skills.add_xp("lore", 40.0)
	var copy: Node = autofree(WorldStateScript.new())
	copy.deserialise(JSON.parse_string(JSON.stringify(ws.serialise())))
	assert_eq(Skills.new(copy).tier("lore"), 1)
