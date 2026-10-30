class_name RiderAINode
extends Node3D
## Thin scene wrapper around RiderAI. Patrols around the rider's timeline position (the
## entity in WorldState) and asks `target_provider` for the player's stealth state.

signal interrogation_started(beats: Array[Dictionary])

@export var entity_id: String = ""
## Callable() -> RiderPerception.Target, installed by the player/scene layer.
var target_provider: Callable = Callable()
var night_provider: Callable = Callable()
var player_race: String = ""
var player_name: String = ""
var ai: RiderAI = RiderAI.new()
var soft_failure: SoftFailure


func _ready() -> void:
	ai.position = global_position
	ai.caught.connect(_on_caught)


func _physics_process(delta: float) -> void:
	if not target_provider.is_valid():
		return
	var loc: Dictionary = WorldState.entity_location(entity_id)
	if loc["pos"] is Vector3:
		ai.patrol_target = loc["pos"]
	var is_night: bool = night_provider.is_valid() and bool(night_provider.call())
	ai.step(delta, target_provider.call(), is_night)
	global_position = ai.position
	if ai.facing.length_squared() > 0.0:
		look_at(global_position + ai.facing, Vector3.UP)


func _on_caught() -> void:
	interrogation_started.emit(RiderInterrogation.build(player_race))


## Called by the dialogue/cutscene layer once the exchange has played out.
func finish_interrogation() -> Dictionary:
	if soft_failure == null:
		soft_failure = SoftFailure.new()
	var summary: Dictionary = soft_failure.apply(player_name, player_race)
	ai.release()
	return summary
