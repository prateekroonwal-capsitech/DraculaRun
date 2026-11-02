class_name SunRig
extends Node3D

## SunRig — owns the DirectionalLight3D and the sun's angular state.
## Azimuth swings the sun across the level (negative = left / −X, positive = right / +X,
## 0 = straight ahead down −Z); elevation sets shadow length (low = long). Both ranges
## come from the level (ShadowLevel). SunJoystick only sets a *target*; the rig moves
## toward it with a capped, smoothed angular speed.
##
## Exposure guard: when `guard` is set (Callable(dir: Vector3) -> bool, "is Dracula
## still fully shaded with the sun in this direction?"), every step that would expose
## him is refused — the sun stops at the last safe angle, the target is clamped there
## and `guard_blocked` fires (the widget shakes, Dracula flinches).
## PDF §4 CPU: the physics tick is disabled whenever the sun is at rest on its target.

## Emitted whenever the live (not target) angles change.
signal sun_moved(azimuth_deg: float, elevation_deg: float)
## The sun reached its target and stopped moving.
signal settled
## A sun move was refused because it would expose Dracula.
signal guard_blocked

@export_group("Limits")
@export var azimuth_min: float = -70.0
@export var azimuth_max: float = 70.0
@export var elevation_min: float = 18.0
@export var elevation_max: float = 60.0

@export_group("Motion")
## Hard cap on angular speed, degrees per second.
@export var max_azimuth_speed: float = 180.0
@export var max_elevation_speed: float = 180.0
## Frame-rate independent follow speed toward target (1/s). Default 12.0.
@export var sun_follow_speed: float = 12.0
## Within this many degrees of the target the sun snaps onto it and stops ticking.
@export var settle_threshold: float = 0.15
## Binary-search steps used to find the last safe angle when the guard refuses a step.
@export var guard_search_steps: int = 8
## Hysteresis margin in degrees: once blocked, target must re-enter safe zone by this much before unblocking.
@export var guard_hysteresis_margin: float = 0.5

@export_group("Start")
@export var start_azimuth: float = 0.0
@export var start_elevation: float = 40.0

@export_group("Look")
@export var light: DirectionalLight3D
@export var sun_color: Color = Color(1.0, 0.82, 0.42)
@export var sun_energy: float = 1.5

var azimuth: float = 0.0
var elevation: float = 45.0
var target_azimuth: float = 0.0
var target_elevation: float = 45.0
## Callable(dir: Vector3) -> bool. Empty = no guard.
var guard: Callable = Callable()

var _is_guard_blocked: bool = false
var _last_safe_azimuth: float = 0.0
var _last_safe_elevation: float = 45.0

func _ready() -> void:
	process_priority = -50
	set_physics_process(false)
	snap_to(start_azimuth, start_elevation)

## Per-level setup: azimuth/elevation ranges and the starting angle.
func configure(az_min: float, az_max: float, el_min: float, el_max: float, start_az: float, start_el: float) -> void:
	print("[STARTUP %dms] SunRig.configure: az=[%.1f, %.1f] el=[%.1f, %.1f] start=(%.1f, %.1f)" % [
		Time.get_ticks_msec(), az_min, az_max, el_min, el_max, start_az, start_el
	])
	azimuth_min = az_min
	azimuth_max = az_max
	elevation_min = el_min
	elevation_max = el_max
	snap_to(start_az, start_el)

## Direction from the ground toward the sun (unit vector) for the given angles.
## Static so validators/self-checks share the exact same math as gameplay.
static func direction_from_angles(azimuth_deg: float, elevation_deg: float) -> Vector3:
	var az := deg_to_rad(azimuth_deg)
	var el := deg_to_rad(elevation_deg)
	return Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))

## Unit vector pointing toward the sun (= −light forward). Used by ShadowSensor.
func get_toward_sun() -> Vector3:
	return direction_from_angles(azimuth, elevation)

