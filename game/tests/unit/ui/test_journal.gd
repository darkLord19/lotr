extends GutTest

const JournalScene: PackedScene = preload("res://ui/journal/journal.tscn")

var journal: Journal
var saved_now: int


func before_each() -> void:
	saved_now = WorldClock.now
	NPCTestHelper.reset_world("3018-09-29T21:00")
	journal = JournalScene.instantiate()
	journal.start_visible = true
	add_child_autofree(journal)


func after_each() -> void:
	WorldState.reset()
	WorldState.poi_info = {}
	WorldClock.now = saved_now


func test_empty_journal_shows_date_and_placeholders() -> void:
	assert_true(journal.visible)
	assert_string_contains(journal._date_label.text, "3018-09-29")
	assert_eq(Journal.heard_rumours().size(), 0)
	assert_eq(Journal.met_people().size(), 0)
	assert_eq(journal.rumour_rows(), 1, "one placeholder line")


func test_lists_heard_rumours_with_player_placeholder_resolved() -> void:
	WorldState.add_knowledge(WorldState.PLAYER_ID, "rumour:dwarves_going_east")
	WorldState.add_knowledge(WorldState.PLAYER_ID, "rumour:player_found_senseless")
	WorldState.add_knowledge(WorldState.PLAYER_ID, "some_other_knowledge")
	WorldState.set_flag("rumour_subject.player_found_senseless", "Hamfast")
	journal.refresh()
	var heard: Array[String] = Journal.heard_rumours()
	assert_eq(heard.size(), 2)
	assert_string_contains(heard[0], "Dwarves")
	assert_true(heard[1].begins_with("Hamfast was found senseless"))
	assert_eq(journal.rumour_rows(), 2)


func test_met_npcs_have_one_line_memory_most_recent_first() -> void:
	WorldState.set_npc_memory("gaffer_gamgee", "I told him about the rider. He seemed worried afterwards.", 100, 1)
	WorldState.set_npc_memory(NPCTestHelper.NPC, "A hobbit named Mr. Underhill. Polite enough.", 200, 0)
	WorldState.set_npc_memory("nob", "", -1, 0)
	var people: Array[Dictionary] = Journal.met_people()
	assert_eq(people.size(), 2, "never-spoken NPCs are skipped")
	assert_eq(people[0]["name"], "Barliman Butterbur")
	assert_eq(people[0]["line"], "A hobbit named Mr. Underhill.")
	assert_eq(people[1]["line"], "I told him about the rider.")
	journal.refresh()
	assert_eq(journal.people_rows(), 2)


func test_one_line_truncates_and_handles_empty() -> void:
	var limit: int = int(Config.get_value("journal.memory_max_chars"))
	var long_text: String = "word ".repeat(100)
	assert_lte(Journal.one_line(long_text).length(), limit)
	assert_true(Journal.one_line(long_text).ends_with("..."))
	assert_eq(Journal.one_line("  "), str(Config.get_value("journal.no_summary")))


func test_j_toggles_visibility() -> void:
	journal.start_visible = false
	journal.hide()
	var j := InputEventKey.new()
	j.keycode = KEY_J
	j.pressed = true
	journal._unhandled_key_input(j)
	assert_true(journal.visible)
	journal._unhandled_key_input(j)
	assert_false(journal.visible)
