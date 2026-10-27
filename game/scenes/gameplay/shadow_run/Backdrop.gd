extends Node3D

## Distant gothic skyline (hills + castle silhouettes). Slides along Z with the
## runner so it reads as "infinitely far away"; it never casts shadows and has no
## collision, so it can never affect shade gameplay.

@export var follow_target: Node3D

func _ready() -> void:
	set_physics_process(follow_target != null)   # PDF §4: idle without a target

func _physics_process(_delta: float) -> void:
	global_position.z = follow_target.global_position.z