func set_target(azimuth_deg: float, elevation_deg: float) -> void:
	var req_az := clampf(azimuth_deg, azimuth_min, azimuth_max)
	var req_el := clampf(elevation_deg, elevation_min, elevation_max)

	if _is_guard_blocked and guard.is_valid():
		# If the requested target is still unsafe, keep target clamped at the last safe angle
		if not _safe(req_az, req_el):
			target_azimuth = _last_safe_azimuth
			target_elevation = _last_safe_elevation
			return
		# Check hysteresis: has the target moved back into the safe zone by at least guard_hysteresis_margin?
		var dist_to_safe_border := Vector2(req_az - _last_safe_azimuth, req_el - _last_safe_elevation).length()
		if dist_to_safe_border < guard_hysteresis_margin:
			target_azimuth = _last_safe_azimuth
			target_elevation = _last_safe_elevation
			return
		# Re-entered safe zone by more than the hysteresis margin: unblock
		_is_guard_blocked = false

	target_azimuth = req_az
	target_elevation = req_el
	set_process(true)

func nudge_target(d_azimuth: float, d_elevation: float) -> void:
	set_target(target_azimuth + d_azimuth, target_elevation + d_elevation)

## Teleport (no rate limit, no guard). Used at level start and by tests/validators.
func snap_to(azimuth_deg: float, elevation_deg: float) -> void:
	target_azimuth = clampf(azimuth_deg, azimuth_min, azimuth_max)
	target_elevation = clampf(elevation_deg, elevation_min, elevation_max)
	azimuth = target_azimuth
	elevation = target_elevation
	_last_safe_azimuth = azimuth
	_last_safe_elevation = elevation
	_is_guard_blocked = false
	_apply()
	set_process(false)

func is_settled() -> bool:
	return not is_processing()

func _process(delta: float) -> void:
	if delta <= 0.0:
		return

	var blend := 1.0 - exp(-sun_follow_speed * delta)

	# Frame-rate independent smoothing via lerp_angle + max speed clamp
	var az_rad := deg_to_rad(azimuth)
	var tgt_az_rad := deg_to_rad(target_azimuth)
	var step_az := rad_to_deg(lerp_angle(az_rad, tgt_az_rad, blend) - az_rad)
	var max_step_az := max_azimuth_speed * delta
	step_az = clampf(step_az, -max_step_az, max_step_az)
	var new_az := azimuth + step_az

	var el_rad := deg_to_rad(elevation)
	var tgt_el_rad := deg_to_rad(target_elevation)
	var step_el := rad_to_deg(lerp_angle(el_rad, tgt_el_rad, blend) - el_rad)
	var max_step_el := max_elevation_speed * delta
	step_el = clampf(step_el, -max_step_el, max_step_el)
	var new_el := elevation + step_el

	if guard.is_valid() and not _safe(new_az, new_el) and _safe(azimuth, elevation):
		# Find the furthest safe angle along the trajectory, clamp target, and hold with hysteresis
		var lo := 0.0
		var hi := 1.0
		for _i in guard_search_steps:
			var mid := (lo + hi) * 0.5
			if _safe(lerpf(azimuth, new_az, mid), lerpf(elevation, new_el, mid)):
				lo = mid
			else:
				hi = mid
		var safe_az := lerpf(azimuth, new_az, lo)
		var safe_el := lerpf(elevation, new_el, lo)
		azimuth = safe_az
		elevation = safe_el
		target_azimuth = safe_az
		target_elevation = safe_el
		_last_safe_azimuth = safe_az
		_last_safe_elevation = safe_el
		_is_guard_blocked = true
		_apply()
		set_process(false)
		guard_blocked.emit()
		settled.emit()
		return

	azimuth = new_az
	elevation = new_el

	if absf(target_azimuth - azimuth) < settle_threshold and absf(target_elevation - elevation) < settle_threshold:
		azimuth = target_azimuth
		elevation = target_elevation
		set_process(false)
		_apply()
		settled.emit()
		return

	_apply()

func _safe(az: float, el: float) -> bool:
	return guard.call(direction_from_angles(az, el))

func _apply() -> void:
	if light:
		light.global_basis = Basis.looking_at(-get_toward_sun(), Vector3.UP)
		light.light_color = sun_color
		light.light_energy = sun_energy
	sun_moved.emit(azimuth, elevation)
