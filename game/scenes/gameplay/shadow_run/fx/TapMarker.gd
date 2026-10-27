class_name TapMarker
extends Node3D

## TapMarker — the ring that answers a tap on the ground: a soft pulse in the
## "go" colour when Dracula can walk there, red/grey when he can't.
## Ring mesh and both materials are authored in TapMarker.tscn.

@export var ring: MeshInstance3D
@export var ok_material: Material
@export var fail_material: Material
@export var pulse_time: float = 0.45
@export var start_scale: float = 0.35

var _tween: Tween

func _ready() -> void:
	visible = false

func play_at(world: Vector3, ok: bool) -> void:
	global_position = world + Vector3(0.0, 0.03, 0.0)
	ring.material_override = ok_material if ok else fail_material
	visible = true
	ring.scale = Vector3.ONE * start_scale
	ring.transparency = 0.0
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(ring, "scale", Vector3.ONE, pulse_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(ring, "transparency", 1.0, pulse_time).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: visible = false)
