extends GutTest
## Rumour spread over the real eriador_west road graph.
##
## Expectation for a strength-5 rumour from Bag End to the Prancing Pony (Bree), with the
## shipped config (p = 5 * 0.3 / (1 + d/2000 m), capped at 0.95, one roll per neighbour per day):
##   Hobbiton -> Bywater   778 m  p = 0.95   (mean 1.05 days)
##   Bywater -> Frogmorton 1745 m p = 0.80   (mean 1.25 days)
##   Frogmorton -> Bree   4079 m  p = 0.49   (mean 2.04 days)
## The shortest settlement chain is 3 hops and a rumour moves one hop per day, so Bree can never
## hear it before day 3; the chain's mean is about 4.3 days (the Stock -> Buckland -> Bree
## detour shaves it to about 4.1, which the 300-seed run measures). So with a fixed seed we
## expect day 3-7, and over many seeds a mean near 4 days with nearly all runs inside the 10-day window.

const RUMOUR: String = "test_strength5"
const BREE_HUB: String = "prancing_pony"
const SEED_SAMPLES: int = 300
const WINDOW_DAYS: int = 10
const MIN_HOPS: int = 3

var net: RumourNetwork
var saved_now: int
var saved_poi: Dictionary


func before_each() -> void:
	saved_now = WorldClock.now
	saved_poi = WorldState.poi_info.duplicate(true)
	WorldState.reset()
	WorldState.poi_info = {}
	net = RumourNetwork.new()
	net.graph = RoadGraph.new()
	assert_true(net.graph.load_region())
	net.rebuild()
	net.register_pois()
	net.seed_rng(7)
	autofree(net)  # kept out of the tree so it does not listen to the live clock/bus


func after_each() -> void:
	WorldState.reset()
	WorldState.poi_info = saved_poi
	WorldClock.now = saved_now


func _plant(strength: int, max_hops: int, origin: String = "bag_end") -> void:
	WorldState.set_flag(RumourNetwork.DYNAMIC_FLAG, {RUMOUR: {"text": "A test rumour.", "origin_poi": origin, "strength": strength, "max_hops": max_hops}})
	WorldState.spread_rumour(RUMOUR, origin)


func test_settlement_graph_follows_the_road() -> void:
	assert_eq(net.neighbours_of("hobbiton").keys(), ["bywater"])
	var bree: Array = net.neighbours_of("bree").keys()
	bree.sort()
	assert_eq(bree, ["buckland", "combe", "frogmorton", "staddle"])
	assert_eq(net.hub_of("bree"), BREE_HUB)
	assert_almost_eq(float(net.neighbours_of("hobbiton")["bywater"]), 778.0, 5.0)


func test_probability_rises_with_strength_and_falls_with_distance() -> void:
	assert_gt(RumourNetwork.spread_probability(4, 1000.0), RumourNetwork.spread_probability(2, 1000.0))
	assert_gt(RumourNetwork.spread_probability(3, 500.0), RumourNetwork.spread_probability(3, 4000.0))
	assert_lte(RumourNetwork.spread_probability(5, 0.0), float(Config.get_value("rumours.spread.p_max")))
	assert_eq(RumourNetwork.spread_probability(0, 500.0), 0.0)


func test_one_hop_per_day() -> void:
	_plant(5, 6)
	net.step_day()
	assert_false(WorldState.rumour_known_at(RUMOUR, "frogmorton"), "a rumour new to Bywater cannot also reach Frogmorton the same day")


func test_fixed_seed_reaches_bree_within_expected_days() -> void:
	_plant(5, 6)
	var day: int = net.simulate_days(RUMOUR, BREE_HUB, WINDOW_DAYS)
	gut.p("seed 7: reached Bree on day %d" % day)
	assert_gte(day, MIN_HOPS, "three settlement hops need at least three days")
	assert_lte(day, 7)
	assert_true(WorldState.rumour_known_at(RUMOUR, "bywater"))


func test_same_seed_is_reproducible() -> void:
	_plant(5, 6)
	var first: int = net.simulate_days(RUMOUR, BREE_HUB, WINDOW_DAYS)
	WorldState.rumours = {}
	WorldState.spread_rumour(RUMOUR, "bag_end")
	net.seed_rng(7)
	assert_eq(net.simulate_days(RUMOUR, BREE_HUB, WINDOW_DAYS), first)


func test_many_seeds_match_the_expected_speed() -> void:
	var total: int = 0
	var within: int = 0
	for s in range(SEED_SAMPLES):
		WorldState.rumours = {}
		_plant(5, 6)
		net.seed_rng(s + 1)
		var day: int = net.simulate_days(RUMOUR, BREE_HUB, WINDOW_DAYS)
		if day > 0:
			within += 1
			total += day
			assert_gte(day, MIN_HOPS)
	var mean: float = float(total) / float(maxi(within, 1))
	gut.p("mean arrival %.2f days, %d/%d within %d days" % [mean, within, SEED_SAMPLES, WINDOW_DAYS])
	assert_between(mean, 3.6, 4.8)
	assert_gte(float(within) / float(SEED_SAMPLES), 0.95)


