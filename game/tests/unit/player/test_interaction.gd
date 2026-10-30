extends GutTest

var host: Node3D
var body: Node3D
var interaction: Interaction


func before_each() -> void:
	WorldState.reset()
	host = Node3D.new()
	add_child_autofree(host)
	body = Node3D.new()
	host.add_child(body)
	interaction = Interaction.new()
	interaction.body = body
	host.add_child(interaction)


func _item(kind: StringName, pos: Vector3, label: String = "thing", target: String = "", payload: Dictionary = {}) -> Interactable:
	var i: Interactable = Interactable.make(kind, label, target, payload)
	host.add_child(i)
	i.global_position = pos
	return i


func test_pick_nearest_respects_range_and_enabled() -> void:
	var pos: Array[Vector3] = [Vector3(2, 0, 0), Vector3(1, 0, 0), Vector3(9, 0, 0)]
	var on: Array[bool] = [true, false, true]
	assert_eq(Interactable.pick_nearest(Vector3.ZERO, pos, on, 2.5), 0)
	assert_eq(Interactable.pick_nearest(Vector3.ZERO, pos, [false, false, true] as Array[bool], 2.5), -1)
	assert_eq(Interactable.pick_nearest(Vector3.ZERO, pos, on, 0.5), -1)


func test_finds_nearest_within_2_5_m_and_builds_prompt() -> void:
	_item(Interactable.KIND_WELL, Vector3(2.4, 0, 0), "the well")
	var npc: Interactable = _item(Interactable.KIND_NPC, Vector3(0, 0, 1.0), "Sam", "sam")
	_item(Interactable.KIND_BED, Vector3(3.0, 0, 0), "the bed")
	assert_eq(interaction.find_nearest(), npc)
	assert_eq(npc.prompt_text(), "Talk to Sam")
	interaction._process(0.0)
	assert_eq(interaction.prompt_text(), "Talk to Sam")
	npc.global_position = Vector3(20, 0, 0)
	interaction._process(0.0)
	assert_eq(interaction.current().kind, Interactable.KIND_WELL)
	assert_eq(interaction.prompt_text(), "Drink from the well")


func test_door_toggles_and_emits() -> void:
	var door: Interactable = _item(Interactable.KIND_DOOR, Vector3(1, 0, 0), "the round door")
	watch_signals(door)
	assert_eq(door.prompt_text(), "Open the round door")
	assert_true(interaction.try_interact())
	assert_true(door.is_open)
	assert_eq(door.prompt_text(), "Close the round door")
	assert_signal_emitted(door, "activated")


func test_food_source_adds_item_to_inventory() -> void:
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", "bag_end", "", {})
	interaction.inventory = Inventory.new(WorldState.PLAYER_ID)
	_item(Interactable.KIND_FOOD, Vector3(1, 0, 0), "the pantry", "", {"item": "bread_loaf", "count": 2})
	assert_true(interaction.try_interact())
	assert_eq(interaction.inventory.count("bread_loaf"), 2)


func test_bed_sleeps_through_survival() -> void:
	WorldState.spawn_entity(WorldState.PLAYER_ID, "player", "bag_end", "", {"race": "hobbit"})
	var start: int = WorldClock.now
	interaction.survival = Survival.new()
	_item(Interactable.KIND_BED, Vector3(1, 0, 0), "the bed", "", {"hours": 2.0})
	assert_true(interaction.try_interact())
	assert_eq(WorldClock.now - start, 120)
	interaction.survival.detach()
	WorldClock.now = start


func test_nothing_in_range_does_nothing() -> void:
	_item(Interactable.KIND_DOOR, Vector3(10, 0, 0))
	assert_false(interaction.try_interact())
	assert_eq(interaction.prompt_text(), "")
