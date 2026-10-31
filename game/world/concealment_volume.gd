class_name ConcealmentVolume
extends Area3D
## Vegetation volume (bushes, dense hedges, forest thickets) that grants concealment to the player.

const GROUP: StringName = &"concealment_volumes"

@export_range(0.0, 1.0) var concealment: float = 0.75


func _ready() -> void:
	add_to_group(GROUP)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	collision_layer = 0
	collision_mask = 2 # Player collision layer


func _on_body_entered(body: Node) -> void:
	if body.has_method("add_concealment_source"):
		body.add_concealment_source(self)


func _on_body_exited(body: Node) -> void:
	if body.has_method("remove_concealment_source"):
		body.remove_concealment_source(self)
