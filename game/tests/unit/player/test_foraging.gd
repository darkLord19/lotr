extends GutTest

const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")
const WorldClockScript: GDScript = preload("res://autoload/world_clock.gd")

var ws: Node
var clock: Node
var inv: Inventory
var skills: Skills
var factions: Factions
var forage: Foraging


func before_each() -> void:
	ws = autofree(WorldStateScript.new())
	clock = autofree(WorldClockScript.new())
	clock.now = 0
	inv = Inventory.new("player", ws)
	skills = Skills.new(ws)
	factions = Factions.new(ws)
	var nodes: Array = [
		{"id": "m1", "item": "mushrooms", "pos": [0, 0, 0], "yield": 2},
		{"id": "m2", "item": "mushrooms", "pos": [100, 0, 0], "yield": 2, "zone": "maggots_fields"},
	]
	forage = Foraging.new(nodes, inv, skills, factions, ws, clock)
	forage.rng.seed = 7


func test_forage_gives_item_and_xp_then_regrows_in_window() -> void:
	var r: Dictionary = forage.forage("m1")
	assert_true(r["ok"])
	assert_eq(inv.count("mushrooms"), 2)
	assert_gt(skills.xp("woodcraft"), 0.0)
	assert_false(forage.is_ready("m1"))
	assert_eq(forage.forage("m1")["reason"], "not_ready")
	var lo: int = Tuning.integer("foraging.regrow_days_min") * clock.MINUTES_PER_DAY
	var hi: int = Tuning.integer("foraging.regrow_days_max") * clock.MINUTES_PER_DAY
	clock.now = lo - 1
	assert_false(forage.is_ready("m1"))
	clock.now = hi
	assert_true(forage.is_ready("m1"))


func test_regrow_delay_always_within_two_to_four_days() -> void:
	var lo: int = Tuning.integer("foraging.regrow_days_min") * clock.MINUTES_PER_DAY
	var hi: int = Tuning.integer("foraging.regrow_days_max") * clock.MINUTES_PER_DAY
	for i in 30:
		clock.now = 0
		ws.flags.erase(Foraging.FLAG_PREFIX + "m1")
		ws.inventories.clear() # keep the pack from filling over 30 picks
		forage.forage("m1")
		var ready_at: int = int(ws.get_flag(Foraging.FLAG_PREFIX + "m1"))
		assert_between(ready_at, lo, hi)


func test_too_heavy_leaves_node_untouched() -> void:
	inv.add("potatoes", int(inv.capacity() / ItemDB.weight_of("potatoes")))
	var r: Dictionary = forage.forage("m1")
	assert_false(r["ok"])
	assert_eq(r["reason"], "too_heavy")
	assert_true(forage.is_ready("m1"))


func test_maggots_field_unwitnessed_costs_nothing() -> void:
	var r: Dictionary = forage.forage("m2", false)
	assert_true(r["ok"])
	assert_false(r["caught"])
	assert_eq(factions.reputation("shire"), 0)
	assert_false(ws.get_flag("caught_in_maggots_fields"))


func test_maggots_field_caught_costs_reputation_and_sets_flag() -> void:
	ws.set_npc_memory("farmer_maggot", "", -1, 0)
	var loss: int = int(Tuning.dict("foraging.zones")["maggots_fields"]["reputation_loss"])
	var r: Dictionary = forage.forage("m2", true)
	assert_true(r["caught"])
	assert_eq(factions.reputation("shire"), -loss)
	assert_true(ws.get_flag("caught_in_maggots_fields"))
	assert_lt(factions.disposition("farmer_maggot"), 0)
	assert_eq(inv.count("mushrooms"), 2, "haul is kept")


func test_witnessed_outside_zone_is_harmless() -> void:
	forage.forage("m1", true)
	assert_eq(factions.reputation("shire"), 0)


func test_stealth_lowers_caught_chance() -> void:
	var base: float = forage.caught_chance()
	skills.add_xp("stealth", 30.0)
	assert_lt(forage.caught_chance(), base)


func test_ready_nodes_filters_by_radius() -> void:
	assert_eq(forage.ready_nodes(Vector3.ZERO, 10.0), ["m1"])
	assert_eq(forage.ready_nodes().size(), 2)
