class_name CameraController
extends Camera2D

# CameraController — smooth follow + screen shake
# PDF §4 CPU: _process disables itself when there is nothing to do
#   (no target, no active shake). Re-enabled by follow() and shake().
#   Cameras must remain as non-disabled nodes, but we avoid the lerp
#   and randf cost on idle frames.

var _target:         Node2D = null
var _shake_strength: float  = 0.0
var _shake_time:     float  = 0.0

func _ready() -> void:

	# PDF §4: nothing to do until follow() or shake() is called
	set_process(false)

func follow(target: Node2D) -> void:
	_target = target
	set_process(true)   # PDF §4: re-enable now that there is work to do

func stop_follow() -> void:
	_target = null
	_check_idle()

func shake(strength: float, duration: float) -> void:
	_shake_strength = strength
	_shake_time     = duration
	set_process(true)   # PDF §4: re-enable for shake frames

func _process(delta: float) -> void:
	if _target:
		global_position = global_position.lerp(_target.global_position, 8.0 * delta)

	if _shake_time > 0.0:
		offset = Vector2(
			randf_range(-_shake_strength, _shake_strength),
			randf_range(-_shake_strength, _shake_strength)
		)
		_shake_time -= delta
	else:
		_shake_time = 0.0
		offset      = Vector2.ZERO
		_check_idle()

# ── PDF §4: stop ticking when neither following nor shaking ───────────────

func _check_idle() -> void:
	if _target == null and _shake_time <= 0.0:
		set_process(false)   # nothing to compute — save the frame budget
