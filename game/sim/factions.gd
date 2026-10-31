class_name Factions
extends RefCounted
## Reputation (per faction) and disposition (per NPC) helpers over WorldState. All values live in
## WorldState; this only applies the clamps and keeps NPC memory fields intact.

const SHIRE: String = "shire"
const BREE: String = "bree"

var _state: Node


func _init(state: Node = null) -> void:
	_state = state if state != null else WorldState


func reputation(faction: String) -> int:
	return _state.get_reputation(faction)


func change_reputation(faction: String, delta: int) -> int:
	return _state.change_reputation(faction, delta)


func disposition(npc_id: String) -> int:
	return int(_state.get_npc_memory(npc_id)["disposition"])


## Same bounds the dialogue layer uses, so a theft cannot push an NPC beyond what talking could.
func change_disposition(npc_id: String, delta: int) -> int:
	var lo: int = Tuning.integer("npc.disposition_min")
	var hi: int = Tuning.integer("npc.disposition_max")
	var m: Dictionary = _state.get_npc_memory(npc_id)
	var d: int = clampi(int(m["disposition"]) + delta, lo, hi)
	_state.set_npc_memory(npc_id, str(m["summary"]), int(m["last_talk"]), d)
	return d
