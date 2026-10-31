extends GutTest

const WorldStateScript: GDScript = preload("res://autoload/world_state.gd")

var ws: Node
var factions: Factions


func before_each() -> void:
	ws = autofree(WorldStateScript.new())
	factions = Factions.new(ws)


func test_reputation_clamped() -> void:
	assert_eq(factions.change_reputation(Factions.BREE, -500), WorldStateScript.REPUTATION_MIN)
	assert_eq(factions.reputation(Factions.BREE), WorldStateScript.REPUTATION_MIN)
	assert_eq(factions.reputation(Factions.SHIRE), 0)


func test_disposition_clamped_and_keeps_memory() -> void:
	ws.set_npc_memory("butterbur", "knows you", 123, 1)
	assert_eq(factions.change_disposition("butterbur", 100), Tuning.integer("npc.disposition_max"))
	assert_eq(factions.change_disposition("butterbur", -100), Tuning.integer("npc.disposition_min"))
	var m: Dictionary = ws.get_npc_memory("butterbur")
	assert_eq(m["summary"], "knows you")
	assert_eq(m["last_talk"], 123)


func test_unknown_npc_starts_neutral() -> void:
	assert_eq(factions.disposition("stranger"), 0)
	assert_eq(factions.change_disposition("stranger", 2), 2)
