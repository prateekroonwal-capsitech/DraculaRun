class_name PowerUp
extends Node3D

## PowerUp — interface stub for post-prototype power-ups (sunlight shield, darkness
## burst, bat transformation, shadow dash, sun freeze). Nothing extends or spawns
## this yet. When implemented: the pickup calls collect(), the run feature applies
## the effect and emits GameBus.powerup_collected(id).

@export var id: StringName = &""
## Effect length in seconds (0 = instant).
@export var duration: float = 0.0

## Apply the effect. context carries whatever the effect needs (e.g. "sensor", "sun_rig").
func activate(_context: Dictionary) -> void:
	pass

## Remove the effect when duration runs out or the run ends.
func deactivate() -> void:
	pass