func test_weak_rumours_are_slower_than_strong_ones() -> void:
	var weak: int = 0
	var strong: int = 0
	for s in range(SEED_SAMPLES):
		for st: Array in [[1, 0], [5, 1]]:
			WorldState.rumours = {}
			_plant(int(st[0]), 6)
			net.seed_rng(s + 1)
			var reached: int = net.simulate_days(RUMOUR, BREE_HUB, WINDOW_DAYS)
			if reached > 0:
				if st[1] == 0:
					weak += 1
				else:
					strong += 1
	assert_lt(weak, strong)


func test_max_hops_limits_the_reach() -> void:
	_plant(5, 1)
	net.simulate_days(RUMOUR, BREE_HUB, 40)
	assert_true(WorldState.rumour_known_at(RUMOUR, "bywater"))
	assert_false(WorldState.rumour_known_at(RUMOUR, "frogmorton"), "max_hops 1 stops after the first neighbour")


func test_npc_in_destination_settlement_gets_it_in_the_prompt() -> void:
	_plant(5, 6)
	WorldState.spawn_entity("barliman_butterbur", "npc", "prancing_pony")
	assert_false(RUMOUR in NPCFacts.heard_rumours("barliman_butterbur", {}))
	WorldState.spread_rumour(RUMOUR, BREE_HUB)
	assert_true(RUMOUR in NPCFacts.heard_rumours("barliman_butterbur", {}))
	WorldState.spawn_entity("bill_ferny", "npc", "bill_ferny_house")
	assert_true(RUMOUR in NPCFacts.heard_rumours("bill_ferny", {}), "same settlement, different POI")


func test_traveller_carries_rumour_between_settlements() -> void:
	WorldState.set_flag(RumourNetwork.DYNAMIC_FLAG, {RUMOUR: {"text": "t", "origin_poi": "prancing_pony", "strength": 5, "max_hops": 6}})
	WorldState.spread_rumour(RUMOUR, "prancing_pony")
	net.note_arrival("pedlar", "prancing_pony")
	var got: bool = false
	# 0.9 (capped) per arrival: a handful of trips is certain enough for a fixed seed.
	for i in range(5):
		if RUMOUR in net.note_arrival("pedlar", "staddle"):
			got = true
			break
		net.note_arrival("pedlar", "prancing_pony")
	assert_true(got)
	assert_true(WorldState.rumour_known_at(RUMOUR, "staddle"))
	assert_false(WorldState.rumour_known_at(RUMOUR, "bywater"))


func test_traveller_outside_settlements_changes_nothing() -> void:
	WorldState.set_flag(RumourNetwork.DYNAMIC_FLAG, {RUMOUR: {"text": "t", "origin_poi": "prancing_pony", "strength": 5, "max_hops": 6}})
	WorldState.spread_rumour(RUMOUR, "prancing_pony")
	net.note_arrival("pedlar", "prancing_pony")
	assert_eq(net.note_arrival("pedlar", "brandywine_bridge").size(), 0)


func test_learned_fact_becomes_rumour_at_npc_settlement() -> void:
	WorldState.spawn_entity("farmer_maggot", "npc", "maggots_farm")
	WorldState.set_flag(NPCMemory.LEARNED_FLAG_PREFIX + "farmer_maggot", ["The stranger paid in old silver."])
	var made: Array[String] = net.ingest_learned_facts()
	assert_eq(made.size(), 1)
	assert_true(WorldState.rumour_known_at(made[0], net.hub_of("marish")), str(WorldState.rumours))
	assert_eq(RumourNetwork.resolve_text(made[0]), "The stranger paid in old silver.")
	assert_eq(net.ingest_learned_facts().size(), 0, "idempotent")
	# NPCs in the same settlement (another farm POI) hear it through the prompt path.
	WorldState.spawn_entity("mrs_maggot", "npc", "bamfurlong")
	assert_true(made[0] in NPCFacts.heard_rumours("mrs_maggot", {}))
	assert_true(NPCContent.rumour_text(made[0]).contains("old silver"))


func test_learned_fact_ingested_when_flag_changes() -> void:
	WorldState.spawn_entity("gaffer_gamgee", "npc", "bagshot_row")
	add_child(net)  # in the tree it listens to flag_changed like in the game
	WorldState.set_flag(NPCMemory.LEARNED_FLAG_PREFIX + "gaffer_gamgee", ["A rider asked for Mr. Baggins."])
	var found: bool = false
	for rid: String in WorldState.rumours:
		found = found or rid.begins_with(RumourNetwork.LEARNED_ID_PREFIX + "gaffer_gamgee")
	assert_true(found)
	assert_true(WorldState.rumour_known_at(WorldState.rumours.keys()[0], "bag_end"), "origin is the settlement hub")


func test_player_placeholder_resolves_from_subject_flag() -> void:
	assert_true(NPCContent.rumour_text("player_found_senseless").begins_with("someone was found"))
	WorldState.set_flag("rumour_subject.player_found_senseless", "Hamfast Underhill")
	assert_true(NPCContent.rumour_text("player_found_senseless").begins_with("Hamfast Underhill was found senseless"))
	assert_false(NPCContent.rumour_text("player_found_senseless").contains("{player}"))
