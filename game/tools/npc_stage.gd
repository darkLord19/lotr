class_name NPCStage
extends Node3D
## Dev scene for captures: the world plus an NPCSpawner following the camera, no game flow.
## tools/capture.sh res://tools/npc_stage.tscn out.png --pos=x,y,z --look=yaw,pitch

var world: WorldRoot
var spawner: NPCSpawner


func _ready() -> void:
	world = (load("res://world/world_root.tscn") as PackedScene).instantiate() as WorldRoot
	add_child(world)
	var graph := RoadGraph.new()
	graph.load_region()
	spawner = NPCSpawner.new()
	spawner.graph = graph
	spawner.viewer = world.camera
	spawner.height_provider = Callable(world, "height_at")
	add_child(spawner)


func capture_prepare() -> void:
	await world.capture_prepare()
	spawner.scan()
	for i in 10:
		await get_tree().process_frame
