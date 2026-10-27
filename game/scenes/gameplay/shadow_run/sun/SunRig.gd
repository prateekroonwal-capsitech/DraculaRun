class_name SunRig
extends Node3D

## SunRig — owns the DirectionalLight3D and the sun's angular state.
## Azimuth sweeps the sun across the road (negative = left / −X, positive = right / +X,
## 0 = straight ahead down −Z). Elevation sets shadow length. The SunControl UI only
## sets a *target*; the rig moves toward it with a capped, smoothed angular speed so
## moving the sun is a deliberate skill rather than instant.
## PDF §4 CPU: the physics tick is disabled whenever the sun is at rest on its target.

## Emitted whenever the live (not target) angles change.
signal sun_moved(azimuth_deg: float, elevation_deg: float)

@export_group("Limits")
@export var azimuth_min: float = -70.0
@export var azimuth_max: float = 70.0
## Low clamp keeps shadows from swallowing the whole road.
@export var elevation_min: float = 18.0
@export var elevation_max: float = 60.0

@export_group("Motion")
## Hard cap on angular speed, degrees per second. Keep SegmentValidator's
## max_azimuth_speed / max_elevation_speed (segment_validator.tres) in sync.
@export var max_azimuth_speed: float = 135.0
@export var max_elevation_speed: float = 135.0
## Exponential smoothing toward the target (1/s). Higher = snappier (lag ≈ 1/smoothing s).
@export var smoothing: float = 13.0
## Minimum catch-up speed (°/s) so the exponential tail never crawls after the finger stops.
@export var min_follow_speed: float = 40.0
## Within this many degrees of the target the sun snaps onto it and stops ticking.
@export var settle_threshold: float = 0.25

@export_group("Start")
@export var start_azimuth: float = 35.0
@export var start_elevation: float = 38.0

@export_group("Look")
@export var light: DirectionalLight3D
@export var world_environment: WorldEnvironment
@export var sun_color: Color = Color(1.0, 0.8, 0.45)
@export var low_sun_horizon: Color = Color(1.0, 0.55, 0.22)
@export var high_sun_horizon: Color = Color(0.98, 0.82, 0.55)
@export var low_sun_ambient: Color = Color(0.32, 0.3, 0.62)
@export var high_sun_ambient: Color = Color(0.38, 0.4, 0.7)

var azimuth: float = 0.0
var elevation: float = 45.0
var target_azimuth: float = 0.0
var target_elevation: float = 45.0

var _sky: ProceduralSkyMaterial

func _ready() -> void:
	# Update the light before anything that queries it this physics frame (ShadowSensor).
	process_physics_priority = -10
	if world_environment and world_environment.environment and world_environment.environment.sky:
		_sky = world_environment.environment.sky.sky_material as ProceduralSkyMaterial
	snap_to(start_azimuth, start_elevation)

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

## Teleport (no rate limit). Used at run start, by tests and by the segment validator.
func snap_to(azimuth_deg: float, elevation_deg: float) -> void:
	target_azimuth = clampf(azimuth_deg, azimuth_min, azimuth_max)
	target_elevation = clampf(elevation_deg, elevation_min, elevation_max)
	azimuth = target_azimuth
	elevation = target_elevation
	_apply()
	set_physics_process(false)

func is_settled() -> bool:
	return is_equal_approx(azimuth, target_azimuth) and is_equal_approx(elevation, target_elevation)

func _physics_process(delta: float) -> void:
	var blend := 1.0 - exp(-smoothing * delta)
	azimuth += _follow_step(target_azimuth - azimuth, blend, max_azimuth_speed, delta)
	elevation += _follow_step(target_elevation - elevation, blend, max_elevation_speed, delta)
	if absf(target_azimuth - azimuth) < settle_threshold and absf(target_elevation - elevation) < settle_threshold:
		azimuth = target_azimuth
		elevation = target_elevation
		set_physics_process(false)   # PDF §4: at rest — stop ticking
	_apply()

## Smoothed step toward the target: exponential ease, never slower than
## min_follow_speed (no lingering tail), never faster than max_speed, never overshooting.
func _follow_step(diff: float, blend: float, max_speed: float, delta: float) -> float:
	var mag := clampf(maxf(absf(diff) * blend, min_follow_speed * delta), 0.0, minf(absf(diff), max_speed * delta))
	return signf(diff) * mag

func _apply() -> void:
	if light:
		light.global_basis = Basis.looking_at(-get_toward_sun(), Vector3.UP)
		light.light_color = sun_color
		# Slightly weaker light near the horizon; still strong enough to read as "danger".
		light.light_energy = lerpf(1.35, 1.75, _elevation_t())
	_apply_tint()
	sun_moved.emit(azimuth, elevation)

func _elevation_t() -> float:
	return inverse_lerp(elevation_min, elevation_max, elevation)

func _apply_tint() -> void:
	var t := _elevation_t()
	if _sky:
		_sky.sky_horizon_color = low_sun_horizon.lerp(high_sun_horizon, t)
		_sky.ground_horizon_color = low_sun_horizon.lerp(high_sun_horizon, t).darkened(0.35)
	if world_environment and world_environment.environment:
		# Shade is lit only by ambient: keep it cool blue-violet so it contrasts the golden sun.
		var env := world_environment.environment
		env.ambient_light_color = low_sun_ambient.lerp(high_sun_ambient, t)
		# Side sun reads a touch warmer overall.
		env.ambient_light_color = env.ambient_light_color.lerp(Color(0.45, 0.35, 0.55), absf(azimuth) / 140.0)
