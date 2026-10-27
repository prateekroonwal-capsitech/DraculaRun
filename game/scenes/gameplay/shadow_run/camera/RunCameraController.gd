class_name RunCameraController
extends Camera3D

# RunCameraController — fixed third-person chase camera for Shadow Run (portrait).
# Mirrors CameraController's API (follow / stop_follow / shake) for 3D; the
# template's CameraController extends Camera2D so it cannot be reused directly.
# The camera uses keep_aspect = KEEP_WIDTH (set in CameraRig.tscn): the horizontal
# FOV is fixed, so every lane (LaneConfig) always fits and taller phones simply see further ahead.
# Ticks in _physics_process to stay in lockstep with Dracula (no follow jitter).
# PDF §4 CPU: the physics tick is off until follow() or shake() gives it work.

## Camera height above the road, meters.
@export var height: float = 11.0
## Distance behind the target along +Z, meters.
@export var distance: float = 9.0
## Downward pitch in degrees (35–45 keeps Dracula in the lower third of the play view).
@export_range(20.0, 70.0) var pitch_degrees: float = 38.0
## How much of the target's lane offset the camera follows (0 = locked to road center).
@export_range(0.0, 1.0) var lateral_follow: float = 0.35
## Lateral smoothing (higher = snappier). Kept low for a slight lag on lane changes.
@export var lateral_smoothing: float = 6.0
## Forward smoothing. Very high while running so speed changes never cause drift.
@export var forward_smoothing: float = 40.0

@export_group("Death cam")
@export var death_height: float = 6.0
@export var death_distance: float = 6.5
@export var death_pitch_degrees: float = 30.0

var _target: Node3D = null
var _shake_strength: float = 0.0
var _shake_time: float = 0.0
var _x: float = 0.0
var _z: float = 0.0

func _ready() -> void:
	# PDF §4: nothing to do until follow() or shake() is called
	set_physics_process(false)

func follow(target: Node3D) -> void:
	_target = target
	_x = target.global_position.x * lateral_follow
	_z = target.global_position.z
	_apply()
	set_physics_process(true)   # PDF §4: re-enable now that there is work to do

func stop_follow() -> void:
	_target = null
	_check_idle()

## Death cam: eases to a stop and dollies in on the target over `duration`.
func focus_death(duration: float = 1.5) -> void:
	forward_smoothing = 2.5
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "height", death_height, duration)
	tw.parallel().tween_property(self, "distance", death_distance, duration)
	tw.parallel().tween_property(self, "pitch_degrees", death_pitch_degrees, duration)

func shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_time = duration
	set_physics_process(true)   # PDF §4: re-enable for shake frames

func _physics_process(delta: float) -> void:
	if _target:
		var tp := _target.global_position
		_x = lerpf(_x, tp.x * lateral_follow, minf(1.0, lateral_smoothing * delta))
		_z = lerpf(_z, tp.z, minf(1.0, forward_smoothing * delta))
		_apply()

	if _shake_time > 0.0:
		h_offset = randf_range(-_shake_strength, _shake_strength)
		v_offset = randf_range(-_shake_strength, _shake_strength)
		_shake_time -= delta
	else:
		_shake_time = 0.0
		h_offset = 0.0
		v_offset = 0.0
		_check_idle()

func _apply() -> void:
	global_position = Vector3(_x, height, _z + distance)
	global_rotation = Vector3(deg_to_rad(-pitch_degrees), 0.0, 0.0)

# ── PDF §4: stop ticking when neither following nor shaking ───────────────

func _check_idle() -> void:
	if _target == null and _shake_time <= 0.0:
		set_physics_process(false)   # nothing to compute — save the frame budget
