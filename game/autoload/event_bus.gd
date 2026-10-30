extends Node

@warning_ignore("unused_signal")
signal llm_availability_changed(available: bool)

# Cross-system signals. Systems never reference each other's nodes; they talk here.
signal flag_changed(flag: String, value: Variant)
signal entity_moved(id: String, poi_or_pos: Variant)
signal item_transferred(item: String, from: String, to: String)
signal rumour_spread(rumour_id: String, poi: String)
signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)
signal player_failed(kind: String, data: Dictionary)
signal timeline_event_fired(event_id: String)
signal reputation_changed(faction: String, value: int)
signal npc_memory_changed(npc_id: String)
signal knowledge_added(npc_id: String, knowledge_id: String)
signal region_changed(region_id: String)
signal skill_unlocked(skill: String, tier: int)
