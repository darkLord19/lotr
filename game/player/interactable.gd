class_name Interactable
extends Node3D
## Component any world object adds as a child to become usable with E. Objects register simply by
## existing in the tree (group membership); they never reference the player. `activated` lets the
## owner react (open a door mesh, play a sound); Interaction applies the built-in effect for `kind`.

signal activated(actor: Node)

const GROUP: StringName = &"interactable"
const KIND_NPC: StringName = &"npc"
const KIND_DOOR: StringName = &"door"
const KIND_WELL: StringName = &"well"
const KIND_BED: StringName = &"bed"
const KIND_FOOD: StringName = &"food"

var kind: StringName = KIND_NPC
## Shown in the prompt ("Talk to Barliman").
var label: String = ""
## NPC id for KIND_NPC.
var target_id: String = ""
## Kind specific: bed {hours, place}, food {item, count}, door {}.
var payload: Dictionary = {}
var enabled: bool = true
var is_open: bool = false


static func make(kind_: StringName, label_: String, target_id_: String = "", payload_: Dictionary = {}) -> Interactable:
	var i := Interactable.new()
	i.kind = kind_
	i.label = label_
	i.target_id = target_id_
	i.payload = payload_
	return i


func _enter_tree() -> void:
	add_to_group(GROUP)


func verb() -> String:
	var verbs: Dictionary = Config.get_value("player.interaction.verbs", {})
	var key: String = String(kind)
	if kind == KIND_DOOR and is_open:
		key = "door_open"
	return str(verbs.get(key, "Use"))


func prompt_text() -> String:
	var subject: String = label if not label.is_empty() else str(Config.get_value("player.interaction.unnamed", "it"))
	return "%s %s" % [verb(), subject]


## Nearest enabled candidate within range, as an index into `positions`; -1 if none. Pure so it is
## testable without scenes. Flat (xz) distance: a well on a slope is still reachable.
static func pick_nearest(from: Vector3, positions: Array[Vector3], enabled_flags: Array[bool], max_dist: float) -> int:
	var best: int = -1
	var best_d: float = max_dist
	for i in positions.size():
		if not enabled_flags[i]:
			continue
		var d: float = Vector2(positions[i].x - from.x, positions[i].z - from.z).length()
		if d <= best_d:
			best_d = d
			best = i
	return best
