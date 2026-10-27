class_name MoveMarker
extends Node3D

## MoveMarker — the one yellow ring that answers both input modes:
##   * tap: play_at() pulses in the "go" colour where Dracula will stop (red/grey when
##     he can't go there), then fades;
##   * drag: hold_at() keeps the same ring steady under the cell he is heading to (never
##     under a sunlit finger) and glides after it; on release play_at() runs the same
##     pulse-and-fade on his final stop.
## Ring mesh and both materials are authored in MoveMarker.tscn.

@export var ring: MeshInstance3D
@export var ok_material: Material
@export var fail_material: Material
@export var pulse_time: float = 0.45
@export var start_scale: float = 0.35
## Drag mode: how quickly the held ring glides to a new target (1/s).
@export var follow_rate: float = 18.0

var _tween: Tween
var _target: Vector3
var _holding: bool = false

func _ready() -> void:
	visible = false
	set_process(false)   # PDF §4: tick only while gliding in drag mode

func play_at(world: Vector3, ok: bool) -> void:
	_holding = false
	set_process(false)
	global_position = world + Vector3(0.0, 0.03, 0.0)
	ring.material_override = ok_material if ok else fail_material
	visible = true
	ring.scale = Vector3.ONE * start_scale
	ring.transparency = 0.0
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(ring, "scale", Vector3.ONE, pulse_time).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(ring, "transparency", 1.0, pulse_time).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func() -> void: visible = false)

## Drag mode: show the ring steadily at `world` (gliding there if already shown).
func hold_at(world: Vector3) -> void:
	_target = world + Vector3(0.0, 0.03, 0.0)
	if not _holding:
		_holding = true
		_kill_tween()
		global_position = _target
		ring.material_override = ok_material
		ring.scale = Vector3.ONE
		ring.transparency = 0.0
		visible = true
		set_process(true)

## Drag cancelled (pause, death, goal): fade without a pulse.
func fade_out() -> void:
	if not _holding:
		return
	_holding = false
	set_process(false)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(ring, "transparency", 1.0, pulse_time * 0.5)
	_tween.tween_callback(func() -> void: visible = false)

func _process(delta: float) -> void:
	global_position = global_position.lerp(_target, minf(1.0, follow_rate * delta))

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
