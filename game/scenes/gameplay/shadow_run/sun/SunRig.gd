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
## Exponential smoothing toward the target (1/s). Higher = snappier (lag ≈ 1/smoothing s).
@export var smoothing: float = 22.0
## Minimum catch-up speed (°/s) so the exponential tail never crawls after the finger stops.
@export var min_follow_speed: float = 60.0
## Within this many degrees of the target the sun snaps onto it and stops ticking.
@export var settle_threshold: float = 0.25
## Binary-search steps used to find the last safe angle when the guard refuses a step.
@export var guard_search_steps: int = 6

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

func _ready() -> void:
	# Update the light before anything that queries it this physics frame (ShadowSensor).
	process_physics_priority = -10
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
	target_azimuth = clampf(azimuth_deg, azimuth_min, azimuth_max)
	target_elevation = clampf(elevation_deg, elevation_min, elevation_max)
	set_physics_process(true)   # PDF §4: there is motion to integrate

func nudge_target(d_azimuth: float, d_elevation: float) -> void:
	set_target(target_azimuth + d_azimuth, target_elevation + d_elevation)

## Teleport (no rate limit, no guard). Used at level start and by tests/validators.
func snap_to(azimuth_deg: float, elevation_deg: float) -> void:
	target_azimuth = clampf(azimuth_deg, azimuth_min, azimuth_max)
	target_elevation = clampf(elevation_deg, elevation_min, elevation_max)
	azimuth = target_azimuth
	elevation = target_elevation
	_apply()
	set_physics_process(false)

func is_settled() -> bool:
	return not is_physics_processing()

func _physics_process(delta: float) -> void:
	var blend := 1.0 - exp(-smoothing * delta)
	var new_az := azimuth + _follow_step(target_azimuth - azimuth, blend, max_azimuth_speed, delta)
	var new_el := elevation + _follow_step(target_elevation - elevation, blend, max_elevation_speed, delta)
	if guard.is_valid() and not _safe(new_az, new_el) and _safe(azimuth, elevation):
		# Find the furthest safe angle between here and the refused step, then stop there.
		var lo := 0.0
		var hi := 1.0
		for _i in guard_search_steps:
			var mid := (lo + hi) * 0.5
			if _safe(lerpf(azimuth, new_az, mid), lerpf(elevation, new_el, mid)):
				lo = mid
			else:
				hi = mid
		azimuth = lerpf(azimuth, new_az, lo)
		elevation = lerpf(elevation, new_el, lo)
		target_azimuth = azimuth
		target_elevation = elevation
		_apply()
		set_physics_process(false)
		guard_blocked.emit()
		settled.emit()
		return
	azimuth = new_az
	elevation = new_el
	if absf(target_azimuth - azimuth) < settle_threshold and absf(target_elevation - elevation) < settle_threshold:
		azimuth = target_azimuth
		elevation = target_elevation
		set_physics_process(false)   # PDF §4: at rest — stop ticking
		_apply()
		settled.emit()
		return
	_apply()

func _safe(az: float, el: float) -> bool:
	return guard.call(direction_from_angles(az, el))

## Smoothed step toward the target: exponential ease, never slower than
## min_follow_speed (no lingering tail), never faster than max_speed, never overshooting.
func _follow_step(diff: float, blend: float, max_speed: float, delta: float) -> float:
	var mag := clampf(maxf(absf(diff) * blend, min_follow_speed * delta), 0.0, minf(absf(diff), max_speed * delta))
	return signf(diff) * mag

func _apply() -> void:
	if light:
		light.global_basis = Basis.looking_at(-get_toward_sun(), Vector3.UP)
		light.light_color = sun_color
		light.light_energy = sun_energy
	sun_moved.emit(azimuth, elevation)
