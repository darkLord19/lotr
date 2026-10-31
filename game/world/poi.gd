class_name Poi
extends Node3D
## Marker for a region point of interest (an inn, Bag End, the Hedge gate). It owns an interaction
## volume (Area3D) that tells the world when the player is at the place, and the Interactable children
## (door, bed, food) that belong to it. CellStreamer creates one per POI while its cell is loaded.

signal player_entered(poi: Poi)
signal player_exited(poi: Poi)

var poi_id: String = ""
var display_name: String = ""
var kind: String = ""
var volume: Area3D
var _occupants: int = 0


static func make(id_: String, name_: String, kind_: String, radius_m: float) -> Poi:
	var p := Poi.new()
	p.poi_id = id_
	p.display_name = name_
	p.kind = kind_
	p.name = "poi_%s" % id_
	p.volume = Area3D.new()
	p.volume.name = "Volume"
	# Monitoring only: the volume never pushes anything, and sees every body layer the player may use.
	p.volume.monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius_m
	shape.shape = sphere
	p.volume.add_child(shape)
	p.add_child(p.volume)
	p.volume.body_entered.connect(p._on_body_entered)
	p.volume.body_exited.connect(p._on_body_exited)
	return p


## Adds an Interactable child at a world position (valid before or after the POI is in the tree).
func add_interactable(kind_: StringName, label_: String, world_pos: Vector3, payload_: Dictionary = {}, target_id_: String = "") -> Interactable:
	var it: Interactable = Interactable.make(kind_, label_, target_id_, payload_)
	it.name = "%s_%d" % [String(kind_), get_child_count()]
	add_child(it)
	it.position = world_pos - position
	return it


func interactables() -> Array[Interactable]:
	var out: Array[Interactable] = []
	for c in get_children():
		if c is Interactable:
			out.append(c as Interactable)
	return out


func occupied() -> bool:
	return _occupants > 0


func _is_player(body: Node) -> bool:
	return body is PlayerController or body.is_in_group(StringName(str(Config.get_value("population.poi.player_group", "player"))))


func _on_body_entered(body: Node3D) -> void:
	if _is_player(body):
		_occupants += 1
		if _occupants == 1:
			player_entered.emit(self)


func _on_body_exited(body: Node3D) -> void:
	if _is_player(body):
		_occupants = maxi(0, _occupants - 1)
		if _occupants == 0:
			player_exited.emit(self)
