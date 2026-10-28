class_name DraculaVisual
extends Node3D

## DraculaVisual — the imported, animated Dracula (inherited scene of Dracula/dracula.glb).
## DraculaController owns position, heading (turning), hops, burn and death; every
## physics frame it calls set_motion() with his real ground speed, and this drives the
## AnimationTree in DraculaVisual.tscn:
##   * Locomotion (BlendSpace1D, x = speed m/s): Idle 0, Walk at walk_clip_speed,
##     Run at run_clip_speed;
##   * Speed (TimeScale): above the Walk point playback is scaled by
##     speed / (blended clip speed), so the feet never slide.
## Only Idle / Walk / Run are imported (dracula_import.gd drops the unused clips).
## Cloak motion is baked into the clips (no runtime cloak script). Hops keep Run playing
## (the controller passes run speed while hopping). Speed changes are smoothed with
## locomotion_blend_time, so stopping eases into Idle.

@export var animation_tree: AnimationTree
## Ground speed each clip was authored for (m/s), measured from the planted foot:
## Walk 1.44, Run 4.24.
@export var walk_clip_speed: float = 1.44
@export var run_clip_speed: float = 4.24
## Crossfade time, seconds (exponential smoothing time constant).
@export var locomotion_blend_time: float = 0.2
## Never play slower than this when moving above walk speed (keeps the stride lively).
@export var min_time_scale: float = 0.5

const _P_LOCO := &"parameters/Locomotion/blend_position"
const _P_SPEED := &"parameters/Speed/scale"

var _target_speed: float = 0.0
var _speed: float = 0.0

func _ready() -> void:
	animation_tree.active = true
	_apply()
	set_process(false)   # PDF §4: tick only while blends are changing

## Called by DraculaController every physics frame: real ground speed (m/s).
func set_motion(speed: float) -> void:
	_target_speed = maxf(0.0, speed)
	if not is_processing() and not is_equal_approx(_target_speed, _speed):
		set_process(true)

## Snap straight to Idle (level start, death).
func reset_to_idle() -> void:
	_target_speed = 0.0
	_speed = 0.0
	_apply()

func _process(delta: float) -> void:
	_speed = lerpf(_speed, _target_speed, 1.0 - exp(-delta / maxf(0.01, locomotion_blend_time)))
	if absf(_speed - _target_speed) < 0.01:
		_speed = _target_speed
		set_process(false)
	_apply()

func _apply() -> void:
	animation_tree.set(_P_LOCO, minf(_speed, run_clip_speed))
	var time_scale := 1.0
	if _speed > walk_clip_speed:
		var t := clampf((_speed - walk_clip_speed) / maxf(0.01, run_clip_speed - walk_clip_speed), 0.0, 1.0)
		time_scale = maxf(min_time_scale, _speed / lerpf(walk_clip_speed, run_clip_speed, t))
	animation_tree.set(_P_SPEED, time_scale)
