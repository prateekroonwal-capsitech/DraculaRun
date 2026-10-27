class_name SunInput
extends UIController

## SunInput — the one interface every sun control implements (SunJoystick, SunControl
## strip). Controls only move the SunRig's *target* through SunRig.set_target() /
## nudge_target(); the rig owns the angle ranges (per level), the speed cap, smoothing and
## the exposure guard, and ShadowRunFeature re-syncs the ShadeGrid from the rig's signals —
## so every control behaves identically. ShadowRunHUD shows exactly one control at a time.
##
## Contract for implementations:
##   * emit drag_started / drag_ended around every interaction (finger, mouse or Q/E/R/F),
##     so Dracula stands still while the sun moves;
##   * consume their own touches in _input() (touches that start on them never become taps);
##   * when disabled, stop reading input and end any interaction (emitting drag_ended).

signal drag_started
signal drag_ended

## Which control is shown. Saved as MODE_KEYS[mode] under ShadowRunFeature.SUN_MODE_KEY.
enum Mode { JOYSTICK, SLIDER }
const MODE_KEYS: PackedStringArray = ["joystick", "slider"]

var _sun: SunRig

static func mode_from_key(key: String, fallback: Mode) -> Mode:
	var i := MODE_KEYS.find(key)
	return fallback if i < 0 else i as Mode

## Explicit dependency: the rig this control steers.
func bind_sun(sun: SunRig) -> void:
	_sun = sun

func set_controls_enabled(_enabled: bool) -> void:
	pass

func is_dragging() -> bool:
	return false

## The guard refused a sun move: show it on the control.
func play_blocked() -> void:
	pass

## True when a viewport position belongs to this control (touches there move the sun).
func contains(_viewport_pos: Vector2) -> bool:
	return false
